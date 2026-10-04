import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A two-or-more-way tab toggle in the book's own idiom: no filled blocks,
/// just serif labels on the parchment. The active tab is bold with a 2px
/// antique-brass underline; inactive tabs are plain dark-green text.
/// Replaces Material's [SegmentedButton].
class BookplateTabs<T> extends StatelessWidget {
  const BookplateTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  /// Tab value -> label, in display order.
  final Map<T, String> tabs;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // IntrinsicHeight + stretch: when one label wraps to two lines and its
    // neighbour doesn't, every tab still ends on the same baseline rule.
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in tabs.entries)
          Expanded(
            child: Semantics(
              button: true,
              selected: entry.key == selected,
              label: entry.value,
              onTap: () => onChanged(entry.key),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(entry.key),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: entry.key == selected
                            ? AppColors.antiqueBrass
                            : AppColors.antiqueBrass.withValues(alpha: 0.25),
                        width: entry.key == selected ? 2 : 1,
                      ),
                    ),
                  ),
                  child: Text(
                    entry.value,
                    // A long label wraps on a narrow phone; keep both lines
                    // centred over the underline.
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.forestGreen,
                      fontWeight: entry.key == selected ? FontWeight.w800 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
      ),
    );
  }
}
