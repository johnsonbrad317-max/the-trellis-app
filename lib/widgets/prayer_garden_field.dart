import 'dart:math' as math;

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
    this.id,
  });

  final String title;
  final String details;
  final String? scripture;
  final DateTime? answeredDate;

  /// The prayer this plant stands for, when the screen showing the garden
  /// wants to open its own detail for it (see [PrayerGardenField.onEntryTap]).
  final String? id;
}

/// Three-letter month names, January first — for the short dates on prayers.
const gardenMonthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A date as "Oct 3, 2026".
String formatGardenDate(DateTime date) =>
    '${gardenMonthAbbrev[date.month - 1]} ${date.day}, ${date.year}';

/// Where one plant (or the "+N" marker) stands in the field.
class GardenPlot {
  const GardenPlot({required this.cell, required this.plantHeight});

  /// The plot's whole patch of ground — its tap target. Plots never overlap.
  final Rect cell;

  /// How tall the plant is drawn, standing on the bottom edge of [cell].
  final double plantHeight;

  /// The square of soft parchment light behind the plant. Wider than the
  /// cell on purpose: neighbouring halos blend into one another.
  Rect get halo => Rect.fromCenter(
        center: Offset(cell.center.dx, cell.bottom - plantHeight / 2),
        width: plantHeight * 1.5,
        height: plantHeight * 1.5,
      );
}

/// The most plots the field will ever draw. Past this it shows one fewer
/// plant and a "+N" marker in the last plot; the list under the field always
/// has every prayer.
const gardenFieldMaxPlots = 12;

/// A plant at full size — what one to three prayers get.
const _fullPlantHeight = 80.0;

/// Each row behind the front one is drawn this much smaller, following the
/// field's furrows back toward the horizon.
const _rowShrink = 0.12;

/// A plot is at least this fraction of its plant's height wide — the plant
/// itself is about 0.6 of its height, so this leaves air between neighbours.
const _plotAspect = 0.78;

/// The smallest patch a finger can reliably hit.
const _minTapTarget = 44.0;

const _fieldPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

/// Lays out [count] plots inside a field of [size] so that every one fits:
/// one row while they fit at a good size, then two or three staggered rows
/// (the back rows a little smaller), every plant shrinking as the count
/// grows. Plots are returned back row first, left to right — the order they
/// are painted in. Nothing is ever placed outside the field.
List<GardenPlot> layoutGardenPlots(Size size, int count) {
  if (count <= 0) return const [];
  final availW = math.max(0.0, size.width - _fieldPadding.horizontal);
  final availH = math.max(0.0, size.height - _fieldPadding.vertical);

  // Try one, two and three rows and keep whichever lets the plants be
  // biggest — preferring fewer rows unless more is clearly better.
  ({List<int> counts, List<double> scales, List<int> stagger, double plant})? best;
  for (var rows = 1; rows <= math.min(3, count); rows++) {
    // The front rows take any remainder: 11 plants in three rows is 3/4/4.
    final counts = [
      for (var i = 0; i < rows; i++) count ~/ rows + (i >= rows - count % rows ? 1 : 0),
    ];
    final scales = [for (var i = 0; i < rows; i++) 1 - _rowShrink * (rows - 1 - i)];

    // Brickwork: a row must not line up in columns with the row in front of
    // it. Rows whose counts differ by one are already offset just by being
    // centred; rows with equal counts are nudged a quarter-plot in opposite
    // directions (-1 / +1 here, 0 for "leave centred").
    final stagger = List<int>.filled(rows, 0);
    var anyAligned = false;
    for (var i = 0; i < rows - 1; i++) {
      if (counts[i].isEven == counts[i + 1].isEven) anyAligned = true;
    }
    if (anyAligned) {
      stagger[rows - 1] = 1;
      for (var i = rows - 2; i >= 0; i--) {
        stagger[i] = counts[i].isEven == counts[i + 1].isEven ? -stagger[i + 1] : stagger[i + 1];
      }
    }

    // The plant height (of the front row) is limited by the field's height
    // shared between the rows, and by each row's width shared between its
    // plots — a nudged row keeps half a plot spare for the nudge.
    var plant = math.min(_fullPlantHeight, availH / scales.reduce((a, b) => a + b));
    for (var i = 0; i < rows; i++) {
      final plotsWide = counts[i] + (stagger[i] == 0 ? 0 : 0.5);
      plant = math.min(plant, availW / plotsWide / (scales[i] * _plotAspect));
    }

    if (best == null || plant > best.plant * 1.1) {
      best = (counts: counts, scales: scales, stagger: stagger, plant: plant);
    }
  }

  final plan = best!;
  final rows = plan.counts.length;
  final blockHeight = plan.plant * plan.scales.reduce((a, b) => a + b);
  var top = _fieldPadding.top + (availH - blockHeight) / 2;
  final centerX = size.width / 2;

  final plots = <GardenPlot>[];
  for (var i = 0; i < rows; i++) {
    final plantHeight = plan.plant * plan.scales[i];
    final plotsWide = plan.counts[i] + (plan.stagger[i] == 0 ? 0 : 0.5);
    // Spread across the row, but never wider than the plant's own halo — one
    // or two plants stand together in the middle rather than at the edges.
    final cellWidth = math.min(availW / plotsWide, plantHeight * 1.5);
    final left = centerX - plan.counts[i] * cellWidth / 2 + plan.stagger[i] * cellWidth / 4;
    for (var j = 0; j < plan.counts[i]; j++) {
      plots.add(GardenPlot(
        cell: Rect.fromLTWH(left + j * cellWidth, top, cellWidth, plantHeight),
        plantHeight: plantHeight,
      ));
    }
    top += plantHeight;
  }
  return plots;
}

