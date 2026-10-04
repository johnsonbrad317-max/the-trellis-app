enum MeetingStatus { pendingResponse, confirmed, declined }

extension MeetingStatusLabel on MeetingStatus {
  String get label => switch (this) {
        MeetingStatus.pendingResponse => 'Pending',
        MeetingStatus.confirmed => 'Confirmed',
        MeetingStatus.declined => 'Declined',
      };
}

extension MeetingStatusDb on MeetingStatus {
  String get dbValue => switch (this) {
        MeetingStatus.pendingResponse => 'pending_response',
        MeetingStatus.confirmed => 'confirmed',
        MeetingStatus.declined => 'declined',
      };
}

MeetingStatus meetingStatusFromDb(String value) => switch (value) {
      'pending_response' => MeetingStatus.pendingResponse,
      'confirmed' => MeetingStatus.confirmed,
      'declined' => MeetingStatus.declined,
      _ => throw ArgumentError('Unknown meeting_status: $value'),
    };

/// A proposed or scheduled meeting between the Runner and one Witness.
class MeetingRequest {
  MeetingRequest({
    required this.id,
    required this.witnessId,
    required this.witnessName,
    required this.time,
    required this.location,
    this.isEmergency = false,
    this.status = MeetingStatus.pendingResponse,
  });

  /// [witnessName] is passed in from the caller's already-loaded witnesses
  /// list rather than joined in the query — `meetings` itself doesn't store
  /// a name snapshot the way the old mock did.
  factory MeetingRequest.fromRow(Map<String, dynamic> row, {required String witnessName}) =>
      MeetingRequest(
        id: row['id'] as String,
        witnessId: row['witness_id'] as String,
        witnessName: witnessName,
        time: DateTime.parse(row['scheduled_time'] as String),
        location: row['location'] as String,
        isEmergency: row['is_emergency'] as bool? ?? false,
        status: meetingStatusFromDb(row['status'] as String),
      );

  Map<String, dynamic> toInsertRow(String runnerId) => {
        'runner_id': runnerId,
        'witness_id': witnessId,
        'scheduled_time': time.toIso8601String(),
        'location': location,
        'is_emergency': isEmergency,
        'status': status.dbValue,
        'proposed_by': 'runner',
      };

  final String id;
  final String witnessId;

  /// Snapshotted at creation so the meeting still reads correctly even if
  /// the Witness is later removed.
  final String witnessName;

  DateTime time;
  String location;
  bool isEmergency;
  MeetingStatus status;
}
