// Pure scheduling maths: given two people's BUSY blocks, find the windows when
// BOTH are free. A Dart port of supabase/functions/_shared/availability.ts so
// the phone can compute shared windows itself from two lists of busy blocks.
// No I/O, no Flutter — everything here is deterministic and unit-tested
// (test/shared_free_windows_test.dart). Keep the two implementations in step.
//
// Time zones: the Edge Function receives UTC instants plus the caller's UTC
// offset and does its own offset arithmetic. Here the caller passes local
// DateTimes and the daily window (dayStartHour..dayEndHour) is read off the
// device's local clock through DateTime's own local fields, so daylight-saving
// changes are handled by the platform. All times are compared as instants, so
// a UTC DateTime in a busy list is fine; the windows returned are always local.
//
// Privacy note: this is the only place the two people's busy blocks meet, and
// it returns ONLY the shared free windows. Callers must never forward the
// inputs to anyone.

/// A span of time, half-open `[start, end)`.
///
/// The two DateTimes may be in any zone; they are compared as instants.
/// Two spans are equal when they cover the same instants, whatever zone each
/// DateTime happens to be expressed in.
class TimeSpan {
  const TimeSpan(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// How long the span lasts (negative for an inverted span).
  Duration get duration => end.difference(start);

  int get _startMs => start.millisecondsSinceEpoch;
  int get _endMs => end.millisecondsSinceEpoch;

  @override
  bool operator ==(Object other) =>
      other is TimeSpan &&
      other.start.isAtSameMomentAs(start) &&
      other.end.isAtSameMomentAs(end);

  @override
  int get hashCode => Object.hash(_startMs, _endMs);

  @override
  String toString() => 'TimeSpan($start, $end)';
}

const int _minuteMs = 60 * 1000;
const int _quarterHourMs = 15 * _minuteMs;

/// The search is never carried further ahead than this many local days, so a
/// huge window cannot make the loop spin (the Edge Function caps windows at
/// 21 days anyway).
const int _maxDays = 45;

/// Sorts and merges overlapping or touching spans; drops empty or inverted
/// ones. The DateTimes in the result are taken from the inputs (no zone
/// conversion). Never mutates its input.
List<TimeSpan> mergeSpans(Iterable<TimeSpan> spans) {
  final sorted = spans.where((s) => s._endMs > s._startMs).toList()
    ..sort((a, b) {
      final byStart = a._startMs.compareTo(b._startMs);
      return byStart != 0 ? byStart : a._endMs.compareTo(b._endMs);
    });

  final merged = <TimeSpan>[];
  for (final span in sorted) {
    if (merged.isNotEmpty && span._startMs <= merged.last._endMs) {
      final last = merged.last;
      if (span._endMs > last._endMs) {
        merged[merged.length - 1] = TimeSpan(last.start, span.end);
      }
    } else {
      merged.add(span);
    }
  }
  return merged;
}

/// The phone's raw event list goes through this before it is used or
/// uploaded: inverted and zero-length blocks (end <= start) are dropped and
/// everything left is sorted and merged, so the result says only WHEN the
/// person is busy and nothing about how many events made them so.
List<TimeSpan> mergeBusyBlocks(Iterable<TimeSpan> blocks) =>
    mergeSpans(blocks.where((b) => b._endMs > b._startMs));

/// The gaps of `[from, to)` not covered by `busy`, which must already be
/// merged (see [mergeSpans]).
List<TimeSpan> invertSpans(List<TimeSpan> busy, DateTime from, DateTime to) {
  final toMs = to.millisecondsSinceEpoch;
  final free = <TimeSpan>[];
  var cursor = from;
  var cursorMs = from.millisecondsSinceEpoch;
  for (final block in busy) {
    if (block._endMs <= cursorMs) continue;
    if (block._startMs >= toMs) break;
    if (block._startMs > cursorMs) free.add(TimeSpan(cursor, block.start));
    // block.end > cursor here (the first check above), so this is the max.
    cursor = block.end;
    cursorMs = block._endMs;
    if (cursorMs >= toMs) break;
  }
  if (cursorMs < toMs) free.add(TimeSpan(cursor, to));
  return free;
}

/// Intersection of two sorted, non-overlapping span lists.
List<TimeSpan> intersectSpans(List<TimeSpan> a, List<TimeSpan> b) {
  final out = <TimeSpan>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final start = a[i]._startMs >= b[j]._startMs ? a[i].start : b[j].start;
    final end = a[i]._endMs <= b[j]._endMs ? a[i].end : b[j].end;
    if (end.millisecondsSinceEpoch > start.millisecondsSinceEpoch) {
      out.add(TimeSpan(start, end));
    }
    if (a[i]._endMs < b[j]._endMs) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

/// A whole hour clamped to 0-24 (24 meaning midnight at the end of the day).
int _clampHour(int value) => value < 0 ? 0 : (value > 24 ? 24 : value);

/// One `[dayStartHour, dayEndHour)` span per local calendar day overlapping
/// `[from, to)`, on the device's local clock. Sorted and non-overlapping (the
/// hours are clamped to 0-24, so one day's window can touch but never overlap
/// the next day's).
///
/// Around a daylight-saving change the platform decides what a wall-clock
/// hour means: a time the clocks skip is pushed forward to the first real
/// instant after the gap, so a window never starts before the hour asked for.
List<TimeSpan> _dailyWindows(
  DateTime from,
  DateTime to,
  int startHourRaw,
  int endHourRaw,
) {
  final startHour = _clampHour(startHourRaw);
  final endHour = _clampHour(endHourRaw);
  if (endHour <= startHour) return const [];

  final toMs = to.millisecondsSinceEpoch;
  final first = from.toLocal();
  final windows = <TimeSpan>[];
  for (var i = 0; i < _maxDays; i++) {
    // The constructor normalises day overflow on the local calendar, so this
    // steps whole calendar days even across daylight-saving changes.
    final day = DateTime(first.year, first.month, first.day + i);
    final start = DateTime(day.year, day.month, day.day, startHour);
    final end = DateTime(day.year, day.month, day.day, endHour);
    if (start.millisecondsSinceEpoch >= toMs) break;
    if (end.millisecondsSinceEpoch > start.millisecondsSinceEpoch) {
      windows.add(TimeSpan(start, end));
    }
  }
  return windows;
}

/// Rounds an epoch-millisecond instant up to the next quarter hour. Quarter
/// hours are the same instants in every zone whose offset is a multiple of
/// fifteen minutes, which is all of them.
int _ceilToQuarterHour(int ms) {
  final remainder = ms % _quarterHourMs; // never negative in Dart
  return remainder == 0 ? ms : ms + (_quarterHourMs - remainder);
}

/// A key naming the local calendar day an instant falls on.
int _localDayKey(DateTime local) =>
    local.year * 10000 + local.month * 100 + local.day;

/// Windows when both people are free, as local DateTimes, in chronological
/// order.
///
/// Merges each person's busy blocks, inverts them into free time within
/// `[from, to)`, intersects the two, clips to the daily window
/// (`dayStartHour`..`dayEndHour` on the device's local clock), rounds each
/// window's start up to the next quarter hour, drops anything shorter than
/// `durationMinutes`, keeps at most `maxPerDay` windows per local calendar
/// day (0 or less: no per-day cap) and stops after `maxSuggestions`.
///
/// `from` and `to` are the search window; pass local DateTimes (any zone is
/// accepted and compared as an instant, but the daily window and the results
/// are always local). Returns `[]` when `to <= from`, when `maxSuggestions`
/// is less than 1, or when the daily window is empty. A zero or negative
/// duration is treated as one minute, as the Edge Function does.
///
/// The defaults match the calendar-availability Edge Function's request
/// defaults (60 minutes, 06:00-20:00, 8 suggestions). Never mutates its input.
List<TimeSpan> sharedFreeWindows({
  required List<TimeSpan> busyA,
  required List<TimeSpan> busyB,
  required DateTime from,
  required DateTime to,
  int durationMinutes = 60,
  // 6 a.m.: a morning coffee before work is a real meeting; the old 8 a.m.
  // start hid it.
  int dayStartHour = 6,
  int dayEndHour = 20,
  int maxSuggestions = 8,
  int maxPerDay = 3,
}) {
  if (to.millisecondsSinceEpoch <= from.millisecondsSinceEpoch) return const [];
  if (maxSuggestions < 1) return const [];
  final durationMs = (durationMinutes < 1 ? 1 : durationMinutes) * _minuteMs;

  final freeA = invertSpans(mergeSpans(busyA), from, to);
  final freeB = invertSpans(mergeSpans(busyB), from, to);
  final sharedFree = intersectSpans(freeA, freeB);

  final daily = _dailyWindows(from, to, dayStartHour, dayEndHour);
  final clipped = intersectSpans(sharedFree, daily);

  final results = <TimeSpan>[];
  final perDay = <int, int>{};

  for (final span in clipped) {
    final startMs = _ceilToQuarterHour(span._startMs);
    if (span._endMs - startMs < durationMs) continue;

    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    if (maxPerDay > 0) {
      final key = _localDayKey(start);
      final count = perDay[key] ?? 0;
      if (count >= maxPerDay) continue;
      perDay[key] = count + 1;
    }

    results.add(
      TimeSpan(start, DateTime.fromMillisecondsSinceEpoch(span._endMs)),
    );
    if (results.length >= maxSuggestions) break;
  }

  return results;
}
