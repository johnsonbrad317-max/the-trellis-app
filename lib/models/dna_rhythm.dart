import 'meeting_proposal_engine.dart' show monthAbbrev;
import 'rule_item.dart';

/// A rhythm a Church Admin (Cloud role) mandates congregation-wide — e.g.
/// Sabbath Rest, Corporate Worship. Injected as a real, church-mandated
/// [RuleItem] into every new Runner's Rule of Life when they redeem that
/// church's invite code at sign-up, and pinned to the top of the Cloud's
/// Congregational Health metrics.
///
/// Deliberately a separate concept from a Runner's personal Anchor Rhythm
/// ([RuleItem.isAnchorRhythm], which triggers an immediate Witness
/// notification when missed): a DNA Rhythm is a shared baseline
/// expectation the whole church holds, not one Runner's personal
/// distress-signal. Redeeming a church code marks the injected [RuleItem]
/// [RuleItem.isChurchMandated] but never [RuleItem.isAnchorRhythm] — the two
/// flags stay independent so the database never conflates them.
///
/// A DNA Rhythm may be for a season ([endsOn], its last day — Lent, say) or
/// year-round (null). When the season ends, or the church retires the rhythm,
/// nobody's copy is deleted: each member's copy becomes their own rhythm,
/// history intact, free to keep or remove (migration 023).
class DnaRhythm {
  const DnaRhythm({
    this.id,
    required this.title,
    required this.category,
    this.frequency = RuleFrequency.weekly,
    this.weeklyDays = const {DateTime.sunday},
    this.endsOn,
  });

  factory DnaRhythm.fromRow(Map<String, dynamic> row) => DnaRhythm(
        id: row['id'] as String?,
        title: row['title'] as String,
        category: ruleCategoryFromDb(row['category'] as String),
        frequency: ruleFrequencyFromDb(row['frequency'] as String),
        weeklyDays: {
          for (final day in (row['weekly_days'] as List<dynamic>? ?? const [])) day as int,
        },
        // A `date` column arrives as 'YYYY-MM-DD'; absent before migration 023.
        endsOn: _parseDate(row['ends_on']),
      );

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }

  Map<String, dynamic> toInsertRow(String churchId) => {
        'church_id': churchId,
        'title': title,
        'category': category.dbValue,
        'frequency': frequency.dbValue,
        'weekly_days': _daysForDb,
        // Only sent when set: a database that predates migration 023 has no
        // such column and would refuse the whole row.
        if (endsOn != null) 'ends_on': _endsOnForDb,
      };

  /// The database row id — null only for a rhythm built in memory (a new one
  /// before it is saved, or one read from a row without an id).
  final String? id;
  final String title;
  final RuleCategory category;
  final RuleFrequency frequency;

  /// DateTime.monday..DateTime.sunday. Only meaningful when [frequency] is
  /// weekly — the database requires at least one day for a weekly rhythm
  /// (defaulting to Sunday) and clears the days for any other frequency, so
  /// a DNA Rhythm can never be saved in a state where it never comes due.
  final Set<int> weeklyDays;

  /// The last day this rhythm is in force (a calendar date, local midnight);
  /// null for a year-round rhythm. The server retires it the morning after.
  final DateTime? endsOn;

  /// What actually gets sent to the database.
  List<int> get _daysForDb =>
      frequency == RuleFrequency.weekly ? (weeklyDays.toList()..sort()) : const [];

  String? get _endsOnForDb {
    final date = endsOn;
    if (date == null) return null;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// Whether [today] is past the rhythm's last day.
  bool hasEnded(DateTime today) {
    final date = endsOn;
    if (date == null) return false;
    return DateTime(today.year, today.month, today.day).isAfter(date);
  }

  /// "Year-round", or "Through Apr 5, 2026".
  String get seasonLabel {
    final date = endsOn;
    if (date == null) return 'Year-round';
    return 'Through ${monthAbbrev[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// The column map for editing an existing rhythm in place. Here `ends_on`
  /// is always sent (so clearing a season back to year-round sticks), which
  /// needs migration 023 — the add/edit dialog is only offered a season once
  /// the column exists, see [DnaRhythm.toInsertRow] for the other direction.
  Map<String, dynamic> toUpdateRow({bool includeSeason = true}) => {
        'title': title,
        'category': category.dbValue,
        'frequency': frequency.dbValue,
        'weekly_days': _daysForDb,
        if (includeSeason) 'ends_on': _endsOnForDb,
      };
}
