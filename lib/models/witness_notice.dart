/// A one-time note for a Witness, kept by the server in `witness_notices`
/// (supabase/migrations/028_departure_notices.sql) and fetched with
/// `get_my_witness_notices()`. Today there is one kind: a Runner they walked
/// with deleted their account ([WitnessNoticeKind.runnerLeft]). The departed
/// person's first name is the only thing kept about them, and only for at most
/// 30 days.
///
/// Shown once, as a bookplate dialog, by `showPendingDepartureNotices`
/// (lib/widgets/departure_notice.dart), then marked seen with
/// `mark_witness_notice_seen`.
enum WitnessNoticeKind { runnerLeft }

class WitnessNotice {
  const WitnessNotice({
    required this.id,
    required this.kind,
    required this.runnerFirstName,
    required this.createdAt,
  });

  final String id;
  final WitnessNoticeKind kind;

  /// The departed Runner's first name, or 'Your Runner' when they had none
  /// (the server's departure_first_name()).
  final String runnerFirstName;
  final DateTime createdAt;

  /// The fallback the server uses when a Runner had no name — also used here
  /// should a row ever arrive with a blank one.
  static const fallbackFirstName = 'Your Runner';

  /// One row of `get_my_witness_notices()`, or null for a row this build does
  /// not understand (an unknown kind from a newer server, a missing id) —
  /// which is then simply never shown.
  static WitnessNotice? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is! String || id.isEmpty) return null;
    final kind = switch (row['kind']) {
      'runner_left' => WitnessNoticeKind.runnerLeft,
      _ => null,
    };
    if (kind == null) return null;
    final name = row['runner_first_name'];
    final created = row['created_at'];
    return WitnessNotice(
      id: id,
      kind: kind,
      runnerFirstName:
          name is String && name.trim().isNotEmpty ? name.trim() : fallbackFirstName,
      createdAt: (created is String ? DateTime.tryParse(created) : null) ?? DateTime.now(),
    );
  }

  /// The dialog's title: "Sarah has left The Trellis".
  String get title => '$runnerFirstName has left The Trellis';

  /// The dialog's body.
  String get message => '$runnerFirstName deleted their account, so everything they '
      'shared — their Rule of Life, check-ins and prayers — was removed with it, '
      'and they no longer appear here. Nothing you did caused this. You might '
      'reach out to them directly.';
}
