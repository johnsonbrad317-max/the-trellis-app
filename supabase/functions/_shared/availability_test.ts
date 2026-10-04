// Deno tests for availability.ts. Run with:
//   deno test supabase/functions/_shared/availability_test.ts
// (Never run under Deno itself — it is not installed on the authoring machine.
// Every test here HAS been executed under Node 24's TypeScript type-stripping
// with `Deno.test` and `assertEquals` shimmed, and passes. If one fails under
// Deno, suspect a runtime difference first.)

import { assertEquals } from 'jsr:@std/assert@1';
import {
  intersectSpans,
  invertSpans,
  mergeSpans,
  sharedFreeWindows,
} from './availability.ts';

const base = {
  durationMinutes: 60,
  dayStartHour: 8,
  dayEndHour: 20,
  maxSuggestions: 20,
};

Deno.test('mergeSpans merges overlapping and touching spans and drops empties', () => {
  assertEquals(
    mergeSpans([
      { start: 50, end: 60 },
      { start: 0, end: 10 },
      { start: 5, end: 20 },
      { start: 20, end: 30 },
      { start: 40, end: 40 },
    ]),
    [{ start: 0, end: 30 }, { start: 50, end: 60 }],
  );
});

Deno.test('invertSpans returns the gaps inside the window', () => {
  assertEquals(
    invertSpans([{ start: 10, end: 20 }, { start: 30, end: 90 }], 0, 50),
    [{ start: 0, end: 10 }, { start: 20, end: 30 }],
  );
  assertEquals(invertSpans([], 0, 50), [{ start: 0, end: 50 }]);
  assertEquals(invertSpans([{ start: -5, end: 100 }], 0, 50), []);
});

Deno.test('intersectSpans keeps only the overlap', () => {
  assertEquals(
    intersectSpans(
      [{ start: 0, end: 10 }, { start: 20, end: 40 }],
      [{ start: 5, end: 25 }, { start: 30, end: 35 }],
    ),
    [{ start: 5, end: 10 }, { start: 20, end: 25 }, { start: 30, end: 35 }],
  );
});

Deno.test('two empty calendars: the whole daily window is shared', () => {
  const out = sharedFreeWindows({
    ...base,
    busyA: [],
    busyB: [],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-07T00:00:00Z',
    tzOffsetMinutes: 0,
  });
  assertEquals(out, [{ start: '2026-10-06T08:00:00.000Z', end: '2026-10-06T20:00:00.000Z' }]);
});

Deno.test('busy blocks from either person are removed; short gaps are dropped', () => {
  const out = sharedFreeWindows({
    ...base,
    // A busy 09:00-11:00; B busy 10:00-12:00 and 12:30-18:00 (leaves a 30 min
    // gap, shorter than the 60 min meeting).
    busyA: [{ start: '2026-10-06T09:00:00Z', end: '2026-10-06T11:00:00Z' }],
    busyB: [
      { start: '2026-10-06T10:00:00Z', end: '2026-10-06T12:00:00Z' },
      { start: '2026-10-06T12:30:00Z', end: '2026-10-06T18:00:00Z' },
    ],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-07T00:00:00Z',
    tzOffsetMinutes: 0,
  });
  assertEquals(out, [
    { start: '2026-10-06T08:00:00.000Z', end: '2026-10-06T09:00:00.000Z' },
    { start: '2026-10-06T18:00:00.000Z', end: '2026-10-06T20:00:00.000Z' },
  ]);
});

Deno.test('window start is rounded up to the next quarter hour', () => {
  const out = sharedFreeWindows({
    ...base,
    busyA: [{ start: '2026-10-06T08:00:00Z', end: '2026-10-06T10:07:00Z' }],
    busyB: [],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-07T00:00:00Z',
    tzOffsetMinutes: 0,
  });
  assertEquals(out, [{ start: '2026-10-06T10:15:00.000Z', end: '2026-10-06T20:00:00.000Z' }]);
});

