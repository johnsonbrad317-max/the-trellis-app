import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/dna_rhythm.dart';
import 'package:trellis/models/rule_item.dart';
import 'package:trellis/widgets/bookplate_chip.dart';
import 'package:trellis/widgets/bookplate_dialog.dart';
import 'package:trellis/widgets/brass_lock.dart';

void main() {
  group('DnaRhythm', () {
    test('a new rhythm defaults to weekly on Sunday', () {
      const rhythm = DnaRhythm(title: 'Corporate Worship', category: RuleCategory.communityHospitality);
      final row = rhythm.toInsertRow('church-1');
      expect(row['frequency'], 'weekly');
      expect(row['weekly_days'], [DateTime.sunday]);
    });

    test('weekly days are sent sorted', () {
      const rhythm = DnaRhythm(
        title: 'Fast',
        category: RuleCategory.bodyPurity,
        weeklyDays: {DateTime.friday, DateTime.wednesday},
      );
      expect(rhythm.toUpdateRow()['weekly_days'], [DateTime.wednesday, DateTime.friday]);
    });

    test('a non-weekly rhythm never sends days', () {
      const rhythm = DnaRhythm(
        title: 'Annual Retreat',
        category: RuleCategory.abidingPrayer,
        frequency: RuleFrequency.annual,
        weeklyDays: {DateTime.monday},
      );
      expect(rhythm.toInsertRow('church-1')['weekly_days'], isEmpty);
    });

    test('reads weekly_days back from a row, tolerating a missing column', () {
      final withDays = DnaRhythm.fromRow({
        'title': 'Sabbath Rest',
        'category': 'work_rest',
        'frequency': 'weekly',
        'weekly_days': [7],
      });
      expect(withDays.weeklyDays, {DateTime.sunday});

      final legacy = DnaRhythm.fromRow({
        'title': 'Old Rhythm',
        'category': 'work_rest',
        'frequency': 'weekly',
      });
      expect(legacy.weeklyDays, isEmpty);
    });

    test('a mandated weekly RuleItem with its days is due on those days only', () {
      final item = RuleItem(
        id: 'r1',
        category: RuleCategory.workRest,
        title: 'Sabbath Rest',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
        isChurchMandated: true,
      );
      expect(item.scheduledFor(DateTime(2026, 10, 4)), isTrue); // a Sunday
      expect(item.scheduledFor(DateTime(2026, 10, 5)), isFalse); // a Monday
    });
  });

  group('BookplateChip', () {
    testWidgets('a disabled chip ignores taps but still shows its selection', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BookplateChip(label: 'Live', selected: false, onTap: () => taps++),
              BookplateChip(label: 'Locked', selected: true, enabled: false, onTap: () => taps++),
            ],
          ),
        ),
      ));

      await tester.tap(find.text('Locked'));
      expect(taps, 0);
      await tester.tap(find.text('Live'));
      expect(taps, 1);
      expect(find.text('Locked'), findsOneWidget);
    });
  });

  group('bookplate dialogs', () {
    Widget host(void Function(BuildContext) onTap) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: GestureDetector(onTap: () => onTap(context), child: const Text('open')),
              ),
            ),
          ),
        );

    testWidgets('showBookplateChoice resolves to the tapped option', (tester) async {
      String? picked;
      await tester.pumpWidget(host((context) async {
        picked = await showBookplateChoice<String>(
          context,
          title: 'Ask which Witness?',
          options: const [(label: 'Ann', value: 'a'), (label: 'Ben', value: 'b')],
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Ask which Witness?'), findsOneWidget);
      expect(find.byType(SimpleDialog), findsNothing);

      await tester.tap(find.text('Ben'));
      await tester.pumpAndSettle();
      expect(picked, 'b');
    });

    testWidgets('showBookplateForm hosts a TextField and rebuilds via its StateSetter',
        (tester) async {
      var count = 0;
      await tester.pumpWidget(host((context) {
        showBookplateForm<void>(
          context,
          title: 'Form',
          bodyBuilder: (context, setState) => Column(
            children: [
              const TextField(),
              Text('count $count'),
            ],
          ),
          actionsBuilder: (dialogContext, setState) => [
            BookplateButton(label: 'Bump', onPressed: () => setState(() => count++)),
          ],
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('count 0'), findsOneWidget);

      await tester.tap(find.text('Bump'));
      await tester.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
    });

    testWidgets('a compact BookplateButton shrinks to its label', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              BookplateButton(label: 'Request Unlock', compact: true, onPressed: () {}),
            ],
          ),
        ),
      ));
      final width = tester.getSize(find.byType(BookplateButton)).width;
      expect(width, lessThan(260));
    });
  });

  testWidgets('BrassLock paints without error at several sizes', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Row(children: [BrassLock(size: 12), BrassLock(), BrassLock(size: 28)]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrassLock), findsNWidgets(3));
  });
}
