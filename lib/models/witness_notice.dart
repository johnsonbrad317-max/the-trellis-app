/// A one-time note for a Witness, kept by the server in `witness_notices`
/// (supabase/migrations/028_departure_notices.sql) and fetched with
/// `get_my_witness_notices()`. Two kinds: a Runner they walked with deleted
/// their account ([WitnessNoticeKind.runnerLeft]), or removed a rhythm that
/// had settled ([WitnessNoticeKind.rhythmRemoved], migration 034). The departed
/// person's first name is the only thing kept about them, and only for at most
/// 30 days.
///
/// Shown once, as a bookplate dialog, by `showPendingDepartureNotices`
/// (lib/widgets/departure_notice.dart), then marked seen with
/// `mark_witness_notice_seen`.
enum WitnessNoticeKind { runnerLeft, rhythmRemoved }

class WitnessNotice {
  const WitnessNotice({
    required this.id,
    required this.kind,
    required this.runnerFirstName,
    required this.createdAt,
    this.detail,
  });

  final String id;
  final WitnessNoticeKind kind;

  /// The departed Runner's first name, or 'Your Runner' when they had none
  /// (the server's departure_first_name()).
  final String runnerFirstName;
  final DateTime createdAt;

  /// [WitnessNoticeKind.rhythmRemoved]: the removed rhythm's title.
  final String? detail;

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
      'rhythm_removed' => WitnessNoticeKind.rhythmRemoved,
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
      detail: row['detail'] is String && (row['detail'] as String).trim().isNotEmpty
          ? (row['detail'] as String).trim()
          : null,
    );
  }

  /// The dialog's title: "Sarah has left The Trellis".
  String get title => switch (kind) {
        WitnessNoticeKind.runnerLeft => '$runnerFirstName has left The Trellis',
        WitnessNoticeKind.rhythmRemoved => '$runnerFirstName removed a rhythm',
      };

  /// The dialog's body.
  String get message => switch (kind) {
        WitnessNoticeKind.runnerLeft => '$runnerFirstName deleted their account, so everything '
            'they shared — their Rule of Life, check-ins and prayers — was removed with it, '
            'and they no longer appear here. You might reach out to them directly.',
        WitnessNoticeKind.rhythmRemoved => detail == null
            ? '$runnerFirstName removed a rhythm from their Rule of Life. You might ask them '
                'about it.'
            : '$runnerFirstName removed "$detail" from their Rule of Life. You might ask them '
                'about it.',
      };
}
