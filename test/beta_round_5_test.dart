import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/prayer_item.dart';
import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/models/witness.dart';
import 'package:trellis/screens/runner/prayer_garden_screen.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/prayer_completion_view.dart';
import 'package:trellis/widgets/pull_to_refresh.dart';

/// TestFlight round 5: first names in prayer texts, editing a prayer,
/// choosing which Witnesses see a shared one, and pull to refresh.
void main() {
  test('a prayer text greets the person by first name', () {
    expect(const PrayerCompletionContact(label: 'Kevin Barb', phoneNumber: '1').firstName, 'Kevin');
    expect(const PrayerCompletionContact(label: '  Melanie  ', phoneNumber: '1').firstName, 'Melanie');
    expect(const PrayerCompletionContact(label: 'Nathaniel  McComb', phoneNumber: '1').firstName,
        'Nathaniel');
  });

  test('who a shared prayer goes to reads safely', () {
    PrayerItem row(Object? sharedWith) => PrayerItem.fromRow({
          'id': 'p',
          'category': 'people',
          'title': 'Kevin',
          'share_with_witnesses': true,
          'shared_with': sharedWith,
        });
    expect(row(null).sharedWith, isNull);
    expect(row(['a', 'b']).sharedWith, ['a', 'b']);
    // A database before migration 033 has no column at all: everyone.
    expect(PrayerItem.fromRow({'id': 'p', 'category': 'people', 'title': 'K'}).sharedWith, isNull);
  });

  group('Prayer Garden', () {
    Future<RunnerProfile> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(440, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final profile = RunnerProfile.preview();
      profile.witnesses.add(Witness(id: 'w2', name: 'Mark Crowe', since: DateTime(2026, 9, 1)));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: PrayerGardenScreen(profile: profile)),
      ));
      await tester.pumpAndSettle();
      return profile;
    }

    testWidgets('a prayer opens in the edit form, filled in', (tester) async {
      final profile = await open(tester);
      final person = profile.prayerItems.firstWhere(
        (item) => item.category == PrayerCategory.people && !item.isAnswered,
      );

      await tester.tap(find.bySemanticsLabel('Edit/Manage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('People').last);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Edit').first);
      await tester.pumpAndSettle();

      expect(find.text('Edit Prayer'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.widgetWithText(TextField, person.title), findsOneWidget);
    });

    testWidgets('sharing with two Witnesses offers a choice of each', (tester) async {
      final profile = await open(tester);
      final witnessFirstName = profile.witnesses.first.name.split(' ').first;

      await tester.tap(find.bySemanticsLabel('Edit/Manage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('People').last);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Edit').first);
      await tester.pumpAndSettle();

      final toggle = find.text('Share with Witness(es)');
      await tester.ensureVisible(toggle);
      if (find.text('Share with').evaluate().isEmpty) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      expect(find.text('Share with'), findsOneWidget);
      expect(find.text(witnessFirstName), findsOneWidget);
      expect(find.text('Mark'), findsOneWidget);
      expect(find.textContaining('gets a notification'), findsOneWidget);
    });
  });

  testWidgets('pulling down refreshes', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: PullToRefresh(
          onRefresh: () async => refreshed++,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 100, child: Text('Runners'))],
          ),
        ),
      ),
    ));
    await tester.fling(find.text('Runners'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });
}
