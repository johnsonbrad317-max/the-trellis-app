import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:url_launcher/url_launcher.dart';

import '../models/calendar_connection.dart';
import 'supabase_client.dart';

/// A calendar operation failed in a way worth telling the person about.
/// [message] is written for display (e.g. in a bookplate notice).
class CalendarServiceException implements Exception {
  const CalendarServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The app's window onto calendar availability. All the heavy lifting —
/// OAuth, tokens, free/busy, intersecting two people's calendars — happens in
/// the Supabase Edge Functions (calendar-connect-start, calendar-disconnect,
/// calendar-availability); this class only invokes them and caches which of
/// MY calendars are connected.
///
/// Privacy: nothing here ever receives anyone's busy blocks or event details,
/// nor which provider the other person uses — only shared open windows.
///
/// Failure model ("fail soft"): [load], [availabilityWith] and [pairStatus]
/// never throw — they return false / null on any failure and leave cached state
/// untouched. [connect] and [disconnect] throw [CalendarServiceException]
/// (with a displayable message) because the person asked for them and needs
/// to hear why it didn't work.
class CalendarService extends ChangeNotifier with WidgetsBindingObserver {
  CalendarService._();

  static final CalendarService instance = CalendarService._();

  List<CalendarConnection> _connections = const [];
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _observing = false;

  /// The user the cached list belongs to, so a sign-out/sign-in as someone
  /// else never shows the previous person's calendars.
  String? _cachedForUserId;

  String? get _currentUserId {
    try {
      return supabase.auth.currentUser?.id;
    } catch (_) {
      // Supabase not initialised (e.g. in a widget test).
      return null;
    }
  }

  bool get _cacheIsCurrent => _cachedForUserId != null && _cachedForUserId == _currentUserId;

  /// The signed-in user's connected calendars (empty until [load] succeeds).
  List<CalendarConnection> get connections => _cacheIsCurrent ? _connections : const [];

  /// True once [load] has succeeded for the current user.
  bool get isLoaded => _isLoaded && _cacheIsCurrent;

  bool get isLoading => _isLoading;

  /// True if at least one calendar is connected and usable.
  bool get hasActiveConnection => connections.any((c) => c.isActive);

  CalendarConnection? connectionFor(CalendarProvider provider) {
    for (final connection in connections) {
      if (connection.provider == provider) return connection;
    }
    return null;
  }

  void _ensureObserving() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// The OAuth round trip happens in the external browser; when the person
  /// comes back to the app, pick up whatever changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The observer is only registered once something has used this service
    // (load/connect), and load() is a no-op when signed out.
    if (state == AppLifecycleState.resumed) {
      load();
    }
  }

