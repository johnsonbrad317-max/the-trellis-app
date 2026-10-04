import '../widgets/brass_glyph.dart';
import 'meeting_request.dart' show MeetingStatus;
import 'rule_item.dart' show RuleFrequency;
import 'watched_prayer_item.dart';

/// A single high-level event on a watched Runner's activity feed, e.g.
/// "Brad added a new Prayer Request." / "2 hours ago".
class RunnerActivityEvent {
  const RunnerActivityEvent({
    required this.message,
    required this.relativeTime,
    required this.glyph,
  });

  final String message;
  final String relativeTime;
  final BrassGlyphKind glyph;
}

/// A read-only snapshot of one rhythm from a watched Runner's Rule of Life,
/// as visible to their Witness.
class WatchedRuleItem {
  const WatchedRuleItem({
    required this.id,
    required this.title,
    required this.completionRate,
    required this.frequency,
    this.isAnchorRhythm = false,
    this.isChurchMandated = false,
    this.weekCompletion = const [true, true, true, true, true, true, true],
  });

  final String id;
  final String title;
  final double completionRate;
  final RuleFrequency frequency;
  final bool isAnchorRhythm;

  /// Mirrors RuleItem.isChurchMandated — flipped to false locally the
  /// moment this Witness approves an unlock request for it, so the
  /// dashboard doesn't wait on a full reload. See
  /// RunnerProfile.respondToUnlockRequest.
  final bool isChurchMandated;

  /// Daily status for the trailing 7 days, oldest first and today last —
  /// e.g. index 5 is "yesterday". Three states, not two: `null` means this
  /// rhythm wasn't even scheduled that day (e.g. a Wed/Fri-only fast on a
  /// Tuesday) — no obligation existed, so it's neither a hit nor a miss and
  /// must never render as one. `true`/`false` mean it was due and was or
  /// wasn't done. Drives the Live Progress heat map
  /// (witness_rule_screen.dart's _WeekHeatMap).
  final List<bool?> weekCompletion;

  bool get missedYesterday => weekCompletion.length >= 6 && weekCompletion[5] == false;

  double get weekCompletionRate {
    final scheduledDays = weekCompletion.whereType<bool>().toList();
    if (scheduledDays.isEmpty) return completionRate;
    return scheduledDays.where((done) => done).length / scheduledDays.length;
  }
}

/// A meeting between this Witness and the watched Runner — either proposed
/// by the Runner (awaiting the Witness's response) or by the Witness
/// (via the Connect tab's scheduling engine).
class WatchedMeetingRequest {
  const WatchedMeetingRequest({
    required this.id,
    required this.timeLabel,
    required this.location,
    this.isEmergency = false,
    this.status = MeetingStatus.pendingResponse,
    this.activity,
    this.time,
  });

  final String id;
  final String timeLabel;
  final String location;
  final bool isEmergency;
  final MeetingStatus status;

  /// e.g. "Coffee", "Lunch", "Kids' Sports" — set for meetings proposed via
  /// the Witness's activity-chip scheduling engine.
  final String? activity;

  /// The actual scheduled date/time, used to add this meeting to the
  /// device's native calendar once it's confirmed. Nullable only for
  /// legacy/mock entries that predate this field.
  final DateTime? time;
}

/// A Runner this Witness is walking alongside.
///
/// A Witness observes and responds — they don't edit the Runner's Rule of
/// Life or prayer list — so this is a read-mostly mock snapshot rather than
/// a live link into a [RunnerProfile].
class WatchedRunner {
  WatchedRunner({
    required this.id,
    required this.name,
    required this.ruleItems,
    required this.sharedPrayerRequests,
    required this.pendingMeetings,
    required this.confirmedMeetings,
    required this.witnessPrayers,
    required this.referenceDate,
    this.recentActivity = const [],
    this.missedAnchorAlert,
    this.lastCheckInDate,
    this.phoneNumber,
    this.seasonScore,
    this.hasSeasonData = false,
    this.isSeasonDrooping = false,
    this.lockRemovalRequested = false,
  });

  final String id;
  final String name;
  final List<WatchedRuleItem> ruleItems;

