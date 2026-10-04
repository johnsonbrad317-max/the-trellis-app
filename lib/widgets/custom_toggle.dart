import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A hand-built forest-green/antique-brass pill toggle, standing in for
/// Material's default [Switch] anywhere the app needs an on/off control
/// (Connect Calendar, Anchor Rhythm, …). A null [onChanged] renders it
/// locked: dimmed and non-interactive.
class CustomToggle extends StatelessWidget {
  const CustomToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What this toggle switches, for screen readers — pass it wherever the
  /// visible label is a separate widget beside the toggle. ([ToggleRow]
  /// merges its own title in instead.)
  final String? semanticLabel;

  static const _width = 52.0;
  static const _height = 30.0;
  static const _thumbSize = 24.0;

  /// The touch target's height; the pill is drawn [_height] tall inside it.
  static const _hitHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: GestureDetector(
          onTap: enabled ? () => onChanged!(!value) : null,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: _width,
            height: _hitHeight,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: _width,
                height: _height,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: value ? AppColors.forestGreen : AppColors.vellum,
                  borderRadius: BorderRadius.circular(_height / 2),
                  border: Border.all(
                    color: value
                        ? AppColors.forestGreen
                        : AppColors.antiqueBrass.withValues(alpha: 0.6),
                  ),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.antiqueBrass,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled row ending in a [CustomToggle] — the drop-in replacement for
/// Material's [SwitchListTile]. A null [onChanged] locks the toggle.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // MergeSemantics: a screen reader announces the title and the toggle's
    // on/off state as one control, not a stray unlabelled switch.
    return MergeSemantics(
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            CustomToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
