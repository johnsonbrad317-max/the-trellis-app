import 'package:flutter/material.dart';

import 'trimmed_asset.dart';

/// Vertical clearance, top and bottom, that scrolling content keeps from the
/// screen edges so it sits in the negative space between the corner vines
/// instead of underneath them. Must stay larger than the vines' height
/// ([CornerVineBackground.vineSize]) minus whatever padding the content
/// already has.
const double kVineSafeInset = 90;

/// Keeps a screen's content clear of the corner vines — and no further.
///
/// The vines are [CornerVineBackground.defaultVineSize] tall, measured from
/// the very top (and bottom) edge of the screen. Whatever already sits in that
/// band — the status bar, and the app bar when the Scaffold extends its body
/// behind it (the Scaffold reports both together as the body's top padding) —
/// counts toward clearing them. So this adds only the remainder:
///
///   * a phone with a status bar and the app's slim app bar: the bar already
///     reaches past the vines, so content starts [minGap] below it;
///   * no status bar (web, desktop) or no app bar: just enough extra to reach
///     the bottom of the vines.
///
/// (The fixed inset this replaces was added ON TOP of the app bar, leaving a
/// band of empty parchment under every header.)
///
/// Place it directly inside the Scaffold body, in place of `SafeArea`.
class VineSafeArea extends StatelessWidget {
  const VineSafeArea({super.key, required this.child, this.clearBottomVines = false});

  final Widget child;

  /// True on screens whose bottom corner vines sit over the body
  /// (TrellisScaffold). Shells hang those vines on the bottom bar instead, and
  /// the bar's own height already keeps content above them.
  final bool clearBottomVines;

  /// Breathing room between the vines (or the app bar) and the content.
  static const double minGap = 12;

  static double _remainder(double alreadyCovered) => (CornerVineBackground.defaultVineSize +
          minGap -
          alreadyCovered)
      .clamp(minGap, double.infinity);

  @override
  Widget build(BuildContext context) {
    // Inside a Scaffold body: top = status bar + app bar (when the body is
    // extended behind it); bottom = home indicator + bottom bar (extendBody).
    final covered = MediaQuery.paddingOf(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          top: _remainder(covered.top),
          bottom: clearBottomVines ? _remainder(covered.bottom) : 0,
        ),
        child: child,
      ),
    );
  }
}

/// The four corner vine illustrations — transparent PNGs with margins of
/// differing sizes, so each is described by the region holding its artwork
/// ([TrimmedAsset]) and drawn at whatever height the caller wants, flush to
/// its corner.
class VineArt {
  const VineArt._();

  static const topLeft = TrimmedAsset(
    asset: 'assets/images/vine_top_left.png',
    imageSize: Size(1024, 559),
    content: Rect.fromLTRB(50, 48, 654, 526),
    cacheWidth: 1024,
  );
  static const topRight = TrimmedAsset(
    asset: 'assets/images/vine_top_right.png',
    imageSize: Size(2816, 1536),
    content: Rect.fromLTRB(1018, 134, 2676, 1440),
    cacheWidth: 1400,
  );
  static const bottomLeft = TrimmedAsset(
    asset: 'assets/images/vine_bottom_left.png',
    imageSize: Size(1024, 559),
    content: Rect.fromLTRB(50, 48, 530, 526),
    cacheWidth: 1024,
  );
  static const bottomRight = TrimmedAsset(
    asset: 'assets/images/vine_bottom_right.png',
    imageSize: Size(1024, 559),
    content: Rect.fromLTRB(492, 48, 974, 526),
    cacheWidth: 1024,
  );

  /// [spec] drawn [height] tall (its width follows the artwork's aspect).
  static Widget sized(TrimmedAsset spec, double height) => TrimmedAsset(
        asset: spec.asset,
        imageSize: spec.imageSize,
        content: spec.content,
        cacheWidth: spec.cacheWidth,
        height: height,
      );
}

/// The app-wide background treatment: antique-brass vine illustrations
/// anchored to the screen corners, over the app's
/// [AppColors.parchmentLight] (set by whatever
/// [Container]/[Scaffold] wraps this). No repeating background pattern, and
/// no code-drawn artwork. Because the vines are the bottom-most children of
/// this [Stack] (painted first, before [child]), real screen content always
/// layers on top of them.
///
/// The bottom pair is optional: screens with a bottom navigation bar turn
/// [bottomVines] off and hang those two on the bar itself instead (see
/// BottomVineFrame), so they frame the bar rather than sitting on content.
class CornerVineBackground extends StatelessWidget {
  const CornerVineBackground({
    super.key,
    required this.child,
    this.vineSize = defaultVineSize,
    this.bottomVines = true,
  });

  /// How tall each corner vine is drawn. [VineSafeArea] clears exactly this.
  static const double defaultVineSize = 100;

  final Widget child;
  final double vineSize;
  final bool bottomVines;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          child: IgnorePointer(child: VineArt.sized(VineArt.topLeft, vineSize)),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IgnorePointer(child: VineArt.sized(VineArt.topRight, vineSize)),
        ),
        if (bottomVines) ...[
          Positioned(
            bottom: 0,
            left: 0,
            child: IgnorePointer(child: VineArt.sized(VineArt.bottomLeft, vineSize)),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: IgnorePointer(child: VineArt.sized(VineArt.bottomRight, vineSize)),
          ),
        ],
        child,
      ],
    );
  }
}
