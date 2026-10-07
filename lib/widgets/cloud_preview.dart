import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'brass_glyph.dart';

/// On a preview profile ([RunnerProfile.isPreview]) says "This is a preview —
/// nothing here is saved." and returns true, so the caller stops before
/// attempting the write; otherwise returns false and does nothing.
bool refuseInPreview(BuildContext context, RunnerProfile profile) {
  if (!profile.isPreview) return false;
  showBookplateNotice(context, PreviewModeException.message);
  return true;
}

/// The slim brass strip across the top of the Cloud preview: what this is,
/// and the way back out.
class CloudPreviewBanner extends StatelessWidget {
  const CloudPreviewBanner({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 2),
        decoration: BoxDecoration(
          color: AppColors.antiqueBrass.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
        ),
        child: Row(
          children: [
            const BrassGlyph(BrassGlyphKind.eye, size: 18, color: AppColors.antiqueBrass),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Preview · sample data for a church of 300',
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.forestGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            BookplateButton(
              label: 'Exit preview',
              compact: true,
              variant: BookplateButtonVariant.link,
              onPressed: onExit,
            ),
          ],
        ),
      ),
    );
  }
}
