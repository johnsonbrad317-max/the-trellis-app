import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A small hand-drawn padlock — brass body, brass shackle, a parchment
/// keyhole — marking something the Runner can see but not change (a church's
/// mandated DNA Rhythm). Painted rather than a Material `Icons.lock*` glyph.
class BrassLock extends StatelessWidget {
  const BrassLock({super.key, this.size = 16, this.color = AppColors.antiqueBrass});

  /// Height of the padlock; its width is 80% of this.
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size * 0.8,
        height: size,
        child: CustomPaint(painter: _BrassLockPainter(color)),
      ),
    );
  }
}

class _BrassLockPainter extends CustomPainter {
  const _BrassLockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (w * 0.14).clamp(1.2, 3.0);

    // Shackle: an upright arch rising from the top of the body.
    final shackle = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final shackleRect = Rect.fromLTRB(w * 0.2, stroke / 2, w * 0.8, h * 0.75);
    canvas.drawArc(shackleRect, 3.14159, 3.14159, false, shackle);
    canvas.drawLine(Offset(w * 0.2, h * 0.38), Offset(w * 0.2, h * 0.5), shackle);
    canvas.drawLine(Offset(w * 0.8, h * 0.38), Offset(w * 0.8, h * 0.5), shackle);

    // Body.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(0, h * 0.46, w, h),
      Radius.circular(w * 0.18),
    );
    canvas.drawRRect(body, Paint()..color = color);

    // Keyhole.
    final keyhole = Paint()..color = AppColors.parchmentLight;
    final cx = w / 2;
    canvas.drawCircle(Offset(cx, h * 0.68), w * 0.11, keyhole);
    canvas.drawRect(
      Rect.fromLTRB(cx - w * 0.04, h * 0.68, cx + w * 0.04, h * 0.86),
      keyhole,
    );
  }

  @override
  bool shouldRepaint(_BrassLockPainter oldDelegate) => oldDelegate.color != color;
}
