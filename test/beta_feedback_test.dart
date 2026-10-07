import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/check_in_entry.dart';
import 'package:trellis/models/church_roster_entry.dart';
import 'package:trellis/models/phone_number.dart';
import 'package:trellis/models/prayer_item.dart';
import 'package:trellis/models/rule_item.dart';
import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/models/user_role.dart';
import 'package:trellis/models/watched_runner.dart';
import 'package:trellis/models/witness_messages.dart';
import 'package:trellis/services/reminder_sync.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/bookplate_app_bar.dart';
import 'package:trellis/widgets/bookplate_time_picker.dart';
import 'package:trellis/widgets/keyboard_host.dart';
import 'package:trellis/widgets/launch_link.dart';
import 'package:trellis/widgets/trellis_scaffold.dart';
import 'package:trellis/widgets/vine_frame.dart';

/// Guards for what the first round of TestFlight feedback turned up.
void main() {
  // ---------------------------------------------------------------------------
  // Phone numbers
  // ---------------------------------------------------------------------------
  group('normalizePhoneNumber', () {
    test('accepts US numbers the way people write them', () {
      for (final input in [
        '8165551234',
        '816-555-1234',
        '(816) 555-1234',
        '816.555.1234',
        '1 816 555 1234',
        '+1 (816) 555-1234',
        '  816 555 1234  ',
      ]) {
        expect(normalizePhoneNumber(input), '+18165551234', reason: input);
      }
    });

    test('keeps an international number that starts with +', () {
      expect(normalizePhoneNumber('+44 20 7946 0958'), '+442079460958');
    });

    test('rejects what cannot be a phone number', () {
      for (final input in [
        '',
        '   ',
        'call me',
        '555-1234', // seven digits, no area code
        '816555123', // nine digits
        '81655512345', // eleven digits not starting with 1
        '0165551234', // area code cannot start with 0
        '8161551234', // exchange cannot start with 1
        '+12', // too short for any country
        '+1234567890123456', // longer than any real number
        '816-555-1234 ext 5',
      ]) {
        expect(normalizePhoneNumber(input), isNull, reason: input);
      }
    });

    test('formats a stored US number for display and leaves others alone', () {
      expect(formatPhoneNumber('+18165551234'), '(816) 555-1234');
      expect(formatPhoneNumber('+442079460958'), '+442079460958');
    });
  });

  group('smsUri', () {
    test('addresses a US number in international form (best chance of iMessage)', () {
      expect(smsUri('(816) 555-1234').path, '+18165551234');
      expect(smsUri('8165551234', body: 'Hi there').toString(), 'sms:+18165551234?body=Hi%20there');
    });

    test('still produces a link for a number it cannot normalize', () {
      expect(smsUri('555-1234').path, '5551234');
    });
  });

  // ---------------------------------------------------------------------------
  // The texts a Witness sends
  // ---------------------------------------------------------------------------
  group('witnessTextFor', () {
    test('each situation sends exactly the wording the owner approved', () {
      String text(WitnessTextReason reason) => witnessTextFor(reason, firstName: 'Melanie');

      expect(
        text(WitnessTextReason.missedAnchor),
        'Hey Melanie - I saw you missed one of your anchor rhythms yesterday. Just wanted to '
        "let you know I'm praying for you, and I'd love to chat today if you're free.",
      );
      expect(
        text(WitnessTextReason.hardWeek),
        "Hey Melanie, looks like it's been a tough week. Just checking in to see how you're "
        "doing. Do you have time for a call today? I'd love to catch up.",
      );
      expect(
        text(WitnessTextReason.goneQuiet),
        "Hey Melanie - I noticed it's been a few days since you checked in. Just wanted to "
        "reach out and see how you're holding up. Let me know if you have time to connect "
        'later this week.',
      );
      expect(
        text(WitnessTextReason.gettingStarted),
        "Hey Melanie, I'm really glad we're doing this together. Whenever you get your "
        "rhythms set up, I'd love to hear what you landed on so I can be praying for you.",
      );
      expect(
        text(WitnessTextReason.thriving),
        "Hey Melanie - I saw you had a great week sticking to your Rule of Life. It's really "
        "encouraging to see. Just wanted to let you know I'm praying for you.",
      );
      expect(
        text(WitnessTextReason.prayed),
        'Hey Melanie, I just spent some time praying for you and for the things you have '
        'shared with me. I am with you in this. How can I keep praying this week?',
      );
    });

    test('no draft names a rhythm, and a blank name still reads', () {
      for (final reason in WitnessTextReason.values) {
        // The function is not even given a rhythm's title; this pins the
        // wording that stands in for one.
        expect(
          witnessTextFor(reason, firstName: 'Sam').toLowerCase(),
          isNot(contains('purity')),
          reason: '$reason',
        );
      }
      expect(witnessTextFor(WitnessTextReason.prayed, firstName: '  '), startsWith('Hey friend,'));
    });
  });

  // ---------------------------------------------------------------------------
  // The first week, then "set"
  // ---------------------------------------------------------------------------
  group('RuleItem settle period', () {
    final committed = DateTime(2026, 10, 1, 9);
    RuleItem item({DateTime? createdAt, DateTime? unlockedUntil}) => RuleItem(
          id: 'r',
          category: RuleCategory.abidingPrayer,
          title: 'pray',
          createdAt: createdAt,
          unlockedUntil: unlockedUntil,
        );

    test('free for seven days after committing, then set', () {
      final rhythm = item(createdAt: DateTime(2026, 9, 20));
      expect(rhythm.settlesAt(committed), DateTime(2026, 10, 8, 9));
      expect(
        rhythm.isSetAt(DateTime(2026, 10, 8, 8, 59), ruleCommittedAt: committed, hasWitness: true),
        isFalse,
      );
      expect(
        rhythm.isSetAt(DateTime(2026, 10, 8, 9), ruleCommittedAt: committed, hasWitness: true),
        isTrue,
      );
    });

    test('a rhythm added later gets its own seven days', () {
      final later = item(createdAt: DateTime(2026, 10, 20, 12));
      expect(later.settlesAt(committed), DateTime(2026, 10, 27, 12));
      expect(
        later.isSetAt(DateTime(2026, 10, 25), ruleCommittedAt: committed, hasWitness: true),
        isFalse,
      );
    });

    test('never set before committing, or with no Witness to ask', () {
      final rhythm = item(createdAt: DateTime(2026, 1, 1));
      final longAfter = DateTime(2027);
      expect(rhythm.isSetAt(longAfter, ruleCommittedAt: null, hasWitness: true), isFalse);
      expect(rhythm.isSetAt(longAfter, ruleCommittedAt: committed, hasWitness: false), isFalse);
    });

    test("a Witness's approval opens it until the deadline, then it is set again", () {
      final rhythm = item(
        createdAt: DateTime(2026, 1, 1),
        unlockedUntil: DateTime(2026, 11, 2, 15),
      );
      expect(
        rhythm.isSetAt(DateTime(2026, 11, 2, 14), ruleCommittedAt: committed, hasWitness: true),
        isFalse,
      );
      expect(
        rhythm.isSetAt(DateTime(2026, 11, 2, 15, 1), ruleCommittedAt: committed, hasWitness: true),
        isTrue,
      );
    });

    test('reads created_at and unlocked_until from a row, and tolerates their absence', () {
      final full = RuleItem.fromRow({
        'id': 'a',
        'category': 'abiding_prayer',
        'title': 't',
        'frequency': 'daily',
        'created_at': '2026-10-01T12:00:00+00:00',
        'unlocked_until': '2026-10-09T12:00:00+00:00',
      });
      expect(full.createdAt!.toUtc(), DateTime.utc(2026, 10, 1, 12));
      expect(full.unlockedUntil!.toUtc(), DateTime.utc(2026, 10, 9, 12));

      final old = RuleItem.fromRow({
        'id': 'a',
        'category': 'abiding_prayer',
        'title': 't',
        'frequency': 'daily',
      });
      expect(old.createdAt, isNull);
      expect(old.unlockedUntil, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // What counts as a miss, for a Witness
  // ---------------------------------------------------------------------------
  group('RunnerProfile.missedDayCounts', () {
    final now = DateTime(2026, 10, 10, 8);

    bool counts(DateTime day, {bool committed = true, DateTime? committedAt, DateTime? created}) =>
        RunnerProfile.missedDayCounts(
          day,
          hasCommittedRule: committed,
          committedAt: committedAt,
          rhythmCreatedAt: created,
          now: now,
        );

    test('nothing counts until the Rule of Life is committed', () {
      expect(counts(DateTime(2026, 10, 1), committed: false), isFalse);
    });

    test('counts only from the day after committing', () {
      final committedAt = DateTime.utc(2026, 10, 5, 15);
      expect(counts(DateTime(2026, 10, 4), committedAt: committedAt), isFalse);
      expect(counts(DateTime(2026, 10, 5), committedAt: committedAt), isFalse);
      expect(counts(DateTime(2026, 10, 6), committedAt: committedAt), isTrue);
    });

    test('never before the rhythm existed', () {
      final created = DateTime.utc(2026, 10, 7, 9);
      expect(counts(DateTime(2026, 10, 6), created: created), isFalse);
      expect(counts(DateTime(2026, 10, 7), created: created), isTrue);
    });

    test('yesterday and today are still open — not reported yet is not a miss', () {
      expect(counts(DateTime(2026, 10, 10)), isFalse); // today
      expect(counts(DateTime(2026, 10, 9)), isFalse); // yesterday: reported on today
      expect(counts(DateTime(2026, 10, 8)), isTrue);
    });

    test('a committed Runner with no recorded date counts as before (older database)', () {
      expect(counts(DateTime(2026, 10, 1)), isTrue);
    });
  });

  group('WatchedRunner standing', () {
    final today = DateTime.now();
    final reference = DateTime(today.year, today.month, today.day);

    /// [week] is oldest-first, ending on [reference] (today).
    WatchedRuleItem rhythm(List<bool?> week, {bool anchor = false}) => WatchedRuleItem(
          id: 'x',
          title: 'Rhythm',
          completionRate: 0,
          frequency: RuleFrequency.daily,
          isAnchorRhythm: anchor,
          weekCompletion: week,
        );

    WatchedRunner runner(
      List<WatchedRuleItem> items, {
      bool committed = true,
      DateTime? committedAt,
      DateTime? lastCheckIn,
    }) =>
        WatchedRunner(
          id: 'r',
          name: 'Melanie Johnson',
          ruleItems: items,
          sharedPrayerRequests: const [],
          pendingMeetings: const [],
          confirmedMeetings: const [],
          witnessPrayers: const [],
          referenceDate: reference,
          hasCommittedRule: committed,
          ruleCommittedAt: committedAt,
          lastCheckInDate: lastCheckIn,
        );

    test('a Runner who has not committed is getting started — never needs support', () {
      // Exactly the reported case: starter rhythms, an Anchor, nothing answered.
      final melanie = runner(
        [rhythm(const [null, null, null, null, null, null, null], anchor: true)],
        committed: false,
      );
      expect(melanie.standing, RunnerStanding.gettingStarted);
      expect(melanie.isStruggling, isFalse);
      expect(melanie.isDrifting, isFalse);
      expect(melanie.missedAnchorAlert, isNull);
      expect(melanie.weekRate, isNull);
    });

    test('a week with nothing due is not a bad week', () {
      final r = runner([rhythm(const [null, null, null, null, null, null, null])], lastCheckIn: today);
      expect(r.weekRate, isNull);
      expect(r.isStruggling, isFalse);
      expect(r.standing, RunnerStanding.thriving);
    });

    test('an Anchor answered "no" for yesterday raises the alert', () {
      final r = runner(
        [rhythm(const [true, true, true, true, true, false, null], anchor: true)],
        lastCheckIn: today,
      );
      expect(r.anchorMissedYesterday, isNotNull);
      expect(r.missedAnchorAlert, contains('yesterday'));
      expect(r.standing, RunnerStanding.needsSupport);
    });

    test('the same miss on a non-Anchor rhythm does not', () {
      final r = runner(
        [rhythm(const [true, true, true, true, true, false, null])],
        lastCheckIn: today,
      );
      expect(r.anchorMissedYesterday, isNull);
      expect(r.standing, RunnerStanding.thriving);
    });

    test('under half the week kept is a hard week', () {
      final r = runner(
        [rhythm(const [false, false, false, true, false, null, null])],
        lastCheckIn: today,
      );
      expect(r.weekRate, closeTo(0.2, 0.001));
      expect(r.isStruggling, isTrue);
    });

    test('quiet is measured from the commit when that is more recent', () {
      final committedToday = runner([rhythm(const [null, null, null, null, null, null, null])],
          committedAt: today);
      expect(committedToday.daysQuiet, 0);
      expect(committedToday.isDrifting, isFalse);

      final silent = runner(
        [rhythm(const [null, null, null, null, null, null, null])],
        committedAt: today.subtract(const Duration(days: 5)),
      );
      expect(silent.daysQuiet, 5);
      expect(silent.isDrifting, isTrue);
    });

    test("one rhythm's week: a dash when nothing was due, else its share", () {
      expect(rhythm(const [null, null, null, null, null, null, null]).weekRate, isNull);
      expect(rhythm(const [true, false, null, null, null, null, null]).weekRate, 0.5);
    });
  });

  // ---------------------------------------------------------------------------
  // Notification switches
  // ---------------------------------------------------------------------------
  group('NotificationCategory', () {
    test('a Runner cannot switch off the weekly roll-up; a Witness can', () {
      expect(NotificationCategory.weeklyRollUp.visibleForRole(UserRole.runner), isFalse);
      expect(NotificationCategory.weeklyRollUp.visibleForRole(UserRole.witness), isTrue);
      expect(NotificationCategory.weeklyRollUp.label, isNot(contains('to Witnesses')));
    });

    test('the daily check-in reminder has a switch, on the Runner side', () {
      expect(NotificationCategory.checkInReminder.visibleForRole(UserRole.runner), isTrue);
      expect(NotificationCategory.checkInReminder.visibleForRole(UserRole.witness), isFalse);
      expect(NotificationCategory.checkInReminder.dbKey, 'check_in_reminder');
    });

    test('database keys are unique', () {
      final keys = NotificationCategory.values.map((c) => c.dbKey).toSet();
      expect(keys, hasLength(NotificationCategory.values.length));
    });
  });

  // ---------------------------------------------------------------------------
  // Reminder planning
  // ---------------------------------------------------------------------------
  group('ReminderSync plans', () {
    final now = DateTime(2026, 10, 10, 6);
    final daily = RuleItem(id: 'd', category: RuleCategory.abidingPrayer, title: 'pray');

    test('check-in: off when switched off or with no Rule of Life', () {
      expect(
        ReminderSync.checkInPlanFor(
          switchedOn: false,
          ruleItems: [daily],
          history: const [],
          hour: 7,
          minute: 0,
          now: now,
        ).enabled,
        isFalse,
      );
      expect(
        ReminderSync.checkInPlanFor(
          switchedOn: true,
          ruleItems: const [],
          history: const [],
          hour: 7,
          minute: 0,
          now: now,
        ).enabled,
        isFalse,
      );
    });

    test('check-in: skips today once yesterday has been reported', () {
      final pending = ReminderSync.checkInPlanFor(
        switchedOn: true,
        ruleItems: [daily],
        history: const [],
        hour: 7,
        minute: 30,
        now: now,
      );
      expect(pending.enabled, isTrue);
      expect(pending.hour, 7);
      expect(pending.minute, 30);
      expect(pending.doneToday, isFalse);

      final done = ReminderSync.checkInPlanFor(
        switchedOn: true,
        ruleItems: [daily],
        history: [
          CheckInEntry(date: DateTime(2026, 10, 9), responses: const {'d': true}),
        ],
        hour: 7,
        minute: 30,
        now: now,
      );
      expect(done.doneToday, isTrue);
    });

    test('check-in: nothing was due yesterday means nothing to be reminded of today', () {
      // Oct 9 2026 is a Friday; a Sunday-only rhythm was not due.
      final sundayOnly = RuleItem(
        id: 's',
        category: RuleCategory.abidingPrayer,
        title: 'worship',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
      );
      expect(
        ReminderSync.checkInPlanFor(
          switchedOn: true,
          ruleItems: [sundayOnly],
          history: const [],
          hour: 7,
          minute: 0,
          now: now,
        ).doneToday,
        isTrue,
      );
    });

    test('prayer: on whenever switched on, even with nothing on the list; done once all are prayed for today', () {
      PrayerItem prayer({bool answered = false, DateTime? lastPrayed}) => PrayerItem(
            id: 'p${lastPrayed?.day}$answered',
            category: PrayerCategory.people,
            title: 'Ruby',
            isAnswered: answered,
            lastPrayedDate: lastPrayed,
          );

      // An empty (or fully answered) list is not "done": the reminder still
      // calls the person to pray at the time they chose.
      for (final prayers in [<PrayerItem>[], [prayer(answered: true)]]) {
        final plan = ReminderSync.prayerPlanFor(
          switchedOn: true,
          prayers: prayers,
          hour: 7,
          minute: 0,
          now: now,
        );
        expect(plan.enabled, isTrue);
        expect(plan.doneToday, isFalse);
      }
      expect(
        ReminderSync.prayerPlanFor(
          switchedOn: false,
          prayers: [prayer()],
          hour: 7,
          minute: 0,
          now: now,
        ).enabled,
        isFalse,
      );
      expect(
        ReminderSync.prayerPlanFor(
          switchedOn: true,
          prayers: [prayer(lastPrayed: DateTime(2026, 10, 10)), prayer(lastPrayed: DateTime(2026, 10, 9))],
          hour: 7,
          minute: 0,
          now: now,
        ).doneToday,
        isFalse,
      );
      expect(
        ReminderSync.prayerPlanFor(
          switchedOn: true,
          prayers: [prayer(lastPrayed: DateTime(2026, 10, 10)), prayer(answered: true)],
          hour: 7,
          minute: 0,
          now: now,
        ).doneToday,
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Church roster
  // ---------------------------------------------------------------------------
  group('ChurchRosterEntry', () {
    test('someone who has never checked in is not "dormant"', () {
      final never = ChurchRosterEntry.fromRow({
        'runner_id': 'r',
        'runner_name': 'New Person',
        'last_check_in_date': null,
        'vitality_score': 0,
      });
      expect(never.hasNeverCheckedIn, isTrue);
      expect(never.isDormant, isFalse);

      final quiet = ChurchRosterEntry.fromRow({
        'runner_id': 'r',
        'runner_name': 'Quiet Person',
        'last_check_in_date':
            DateTime.now().subtract(const Duration(days: 10)).toIso8601String().split('T').first,
        'vitality_score': 0.5,
      });
      expect(quiet.isDormant, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Time picker
  // ---------------------------------------------------------------------------
  group('time picker', () {
    test('spells the chosen time out', () {
      expect(formatTimeOfDay(hour12: 7, minute: 0, isPm: false), '7:00 AM');
      expect(formatTimeOfDay(hour12: 12, minute: 5, isPm: true), '12:05 PM');
    });

    testWidgets('shows the time in words and follows the AM/PM switch', (tester) async {
      TimeOfDay? picked;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () async {
                  picked = await showBookplateTimePicker(
                    context,
                    initialTime: const TimeOfDay(hour: 19, minute: 0),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('7:00 PM'), findsOneWidget);

      await tester.tap(find.text('AM'));
      await tester.pumpAndSettle();
      expect(find.text('7:00 AM'), findsOneWidget);
      expect(find.text('7:00 PM'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();
      expect(picked, const TimeOfDay(hour: 7, minute: 0));
    });
  });

  // ---------------------------------------------------------------------------
  // Keyboard manners
  // ---------------------------------------------------------------------------
  group('KeyboardHost', () {
    Widget app() => MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => KeyboardHost(child: child!),
          home: Scaffold(
            body: Column(
              children: [
                const TextField(key: ValueKey('field')),
                const SizedBox(height: 100, child: ColoredBox(color: Color(0x00000000))),
                Builder(
                  builder: (context) => Text(
                    'inset:${MediaQuery.viewInsetsOf(context).bottom.round()}',
                  ),
                ),
              ],
            ),
          ),
        );

    void raiseKeyboard(WidgetTester tester, {double height = 300}) {
      tester.view.viewInsets = FakeViewPadding(bottom: height * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
    }

    testWidgets('no Done bar while the keyboard is down', (tester) async {
      await tester.pumpWidget(app());
      expect(find.text('Done'), findsNothing);
    });

    testWidgets('a Done bar rides above the keyboard and closes it', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.pump();
      raiseKeyboard(tester);
      await tester.pump();

      expect(KeyboardHost.textFieldHasFocus(), isTrue);
      expect(find.text('Done'), findsOneWidget);
      // The bar sits directly on top of the keyboard.
      final bar = tester.getRect(find.text('Done'));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(bar.bottom, lessThanOrEqualTo(screen.height - 300));
      expect(bar.top, greaterThanOrEqualTo(screen.height - 300 - KeyboardHost.barHeight));

      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(KeyboardHost.textFieldHasFocus(), isFalse);
    });

    testWidgets('tapping empty space puts the keyboard away', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.pump();
      raiseKeyboard(tester);
      await tester.pump();
      expect(KeyboardHost.textFieldHasFocus(), isTrue);

      await tester.tapAt(const Offset(200, 110)); // the blank box under the field
      await tester.pump();
      expect(KeyboardHost.textFieldHasFocus(), isFalse);
    });

    testWidgets('tapping the field itself keeps the keyboard', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.pump();
      raiseKeyboard(tester);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.pump();
      expect(KeyboardHost.textFieldHasFocus(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // The screen frame
  // ---------------------------------------------------------------------------
  group('VineFrame', () {
    Future<void> pumpScreen(WidgetTester tester, {required int rows}) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: TrellisScaffold(
          appBar: const BookplateAppBar(title: 'Rule of Life'),
          body: Column(
            children: [
              for (var i = 0; i < rows; i++) SizedBox(height: 60, child: Text('row $i')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    double headerOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: find.byType(BookplateAppBar), matching: find.byType(AnimatedOpacity)),
        )
        .opacity;

    testWidgets('on a phone the page starts right under a 44px header below the status bar',
        (tester) async {
      await pumpScreen(tester, rows: 3);
      expect(VineFrame.vineSizeFor(440), 72);
      // status bar 62 + toolbar 44 + gap, then the screen's own 16 of padding.
      final firstRow = tester.getTopLeft(find.text('row 0')).dy;
      expect(firstRow, closeTo(62 + 44 + VineFrame.gap + 16, 0.5));
      // It used to start at 139 + 16.
      expect(firstRow, lessThan(139));
    });

    testWidgets('the header slides away on scroll down and returns on scroll up', (tester) async {
      await pumpScreen(tester, rows: 60);
      expect(headerOpacity(tester), 1);

      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(headerOpacity(tester), 0);
      // The page took the header's room: content now starts under the status bar.
      final viewportTop = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
      expect(viewportTop, closeTo(62 + VineFrame.gap, 0.5));

      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(headerOpacity(tester), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a page too short to scroll keeps its header', (tester) async {
      await pumpScreen(tester, rows: 3);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(headerOpacity(tester), 1);
    });

    testWidgets('the last row can scroll clear of the bottom vines', (tester) async {
      await pumpScreen(tester, rows: 60);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -20000));
      await tester.pumpAndSettle();
      final lastRowBottom = tester.getBottomLeft(find.text('row 59')).dy;
      // 956 tall; the bottom vines are 72 tall.
      expect(lastRowBottom, lessThanOrEqualTo(956 - 72));
    });
  });

  // ---------------------------------------------------------------------------
  // Source scans
  // ---------------------------------------------------------------------------
  group('source rules', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('every text field says how its keyboard should behave', () {
      // Sentences that don't capitalise were a beta complaint. A field must
      // set textCapitalization, or be a kind that has no use for it (a
      // keyboardType such as email/phone, or an obscured password).
      final offenders = <String>[];
      final opener = RegExp(r'\b(TextField|TextFormField)\(');
      for (final file in dartFiles) {
        final source = file.readAsStringSync();
        for (final match in opener.allMatches(source)) {
          // Walk to the matching close parenthesis.
          var depth = 0;
          var end = match.end - 1;
          for (var i = match.end - 1; i < source.length; i++) {
            final char = source[i];
            if (char == '(') depth++;
            if (char == ')') {
              depth--;
              if (depth == 0) {
                end = i;
                break;
              }
            }
          }
          final body = source.substring(match.start, end);
          final handled = body.contains('textCapitalization:') ||
              body.contains('keyboardType:') ||
              body.contains('obscureText:');
          if (!handled) {
            final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
            offenders.add('${file.path}:$line');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('sign-up no longer seeds starter rhythms, and asks for a phone number', () {
      // Account creation now happens on the sign-up form itself.
      final walkthrough = File('lib/screens/role_walkthrough_screen.dart').readAsStringSync();
      expect(walkthrough.contains('_seedBaseline'), isFalse);
      expect(walkthrough.contains('applyRuleOfLifeBaseline'), isFalse);
      expect(walkthrough.contains("'phone': phone"), isTrue);
      expect(walkthrough.contains('normalizePhoneNumber'), isTrue);
      expect(walkthrough.contains("labelText: 'Mobile Number'"), isTrue);
    });

    test('"Vitality" is no longer shown to anyone', () {
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          expect(
            RegExp(r'''['"][^'"]*\bVitality\b''').hasMatch(line),
            isFalse,
            reason: '${file.path}:${i + 1}',
          );
        }
      }
    });
  });
}
