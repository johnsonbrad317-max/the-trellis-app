import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'trimmed_asset.dart';

/// One condition of a vine part, as drawn in assets/images/vine/.
enum VinePartState {
  /// Not grown yet — not drawn at all.
  hidden,
  bare,
  leafed,
  fruiting,
  withered,
}

/// The vine as it stands on a given day: how far the main stem has climbed
/// and the condition of each of its six side branches (1 lowest, 6 highest).
///
/// The art is ONE grapevine drawn in aligned layers — a stem in three states
/// and six branches in four — so the picture changes piece by piece: a new
/// Runner sees a young shoot, a branch appears each week of their season,
/// branches bear fruit as they keep their rhythms, and a hard stretch withers
/// the newest one or two while the rest stand.
@immutable
class VineScene {
  const VineScene({required this.stem, required this.stemReveal, required this.branches})
      : assert(branches.length == 6);

  /// bare, leafed or withered (never hidden or fruiting).
  final VinePartState stem;

  /// The share of the stem shown, from the bottom (0.0-1.0).
  final double stemReveal;

  /// Branches 1-6, lowest first.
  final List<VinePartState> branches;

  /// Where each branch leaves the stem, on the 2528-high canvas (README).
  static const _attachY = [2250.0, 1950.0, 1650.0, 1350.0, 1050.0, 750.0];
  static const _canvasHeight = 2528.0;

  /// How many days of the season it takes for each new branch to appear.
  static const daysPerBranch = 7;

  /// The scene for a season.
  ///
  /// * [hasData] false (no check-ins yet): a young bare shoot, nothing more.
  /// * [seasonDays] — days since the Rule of Life was committed — sets how
  ///   far the vine has grown: one branch the first week, a new one each
  ///   week after, all six from the sixth week. Unknown (null) means fully
  ///   grown, for views that only know the season's score.
  /// * [consistency] (0.0-1.0, the share of rhythms kept) decides how many
  ///   of the grown branches bear fruit — the oldest first — from none below
  ///   half to all of them at 90%.
  /// * A hard stretch withers branches, the newest first: one below 50%,
  ///   two below 30% or after three missed Anchor Rhythms ([isDrooping]); and
  ///   below 15% the whole vine, stem included, has withered.
  /// * The newest branch is bare for the first few days after it appears.
  static VineScene of({
    required bool hasData,
    required double consistency,
    required bool isDrooping,
    int? seasonDays,
  }) {
    if (!hasData) {
      return VineScene(
        stem: VinePartState.bare,
        stemReveal: _revealFor(1, beforeBranch: true),
        branches: List.filled(6, VinePartState.hidden),
      );
    }

    final days = seasonDays == null ? null : (seasonDays < 0 ? 0 : seasonDays);
    final grown = days == null ? 6 : (1 + days ~/ daysPerBranch).clamp(1, 6);
    final newestIsBare = days != null && grown < 6 && days % daysPerBranch < 3;
    final score = consistency.isNaN ? 0.0 : consistency.clamp(0.0, 1.0);

    if (score < 0.15) {
      return VineScene(
        stem: VinePartState.withered,
        stemReveal: _revealFor(grown),
        branches: [
          for (var i = 0; i < 6; i++) i < grown ? VinePartState.withered : VinePartState.hidden,
        ],
      );
    }

    final withered = (isDrooping || score < 0.3) ? 2 : (score < 0.5 ? 1 : 0);
    final fruitShare = ((score - 0.5) / 0.4).clamp(0.0, 1.0);
    final fruiting = (grown * fruitShare).round();

    final branches = <VinePartState>[];
    for (var i = 0; i < 6; i++) {
      if (i >= grown) {
        branches.add(VinePartState.hidden);
      } else if (i >= grown - withered) {
        branches.add(VinePartState.withered);
      } else if (newestIsBare && i == grown - 1) {
        branches.add(VinePartState.bare);
      } else if (i < fruiting) {
        branches.add(VinePartState.fruiting);
      } else {
        branches.add(VinePartState.leafed);
      }
    }
    return VineScene(
      stem: VinePartState.leafed,
      stemReveal: _revealFor(grown),
      branches: branches,
    );
  }

