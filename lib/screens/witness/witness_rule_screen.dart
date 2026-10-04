import 'package:flutter/material.dart';

import '../../models/rule_item.dart' show RuleFrequency;
import '../../models/runner_profile.dart';
import '../../models/watched_runner.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/launch_link.dart';

// Backend notification triggers (Cloud Functions) that feed this screen and
// the Witness's push notifications:
// - push_weekly_summary: sent Sunday evening with the Runner's week-in-review.
// - push_anchor_breach: sent immediately when the Runner logs a failed
//   Anchor Rhythm in their Daily Check-In.
// - push_missed_checkin: sent the morning after the Runner misses a
//   scheduled daily check-in.

enum _NudgeType { thriving, struggling, drifting }

class _Nudge {
  const _Nudge({required this.type, required this.message});

  final _NudgeType type;
  final String message;
}

_Nudge? _buildNudge(WatchedRunner runner) {
  // A Runner with no rhythms yet has a completion rate of "0" only because
  // there is nothing to complete — that is not a struggling week, and must
  // not raise the terracotta alert.
  if (runner.ruleItems.isEmpty) return null;

  final weekRate = runner.weekCompletionRate;
  final missedAnchor = runner.anchorMissedYesterday;

  if (missedAnchor != null || weekRate < 0.5) {
    return _Nudge(
      type: _NudgeType.struggling,
      message: missedAnchor != null
          ? '${runner.name} missed an Anchor Rhythm (${missedAnchor.title}) yesterday.'
          : "${runner.name}'s completion has dropped below 50% this week.",
    );
  }

  if (runner.daysSinceLastCheckIn >= 2) {
    return _Nudge(
      type: _NudgeType.drifting,
      message: "${runner.name} hasn't checked in recently.",
    );
  }

  if (weekRate > 0.9) {
    return _Nudge(type: _NudgeType.thriving, message: '${runner.name} is having a strong week.');
  }

  return null;
}

/// The Witness's operational hub for the active Runner: a live read-only
/// progress heat map for the current week, and contextual Nudge Engine
/// cards (Thriving / Struggling / Drifting) with one-tap actions.
class WitnessRuleScreen extends StatelessWidget {
  const WitnessRuleScreen({super.key, required this.profile, required this.onNavigateToConnect});

  final RunnerProfile profile;
  final VoidCallback onNavigateToConnect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        final runner = profile.selectedWatchedRunner;

