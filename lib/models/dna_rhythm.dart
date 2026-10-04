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
class DnaRhythm {
  const DnaRhythm({
    required this.title,
    required this.category,
    this.frequency = RuleFrequency.weekly,
    this.weeklyDays = const {DateTime.sunday},
  });

  factory DnaRhythm.fromRow(Map<String, dynamic> row) => DnaRhythm(
        title: row['title'] as String,
        category: ruleCategoryFromDb(row['category'] as String),
        frequency: ruleFrequencyFromDb(row['frequency'] as String),
        weeklyDays: {
          for (final day in (row['weekly_days'] as List<dynamic>? ?? const [])) day as int,
        },
      );

  Map<String, dynamic> toInsertRow(String churchId) => {
        'church_id': churchId,
        'title': title,
        'category': category.dbValue,
        'frequency': frequency.dbValue,
        'weekly_days': _daysForDb,
      };

  final String title;
  final RuleCategory category;
  final RuleFrequency frequency;

  /// DateTime.monday..DateTime.sunday. Only meaningful when [frequency] is
  /// weekly — the database requires at least one day for a weekly rhythm
  /// (defaulting to Sunday) and clears the days for any other frequency, so
  /// a DNA Rhythm can never be saved in a state where it never comes due.
  final Set<int> weeklyDays;

  /// What actually gets sent to the database.
  List<int> get _daysForDb =>
      frequency == RuleFrequency.weekly ? (weeklyDays.toList()..sort()) : const [];

  /// The column map for editing an existing rhythm in place.
  Map<String, dynamic> toUpdateRow() => {
        'title': title,
        'category': category.dbValue,
        'frequency': frequency.dbValue,
        'weekly_days': _daysForDb,
      };
}
