/// One rhythm's real numbers over the trailing 180-day season, as computed by
/// the database (`get_runner_analytics`, supabase/migrations/013).
///
/// There is nothing to calculate or invent on the client: the rule — every
/// scheduled day counts, and a scheduled day with no check-in is a miss — is
/// applied once, server-side, so the Runner's own dashboard, their Witness's
/// view of them, and the Cloud's roster can never disagree.
class RhythmAnalytics {
  const RhythmAnalytics({
    required this.ruleItemId,
    required this.completionRate,
    required this.scheduledDays,
    required this.completedDays,
    required this.consecutiveMisses,
    required this.weekly,
    required this.monthly,
    required this.quarterly,
  });

  factory RhythmAnalytics.fromJson(Map<String, dynamic> json) => RhythmAnalytics(
        ruleItemId: json['rule_item_id'] as String,
        completionRate: (json['completion_rate'] as num?)?.toDouble(),
        scheduledDays: (json['scheduled'] as num?)?.toInt() ?? 0,
        completedDays: (json['completed'] as num?)?.toInt() ?? 0,
        consecutiveMisses: (json['consecutive_misses'] as num?)?.toInt() ?? 0,
        weekly: _series(json['weekly']),
        monthly: _series(json['monthly']),
        quarterly: _series(json['quarterly']),
      );

  static List<double?> _series(Object? raw) => [
        for (final value in (raw as List<dynamic>? ?? const [])) (value as num?)?.toDouble(),
      ];

  final String ruleItemId;

  /// 0.0-1.0 over the season: completed / scheduled days. Null when the rhythm
  /// hasn't had a single scheduled day yet (just created, or a monthly rhythm
  /// before its first 1st) — there is nothing to measure, which is not the
  /// same as 0%.
  final double? completionRate;

  /// How many days this rhythm was scheduled (and reportable) in the season.
  final int scheduledDays;

  /// How many of those were answered Yes. The difference is every "No" plus
  /// every day nobody checked in.
  final int completedDays;

  /// Consecutive misses counted back from the newest reportable scheduled day
  /// — meaningful for Anchor Rhythms, where three in a row droops the vine.
  final int consecutiveMisses;

  /// Completion rate per bucket, oldest first, null where nothing was
  /// scheduled: 8 weeks, 6 thirty-day months, 4 ninety-day quarters.
  final List<double?> weekly;
  final List<double?> monthly;
  final List<double?> quarterly;

  bool get hasMeasurement => completionRate != null;

  /// The rate to display and rank by — an unmeasured rhythm reads as 0.
  double get rate => completionRate ?? 0;
}

/// A Runner's whole season: the score that drives the Trellis, plus each
/// rhythm's own numbers. Built from `get_runner_analytics`'s JSON.
class RunnerAnalytics {
  const RunnerAnalytics({
    required this.score,
    required this.hasData,
    required this.isDrooping,
    required this.rhythms,
  });

  /// Nothing loaded yet, or a Runner with no history — the empty trellis.
  const RunnerAnalytics.empty()
      : score = 0,
        hasData = false,
        isDrooping = false,
        rhythms = const {};

  factory RunnerAnalytics.fromJson(Map<String, dynamic> json) => RunnerAnalytics(
        score: (json['score'] as num?)?.toDouble() ?? 0,
        hasData: json['has_data'] as bool? ?? false,
        isDrooping: json['is_drooping'] as bool? ?? false,
        rhythms: {
          for (final row in (json['rhythms'] as List<dynamic>? ?? const []))
            (row as Map<String, dynamic>)['rule_item_id'] as String:
                RhythmAnalytics.fromJson(row),
        },
      );

  /// 0.0-1.0 season consistency: the mean of every measured rhythm's rate,
  /// unanswered scheduled days counted as misses, over the last 180 days.
  final double score;

  /// False until the Runner has answered at least one check-in in the season
  /// — until then the Trellis stays bare rather than showing a score of 0
  /// for someone who simply hasn't begun.
  final bool hasData;

  /// An Anchor Rhythm has been missed three or more times running.
  final bool isDrooping;

  /// Rule item id -> that rhythm's numbers.
  final Map<String, RhythmAnalytics> rhythms;

  RhythmAnalytics? forItem(String ruleItemId) => rhythms[ruleItemId];
}
