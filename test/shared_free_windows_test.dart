// Tests for lib/models/shared_free_windows.dart, the Dart port of the Edge
// Function helper supabase/functions/_shared/availability.ts. The first group
// mirrors availability_test.ts case for case (with local DateTimes standing in
// for "UTC + offset 0"); the rest pin behaviours the phone relies on.
//
// All times are fixed local DateTimes so the results do not depend on the
// machine's zone (the daily window is read off the same local clock).

import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/shared_free_windows.dart';

/// 2026-10-06 (a Tuesday) at the given local hour and minute.
DateTime oct(int day, [int hour = 0, int minute = 0]) =>
    DateTime(2026, 10, day, hour, minute);

TimeSpan span(DateTime start, DateTime end) => TimeSpan(start, end);

/// Shorthand for a busy block or window on one day.
TimeSpan at(int day, int h1, int m1, int h2, int m2) =>
    TimeSpan(oct(day, h1, m1), oct(day, h2, m2));

List<TimeSpan> windows({
  List<TimeSpan> busyA = const [],
  List<TimeSpan> busyB = const [],
  required DateTime from,
  required DateTime to,
  int durationMinutes = 60,
  int dayStartHour = 8,
  int dayEndHour = 20,
  int maxSuggestions = 20,
  int maxPerDay = 0,
}) =>
    sharedFreeWindows(
      busyA: busyA,
      busyB: busyB,
      from: from,
      to: to,
      durationMinutes: durationMinutes,
      dayStartHour: dayStartHour,
      dayEndHour: dayEndHour,
      maxSuggestions: maxSuggestions,
      maxPerDay: maxPerDay,
    );

