// Pure scheduling maths: given two people's BUSY intervals, find the windows
// when BOTH are free. No I/O, no Cronofy, no Supabase — everything here is
// deterministic so it can be unit-tested (availability_test.ts).
//
// Privacy note: this is the only place the two people's busy blocks ever meet,
// and it returns ONLY the shared free windows. Callers must never forward the
// inputs to anyone.

export type TimeLike = string | number | Date;

export interface BusyBlock {
  start: TimeLike;
  end: TimeLike;
}

export interface FreeWindow {
  /// ISO 8601, UTC.
  start: string;
  end: string;
}

export interface SharedFreeWindowsInput {
  busyA: BusyBlock[];
  busyB: BusyBlock[];
  /// The search window.
  from: TimeLike;
  to: TimeLike;
  durationMinutes: number;
  /// Only suggest times between these local hours (0-24) each day, in the
  /// caller's time zone.
  dayStartHour: number;
  dayEndHour: number;
  /// The caller's IANA time zone, e.g. "America/Chicago". Used for the daily
  /// window when tzOffsetMinutes is absent.
  tzid?: string;
  /// The caller's fixed UTC offset in minutes (east positive, e.g. -300 for
  /// UTC-5). Preferred over tzid when both are given.
  tzOffsetMinutes?: number;
  maxSuggestions: number;
  /// Optional cap on windows returned per local day, so a free week isn't
  /// summarised as seven mornings. Default: no cap.
  maxPerDay?: number;
}

interface Span {
  start: number;
  end: number;
}

const MINUTE = 60_000;
const QUARTER_HOUR = 15 * MINUTE;

function toMs(value: TimeLike): number {
  const ms = value instanceof Date ? value.getTime() : typeof value === 'number' ? value : Date.parse(value);
  if (!Number.isFinite(ms)) throw new RangeError(`Invalid time: ${String(value)}`);
  return ms;
}

/// Sorts and merges overlapping/touching spans; drops empty or inverted ones.
export function mergeSpans(spans: Span[]): Span[] {
  const sorted = spans
    .filter((s) => s.end > s.start)
    .map((s) => ({ start: s.start, end: s.end }))
    .sort((a, b) => a.start - b.start || a.end - b.end);

  const merged: Span[] = [];
  for (const span of sorted) {
    const last = merged[merged.length - 1];
    if (last && span.start <= last.end) {
      if (span.end > last.end) last.end = span.end;
    } else {
      merged.push(span);
    }
  }
  return merged;
}

/// The gaps of [from, to] not covered by `busy` (which must be merged).
export function invertSpans(busy: Span[], from: number, to: number): Span[] {
  const free: Span[] = [];
  let cursor = from;
  for (const block of busy) {
    if (block.end <= cursor) continue;
    if (block.start >= to) break;
    if (block.start > cursor) free.push({ start: cursor, end: block.start });
    cursor = Math.max(cursor, block.end);
    if (cursor >= to) break;
  }
  if (cursor < to) free.push({ start: cursor, end: to });
  return free;
}

/// Intersection of two sorted, non-overlapping span lists.
export function intersectSpans(a: Span[], b: Span[]): Span[] {
  const out: Span[] = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const start = Math.max(a[i].start, b[j].start);
    const end = Math.min(a[i].end, b[j].end);
    if (end > start) out.push({ start, end });
    if (a[i].end < b[j].end) i++;
    else j++;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Time zones
// ---------------------------------------------------------------------------

interface Zone {
  tzid?: string;
  tzOffsetMinutes?: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

/// True if `tzid` is an IANA zone this runtime understands.
export function isValidTzid(tzid: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tzid });
    return true;
  } catch (_) {
    return false;
  }
}

/// Offset of the zone from UTC, in minutes, at the given instant.
function offsetMinutesAt(ms: number, zone: Zone): number {
  if (typeof zone.tzOffsetMinutes === 'number' && Number.isFinite(zone.tzOffsetMinutes)) {
    return zone.tzOffsetMinutes;
  }
  if (!zone.tzid) return 0;

  let formatter = formatters.get(zone.tzid);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: zone.tzid,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    formatters.set(zone.tzid, formatter);
  }

  const whole = Math.floor(ms / 1000) * 1000;
  const parts: Record<string, number> = {};
  for (const part of formatter.formatToParts(new Date(whole))) {
    if (part.type !== 'literal') parts[part.type] = Number(part.value);
  }
  const wallAsUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return Math.round((wallAsUtc - whole) / MINUTE);
}

/// Offset from UTC (minutes, east positive) of an IANA zone at an instant.
/// `tzid` must be valid (see isValidTzid).
export function utcOffsetMinutesAt(ms: number, tzid: string): number {
  return offsetMinutesAt(ms, { tzid });
}

const DAY = 24 * 60 * MINUTE;