Deno.test('the daily window is applied in the caller\'s UTC offset', () => {
  // UTC-5: 08:00-20:00 local = 13:00-01:00Z (next day).
  const out = sharedFreeWindows({
    ...base,
    busyA: [],
    busyB: [],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-07T00:00:00Z',
    tzOffsetMinutes: -300,
  });
  assertEquals(out, [
    // Local Oct 5 evening (from is 19:00 local on Oct 5): 00:00Z-01:00Z.
    { start: '2026-10-06T00:00:00.000Z', end: '2026-10-06T01:00:00.000Z' },
    // Local Oct 6 08:00-20:00.
    { start: '2026-10-06T13:00:00.000Z', end: '2026-10-07T00:00:00.000Z' },
  ]);
});

Deno.test('tzid is honoured, including daylight saving', () => {
  // New York in July is UTC-4: 09:00-17:00 local = 13:00-21:00Z.
  const summer = sharedFreeWindows({
    ...base,
    dayStartHour: 9,
    dayEndHour: 17,
    busyA: [],
    busyB: [],
    from: '2026-07-07T04:00:00Z', // local midnight Jul 7
    to: '2026-07-08T04:00:00Z',
    tzid: 'America/New_York',
  });
  assertEquals(summer, [{ start: '2026-07-07T13:00:00.000Z', end: '2026-07-07T21:00:00.000Z' }]);

  // ...and in January UTC-5: 14:00-22:00Z.
  const winter = sharedFreeWindows({
    ...base,
    dayStartHour: 9,
    dayEndHour: 17,
    busyA: [],
    busyB: [],
    from: '2026-01-13T05:00:00Z',
    to: '2026-01-14T05:00:00Z',
    tzid: 'America/New_York',
  });
  assertEquals(winter, [{ start: '2026-01-13T14:00:00.000Z', end: '2026-01-13T22:00:00.000Z' }]);
});

Deno.test('an offset takes precedence over a tzid', () => {
  const out = sharedFreeWindows({
    ...base,
    busyA: [],
    busyB: [],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-07T00:00:00Z',
    tzid: 'America/New_York',
    tzOffsetMinutes: 0,
  });
  assertEquals(out, [{ start: '2026-10-06T08:00:00.000Z', end: '2026-10-06T20:00:00.000Z' }]);
});

Deno.test('maxSuggestions and maxPerDay limit the output', () => {
  const common = {
    ...base,
    busyA: [{ start: '2026-10-06T12:00:00Z', end: '2026-10-06T13:00:00Z' }],
    busyB: [{ start: '2026-10-06T16:00:00Z', end: '2026-10-06T17:00:00Z' }],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-08T00:00:00Z',
    tzOffsetMinutes: 0,
  };
  // Day 1 has three windows (8-12, 13-16, 17-20); day 2 has one.
  assertEquals(sharedFreeWindows(common).length, 4);
  assertEquals(sharedFreeWindows({ ...common, maxSuggestions: 2 }).length, 2);
  const capped = sharedFreeWindows({ ...common, maxPerDay: 1 });
  assertEquals(capped.map((w) => w.start), [
    '2026-10-06T08:00:00.000Z',
    '2026-10-07T08:00:00.000Z',
  ]);
});

// --- Regression tests for bugs found in the pre-release audit -----------------

Deno.test('maxSuggestions of 0 / negative / NaN returns nothing', () => {
  const common = {
    ...base,
    busyA: [],
    busyB: [],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-07T00:00:00Z',
    tzOffsetMinutes: 0,
  };
  assertEquals(sharedFreeWindows({ ...common, maxSuggestions: 0 }), []);
  assertEquals(sharedFreeWindows({ ...common, maxSuggestions: -1 }), []);
  assertEquals(sharedFreeWindows({ ...common, maxSuggestions: NaN }), []);
});

