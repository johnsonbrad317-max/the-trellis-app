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
  /// e.g. index 5 is "yesterday". Three states, not two: `null` means no
  /// obligation existed that day, so it's neither a hit nor a miss and must
  /// never render as one — the rhythm wasn't scheduled (e.g. a Wed/Fri-only
  /// fast on a Tuesday), or it didn't count yet (the Runner hadn't committed
  /// their Rule of Life, or hadn't added this rhythm). `true`/`false` mean
  /// it was due and was or wasn't done. Drives the Live Progress heat map
  /// (witness_rule_screen.dart's _WeekHeatMap).
  final List<bool?> weekCompletion;

  /// How many days this week this rhythm was due (and counted).
  int get weekDueCount => weekCompletion.whereType<bool>().length;

  /// How many of those were kept.
  int get weekKeptCount => weekCompletion.where((done) => done == true).length;

  /// This week's kept share, or null when nothing was due — which is not 0%.
  double? get weekRate => weekDueCount == 0 ? null : weekKeptCount / weekDueCount;

  double get weekCompletionRate => weekRate ?? completionRate;
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

/// Where a watched Runner stands, in one word, for their card.
enum RunnerStanding {
  /// No committed Rule of Life yet — nothing to be on or off track with.
  gettingStarted,
  thriving,
  needsSupport,
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
    this.lastCheckInDate,
    this.phoneNumber,
    this.seasonScore,
    this.hasSeasonData = false,
    this.isSeasonDrooping = false,
    this.lockRemovalRequested = false,
    this.hasCommittedRule = true,
    this.ruleCommittedAt,
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

  DateTime? lastCheckInDate;

  /// Non-null when an Anchor Rhythm was missed yesterday and needs this
  /// Witness's attention.
  String? get missedAnchorAlert {
    final missed = anchorMissedYesterday;
    return missed == null ? null : 'Missed "${missed.title}" yesterday.';
  }

  /// Whether this Runner has committed their Rule of Life. Until they have,
  /// nothing counts against them: no missed days, no alerts, no "needs
  /// support" — a draft is not a promise.
  final bool hasCommittedRule;

  /// When they committed (null if not, or if the database doesn't say).
  final DateTime? ruleCommittedAt;

  String get firstName => name.split(' ').first;

  /// Still setting up: there is nothing yet to be on or off track with.
  bool get isGettingStarted => !hasCommittedRule || ruleItems.isEmpty;

  /// This week's kept share across every rhythm, counting only days that were
  /// actually due. Null when nothing was due yet — which is not a bad week.
  double? get weekRate {
    var due = 0;
    var kept = 0;
    for (final item in ruleItems) {
      due += item.weekDueCount;
      kept += item.weekKeptCount;
    }
    return due == 0 ? null : kept / due;
  }

  /// How many of the trailing 7 days count toward the week: something was
  /// due that day, after the Rule of Life was committed.
  int get weekCountedDays {
    var counted = 0;
    for (var day = 0; day < 7; day++) {
      if (ruleItems.any((item) => day < item.weekCompletion.length && item.weekCompletion[day] != null)) {
        counted++;
      }
    }
    return counted;
  }

  /// Days a week needs before it is called hard or strong. One day is not a
  /// week: three rhythms with two missed on the first day is a bad day.
  static const daysToJudgeWeek = 3;

  /// This week's kept share once there are [daysToJudgeWeek] days of it;
  /// null before that.
  double? get judgedWeekRate =>
      isGettingStarted || weekCountedDays < daysToJudgeWeek ? null : weekRate;

  /// Under half of this week's rhythms kept, over at least three days.
  bool get isHardWeek {
    final rate = judgedWeekRate;
    return rate != null && rate < 0.5;
  }

  /// Over 90% of this week's rhythms kept, over at least three days.
  bool get isStrongWeek {
    final rate = judgedWeekRate;
    return rate != null && rate > 0.9;
  }

  /// A missed Anchor Rhythm yesterday, or a hard week. Never true for a
  /// Runner who is still getting started.
  bool get isStruggling {
    if (isGettingStarted) return false;
    return anchorMissedYesterday != null || isHardWeek;
  }

  /// Days since this Runner was last heard from: their last check-in, or the
  /// day they committed if that is more recent (someone who committed this
  /// morning has not "gone quiet").
  int get daysQuiet {
    final committedAt = ruleCommittedAt;
    final lastCheckIn = lastCheckInDate;
    DateTime? latest = lastCheckIn;
    if (committedAt != null && (latest == null || committedAt.isAfter(latest))) {
      latest = committedAt;
    }
    if (latest == null) return 999;
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day)
        .difference(DateTime(latest.year, latest.month, latest.day))
        .inDays;
  }

  /// Committed, but not heard from for two days or more.
  bool get isDrifting => !isGettingStarted && daysQuiet >= 2;

  /// The one-word standing shown on the Runner's card.
  RunnerStanding get standing {
    if (isGettingStarted) return RunnerStanding.gettingStarted;
    if (isStruggling) return RunnerStanding.needsSupport;
    return RunnerStanding.thriving;
  }

  /// Drives the shared [VineVisualizerCard]: the real season score when
  /// loaded, otherwise the average of the trailing week's completion rates.
  double get vitalityScore {
    final season = seasonScore;
    if (season != null) return season;
    if (ruleItems.isEmpty) return 0;
    return ruleItems.fold<double>(0, (sum, item) => sum + item.completionRate) / ruleItems.length;
  }

  /// This week's completion rate, 0 when nothing was due. Prefer [weekRate],
  /// which can tell "nothing due" from "nothing done".
  double get weekCompletionRate => weekRate ?? 0;

  /// The first Anchor Rhythm the Runner reported missing yesterday, if any.
  ///
  /// "Yesterday" is the real calendar day before today — found in each
  /// rhythm's week by date, not assumed to sit at a fixed position (the week
  /// is anchored to the Runner's latest reported day, see [referenceDate]).
  /// Only a day the Runner actually answered "no" for counts here: a day they
  /// simply haven't reported on yet is not a miss (see
  /// RunnerProfile.missedDayCounts), it is silence — which [isDrifting] covers.
  WatchedRuleItem? get anchorMissedYesterday {
    final today = DateTime.now();
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final reference = DateTime(referenceDate.year, referenceDate.month, referenceDate.day);
    final index = 6 - reference.difference(yesterday).inDays;
    if (index < 0 || index > 6) return null;
    for (final item in ruleItems) {
      if (!item.isAnchorRhythm || item.weekCompletion.length <= index) continue;
      if (item.weekCompletion[index] == false) return item;
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