  /// This Runner's 180-day season score exactly as the Runner sees it on their
  /// own dashboard (`get_runner_analytics`): every scheduled day counts, an
  /// unanswered one is a miss. Null only if it couldn't be loaded, in which
  /// case [vitalityScore] falls back to the trailing week.
  final double? seasonScore;

  /// The Runner has answered at least one check-in this season.
  final bool hasSeasonData;

  /// An Anchor Rhythm has been missed three or more times in a row.
  final bool isSeasonDrooping;

  /// The calendar day each WatchedRuleItem.weekCompletion entry is anchored
  /// to (index 6 = this date, index 0 = 6 days before it) — the Runner's
  /// own most recently reported day, not this device's clock (see
  /// RunnerProfile.loadWitnessData). Any UI that labels the heat map's
  /// columns with actual dates MUST derive them from this, not from
  /// DateTime.now() independently — those two are not guaranteed to agree,
  /// and a Witness in a different timezone than their Runner is exactly
  /// the case this matters for.
  final DateTime referenceDate;

  /// Prayer requests the Runner has explicitly shared with this Witness.
  final List<WatchedPrayerItem> sharedPrayerRequests;

  /// Private intercessions this Witness has added for the Runner — not
  /// visible to the Runner, and only editable by the Witness.
  final List<WatchedPrayerItem> witnessPrayers;

  /// Meetings the Runner has proposed, awaiting this Witness's response.
  final List<WatchedMeetingRequest> pendingMeetings;

  /// Confirmed upcoming meetings between this Witness and the Runner.
  final List<WatchedMeetingRequest> confirmedMeetings;
  final List<RunnerActivityEvent> recentActivity;
  final String? phoneNumber;

  /// This Runner has asked to turn their accountability lock off and is
  /// waiting on a Witness's answer (RunnerProfile.resolveLockRemoval).
  bool lockRemovalRequested;

  /// Non-null when an Anchor Rhythm has been missed and needs this
  /// Witness's attention.
  String? missedAnchorAlert;
  DateTime? lastCheckInDate;

  String get firstName => name.split(' ').first;

  /// A quick status derived from whether an Anchor Rhythm alert is active —
  /// drives the carousel's status dot ("Thriving" vs. "Needs Support").
  bool get isThriving => missedAnchorAlert == null;

  /// Drives the shared [VineVisualizerCard]: the real season score when
  /// loaded, otherwise the average of the trailing week's completion rates.
  double get vitalityScore {
    final season = seasonScore;
    if (season != null) return season;
    if (ruleItems.isEmpty) return 0;
    return ruleItems.fold<double>(0, (sum, item) => sum + item.completionRate) / ruleItems.length;
  }

  /// This week's completion rate across [ruleItems], used by the Witness's
  /// Nudge Engine (Thriving/Struggling/Drifting thresholds).
  double get weekCompletionRate {
    if (ruleItems.isEmpty) return 0;
    return ruleItems.fold<double>(0, (sum, item) => sum + item.weekCompletionRate) /
        ruleItems.length;
  }

  /// The first Anchor Rhythm missed yesterday, if any.
  WatchedRuleItem? get anchorMissedYesterday {
    for (final item in ruleItems) {
      if (item.isAnchorRhythm && item.missedYesterday) return item;
    }
    return null;
  }

  /// A prayer answered within the last 3 days, if any — drives the Witness
  /// Connect tab's "celebrate" contextual meeting prompt while it's fresh.
  WatchedPrayerItem? get recentlyAnsweredPrayer {
    final now = DateTime.now();
    for (final item in [...sharedPrayerRequests, ...witnessPrayers]) {
      final answeredDate = item.answeredDate;
      if (item.isAnswered && answeredDate != null && now.difference(answeredDate).inDays <= 3) {
        return item;
      }
    }
    return null;
  }

  int get daysSinceLastCheckIn {
    final date = lastCheckInDate;
    if (date == null) return 999;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final startOfCheckIn = DateTime(date.year, date.month, date.day);
    return startOfToday.difference(startOfCheckIn).inDays;
  }

  String get lastCheckInLabel {
    if (lastCheckInDate == null) return 'No check-ins yet';
    final days = daysSinceLastCheckIn;
    if (days <= 0) return 'Checked in today';
    if (days == 1) return 'Checked in yesterday';
    return 'Checked in $days days ago';
  }
}
