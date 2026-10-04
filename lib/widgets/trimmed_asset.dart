import 'package:flutter/material.dart';

/// An [Image.asset] shown cropped to the opaque region of a transparent PNG.
///
/// The supplied artwork is exported on large transparent canvases with the
/// actual illustration sitting somewhere inside (e.g. a cabin in the lower
/// right of a 2816x1536 sheet), so fitting the whole canvas into a frame
/// leaves the art tiny. [content] is that illustration's bounding box in
/// source pixels; only it is scaled into the frame, per [fit]. The asset
/// files themselves are left untouched.
class TrimmedAsset extends StatelessWidget {
  const TrimmedAsset({
    super.key,
    required this.asset,
    required this.imageSize,
    required this.content,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.cacheWidth,
  });

  final String asset;

  /// Pixel size of the source PNG.
  final Size imageSize;

  /// Bounding box of the opaque artwork, in source pixels.
  final Rect content;

  /// Frame size. With only one given, the other follows the artwork's aspect
  /// ratio; with neither, the frame fills whatever its parent allows.
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  /// Decode the source at this width instead of full size (the sheets are
  /// up to 2816px wide).
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final fracW = content.width / imageSize.width;
    final fracH = content.height / imageSize.height;
    final contentAspect = content.width / content.height;

    final frameWidth = width ?? (height != null ? height! * contentAspect : null);
    final frameHeight = height ?? (width != null ? width! / contentAspect : null);

    // Align places the (larger) sheet so that [content] lands in the
    // (smaller) widthFactor/heightFactor window.
    final alignX = fracW >= 1 ? 0.0 : 2 * (content.left / imageSize.width) / (1 - fracW) - 1;
    final alignY = fracH >= 1 ? 0.0 : 2 * (content.top / imageSize.height) / (1 - fracH) - 1;

    const sheetHeight = 100.0;
    final sheetWidth = sheetHeight * imageSize.width / imageSize.height;

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: FittedBox(
        fit: fit,
        alignment: alignment,
        clipBehavior: Clip.hardEdge,
        child: ClipRect(
          child: Align(
            alignment: Alignment(alignX, alignY),
            widthFactor: fracW,
            heightFactor: fracH,
            child: SizedBox(
              width: sheetWidth,
              height: sheetHeight,
              child: Image.asset(
                asset,
                fit: BoxFit.fill,
                cacheWidth: cacheWidth,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
