import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'brass_glyph.dart';
import 'vine_safe_app_bar.dart';

/// The app's top bar for a pushed screen: a hand-drawn back chevron (shown
/// automatically when there is somewhere to go back to), an EB Garamond title
/// that shrinks to fit, and any [actions]. Drop-in for `AppBar` inside
/// [TrellisScaffold] / [VineSafeAppBar]; it replaces the stock back arrow and
/// icon buttons with woodcut marks.
class BookplateAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BookplateAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions = const [],
    this.showBack,
    this.onBack,
  }) : assert(title == null || titleWidget == null, 'Pass either title or titleWidget.');

  final String? title;
  final Widget? titleWidget;

  /// Trailing widgets — use [BrassGlyphButton], not `IconButton`.
  final List<Widget> actions;

  /// Null shows the back chevron only when the navigator can pop.
  final bool? showBack;

  /// Overrides the default pop (e.g. to pop back to the first route).
  final VoidCallback? onBack;

  /// The bar's height — the app-wide slim toolbar.
  static const double height = VineSafeAppBar.toolbarHeight;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final back = showBack ?? Navigator.of(context).canPop();

    return AppBar(
      toolbarHeight: height,
      automaticallyImplyLeading: false,
      leading: back
          ? BrassGlyphButton(
              kind: BrassGlyphKind.back,
              semanticLabel: 'Back',
              color: AppColors.forestGreen,
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            )
          : null,
      title: titleWidget ?? (title == null ? null : AppBarTitle(title!)),
      actions: actions,
    );
  }
}
