import 'package:flutter/material.dart';

/// Wraps an [AppBar] so its toolbar sits in the negative space between the
/// corner vines instead of on top of them.
///
/// The vines hug the screen corners with arms running ~30px along the top
/// edge and ~30px down each side, so the toolbar is pushed [topInset] down
/// and in from each edge — [desktopSideInset] on wide screens, but only
/// [phoneSideInset] on phones, where every pixel of width is needed to keep
/// titles and actions from crowding. The wrapper's [preferredSize] grows by
/// [topInset] so the Scaffold still reserves the right amount of room; the
/// wrapped AppBar keeps handling the status-bar inset itself.
class VineSafeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const VineSafeAppBar({super.key, required this.child});

  final PreferredSizeWidget child;

  /// How far the toolbar sits below the top edge so it clears the corner
  /// vines' horizontal arms (they reach ~20px down the top edge at the app's
  /// vine size). Tuned down from 30 so the header band is slimmer.
  static const double topInset = 20;

  /// The toolbar's own height (the stock Material bar is 56). 44 still holds
  /// a 44px tap target while giving the screen back its room — every app bar
  /// in the app (BookplateAppBar and the three shells) uses this one value.
  static const double toolbarHeight = 44;
  static const double desktopSideInset = 30;
  static const double phoneSideInset = 12;
  static const double phoneBreakpoint = 600;

  @override
  Size get preferredSize => Size.fromHeight(child.preferredSize.height + topInset);

  @override
  Widget build(BuildContext context) {
    final sideInset =
        MediaQuery.sizeOf(context).width < phoneBreakpoint ? phoneSideInset : desktopSideInset;

    return Padding(
      padding: EdgeInsets.fromLTRB(sideInset, topInset, sideInset, 0),
      child: child,
    );
  }
}

/// An [AppBar] title that shrinks to fit rather than truncating with an
/// ellipsis, so a long title (e.g. a church name or "Walking with …") stays
/// fully readable on a narrow screen.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text, maxLines: 1),
    );
  }
}
