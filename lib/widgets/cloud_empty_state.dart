import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';

/// The Cloud's "nothing here yet" panel — a quiet engraved leaf, a heading,
/// and a line saying what will fill the space and how to begin. For an
/// ordinary empty church; never an error, and never red.
class CloudEmptyState extends StatelessWidget {
  const CloudEmptyState({
    super.key,
    this.title = 'No data yet',
    required this.message,
    this.glyph = BrassGlyphKind.leaf,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final BrassGlyphKind glyph;

  /// An optional first step ("Create a Church Code").
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BookplatePlate(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: BrassGlyph(
              glyph,
              size: 36,
              color: AppColors.antiqueBrass.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          Text(title, style: textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            message,
            style: textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: AppColors.forestGreen.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            BookplateButton(
              label: actionLabel!,
              variant: BookplateButtonVariant.secondary,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
