import 'dart:math';

import 'check_in_entry.dart';
import 'church_code.dart';
import 'church_rhythm_metric.dart';
import 'church_roster_entry.dart';
import 'cloud_triage.dart';
import 'dna_rhythm.dart';
import 'meeting_proposal_engine.dart' show formatMeetingDate, formatMeetingTime;
import 'meeting_request.dart';
import 'prayer_item.dart';
import 'rhythm_analytics.dart';
import 'rule_item.dart';
import 'watched_prayer_item.dart';
import 'watched_runner.dart';
import 'witness.dart';

/// The made-up church behind the Cloud preview ("See Preview" on the Cloud
/// Access Code dialog) and RunnerProfile.preview(): Grace Community Church, a
/// congregation of 300 with 220 people using The Trellis, seen by its Cloud
/// admin, Sarah Mitchell — who is also a Runner and a Witness herself.
///
/// Entirely offline and identical every time: every "random" figure comes
/// from a fixed seed, and the only thing that moves is the calendar (dates
/// are relative to today, so the sample never goes stale).
class PreviewSampleData {
  PreviewSampleData._();

  static const userId = 'preview-sarah-mitchell';
  static const userName = 'Sarah Mitchell';
  static const userEmail = 'sarah.mitchell@example.com';
  static const userPhone = '+15555550123';
  static const churchId = 'preview-grace-community-church';
  static const churchName = 'Grace Community Church';

  /// Licenses the church has bought — "a church of 300".
  static const licenseCap = 300;

  /// People actually using The Trellis.
  static const rosterSize = 220;

  /// The roster's vitality spread: 55% Full Bloom, 30% Budding, 15% Drooping.
  static const fullBloomCount = 121;
  static const buddingCount = 66;
  static const droopingCount = 33;

  /// Of the Drooping, how many joined but have never checked in.
  static const neverCheckedInCount = 5;

  static const witnessId = 'preview-witness-rachel-adams';
  static const witnessName = 'Rachel Adams';

  // ---------------------------------------------------------------------------
  // The church (Cloud)
  // ---------------------------------------------------------------------------

  static const _firstNames = [
    'Abigail', 'Aaron', 'Amelia', 'Andrew', 'Anna', 'Benjamin', 'Caleb', 'Caroline', //
    'Charlotte', 'Christopher', 'Claire', 'Daniel', 'David', 'Eleanor', 'Elijah', 'Elizabeth',
    'Emily', 'Ethan', 'Evelyn', 'Gabriel', 'Grace', 'Hannah', 'Henry', 'Isaac',
    'Isabella', 'Jacob', 'James', 'Jonathan', 'Joseph', 'Joshua', 'Julia', 'Leah',
    'Levi', 'Lucy', 'Luke', 'Lydia', 'Madeline', 'Mark', 'Mary', 'Matthew',
    'Micah', 'Miriam', 'Naomi', 'Nathan', 'Noah', 'Olivia', 'Paul', 'Peter',
    'Rebecca', 'Ruth', 'Samuel', 'Sophia', 'Stephen', 'Susanna', 'Thomas', 'Timothy',
    'Victoria', 'William', 'Zachary', 'Esther',
  ];

  // 22 initials: with 60 first names, (i % 60, (7i + i ~/ 60) % 22) never
  // repeats across 220 people, so every name on the roster is distinct.
  static const _initials = 'ABCDEFGHIJKLMNOPRSTVWY';

  static String _rosterName(int i) {
    final first = _firstNames[i % _firstNames.length];
    final initial = _initials[(i * 7 + i ~/ _firstNames.length) % _initials.length];
    return '$first $initial.';
  }

  static String _rosterId(int i) => 'preview-runner-${i + 1}';

  static String _phoneFor(int i) => '+1555${(2010000 + i * 137).toString().padLeft(7, '0')}';

