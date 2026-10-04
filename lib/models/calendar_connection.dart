/// The calendar services a person can connect (all via Cronofy on the
/// backend — see supabase/CALENDAR_SETUP.md).
enum CalendarProvider {
  google,
  outlook,
  apple;

  /// The value stored in `calendar_connections.provider` and sent to the
  /// Edge Functions.
  String get dbValue => switch (this) {
        CalendarProvider.google => 'google',
        CalendarProvider.outlook => 'outlook',
        CalendarProvider.apple => 'apple',
      };

  String get label => switch (this) {
        CalendarProvider.google => 'Google Calendar',
        CalendarProvider.outlook => 'Outlook Calendar',
        CalendarProvider.apple => 'Apple Calendar',
      };

  /// The provider for a database value, or null if it isn't one we know.
  static CalendarProvider? fromDb(Object? value) {
    for (final provider in CalendarProvider.values) {
      if (provider.dbValue == value) return provider;
    }
    return null;
  }
}

/// Whether a connection can currently be used.
enum CalendarConnectionStatus {
  active,

  /// The provider rejected our access (password changed, access revoked…);
  /// the person has to connect again.
  needsReauth;

  static CalendarConnectionStatus fromDb(Object? value) =>
      value == 'needs_reauth' ? CalendarConnectionStatus.needsReauth : CalendarConnectionStatus.active;
}

/// One connected calendar, as returned by `get_my_calendar_connections()`.
/// Carries no tokens and no event data.
class CalendarConnection {
  const CalendarConnection({
    required this.provider,
    required this.status,
    required this.connectedAt,
  });

  /// Throws [FormatException] for an unknown provider or malformed row.
  factory CalendarConnection.fromJson(Map<String, dynamic> json) {
    final provider = CalendarProvider.fromDb(json['provider']);
    if (provider == null) {
      throw FormatException('Unknown calendar provider: ${json['provider']}');
    }
    final connectedAt = json['connected_at'];
    return CalendarConnection(
      provider: provider,
      status: CalendarConnectionStatus.fromDb(json['status']),
      connectedAt: connectedAt is String ? DateTime.tryParse(connectedAt)?.toLocal() : null,
    );
  }

  final CalendarProvider provider;
  final CalendarConnectionStatus status;
  final DateTime? connectedAt;

  bool get isActive => status == CalendarConnectionStatus.active;
}

/// A window when both people are free, from `calendar-availability`. Times are
/// local to this device.
class SharedSlot {
  const SharedSlot({required this.start, required this.end});

  /// Throws [FormatException] if either time is missing or unparseable.
  factory SharedSlot.fromJson(Map<String, dynamic> json) {
    final start = json['start'];
    final end = json['end'];
    final parsedStart = start is String ? DateTime.tryParse(start) : null;
    final parsedEnd = end is String ? DateTime.tryParse(end) : null;
    if (parsedStart == null || parsedEnd == null) {
      throw FormatException('Malformed shared slot: $json');
    }
    return SharedSlot(start: parsedStart.toLocal(), end: parsedEnd.toLocal());
  }

  final DateTime start;
  final DateTime end;
}

/// The answer to "when are we both free?" with one other person.
class PairAvailability {
  const PairAvailability({
    required this.suggestions,
    required this.meConnected,
    required this.otherConnected,
    this.rateLimitedForSeconds,
  });

  /// The server (or this device, remembering a recent refusal) says too many
  /// lookups were made; nothing is known about anyone's calendars. Try again
  /// after [retryAfterSeconds].
  const PairAvailability.rateLimited(int retryAfterSeconds)
      : suggestions = const [],
        meConnected = false,
        otherConnected = false,
        rateLimitedForSeconds = retryAfterSeconds;

  /// Tolerant of missing fields (treated as "not connected" / no slots);
  /// malformed individual slots are skipped.
  factory PairAvailability.fromJson(Map<String, dynamic> json) {
    final slots = <SharedSlot>[];
    final raw = json['suggestions'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        try {
          slots.add(SharedSlot.fromJson(item));
        } on FormatException {
          // Skip a malformed slot rather than losing the rest.
        }
      }
    }
    return PairAvailability(
      suggestions: slots,
      meConnected: json['me_connected'] == true,
      otherConnected: json['other_connected'] == true,
    );
  }

  /// Nobody connected / nothing known.
  static const PairAvailability none =
      PairAvailability(suggestions: [], meConnected: false, otherConnected: false);

  final List<SharedSlot> suggestions;
  final bool meConnected;
  final bool otherConnected;

  /// Non-null only for a [PairAvailability.rateLimited] answer.
  final int? rateLimitedForSeconds;

  bool get isRateLimited => rateLimitedForSeconds != null;

  bool get bothConnected => meConnected && otherConnected;

  /// "about a minute" / "about 12 minutes" for a rate-limited answer.
  String get retryAfterLabel {
    final seconds = rateLimitedForSeconds ?? 60;
    if (seconds <= 90) return 'about a minute';
    final minutes = (seconds / 60).ceil();
    return minutes >= 60 ? 'about an hour' : 'about $minutes minutes';
  }
}
