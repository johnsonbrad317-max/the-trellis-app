import '../widgets/brass_glyph.dart';

enum RuleCategory { abidingPrayer, marriageFamily, bodyPurity, workRest, communityHospitality }

/// snake_case mapping to Postgres's `rule_category` enum
/// (supabase/migrations/init_schema.sql) — every Dart enum value name here
/// maps 1:1 to its SQL counterpart.
extension RuleCategoryDb on RuleCategory {
  String get dbValue => switch (this) {
        RuleCategory.abidingPrayer => 'abiding_prayer',
        RuleCategory.marriageFamily => 'marriage_family',
        RuleCategory.bodyPurity => 'body_purity',
        RuleCategory.workRest => 'work_rest',
        RuleCategory.communityHospitality => 'community_hospitality',
      };
}

RuleCategory ruleCategoryFromDb(String value) => switch (value) {
      'abiding_prayer' => RuleCategory.abidingPrayer,
      'marriage_family' => RuleCategory.marriageFamily,
      'body_purity' => RuleCategory.bodyPurity,
      'work_rest' => RuleCategory.workRest,
      'community_hospitality' => RuleCategory.communityHospitality,
      _ => throw ArgumentError('Unknown rule_category: $value'),
    };

extension RuleCategoryLabel on RuleCategory {
  String get label => switch (this) {
        RuleCategory.abidingPrayer => 'Abiding & Prayer',
        RuleCategory.marriageFamily => 'Marriage & Family',
        RuleCategory.bodyPurity => 'Body & Purity',
        RuleCategory.workRest => 'Work & Rest',
        RuleCategory.communityHospitality => 'Community & Hospitality',
      };

  /// The engraved mark for this category (see [BrassGlyph]).
  BrassGlyphKind get glyph => switch (this) {
        RuleCategory.abidingPrayer => BrassGlyphKind.cross,
        RuleCategory.marriageFamily => BrassGlyphKind.heart,
        RuleCategory.bodyPurity => BrassGlyphKind.leaf,
        RuleCategory.workRest => BrassGlyphKind.briefcase,
        RuleCategory.communityHospitality => BrassGlyphKind.people,
      };
}

enum RuleFrequency { daily, weekly, monthly, annual }

extension RuleFrequencyLabel on RuleFrequency {
  String get label => switch (this) {
        RuleFrequency.daily => 'Daily',
        RuleFrequency.weekly => 'Weekly',
        RuleFrequency.monthly => 'Monthly',
        RuleFrequency.annual => 'Annual',
      };
}

extension RuleFrequencyDb on RuleFrequency {
  String get dbValue => switch (this) {
        RuleFrequency.daily => 'daily',
        RuleFrequency.weekly => 'weekly',
        RuleFrequency.monthly => 'monthly',
        RuleFrequency.annual => 'annual',
      };
}

RuleFrequency ruleFrequencyFromDb(String value) => switch (value) {
      'daily' => RuleFrequency.daily,
      'weekly' => RuleFrequency.weekly,
      'monthly' => RuleFrequency.monthly,
      'annual' => RuleFrequency.annual,
      _ => throw ArgumentError('Unknown rule_frequency: $value'),
    };

/// Monday..Sunday in display order, using dart:core's DateTime.monday..sunday
/// values so they compare directly against DateTime.weekday.
const weekdayOrder = [
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
  DateTime.sunday,
];

String weekdayShortLabel(int weekday) => const {
      DateTime.monday: 'M',
      DateTime.tuesday: 'Tu',
      DateTime.wednesday: 'W',
      DateTime.thursday: 'Th',
      DateTime.friday: 'F',
      DateTime.saturday: 'Sa',
      DateTime.sunday: 'Su',
    }[weekday]!;

/// How long a rhythm stays freely editable after the Rule of Life is committed
/// (or, for a rhythm added later, after it was added). A decision made on day
/// one shouldn't bind forever without a chance to live with it first; after
/// this, changing or removing the rhythm needs a Witness's approval. The
/// database enforces the same period (supabase/migrations/021).
const Duration ruleSettlePeriod = Duration(days: 7);

/// How long a Witness's approval keeps a set rhythm open for changes.
const Duration ruleUnlockWindow = Duration(hours: 24);

/// A single rhythm within a Runner's Rule of Life, e.g. "pray for 15
/// minutes" under Abiding & Prayer.
class RuleItem {
  RuleItem({
    required this.id,
    required this.category,
    required this.title,
    this.frequency = RuleFrequency.daily,
    Set<int>? weeklyDays,
    this.isAnchorRhythm = false,
    this.isChurchMandated = false,
    this.createdAt,
    this.unlockedUntil,
    this.dnaRhythmId,
  }) : weeklyDays = weeklyDays ?? <int>{};

  factory RuleItem.fromRow(Map<String, dynamic> row) => RuleItem(
        id: row['id'] as String,
        category: ruleCategoryFromDb(row['category'] as String),
        title: row['title'] as String,
        frequency: ruleFrequencyFromDb(row['frequency'] as String),
        weeklyDays: {
          for (final day in (row['weekly_days'] as List<dynamic>? ?? const [])) day as int,
        },
        isAnchorRhythm: row['is_anchor_rhythm'] as bool? ?? false,
        isChurchMandated: row['is_church_mandated'] as bool? ?? false,
        createdAt: _parseTime(row['created_at']),
        // Absent on a database that predates migration 021 — then nothing is
        // ever "unlocked", which is also what the server would say.
        unlockedUntil: _parseTime(row['unlocked_until']),
        dnaRhythmId: row['dna_rhythm_id'] as String?,
      );

