import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../theme/app_colors.dart';
import 'brass_glyph.dart';
import 'trimmed_asset.dart';

/// A vintage-bookplate-style role card: two nested [Container]s (each a
/// thin 1px antique-brass border, 4px apart) for the fine double-line
/// edging, a very soft diffused drop shadow so the card reads as a thick
/// physical card floating off the parchment background, and a real
/// [Image.asset] illustration above the title — no Material icons (the
/// selected mark is a hand-drawn [BrassGlyph]). Shared by the onboarding walkthrough carousel
/// (auth_onboarding_screen.dart — display-only, no [onTap]) and the actual
/// role-selection carousel (role_selection_screen.dart — [selected] drives
/// the highlight border + checkmark).
class OrnateRoleCard extends StatelessWidget {
  const OrnateRoleCard({super.key, required this.role, this.selected = false, this.onTap});

  final UserRole role;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final borderColor = selected ? AppColors.forestGreen : AppColors.antiqueBrass;

    // Outer container: 1px brass border, soft diffused shadow, 4px padding
    // before the inner border — the "nest two Containers" bookplate edging.
    final chrome = Container(
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
        // High blur radius, very low opacity, no spread — a soft diffused
        // shadow so the card reads as thick cardstock rather than a flat
        // Material surface with a hard-edged drop shadow.
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.10),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Inner container: a second 1px brass border.
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.6)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The art takes all the height the text below doesn't need,
                // scaled (contain) as large as the frame allows. The PNG is
                // transparent, so it sits straight on the parchment — cropped
                // to its opaque region first, since the canvas has wide
                // empty margins that would otherwise shrink it to a speck.
                Expanded(
                  child: TrimmedAsset(
                    asset: role.cardArtAsset,
                    imageSize: role.cardArtSize,
                    content: role.cardArtContent,
                    fit: BoxFit.contain,
                    cacheWidth: 1400,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  role.label.toUpperCase(),
                  style: textTheme.titleLarge?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  role.tagline,
                  style: textTheme.titleMedium?.copyWith(color: AppColors.antiqueBrass),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  role.description,
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (selected)
            const Positioned(
              top: -6,
              right: -6,
              child: BrassGlyph(
                BrassGlyphKind.checkCircle,
                size: 24,
                color: AppColors.antiqueBrass,
                semanticLabel: 'Selected',
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return chrome;

    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: chrome);
  }
}
