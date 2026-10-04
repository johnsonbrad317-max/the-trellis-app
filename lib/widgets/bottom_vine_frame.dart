import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'corner_vine_background.dart';

/// Wraps a bottom navigation bar so the two bottom corner vines frame the
/// bar itself instead of sitting over page content.
///
/// The bar paints NO background of its own — the screen's parchment gradient
/// runs straight on underneath it (shells set `Scaffold.extendBody: true`), so
/// the footer reads as part of the page rather than a separate block. A single
/// engraved brass hairline, running between the vines, marks where the page
/// ends and the navigation begins. The bar's items are inset by [sideInset] so
/// they land in the negative space between the vines, mirroring what
/// VineSafeAppBar does for the top toolbar.
class BottomVineFrame extends StatelessWidget {
  const BottomVineFrame({super.key, required this.child});

  /// A [BottomNavigationBar] with a transparent background.
  final Widget child;

  static const double vineHeight = 76;
  static const double sideInset = 64;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: sideInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The engraved rule: a brass line with a fainter one beneath.
              Container(height: 1, color: AppColors.antiqueBrass.withValues(alpha: 0.55)),
              const SizedBox(height: 2),
              Container(height: 1, color: AppColors.antiqueBrass.withValues(alpha: 0.2)),
              child,
            ],
          ),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          child: IgnorePointer(child: VineArt.sized(VineArt.bottomLeft, vineHeight)),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: IgnorePointer(child: VineArt.sized(VineArt.bottomRight, vineHeight)),
        ),
      ],
    );
  }
}
