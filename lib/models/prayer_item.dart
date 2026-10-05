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

  /// The category said of one prayer rather than of a list — the small
  /// heading on a single prayer's card.
  String get singularLabel => switch (this) {
        PrayerCategory.witnessRequests => 'From My Witness',
        PrayerCategory.people => 'Person',
        PrayerCategory.situations => 'Situation',
      };
}

/// The private Supabase Storage bucket holding prayer photos. Each signed-in
/// user may read and write only the folder named with their own user id, so a
/// photo is only ever shown to the Runner who owns the prayer.
const prayerPhotoBucket = 'prayer-photos';

/// Where one prayer's photo lives inside [prayerPhotoBucket].
String prayerPhotoPathFor({required String userId, required String prayerId}) =>
    '$userId/$prayerId.jpg';

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
    this.photoPath,
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
        photoPath: _photoPathFrom(row['photo_path']),
      );

  /// Tolerant on purpose: a database that has not had the photo migration run
  /// has no `photo_path` column at all, and prayers must still load from it.
  static String? _photoPathFrom(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  // `photo_path` is deliberately not part of an insert: a photo can only be
  // uploaded once the row (and so its id) exists, and leaving the column out
  // keeps adding a prayer working on a database without it.

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

  /// Path of this prayer's photo inside the private [prayerPhotoBucket], or
  /// null when it has none (initials are shown instead). Only the Runner who
  /// owns the prayer can read the photo — it is never sent to a Witness.
  String? photoPath;

  bool wasPrayedOn(DateTime date) =>
      lastPrayedDate != null &&
      lastPrayedDate!.year == date.year &&
      lastPrayedDate!.month == date.month &&
      lastPrayedDate!.day == date.day;
}
