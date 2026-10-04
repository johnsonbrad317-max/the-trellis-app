import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'corner_vine_background.dart';
import 'vine_safe_app_bar.dart';

/// Shared scaffold applying the solid parchment background and corner vine
/// illustrations. The body is always wrapped in a [SingleChildScrollView] so
/// a focused text field never causes a keyboard overflow, per the app-wide
/// layout rule.
class TrellisScaffold extends StatelessWidget {
  const TrellisScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final vineSafeAppBar = appBar == null ? null : VineSafeAppBar(child: appBar!);

    return Scaffold(
      appBar: vineSafeAppBar,
      extendBodyBehindAppBar: true,
      floatingActionButton: floatingActionButton,
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.parchmentLight,
        child: CornerVineBackground(
          // extendBodyBehindAppBar lets the parchment + vines run behind a
          // transparent AppBar; VineSafeArea keeps the content in the space
          // between the corner vines (and clear of the AppBar) — counting the
          // app bar and status bar toward that clearance rather than stacking
          // a second inset beneath them.
          child: VineSafeArea(
            clearBottomVines: true,
            child: SingleChildScrollView(
              padding: padding,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