  static String _emailFor(int i) {
    final name = _rosterName(i).toLowerCase().replaceAll('.', '').replaceAll(' ', '.');
    return '$name@example.com';
  }

  /// 220 Runners: 121 Full Bloom, 66 Budding, 33 Drooping (5 of whom joined
  /// but have never checked in); 14 dormant (no check-in for 8+ days); 18
  /// without a Witness; 24 with two.
  static List<ChurchRosterEntry> roster() {
    final random = Random(300);
    final statuses = [
      for (var i = 0; i < fullBloomCount; i++) VineStatus.fullBloom,
      for (var i = 0; i < buddingCount; i++) VineStatus.budding,
      for (var i = 0; i < droopingCount; i++) VineStatus.drooping,
    ]..shuffle(random);

    var buddingSeen = 0;
    var droopingSeen = 0;
    final entries = <ChurchRosterEntry>[];

    for (var i = 0; i < rosterSize; i++) {
      final status = statuses[i];
      double vitality;
      int daysSince;
      switch (status) {
        case VineStatus.fullBloom:
          vitality = 0.76 + random.nextDouble() * 0.22;
          daysSince = random.nextInt(3);
        case VineStatus.budding:
          vitality = 0.46 + random.nextDouble() * 0.27;
          // Four Budding vines have gone quiet for over a week.
          daysSince = buddingSeen < 4 ? 8 + random.nextInt(6) : random.nextInt(5);
          buddingSeen++;
        case VineStatus.drooping:
          if (droopingSeen < neverCheckedInCount) {
            vitality = 0;
            daysSince = 999;
          } else if (droopingSeen < neverCheckedInCount + 10) {
            vitality = 0.12 + random.nextDouble() * 0.3;
            daysSince = 8 + random.nextInt(30);
          } else {
            vitality = 0.15 + random.nextDouble() * 0.28;
            daysSince = 2 + random.nextInt(5);
          }
          droopingSeen++;
      }

      final neverCheckedIn = daysSince >= 999;
      // Newcomers who have not begun yet have no Witness either; so do a
      // further thirteen spread through the church.
      final unpaired = neverCheckedIn || i % 17 == 3;
      final twoWitnesses = !unpaired && i % 9 == 4;

      entries.add(ChurchRosterEntry(
        id: _rosterId(i),
        runnerName: _rosterName(i),
        runnerPhoneNumber: _phoneFor(i),
        runnerEmail: _emailFor(i),
        witnesses: [
          if (!unpaired) _rosterWitness((i * 37 + 11) % rosterSize, shared: i % 11 != 5),
          if (twoWitnesses) _rosterWitness((i * 53 + 29) % rosterSize, shared: true),
        ],
        vitalityScore: double.parse(vitality.toStringAsFixed(2)),
        daysSinceLastCheckIn: daysSince,
      ));
    }
    return entries;
  }

  /// Witnesses are members of the church too, so they are drawn from the
  /// roster itself. One in eleven has not consented to share contact details
  /// with the church yet.
  static RosterWitness _rosterWitness(int i, {required bool shared}) => RosterWitness(
        name: _rosterName(i),
        phoneNumber: shared ? _phoneFor(i) : null,
        email: shared ? _emailFor(i) : null,
        hasSharedContact: shared,
      );

