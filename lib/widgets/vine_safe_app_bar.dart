import 'package:flutter/material.dart';

/// Sizes shared by every header in the app (BookplateAppBar and the three
/// shells' bars). Where the header sits, and how it slides away on scroll, is
/// VineFrame's job.
class VineSafeAppBar {
  const VineSafeAppBar._();

  /// The toolbar's height (the stock Material bar is 56). 44 still holds a
  /// 44px tap target while giving the screen back its room.
  static const double toolbarHeight = 44;
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
