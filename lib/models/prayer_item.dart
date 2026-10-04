import '../widgets/brass_glyph.dart';

enum PrayerCategory { witnessRequests, people, situations }

extension PrayerCategoryDb on PrayerCategory {
  String get dbValue => switch (this) {
        PrayerCategory.witnessRequests => 'witness_requests',
        PrayerCategory.people => 'people',
        PrayerCategory.situations => 'situations',
      };
}

PrayerCategory prayerCategoryFromDb(String value) => switch (value) {
      'witness_requests' => PrayerCategory.witnessRequests,
      'people' => PrayerCategory.people,
      'situations' => PrayerCategory.situations,
      _ => throw ArgumentError('Unknown prayer_category: $value'),
    };

extension PrayerCategoryLabel on PrayerCategory {
  String get label => switch (this) {
        // Not "Witness Requests" — this reads as Witnesses asking the
        // Runner for help, when it's actually the Runner interceding for
        // their Witness(es)' own burdens.
        PrayerCategory.witnessRequests => 'Burdens from my Witness(es)',
        PrayerCategory.people => 'People',
        PrayerCategory.situations => 'Situations',
      };

  /// The engraved mark for this category (see [BrassGlyph]).
  BrassGlyphKind get glyph => switch (this) {
        PrayerCategory.witnessRequests => BrassGlyphKind.eye,
        PrayerCategory.people => BrassGlyphKind.person,
        PrayerCategory.situations => BrassGlyphKind.mountain,
      };
}

/// A single burden or praise in the Runner's Prayer Garden.
class PrayerItem {
  PrayerItem({
    required this.id,
    required this.category,
    required this.title,
    this.details = '',
    this.phoneNumber,
    this.scripture,
    this.shareWithWitnesses = false,
    this.isAnswered = false,
    this.lastPrayedDate,
    this.answeredDate,
  });

  factory PrayerItem.fromRow(Map<String, dynamic> row) => PrayerItem(
        id: row['id'] as String,
        category: prayerCategoryFromDb(row['category'] as String),
        title: row['title'] as String,
        details: row['details'] as String? ?? '',
        phoneNumber: row['phone_number'] as String?,
        scripture: row['scripture'] as String?,
        shareWithWitnesses: row['share_with_witnesses'] as bool? ?? false,
        isAnswered: row['is_answered'] as bool? ?? false,
        lastPrayedDate: row['last_prayed_date'] == null
            ? null
            : DateTime.parse(row['last_prayed_date'] as String),
        answeredDate: row['answered_date'] == null
            ? null
            : DateTime.parse(row['answered_date'] as String),
      );

  Map<String, dynamic> toInsertRow(String runnerId) => {
        'runner_id': runnerId,
        'category': category.dbValue,
        'title': title,
        'details': details,
        'phone_number': phoneNumber,
        'scripture': scripture,
        'share_with_witnesses': shareWithWitnesses,
        'is_answered': isAnswered,
        'last_prayed_date': lastPrayedDate?.toIso8601String().split('T').first,
        'answered_date': answeredDate?.toIso8601String().split('T').first,
      };

  final String id;
  PrayerCategory category;

  /// For [PrayerCategory.people], this is the person's name.
  String title;
  String details;
  String? phoneNumber;
  String? scripture;
  bool shareWithWitnesses;
  bool isAnswered;
  DateTime? lastPrayedDate;

  /// When this prayer was marked answered — drives the Blooming Garden's
  /// tap-to-view detail sheet.
  DateTime? answeredDate;

  bool wasPrayedOn(DateTime date) =>
      lastPrayedDate != null &&
      lastPrayedDate!.year == date.year &&
      lastPrayedDate!.month == date.month &&
      lastPrayedDate!.day == date.day;
}
