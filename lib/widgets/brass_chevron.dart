import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A small hand-drawn chevron in forest green that turns from pointing down
/// (closed) to pointing up (open) — the woodcut stand-in for Material's
/// expand/collapse arrow icons.
class BrassChevron extends StatelessWidget {
  const BrassChevron({
    super.key,
    required this.open,
    this.size = 14,
    this.color = AppColors.forestGreen,
  });

  final bool open;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedRotation(
        turns: open ? 0.5 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: CustomPaint(
          size: Size(size, size * 0.6),
          painter: _ChevronPainter(color),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.14).clamp(1.4, 3.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.04, size.height * 0.1)
        ..lineTo(size.width / 2, size.height * 0.9)
        ..lineTo(size.width * 0.96, size.height * 0.1),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}
