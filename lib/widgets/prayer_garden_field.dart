import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'trimmed_asset.dart';

/// What the garden needs to know about one prayer — a plain value so the
/// Runner's [PrayerItem]s and the Witness's [WatchedPrayerItem]s can share
/// the same visual.
class GardenEntry {
  const GardenEntry({
    required this.title,
    this.details = '',
    this.scripture,
    this.answeredDate,
  });

  final String title;
  final String details;
  final String? scripture;
  final DateTime? answeredDate;
}

const _monthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) => '${_monthAbbrev[date.month - 1]} ${date.day}, ${date.year}';

/// The Prayer Garden header: the plowed field (`prayer_field.png`) filling
/// the full width as a background, with exactly one `prayer_sprout.png` per
/// active burden — or, when [answered], one `prayer_bloom.png` per answered
/// prayer — laid out in a [Wrap] over it. Tapping any plant opens that
/// prayer's detail sheet.
class PrayerGardenField extends StatelessWidget {
  const PrayerGardenField({
    super.key,
    required this.entries,
    required this.answered,
    this.height = 220,
  });

  final List<GardenEntry> entries;
  final bool answered;
  final double height;

  static const _plantHeight = 80.0;

  /// Side of the square holding each plant and its soft parchment backlight.
  static const _haloSize = 120.0;

  void _showDetail(BuildContext context, GardenEntry entry) {
    showBookplateSheet<void>(
      context,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(entry.title, style: textTheme.headlineSmall),
            if (entry.details.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(entry.details, style: textTheme.bodyMedium),
            ],
            if (entry.scripture != null) ...[
              const SizedBox(height: 12),
              Text(
                entry.scripture!,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.antiqueBrass,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (answered) ...[
              const SizedBox(height: 16),
              Text(
                entry.answeredDate == null
                    ? 'Answered'
                    : 'Answered ${_formatDate(entry.answeredDate!)}',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.forestGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _plant(BuildContext context, GardenEntry entry) {
    final asset = answered
        ? const TrimmedAsset(
            asset: 'assets/images/prayer_bloom.png',
            imageSize: Size(1024, 559),
            content: Rect.fromLTRB(366, 40, 660, 516),
            height: _plantHeight,
            cacheWidth: 600,
          )
        : const TrimmedAsset(
            asset: 'assets/images/prayer_sprout.png',
            imageSize: Size(2816, 1536),
            content: Rect.fromLTRB(1170, 336, 1648, 1134),
            height: _plantHeight,
            cacheWidth: 900,
          );

    return Semantics(
      button: true,
      label: entry.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showDetail(context, entry),
        child: Container(
          width: _haloSize,
          height: _haloSize,
          alignment: Alignment.center,
          // A soft backlight: parchment at the center fading to fully
          // transparent at the edge, so the plant lifts off the cross-hatched
          // field without a hard-edged badge.
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                AppColors.parchmentLight.withValues(alpha: 0.95),
                AppColors.parchmentLight.withValues(alpha: 0.75),
                AppColors.parchmentLight.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: asset,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          // cover fills the header's full width at any screen size, trimming
          // the field's top (sky-side) rows rather than its sides.
          // Softened so the plants (each on its own soft backlight) read clearly.
          const Positioned.fill(
            child: Opacity(
              opacity: 0.55,
              child: TrimmedAsset(
                asset: 'assets/images/prayer_field.png',
                imageSize: Size(2816, 1536),
                content: Rect.fromLTRB(96, 480, 2724, 1416),
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
                cacheWidth: 1600,
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Center(
                child: SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [for (final entry in entries) _plant(context, entry)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
