import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/dna_rhythm.dart';
import 'package:trellis/models/rule_item.dart';
import 'package:trellis/screens/runner_shell.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/launch_link.dart';
import 'package:trellis/widgets/vine_visualizer.dart';

/// The second TestFlight feedback round (reports 27–38): reminder taps land on
/// their tab, DNA Rhythm seasons, the email chooser, and the Witness's line
/// under an empty trellis.
void main() {
  group('DnaRhythm seasons', () {
    test('a season is read from and written to the row as a plain date', () {
      final rhythm = DnaRhythm.fromRow({
        'id': 'dna-1',
        'title': 'Lenten Fast',
        'category': 'body_purity',
        'frequency': 'weekly',
        'weekly_days': [5],
        'ends_on': '2026-04-05',
      });
      expect(rhythm.id, 'dna-1');
      expect(rhythm.endsOn, DateTime(2026, 4, 5));
      expect(rhythm.seasonLabel, 'Through Apr 5, 2026');
      expect(rhythm.toInsertRow('church-1')['ends_on'], '2026-04-05');
      expect(rhythm.toUpdateRow()['ends_on'], '2026-04-05');
    });

    test('a year-round rhythm sends no ends_on on insert (older databases refuse the column)', () {
      const rhythm = DnaRhythm(title: 'Sabbath Rest', category: RuleCategory.workRest);
      expect(rhythm.endsOn, isNull);
      expect(rhythm.seasonLabel, 'Year-round');
      expect(rhythm.toInsertRow('church-1').containsKey('ends_on'), isFalse);
      // An edit can clear a season back to year-round once the column exists…
      expect(rhythm.toUpdateRow().containsKey('ends_on'), isTrue);
      expect(rhythm.toUpdateRow()['ends_on'], isNull);
      // …and leaves it out entirely before then.
      expect(rhythm.toUpdateRow(includeSeason: false).containsKey('ends_on'), isFalse);
    });

    test('a row without ends_on (before migration 023) reads as year-round', () {
      final rhythm = DnaRhythm.fromRow({
        'title': 'Sabbath Rest',
        'category': 'work_rest',
        'frequency': 'weekly',
        'weekly_days': [7],
      });
      expect(rhythm.id, isNull);
      expect(rhythm.endsOn, isNull);
      expect(rhythm.hasEnded(DateTime(2030)), isFalse);
    });

    test('hasEnded is true only from the day after the last day', () {
      final rhythm = DnaRhythm(
        title: 'Lent',
        category: RuleCategory.abidingPrayer,
        endsOn: DateTime(2026, 4, 5),
      );
      expect(rhythm.hasEnded(DateTime(2026, 4, 5, 23, 59)), isFalse);
      expect(rhythm.hasEnded(DateTime(2026, 4, 6, 0, 1)), isTrue);
    });

    test('a rule item reads the DNA link it came from, tolerating its absence', () {
      final linked = RuleItem.fromRow({
        'id': 'r1',
        'category': 'work_rest',
        'title': 'Sabbath Rest',
        'frequency': 'weekly',
        'is_church_mandated': true,
        'dna_rhythm_id': 'dna-1',
      });
      expect(linked.dnaRhythmId, 'dna-1');
      final own = RuleItem.fromRow({
        'id': 'r2',
        'category': 'work_rest',
        'title': 'Sabbath',
        'frequency': 'weekly',
      });
      expect(own.dnaRhythmId, isNull);
    });
  });

  group('reminder taps', () {
    test('the Runner tabs are in bottom-bar order, so a payload maps to an index', () {
      expect(RunnerTab.values, [
        RunnerTab.dashboard,
        RunnerTab.ruleOfLife,
        RunnerTab.prayer,
        RunnerTab.connect,
      ]);
      expect(RunnerTab.ruleOfLife.index, 1);
      expect(RunnerTab.prayer.index, 2);
    });
  });

  group('email chooser links', () {
    test('Gmail and Outlook compose links carry the address, subject and body, spaces as %20',
        () {
      final gmail = gmailComposeUri('pastor@example.com', subject: 'Thinking of you', body: 'Hi Sam');
      expect(gmail.scheme, 'googlegmail');
      expect(gmail.toString(), contains('to=pastor%40example.com'));
      expect(gmail.toString(), contains('subject=Thinking%20of%20you'));
      expect(gmail.toString(), contains('body=Hi%20Sam'));
      expect(gmail.toString(), isNot(contains('+')));

      final outlook = outlookComposeUri(' pastor@example.com ');
      expect(outlook.scheme, 'ms-outlook');
      expect(outlook.host, 'compose');
      expect(outlook.toString(), 'ms-outlook://compose?to=pastor%40example.com');
    });

    test('the church license page is one address, on the www host', () {
      expect(churchLicenseUrl, 'https://www.unhinderedlives.com/trellis');
    });
  });

  group('empty trellis caption', () {
    Widget host(Widget child) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    testWidgets('a Runner reads their own line by default', (tester) async {
      await tester.pumpWidget(host(
        const VineVisualizerCard(vitalityScore: 0, isDrooping: false, hasData: false),
      ));
      expect(find.text('Stick to Your Rule and Watch Yourself Grow'), findsOneWidget);
    });

    testWidgets("a Witness reads the line about the Runner they're watching", (tester) async {
      await tester.pumpWidget(host(
        const VineVisualizerCard(
          vitalityScore: 0,
          isDrooping: false,
          hasData: false,
          showTitle: false,
          emptyCaption: 'Hold them accountable, and watch them grow.',
        ),
      ));
      expect(find.text('Hold them accountable, and watch them grow.'), findsOneWidget);
      expect(find.text('Stick to Your Rule and Watch Yourself Grow'), findsNothing);
    });
  });
}
