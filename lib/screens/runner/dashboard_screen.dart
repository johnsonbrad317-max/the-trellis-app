import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/rhythm_analytics.dart';
import '../../models/rule_item.dart';
import '../../models/runner_profile.dart';
import '../../models/support_request.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_tabs.dart';
import '../../widgets/getting_started_plate.dart';
import '../../widgets/vine_visualizer.dart';

/// Below this share of scheduled days a rhythm reads as needing care; at or
/// above it, as a faithful one. (The Trellis's own tiers — struggling under
/// 0.45, flourishing from 0.75 — live in [TrellisState].)
const _faithfulFrom = 0.6;

/// A rhythm needs at least this many scheduled days behind it before an
/// Insight is written about it — one good (or bad) day isn't a pattern.
const _minDaysForInsight = 3;

/// The Runner's dashboard: a 180-day "Vine" vitality visual, a handful of
/// gracious insights, and a drill-down list of every active rhythm.
///
/// Every figure here comes straight from the database
/// (`RunnerProfile.analytics`): the season score averages each rhythm over the
/// last 180 days and counts a scheduled day with no check-in as a miss. The
/// screen does no scoring of its own.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        final items = profile.ruleItems;
        final analytics = profile.analytics;

        // Until the first real check-in there is nothing to measure: no
        // score, no missed-rhythm warnings, no insights — just the empty
        // trellis.
        final hasData = items.isNotEmpty && analytics.hasData;
        final insights = hasData ? _buildInsights(items, analytics) : const <_Insight>[];
        final couldNotLoad = profile.analyticsFailed && !profile.analyticsLoaded;

        // A new Runner's next step comes first, until all three are done
        // (and only once their data has loaded — "no Witness yet" isn't true
        // until it has).
        final showGettingStarted =
            profile.isRunnerDataLoaded && GettingStartedPlate.isNeeded(profile);

        return CustomScrollView(
          slivers: [
            if (showGettingStarted)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                sliver: SliverToBoxAdapter(child: GettingStartedPlate(profile: profile)),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              sliver: SliverToBoxAdapter(
                child: VineVisualizerCard(
                  vitalityScore: hasData ? analytics.score : 0,
                  isDrooping: hasData && analytics.isDrooping,
                  hasData: hasData,
                ),
              ),
            ),
            if (couldNotLoad)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                sliver: SliverToBoxAdapter(
                  child: _Plate(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "Your season couldn't be loaded just now, so the vine above is bare "
                          'rather than a verdict on how you are doing.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        BookplateButton(
                          label: 'Try Again',
                          variant: BookplateButtonVariant.secondary,
                          onPressed: profile.refreshAnalytics,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (insights.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                sliver: SliverToBoxAdapter(
                  child: Text('Insights', style: Theme.of(context).textTheme.headlineMedium),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList.separated(
                  itemCount: insights.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _InsightCard(profile: profile, insight: insights[index]),
                ),
              ),
            ],
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              sliver: SliverToBoxAdapter(
                child: Text('Season Metrics', style: Theme.of(context).textTheme.headlineMedium),
              ),
            ),
            if (items.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: _Plate(
                    child: Text(
                      'Build a Rule of Life to start seeing your rhythms here.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _RhythmTile(
                      item: item,
                      analytics: analytics.forItem(item.id),
                      onTap: () => _showDrillDown(context, item, analytics.forItem(item.id)),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}

class _Insight {
  const _Insight({
    required this.message,
    required this.positive,
    this.ruleItemId,
    this.rhythmTitle,
  });

  final String message;
  final bool positive;

  /// The rhythm a gentle flag is about — what a prayer or meeting request
  /// attaches to. Null for praise (nothing to ask for).
  final String? ruleItemId;
  final String? rhythmTitle;
}

/// Insights written from the real numbers only: the most faithful rhythms
/// (praise), and the ones furthest from faithful (a gentle flag). A rhythm
/// appears at most once, and only if it has enough scheduled days behind it
/// to mean something.
List<_Insight> _buildInsights(List<RuleItem> items, RunnerAnalytics analytics) {
  final measured = [
    for (final item in items)
      if ((analytics.forItem(item.id)?.scheduledDays ?? 0) >= _minDaysForInsight)
        (item: item, analytics: analytics.forItem(item.id)!),
  ]..sort((a, b) => b.analytics.rate.compareTo(a.analytics.rate));

  final praised = measured
      .where((entry) => entry.analytics.rate >= _faithfulFrom)
      .take(2)
      .toList();
  final flagged = measured.reversed
      .where((entry) => entry.analytics.rate < _faithfulFrom && !praised.contains(entry))
      .take(2)
      .toList()
      .reversed
      .toList();

  int pct(RhythmAnalytics a) => (a.rate * 100).round();

  return [
    for (final entry in praised)
      _Insight(
        message: 'Faithful in ${entry.item.displayTitle}: ${pct(entry.analytics)}% of the season.',
        positive: true,
      ),
    for (final entry in flagged)
      _Insight(
        message: '${entry.item.displayTitle} is at ${pct(entry.analytics)}% this season.',
        positive: false,
        ruleItemId: entry.item.id,
        rhythmTitle: entry.item.displayTitle,
      ),
  ];
}

/// The parchment plate every card on this screen is cut from: vellum fill,
/// antique-brass hairline, a soft shadow.
class _Plate extends StatelessWidget {
  const _Plate({required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.vellum,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InsightCard extends StatefulWidget {
  const _InsightCard({required this.profile, required this.insight});

  final RunnerProfile profile;
  final _Insight insight;

  @override
  State<_InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends State<_InsightCard> {
  SupportRequestKind? _sending;

  /// A real request: a row per Witness, a real push to each. The Runner is told
  /// exactly what happened — including "you have no Witness" and "you already
  /// asked today" — never a claim the server didn't back.
  Future<void> _request(SupportRequestKind kind) async {
    if (_sending != null) return;
    final insight = widget.insight;
    setState(() => _sending = kind);

    String notice;
    try {
      final outcome = await widget.profile.requestSupport(kind, ruleItemId: insight.ruleItemId);
      final about = insight.rhythmTitle == null ? '' : ' about ${insight.rhythmTitle}';
      notice = switch (outcome) {
        SupportRequestOutcome.sent => kind == SupportRequestKind.prayer
            ? 'Your Witness has been asked to pray$about.'
            : 'Your Witness has been asked to meet$about.',
        SupportRequestOutcome.alreadyAsked =>
          "You've already asked about this today — your Witness has it.",
        SupportRequestOutcome.noWitness =>
          'You need a Witness first. Invite one from My Witnesses in the menu.',
      };
    } catch (_) {
      notice = "Couldn't send that request. Check your connection and try again.";
    } finally {
      if (mounted) setState(() => _sending = null);
    }
    if (mounted) showBookplateNotice(context, notice);
  }

  Widget _requestButton(SupportRequestKind kind, String label) {
    final requested = widget.profile.hasRequestedSupport(
      kind,
      ruleItemId: widget.insight.ruleItemId,
    );
    return BookplateButton(
      label: requested ? '$label — Sent' : label,
      compact: true,
      variant: BookplateButtonVariant.secondary,
      busy: _sending == kind,
      onPressed: requested ? null : () => _request(kind),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insight = widget.insight;
    final color = insight.positive ? AppColors.forestGreen : AppColors.antiqueBrass;

    return _Plate(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 2))),
            child: Text(insight.message, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (!insight.positive && insight.ruleItemId != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _requestButton(SupportRequestKind.prayer, 'Request Prayer'),
                _requestButton(SupportRequestKind.meeting, 'Request Meeting'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RhythmTile extends StatelessWidget {
  const _RhythmTile({required this.item, required this.analytics, required this.onTap});

  final RuleItem item;

  /// Null only if the server returned nothing for this rhythm yet (e.g. it
  /// was just added and the refresh hasn't landed).
  final RhythmAnalytics? analytics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheduled = analytics?.scheduledDays ?? 0;
    final completed = analytics?.completedDays ?? 0;

    return Semantics(
      button: true,
      hint: 'Shows this rhythm by week, month and quarter',
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _Plate(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displayTitle, style: textTheme.titleMedium),
                  Text(
                    '${item.frequency.label} · ${item.category.label}',
                    style: textTheme.bodySmall,
                  ),
                  if (scheduled > 0)
                    Text(
                      '$completed of $scheduled scheduled days',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.antiqueBrass),
                    )
                  else
                    Text(
                      'No scheduled days yet',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.antiqueBrass,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _ThickProgressRing(value: analytics?.completionRate),
          ],
        ),
      ),
      ),
    );
  }
}

/// A thick, layered concentric ring — a thin forest-green outer bezel around
/// a thick antique-brass progress arc — painted by hand rather than drawn with
/// Material's progress indicator. A null [value] (nothing scheduled yet) shows
/// the bare bezel and a dash, not a misleading 0%.
class _ThickProgressRing extends StatelessWidget {
  const _ThickProgressRing({required this.value});

  final double? value;
  static const _size = 52.0;

  @override
  Widget build(BuildContext context) {
    final fraction = (value ?? 0).clamp(0.0, 1.0);

    return Semantics(
      label: value == null ? 'No score yet' : '${(fraction * 100).round()} percent',
      excludeSemantics: true,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(size: const Size.square(_size), painter: _RingPainter(fraction)),
            // The ring is a fixed 52px, so the figure shrinks to stay inside
            // it at large text sizes rather than spilling over the arc.
            SizedBox(
              width: 26,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value == null ? '—' : '${(fraction * 100).round()}%',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.forestGreen,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fraction);

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.width / 2 - 1.25;
    final trackRadius = size.width / 2 - 7 - 3;

    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.forestGreen.withValues(alpha: 0.3),
    );
    canvas.drawCircle(
      center,
      trackRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = AppColors.antiqueBrass.withValues(alpha: 0.15),
    );
    if (fraction > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: trackRadius),
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = AppColors.antiqueBrass,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.fraction != fraction;
}

enum _Period { weekly, monthly, quarterly }

/// One rhythm's detail on a parchment bookplate: the season figure, and its
/// completion rate by week, month, or quarter. A bar is missing (not zero)
/// where nothing was scheduled — before the rhythm existed, or in a quiet
/// stretch for a weekly one.
Future<void> _showDrillDown(BuildContext context, RuleItem item, RhythmAnalytics? analytics) {
  var period = _Period.weekly;

  List<double?> values() => switch (period) {
        _Period.weekly => analytics?.weekly ?? const [],
        _Period.monthly => analytics?.monthly ?? const [],
        _Period.quarterly => analytics?.quarterly ?? const [],
      };

  List<String> labels(int count) => switch (period) {
        _Period.weekly => [for (var i = 0; i < count; i++) 'W${i + 1}'],
        _Period.monthly => [for (var i = 0; i < count; i++) 'M${i + 1}'],
        _Period.quarterly => [for (var i = 0; i < count; i++) 'Q${i + 1}'],
      };

  final scheduled = analytics?.scheduledDays ?? 0;
  final summary = scheduled == 0
      ? 'Nothing has been scheduled yet.'
      : '${((analytics?.rate ?? 0) * 100).round()}% over the last 180 days — '
          '${analytics?.completedDays ?? 0} of $scheduled scheduled days.';

  return showBookplateForm<void>(
    context,
    title: item.displayTitle,
    message: summary,
    bodyBuilder: (dialogContext, setState) {
      final bars = values();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BookplateTabs<_Period>(
            tabs: const {
              _Period.weekly: 'Weekly',
              _Period.monthly: 'Monthly',
              _Period.quarterly: 'Quarterly',
            },
            selected: period,
            onChanged: (next) => setState(() => period = next),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: bars.isEmpty
                ? Center(
                    child: Text(
                      'No history to chart yet.',
                      style: Theme.of(dialogContext).textTheme.bodyMedium,
                    ),
                  )
                : _ConsistencyBarChart(values: bars, labels: labels(bars.length)),
          ),
          const SizedBox(height: 4),
          Text(
            'Oldest on the left. Days with no check-in count as missed.',
            style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: AppColors.antiqueBrass,
                  fontStyle: FontStyle.italic,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    },
    actionsBuilder: (dialogContext, setState) => [
      BookplateButton(
        label: 'Close',
        variant: BookplateButtonVariant.secondary,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );
}

class _ConsistencyBarChart extends StatelessWidget {
  const _ConsistencyBarChart({required this.values, required this.labels});

  final List<double?> values;
  final List<String> labels;

  /// A bucket's rate as a 0-1 fraction (null — nothing scheduled — draws no bar).
  static double _unit(double? value) => (value ?? 0).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              // Labels keep to one line and shrink to the column (8 weekly
              // bars on a 320pt phone leave ~20px each), and the bar is
              // Flexible — it yields height to the two labels at large text
              // sizes — so the chart can't overflow its fixed box.
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      values[i] == null ? '—' : '${(_unit(values[i]) * 100).round()}',
                      maxLines: 1,
                      style: textTheme.labelSmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Container(
                      height: 100 * _unit(values[i]),
                      decoration: BoxDecoration(
                        color: AppColors.forestGreen
                            .withValues(alpha: 0.3 + _unit(values[i]) * 0.6),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(labels[i], maxLines: 1, style: textTheme.labelSmall),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
