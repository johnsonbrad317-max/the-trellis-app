import 'package:flutter/foundation.dart';

/// A Witness paired with a Runner, as visible to Church Admins on the
/// Roster tab — just enough contact info to place a quick call/text.
@immutable
class RosterWitness {
  const RosterWitness({
    required this.name,
    this.phoneNumber,
    this.email,
    required this.hasSharedContact,
  });

  final String name;
  final String? phoneNumber;
  final String? email;

  /// Whether this Witness consented to sharing contact details with this
  /// church (see supabase/migrations/007_witness_church_consent.sql and
  /// 008_gate_witness_contact.sql). [phoneNumber]/[email] are always null
  /// when this is false — the server enforces that — but this flag lets
  /// the UI explain *why* a contact action is disabled instead of leaving
  /// it indistinguishable from "no phone/email on file".
  final bool hasSharedContact;

  factory RosterWitness.fromRow(Map<String, dynamic> row) => RosterWitness(
        name: row['name'] as String,
        phoneNumber: row['phone_number'] as String?,
        email: row['email'] as String?,
        hasSharedContact: row['consent'] as bool? ?? false,
      );
}

/// A Runner's overall spiritual-vitality tier, shown as a status chip on
/// the Church Admin's Roster.
enum VineStatus { fullBloom, budding, drooping }

extension VineStatusLabel on VineStatus {
  String get label => switch (this) {
        VineStatus.fullBloom => 'Full Bloom',
        VineStatus.budding => 'Budding',
        VineStatus.drooping => 'Drooping',
      };
}

/// One row on the Church Admin's Roster — a church-wide, read-only summary
/// of a single Runner and their paired Witness(es).
///
/// This is deliberately a flat mock snapshot rather than a live link into
/// [WatchedRunner]/[RunnerProfile] — a Church Admin oversees the whole
/// congregation, not just the Runners a single Witness watches.
class ChurchRosterEntry {
  const ChurchRosterEntry({
    required this.id,
    required this.runnerName,
    this.runnerPhoneNumber,
    this.runnerEmail,
    required this.witnesses,
    required this.vitalityScore,
    required this.daysSinceLastCheckIn,
  });

  /// [row] is a `church_roster` view row (see
  /// supabase/migrations/002_grants_and_cloud_access.sql).
  factory ChurchRosterEntry.fromRow(Map<String, dynamic> row) {
    final lastCheckIn = row['last_check_in_date'] == null
        ? null
        : DateTime.parse(row['last_check_in_date'] as String);
    final daysSince = lastCheckIn == null
        ? 999
        : DateTime.now().difference(lastCheckIn).inDays;

    return ChurchRosterEntry(
      id: row['runner_id'] as String,
      runnerName: row['runner_name'] as String,
      runnerPhoneNumber: row['runner_phone_number'] as String?,
      runnerEmail: row['runner_email'] as String?,
      witnesses: [
        for (final w in (row['witnesses'] as List<dynamic>? ?? const []))
          RosterWitness.fromRow(w as Map<String, dynamic>),
      ],
      vitalityScore: (row['vitality_score'] as num?)?.toDouble() ?? 0.0,
      daysSinceLastCheckIn: daysSince,
    );
  }

  final String id;
  final String runnerName;
  final String? runnerPhoneNumber;
  final String? runnerEmail;

  /// Empty when the Runner has no active Witness — the "High Isolation
  /// Risk" case the Roster calls out explicitly.
  final List<RosterWitness> witnesses;

  /// 0.0-1.0 average Rule of Life completion, drives [vineStatus].
  final double vitalityScore;
  final int daysSinceLastCheckIn;

  bool get isUnpaired => witnesses.isEmpty;

  /// Never checked in at all (stored as a 999-day gap): not yet started,
  /// which is a different thing from having gone quiet.
  bool get hasNeverCheckedIn => daysSinceLastCheckIn >= 999;

  /// A Runner who WAS checking in and hasn't for over a week — the Roster's
  /// "Dormant Vines" filter. Someone still setting up is not dormant.
  bool get isDormant => daysSinceLastCheckIn > 7 && !hasNeverCheckedIn;

  VineStatus get vineStatus {
    if (vitalityScore >= 0.75) return VineStatus.fullBloom;
    if (vitalityScore >= 0.45) return VineStatus.budding;
    return VineStatus.drooping;
  }

  String get lastCheckInLabel {
    if (daysSinceLastCheckIn <= 0) return 'Checked in today';
    if (daysSinceLastCheckIn == 1) return 'Checked in yesterday';
    return 'Checked in $daysSinceLastCheckIn days ago';
  }
}