  static DateTime? _parseTime(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  /// Row shape for inserting a new rhythm — `id` is left out so Postgres's
  /// `gen_random_uuid()` default assigns one, read back via
  /// `.select().single()`.
  Map<String, dynamic> toInsertRow(String runnerId) => {
        'runner_id': runnerId,
        'category': category.dbValue,
        'title': title,
        'frequency': frequency.dbValue,
        'weekly_days': weeklyDays.toList(),
        'is_anchor_rhythm': isAnchorRhythm,
        'is_church_mandated': isChurchMandated,
      };

  final String id;
  final RuleCategory category;
  String title;
  RuleFrequency frequency;

  /// Only meaningful when [frequency] is [RuleFrequency.weekly]. Values are
  /// DateTime.monday..DateTime.sunday.
  Set<int> weeklyDays;

  /// A Runner's own, personally chosen Anchor Rhythm notifies their Witness
  /// immediately if missed, rather than waiting for the weekly roll-up.
  /// Deliberately independent of [isChurchMandated] — a shared church
  /// baseline is never automatically a personal distress-signal.
  bool isAnchorRhythm;

  /// True for a DNA Rhythm injected at sign-up from the Runner's church
  /// affiliation code — the Runner didn't choose this rhythm themselves,
  /// so it can't be deleted or un-anchored from the builder.
  bool isChurchMandated;

  /// When this rhythm was added (null only for one built in memory).
  final DateTime? createdAt;

  /// Until when a Witness's approval keeps this rhythm open for changes.
  DateTime? unlockedUntil;

  /// The church DNA Rhythm this copy came from (migration 023); null for a
  /// Runner's own rhythm, for one whose DNA Rhythm has since been retired,
  /// and on a database that predates the column. Read-only to the app.
  final String? dnaRhythmId;

  /// The moment this rhythm stops being freely editable: [ruleSettlePeriod]
  /// after the Rule of Life was committed, or after the rhythm was added if
  /// that came later. Null while the Rule of Life is not committed.
  DateTime? settlesAt(DateTime? ruleCommittedAt) {
    if (ruleCommittedAt == null) return null;
    final created = createdAt;
    final start = created != null && created.isAfter(ruleCommittedAt) ? created : ruleCommittedAt;
    return start.add(ruleSettlePeriod);
  }

  /// A Witness approved changes and that approval is still running.
  bool isUnlockedAt(DateTime now) => unlockedUntil?.isAfter(now) ?? false;

  /// Whether this rhythm is "set" — changing or removing it needs a Witness's
  /// approval. Set means: the Rule of Life is committed, the settle period
  /// has passed, there IS a Witness to ask (with none, nobody could approve,
  /// so the Runner stays free to edit), and no approval is currently running.
  /// (A church-mandated rhythm is locked separately, at all times.)
  bool isSetAt(DateTime now, {required DateTime? ruleCommittedAt, required bool hasWitness}) {
    final settles = settlesAt(ruleCommittedAt);
    if (settles == null || now.isBefore(settles)) return false;
    if (!hasWitness) return false;
    return !isUnlockedAt(now);
  }

  /// Positive-phrased check-in prompt, e.g. "Did you maintain Sexual
  /// Purity?" for a title of "maintain Sexual Purity".
  ///
  /// Titles chosen from the Title Case presets start with a capital ("Read
  /// Scripture for 15 Minutes"); mid-sentence that reads wrongly, so the first
  /// letter is lowered — unless the first word is an acronym or initialism
  /// ("AA meeting"), which is left alone.
  String get checkInPrompt {
    final text = title.trim();
    if (text.length < 2) return 'Did you $text?';
    final first = text[0];
    final second = text[1];
    final startsCapitalisedWord = first != first.toLowerCase() && second == second.toLowerCase();
    return 'Did you ${startsCapitalisedWord ? first.toLowerCase() + text.substring(1) : text}?';
  }

  /// Minor words that stay lowercase in Title Case unless they lead.
  static const _minorWords = {
    'a', 'an', 'and', 'as', 'at', 'but', 'by', 'for', 'in', //
    'nor', 'of', 'on', 'or', 'so', 'the', 'to', 'up', 'yet',
  };

  /// Title-Cased for display outside the check-in question form, e.g.
  /// "Pray for 15 Minutes" for a title of "pray for 15 minutes".
  String get displayTitle {
    if (title.isEmpty) return title;
    final words = title.split(' ');
    return List.generate(words.length, (i) {
      final word = words[i];
      if (word.isEmpty) return word;
      final lower = word.toLowerCase();
      if (i != 0 && _minorWords.contains(lower)) return lower;
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    }).join(' ');
  }

  /// Whether this rhythm was scheduled for the given calendar date.
  ///
  /// Monthly means "the 1st" and annual means "January 1st" in 1.0 — a Runner
  /// can't yet choose the day. The database's scoring uses the identical rule
  /// (`_runner_resolved_days`, supabase/migrations/014), so the check-in
  /// screen and the season score always agree; change both together.
  bool scheduledFor(DateTime date) => switch (frequency) {
        RuleFrequency.daily => true,
        RuleFrequency.weekly => weeklyDays.contains(date.weekday),
        RuleFrequency.monthly => date.day == 1,
        RuleFrequency.annual => date.month == 1 && date.day == 1,
      };
}
