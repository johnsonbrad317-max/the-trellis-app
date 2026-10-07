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

/// A suggested time in full, e.g. 'Tue, Oct 6 · 12:00 PM' (the screen-reader
/// label of a time chip).
String formatSlotLabel(DateTime start) => '${formatMeetingDate(start)} · ${formatMeetingTime(start)}';

/// A proposed meeting time/place, not yet sent to the other party. Shared by
/// the Runner's own Connect tab and the Witness's. (Which times and places are
/// suggested lives in meeting_activity.dart and MeetingSpotService.)
class ProposedMeeting {
  const ProposedMeeting({required this.time, required this.timeLabel, required this.location});

  final DateTime time;
  final String timeLabel;
  final String location;
}
