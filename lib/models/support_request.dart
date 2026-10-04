/// What a Runner is asking their Witness for.
enum SupportRequestKind { prayer, meeting }

extension SupportRequestKindDb on SupportRequestKind {
  String get dbValue => switch (this) {
        SupportRequestKind.prayer => 'prayer',
        SupportRequestKind.meeting => 'meeting',
      };

  String get label => switch (this) {
        SupportRequestKind.prayer => 'Prayer',
        SupportRequestKind.meeting => 'Meeting',
      };
}

SupportRequestKind supportRequestKindFromDb(String value) => switch (value) {
      'prayer' => SupportRequestKind.prayer,
      'meeting' => SupportRequestKind.meeting,
      _ => throw ArgumentError('Unknown support request kind: $value'),
    };

/// How a Runner's attempt to ask for support turned out.
enum SupportRequestOutcome {
  /// At least one Witness was newly asked (and, if they have push on, pinged).
  sent,

  /// The same ask about the same rhythm went out in the last 24 hours — the
  /// server declined to nag the Witness twice.
  alreadyAsked,

  /// This Runner has no active Witness to ask.
  noWitness,
}

/// A Runner's request for prayer or a meeting, as it appears on the Witness it
/// was sent to (`support_requests`, supabase/migrations/014). Created only by
/// the `create_support_request` RPC; the Witness acknowledges it.
class SupportRequest {
  const SupportRequest({
    required this.id,
    required this.runnerId,
    required this.runnerName,
    required this.kind,
    required this.createdAt,
    this.ruleItemTitle,
    this.note,
  });

  /// [row] is a `support_requests` row selected with
  /// `runner:profiles!runner_id(name), rule_item:rule_items!rule_item_id(title)`.
  factory SupportRequest.fromRow(Map<String, dynamic> row) => SupportRequest(
        id: row['id'] as String,
        runnerId: row['runner_id'] as String,
        runnerName: (row['runner'] as Map<String, dynamic>?)?['name'] as String? ?? 'A Runner',
        kind: supportRequestKindFromDb(row['kind'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
        ruleItemTitle: (row['rule_item'] as Map<String, dynamic>?)?['title'] as String?,
        note: row['note'] as String?,
      );

  final String id;
  final String runnerId;
  final String runnerName;
  final SupportRequestKind kind;
  final DateTime createdAt;

  /// The rhythm the Runner was looking at when they asked, if any.
  final String? ruleItemTitle;
  final String? note;

  String get firstName => runnerName.trim().split(' ').first;

  /// "Ruth is asking you to pray about "Read Scripture"." / "… would like to
  /// meet."
  String get summary {
    final about = ruleItemTitle == null ? '' : ' about "$ruleItemTitle"';
    return switch (kind) {
      SupportRequestKind.prayer => '$runnerName is asking you to pray$about.',
      SupportRequestKind.meeting => '$runnerName would like to meet$about.',
    };
  }
}
