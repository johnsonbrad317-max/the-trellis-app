import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bookplate_chip.dart';
import 'bookplate_dialog.dart';

/// Picks a time of day on a parchment bookplate — two scrolling wheels (hour,
/// minute) between brass rules, and AM/PM chips — in place of Material's
/// `showTimePicker`. Resolves to the chosen time, or null if dismissed.
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
            onSelectedItemChanged: (index) => setState(() => onChanged(index % count)),
            childDelegate: ListWheelChildLoopingListDelegate(
              children: [
                for (var i = 0; i < count; i++)
                  Center(
                    child: Text(
                      label(i),
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: i == selected ? FontWeight.w800 : FontWeight.w400,
                        color: AppColors.forestGreen.withValues(alpha: i == selected ? 1 : 0.45),
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
          child: SizedBox(
          height: 150,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The brass rules the chosen row sits between.
              IgnorePointer(
                child: Container(
                  height: 40,
                  decoration: const BoxDecoration(
                    border: Border.symmetric(
                      horizontal: BorderSide(color: AppColors.antiqueBrass, width: 1.2),
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
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BookplateChip(
                        label: 'AM',
                        selected: !isPm,
                        compact: true,
                        onTap: () => setState(() => isPm = false),
                      ),
                      const SizedBox(height: 8),
                      BookplateChip(
                        label: 'PM',
                        selected: isPm,
                        compact: true,
                        onTap: () => setState(() => isPm = true),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          ),
        );
      },
      actionsBuilder: (dialogContext, setState) => [
        BookplateButton(
          label: 'Set',
          onPressed: () {
            final hour24 = (hour12 % 12) + (isPm ? 12 : 0);
            Navigator.of(dialogContext).pop(TimeOfDay(hour: hour24, minute: minute));
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