        if (runner == null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 72),
                const BrassGlyph(BrassGlyphKind.people, size: 48, color: AppColors.forestGreen),
                const SizedBox(height: 16),
                Text(
                  'Select a Runner from the Runners tab to see their Rule of Life.',
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final nudge = _buildNudge(runner);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("${runner.name}'s Rule of Life", style: textTheme.headlineMedium),
              const SizedBox(height: 16),
              if (nudge != null) ...[
                _NudgeCard(nudge: nudge, runner: runner, onNavigateToConnect: onNavigateToConnect),
                const SizedBox(height: 24),
              ],
              Text('This Week', style: textTheme.titleLarge),
              const SizedBox(height: 12),
              if (runner.ruleItems.isEmpty)
                BookplatePlate(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No rhythms to show yet.',
                    style: textTheme.bodyMedium,
                  ),
                )
              else ...[
                Builder(builder: (context) {
                  // A 7-day grid can only ever mean something for a daily
                  // or weekly obligation — a monthly/annual one is "due"
                  // on at most one of these seven days, so cramming it in
                  // here is nearly all dashes and tells a Witness nothing
                  // useful. Split them out rather than render that.
                  final weekly = <WatchedRuleItem>[];
                  final other = <WatchedRuleItem>[];
                  for (final item in runner.ruleItems) {
                    (item.frequency == RuleFrequency.daily ||
                            item.frequency == RuleFrequency.weekly
                        ? weekly
                        : other)
                        .add(item);
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (weekly.isNotEmpty)
                        _WeekHeatMap(items: weekly, referenceDate: runner.referenceDate)
                      else
                        BookplatePlate(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No daily or weekly rhythms to show this week.',
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      if (other.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text('Monthly & Annual Rhythms', style: textTheme.titleLarge),
                        const SizedBox(height: 12),
                        _OtherRhythmsList(items: other),
                      ],
                    ],
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NudgeCard extends StatelessWidget {
  const _NudgeCard({required this.nudge, required this.runner, required this.onNavigateToConnect});

  final _Nudge nudge;
  final WatchedRunner runner;
  final VoidCallback onNavigateToConnect;

  Color get _accentColor => switch (nudge.type) {
        _NudgeType.thriving => AppColors.forestGreen,
        _NudgeType.struggling => AppColors.terracotta,
        _NudgeType.drifting => AppColors.antiqueBrass,
      };

  BrassGlyphKind get _glyph => switch (nudge.type) {
        _NudgeType.thriving => BrassGlyphKind.trendUp,
        _NudgeType.struggling => BrassGlyphKind.exclamation,
        _NudgeType.drifting => BrassGlyphKind.clock,
      };

  /// Opens the messaging app with [body] written. With no number on file for
  /// this Runner it still opens — the Witness picks the recipient there.
  Future<void> _sendSms(BuildContext context, String body) => launchOrNotify(
        context,
        smsUri(runner.phoneNumber ?? '', body: body),
        unavailable: 'No messaging app is available on this device.',
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isStruggling = nudge.type == _NudgeType.struggling;

    return Container(
      decoration: BoxDecoration(
        color: isStruggling ? AppColors.terracottaTint : AppColors.vellum,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _accentColor.withValues(alpha: isStruggling ? 0.8 : 0.4),
          width: isStruggling ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrassGlyph(_glyph, color: _accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nudge.message,
                    style: textTheme.titleMedium?.copyWith(
                      color: isStruggling ? AppColors.terracotta : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            switch (nudge.type) {
              _NudgeType.thriving => BookplateButton(
                  onPressed: () => _sendSms(
                    context,
                    "Hey ${runner.firstName}, saw you're having a great week on the Trellis. "
                    'Proud of you!',
                  ),
                  label: 'Send an encouraging text',
                ),
              _NudgeType.struggling => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BookplateButton(
                      variant: BookplateButtonVariant.danger,
                      onPressed: () => _sendSms(
                        context,
                        "Hey ${runner.firstName}, just checking in on you — no pressure, I'm "
                        'here if you want to talk.',
                      ),
                      label: 'Send a check-in text',
                    ),
                    const SizedBox(height: 8),
                    BookplateButton(
                      variant: BookplateButtonVariant.secondary,
                      onPressed: onNavigateToConnect,
                      label: 'Suggest a Meeting',
                    ),
                  ],
                ),
              _NudgeType.drifting => BookplateButton(
                  onPressed: () => _sendSms(
                    context,
                    "Hey ${runner.firstName}, haven't seen a check-in from you in a couple "
                    'days. Just wanted to check in — everything okay?',
                  ),
                  label: 'Nudge ${runner.firstName}',
                ),
            },
          ],
        ),
      ),
    );
  }
}

const _monthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class _WeekHeatMap extends StatelessWidget {
  const _WeekHeatMap({required this.items, required this.referenceDate});

  final List<WatchedRuleItem> items;

  /// Must be the exact same date WatchedRuleItem.weekCompletion was built
  /// against (RunnerProfile.loadWitnessData's own `referenceDate`) — column
  /// index 6 is this date, not "today" on whichever device is looking at
  /// it. Using DateTime.now() here independently was the actual bug: the
  /// grid's labels and its data were silently anchored to two different
  /// dates, which could make a rhythm's real scheduled day land under the
  /// wrong weekday header entirely, not just off by a rendering quirk.
  final DateTime referenceDate;

  static String _formatShortDate(DateTime date) => '${_monthAbbrev[date.month - 1]} ${date.day}';

  List<String> get _dayLabels => [
        for (var i = 6; i >= 0; i--) _formatShortDate(referenceDate.subtract(Duration(days: i))),
      ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dayLabels = _dayLabels;

    TextStyle? titleStyle(WatchedRuleItem item) => item.isAnchorRhythm
        ? textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)
        : textTheme.bodySmall;

    Widget percent(WatchedRuleItem item) => Text(
          '${(item.weekCompletionRate * 100).round()}%',
          style: textTheme.labelSmall?.copyWith(
            color: AppColors.forestGreen,
            fontWeight: FontWeight.w600,
          ),
        );

    // One day header: a single line that shrinks to its column.
    Widget dayLabel(String label) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: textTheme.labelSmall),
            ),
          ),
        );

    List<Widget> dayCells(WatchedRuleItem item) => [
          for (final done in item.weekCompletion) Expanded(child: Center(child: _dayMark(done))),
        ];

    return BookplatePlate(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Side by side, a rhythm's title only gets 3/10 of the plate — on a
          // phone that is ~50px, which cut every title to a few characters.
          // So on a narrow plate (or at a large text size) each rhythm takes
          // two lines instead: its full title, then its seven days.
          final stacked = constraints.maxWidth < 440 ||
              MediaQuery.textScalerOf(context).scale(100) > 130;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    if (!stacked) const Expanded(flex: 3, child: SizedBox()),
                    for (final label in dayLabels) dayLabel(label),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (final item in items) ...[
                Semantics(
                  label: _spokenSummary(item),
                  excludeSemantics: true,
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Text(item.title, style: titleStyle(item))),
                                const SizedBox(width: 8),
                                percent(item),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(children: dayCells(item)),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: titleStyle(item),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  percent(item),
                                ],
                              ),
                            ),
                            ...dayCells(item),
                          ],
                        ),
                ),
                SizedBox(height: stacked ? 14 : 10),
              ],
            ],
          );
        },
      ),
    );
  }

  /// One day's mark. `null` means this rhythm wasn't even scheduled that day
  /// (e.g. a Wed/Fri-only fast on a Monday) — a muted dash, not an empty
  /// "missed" circle, so a Witness never mistakes "not due" for "skipped".
  /// Done and missed differ by shape (filled vs. hollow), not colour alone.
  static Widget _dayMark(bool? done) {
    if (done == null) {
      return Container(
        width: 10,
        height: 2,
        color: AppColors.forestGreen.withValues(alpha: 0.25),
      );
    }
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.forestGreen : Colors.transparent,
        border: done
            ? null
            : Border.all(color: AppColors.forestGreen.withValues(alpha: 0.4), width: 1.5),
      ),
    );
  }

  /// What a screen reader says for one rhythm's row, in place of seven
  /// unlabelled dots.
  static String _spokenSummary(WatchedRuleItem item) {
    final due = item.weekCompletion.whereType<bool>().toList();
    final kept = due.where((done) => done).length;
    final anchor = item.isAnchorRhythm ? ', Anchor Rhythm' : '';
    if (due.isEmpty) return '${item.title}$anchor: not scheduled this week';
    return '${item.title}$anchor: kept $kept of ${due.length} scheduled days this week';
  }
}

/// Monthly/Annual rhythms, filtered out of _WeekHeatMap since a 7-day grid
/// can't meaningfully represent a once-a-month or once-a-year obligation —
/// just their title, frequency, and Anchor status, no day-by-day claim
/// about what happened this week (there usually isn't one to make).
class _OtherRhythmsList extends StatelessWidget {
  const _OtherRhythmsList({required this.items});

  final List<WatchedRuleItem> items;

  String _frequencyLabel(RuleFrequency frequency) => switch (frequency) {
        RuleFrequency.monthly => 'Monthly',
        RuleFrequency.annual => 'Annual',
        RuleFrequency.daily || RuleFrequency.weekly => '',
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BookplatePlate(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const BookplateDivider(),
            BookplateRow(
              title: items[i].title,
              titleStyle: items[i].isAnchorRhythm
                  ? textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
                  : textTheme.bodyMedium,
              trailing: Text(
                _frequencyLabel(items[i].frequency),
                style: textTheme.labelSmall?.copyWith(color: AppColors.antiqueBrass),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
