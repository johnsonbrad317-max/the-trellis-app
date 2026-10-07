import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/getting_started_plate.dart';

void main() {
  group('gettingStartedSteps', () {
    test('a brand-new Runner has three steps, the check-in waiting on the Rule', () {
      final steps = gettingStartedSteps(
        hasCommittedRule: false,
        hasOwnRhythms: false,
        hasWitness: false,
        hasCheckedIn: false,
      );
      expect(steps.map((s) => s.title), [
        'Choose your Rule of Life',
        'Invite a Witness',
        'Make your first check-in',
      ]);
      expect(steps.map((s) => s.done), [false, false, false]);
      expect(steps.map((s) => s.available), [true, true, false]);
      expect(steps.first.detail, contains('ready-made Rule'));
    });

    test('rhythms already chosen but not committed point to committing', () {
      final steps = gettingStartedSteps(
        hasCommittedRule: false,
        hasOwnRhythms: true,
        hasWitness: false,
        hasCheckedIn: false,
      );
      expect(steps.first.detail, contains('commit'));
    });

    test('committing opens the check-in step; doing everything finishes the list', () {
      final committed = gettingStartedSteps(
        hasCommittedRule: true,
        hasOwnRhythms: true,
        hasWitness: false,
        hasCheckedIn: false,
      );
      expect(committed.last.available, isTrue);

      final all = gettingStartedSteps(
        hasCommittedRule: true,
        hasOwnRhythms: true,
        hasWitness: true,
        hasCheckedIn: true,
      );
      expect(all.every((s) => s.done), isTrue);
    });
  });

  testWidgets('a Runner who has done all three sees no checklist', (tester) async {
    // The offline sample Runner has a committed Rule, a Witness and check-ins.
    final profile = RunnerProfile.preview();
    expect(GettingStartedPlate.isNeeded(profile), isFalse);

    // Strip it back to a new Runner and the plate has three numbered steps.
    profile.checkInHistory.clear();
    profile.witnesses.clear();
    profile.hasCommittedRule = false;
    expect(GettingStartedPlate.isNeeded(profile), isTrue);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: GettingStartedPlate(profile: profile))),
    ));
    expect(find.text('Getting Started'), findsOneWidget);
    expect(find.text('3 steps to begin.'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Opens once your Rule of Life is committed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
