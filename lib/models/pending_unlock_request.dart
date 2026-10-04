enum UnlockRequestStatus { pending, approved, denied }

extension UnlockRequestStatusDb on UnlockRequestStatus {
  String get dbValue => switch (this) {
        UnlockRequestStatus.pending => 'pending',
        UnlockRequestStatus.approved => 'approved',
        UnlockRequestStatus.denied => 'denied',
      };
}

UnlockRequestStatus unlockRequestStatusFromDb(String value) => switch (value) {
      'pending' => UnlockRequestStatus.pending,
      'approved' => UnlockRequestStatus.approved,
      'denied' => UnlockRequestStatus.denied,
      _ => throw ArgumentError('Unknown unlock request status: $value'),
    };

/// A Runner's request to a specific Witness for permission to unlock a
/// DNA Rhythm ([RuleItem.isChurchMandated]) so it can be edited or
/// removed like any other rhythm. See
/// supabase/migrations/003_accountability_unlocks.sql.
class PendingUnlockRequest {
  const PendingUnlockRequest({
    required this.id,
    required this.runnerId,
    required this.witnessId,
    required this.ruleItemId,
    required this.ruleItemTitle,
    required this.runnerName,
    required this.status,
    required this.requestedAt,
  });

  /// Expects a query that embedded the Runner's name and the rhythm's
  /// title, e.g.
  /// `select('*, runner:profiles!runner_id(name), rule_item:rule_items!rule_item_id(title)')`
  /// — see RunnerProfile.loadWitnessData.
  factory PendingUnlockRequest.fromRow(Map<String, dynamic> row) => PendingUnlockRequest(
        id: row['id'] as String,
        runnerId: row['runner_id'] as String,
        witnessId: row['witness_id'] as String,
        ruleItemId: row['rule_item_id'] as String,
        ruleItemTitle:
            (row['rule_item'] as Map<String, dynamic>?)?['title'] as String? ?? 'a rhythm',
        runnerName: (row['runner'] as Map<String, dynamic>?)?['name'] as String? ?? 'Your Runner',
        status: unlockRequestStatusFromDb(row['status'] as String),
        requestedAt: DateTime.parse(row['requested_at'] as String),
      );

  final String id;
  final String runnerId;
  final String witnessId;
  final String ruleItemId;
  final String ruleItemTitle;
  final String runnerName;
  final UnlockRequestStatus status;
  final DateTime requestedAt;
}
