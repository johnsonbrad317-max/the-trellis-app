import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';

import '../models/shared_free_windows.dart';

/// What this phone's calendars say about when their owner is busy.
///
/// Reads every calendar the phone already has — iCloud, Google, Outlook,
/// Exchange, whatever the person has signed into on the device — through the
/// phone's own calendar store (EventKit on iOS, CalendarContract on Android).
/// No account is ever connected to The Trellis, and nothing leaves this class
/// but [TimeSpan]s: start and end, never a title, place or guest.
///
/// Permission: the phone asks once, with the purpose strings in
/// ios/Runner/Info.plist and the READ/WRITE_CALENDAR entries in the Android
/// manifest. If it is refused, every read answers "nothing known" rather than
/// throwing; the caller decides what to say.
class DeviceCalendars {
  /// [plugin] is for tests; the app lets the real one be created lazily.
  DeviceCalendars({DeviceCalendarPlugin? plugin}) {
    _plugin = plugin;
  }

  /// Created lazily: constructing the plugin initialises the timezone
  /// database, which widget tests and the web build never need.
  DeviceCalendarPlugin? _plugin;
  DeviceCalendarPlugin get _calendar => _plugin ??= DeviceCalendarPlugin();

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Whether the phone currently allows reading its calendars. False on
  /// platforms without calendars and whenever the plugin can't say.
  Future<bool> hasPermission() async {
    if (!isSupportedPlatform) return false;
    try {
      final result = await _calendar.hasPermissions();
      return result.isSuccess && (result.data ?? false);
    } catch (error) {
      debugPrint('DeviceCalendars.hasPermission failed: $error');
      return false;
    }
  }

  /// Asks the phone for calendar access (no prompt if already decided).
  /// Returns whether access is now allowed.
  Future<bool> requestPermission() async {
    if (!isSupportedPlatform) return false;
    try {
      final result = await _calendar.requestPermissions();
      return result.isSuccess && (result.data ?? false);
    } catch (error) {
      debugPrint('DeviceCalendars.requestPermission failed: $error');
      return false;
    }
  }

  /// The names of the calendars on this phone, for showing the person what
  /// is being read ("Home", "Work", "Family"). Empty without permission.
  Future<List<String>> calendarNames() async {
    final calendars = await _calendars();
    return [
      for (final calendar in calendars)
        if (calendar.name != null && calendar.name!.trim().isNotEmpty) calendar.name!.trim(),
    ];
  }

  /// The merged busy blocks across every calendar on the phone between
  /// [from] and [to], or null if the calendars could not be read (no
  /// permission, unsupported platform, plugin failure). An empty list is a
  /// real answer: nothing on the calendar.
  Future<List<TimeSpan>?> busyBlocks({required DateTime from, required DateTime to}) async {
    if (!isSupportedPlatform || to.isBefore(from)) return null;
    if (!await hasPermission()) return null;
    final calendars = await _calendars();
    final events = <Event>[];
    for (final calendar in calendars) {
      final id = calendar.id;
      if (id == null) continue;
      try {
        final result = await _calendar.retrieveEvents(
          id,
          RetrieveEventsParams(startDate: from, endDate: to),
        );
        if (result.isSuccess && result.data != null) events.addAll(result.data!);
      } catch (error) {
        // One unreadable calendar (a subscribed holiday feed, say) must not
        // hide the rest.
        debugPrint('DeviceCalendars: could not read calendar ${calendar.name}: $error');
      }
    }
    return busyBlocksFrom(events, from: from, to: to);
  }

  Future<List<Calendar>> _calendars() async {
    if (!isSupportedPlatform) return const [];
    try {
      final result = await _calendar.retrieveCalendars();
      if (!result.isSuccess || result.data == null) return const [];
      return result.data!.toList();
    } catch (error) {
      debugPrint('DeviceCalendars.retrieveCalendars failed: $error');
      return const [];
    }
  }

  /// Pure, for tests: the busy blocks a list of calendar events amounts to.
  ///
  /// Skipped: all-day events (birthdays, holidays, "out of office" banners —
  /// they rarely mean the person cannot meet), events the calendar marks as
  /// free time, and events with no start or end. Everything else counts as
  /// busy, tentative included. Blocks are clipped to [from]..[to] and merged
  /// where they overlap or touch, so the result says nothing about how many
  /// events there were.
  @visibleForTesting
  static List<TimeSpan> busyBlocksFrom(
    Iterable<Event> events, {
    required DateTime from,
    required DateTime to,
  }) {
    final spans = <TimeSpan>[];
    for (final event in events) {
      if (event.allDay ?? false) continue;
      if (event.availability == Availability.Free) continue;
      final start = event.start;
      final end = event.end;
      if (start == null || end == null) continue;
      // Compared as instants and re-expressed as plain local DateTimes (the
      // plugin's TZDateTime.toLocal needs the timezone database to have been
      // set up, which the pure path here must not depend on).
      final clippedStart = start.isBefore(from) ? from : _asLocal(start);
      final clippedEnd = end.isAfter(to) ? to : _asLocal(end);
      if (!clippedEnd.isAfter(clippedStart)) continue;
      spans.add(TimeSpan(clippedStart, clippedEnd));
    }
    return mergeBusyBlocks(spans);
  }

  static DateTime _asLocal(DateTime time) =>
      DateTime.fromMillisecondsSinceEpoch(time.millisecondsSinceEpoch);
}