/// How many plots a field of [size] can hold with each still a comfortable
/// tap target — [gardenFieldMaxPlots] on any phone, fewer only in a very
/// narrow or short field. Always at least one.
int gardenFieldCapacity(Size size) {
  for (var count = gardenFieldMaxPlots; count > 1; count--) {
    final fits = layoutGardenPlots(size, count).every(
      (plot) => plot.cell.width >= _minTapTarget && plot.cell.height >= _minTapTarget,
    );
    if (fits) return count;
  }
  return 1;
}

/// The Prayer Garden header: the plowed field (`prayer_field.png`) filling
/// the full width as a background, with one `prayer_sprout.png` per active
/// burden — or, when [answered], one `prayer_bloom.png` per answered prayer —
/// standing in it. The plants shrink and fall into staggered rows as the
/// garden grows (see [layoutGardenPlots]), so they always fit; past
/// [gardenFieldMaxPlots] the last plot becomes a "+N" marker pointing at the
/// full list below. Tapping any plant opens that prayer's detail sheet.
class PrayerGardenField extends StatelessWidget {
  const PrayerGardenField({
    super.key,
    required this.entries,
    required this.answered,
    this.height = 220,
    this.onEntryTap,
    this.onShowAll,
  });

  final List<GardenEntry> entries;
  final bool answered;
  final double height;

  /// Called when a plant is tapped, in place of the built-in read-only detail
  /// sheet — for a screen whose prayers can be acted on from their detail.
  final ValueChanged<GardenEntry>? onEntryTap;

  /// Called when the "+N" marker is tapped (e.g. to scroll to the list). Left
  /// null, the marker just says where the rest are.
  final VoidCallback? onShowAll;

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
                    : 'Answered ${formatGardenDate(entry.answeredDate!)}',
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

  Widget _plant(BuildContext context, GardenEntry entry, GardenPlot plot) {
    final asset = answered
        ? TrimmedAsset(
            asset: 'assets/images/prayer_bloom.png',
            imageSize: const Size(1024, 559),
            content: const Rect.fromLTRB(366, 40, 660, 516),
            height: plot.plantHeight,
            cacheWidth: 600,
          )
        : TrimmedAsset(
            asset: 'assets/images/prayer_sprout.png',
            imageSize: const Size(2816, 1536),
            content: const Rect.fromLTRB(1170, 336, 1648, 1134),
            height: plot.plantHeight,
            cacheWidth: 900,
          );

    void open() => onEntryTap != null ? onEntryTap!(entry) : _showDetail(context, entry);

    // The whole plot is the tap target, not just the drawn plant.
    return Semantics(
      button: true,
      label: entry.title,
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: Align(alignment: Alignment.bottomCenter, child: asset),
      ),
    );
  }

  /// The soft backlight under one plant: parchment at the center fading to
  /// fully transparent at the edge, so the plant lifts off the cross-hatched
  /// field without a hard-edged badge.
  Widget _halo() {
    return IgnorePointer(
      child: DecoratedBox(
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
      ),
    );
  }

  /// "+N" in brass on a small parchment roundel, standing in the last plot
  /// for every prayer the field has no room to draw.
  Widget _moreMarker(BuildContext context, GardenPlot plot, int hidden) {
    final diameter =
        (math.min(plot.cell.width, plot.cell.height) * 0.72).clamp(36.0, 56.0).toDouble();

    void showAll() => onShowAll != null
        ? onShowAll!()
        : showBookplateNotice(context, 'All ${entries.length} are listed below.');

    return Semantics(
      button: true,
      label: '$hidden more, listed below',
      onTap: showAll,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: showAll,
        child: Center(
          child: Container(
            width: diameter,
            height: diameter,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.parchmentLight,
              border: Border.all(color: AppColors.antiqueBrass, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.forestGreen.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            // Scaled down to fit: "+128", or a large system text size, must
            // stay inside the roundel.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '+$hidden',
                maxLines: 1,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.antiqueBrass,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth.isFinite ? constraints.maxWidth : 320, height);

          // Everything fits up to the field's capacity; beyond it the last
          // plot is given over to the "+N" marker.
          final capacity = gardenFieldCapacity(size);
          final overflowing = entries.length > capacity;
          final plantCount = overflowing ? capacity - 1 : entries.length;
          final plots = layoutGardenPlots(size, overflowing ? capacity : entries.length);

          return Stack(
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
              // Every halo goes down before any plant, so one plant's light
              // never washes over its neighbour.
              for (var i = 0; i < plantCount; i++)
                Positioned.fromRect(rect: plots[i].halo, child: _halo()),
              for (var i = 0; i < plantCount; i++)
                Positioned.fromRect(
                  rect: plots[i].cell,
                  child: _plant(context, entries[i], plots[i]),
                ),
              if (overflowing)
                Positioned.fromRect(
                  rect: plots.last.cell,
                  child: _moreMarker(context, plots.last, entries.length - plantCount),
                ),
            ],
          );
        },
      ),
    );
  }
}
