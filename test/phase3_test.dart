import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/cloud_triage.dart';
import 'package:trellis/models/rhythm_analytics.dart';
import 'package:trellis/models/watched_runner.dart';
import 'package:trellis/widgets/bookplate_time_picker.dart';
import 'package:trellis/widgets/brass_chevron.dart';

void main() {
  group('RunnerAnalytics.fromJson', () {
    final json = <String, dynamic>{
      'score': 0.4375,
      'has_data': true,
      'is_drooping': true,
      'window_days': 180,
      'rhythms': [
        {
          'rule_item_id': 'a',
          'title': 'Pray',
          'completion_rate': 0.75,
          'scheduled': 100,
          'completed': 75,
          'consecutive_misses': 0,
          'weekly': [1, 0.5, null, 0.75],
          'monthly': [0.8],
          'quarterly': [],
        },
        {
          'rule_item_id': 'b',
          'title': 'New monthly rhythm',
          'completion_rate': null,
          'scheduled': 0,
          'completed': 0,
          'consecutive_misses': 3,
          'weekly': [],
          'monthly': [],
          'quarterly': [],
        },
      ],
    };

    test('reads the score, flags, and each rhythm by rule item id', () {
      final analytics = RunnerAnalytics.fromJson(json);
      expect(analytics.score, 0.4375);
      expect(analytics.hasData, isTrue);
      expect(analytics.isDrooping, isTrue);
      expect(analytics.rhythms.keys, {'a', 'b'});

      final pray = analytics.forItem('a')!;
      expect(pray.completionRate, 0.75);
      expect(pray.scheduledDays, 100);
      expect(pray.completedDays, 75);
      expect(pray.weekly, [1.0, 0.5, null, 0.75]);
    });

    test('a rhythm with nothing scheduled is unmeasured, not 0%', () {
      final fresh = RunnerAnalytics.fromJson(json).forItem('b')!;
      expect(fresh.completionRate, isNull);
      expect(fresh.hasMeasurement, isFalse);
      expect(fresh.rate, 0);
      expect(fresh.consecutiveMisses, 3);
    });

    test('an empty or missing payload is the bare trellis', () {
      expect(RunnerAnalytics.fromJson(const {}).hasData, isFalse);
      expect(const RunnerAnalytics.empty().score, 0);
      expect(const RunnerAnalytics.empty().rhythms, isEmpty);
    });
  });

  group('WatchedRunner season', () {
    WatchedRunner runner({double? season}) => WatchedRunner(
          id: 'r',
          name: 'Ruth Example',
          ruleItems: const [],
          sharedPrayerRequests: const [],
          pendingMeetings: const [],
          confirmedMeetings: const [],
          witnessPrayers: const [],
          referenceDate: DateTime(2026, 10, 3),
          seasonScore: season,
        );

    test('uses the server season score when it loaded', () {
      expect(runner(season: 0.62).vitalityScore, 0.62);
    });

    test('falls back to the trailing week when it did not', () {
      expect(runner().vitalityScore, 0);
    });
  });

  group('CloudTriage.fromJson', () {
    test('parses every category and the thresholds it was computed with', () {
      final triage = CloudTriage.fromJson({
        'struggling': [
          {'runner_id': 'r1', 'name': 'Ann Lee', 'score': 0.31, 'is_drooping': true},
        ],
        'isolated': [
          {'runner_id': 'r2', 'name': 'Bo Kim', 'days_in_church': 12},
        ],
        'dormant': [
          {'runner_id': 'r3', 'name': 'Cy Poe', 'days_since_check_in': null},
        ],
        'witness_alerts': [
          {
            'witness_id': 'w1',
            'name': 'Di Fox',
            'runner_count': 2,
            'consent': false,
            'phone_number': null,
            'email': null,
          },
        ],
        'thresholds': {'struggling_below': 0.45, 'stale_days': 7},
      });

      expect(triage.isEmpty, isFalse);
      expect(triage.struggling.single.score, 0.31);
      expect(triage.struggling.single.isDrooping, isTrue);
      expect(triage.struggling.single.firstName, 'Ann');
      expect(triage.isolated.single.daysInChurch, 12);
      expect(triage.dormant.single.daysSinceCheckIn, isNull);
      expect(triage.witnessAlerts.single.hasSharedContact, isFalse);
      expect(triage.witnessAlerts.single.phoneNumber, isNull);
      expect(triage.witnessAlerts.single.runnerCount, 2);
      expect(triage.strugglingBelow, 0.45);
      expect(triage.staleDays, 7);
    });

    test('an all-clear is empty', () {
      expect(CloudTriage.fromJson(const {}).isEmpty, isTrue);
      expect(const CloudTriage.empty().isEmpty, isTrue);
    });
  });

  group('showBookplateTimePicker', () {
    Widget host(void Function(BuildContext) onTap) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: GestureDetector(onTap: () => onTap(context), child: const Text('open')),
              ),
            ),
          ),
        );

    testWidgets('returns the initial time when set untouched', (tester) async {
      TimeOfDay? picked;
      await tester.pumpWidget(host((context) async {
        picked = await showBookplateTimePicker(
          context,
          initialTime: const TimeOfDay(hour: 21, minute: 5),
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing);
      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();
      expect(picked, const TimeOfDay(hour: 21, minute: 5));
    });

    testWidgets('AM/PM chips change the period', (tester) async {
      TimeOfDay? picked;
      await tester.pumpWidget(host((context) async {
        picked = await showBookplateTimePicker(
          context,
          initialTime: const TimeOfDay(hour: 21, minute: 5),
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();
      expect(picked, const TimeOfDay(hour: 9, minute: 5));
    });

    testWidgets('noon and midnight keep the right hour', (tester) async {
      TimeOfDay? picked;
      await tester.pumpWidget(host((context) async {
        picked = await showBookplateTimePicker(
          context,
          initialTime: const TimeOfDay(hour: 0, minute: 0),
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();
      expect(picked, const TimeOfDay(hour: 0, minute: 0)); // 12:00 AM

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();
      expect(picked, const TimeOfDay(hour: 12, minute: 0)); // 12:00 PM
    });
  });

  testWidgets('BrassChevron renders open and closed', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Row(children: [BrassChevron(open: false), BrassChevron(open: true)])),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrassChevron), findsNWidgets(2));
  });
}
