// What a Runner and their Witness are meeting FOR, and what that means for the
// times (and place) The Trellis offers. Shared by both Connect tabs.
//
// The rules, as the owner set them:
//
//   * Coffee — 6:00, 6:30, 7:00, 7:30 or 8:00 a.m., an hour long, weekdays
//     only. Suggested place: a coffee shop midway between the two of them.
//   * Lunch  — 11:00, 11:30, 12:00 or 12:30, an hour long, weekdays only.
//     Suggested place: a sit-down restaurant midway between them.
//   * Organic Life (errands, kids' sports, a house project, grilling, other) —
//     no time and no place is suggested; whoever proposes it fills both in,
//     because it is whatever that day holds.
//
// Coffee and lunch are offered over the next [meetingSuggestionDays] weekdays
// on or after the earliest allowed moment: 48 hours from now ([standardLead]).
// A day counts toward the five only if at least one of its times is still
// available (a Friday whose coffee hours fall inside the 48 hours is skipped,
// so there are always five days to choose from).
//
// Emergency (Runner only — the toggle that bypasses the 48-hour rule): the
// earliest moment is 2 hours from now ([emergencyLead]) and the offer is the
// remaining candidate times today and tomorrow, weekends included — someone
// in crisis should not be told to wait for Monday.
//
// Everything here is pure (no I/O, no Flutter) and unit-tested in
// test/meeting_activity_test.dart. Times are on the phone's local clock.

import 'shared_free_windows.dart' show TimeSpan, mergeSpans;

/// The three things the activity chips choose between.
enum MeetingKind { coffee, lunch, organicLife }

/// A chip on a Connect tab: coffee, lunch, or one of the Organic Life
/// sub-activities (which all behave as [MeetingKind.organicLife]).
enum MeetingActivity {
  coffee,
  lunch,
  errands,
  kidsSports,
  houseProject,
  grillingBbq,
  other;

  MeetingKind get kind => switch (this) {
        MeetingActivity.coffee => MeetingKind.coffee,
        MeetingActivity.lunch => MeetingKind.lunch,
        _ => MeetingKind.organicLife,
      };

  bool get isOrganicLife => kind == MeetingKind.organicLife;

  String get chipLabel => switch (this) {
        MeetingActivity.coffee => 'Coffee',
        MeetingActivity.lunch => 'Lunch',
        MeetingActivity.errands => 'Errands',
        MeetingActivity.kidsSports => "Kids' Sports",
        MeetingActivity.houseProject => 'House Project',
        MeetingActivity.grillingBbq => 'Grilling/BBQ',
        MeetingActivity.other => 'Other',
      };

  String get inviteFragment => switch (this) {
        MeetingActivity.coffee => 'grab coffee',
        MeetingActivity.lunch => 'grab lunch',
        MeetingActivity.errands => 'join you for errands',
        MeetingActivity.kidsSports => "join you at the kids' games",
        MeetingActivity.houseProject => 'help out on a house project',
        MeetingActivity.grillingBbq => 'grill out together',
        MeetingActivity.other => 'spend time together',
      };

  /// The Organic Life sub-activities, in chip order.
  static const organicLifeOptions = [
    MeetingActivity.errands,
    MeetingActivity.kidsSports,
    MeetingActivity.houseProject,
    MeetingActivity.grillingBbq,
    MeetingActivity.other,
  ];
}

/// A wall-clock start time, e.g. 6:30.
typedef ClockTime = ({int hour, int minute});

/// How many days of coffee / lunch times are offered.
const int meetingSuggestionDays = 5;

/// The usual lead time: nothing is suggested sooner than 48 hours out.
const Duration standardLead = Duration(hours: 48);

/// With the Runner's Emergency toggle on.
const Duration emergencyLead = Duration(hours: 2);

extension MeetingKindPlan on MeetingKind {
  /// The fixed start times offered for this kind (none for Organic Life).
  List<ClockTime> get candidateTimes => switch (this) {
        MeetingKind.coffee => const [
            (hour: 6, minute: 0),
            (hour: 6, minute: 30),
            (hour: 7, minute: 0),
            (hour: 7, minute: 30),
            (hour: 8, minute: 0),
          ],
        MeetingKind.lunch => const [
            (hour: 11, minute: 0),
            (hour: 11, minute: 30),
            (hour: 12, minute: 0),
            (hour: 12, minute: 30),
          ],
        MeetingKind.organicLife => const [],
      };

  /// How long the meeting is assumed to last — a candidate time is only
  /// offered when both people are free for all of it.
  int get durationMinutes => 60;

  /// Whether The Trellis suggests times (and a midway place) at all.
  bool get suggestsTimes => this != MeetingKind.organicLife;

  /// Whether a midway place is suggested.
  bool get suggestsPlace => this != MeetingKind.organicLife;

  /// How the suggested place is described, e.g. in "No coffee shop found".
  String get placeNoun => switch (this) {
        MeetingKind.coffee => 'coffee shop',
        MeetingKind.lunch => 'lunch spot',
        MeetingKind.organicLife => 'place',
      };

  /// 'coffee' / 'lunch' / '' — for "Usual coffee times".
  String get timesNoun => switch (this) {
        MeetingKind.coffee => 'coffee',
        MeetingKind.lunch => 'lunch',
        MeetingKind.organicLife => '',
      };
}

