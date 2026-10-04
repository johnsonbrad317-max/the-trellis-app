/// A single day's retrospective Daily Check-In: which RuleItem ids were
/// answered Yes/No.
class CheckInEntry {
  const CheckInEntry({required this.date, required this.responses});

  final DateTime date;

  /// RuleItem id -> answered Yes.
  final Map<String, bool> responses;

  /// One row per rule item for this day, ready for a batch insert into
  /// `check_ins` — the SQL schema normalizes one day's worth of responses
  /// into several (rule_item_id, check_in_date, answered_yes) rows rather
  /// than storing the whole day as a single JSON blob (see
  /// supabase/migrations/init_schema.sql).
  List<Map<String, dynamic>> toInsertRows(String runnerId) => [
        for (final entry in responses.entries)
          {
            'runner_id': runnerId,
            'rule_item_id': entry.key,
            'check_in_date': date.toIso8601String().split('T').first,
            'answered_yes': entry.value,
          },
      ];

  /// Reconstructs day-grouped entries from raw `check_ins` rows (as
  /// returned by a `.select()` spanning multiple days) — groups by
  /// check_in_date, the inverse of [toInsertRows].
  static List<CheckInEntry> fromRows(List<Map<String, dynamic>> rows) {
    final byDate = <String, Map<String, bool>>{};
    for (final row in rows) {
      final dateKey = row['check_in_date'] as String;
      byDate.putIfAbsent(dateKey, () => {})[row['rule_item_id'] as String] =
          row['answered_yes'] as bool;
    }
    return [
      for (final entry in byDate.entries)
        CheckInEntry(date: DateTime.parse(entry.key), responses: entry.value),
    ];
  }
}
