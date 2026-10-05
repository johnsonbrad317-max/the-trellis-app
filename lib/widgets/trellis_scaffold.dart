import 'package:flutter/material.dart';

import 'vine_frame.dart';

/// The scaffold for every pushed screen: parchment, corner vines and a header
/// that slides away on scroll (all from [VineFrame]), with the body always in
/// a scroll view so a focused text field can never cause a keyboard overflow.
///
/// The body scrolls the full height of the screen — under the header's soft
/// edge at the top, and over the bottom vines at the bottom — instead of being
/// boxed into a band between them. Padding at the end of the scroll lets the
/// last line come to rest above the bottom vines.
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
    // Read here, above the Scaffold: inside its body the keyboard inset has
    // already been taken out of the MediaQuery.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      floatingActionButton: floatingActionButton,
      resizeToAvoidBottomInset: true,
      body: VineFrame(
        header: appBar,
        keyboardOpen: keyboardOpen,
        child: Builder(
          builder: (context) => SingleChildScrollView(
            padding: padding.add(
              EdgeInsets.only(
                bottom: VineFrame.bottomRestInset(context, keyboardOpen: keyboardOpen) +
                    MediaQuery.paddingOf(context).bottom,
              ),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