  /// The stem shows up to a little above its newest branch (all of it once
  /// the sixth has grown); [beforeBranch] stops it below the first branch.
  static double _revealFor(int grown, {bool beforeBranch = false}) {
    if (!beforeBranch && grown >= 6) return 1.0;
    // Day one: a young shoot about a quarter of the way up, past where the
    // first branch will come.
    final top = beforeBranch ? 1850.0 : _attachY[grown - 1] - 300;
    return ((_canvasHeight - top) / _canvasHeight).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is VineScene &&
      other.stem == stem &&
      other.stemReveal == stemReveal &&
      _listEquals(other.branches, branches);

  @override
  int get hashCode => Object.hash(stem, stemReveal, Object.hashAll(branches));

  static bool _listEquals(List<VinePartState> a, List<VinePartState> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'VineScene(stem: ${stem.name} ${stemReveal.toStringAsFixed(2)}, '
      'branches: ${branches.map((b) => b.name).join(', ')})';
}

/// How the vine's own colours sit against the brass trellis. The art is drawn
/// in green leaves and purple grapes; [muted] warms and softens them toward
/// the app's parchment-and-brass palette while keeping healthy and withered
/// easy to tell apart; [sepia] tones everything to brass and bronze like the
/// rest of the woodcuts; [original] leaves the art as drawn.
enum VineTone { original, muted, sepia }

/// Whole days from [since] to now (never negative), or null when unknown —
/// the vine's season age, from the day the Rule of Life was committed.
int? daysSince(DateTime? since, [DateTime? now]) {
  if (since == null) return null;
  final days = (now ?? DateTime.now()).difference(since).inDays;
  return days < 0 ? 0 : days;
}

/// The tone the app uses. One line to change.
const VineTone vineTone = VineTone.original;

/// The colour matrix for [tone]: luminance mapped from deep bronze to
/// parchment, blended with the original colour by how much is kept.
ColorFilter? vineToneFilter(VineTone tone) {
  final keep = switch (tone) {
    VineTone.original => null,
    VineTone.muted => 0.35,
    VineTone.sepia => 0.0,
  };
  if (keep == null) return null;
  const dark = [52.0, 36.0, 14.0];
  const light = [246.0, 232.0, 198.0];
  const luma = [0.299, 0.587, 0.114];
  final matrix = <double>[];
  for (var c = 0; c < 3; c++) {
    final span = light[c] - dark[c];
    for (var k = 0; k < 3; k++) {
      matrix.add(span * luma[k] / 255 * (1 - keep) + (k == c ? keep : 0));
    }
    matrix.addAll([0, dark[c] * (1 - keep)]);
  }
  matrix.addAll([0, 0, 0, 1, 0]);
  return ColorFilter.matrix(matrix);
}

/// The trellis with its vine: the bare wooden trellis, and over it the stem
/// (revealed from the bottom as the season grows) and each branch in its
/// current condition. A change of scene crossfades each part on its own — a
/// branch coming into fruit, another withering — and the stem climbs.
///
/// The widget is the size of the trellis frame. The vine is drawn at its full
/// canvas size around it, so leaves and grapes the artist let hang over the
/// posts or below the rail do hang over them instead of being cut off.
class TrellisVisual extends StatelessWidget {
  const TrellisVisual({super.key, required this.scene, this.height = 280, this.tone = vineTone});

  final VineScene scene;
  final double height;

  /// How the vine is coloured; the app-wide [vineTone] unless a caller (a
  /// side-by-side comparison, say) asks for another.
  final VineTone tone;

  /// The shared canvas every layer is drawn on, and the trellis frame's
  /// region of it.
  static const _canvas = Size(1696, 2528);
  static const _frame = Rect.fromLTRB(120, 36, 1578, 2442);
  static const _fade = Duration(milliseconds: 600);

  static String _vineAsset(String part, VinePartState state) =>
      'assets/images/vine/vine_${part}_${state.name}.png';

  @override
  Widget build(BuildContext context) {
    final scale = height / _frame.height;
    final width = _frame.width * scale;
    final canvasWidth = _canvas.width * scale;
    final canvasHeight = _canvas.height * scale;

    Widget layer(String asset) => Image.asset(
          asset,
          width: canvasWidth,
          height: canvasHeight,
          fit: BoxFit.fill,
          cacheWidth: 700,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        );

    Widget branch(int number, VinePartState state) => AnimatedSwitcher(
          duration: _fade,
          child: state == VinePartState.hidden
              ? SizedBox.shrink(key: ValueKey('b$number-hidden'))
              : KeyedSubtree(
                  key: ValueKey('b$number-${state.name}'),
                  child: layer(_vineAsset('branch_$number', state)),
                ),
        );

    final vine = Stack(
      children: [
        // The stem, climbing: shown from the bottom up to its reveal, its
        // top dissolving rather than ending in a straight cut.
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: scene.stemReveal),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, factor, child) => ClipRect(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: factor,
                  child: factor >= 0.999
                      ? child
                      : ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0xFF000000)],
                            stops: [0.0, 0.08],
                          ).createShader(bounds),
                          child: child,
                        ),
                ),
              ),
              child: AnimatedSwitcher(
                duration: _fade,
                child: KeyedSubtree(
                  key: ValueKey('stem-${scene.stem.name}'),
                  child: layer(_vineAsset('stem', scene.stem)),
                ),
              ),
            ),
          ),
        ),
        // Branches over the stem, lowest first (1 and 4 loop in front of it).
        for (var i = 0; i < 6; i++) Positioned.fill(child: branch(i + 1, scene.branches[i])),
      ],
    );
    final filter = vineToneFilter(tone);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The bare wooden trellis, always whole, filling the widget.
          Positioned.fill(
            child: TrimmedAsset(
              asset: 'assets/images/trellis_empty.png',
              imageSize: _canvas,
              content: _frame,
              height: height,
              cacheWidth: 700,
            ),
          ),
          // The vine, on the full canvas laid around the frame.
          Positioned(
            left: -_frame.left * scale,
            top: -_frame.top * scale,
            width: canvasWidth,
            height: canvasHeight,
            child: filter == null ? vine : ColorFiltered(colorFilter: filter, child: vine),
          ),
        ],
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
/// and a single line of encouragement — no score, no warnings. The vine itself
/// is assembled piece by piece (see [VineScene]).
class VineVisualizerCard extends StatelessWidget {
  const VineVisualizerCard({
    super.key,
    required this.vitalityScore,
    required this.isDrooping,
    this.hasData = true,
    this.showTitle = true,
    this.emptyCaption = 'Stick to Your Rule and Watch Yourself Grow',
    this.seasonDays,
  });

  /// Days since the Rule of Life was committed — how far the vine has grown
  /// (see [VineScene.of]). Null shows it fully grown.
  final int? seasonDays;

  final double vitalityScore;
  final bool isDrooping;
  final bool hasData;

  /// The single line under an empty trellis ([hasData] false). The default
  /// speaks to the Runner; a Witness looking at someone else's bare trellis
  /// gets their own line.
  final String emptyCaption;

  /// False hides the "This Season" heading — for contexts (like
  /// the Witness dashboard) that already show their own contextual title
  /// above this card.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scene = VineScene.of(
      hasData: hasData,
      consistency: vitalityScore,
      isDrooping: isDrooping,
      seasonDays: seasonDays,
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
          TrellisVisual(scene: scene),
          const SizedBox(height: 12),
          if (!hasData)
            Text(
              emptyCaption,
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
      scene: VineScene.of(hasData: hasData, consistency: vitalityScore, isDrooping: isDrooping),
      height: height,
    );
  }
}
