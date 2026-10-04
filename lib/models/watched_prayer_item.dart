/// A prayer request for a watched Runner — either shared by the Runner
/// themselves, or a private intercession the Witness added on their own.
class WatchedPrayerItem {
  WatchedPrayerItem({
    required this.id,
    required this.title,
    this.details = '',
    this.isAnswered = false,
    this.lastPrayedDate,
    this.answeredDate,
  });

  final String id;
  String title;
  String details;
  bool isAnswered;
  DateTime? lastPrayedDate;

  /// When this was marked answered — drives the Witness Connect tab's
  /// "prayer answered" contextual meeting prompt while the news is fresh.
  DateTime? answeredDate;

  bool wasPrayedOn(DateTime date) =>
      lastPrayedDate != null &&
      lastPrayedDate!.year == date.year &&
      lastPrayedDate!.month == date.month &&
      lastPrayedDate!.day == date.day;
}
