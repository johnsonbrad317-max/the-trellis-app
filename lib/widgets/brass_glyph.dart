import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Every mark the app draws where Material would have used an `Icon`. Each is
/// painted by hand as a few engraved strokes on a 24x24 grid — no icon font,
/// no `Icons.*` anywhere.
enum BrassGlyphKind {
  // Direction & action
  back,
  forward,
  up,
  down,
  close,
  check,
  checkCircle,
  plus,
  more,
  search,
  undo,
  copy,
  pencil,
  trash,
  logout,
  trendUp,
  // Status
  exclamation,
  info,
  lock,
  unlock,
  // Things & places
  calendar,
  clock,
  pin,
  bubble,
  envelope,
  bell,
  gear,
  briefcase,
  // People
  person,
  personAdd,
  people,
  // Emblems
  heart,
  leaf,
  cross,
  eye,
  mountain,
  cloud,
}

/// A hand-drawn glyph, in [color] (forest green by default) at [size] square.
class BrassGlyph extends StatelessWidget {
  const BrassGlyph(
    this.kind, {
    super.key,
    this.size = 22,
    this.color = AppColors.forestGreen,
    this.semanticLabel,
  });

  final BrassGlyphKind kind;
  final double size;
  final Color color;

  /// Spoken by screen readers; null marks the glyph decorative.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final painted = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GlyphPainter(kind, color)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: painted);
    return Semantics(label: semanticLabel, image: true, child: painted);
  }
}

/// A tappable [BrassGlyph] with a 44x44 hit area — the woodcut replacement for
/// `IconButton`. A null [onPressed] dims it and makes it inert.
class BrassGlyphButton extends StatelessWidget {
  const BrassGlyphButton({
    super.key,
    required this.kind,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 22,
    this.color = AppColors.forestGreen,
  });

