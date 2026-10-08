import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/screens/runner/daily_checkin_screen.dart';
import 'package:trellis/theme/app_theme.dart';

/// A day's check-in is locked in once given (supabase/migrations/031).
void main() {
  final now = DateTime.now();
  final yesterday = DateTime(now.year, now.month, now.day - 1);

  Future<void> open(WidgetTester tester, RunnerProfile profile) async {
    tester.view.physicalSize = const Size(440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DailyCheckInScreen(profile: profile),
    ));
    await tester.pumpAndSettle();
  }

  test('checkInFor finds the day regardless of the time of day', () {
    final profile = RunnerProfile.preview();
    expect(profile.checkInFor(yesterday.add(const Duration(hours: 15))), isNotNull);
    expect(profile.checkInFor(DateTime(now.year, now.month, now.day)), isNull);
  });

  testWidgets('a day already checked in shows its answers, locked', (tester) async {
    final profile = RunnerProfile.preview();
    final given = profile.checkInFor(yesterday)!;
    await open(tester, profile);

    expect(find.text('Checked in. Your answers are locked in.'), findsOneWidget);
    expect(find.text('Submit Check-In'), findsNothing);
    expect(find.text('Yes'), findsNWidgets(given.responses.length));

    // Tapping an answer changes nothing.
    await tester.tap(find.text('No').first);
    await tester.pumpAndSettle();
    expect(profile.checkInFor(yesterday)!.responses, given.responses);
  });

  testWidgets('a day not yet checked in can be answered and submitted', (tester) async {
    final profile = RunnerProfile.preview();
    profile.checkInHistory.removeWhere((entry) => profile.checkInFor(yesterday) == entry);
    await open(tester, profile);

    expect(find.text('A short retrospective — how did yesterday go?'), findsOneWidget);
    expect(find.text('Submit Check-In'), findsOneWidget);
  });
}
