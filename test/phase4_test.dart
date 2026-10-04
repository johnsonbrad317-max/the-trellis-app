import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/support_request.dart';
import 'package:trellis/widgets/bookplate_app_bar.dart';
import 'package:trellis/widgets/bookplate_dialog.dart';
import 'package:trellis/widgets/bookplate_plate.dart';
import 'package:trellis/widgets/brass_glyph.dart';

void main() {
  group('SupportRequest', () {
    final row = <String, dynamic>{
      'id': 's1',
      'runner_id': 'r1',
      'kind': 'prayer',
      'note': null,
      'created_at': '2026-10-03T12:00:00Z',
      'runner': {'name': 'Ruth Example'},
      'rule_item': {'title': 'Read Scripture for 15 Minutes'},
    };

    test('reads a row with its embedded runner and rhythm', () {
      final request = SupportRequest.fromRow(row);
      expect(request.kind, SupportRequestKind.prayer);
      expect(request.runnerName, 'Ruth Example');
      expect(request.firstName, 'Ruth');
      expect(request.ruleItemTitle, 'Read Scripture for 15 Minutes');
      expect(
        request.summary,
        'Ruth Example is asking you to pray about "Read Scripture for 15 Minutes".',
      );
    });

    test('a meeting request with no rhythm reads cleanly', () {
      final request = SupportRequest.fromRow({...row, 'kind': 'meeting', 'rule_item': null});
      expect(request.kind, SupportRequestKind.meeting);
      expect(request.summary, 'Ruth Example would like to meet.');
    });

    test('a missing runner name falls back rather than crashing', () {
      expect(SupportRequest.fromRow({...row, 'runner': null}).runnerName, 'A Runner');
    });

    test('kind round-trips through its database value', () {
      for (final kind in SupportRequestKind.values) {
        expect(supportRequestKindFromDb(kind.dbValue), kind);
      }
      expect(() => supportRequestKindFromDb('nonsense'), throwsArgumentError);
    });
  });

  group('BrassGlyph', () {
    testWidgets('every glyph paints without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Wrap(children: [for (final kind in BrassGlyphKind.values) BrassGlyph(kind)]),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(BrassGlyph), findsNWidgets(BrassGlyphKind.values.length));
    });

    testWidgets('BrassGlyphButton taps, and is inert when disabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              BrassGlyphButton(
                kind: BrassGlyphKind.plus,
                semanticLabel: 'Add',
                onPressed: () => taps++,
              ),
              const BrassGlyphButton(
                kind: BrassGlyphKind.close,
                semanticLabel: 'Close',
                onPressed: null,
              ),
            ],
          ),
        ),
      ));

      expect(tester.getSize(find.byType(BrassGlyphButton).first), const Size(44, 44));
      await tester.tap(find.byType(BrassGlyphButton).first);
      await tester.tap(find.byType(BrassGlyphButton).last);
      expect(taps, 1);
    });
  });

  group('plate kit', () {
    testWidgets('BookplatePlate and BookplateRow are tappable', (tester) async {
      var plateTaps = 0;
      var rowTaps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BookplatePlate(onTap: () => plateTaps++, child: const Text('plate')),
              BookplateRow(title: 'row', subtitle: 'sub', onTap: () => rowTaps++),
              const BookplateDivider(),
            ],
          ),
        ),
      ));

      await tester.tap(find.text('plate'));
      await tester.tap(find.text('row'));
      expect(plateTaps, 1);
      expect(rowTaps, 1);
      expect(find.text('sub'), findsOneWidget);
    });

    testWidgets('BookplateCheckbox toggles and locks', (tester) async {
      var value = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                BookplateCheckboxRow(
                  value: value,
                  onChanged: (v) => setState(() => value = v),
                  label: const Text('I agree'),
                ),
                const BookplateCheckbox(value: true, onChanged: null),
              ],
            ),
          ),
        ),
      ));

      await tester.tap(find.text('I agree'));
      await tester.pump();
      expect(value, isTrue);
      await tester.tap(find.byType(BookplateCheckbox).last);
      await tester.pump();
      expect(value, isTrue);
    });

    testWidgets('a busy BookplateButton ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BookplateButton(label: 'Send', busy: true, onPressed: () => taps++),
              BookplateButton(label: 'Link', variant: BookplateButtonVariant.link, onPressed: () => taps += 10),
            ],
          ),
        ),
      ));

      expect(find.byType(BookplateSpinner), findsOneWidget);
      await tester.tap(find.text('Send'));
      await tester.tap(find.text('Link'));
      expect(taps, 10);
    });
  });

  group('showBookplateSheet', () {
    testWidgets('rises, shows content, and resolves with a popped value', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () async {
                  result = await showBookplateSheet<String>(
                    context,
                    builder: (sheetContext) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('A sheet'),
                        BookplateButton(
                          label: 'Pick',
                          onPressed: () => Navigator.of(sheetContext).pop('picked'),
                        ),
                      ],
                    ),
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
      expect(find.text('A sheet'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      expect(result, 'picked');
    });
  });

  group('BookplateAppBar', () {
    testWidgets('shows a back chevron only when there is a route to pop', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            appBar: const BookplateAppBar(title: 'Home'),
            body: Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const Scaffold(appBar: BookplateAppBar(title: 'Pushed')),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));

      expect(find.byType(BrassGlyphButton), findsNothing);
      expect(find.byType(BackButton), findsNothing);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Pushed'), findsOneWidget);
      expect(find.byType(BrassGlyphButton), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);

      await tester.tap(find.byType(BrassGlyphButton));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    });
  });
}