/// The UTC instant at which the wall clock in `zone` reads y-m-d h:00.
///
/// Around a daylight-saving change a wall-clock time can be ambiguous (it
/// happens twice: the FIRST occurrence is used) or not exist at all (the
/// clocks skip it: the first real instant after the gap is used, so a daily
/// window never starts before the hour that was asked for).
function localToUtc(year: number, month: number, day: number, hour: number, zone: Zone): number {
  const wall = Date.UTC(year, month, day, hour, 0, 0);
  if (typeof zone.tzOffsetMinutes === 'number' && Number.isFinite(zone.tzOffsetMinutes)) {
    return wall - zone.tzOffsetMinutes * MINUTE;
  }
  if (!zone.tzid) return wall;

  // Candidate instants using the offsets in force a day either side (one of
  // them is the offset before any change, the other the offset after it).
  const before = wall - offsetMinutesAt(wall - DAY, zone) * MINUTE;
  const after = wall - offsetMinutesAt(wall + DAY, zone) * MINUTE;
  if (before === after) return before;

  const reads = (candidate: number) => candidate + offsetMinutesAt(candidate, zone) * MINUTE === wall;
  const valid = [before, after].filter(reads);
  if (valid.length > 0) return Math.min(...valid);
  // In the gap: neither candidate reads back as `wall`. The later one is the
  // requested time pushed forward by the size of the gap.
  return Math.max(before, after);
}

/// The local calendar date (y, m0, d) of an instant in `zone`.
function localDate(ms: number, zone: Zone): { year: number; month: number; day: number } {
  const shifted = new Date(ms + offsetMinutesAt(ms, zone) * MINUTE);
  return { year: shifted.getUTCFullYear(), month: shifted.getUTCMonth(), day: shifted.getUTCDate() };
}

const MAX_DAYS = 45;

/// A whole hour in [0, 24], or null if the value is not a usable number.
function clampHour(value: number): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return Math.min(24, Math.max(0, Math.trunc(value)));
}

/// One [dayStartHour, dayEndHour] span per local day overlapping [from, to].
/// Sorted and non-overlapping (the hours are clamped to 0-24, so one day's
/// window can touch but never overlap the next day's).
function dailyWindows(from: number, to: number, startHourRaw: number, endHourRaw: number, zone: Zone): Span[] {
  const startHour = clampHour(startHourRaw);
  const endHour = clampHour(endHourRaw);
  if (startHour === null || endHour === null || endHour <= startHour) return [];

  const first = localDate(from, zone);
  const windows: Span[] = [];
  for (let i = 0; i < MAX_DAYS; i++) {
    const day = new Date(Date.UTC(first.year, first.month, first.day + i));
    const y = day.getUTCFullYear();
    const m = day.getUTCMonth();
    const d = day.getUTCDate();
    const start = localToUtc(y, m, d, startHour, zone);
    const end = localToUtc(y, m, d, endHour, zone);
    if (start >= to) break;
    if (end > start) windows.push({ start, end });
  }
  return windows;
}

// ---------------------------------------------------------------------------
// The one function the Edge Function calls
// ---------------------------------------------------------------------------

/// Times when both A and B are free: merges each person's busy blocks,
/// inverts them into free sets, intersects the two, clips to the daily window
/// in the caller's zone, drops anything shorter than the meeting, rounds each
/// start up to the next quarter hour, and returns at most `maxSuggestions`
/// windows in chronological order.
///
/// Throws RangeError if `from`, `to` or any busy block's time cannot be read —
/// an unreadable busy block is never silently treated as free time. Never
/// mutates its input.
export function sharedFreeWindows(input: SharedFreeWindowsInput): FreeWindow[] {
  const from = toMs(input.from);
  const to = toMs(input.to);
  if (to <= from) return [];

  // A meeting length we cannot interpret must not degrade into "any gap will
  // do": no answer is better than a wrong one. (Zero/negative is floored to
  // one minute.)
  if (typeof input.durationMinutes !== 'number' || !Number.isFinite(input.durationMinutes)) return [];
  const duration = Math.max(1, input.durationMinutes) * MINUTE;

  // NaN / zero / negative => nothing. Infinity => everything that exists.
  const maxSuggestions = typeof input.maxSuggestions === 'number' ? input.maxSuggestions : NaN;
  if (Number.isNaN(maxSuggestions) || maxSuggestions < 1) return [];

  const zone: Zone = { tzid: input.tzid, tzOffsetMinutes: input.tzOffsetMinutes };

  const toSpans = (blocks: BusyBlock[]): Span[] =>
    blocks.map((b) => ({ start: toMs(b.start), end: toMs(b.end) }));

  const freeA = invertSpans(mergeSpans(toSpans(input.busyA)), from, to);
  const freeB = invertSpans(mergeSpans(toSpans(input.busyB)), from, to);
  const sharedFree = intersectSpans(freeA, freeB);

  const daily = dailyWindows(from, to, input.dayStartHour, input.dayEndHour, zone);
  const clipped = intersectSpans(sharedFree, daily);

  const results: FreeWindow[] = [];
  const perDay = new Map<string, number>();

  for (const span of clipped) {
    const start = Math.ceil(span.start / QUARTER_HOUR) * QUARTER_HOUR;
    if (span.end - start < duration) continue;

    if (input.maxPerDay !== undefined && input.maxPerDay > 0) {
      const d = localDate(start, zone);
      const key = `${d.year}-${d.month}-${d.day}`;
      const count = perDay.get(key) ?? 0;
      if (count >= input.maxPerDay) continue;
      perDay.set(key, count + 1);
    }

    results.push({ start: new Date(start).toISOString(), end: new Date(span.end).toISOString() });
    if (results.length >= maxSuggestions) break;
  }

  return results;
}
