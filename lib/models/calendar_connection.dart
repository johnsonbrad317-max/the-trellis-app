import 'shared_free_windows.dart';

/// A window when both people are free. Times are local to this device.
class SharedSlot {
  const SharedSlot({required this.start, required this.end});

  /// From a [TimeSpan] produced by [sharedFreeWindows].
  SharedSlot.fromSpan(TimeSpan span)
      : start = span.start.toLocal(),
        end = span.end.toLocal();

  final DateTime start;
  final DateTime end;
}

/// The answer to "when are we both free?" with one other person.
///
/// Each person's phone uploads the busy blocks (start and end only — never a
/// title) from the calendars already on it; the intersection is computed on
/// the asking phone. So "sharing" here means "has uploaded busy blocks", and
/// a sync time says how fresh they are.
class PairAvailability {
  const PairAvailability({
    required this.suggestions,
    required this.meSharing,
    required this.otherSharing,
    this.meSyncedAt,
    this.otherSyncedAt,
    this.myBusy = const [],
    this.otherBusy = const [],
  });

  /// Nobody sharing / nothing known.
  static const PairAvailability none =
      PairAvailability(suggestions: [], meSharing: false, otherSharing: false);

  final List<SharedSlot> suggestions;

  /// Whether this phone has uploaded busy blocks.
  final bool meSharing;

  /// Whether the other person's phone has.
  final bool otherSharing;

  final DateTime? meSyncedAt;
  final DateTime? otherSyncedAt;

  /// The busy blocks behind [suggestions], when both are sharing: mine (read
  /// from this phone just now) and the other person's (as their phone last
  /// uploaded them). Empty otherwise. For the activity-specific slot search
  /// on this phone only (see meeting_activity.dart) — never sent anywhere.
  final List<TimeSpan> myBusy;
  final List<TimeSpan> otherBusy;

  bool get bothSharing => meSharing && otherSharing;

  /// How long ago the other person's busy blocks were uploaded — in whole
  /// days, or null when unknown or within the last day. Their phone refreshes
  /// whenever they open the app, so an old upload means they haven't lately,
  /// and the shared times may be optimistic.
  int? otherStaleDays([DateTime? now]) {
    final synced = otherSyncedAt;
    if (synced == null) return null;
    final days = (now ?? DateTime.now()).difference(synced).inDays;
    return days >= 1 ? days : null;
  }
}

/// "just now", "20 minutes ago", "3 hours ago", "yesterday", "4 days ago".
String agoLabel(DateTime time, [DateTime? now]) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) {
    return diff.inMinutes == 1 ? '1 minute ago' : '${diff.inMinutes} minutes ago';
  }
  if (diff.inHours < 24) return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays} days ago';
}
