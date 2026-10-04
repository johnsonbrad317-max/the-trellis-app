import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'brass_chevron.dart';

/// The "Runner ▾" role-switcher control shared by all three navigation
/// shells' app bars.
///
/// Deliberately built from a plain [Row] — a row of explicit, unconstrained
/// children never clips regardless of label length under any AppBar/theme
/// constraint combination.
class RoleSwitcherButton extends StatelessWidget {
  const RoleSwitcherButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 420;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 4 : 12),
      child: Center(
        child: Semantics(
          button: true,
          label: 'Switch role, currently $label',
          onTap: onPressed,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onPressed,
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: narrow ? 10 : 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.vellum,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.vellumBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.forestGreen,
                              fontWeight: FontWeight.w600,
                            ),
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                      const SizedBox(width: 8),
                      const BrassChevron(open: false, size: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