void main() {
  group('TimeSpan', () {
    test('equality compares instants, not zones', () {
      final local = oct(6, 9);
      expect(
        TimeSpan(local, oct(6, 10)),
        TimeSpan(local.toUtc(), oct(6, 10).toUtc()),
      );
      expect(TimeSpan(local, oct(6, 10)).hashCode,
          TimeSpan(local.toUtc(), oct(6, 10).toUtc()).hashCode);
      expect(TimeSpan(local, oct(6, 10)), isNot(TimeSpan(local, oct(6, 11))));
      expect(TimeSpan(local, oct(6, 10)).duration, const Duration(hours: 1));
    });
  });

  // ---------------------------------------------------------------------------
  // Mirrors of availability_test.ts
  // ---------------------------------------------------------------------------
  group('mirrors of the Edge Function tests', () {
    // The TS tests use small integer "times"; minutes after midnight play that
    // role here.
    DateTime m(int minutes) => oct(6, 0, minutes);
    TimeSpan s(int a, int b) => TimeSpan(m(a), m(b));

    test('mergeSpans merges overlapping and touching spans and drops empties',
        () {
      expect(
        mergeSpans([s(50, 60), s(0, 10), s(5, 20), s(20, 30), s(40, 40)]),
        [s(0, 30), s(50, 60)],
      );
    });

    test('mergeSpans does not mutate its input', () {
      final input = [s(5, 20), s(0, 10)];
      mergeSpans(input);
      expect(input, [s(5, 20), s(0, 10)]);
    });

    test('invertSpans returns the gaps inside the window', () {
      expect(
        invertSpans([s(10, 20), s(30, 90)], m(0), m(50)),
        [s(0, 10), s(20, 30)],
      );
      expect(invertSpans([], m(0), m(50)), [s(0, 50)]);
      expect(invertSpans([s(-5, 100)], m(0), m(50)), isEmpty);
    });

    test('intersectSpans keeps only the overlap', () {
      expect(
        intersectSpans(
          [s(0, 10), s(20, 40)],
          [s(5, 25), s(30, 35)],
        ),
        [s(5, 10), s(20, 25), s(30, 35)],
      );
    });

    test('two empty calendars: the whole daily window is shared', () {
      expect(
        windows(from: oct(6), to: oct(7)),
        [at(6, 8, 0, 20, 0)],
      );
    });

    test('busy blocks from either person are removed; short gaps are dropped',
        () {
      // A busy 09:00-11:00; B busy 10:00-12:00 and 12:30-18:00 (leaves a 30
      // minute gap, shorter than the 60 minute meeting).
      expect(
        windows(
          busyA: [at(6, 9, 0, 11, 0)],
          busyB: [at(6, 10, 0, 12, 0), at(6, 12, 30, 18, 0)],
          from: oct(6),
          to: oct(7),
        ),
        [at(6, 8, 0, 9, 0), at(6, 18, 0, 20, 0)],
      );
    });

    test('window start is rounded up to the next quarter hour', () {
      expect(
        windows(
          busyA: [at(6, 8, 0, 10, 7)],
          from: oct(6),
          to: oct(7),
        ),
        [at(6, 10, 15, 20, 0)],
      );
    });

    test('a search window that starts the evening before yields two days',
        () {
      // The TS "UTC offset" test seen from the local clock: from is 19:00 on
      // Oct 5, so Oct 5 contributes 19:00-20:00 and Oct 6 08:00-19:00.
      expect(
        windows(from: oct(5, 19), to: oct(6, 19)),
        [at(5, 19, 0, 20, 0), at(6, 8, 0, 19, 0)],
      );
    });

    test('maxSuggestions and maxPerDay limit the output', () {
      final busyA = [at(6, 12, 0, 13, 0)];
      final busyB = [at(6, 16, 0, 17, 0)];
      // Day 1 has three windows (8-12, 13-16, 17-20); day 2 has one.
      expect(
        windows(busyA: busyA, busyB: busyB, from: oct(6), to: oct(8)).length,
        4,
      );
      expect(
        windows(
          busyA: busyA,
          busyB: busyB,
          from: oct(6),
          to: oct(8),
          maxSuggestions: 2,
        ).length,
        2,
      );
      final capped = windows(
        busyA: busyA,
        busyB: busyB,
        from: oct(6),
        to: oct(8),
        maxPerDay: 1,
      );
      expect(capped.map((w) => w.start), [oct(6, 8), oct(7, 8)]);
    });

    test('maxSuggestions of 0 / negative returns nothing', () {
      expect(windows(from: oct(6), to: oct(7), maxSuggestions: 0), isEmpty);
      expect(windows(from: oct(6), to: oct(7), maxSuggestions: -1), isEmpty);
    });

    test('unsorted, overlapping, zero-length and inverted busy blocks', () {
      expect(
        windows(
          busyA: [
            at(6, 15, 0, 16, 0),
            at(6, 9, 0, 11, 0),
            at(6, 10, 30, 12, 0),
            at(6, 13, 0, 13, 0),
            at(6, 14, 0, 8, 0),
          ],
          from: oct(6),
          to: oct(7),
        ),
        [at(6, 8, 0, 9, 0), at(6, 12, 0, 15, 0), at(6, 16, 0, 20, 0)],
      );
    });

    test('a fully busy person leaves no suggestions', () {
      expect(
        windows(
          busyA: [span(oct(5), oct(9))],
          from: oct(6),
          to: oct(8),
        ),
        isEmpty,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Behaviours the phone relies on
  // ---------------------------------------------------------------------------
  group('sharedFreeWindows', () {
    test('touching busy blocks merge so the gap between them is not free', () {
      expect(
        windows(
          busyA: [at(6, 9, 0, 10, 0), at(6, 10, 0, 11, 0)],
          from: oct(6),
          to: oct(7),
        ),
        [at(6, 8, 0, 9, 0), at(6, 11, 0, 20, 0)],
      );
      expect(
        mergeSpans([at(6, 10, 0, 11, 0), at(6, 9, 0, 10, 0)]),
        [at(6, 9, 0, 11, 0)],
      );
    });

    test('a busy block spanning midnight clips both days', () {
      expect(
        windows(
          busyA: [span(oct(6, 18), oct(7, 10))],
          from: oct(6),
          to: oct(8),
        ),
        [at(6, 8, 0, 18, 0), at(7, 10, 0, 20, 0)],
      );
    });

    test('both completely free: one window per day at dayStartHour', () {
      final out = sharedFreeWindows(
        busyA: const [],
        busyB: const [],
        from: oct(6),
        to: oct(9),
      );
      expect(out, [at(6, 8, 0, 20, 0), at(7, 8, 0, 20, 0), at(8, 8, 0, 20, 0)]);
      for (final w in out) {
        expect(w.start.hour, 8);
        expect(w.start.minute, 0);
      }
    });

    test('the default maxPerDay keeps the first three windows of a day', () {
      // Four gaps on Oct 6: 8-9, 10-11, 12-13, 14-20. Default maxPerDay = 3
      // keeps the first three; Oct 7 still gets its own.
      final out = sharedFreeWindows(
        busyA: [at(6, 9, 0, 10, 0), at(6, 11, 0, 12, 0), at(6, 13, 0, 14, 0)],
        busyB: const [],
        from: oct(6),
        to: oct(8),
      );
      expect(out, [
        at(6, 8, 0, 9, 0),
        at(6, 10, 0, 11, 0),
        at(6, 12, 0, 13, 0),
        at(7, 8, 0, 20, 0),
      ]);
    });

    test('one person fully busy leaves nothing', () {
      expect(
        windows(
          busyB: [span(oct(6), oct(8))],
          from: oct(6),
          to: oct(8),
        ),
        isEmpty,
      );
    });

    test('a free span starting 9:07 yields 9:15', () {
      expect(
        windows(
          busyA: [at(6, 8, 0, 9, 7)],
          from: oct(6),
          to: oct(7),
        ),
        [at(6, 9, 15, 20, 0)],
      );
      // Already on a quarter hour: left alone.
      expect(
        windows(busyA: [at(6, 8, 0, 9, 30)], from: oct(6), to: oct(7)),
        [at(6, 9, 30, 20, 0)],
      );
    });

    test('rounding happens before the duration check', () {
      // 9:07-10:07 is 60 minutes, but after rounding to 9:15 only 52 remain.
      expect(
        windows(
          busyA: [at(6, 8, 0, 9, 7), at(6, 10, 7, 20, 0)],
          from: oct(6),
          to: oct(7),
        ),
        isEmpty,
      );
    });

    test('windows shorter than the duration are dropped', () {
      final busyA = [at(6, 8, 0, 9, 0), at(6, 9, 45, 20, 0)];
      expect(
        windows(busyA: busyA, from: oct(6), to: oct(7), durationMinutes: 60),
        isEmpty,
      );
      expect(
        windows(busyA: busyA, from: oct(6), to: oct(7), durationMinutes: 45),
        [at(6, 9, 0, 9, 45)],
      );
      expect(
        windows(busyA: busyA, from: oct(6), to: oct(7), durationMinutes: 30),
        [at(6, 9, 0, 9, 45)],
      );
    });

    test('a zero or negative duration is treated as one minute', () {
      // The only gap is 09:00-09:10.
      final busyA = [at(6, 8, 0, 9, 0), at(6, 9, 10, 20, 0)];
      expect(
        windows(busyA: busyA, from: oct(6), to: oct(7), durationMinutes: 0),
        [at(6, 9, 0, 9, 10)],
      );
      expect(
        windows(busyA: busyA, from: oct(6), to: oct(7), durationMinutes: -30),
        [at(6, 9, 0, 9, 10)],
      );
      // ...but a gap shorter than a minute still fails.
      expect(
        windows(
          busyA: [at(6, 8, 0, 9, 0), span(oct(6, 9, 0).add(const Duration(seconds: 30)), oct(6, 20))],
          from: oct(6),
          to: oct(7),
          durationMinutes: 0,
        ),
        isEmpty,
      );
    });

    test('maxSuggestions caps the list in chronological order', () {
      final out = windows(from: oct(6), to: oct(13), maxSuggestions: 3);
      expect(out, [at(6, 8, 0, 20, 0), at(7, 8, 0, 20, 0), at(8, 8, 0, 20, 0)]);
      expect(windows(from: oct(6), to: oct(13), maxSuggestions: 1).length, 1);
      // The function's own default is 8.
      expect(
        sharedFreeWindows(
          busyA: const [],
          busyB: const [],
          from: oct(6),
          to: oct(26),
        ).length,
        8,
      );
    });

    test('from == to and to < from give nothing', () {
      expect(windows(from: oct(6, 9), to: oct(6, 9)), isEmpty);
      expect(windows(from: oct(7), to: oct(6)), isEmpty);
    });

    test('busy blocks outside the search window are ignored', () {
      expect(
        windows(
          busyA: [at(5, 9, 0, 17, 0), at(7, 9, 0, 17, 0)],
          busyB: [span(oct(1), oct(6)), span(oct(7), oct(20))],
          from: oct(6),
          to: oct(7),
        ),
        [at(6, 8, 0, 20, 0)],
      );
    });

    test('a window is clipped to the search window, not just the day', () {
      expect(
        windows(from: oct(6, 9, 30), to: oct(6, 14, 20)),
        [at(6, 9, 30, 14, 20)],
      );
    });

    test('the daily window honours custom hours and clamps odd ones', () {
      expect(
        windows(from: oct(6), to: oct(7), dayStartHour: 18, dayEndHour: 21),
        [at(6, 18, 0, 21, 0)],
      );
      // 0-24 covers the whole day; out-of-range hours clamp to it.
      expect(
        windows(from: oct(6), to: oct(7), dayStartHour: -3, dayEndHour: 30),
        [span(oct(6), oct(7))],
      );
      // An empty or inverted daily window yields nothing.
      expect(
        windows(from: oct(6), to: oct(7), dayStartHour: 12, dayEndHour: 12),
        isEmpty,
      );
      expect(
        windows(from: oct(6), to: oct(7), dayStartHour: 14, dayEndHour: 9),
        isEmpty,
      );
    });

    test('results are local DateTimes even when the inputs are UTC', () {
      final out = sharedFreeWindows(
        busyA: [span(oct(6, 9).toUtc(), oct(6, 11).toUtc())],
        busyB: const [],
        from: oct(6).toUtc(),
        to: oct(7).toUtc(),
        maxSuggestions: 20,
      );
      expect(out, [at(6, 8, 0, 9, 0), at(6, 11, 0, 20, 0)]);
      for (final w in out) {
        expect(w.start.isUtc, isFalse);
        expect(w.end.isUtc, isFalse);
      }
    });

    test('does not mutate the busy lists', () {
      final busyA = [at(6, 15, 0, 16, 0), at(6, 9, 0, 11, 0)];
      final copy = List.of(busyA);
      windows(busyA: busyA, from: oct(6), to: oct(7));
      expect(busyA, copy);
    });
  });

  group('mergeBusyBlocks', () {
    test('drops inverted and zero-length spans, then merges', () {
      expect(
        mergeBusyBlocks([
          at(6, 14, 0, 8, 0), // inverted
          at(6, 13, 0, 13, 0), // zero-length
          at(6, 10, 30, 12, 0),
          at(6, 9, 0, 11, 0),
          at(6, 15, 0, 16, 0),
        ]),
        [at(6, 9, 0, 12, 0), at(6, 15, 0, 16, 0)],
      );
      expect(mergeBusyBlocks(const []), isEmpty);
      expect(mergeBusyBlocks([at(6, 14, 0, 8, 0)]), isEmpty);
    });

    test('accepts any iterable', () {
      final blocks = {at(6, 9, 0, 10, 0), at(6, 9, 30, 11, 0)};
      expect(mergeBusyBlocks(blocks), [at(6, 9, 0, 11, 0)]);
    });
  });
}
