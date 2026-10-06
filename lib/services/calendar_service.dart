import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../models/calendar_connection.dart';
import '../models/shared_free_windows.dart';
import 'device_calendars.dart';
import 'supabase_client.dart';

/// A calendar operation failed in a way worth telling the person about.
/// [message] is written for display (e.g. in a bookplate notice).
class CalendarServiceException implements Exception {
  const CalendarServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calendar sharing, the on-device way.
///
/// Each person's phone reads the calendars already on it ([DeviceCalendars])
/// and uploads the next few weeks of BUSY BLOCKS — start and end, never a
/// title — to The Trellis (`replace_my_busy_blocks`, migration 025). When
/// someone proposes a meeting, this phone reads its own calendars afresh,
/// fetches the other person's uploaded blocks (`get_pair_calendar`, which
/// answers only for an active Witness pairing) and works out the shared open
/// windows itself ([sharedFreeWindows]). No calendar account is ever connected
/// to The Trellis and no third party is involved.
///
/// Freshness: the upload is redone whenever the app opens or returns to the
/// foreground and the last one is older than [refreshAfter], and whenever the
/// person asks. A partner who hasn't opened the app for days has stale blocks;
/// [PairAvailability.otherStaleDays] lets the screen say so.
///
/// Failure model ("fail soft"): [load], [syncIfStale] and [availabilityWith]
/// never throw — they return false / null and keep cached state. [enable],
/// [refresh] and [disable] throw [CalendarServiceException] with a displayable
/// message, because the person asked for them and needs to hear why not.
class CalendarService extends ChangeNotifier with WidgetsBindingObserver {
  CalendarService._();

  static final CalendarService instance = CalendarService._();

  /// How far ahead busy blocks are uploaded. Suggestions search two weeks
  /// ahead from a 48-hour lead; three weeks leaves room for both.
  static const Duration uploadWindow = Duration(days: 21);

  /// An upload older than this is redone on the next app open or resume.
  static const Duration refreshAfter = Duration(hours: 6);

  /// Swappable for tests.
  @visibleForTesting
  DeviceCalendars device = DeviceCalendars();

  bool _isSharing = false;
  DateTime? _lastSyncedAt;
  List<String> _calendarNames = const [];
  bool _isLoaded = false;
  bool _isBusy = false;
  bool _observing = false;

  /// The user the cached state belongs to, so a sign-out/sign-in as someone
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

  /// Whether this account has uploaded busy blocks from a phone.
  bool get isSharing => _cacheIsCurrent && _isSharing;

  /// When this account last uploaded busy blocks (any device).
  DateTime? get lastSyncedAt => _cacheIsCurrent ? _lastSyncedAt : null;

  /// The calendars found on this phone, once read (empty before that or
  /// without permission).
  List<String> get calendarNames => _cacheIsCurrent ? _calendarNames : const [];

  /// True once [load] has succeeded for the current user.
  bool get isLoaded => _isLoaded && _cacheIsCurrent;

  /// A sync, enable or disable is in flight.
  bool get isBusy => _isBusy;

  void _ensureObserving() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Coming back to the app is the moment to bring the upload up to date.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncIfStale();
  }

  /// Refreshes the sharing state from the server, then redoes the upload if it
  /// is stale. Returns true on success; on failure (offline, signed out)
  /// returns false and keeps the previous state.
  Future<bool> load() async {
    final userId = _currentUserId;
    if (userId == null) return false;
    _ensureObserving();
    try {
      final row = await supabase
          .from('profiles')
          .select('calendar_connected, calendar_synced_at')
          .eq('id', userId)
          .single();
      final syncedAt = _parseTime(row['calendar_synced_at']);
      _isSharing = row['calendar_connected'] == true && syncedAt != null;
      _lastSyncedAt = syncedAt;
      _cachedForUserId = userId;
      _isLoaded = true;
      notifyListeners();
      // Best effort, after the state is known.
      await syncIfStale();
      return true;
    } catch (error) {
      debugPrint('CalendarService.load failed: ${error.runtimeType}');
      return false;
    }
  }

  /// Redoes the upload if sharing is on and the last one is older than
  /// [refreshAfter]. Never throws; a failed refresh keeps the old blocks.
  Future<void> syncIfStale() async {
    if (!isSharing || _isBusy) return;
    final last = _lastSyncedAt;
    if (last != null && DateTime.now().difference(last) < refreshAfter) return;
    try {
      await _upload();
    } catch (error) {
      debugPrint('CalendarService.syncIfStale failed: ${error.runtimeType}');
    }
  }

  /// Turns sharing on: asks the phone for calendar access, then uploads. Throws
  /// [CalendarServiceException] if access was refused or the upload failed.
  Future<void> enable() async {
    _ensureObserving();
    if (!DeviceCalendars.isSupportedPlatform) {
      throw const CalendarServiceException(
        'Calendar sharing works from the app on your phone, where your calendars are.',
      );
    }
    final allowed = await device.requestPermission();
    if (!allowed) {
      throw const CalendarServiceException(
        "Calendar access wasn't allowed. To share your free and busy times, allow Calendars "
        "for The Trellis in your phone's Settings, then try again.",
      );
    }
    await _uploadOrThrow();
  }

