import 'package:flutter/material.dart';

import '../models/prayer_item.dart';
import '../services/prayer_photo_service.dart';
import '../theme/app_colors.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';
import 'prayer_garden_field.dart' show gardenMonthAbbrev;
import 'prayer_medallion.dart';

/// One prayer as a devotional bookplate — the card walked through in the
/// Runner's Daily Prayer session. Inside the double-rule frame used on the
/// role cards: a medallion (the person's photo or initials, or the category's
/// mark for a situation), a small brass heading, the name, a leaf-centred
/// rule, the details, the scripture in brass italics, and a quiet line saying
/// when this was last prayed for.
///
/// It fills whatever box its parent gives it. Short prayers sit centred in
/// the frame; a long one scrolls inside it instead of overflowing.
class PrayerCard extends StatelessWidget {
  const PrayerCard({
    super.key,
    required this.item,
    this.faded = false,
    this.today,
    this.photoService,
  });

  final PrayerItem item;

  /// Drawn at half strength — the cards waiting behind the one on top.
  final bool faded;

  /// "Now", for the last-prayed line; the real date unless a test fixes it.
  final DateTime? today;

  final PrayerPhotoService? photoService;

  /// "Last prayed yesterday", "Last prayed Oct 3", or — never prayed for yet
  /// — "First time praying for this".
  static String lastPrayedLine(DateTime? lastPrayed, DateTime today) {
    if (lastPrayed == null) return 'First time praying for this';
    // Whole calendar days, counted in UTC so a daylight-saving change cannot
    // make "yesterday" come out as zero or two days.
    final days = DateTime.utc(today.year, today.month, today.day)
        .difference(DateTime.utc(lastPrayed.year, lastPrayed.month, lastPrayed.day))
        .inDays;
    if (days <= 0) return 'Last prayed today';
    if (days == 1) return 'Last prayed yesterday';
    if (days < 7) return 'Last prayed $days days ago';
    final date = '${gardenMonthAbbrev[lastPrayed.month - 1]} ${lastPrayed.day}';
    return lastPrayed.year == today.year
        ? 'Last prayed $date'
        : 'Last prayed $date, ${lastPrayed.year}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isPerson = item.category == PrayerCategory.people;
    final scripture = item.scripture?.trim() ?? '';

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PrayerMedallion(
          name: item.title,
          photoPath: isPerson ? item.photoPath : null,
          glyph: isPerson ? null : item.category.glyph,
          size: 96,
          service: photoService,
        ),
        const SizedBox(height: 14),
        // No category kicker ("PERSON" / "SITUATION") above the name: the
        // medallion already says which it is, and the label read as clutter.
        Text(item.title, textAlign: TextAlign.center, style: textTheme.headlineSmall),
        const SizedBox(height: 12),
        // A short rule with a brass leaf at its centre — the one ornament.
        const SizedBox(
          width: 148,
          child: Row(
            children: [
              Expanded(child: BookplateDivider()),
              SizedBox(width: 10),
              BrassGlyph(BrassGlyphKind.leaf, size: 14, color: AppColors.antiqueBrass),
              SizedBox(width: 10),
              Expanded(child: BookplateDivider()),
            ],
          ),
        ),
        if (item.details.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            item.details,
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(height: 1.4),
          ),
        ],
        if (scripture.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            scripture,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.antiqueBrass,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          lastPrayedLine(item.lastPrayedDate, today ?? DateTime.now()),
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.forestGreen.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );

    const inset = EdgeInsets.symmetric(horizontal: 20, vertical: 22);

    return Opacity(
      opacity: faded ? 0.5 : 1,
      // The bookplate's double rule: a brass line, a 4px parchment gap, and a
      // second, fainter line — over a soft diffused shadow so the card reads
      // as thick stock lying on the page.
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.parchmentLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.forestGreen.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.vellum,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The details are free text. At least as tall as the frame, so
              // a short prayer is centred in it with no dead area at the
              // foot; taller than the frame, it scrolls (never overflows) —
              // which is also what happens at a large text size.
              final frameHeight =
                  constraints.hasBoundedHeight ? constraints.maxHeight - inset.vertical : 0.0;
              return Stack(
                children: [
                  SingleChildScrollView(
                    padding: inset,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: double.infinity,
                        minHeight: frameHeight < 0 ? 0 : frameHeight,
                      ),
                      child: content,
                    ),
                  ),
                  // Text scrolling under either edge fades into the vellum
                  // instead of being cut off by the rule — and, at the foot,
                  // hints that there is more to read. Over bare vellum these
                  // are invisible.
                  const Positioned(top: 0, left: 0, right: 0, height: 16, child: _EdgeFade()),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 16,
                    child: _EdgeFade(fromBottom: true),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({this.fromBottom = false});

  final bool fromBottom;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromBottom ? Alignment.bottomCenter : Alignment.topCenter,
            end: fromBottom ? Alignment.topCenter : Alignment.bottomCenter,
            colors: [AppColors.vellum, AppColors.vellum.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
