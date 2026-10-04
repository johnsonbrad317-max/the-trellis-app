import 'calendar_connection.dart' show SharedSlot;

const weekdayAbbrev = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatMeetingDate(DateTime date) =>
    '${weekdayAbbrev[date.weekday - 1]}, ${monthAbbrev[date.month - 1]} ${date.day}';

String formatMeetingTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final period = time.hour >= 12 ? 'PM' : 'AM';
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute $period';
}

/// How a shared-free-time suggestion reads on a chip, e.g. 'Tue, Oct 6 · 12:00 PM'.
String formatSlotLabel(DateTime start) => '${formatMeetingDate(start)} · ${formatMeetingTime(start)}';

/// A mock-engine proposed meeting time/place, not yet sent to the other
/// party. Shared by the Runner's own Connect tab and the Witness's.
class ProposedMeeting {
  const ProposedMeeting({required this.time, required this.timeLabel, required this.location});

  final DateTime time;
  final String timeLabel;
  final String location;
}

/// Generates a proposed meeting.
///
/// When [sharedSlots] (real times both people are free, from
/// CalendarService.availabilityWith) are available and this isn't an
/// emergency, the first one is used. Otherwise this falls back to the mock
/// heuristic below, which is unchanged.
///
/// TODO(backend): geocode an actual midpoint for the location.
ProposedMeeting generateMeetingProposal({
  required bool isEmergency,
  required int variation,
  String location = '',
  List<SharedSlot> sharedSlots = const [],
}) {
  final now = DateTime.now();

  if (!isEmergency) {
    for (final slot in sharedSlots) {
      if (slot.start.isAfter(now)) {
        return ProposedMeeting(
          time: slot.start,
          timeLabel: 'Both free — ${formatMeetingDate(slot.start)} at ${formatMeetingTime(slot.start)}',
          location: location,
        );
      }
    }
  }

  if (isEmergency) {
    final time = now.add(const Duration(hours: 2));
    return ProposedMeeting(
      time: time,
      timeLabel: 'Today, as soon as possible — ${formatMeetingTime(time)}',
      location: location,
    );
  }

  final candidate = now.add(const Duration(hours: 48));
  final isWeekend =
      candidate.weekday == DateTime.saturday || candidate.weekday == DateTime.sunday;

  if (isWeekend) {
    final daysUntilSaturday = (DateTime.saturday - candidate.weekday + 7) % 7;
    final saturday = DateTime(
      candidate.year,
      candidate.month,
      candidate.day,
    ).add(Duration(days: daysUntilSaturday));
    final time = DateTime(saturday.year, saturday.month, saturday.day, 9);
    return ProposedMeeting(
      time: time,
      timeLabel: 'Saturday morning — ${formatMeetingDate(time)} at ${formatMeetingTime(time)}',
      location: location,
    );
  }

  final useLunch = variation.isOdd;
  final time = useLunch
      ? DateTime(candidate.year, candidate.month, candidate.day, 12)
      : DateTime(candidate.year, candidate.month, candidate.day, 6);
  final timeLabel = useLunch
      ? 'Lunch — ${formatMeetingDate(time)} at 12:00 - 1:00 PM'
      : 'Early morning — ${formatMeetingDate(time)} at 6:00 - 7:00 AM';

  return ProposedMeeting(time: time, timeLabel: timeLabel, location: location);
}