  /// Needs Attention, derived from [roster] the way `get_cloud_triage` would:
  /// struggling (Drooping and checking in), the Witnesses walking with them,
  /// the isolated (no Witness), and the quiet (dormant or never started).
  static CloudTriage triage(List<ChurchRosterEntry> roster) {
    final struggling = [
      for (final entry in roster)
        if (entry.vineStatus == VineStatus.drooping && !entry.hasNeverCheckedIn) entry,
    ]..sort((a, b) => a.vitalityScore.compareTo(b.vitalityScore));

    final witnessCounts = <String, ({RosterWitness witness, int count})>{};
    for (final entry in struggling) {
      if (entry.witnesses.isEmpty) continue;
      final witness = entry.witnesses.first;
      final existing = witnessCounts[witness.name];
      witnessCounts[witness.name] =
          (witness: witness, count: existing == null ? 1 : existing.count + 1);
    }

    return CloudTriage(
      struggling: [
        for (var i = 0; i < struggling.length; i++)
          TriageRunner(
            id: struggling[i].id,
            name: struggling[i].runnerName,
            score: struggling[i].vitalityScore,
            isDrooping: i % 3 == 0,
          ),
      ],
      witnessAlerts: [
        for (final alert in witnessCounts.values.take(9))
          TriageWitness(
            id: 'preview-witness-${alert.witness.name}',
            name: alert.witness.name,
            runnerCount: alert.count,
            hasSharedContact: alert.witness.hasSharedContact,
            phoneNumber: alert.witness.phoneNumber,
            email: alert.witness.email,
          ),
      ],
      isolated: [
        for (var i = 0; i < roster.length; i++)
          if (roster[i].isUnpaired && !roster[i].hasNeverCheckedIn)
            TriageRunner(id: roster[i].id, name: roster[i].runnerName, daysInChurch: 21 + (i * 13) % 90),
      ],
      dormant: [
        for (final entry in roster)
          if (entry.isDormant || entry.hasNeverCheckedIn)
            TriageRunner(
              id: entry.id,
              name: entry.runnerName,
              daysSinceCheckIn: entry.hasNeverCheckedIn ? null : entry.daysSinceLastCheckIn,
            ),
      ],
    );
  }

  /// How many Runners checked in within the last 30 days — the figure the
  /// k-anonymity lock compares against.
  static int trackedRunnerCount(List<ChurchRosterEntry> roster) =>
      roster.where((entry) => entry.daysSinceLastCheckIn <= 30).length;

  static const sabbathRestId = 'preview-dna-sabbath-rest';

  /// Three DNA Rhythms: a weekly Sabbath, a daily prayer for the city, and a
  /// seasonal fast that ends a few weeks from now.
  static List<DnaRhythm> dnaRhythms(DateTime today) => [
        const DnaRhythm(
          id: sabbathRestId,
          title: 'Sabbath Rest',
          category: RuleCategory.workRest,
          weeklyDays: {DateTime.sunday},
        ),
        const DnaRhythm(
          id: 'preview-dna-pray-for-the-city',
          title: 'Pray for the City',
          category: RuleCategory.abidingPrayer,
          frequency: RuleFrequency.daily,
          weeklyDays: {},
        ),
        DnaRhythm(
          id: 'preview-dna-forty-days',
          title: 'Forty Days of Fasting',
          category: RuleCategory.bodyPurity,
          weeklyDays: const {DateTime.wednesday},
          endsOn: DateTime(today.year, today.month, today.day + 26),
        ),
      ];

  /// Congregational Health: the DNA Rhythms first, then the rhythms enough
  /// members hold to be shown without singling anyone out.
  static const metrics = [
    ChurchRhythmMetric(title: 'Sabbath Rest', completionRate: 0.71),
    ChurchRhythmMetric(title: 'Pray for the City', completionRate: 0.64),
    ChurchRhythmMetric(title: 'Forty Days of Fasting', completionRate: 0.52),
    ChurchRhythmMetric(title: 'Read Scripture', completionRate: 0.78),
    ChurchRhythmMetric(title: 'Family Dinner Without Phones', completionRate: 0.74),
    ChurchRhythmMetric(title: 'Pray for 15 Minutes', completionRate: 0.69),
    ChurchRhythmMetric(title: 'Exercise Three Times a Week', completionRate: 0.58),
    ChurchRhythmMetric(title: 'Avoid Idle Scrolling', completionRate: 0.47),
    ChurchRhythmMetric(title: 'Weekly Date Night', completionRate: 0.43),
  ];

