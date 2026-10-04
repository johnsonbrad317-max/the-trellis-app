/// One rhythm's aggregate completion rate across the whole congregation —
/// the Cloud's Congregational Health metrics list. Deliberately a flat,
/// church-wide rollup (like [ChurchRosterEntry]) rather than something
/// derived live from individual Runners, since a Church Admin should never
/// be able to reverse-engineer one person's data from these numbers.
class ChurchRhythmMetric {
  const ChurchRhythmMetric({required this.title, required this.completionRate});

  /// [json] is one entry of `get_congregational_health()`'s `metrics` array
  /// (see supabase/migrations/init_schema.sql).
  factory ChurchRhythmMetric.fromJson(Map<String, dynamic> json) => ChurchRhythmMetric(
        title: json['title'] as String,
        completionRate: (json['completion_rate'] as num).toDouble(),
      );

  final String title;

  /// 0.0-1.0 aggregate completion rate across every active Runner tracking
  /// this rhythm, over the last 30 days.
  final double completionRate;
}