Deno.test('an unusable duration never lets a too-short gap through', () => {
  // The only shared gap is 09:00-09:20.
  const out = sharedFreeWindows({
    ...base,
    durationMinutes: NaN,
    busyA: [{ start: '2026-10-06T00:00:00Z', end: '2026-10-06T09:00:00Z' }],
    busyB: [{ start: '2026-10-06T09:20:00Z', end: '2026-10-07T00:00:00Z' }],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-07T00:00:00Z',
    tzOffsetMinutes: 0,
  });
  assertEquals(out, []);
});

Deno.test('America/Chicago daylight-saving changes (tzid): 08-20 local on each side', () => {
  const spring = sharedFreeWindows({
    ...base,
    busyA: [],
    busyB: [],
    from: '2026-03-07T06:00:00Z', // local midnight Mar 7 (CST)
    to: '2026-03-09T05:00:00Z', // local midnight Mar 9 (CDT)
    tzid: 'America/Chicago',
  });
  assertEquals(spring, [
    { start: '2026-03-07T14:00:00.000Z', end: '2026-03-08T02:00:00.000Z' },
    { start: '2026-03-08T13:00:00.000Z', end: '2026-03-09T01:00:00.000Z' },
  ]);

  const fall = sharedFreeWindows({
    ...base,
    busyA: [],
    busyB: [],
    from: '2026-10-31T05:00:00Z', // local midnight Oct 31 (CDT)
    to: '2026-11-02T06:00:00Z', // local midnight Nov 2 (CST)
    tzid: 'America/Chicago',
  });
  assertEquals(fall, [
    { start: '2026-10-31T13:00:00.000Z', end: '2026-11-01T01:00:00.000Z' },
    { start: '2026-11-01T14:00:00.000Z', end: '2026-11-02T02:00:00.000Z' },
  ]);
});

Deno.test('a day start inside the spring-forward gap begins at the first real instant after it', () => {
  // 02:00 on 2026-03-08 does not exist in Chicago; the window must not start
  // at 01:00 CST (which is before the hour that was asked for).
  const out = sharedFreeWindows({
    ...base,
    dayStartHour: 2,
    dayEndHour: 6,
    busyA: [],
    busyB: [],
    from: '2026-03-08T06:00:00Z',
    to: '2026-03-09T05:00:00Z',
    tzid: 'America/Chicago',
  });
  assertEquals(out, [{ start: '2026-03-08T08:00:00.000Z', end: '2026-03-08T11:00:00.000Z' }]);
});

Deno.test('unsorted, overlapping, zero-length and inverted busy blocks', () => {
  const out = sharedFreeWindows({
    ...base,
    busyA: [
      { start: '2026-10-06T15:00:00Z', end: '2026-10-06T16:00:00Z' },
      { start: '2026-10-06T09:00:00Z', end: '2026-10-06T11:00:00Z' },
      { start: '2026-10-06T10:30:00Z', end: '2026-10-06T12:00:00Z' },
      { start: '2026-10-06T13:00:00Z', end: '2026-10-06T13:00:00Z' },
      { start: '2026-10-06T14:00:00Z', end: '2026-10-06T08:00:00Z' },
    ],
    busyB: [],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-07T00:00:00Z',
    tzOffsetMinutes: 0,
  });
  assertEquals(out, [
    { start: '2026-10-06T08:00:00.000Z', end: '2026-10-06T09:00:00.000Z' },
    { start: '2026-10-06T12:00:00.000Z', end: '2026-10-06T15:00:00.000Z' },
    { start: '2026-10-06T16:00:00.000Z', end: '2026-10-06T20:00:00.000Z' },
  ]);
});

Deno.test('a fully busy person leaves no suggestions', () => {
  const out = sharedFreeWindows({
    ...base,
    busyA: [{ start: '2026-10-05T00:00:00Z', end: '2026-10-09T00:00:00Z' }],
    busyB: [],
    from: '2026-10-06T00:00:00Z',
    to: '2026-10-08T00:00:00Z',
    tzOffsetMinutes: 0,
  });
  assertEquals(out, []);
});