  /// Refreshes [connections] from the server. Returns true on success; on
  /// failure (offline, signed out) returns false and keeps the previous list.
  Future<bool> load() async {
    if (_isLoading) return false;
    final userId = _currentUserId;
    if (userId == null) return false;
    _ensureObserving();

    _isLoading = true;
    notifyListeners();
    try {
      final rows = await supabase.rpc('get_my_calendar_connections');
      final parsed = <CalendarConnection>[];
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map) continue;
          try {
            parsed.add(CalendarConnection.fromJson(Map<String, dynamic>.from(row)));
          } on FormatException {
            // A provider this build doesn't know about — ignore it.
          }
        }
      }
      _connections = parsed;
      _cachedForUserId = userId;
      _isLoaded = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Starts connecting [provider]: asks the server for a signed authorise URL
  /// and opens it in the external browser. Resolves once the browser has been
  /// launched (the connection itself completes later — [load] runs when the
  /// app resumes). Throws [CalendarServiceException] on failure.
  Future<void> connect(CalendarProvider provider) async {
    _ensureObserving();
    final Object? data;
    try {
      final response = await supabase.functions.invoke(
        'calendar-connect-start',
        body: {'provider': provider.dbValue},
      );
      data = response.data;
    } catch (_) {
      throw const CalendarServiceException(
        "Couldn't start the calendar connection. Check your connection and try again.",
      );
    }

    final json = _asMap(data);
    final raw = json?['authorize_url'];
    final uri = raw is String ? Uri.tryParse(raw) : null;
    if (uri == null || uri.scheme != 'https') {
      throw const CalendarServiceException(
        'Calendar connection is not available right now. Please try again later.',
      );
    }

    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      throw const CalendarServiceException("Couldn't open your browser to connect the calendar.");
    }
  }

  /// Disconnects [provider] (the server revokes access and deletes the stored
  /// tokens), then refreshes [connections]. Throws [CalendarServiceException]
  /// on failure.
  Future<void> disconnect(CalendarProvider provider) async {
    try {
      await supabase.functions.invoke(
        'calendar-disconnect',
        body: {'provider': provider.dbValue},
      );
    } catch (_) {
      throw const CalendarServiceException(
        "Couldn't disconnect that calendar. Check your connection and try again.",
      );
    }
    await load();
  }

  /// Times in [from]..[to] when both I and [otherUserId] are free for
  /// [durationMinutes], as shared open windows only. Returns null if the
  /// request failed (offline, server not configured, not paired…); callers
  /// should then fall back to manual entry. When either person has no calendar
  /// connected the result has no suggestions and says who is missing.
  ///
  /// If the server has refused for too many lookups (HTTP 429), the answer is a
  /// [PairAvailability.rateLimited] saying when to try again — and this device
  /// remembers it, so a person tapping around doesn't keep asking while blocked.
  Future<PairAvailability?> availabilityWith(
    String otherUserId, {
    required DateTime from,
    required DateTime to,
    int durationMinutes = 60,
  }) async {
    final blockedUntil = _availabilityBlockedUntil;
    // The limit is per signed-in person; a different user on this device starts clean.
    if (blockedUntil != null && _availabilityBlockedForUserId == _currentUserId) {
      final remaining = blockedUntil.difference(DateTime.now()).inSeconds;
      if (remaining > 0) return PairAvailability.rateLimited(remaining);
      _availabilityBlockedUntil = null;
    }

    try {
      final response = await supabase.functions.invoke(
        'calendar-availability',
        body: {
          'other_user_id': otherUserId,
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
          'duration_minutes': durationMinutes,
          // Dart's DateTime.timeZoneName is not an IANA id, so send the UTC
          // offset (minutes, east positive) at the start of the window; the
          // server prefers it over any tzid.
          'tz_offset_minutes': from.timeZoneOffset.inMinutes,
        },
      );
      final json = _asMap(response.data);
      if (json == null) return null;
      return PairAvailability.fromJson(json);
    } on FunctionException catch (error) {
      if (error.status != 429) return null;
      final seconds = retryAfterSecondsFrom(error.details);
      _availabilityBlockedUntil = DateTime.now().add(Duration(seconds: seconds));
      _availabilityBlockedForUserId = _currentUserId;
      return PairAvailability.rateLimited(seconds);
    } catch (_) {
      return null;
    }
  }

  /// Until when the server last told this device to stop asking for shared
  /// times (a 429); null when not blocked.
  DateTime? _availabilityBlockedUntil;
  String? _availabilityBlockedForUserId;

  /// The wait, in whole seconds, from a 429 body such as
  /// `{error, code: rate_limited, retry_after_seconds: 42}`. Missing or
  /// nonsense values mean a minute; anything is held to between 1 second and
  /// an hour so a bad value can never lock the feature away.
  @visibleForTesting
  static int retryAfterSecondsFrom(Object? details) {
    final raw = _asMap(details)?['retry_after_seconds'];
    if (raw is! num || !raw.isFinite || raw < 1) return 60;
    return raw.ceil().clamp(1, 3600);
  }

  /// Whether I and [otherUserId] have a calendar connected, without fetching
  /// any times. Only answers for an active pairing (otherwise both false).
  /// Returns null on failure. The result never has suggestions.
  Future<PairAvailability?> pairStatus(String otherUserId) async {
    try {
      final rows = await supabase.rpc(
        'get_calendar_pair_status',
        params: {'p_other_user_id': otherUserId},
      );
      final row = rows is List && rows.isNotEmpty ? rows.first : rows;
      final json = _asMap(row);
      if (json == null) return null;
      return PairAvailability(
        suggestions: const [],
        meConnected: json['me_connected'] == true,
        otherConnected: json['other_connected'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