/// One day's offered start times, in order. [day] is local midnight.
class MeetingDaySlots {
  const MeetingDaySlots({required this.day, required this.starts});

  final DateTime day;
  final List<DateTime> starts;

  @override
  String toString() => 'MeetingDaySlots($day, $starts)';
}

bool _isWeekend(DateTime day) => day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

/// The earliest moment a meeting may be suggested for.
DateTime earliestMeetingStart({required DateTime now, bool emergency = false}) =>
    now.add(emergency ? emergencyLead : standardLead);

/// The candidate times for [kind] before anyone's calendar is consulted:
/// the next [meetingSuggestionDays] weekdays (or, for an [emergency], what
/// is left of today and tomorrow, weekends included) with every fixed start
/// time at or after the earliest allowed moment. Days with no time left are
/// skipped. Organic Life has none.
List<MeetingDaySlots> candidateMeetingDays(
  MeetingKind kind, {
  required DateTime now,
  bool emergency = false,
}) {
  final times = kind.candidateTimes;
  if (times.isEmpty) return const [];

  final earliest = earliestMeetingStart(now: now, emergency: emergency);
  // An emergency looks only at today and tomorrow; otherwise start on the
  // earliest allowed day and walk forward (bounded, so it can never spin).
  final firstDay = emergency
      ? DateTime(now.year, now.month, now.day)
      : DateTime(earliest.year, earliest.month, earliest.day);
  final maxDays = emergency ? 2 : 21;
  final wanted = emergency ? 2 : meetingSuggestionDays;

  final days = <MeetingDaySlots>[];
  for (var i = 0; i < maxDays && days.length < wanted; i++) {
    // The constructor normalises day overflow on the local calendar, so this
    // steps whole days even across a daylight-saving change.
    final day = DateTime(firstDay.year, firstDay.month, firstDay.day + i);
    if (!emergency && _isWeekend(day)) continue;
    final starts = [
      for (final t in times)
        if (!DateTime(day.year, day.month, day.day, t.hour, t.minute).isBefore(earliest))
          DateTime(day.year, day.month, day.day, t.hour, t.minute),
    ];
    if (starts.isNotEmpty) days.add(MeetingDaySlots(day: day, starts: starts));
  }
  return days;
}

/// The span the calendars need to be read over to check [days]: from the
/// first offered start to the end of the last one. Null when there is nothing.
TimeSpan? meetingSearchWindow(List<MeetingDaySlots> days, {required int durationMinutes}) {
  if (days.isEmpty) return null;
  final first = days.first.starts.first;
  final last = days.last.starts.last;
  return TimeSpan(first, last.add(Duration(minutes: durationMinutes)));
}

/// Keeps only the candidate times when BOTH people are free for the whole
/// [durationMinutes]: a busy block that overlaps any part of the meeting —
/// even its last five minutes — rules that time out. Days left with nothing
/// are dropped.
///
/// [busyA] / [busyB] null means that person's calendar isn't being shared:
/// then nothing can be checked and [days] come back unfiltered.
List<MeetingDaySlots> filterFreeForBoth(
  List<MeetingDaySlots> days, {
  required int durationMinutes,
  List<TimeSpan>? busyA,
  List<TimeSpan>? busyB,
}) {
  if (busyA == null || busyB == null) return days;
  final busy = mergeSpans([...busyA, ...busyB]);
  final length = Duration(minutes: durationMinutes < 1 ? 1 : durationMinutes);

  bool isFree(DateTime start) {
    final end = start.add(length);
    for (final block in busy) {
      if (block.start.isBefore(end) && block.end.isAfter(start)) return false;
    }
    return true;
  }

  return [
    for (final day in days)
      if (day.starts.where(isFree).toList() case final free when free.isNotEmpty)
        MeetingDaySlots(day: day.day, starts: free),
  ];
}

/// The whole recipe: [kind]'s candidate times for the coming days, kept only
/// where both people are free. Pass null busy lists when either calendar
/// isn't shared (the canonical times come back unfiltered).
List<MeetingDaySlots> suggestMeetingSlots(
  MeetingKind kind, {
  required DateTime now,
  bool emergency = false,
  List<TimeSpan>? busyA,
  List<TimeSpan>? busyB,
}) =>
    filterFreeForBoth(
      candidateMeetingDays(kind, now: now, emergency: emergency),
      durationMinutes: kind.durationMinutes,
      busyA: busyA,
      busyB: busyB,
    );

/// Where the date/time pickers start before anything is chosen: the first
/// candidate time for coffee / lunch, otherwise the earliest allowed moment
/// rounded up to the next whole hour (Organic Life suggests nothing — this
/// is only a starting point for the pickers).
DateTime defaultMeetingStart(MeetingKind kind, {required DateTime now, bool emergency = false}) {
  final days = candidateMeetingDays(kind, now: now, emergency: emergency);
  if (days.isNotEmpty) return days.first.starts.first;
  final earliest = earliestMeetingStart(now: now, emergency: emergency);
  final hour = DateTime(earliest.year, earliest.month, earliest.day, earliest.hour);
  return hour.isBefore(earliest) ? hour.add(const Duration(hours: 1)) : hour;
}

/// "6:00", "12:30" — the short label on a time chip (the day is on its row).
String formatChipTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:${time.minute.toString().padLeft(2, '0')}';
}
