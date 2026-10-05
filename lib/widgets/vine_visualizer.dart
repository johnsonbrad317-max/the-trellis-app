import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'trimmed_asset.dart';

/// Which of the five trellis illustrations a Runner's season calls for.
enum TrellisState {
  empty('assets/images/trellis_empty.png'),
  growing('assets/images/trellis_growing.png'),
  flourishing('assets/images/trellis_flourishing.png'),
  struggling('assets/images/trellis_struggling.png'),
  dead('assets/images/trellis_dead.png');

  const TrellisState(this.asset);

  final String asset;

  /// The state for a season. [hasData] is false until the Runner has real
  /// check-ins — a brand-new Runner always sees the empty trellis, never a
  /// score. After that, [consistency] (0.0-1.0) picks the tier, and an
  /// Anchor Rhythm missed three times running ([isDrooping]) caps it at
  /// struggling.
  static TrellisState of({
    required bool hasData,
    required double consistency,
    required bool isDrooping,
  }) {
    if (!hasData) return TrellisState.empty;
    if (consistency < 0.15) return TrellisState.dead;
    if (isDrooping || consistency < 0.45) return TrellisState.struggling;
    if (consistency < 0.75) return TrellisState.growing;
    return TrellisState.flourishing;
  }
}

/// The Trellis visual, built as a two-layer Stack so the wooden frame is never
/// cut: the bottom layer is always the full, bare `trellis_empty.png`, and
/// over it sits the current [TrellisState]'s illustration inside a ClipRect
/// anchored at the bottom. [reveal] (0.0-1.0) is the share of that top
/// layer's height that shows, so consistency grows the vine up a permanent
/// trellis — the wood lines up pixel-for-pixel across the assets. The empty
/// state is just the bare base.
class TrellisVisual extends StatelessWidget {
  const TrellisVisual({
    super.key,
    required this.state,
    required this.reveal,
    this.height = 280,
  });

  final TrellisState state;
  final double reveal;
  final double height;

  // The five PNGs share one 1696x2528 canvas; this is the region that holds
  // the frame in all of them, so the layers line up exactly.
  static const _imageSize = Size(1696, 2528);
  static const _content = Rect.fromLTRB(120, 36, 1578, 2442);

  /// Even a near-zero season shows a sliver of growth, rather than reading as
  /// if the state image failed to load.
  static const _minReveal = 0.12;

  Widget _layer(TrellisState layerState) => TrimmedAsset(
        asset: layerState.asset,
        imageSize: _imageSize,
        content: _content,
        height: height,
        cacheWidth: 700,
      );

  @override
  Widget build(BuildContext context) {
    final target = reveal.clamp(_minReveal, 1.0);

    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Stack(
          children: [
            // Bottom layer: the bare wooden trellis, always 100% visible.
            _layer(TrellisState.empty),
            // Top layer: the current state's vine, revealed from the bottom.
            if (state != TrellisState.empty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: target),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, factor, child) => ClipRect(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      heightFactor: factor,
                      child: child,
                    ),
                  ),
                  child: _layer(state),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The "This Season" card, shared by the Runner's own dashboard and the
/// read-only view a Witness sees for a Runner they're watching.
///
/// What it reports is deliberately worded as what the Runner DID — the share
/// of their rhythms kept over the last 180 days — never as a measure of their
/// standing with God. ("Vitality: 22%" said something this app has no
/// business saying.) [vitalityScore] is that share, 0.0-1.0 (the name is
/// historical; it is never shown); [isDrooping] is true
/// when an Anchor Rhythm has been missed three times in a row; [hasData] is
/// false for a Runner with no check-ins yet, which shows the empty trellis
/// and a single line of encouragement — no score, no warnings.
class VineVisualizerCard extends StatelessWidget {
  const VineVisualizerCard({
    super.key,
    required this.vitalityScore,
    required this.isDrooping,
    this.hasData = true,
    this.showTitle = true,
  });

  final double vitalityScore;
  final bool isDrooping;
  final bool hasData;

  /// False hides the "This Season" heading — for contexts (like
  /// the Witness dashboard) that already show their own contextual title
  /// above this card.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final state = TrellisState.of(
      hasData: hasData,
      consistency: vitalityScore,
      isDrooping: isDrooping,
    );

    // A plain container with exactly the parchment look this card has always
    // had (vellum at 85%, a faint green hairline, 16px corners) — no Material
    // Card, same pixels.
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.vellum.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.vellumBorder),
      ),
      child: Column(
        children: [
          if (hasData && showTitle) ...[
            Text('This Season', style: textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              'the last 180 days',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.forestGreen.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
          ],
          TrellisVisual(state: state, reveal: vitalityScore),
          const SizedBox(height: 12),
          if (!hasData)
            Text(
              'Stick to Your Rule and Watch Yourself Grow',
              style: textTheme.titleMedium?.copyWith(fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            )
          else
            Text(
              isDrooping
                  ? 'An Anchor Rhythm has been missed three times in a row — this vine could use some care.'
                  : 'Rhythms kept: ${(vitalityScore * 100).round()}%',
              style: textTheme.bodyMedium?.copyWith(
                color: isDrooping ? AppColors.terracotta : AppColors.forestGreen,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

/// Just the trellis picture, with no surrounding Card/title/caption — sized
/// to whatever [height] you give it, so it works as a miniature next to a
/// status pill (e.g. the Cloud Roster).
class VineGlyph extends StatelessWidget {
  const VineGlyph({
    super.key,
    required this.vitalityScore,
    required this.isDrooping,
    this.hasData = true,
    this.height = 40,
  });

  final double vitalityScore;
  final bool isDrooping;
  final bool hasData;
  final double height;

  @override
  Widget build(BuildContext context) {
    return TrellisVisual(
      state: TrellisState.of(
        hasData: hasData,
        consistency: vitalityScore,
        isDrooping: isDrooping,
      ),
      reveal: vitalityScore,
      height: height,
    );
  }
}