  /// Six unused invite codes and three already redeemed.
  static List<ChurchCode> churchCodes(DateTime now) => [
        for (final (code, days) in const [
          ('K7QM4XRT', 1),
          ('H2WJ9PLC', 3),
          ('T5NB8DVA', 6),
          ('R3FY6KMS', 9),
          ('M8GE2ZQW', 14),
          ('B4PX7NHU', 21),
        ])
          ChurchCode(code: code, generatedDate: now.subtract(Duration(days: days))),
        for (final (code, days) in const [('C9LD3TRV', 30), ('W6UA5JEK', 34), ('P2SH8MBY', 41)])
          ChurchCode(code: code, generatedDate: now.subtract(Duration(days: days)), isRedeemed: true),
      ];

  /// When the church's licenses next renew: the first of the month, five
  /// months on.
  static DateTime annualRenewalDate(DateTime now) => DateTime(now.year, now.month + 5, 1);

  // ---------------------------------------------------------------------------
  // Sarah as a Runner
  // ---------------------------------------------------------------------------

  /// When Sarah committed her Rule of Life — nine weeks ago.
  static DateTime ruleCommittedAt(DateTime now) => now.subtract(const Duration(days: 64));

  /// Four practices across the categories, two sins to throw off, and the
  /// church's Sabbath Rest.
  static List<RuleItem> ruleItems(DateTime now) {
    final created = ruleCommittedAt(now).subtract(const Duration(days: 1));
    return [
      RuleItem(
        id: 'preview-rule-pray',
        category: RuleCategory.abidingPrayer,
        title: 'pray for 15 minutes',
        isAnchorRhythm: true,
        createdAt: created,
      ),
      RuleItem(
        id: 'preview-rule-walk',
        category: RuleCategory.bodyPurity,
        title: 'walk for 30 minutes',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
        createdAt: created,
      ),
      RuleItem(
        id: 'preview-rule-dinner',
        category: RuleCategory.marriageFamily,
        title: 'have family dinner without phones',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.tuesday, DateTime.thursday, DateTime.sunday},
        createdAt: created,
      ),
      RuleItem(
        id: 'preview-rule-hospitality',
        category: RuleCategory.communityHospitality,
        title: 'invite someone to share a meal',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.saturday},
        createdAt: created,
      ),
      RuleItem(
        id: 'preview-rule-gossip',
        category: RuleCategory.communityHospitality,
        title: 'gossip',
        isThrowOff: true,
        createdAt: created,
      ),
      RuleItem(
        id: 'preview-rule-scrolling',
        category: RuleCategory.workRest,
        title: 'idle scrolling',
        isThrowOff: true,
        createdAt: created,
      ),
      RuleItem(
        id: 'preview-rule-sabbath',
        category: RuleCategory.workRest,
        title: 'Sabbath Rest',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
        isChurchMandated: true,
        createdAt: created,
        dnaRhythmId: sabbathRestId,
      ),
    ];
  }

  static DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

  /// Every day from the day after committing through yesterday, each due
  /// rhythm answered — about four days in five a Yes.
  static List<CheckInEntry> checkInHistory(List<RuleItem> items, DateTime now) {
    final random = Random(80);
    final today = _day(now);
    final first = _day(ruleCommittedAt(now)).add(const Duration(days: 1));
    final entries = <CheckInEntry>[];
    for (var day = first; day.isBefore(today); day = DateTime(day.year, day.month, day.day + 1)) {
      final isYesterday = DateTime(day.year, day.month, day.day + 1) == today;
      final responses = <String, bool>{};
      for (final item in items) {
        if (!item.scheduledFor(day)) continue;
        // Yesterday was a good day — the dashboard opens on a kept Anchor.
        responses[item.id] = isYesterday || random.nextDouble() < 0.82;
      }
      if (responses.isNotEmpty) entries.add(CheckInEntry(date: day, responses: responses));
    }
    return entries;
  }

  /// The season `get_runner_analytics` would compute from [history]: per
  /// rhythm completion over the scheduled days, and its weekly, 30-day and
  /// 90-day buckets (oldest first, null where nothing was due).
  static RunnerAnalytics analytics(List<RuleItem> items, List<CheckInEntry> history, DateTime now) {
    final today = _day(now);
    final answers = <DateTime, Map<String, bool>>{
      for (final entry in history) _day(entry.date): entry.responses,
    };

    double? rateOver(RuleItem item, int fromDaysAgo, int toDaysAgo) {
      var due = 0;
      var kept = 0;
      for (var back = fromDaysAgo; back >= toDaysAgo; back--) {
        final day = DateTime(today.year, today.month, today.day - back);
        final answer = answers[day]?[item.id];
        if (answer == null) continue;
        due++;
        if (answer) kept++;
      }
      return due == 0 ? null : kept / due;
    }

    List<double?> buckets(RuleItem item, int count, int size) => [
          for (var b = count - 1; b >= 0; b--) rateOver(item, (b + 1) * size, b * size + 1),
        ];

    final rhythms = <String, RhythmAnalytics>{};
    for (final item in items) {
      var due = 0;
      var kept = 0;
      var consecutiveMisses = 0;
      var streakOpen = true;
      for (var back = 1; back <= 180; back++) {
        final day = DateTime(today.year, today.month, today.day - back);
        final answer = answers[day]?[item.id];
        if (answer == null) continue;
        due++;
        if (answer) kept++;
        if (streakOpen) {
          if (answer) {
            streakOpen = false;
          } else {
            consecutiveMisses++;
          }
        }
      }
      rhythms[item.id] = RhythmAnalytics(
        ruleItemId: item.id,
        completionRate: due == 0 ? null : kept / due,
        scheduledDays: due,
        completedDays: kept,
        consecutiveMisses: consecutiveMisses,
        weekly: buckets(item, 8, 7),
        monthly: buckets(item, 6, 30),
        quarterly: buckets(item, 4, 90),
      );
    }

    final measured = [for (final r in rhythms.values) if (r.hasMeasurement) r.rate];
    return RunnerAnalytics(
      score: measured.isEmpty ? 0 : measured.reduce((a, b) => a + b) / measured.length,
      hasData: history.isNotEmpty,
      isDrooping: false,
      rhythms: rhythms,
    );
  }

  /// People and situations, one burden carried for her Witness, and one
  /// already answered. No photos.
  static List<PrayerItem> prayerItems(DateTime now) {
    final yesterday = now.subtract(const Duration(days: 1));
    return [
      PrayerItem(
        id: 'preview-prayer-mom',
        category: PrayerCategory.people,
        title: 'Mom',
        details: 'Recovery after her knee surgery, and patience with the slow weeks.',
        shareWithWitnesses: true,
        lastPrayedDate: yesterday,
      ),
      PrayerItem(
        id: 'preview-prayer-james',
        category: PrayerCategory.people,
        title: 'James Cooper',
        details: 'Starting a new job — wisdom, and good friends at work.',
        scripture: 'James 1:5',
        lastPrayedDate: yesterday,
      ),
      PrayerItem(
        id: 'preview-prayer-emily-mark',
        category: PrayerCategory.people,
        title: 'Emily & Mark',
        details: 'Expecting their first child. Health for mother and baby.',
      ),
      PrayerItem(
        id: 'preview-prayer-small-group',
        category: PrayerCategory.situations,
        title: 'Our small group',
        details: 'That we would grow more honest with one another.',
        shareWithWitnesses: true,
      ),
      PrayerItem(
        id: 'preview-prayer-food-pantry',
        category: PrayerCategory.situations,
        title: 'The church food pantry',
        details: 'More volunteers on Saturday mornings, and open doors with our neighbors.',
      ),
      PrayerItem(
        id: 'preview-prayer-rachel',
        category: PrayerCategory.witnessRequests,
        title: "Rachel's father",
        details: 'Peace for the family while he waits on test results.',
      ),
      PrayerItem(
        id: 'preview-prayer-linda',
        category: PrayerCategory.people,
        title: 'Aunt Linda',
        details: 'A clear scan.',
        isAnswered: true,
        answeredDate: now.subtract(const Duration(days: 9)),
        lastPrayedDate: now.subtract(const Duration(days: 10)),
      ),
    ];
  }

  static List<Witness> witnesses(DateTime now) => [
        Witness(id: witnessId, name: witnessName, since: ruleCommittedAt(now)),
      ];

  /// Coffee with Rachel on the calendar, and a lunch Sarah has proposed.
  static List<MeetingRequest> meetingRequests(DateTime now) {
    final today = _day(now);
    return [
      MeetingRequest(
        id: 'preview-meeting-coffee',
        witnessId: witnessId,
        witnessName: witnessName,
        time: DateTime(today.year, today.month, today.day + 2, 7),
        location: 'Common Grounds Coffee',
        status: MeetingStatus.confirmed,
      ),
      MeetingRequest(
        id: 'preview-meeting-lunch',
        witnessId: witnessId,
        witnessName: witnessName,
        time: DateTime(today.year, today.month, today.day + 6, 12),
        location: 'Main Street Deli',
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Sarah as a Witness
  // ---------------------------------------------------------------------------

  /// One week of a rhythm for the Witness heat map, oldest first, index 6 =
  /// [reference] (yesterday): null on a day it wasn't due, otherwise [kept]
  /// for that index.
  static List<bool?> _week(RuleItem item, DateTime reference, bool Function(int index) kept) => [
        for (var index = 0; index < 7; index++)
          item.scheduledFor(DateTime(reference.year, reference.month, reference.day - (6 - index)))
              ? kept(index)
              : null,
      ];

  static WatchedMeetingRequest _watchedMeeting(
    String id,
    DateTime time,
    String location, {
    MeetingStatus status = MeetingStatus.confirmed,
    String? activity,
  }) =>
      WatchedMeetingRequest(
        id: id,
        timeLabel: '${formatMeetingDate(time)} at ${formatMeetingTime(time)}',
        location: location,
        status: status,
        activity: activity,
        time: time,
      );

  /// Two Runners Sarah walks with: Emma, who is thriving, and David, who
  /// missed his Anchor Rhythm yesterday — so the nudge and text options show.
  static List<WatchedRunner> watchedRunners(DateTime now) {
    final today = _day(now);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final committed = today.subtract(const Duration(days: 90));

    WatchedRuleItem watched(
      RuleItem item, {
      required double rate,
      required bool Function(int index) kept,
    }) =>
        WatchedRuleItem(
          id: item.id,
          title: item.displayTitle,
          completionRate: rate,
          frequency: item.frequency,
          isAnchorRhythm: item.isAnchorRhythm,
          isChurchMandated: item.isChurchMandated,
          weekCompletion: _week(item, yesterday, kept),
        );

    final emmaPray = RuleItem(
      id: 'preview-emma-pray',
      category: RuleCategory.abidingPrayer,
      title: 'pray before work',
      isAnchorRhythm: true,
    );
    final emmaScripture =
        RuleItem(id: 'preview-emma-scripture', category: RuleCategory.abidingPrayer, title: 'read Scripture');
    final emmaGossip = RuleItem(
      id: 'preview-emma-gossip',
      category: RuleCategory.communityHospitality,
      title: 'gossip',
      isThrowOff: true,
    );
    final emmaSabbath = RuleItem(
      id: 'preview-emma-sabbath',
      category: RuleCategory.workRest,
      title: 'Sabbath Rest',
      frequency: RuleFrequency.weekly,
      weeklyDays: {DateTime.sunday},
      isChurchMandated: true,
    );

    final davidPray = RuleItem(
      id: 'preview-david-pray',
      category: RuleCategory.abidingPrayer,
      title: 'morning prayer',
      isAnchorRhythm: true,
    );
    final davidRun = RuleItem(
      id: 'preview-david-run',
      category: RuleCategory.bodyPurity,
      title: 'run three times a week',
      frequency: RuleFrequency.weekly,
      weeklyDays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
    );
    final davidDinner = RuleItem(
      id: 'preview-david-dinner',
      category: RuleCategory.marriageFamily,
      title: 'date night with Jenna',
      frequency: RuleFrequency.weekly,
      weeklyDays: {DateTime.friday},
    );
    final davidSabbath = RuleItem(
      id: 'preview-david-sabbath',
      category: RuleCategory.workRest,
      title: 'Sabbath Rest',
      frequency: RuleFrequency.weekly,
      weeklyDays: {DateTime.sunday},
      isChurchMandated: true,
    );

    return [
      WatchedRunner(
        id: 'preview-watched-emma',
        name: 'Emma Collins',
        phoneNumber: '+15555550142',
        hasCommittedRule: true,
        ruleCommittedAt: committed,
        seasonScore: 0.88,
        hasSeasonData: true,
        referenceDate: yesterday,
        lastCheckInDate: yesterday,
        ruleItems: [
          watched(emmaPray, rate: 0.94, kept: (_) => true),
          watched(emmaScripture, rate: 0.86, kept: (index) => index != 2),
          watched(emmaGossip, rate: 0.9, kept: (_) => true),
          watched(emmaSabbath, rate: 0.83, kept: (_) => true),
        ],
        sharedPrayerRequests: [
          WatchedPrayerItem(
            id: 'preview-emma-prayer-kate',
            title: 'My sister Kate',
            details: 'Settling into a new city — that she finds a church family.',
            lastPrayedDate: yesterday,
          ),
          WatchedPrayerItem(
            id: 'preview-emma-prayer-exam',
            title: 'Nursing board exam',
            details: 'Passed!',
            isAnswered: true,
            answeredDate: today.subtract(const Duration(days: 2)),
          ),
        ],
        witnessPrayers: [
          WatchedPrayerItem(id: 'preview-emma-intercession', title: 'Rest in a busy season'),
        ],
        pendingMeetings: [],
        confirmedMeetings: [
          _watchedMeeting(
            'preview-emma-lunch',
            DateTime(today.year, today.month, today.day + 3, 12),
            'Main Street Deli',
            activity: 'Lunch',
          ),
        ],
      ),
      WatchedRunner(
        id: 'preview-watched-david',
        name: 'David Brooks',
        phoneNumber: '+15555550178',
        hasCommittedRule: true,
        ruleCommittedAt: committed,
        seasonScore: 0.61,
        hasSeasonData: true,
        referenceDate: yesterday,
        lastCheckInDate: yesterday,
        ruleItems: [
          // Yesterday (index 6) — the missed Anchor.
          watched(davidPray, rate: 0.66, kept: (index) => index != 6 && index != 2),
          watched(davidRun, rate: 0.55, kept: (index) => index.isEven),
          watched(davidDinner, rate: 0.7, kept: (_) => true),
          watched(davidSabbath, rate: 0.62, kept: (_) => false),
        ],
        sharedPrayerRequests: [
          WatchedPrayerItem(
            id: 'preview-david-prayer-job',
            title: 'A decision about a job offer',
            details: 'Wisdom, and peace for Jenna and me about moving.',
          ),
        ],
        witnessPrayers: [
          WatchedPrayerItem(id: 'preview-david-intercession', title: 'Strength this week'),
        ],
        pendingMeetings: [
          _watchedMeeting(
            'preview-david-coffee',
            DateTime(today.year, today.month, today.day + 1, 7, 30),
            'Common Grounds Coffee',
            status: MeetingStatus.pendingResponse,
          ),
        ],
        confirmedMeetings: [],
      ),
    ];
  }
}
