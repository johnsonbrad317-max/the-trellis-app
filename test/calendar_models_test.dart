import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:trellis/models/calendar_connection.dart';
import 'package:trellis/models/shared_free_windows.dart';
import 'package:trellis/services/calendar_service.dart';
import 'package:trellis/services/device_calendars.dart';

/// Calendar sharing, the on-device way: the models the screens read, what the
/// phone's events are reduced to before upload, and how the other person's
/// uploaded blocks are read back.
void main() {
  group('SharedSlot', () {
    test('is built from a shared window in local time', () {
      final slot = SharedSlot.fromSpan(
        TimeSpan(DateTime.utc(2026, 10, 6, 17), DateTime.utc(2026, 10, 6, 19)),
      );
      expect(slot.start.toUtc(), DateTime.utc(2026, 10, 6, 17));
      expect(slot.end.toUtc(), DateTime.utc(2026, 10, 6, 19));
      expect(slot.start.isUtc, isFalse);
    });
  });

  group('PairAvailability', () {
    test('both sharing only when both have uploaded', () {
      const both = PairAvailability(suggestions: [], meSharing: true, otherSharing: true);
      const me = PairAvailability(suggestions: [], meSharing: true, otherSharing: false);
      expect(both.bothSharing, isTrue);
      expect(me.bothSharing, isFalse);
      expect(PairAvailability.none.bothSharing, isFalse);
    });

    test("says how stale the other person's upload is, in whole days, from a day on", () {
      final now = DateTime(2026, 10, 12, 9);
      PairAvailability at(DateTime? synced) => PairAvailability(
            suggestions: const [],
            meSharing: true,
            otherSharing: true,
            otherSyncedAt: synced,
          );
      expect(at(null).otherStaleDays(now), isNull);
      expect(at(now.subtract(const Duration(hours: 5))).otherStaleDays(now), isNull);
      expect(at(now.subtract(const Duration(hours: 30))).otherStaleDays(now), 1);
      expect(at(now.subtract(const Duration(days: 4, hours: 2))).otherStaleDays(now), 4);
    });
  });

  group('agoLabel', () {
    final now = DateTime(2026, 10, 12, 9);
    test('reads naturally at every scale', () {
      expect(agoLabel(now.subtract(const Duration(seconds: 20)), now), 'just now');
      expect(agoLabel(now.subtract(const Duration(minutes: 1)), now), '1 minute ago');
      expect(agoLabel(now.subtract(const Duration(minutes: 20)), now), '20 minutes ago');
      expect(agoLabel(now.subtract(const Duration(hours: 1)), now), '1 hour ago');
      expect(agoLabel(now.subtract(const Duration(hours: 3)), now), '3 hours ago');
      expect(agoLabel(now.subtract(const Duration(hours: 30)), now), 'yesterday');
      expect(agoLabel(now.subtract(const Duration(days: 4)), now), '4 days ago');
    });
  });

  group('sharedFreeWindows defaults', () {
    test('a day starts at 6 a.m. (room for a morning coffee) and ends at 8 p.m.', () {
      final from = DateTime(2026, 10, 12);
      final windows = sharedFreeWindows(
        busyA: const [],
        busyB: const [],
        from: from,
        to: from.add(const Duration(days: 1)),
      );
      expect(windows, isNotEmpty);
      expect(windows.first.start, DateTime(2026, 10, 12, 6));
      expect(windows.first.end, DateTime(2026, 10, 12, 20));
    });
  });

  group('CalendarService.parseBusyBlocks', () {
    test('reads the server shape and skips anything malformed', () {
      final blocks = CalendarService.parseBusyBlocks([
        {'start': '2026-10-06T17:00:00+00:00', 'end': '2026-10-06T18:00:00+00:00'},
        {'start': 'nope', 'end': '2026-10-06T18:00:00+00:00'},
        {'start': '2026-10-06T19:00:00+00:00', 'end': '2026-10-06T19:00:00+00:00'},
        'garbage',
        {'start': '2026-10-07T17:00:00+00:00', 'end': '2026-10-07T18:00:00+00:00'},
      ]);
      expect(blocks, hasLength(2));
      expect(blocks.first.start.toUtc(), DateTime.utc(2026, 10, 6, 17));
      expect(blocks.last.end.toUtc(), DateTime.utc(2026, 10, 7, 18));
      expect(CalendarService.parseBusyBlocks(null), isEmpty);
      expect(CalendarService.parseBusyBlocks('[]'), isEmpty);
    });
  });

  group('DeviceCalendars.busyBlocksFrom', () {
    tz.TZDateTime at(int day, int hour, [int minute = 0]) =>
        tz.TZDateTime.utc(2026, 10, day, hour, minute);
    Event event({
      required tz.TZDateTime start,
      required tz.TZDateTime end,
      bool allDay = false,
      Availability availability = Availability.Busy,
    }) =>
        Event('cal-1', start: start, end: end, allDay: allDay, availability: availability);

    final from = DateTime.utc(2026, 10, 6);
    final to = DateTime.utc(2026, 10, 8);

    test('keeps busy and tentative events, drops all-day and free ones and empties', () {
      final blocks = DeviceCalendars.busyBlocksFrom([
        event(start: at(6, 9), end: at(6, 10)),
        event(start: at(6, 11), end: at(6, 12), availability: Availability.Tentative),
        event(start: at(6, 13), end: at(6, 14), availability: Availability.Free),
        event(start: at(7, 0), end: at(8, 0), allDay: true),
        Event('cal-1', start: at(6, 15)),
      ], from: from, to: to);
      expect(blocks.map((b) => '${b.start.toUtc().hour}-${b.end.toUtc().hour}'), ['9-10', '11-12']);
    });

    test('clips to the window and merges overlapping or touching events', () {
      final blocks = DeviceCalendars.busyBlocksFrom([
        event(start: at(5, 22), end: at(6, 1)), // started before the window
        event(start: at(6, 9), end: at(6, 10, 30)),
        event(start: at(6, 10), end: at(6, 11)), // overlaps the one above
        event(start: at(6, 11), end: at(6, 12)), // touches it
        event(start: at(7, 23), end: at(8, 2)), // runs past the window
        event(start: at(9, 9), end: at(9, 10)), // outside altogether
      ], from: from, to: to);
      expect(blocks, hasLength(3));
      expect(blocks[0].start.toUtc(), from);
      expect(blocks[0].end.toUtc(), DateTime.utc(2026, 10, 6, 1));
      expect(blocks[1].start.toUtc(), DateTime.utc(2026, 10, 6, 9));
      expect(blocks[1].end.toUtc(), DateTime.utc(2026, 10, 6, 12));
      expect(blocks[2].end.toUtc(), to);
    });

    test('says nothing about how many events there were', () {
      final one = DeviceCalendars.busyBlocksFrom([event(start: at(6, 9), end: at(6, 12))], from: from, to: to);
      final three = DeviceCalendars.busyBlocksFrom([
        event(start: at(6, 9), end: at(6, 10)),
        event(start: at(6, 10), end: at(6, 11)),
        event(start: at(6, 11), end: at(6, 12)),
      ], from: from, to: to);
      expect(three.length, one.length);
      expect(three.single.start, one.single.start);
      expect(three.single.end, one.single.end);
    });
  });
}
