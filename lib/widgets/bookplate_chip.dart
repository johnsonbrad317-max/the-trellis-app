import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A selectable label built from a plain [Container] instead of Material's
/// [ChoiceChip]: parchment fill, 1px antique-brass border, serif type.
/// Selected chips take a forest-green border and a brass-tinted fill.
class BookplateChip extends StatelessWidget {
  const BookplateChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.compact = false,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// False renders the chip faded and inert — for a choice that is shown but
  /// can't be changed (e.g. the schedule of a church-mandated rhythm). The
  /// selected state still reads, so the current value stays visible.
  final bool enabled;

  /// Tighter padding and smaller type, for dense groups (weekday pickers,
  /// preset suggestions).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final chip = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 11, vertical: 5)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.antiqueBrass.withValues(alpha: 0.18)
              : AppColors.parchmentLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.forestGreen : AppColors.antiqueBrass,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: (compact ? textTheme.bodyMedium : textTheme.bodyLarge)?.copyWith(
            color: AppColors.forestGreen,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );

    // A purely informational chip (no handler at all) stays its drawn size;
    // a tappable one — even while disabled, so a row of chips keeps its
    // rhythm — gets a 44px touch target around the same drawn chip.
    if (onTap == null) {
      return Semantics(label: label, selected: selected, excludeSemantics: true, child: chip);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(widthFactor: 1, heightFactor: 1, child: chip),
        ),
      ),
    );
  }
}

/// A small read-only status tag (e.g. "Confirmed", "Pending") — the same
/// parchment/brass-border look as [BookplateChip], outlined in [color].
class BookplateTag extends StatelessWidget {
  const BookplateTag({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
