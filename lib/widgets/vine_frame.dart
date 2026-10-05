import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'corner_vine_background.dart';

/// The frame every screen sits in: parchment, the corner vines, a slim header
/// that slides away while the page is being read, and the page itself in all
/// the room that is left.
///
/// How the top is laid out, and why:
///
///   * The top vines live in the band the status bar already takes (clock,
///     Dynamic Island) — space no page content could use anyway — rather than
///     in a band of their own beneath it.
///   * The header (a 44px toolbar) sits directly under that band. When the
///     reader scrolls down it slides away and the page takes its place;
///     scrolling back up — or reaching the top — brings it back. A page too
///     short to scroll never hides it.
///   * The page's top edge dissolves into the parchment over a few pixels, so
///     content passes "under" the header instead of being cut off by a line.
///
/// The bottom comes in two modes:
///
///   * [bottomVines] true — a pushed screen. The bottom corner vines are drawn
///     *beneath* the page, which runs to the very bottom of the screen; the
///     screen's own scroll view adds [bottomRestInset] of padding at its end so
///     the last line can rest above them. Nothing is reserved while scrolling.
///     With the keyboard up ([keyboardOpen]) the vines are not drawn at all:
///     riding on top of the keyboard they only took room from the form.
///   * [bottomVines] false — a shell with a bottom bar, which carries the vines
///     itself (BottomVineFrame). The page stops at the bar.
///
/// Place this as a Scaffold's `body`, with no `appBar` on the Scaffold.
class VineFrame extends StatefulWidget {
  const VineFrame({
    super.key,
    required this.child,
    this.header,
    this.bottomVines = true,
    this.keyboardOpen = false,
    this.headerResetToken,
  });

  /// The page. It receives a MediaQuery whose top padding has already been
  /// used up, so a nested SafeArea adds nothing extra at the top.
  final Widget child;

  /// The toolbar (an AppBar / BookplateAppBar). Null for screens without one.
  final PreferredSizeWidget? header;

  final bool bottomVines;

  /// Whether the on-screen keyboard is up. Read it from a context ABOVE the
  /// Scaffold (the Scaffold hides the keyboard inset from its own body).
  final bool keyboardOpen;

  /// When this changes (e.g. the shell's tab index) a hidden header comes back.
  final Object? headerResetToken;

  /// Below this width the screen is treated as a phone: smaller vines, tighter
  /// side insets.
  static const double phoneBreakpoint = 600;

  /// How tall the corner vines are drawn at this screen width.
  static double vineSizeFor(double screenWidth) => screenWidth < phoneBreakpoint ? 72 : 100;

  /// How far the toolbar may tuck up under the vines' lowest leaves.
  static const double _vineOverlap = 12;

  /// Breathing room between the header (or the top band) and the page.
  static const double gap = 6;

  /// Height of the soft edge where the page dissolves under the header.
  static const double _fade = 14;

  /// The header's side insets, so its buttons clear the vines' side arms.
  static double _sideInset(double screenWidth) => screenWidth < phoneBreakpoint ? 12 : 30;

  /// The band at the very top that holds the vines: the status bar's height,
  /// or — where there is no status bar to speak of (web, desktop, older
  /// phones) — just enough to hold the vines themselves.
  static double topBand(BuildContext context) {
    final media = MediaQuery.of(context);
    return math.max(media.padding.top, vineSizeFor(media.size.width) - _vineOverlap);
  }

  /// Padding a pushed screen's scroll view should add at its END so its last
  /// content can rest above the bottom vines (and the home indicator).
  static double bottomRestInset(BuildContext context, {required bool keyboardOpen}) {
    final media = MediaQuery.of(context);
    if (keyboardOpen) return 16;
    return vineSizeFor(media.size.width) + 8;
  }

  @override
  State<VineFrame> createState() => _VineFrameState();
}

class _VineFrameState extends State<VineFrame> {
  static const _slide = Duration(milliseconds: 200);

  bool _headerShown = true;

  /// Distance scrolled in the current direction since it last changed.
  double _travel = 0;

  @override
  void didUpdateWidget(VineFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.headerResetToken != widget.headerResetToken) {
      _headerShown = true;
      _travel = 0;
    }
  }

  void _setHeaderShown(bool shown) {
    if (_headerShown == shown) return;
    setState(() => _headerShown = shown);
  }

  bool _onScroll(ScrollNotification notification) {
    final header = widget.header;
    if (header == null) return false;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    // A text field scrolling its own lines is not the page being read.
    if (notification.context?.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    if (notification is! ScrollUpdateNotification) return false;
    // The rubber-band past either end must not flip the header back and forth.
    if (metrics.outOfRange) return false;

    if (metrics.pixels <= 0) {
      _travel = 0;
      _setHeaderShown(true);
      return false;
    }

    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;
    if (delta.sign != _travel.sign) _travel = 0;
    _travel += delta;

    final toolbar = header.preferredSize.height;
    // Hiding the header makes the page taller by the toolbar's height; only
    // hide when there is clearly more to read than that, or a barely-scrolling
    // page would hide the header, stop scrolling, show it, and repeat.
    if (_travel > 24 && metrics.maxScrollExtent > toolbar + 48) {
      _setHeaderShown(false);
    } else if (_travel < -12) {
      _setHeaderShown(true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final vine = VineFrame.vineSizeFor(width);
    final band = VineFrame.topBand(context);
    final header = widget.header;
    final toolbar = header?.preferredSize.height ?? 0;
    final headerShown = header != null && _headerShown;
    final pageTop = band + (headerShown ? toolbar : 0) + VineFrame.gap;
    final sideInset = VineFrame._sideInset(width);
    final showBottomVines = widget.bottomVines && !widget.keyboardOpen;

    return ColoredBox(
      color: AppColors.parchmentLight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Bottom vines first: on a pushed screen the page slides over them.
          if (showBottomVines) ...[
            Positioned(
              left: 0,
              bottom: 0,
              child: IgnorePointer(child: VineArt.sized(VineArt.bottomLeft, vine)),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: IgnorePointer(child: VineArt.sized(VineArt.bottomRight, vine)),
            ),
          ],

          // The page, in everything below the top band (and the header, while
          // it is showing).
          AnimatedPadding(
            duration: _slide,
            curve: Curves.easeOut,
            padding: EdgeInsets.only(top: pageTop),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: SafeArea(
                top: false,
                // A shell's page stops at its bottom bar; a pushed screen's
                // runs to the bottom edge (see the class comment).
                bottom: !widget.bottomVines,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: widget.child,
                    ),
                    // The soft top edge the page dissolves under.
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: VineFrame._fade,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [AppColors.parchmentLight, AppColors.parchmentClear],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Top vines, in the status-bar band.
          Positioned(
            top: 0,
            left: 0,
            child: IgnorePointer(child: VineArt.sized(VineArt.topLeft, vine)),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IgnorePointer(child: VineArt.sized(VineArt.topRight, vine)),
          ),

          // The header, above the vines so its buttons are never behind a leaf.
          if (header != null)
            Positioned(
              top: band,
              left: sideInset,
              right: sideInset,
              height: toolbar,
              child: IgnorePointer(
                ignoring: !headerShown,
                child: AnimatedSlide(
                  duration: _slide,
                  curve: Curves.easeOut,
                  offset: headerShown ? Offset.zero : const Offset(0, -0.5),
                  child: AnimatedOpacity(
                    duration: _slide,
                    opacity: headerShown ? 1 : 0,
                    // The bar must not add the status bar's height itself: the
                    // band above already accounts for it.
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: ExcludeSemantics(excluding: !headerShown, child: header),
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
