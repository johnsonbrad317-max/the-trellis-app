import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The parchment plate everything card-like is cut from — the woodcut
/// replacement for Material's `Card`: vellum fill, an antique-brass hairline,
/// a soft diffused shadow. Optionally tappable, optionally marked with an
/// [accent] stripe down its left edge, optionally [emphasized] (a heavier
/// brass border, for something that deserves to stand out).
class BookplatePlate extends StatelessWidget {
  const BookplatePlate({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.accent,
    this.emphasized = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: double.infinity,
      padding: padding,
      decoration: accent == null
          ? null
          : BoxDecoration(border: Border(left: BorderSide(color: accent!, width: 3))),
      child: child,
    );

    final plate = Container(
      decoration: BoxDecoration(
        color: AppColors.vellum,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.antiqueBrass.withValues(alpha: emphasized ? 1 : 0.5),
          width: emphasized ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: accent == null ? Clip.none : Clip.antiAlias,
      child: body,
    );

    if (onTap == null) return plate;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: plate);
  }
}

/// One line of a list — leading mark, title, optional subtitle, trailing
/// widget — the woodcut replacement for `ListTile`. Tappable when [onTap] is
/// given (no ripple: it simply acts).
class BookplateRow extends StatelessWidget {
  const BookplateRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
    this.titleStyle,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final row = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle ?? textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: row),
    );
  }
}

/// A hairline rule in faded brass — the woodcut replacement for `Divider`.
class BookplateDivider extends StatelessWidget {
  const BookplateDivider({super.key, this.indent = 0, this.height = 1});

  final double indent;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Container(height: 1, margin: EdgeInsets.symmetric(vertical: (height - 1) / 2), color: AppColors.vellumBorder),
    );
  }
}

/// A square brass-bordered box that fills forest green with a brass tick —
/// the woodcut replacement for `Checkbox`. A null [onChanged] locks it.
class BookplateCheckbox extends StatelessWidget {
  const BookplateCheckbox({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      checked: value,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? AppColors.forestGreen : AppColors.vellum,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.antiqueBrass, width: 1.5),
                ),
                child: value
                    ? CustomPaint(painter: _TickPainter())
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.22, size.height * 0.52)
        ..lineTo(size.width * 0.43, size.height * 0.72)
        ..lineTo(size.width * 0.78, size.height * 0.30),
      Paint()
        ..color = AppColors.antiqueBrass
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) => false;
}

/// A [BookplateCheckbox] with its label beside it — the replacement for
/// `CheckboxListTile`. Tapping the label toggles it too.
class BookplateCheckboxRow extends StatelessWidget {
  const BookplateCheckboxRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookplateCheckbox(value: value, onChanged: onChanged),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(padding: const EdgeInsets.only(top: 12), child: label),
          ),
        ],
      ),
    );
  }
}

/// A turning brass arc — the woodcut replacement for
/// `CircularProgressIndicator`. Indeterminate only.
class BookplateSpinner extends StatefulWidget {
  const BookplateSpinner({
    super.key,
    this.size = 22,
    this.color = AppColors.antiqueBrass,
    this.semanticLabel = 'Loading',
  });

  final double size;
  final Color color;
  final String semanticLabel;

  @override
  State<BookplateSpinner> createState() => _BookplateSpinnerState();
}

class _BookplateSpinnerState extends State<BookplateSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: RotationTransition(
          turns: _controller,
          child: CustomPaint(painter: _ArcPainter(widget.color)),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.13;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 1.1,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => oldDelegate.color != color;
}