  /// Redoes the upload now, at the person's request.
  Future<void> refresh() async {
    if (!await device.hasPermission()) {
      throw const CalendarServiceException(
        "The Trellis no longer has calendar access on this phone. Allow Calendars for The "
        "Trellis in your phone's Settings, then try again.",
      );
    }
    await _uploadOrThrow();
  }

  /// Turns sharing off: removes this account's busy blocks from The Trellis.
  /// (Calendar permission on the phone is the phone's to revoke, in Settings.)
  Future<void> disable() async {
    if (_isBusy) return;
    _isBusy = true;
    notifyListeners();
    try {
      await supabase.rpc('clear_my_busy_blocks');
      _isSharing = false;
      _lastSyncedAt = null;
      _cachedForUserId = _currentUserId;
    } catch (_) {
      throw const CalendarServiceException(
        "Couldn't stop sharing just now. Check your connection and try again.",
      );
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _uploadOrThrow() async {
    if (_isBusy) return;
    try {
      await _upload();
    } on CalendarServiceException {
      rethrow;
    } on PostgrestException catch (error) {
      debugPrint('CalendarService upload refused: ${error.code}');
      throw CalendarServiceException(
        error.code == '42883' || error.code == 'PGRST202'
            ? 'Calendar sharing is not switched on yet on The Trellis\'s side (migration 025). '
                'You can still pick meeting times by hand.'
            : "Couldn't save your busy times. Check your connection and try again.",
      );
    } catch (_) {
      throw const CalendarServiceException(
        "Couldn't save your busy times. Check your connection and try again.",
      );
    }
  }

  /// Reads the phone's calendars and replaces this account's uploaded blocks.
  Future<void> _upload() async {
    final userId = _currentUserId;
    if (userId == null) return;
    _isBusy = true;
    notifyListeners();
    try {
      final now = DateTime.now();
      // From the start of today, so a block already under way still counts.
      final from = DateTime(now.year, now.month, now.day);
      final to = from.add(uploadWindow);
      final blocks = await device.busyBlocks(from: from, to: to);
      if (blocks == null) {
        throw const CalendarServiceException(
          "Couldn't read this phone's calendars. Allow Calendars for The Trellis in your "
          "phone's Settings, then try again.",
        );
      }
      await supabase.rpc('replace_my_busy_blocks', params: {
        'p_blocks': [
          for (final block in blocks)
            {
              'start': block.start.toUtc().toIso8601String(),
              'end': block.end.toUtc().toIso8601String(),
            },
        ],
        'p_window_start': from.toUtc().toIso8601String(),
        'p_window_end': to.toUtc().toIso8601String(),
      });
      _isSharing = true;
      _lastSyncedAt = DateTime.now();
      _cachedForUserId = userId;
      _isLoaded = true;
      _calendarNames = await device.calendarNames();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Times in [from]..[to] when both I and [otherUserId] are free for
  /// [durationMinutes]. My side is read from this phone's calendars right now;
  /// the other side is what their phone uploaded. Returns null if the lookup
  /// failed (offline, server not ready, not paired…); callers then fall back
  /// to manual entry. When either side isn't sharing the result has no
  /// suggestions and says who is missing.
  Future<PairAvailability?> availabilityWith(
    String otherUserId, {
    required DateTime from,
    required DateTime to,
    int durationMinutes = 60,
  }) async {
    try {
      final response = await supabase.rpc('get_pair_calendar', params: {
        'p_other_user_id': otherUserId,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      });
      final json = _asMap(response);
      if (json == null) return null;

      final otherSharing = json['other_connected'] == true;
      final meSharingOnServer = json['me_connected'] == true;
      final meSyncedAt = _parseTime(json['me_synced_at']);
      final otherSyncedAt = _parseTime(json['other_synced_at']);

      // My side comes from the phone itself — fresher than my upload, and
      // the honest answer if permission has since been withdrawn.
      final mine = meSharingOnServer ? await device.busyBlocks(from: from, to: to) : null;
      final meSharing = mine != null;

      if (!(meSharing && otherSharing)) {
        return PairAvailability(
          suggestions: const [],
          meSharing: meSharing,
          otherSharing: otherSharing,
          meSyncedAt: meSyncedAt,
          otherSyncedAt: otherSyncedAt,
        );
      }

      final theirs = parseBusyBlocks(json['other_busy']);
      final windows = sharedFreeWindows(
        busyA: mine,
        busyB: theirs,
        from: from,
        to: to,
        durationMinutes: durationMinutes,
      );
      return PairAvailability(
        suggestions: [for (final window in windows) SharedSlot.fromSpan(window)],
        meSharing: true,
        otherSharing: true,
        meSyncedAt: meSyncedAt,
        otherSyncedAt: otherSyncedAt,
      );
    } catch (error) {
      debugPrint('CalendarService.availabilityWith failed: ${error.runtimeType}');
      return null;
    }
  }

  /// Busy blocks from the server's `[{start, end}]` (ISO strings), as local
  /// spans; malformed entries are skipped.
  @visibleForTesting
  static List<TimeSpan> parseBusyBlocks(Object? raw) {
    if (raw is! List) return const [];
    final spans = <TimeSpan>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final start = _parseTime(item['start']);
      final end = _parseTime(item['end']);
      if (start == null || end == null || !end.isAfter(start)) continue;
      spans.add(TimeSpan(start, end));
    }
    return spans;
  }

  static DateTime? _parseTime(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

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