  final BrassGlyphKind kind;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      // Declared here because excludeSemantics drops the GestureDetector's
      // own tap action — a screen reader needs it to press the button.
      onTap: onPressed,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: BrassGlyph(kind, size: size, color: color)),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind, this.color);

  final BrassGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    void stroke(Path path) => canvas.drawPath(path, line);
    void poly(List<double> xy, {bool close = false}) {
      final path = Path()..moveTo(xy[0], xy[1]);
      for (var i = 2; i < xy.length; i += 2) {
        path.lineTo(xy[i], xy[i + 1]);
      }
      if (close) path.close();
      stroke(path);
    }

    void ring(double x, double y, double r) => canvas.drawCircle(Offset(x, y), r, line);
    void dot(double x, double y, double r) => canvas.drawCircle(Offset(x, y), r, fill);
    void box(double l, double t, double r, double b, double radius, {bool filled = false}) {
      final rect = RRect.fromLTRBR(l, t, r, b, Radius.circular(radius));
      canvas.drawRRect(rect, filled ? fill : line);
    }

    void personAt(double cx, double headY, double headR, double bodyTop, double halfWidth) {
      ring(cx, headY, headR);
      stroke(Path()
        ..moveTo(cx - halfWidth, 20)
        ..cubicTo(cx - halfWidth, bodyTop + 1.5, cx - halfWidth * 0.55, bodyTop, cx, bodyTop)
        ..cubicTo(cx + halfWidth * 0.55, bodyTop, cx + halfWidth, bodyTop + 1.5, cx + halfWidth, 20));
    }

    switch (kind) {
      case BrassGlyphKind.back:
        poly([15, 5, 8, 12, 15, 19]);
      case BrassGlyphKind.forward:
        poly([9, 5, 16, 12, 9, 19]);
      case BrassGlyphKind.up:
        poly([5, 15, 12, 8, 19, 15]);
      case BrassGlyphKind.down:
        poly([5, 9, 12, 16, 19, 9]);
      case BrassGlyphKind.close:
        poly([6, 6, 18, 18]);
        poly([18, 6, 6, 18]);
      case BrassGlyphKind.check:
        poly([5, 12.5, 10, 17.5, 19, 7]);
      case BrassGlyphKind.checkCircle:
        ring(12, 12, 9);
        poly([7.5, 12.5, 10.8, 15.8, 16.5, 9]);
      case BrassGlyphKind.plus:
        poly([12, 5, 12, 19]);
        poly([5, 12, 19, 12]);
      case BrassGlyphKind.more:
        dot(12, 5, 1.7);
        dot(12, 12, 1.7);
        dot(12, 19, 1.7);
      case BrassGlyphKind.search:
        ring(10.5, 10.5, 6);
        poly([15, 15, 20, 20]);
      case BrassGlyphKind.undo:
        poly([9, 6, 4, 11, 9, 16]);
        stroke(Path()
          ..moveTo(4, 11)
          ..lineTo(15, 11)
          ..arcToPoint(const Offset(15, 21), radius: const Radius.circular(5))
          ..lineTo(11, 21));
      case BrassGlyphKind.copy:
        box(8, 8, 19, 19, 2);
        stroke(Path()
          ..moveTo(5, 15)
          ..lineTo(5, 6.5)
          ..arcToPoint(const Offset(6.5, 5), radius: const Radius.circular(1.5))
          ..lineTo(15, 5));
      case BrassGlyphKind.pencil:
        poly([5, 19, 6, 15, 16, 5, 19, 8, 9, 18], close: true);
        poly([14, 7, 17, 10]);
      case BrassGlyphKind.trash:
        poly([5, 7, 19, 7]);
        poly([10, 7, 10, 5, 14, 5, 14, 7]);
        poly([7, 7, 8, 20, 16, 20, 17, 7]);
        poly([10, 10, 10, 17]);
        poly([14, 10, 14, 17]);
      case BrassGlyphKind.logout:
        poly([10, 4, 5, 4, 5, 20, 10, 20]);
        poly([10, 12, 20, 12]);
        poly([16, 8, 20, 12, 16, 16]);
      case BrassGlyphKind.trendUp:
        poly([3, 17, 9, 11, 13, 15, 21, 7]);
        poly([15, 7, 21, 7, 21, 13]);
      case BrassGlyphKind.exclamation:
        poly([12, 5, 12, 14]);
        dot(12, 18.5, 1.5);
      case BrassGlyphKind.info:
        ring(12, 12, 9);
        dot(12, 7.6, 1.2);
        poly([12, 11, 12, 17]);
      case BrassGlyphKind.lock:
        box(5, 11, 19, 21, 2, filled: true);
        stroke(Path()
          ..moveTo(8, 11)
          ..lineTo(8, 8)
          ..arcToPoint(const Offset(16, 8), radius: const Radius.circular(4))
          ..lineTo(16, 11));
      case BrassGlyphKind.unlock:
        box(5, 11, 19, 21, 2, filled: true);
        stroke(Path()
          ..moveTo(8, 11)
          ..lineTo(8, 8)
          ..arcToPoint(const Offset(16, 8), radius: const Radius.circular(4))
          ..lineTo(16, 9));
      case BrassGlyphKind.calendar:
        box(4, 6, 20, 20, 2);
        poly([4, 10.5, 20, 10.5]);
        poly([8, 4, 8, 8]);
        poly([16, 4, 16, 8]);
      case BrassGlyphKind.clock:
        ring(12, 12, 9);
        poly([12, 7, 12, 12, 16, 14]);
      case BrassGlyphKind.pin:
        stroke(Path()
          ..moveTo(12, 21)
          ..cubicTo(6, 14, 5, 11.5, 5, 9)
          ..arcToPoint(const Offset(19, 9), radius: const Radius.circular(7))
          ..cubicTo(19, 11.5, 18, 14, 12, 21)
          ..close());
        ring(12, 9, 2.4);
      case BrassGlyphKind.bubble:
        box(4, 5, 20, 16, 3);
        poly([8.5, 16, 7, 20, 12.5, 16]);
      case BrassGlyphKind.envelope:
        box(3, 6, 21, 18, 2);
        poly([3.8, 7.5, 12, 13.5, 20.2, 7.5]);
      case BrassGlyphKind.bell:
        stroke(Path()
          ..moveTo(6, 17)
          ..lineTo(6, 11)
          ..arcToPoint(const Offset(18, 11), radius: const Radius.circular(6))
          ..lineTo(18, 17)
          ..lineTo(19.5, 18.5)
          ..lineTo(4.5, 18.5)
          ..close());
        stroke(Path()
          ..moveTo(10, 21)
          ..quadraticBezierTo(12, 22.6, 14, 21));
      case BrassGlyphKind.gear:
        ring(12, 12, 6);
        ring(12, 12, 2.4);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          poly([
            12 + math.cos(angle) * 6,
            12 + math.sin(angle) * 6,
            12 + math.cos(angle) * 9,
            12 + math.sin(angle) * 9,
          ]);
        }
      case BrassGlyphKind.briefcase:
        box(4, 8, 20, 19, 2);
        poly([9, 8, 9, 6, 15, 6, 15, 8]);
        poly([4, 13, 20, 13]);
      case BrassGlyphKind.person:
        personAt(12, 8, 3.6, 13.5, 7);
      case BrassGlyphKind.personAdd:
        personAt(9.5, 8, 3.3, 13.5, 6);
        poly([18, 7, 18, 13]);
        poly([15, 10, 21, 10]);
      case BrassGlyphKind.people:
        personAt(9, 8.5, 3, 14, 6);
        ring(16.8, 9.5, 2.5);
        stroke(Path()
          ..moveTo(16, 14)
          ..cubicTo(19, 14, 21, 15.4, 21, 18.5));
      case BrassGlyphKind.heart:
        stroke(Path()
          ..moveTo(12, 20)
          ..cubicTo(4, 14, 3, 10.5, 3, 8.5)
          ..arcToPoint(const Offset(12, 7), radius: const Radius.circular(4.6))
          ..arcToPoint(const Offset(21, 8.5), radius: const Radius.circular(4.6))
          ..cubicTo(21, 10.5, 20, 14, 12, 20)
          ..close());
      case BrassGlyphKind.leaf:
        stroke(Path()
          ..moveTo(5, 19)
          ..cubicTo(5, 9, 10, 5, 19, 5)
          ..cubicTo(19, 14, 15, 19, 5, 19)
          ..close());
        poly([5, 19, 14, 10]);
      case BrassGlyphKind.cross:
        poly([12, 3, 12, 21]);
        poly([7, 8.5, 17, 8.5]);
      case BrassGlyphKind.eye:
        stroke(Path()
          ..moveTo(2, 12)
          ..cubicTo(5, 6.5, 19, 6.5, 22, 12)
          ..cubicTo(19, 17.5, 5, 17.5, 2, 12)
          ..close());
        ring(12, 12, 3);
      case BrassGlyphKind.mountain:
        poly([3, 19, 9, 9, 13, 15, 16, 11, 21, 19], close: true);
      case BrassGlyphKind.cloud:
        stroke(Path()
          ..moveTo(7, 18)
          ..lineTo(17, 18)
          ..arcToPoint(const Offset(17, 10), radius: const Radius.circular(4))
          ..arcToPoint(const Offset(5.5, 11.5), radius: const Radius.circular(6))
          ..arcToPoint(const Offset(7, 18), radius: const Radius.circular(3.3))
          ..close());
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
