/// One Runner flagged on the Cloud's "Needs Attention" list. Only what a
/// pastoral follow-up needs: who, and the one number that put them there —
/// never a check-in answer.
class TriageRunner {
  const TriageRunner({
    required this.id,
    required this.name,
    this.score,
    this.isDrooping = false,
    this.daysInChurch,
    this.daysSinceCheckIn,
  });

  factory TriageRunner.fromJson(Map<String, dynamic> json) => TriageRunner(
        id: json['runner_id'] as String,
        name: json['name'] as String,
        score: (json['score'] as num?)?.toDouble(),
        isDrooping: json['is_drooping'] as bool? ?? false,
        daysInChurch: (json['days_in_church'] as num?)?.toInt(),
        daysSinceCheckIn: (json['days_since_check_in'] as num?)?.toInt(),
      );

  final String id;
  final String name;

  /// Season consistency (0.0-1.0) for a struggling Runner.
  final double? score;

  /// An Anchor Rhythm has been missed three or more times running.
  final bool isDrooping;
  final int? daysInChurch;

  /// Null for a Runner who has never checked in.
  final int? daysSinceCheckIn;

  String get firstName => name.trim().split(' ').first;
}

/// A Witness currently walking with a struggling Runner. Contact details are
/// present only where that pairing carries the Witness's consent to share
/// them with the church (supabase/migrations/007, 008).
class TriageWitness {
  const TriageWitness({
    required this.id,
    required this.name,
    required this.runnerCount,
    required this.hasSharedContact,
    this.phoneNumber,
    this.email,
  });

  factory TriageWitness.fromJson(Map<String, dynamic> json) => TriageWitness(
        id: json['witness_id'] as String,
        name: json['name'] as String,
        runnerCount: (json['runner_count'] as num?)?.toInt() ?? 1,
        hasSharedContact: json['consent'] as bool? ?? false,
        phoneNumber: json['phone_number'] as String?,
        email: json['email'] as String?,
      );

  final String id;
  final String name;
  final int runnerCount;
  final bool hasSharedContact;
  final String? phoneNumber;
  final String? email;

  String get firstName => name.trim().split(' ').first;
}

/// The Cloud's live "Needs Attention" list, as computed by `get_cloud_triage`
/// (supabase/migrations/013) from the strict 180-day consistency score.
class CloudTriage {
  const CloudTriage({
    required this.struggling,
    required this.isolated,
    required this.dormant,
    required this.witnessAlerts,
    this.strugglingBelow = 0.45,
    this.staleDays = 7,
  });

  const CloudTriage.empty()
      : struggling = const [],
        isolated = const [],
        dormant = const [],
        witnessAlerts = const [],
        strugglingBelow = 0.45,
        staleDays = 7;

  factory CloudTriage.fromJson(Map<String, dynamic> json) {
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) build) => [
          for (final row in (json[key] as List<dynamic>? ?? const []))
            build(row as Map<String, dynamic>),
        ];
    final thresholds = json['thresholds'] as Map<String, dynamic>? ?? const {};

    return CloudTriage(
      struggling: parse('struggling', TriageRunner.fromJson),
      isolated: parse('isolated', TriageRunner.fromJson),
      dormant: parse('dormant', TriageRunner.fromJson),
      witnessAlerts: parse('witness_alerts', TriageWitness.fromJson),
      strugglingBelow: (thresholds['struggling_below'] as num?)?.toDouble() ?? 0.45,
      staleDays: (thresholds['stale_days'] as num?)?.toInt() ?? 7,
    );
  }

  final List<TriageRunner> struggling;
  final List<TriageRunner> isolated;
  final List<TriageRunner> dormant;
  final List<TriageWitness> witnessAlerts;

  /// The score under which a Runner counts as struggling, and how many days
  /// without a check-in counts as dormant — echoed from the server so the
  /// screen's wording can never drift from the rule that produced the list.
  final double strugglingBelow;
  final int staleDays;

  bool get isEmpty =>
      struggling.isEmpty && isolated.isEmpty && dormant.isEmpty && witnessAlerts.isEmpty;
}
