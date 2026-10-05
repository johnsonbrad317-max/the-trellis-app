import 'package:flutter/material.dart';

import 'trimmed_asset.dart';

/// Clearance from the bottom edge for things that float above every screen
/// (the notice banner): enough to sit above the bottom corner vines, or a
/// shell's bottom bar. Screens themselves are framed by VineFrame.
const double kVineSafeInset = 90;

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

