import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';

/// Picks a time of day on a parchment bookplate, in place of Material's
/// `showTimePicker`: the chosen time written out in full at the top, two
/// scrolling wheels (hour, minute) between brass rules, and a two-part AM/PM
/// switch beside them. Resolves to the chosen time, or null if dismissed.
///
/// The time is spelled out ("7:00 AM") and the selected half of the switch is
/// solid green on purpose: an earlier version tinted the chosen AM/PM chip so
/// faintly — and laid the chips over the brass rules — that people could not
/// tell which was set.
Future<TimeOfDay?> showBookplateTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
  String title = 'Choose a Time',
}) async {
  var hour12 = initialTime.hourOfPeriod == 0 ? 12 : initialTime.hourOfPeriod;
  var minute = initialTime.minute;
  var isPm = initialTime.period == DayPeriod.pm;

  final hourController = FixedExtentScrollController(initialItem: hour12 - 1);
  final minuteController = FixedExtentScrollController(initialItem: minute);

  try {
    return await showBookplateForm<TimeOfDay>(
      context,
      title: title,
      bodyBuilder: (dialogContext, setState) {
        final textTheme = Theme.of(dialogContext).textTheme;

        Widget wheel({
          required FixedExtentScrollController controller,
          required int count,
          required int selected,
          required String Function(int index) label,
          required ValueChanged<int> onChanged,
        }) {
          return ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 40,
            diameterRatio: 1.6,
            perspective: 0.003,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) =>
                setState(() => onChanged(index % count)),
            childDelegate: ListWheelChildLoopingListDelegate(
              children: [
                for (var i = 0; i < count; i++)
                  Center(
                    child: Text(
                      label(i),
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: i == selected
                            ? FontWeight.w800
                            : FontWeight.w400,
                        color: AppColors.forestGreen.withValues(
                          alpha: i == selected ? 1 : 0.45,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        // The wheels' rows are a fixed 40px, so very large accessibility text
        // is capped here rather than clipped mid-glyph by the row above/below.
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The answer, in words — what "Set" will save.
              Semantics(
                liveRegion: true,
                child: Text(
                  formatTimeOfDay(hour12: hour12, minute: minute, isPm: isPm),
                  key: const ValueKey('time-picker-readout'),
                  style: textTheme.headlineMedium?.copyWith(
                    color: AppColors.forestGreen,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: Row(
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // The brass rules the chosen row sits between — only
                          // as wide as the wheels themselves.
                          IgnorePointer(
                            child: Container(
                              height: 40,
                              decoration: const BoxDecoration(
                                border: Border.symmetric(
                                  horizontal: BorderSide(
                                    color: AppColors.antiqueBrass,
                                    width: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: wheel(
                                  controller: hourController,
                                  count: 12,
                                  selected: hour12 - 1,
                                  label: (i) => '${i + 1}',
                                  onChanged: (i) => hour12 = i + 1,
                                ),
                              ),
                              Text(':', style: textTheme.headlineSmall),
                              Expanded(
                                child: wheel(
                                  controller: minuteController,
                                  count: 60,
                                  selected: minute,
                                  label: (i) => i.toString().padLeft(2, '0'),
                                  onChanged: (i) => minute = i,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    _PeriodSwitch(
                      isPm: isPm,
                      onChanged: (value) => setState(() => isPm = value),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      actionsBuilder: (dialogContext, setState) => [
        BookplateButton(
          label: 'Set',
          onPressed: () {
            final hour24 = (hour12 % 12) + (isPm ? 12 : 0);
            Navigator.of(dialogContext)
                .pop(TimeOfDay(hour: hour24, minute: minute));
          },
        ),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.secondary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    );
  } finally {
    hourController.dispose();
    minuteController.dispose();
  }
}

/// "7:00 AM" from the picker's three parts.
@visibleForTesting
String formatTimeOfDay({
  required int hour12,
  required int minute,
  required bool isPm,
}) => '$hour12:${minute.toString().padLeft(2, '0')} ${isPm ? 'PM' : 'AM'}';

/// AM over PM, as one bordered block: the chosen half is solid forest green
/// with light lettering, the other plain parchment — unmistakable at a glance,
/// and distinguishable without relying on colour alone (weight changes too).
class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.isPm, required this.onChanged});

  final bool isPm;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget half({required String label, required bool pm}) {
      final selected = isPm == pm;
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: () => onChanged(pm),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(pm),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 64,
            height: 48,
            alignment: Alignment.center,
            color: selected ? AppColors.forestGreen : AppColors.parchmentLight,
            child: Text(
              label,
              style: textTheme.titleMedium?.copyWith(
                color: selected
                    ? AppColors.parchmentLight
                    : AppColors.forestGreen,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          half(label: 'AM', pm: false),
          Container(height: 1.2, width: 64, color: AppColors.antiqueBrass),
          half(label: 'PM', pm: true),
        ],
      ),
    );
  }
}
