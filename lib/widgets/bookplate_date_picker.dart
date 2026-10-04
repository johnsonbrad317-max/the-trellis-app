import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'brass_glyph.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Picks a calendar day on a parchment bookplate — a month header with brass
/// chevrons, weekday letters, and a grid of tappable days — in place of
/// the stock Material date dialog. Days outside [firstDate]..[lastDate] (compared
/// by calendar day, so today is selectable when [firstDate] is "now") are
/// faded and inert. Resolves to the chosen day at midnight, or null if the
/// dialog is cancelled or dismissed.
Future<DateTime?> showBookplateDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Choose a Date',
}) {
  final first = _dateOnly(firstDate);
  final last = _dateOnly(lastDate);
  var selected = _dateOnly(initialDate);
  if (selected.isBefore(first)) selected = first;
  if (selected.isAfter(last)) selected = last;
  var visibleMonth = DateTime(selected.year, selected.month);
  final today = _dateOnly(DateTime.now());

  return showBookplateForm<DateTime>(
    context,
    title: title,
    bodyBuilder: (dialogContext, setState) {
      final textTheme = Theme.of(dialogContext).textTheme;

      final previousMonth = DateTime(visibleMonth.year, visibleMonth.month - 1);
      final nextMonth = DateTime(visibleMonth.year, visibleMonth.month + 1);
      // A month can be visited if any of its days falls inside the range.
      final canGoBack = !DateTime(visibleMonth.year, visibleMonth.month, 0).isBefore(first);
      final canGoForward = !nextMonth.isAfter(last);

      final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
      // DateTime.weekday: Monday = 1 … Sunday = 7; the grid starts on Sunday.
      final leadingBlanks = DateTime(visibleMonth.year, visibleMonth.month, 1).weekday % 7;
      final cellCount = leadingBlanks + daysInMonth;
      final rowCount = (cellCount / 7).ceil();

      Widget dayCell(int? day) {
        if (day == null) return const SizedBox(height: 44);

        final date = DateTime(visibleMonth.year, visibleMonth.month, day);
        final inRange = !date.isBefore(first) && !date.isAfter(last);
        final isSelected = date == selected;
        final isToday = date == today;

        return Semantics(
          button: true,
          enabled: inRange,
          selected: isSelected,
          label: '${_monthNames[date.month - 1]} $day, ${date.year}',
          onTap: inRange ? () => setState(() => selected = date) : null,
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('bookplate-day-${date.year}-${date.month}-$day'),
            behavior: HitTestBehavior.opaque,
            onTap: inRange ? () => setState(() => selected = date) : null,
            child: SizedBox(
              height: 44,
              child: Center(
                child: Opacity(
                  opacity: inRange ? 1 : 0.3,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.forestGreen : Colors.transparent,
                      shape: BoxShape.circle,
                      border: isToday
                          ? Border.all(color: AppColors.antiqueBrass, width: 1.6)
                          : null,
                    ),
                    // Scales down (never wraps "30" onto two lines) when the
                    // cell is narrow or the text size is set very large.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$day',
                        maxLines: 1,
                        style: textTheme.bodyLarge?.copyWith(
                          color: isSelected ? AppColors.parchmentLight : AppColors.forestGreen,
                          fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BrassGlyphButton(
                kind: BrassGlyphKind.back,
                semanticLabel: 'Previous month',
                onPressed: canGoBack ? () => setState(() => visibleMonth = previousMonth) : null,
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${_monthNames[visibleMonth.month - 1]} ${visibleMonth.year}',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge,
                  ),
                ),
              ),
              BrassGlyphButton(
                kind: BrassGlyphKind.forward,
                semanticLabel: 'Next month',
                onPressed: canGoForward ? () => setState(() => visibleMonth = nextMonth) : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final letter in _weekdayLetters)
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      letter,
                      textAlign: TextAlign.center,
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.antiqueBrass,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Container(height: 1, color: AppColors.vellumBorder),
          const SizedBox(height: 4),
          for (var row = 0; row < rowCount; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: dayCell(() {
                      final day = row * 7 + col - leadingBlanks + 1;
                      return day >= 1 && day <= daysInMonth ? day : null;
                    }()),
                  ),
              ],
            ),
        ],
      );
    },
    actionsBuilder: (dialogContext, setState) => [
      BookplateButton(
        label: 'Set',
        onPressed: () => Navigator.of(dialogContext).pop(selected),
      ),
      BookplateButton(
        label: 'Cancel',
        variant: BookplateButtonVariant.secondary,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );
}
