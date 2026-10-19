import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/prayer_texts.dart';
import 'package:trellis/models/scripture_verses.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/models/prayer_item.dart';
import 'package:trellis/widgets/prayer_card.dart';
import 'package:trellis/widgets/prayer_completion_view.dart';
import 'package:trellis/widgets/prayer_text_sheet.dart';
import 'package:trellis/widgets/scripture_chooser.dart';

/// A verse added to an "I prayed for you" text (BSB).
void main() {
  final morning = DateTime(2026, 10, 19, 8);

  group('the verse list', () {
    test('every theme has passages, each short and clean', () {
      expect(scriptureByTheme.keys, unorderedEquals(ScriptureTheme.values));
      for (final MapEntry(key: theme, value: passages) in scriptureByTheme.entries) {
        expect(passages.length, greaterThanOrEqualTo(6), reason: theme.label);
        for (final p in passages) {
          expect(p.text, isNotEmpty, reason: p.reference);
          expect(p.text.length, lessThanOrEqualTo(400), reason: p.reference);
          // No Psalm headings, and quotation marks that open also close.
          expect(p.text, isNot(matches(RegExp('^(For the choirmaster|A Psalm|Of David|A song)'))));
          expect('“'.allMatches(p.text).length, '”'.allMatches(p.text).length,
              reason: p.reference);
          expect(p.text, matches(RegExp(r'[.!?”’]$')), reason: p.reference);
        }
      }
    });

    test('no passage is offered under two themes', () {
      final refs = [for (final ps in scriptureByTheme.values) for (final p in ps) p.reference];
      expect(refs.toSet().length, refs.length);
    });
  });

  test('the verse follows the text, with its reference', () {
    final passage = scriptureByTheme[ScriptureTheme.peace]!.first;
    final text = withScripture('Hey Kevin, I prayed for you this morning.', passage,
        firstName: 'Kevin', now: morning);
    expect(text, startsWith('Hey Kevin, I prayed for you this morning.\n\n'));
    expect(text, endsWith('"${passage.text}" (${passage.reference}, BSB)'));
    expect(text, isNot(contains('this morning:')));
  });

  test("a prayer's own scripture is matched to its BSB text, or sent as a reference", () {
    final found = passageForReference('philippians 4:6-7');
    expect(found.reference, 'Philippians 4:6–7');
    expect(found.text, startsWith('Be anxious for nothing'));

    final other = passageForReference('Psalm 139:13');
    expect(other.text, isEmpty);
    expect(withScripture('Hi.', other, firstName: 'K', now: morning), endsWith('\nPsalm 139:13'));
  });

  group('the sheet', () {
    String? sent;

    Future<void> open(WidgetTester tester, {String? saved}) async {
      sent = null;
      tester.view.physicalSize = const Size(440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  sent = await showPrayerTextSheet(
                    context,
                    firstName: 'Kevin',
                    message: 'Hey Kevin, I prayed for you this morning.',
                    savedScripture: saved,
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
    }

    testWidgets('"Just send the text" sends the text alone', (tester) async {
      await open(tester);
      expect(find.text('Add a verse?'), findsOneWidget);
      await tester.tap(find.text('Just send the text'));
      await tester.pumpAndSettle();
      expect(sent, 'Hey Kevin, I prayed for you this morning.');
    });

    testWidgets('choosing a theme offers a verse, another on request, then sends it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Peace'));
      await tester.pumpAndSettle();
      final firstRef = tester.widget<Text>(find.textContaining(', BSB')).data!;

      await tester.tap(find.text('Different verse'));
      await tester.pumpAndSettle();
      final secondRef = tester.widget<Text>(find.textContaining(', BSB')).data!;
      expect(secondRef, isNot(firstRef));

      await tester.tap(find.text('Send with this verse'));
      await tester.pumpAndSettle();
      expect(sent, startsWith('Hey Kevin, I prayed for you this morning.\n\n'));
      expect(sent, endsWith('($secondRef)'));
    });

    testWidgets('Comfort always opens on Habakkuk 3:17–19', (tester) async {
      expect(scriptureByTheme[ScriptureTheme.comfort]!.first.reference, 'Habakkuk 3:17–19');
      await open(tester);
      await tester.tap(find.text('Comfort'));
      await tester.pumpAndSettle();
      expect(find.text('Habakkuk 3:17–19, BSB'), findsOneWidget);
      expect(find.textContaining('Though the fig tree does not bud'), findsOneWidget);
    });

    testWidgets("a prayer's own scripture is offered first", (tester) async {
      await open(tester, saved: 'Philippians 4:6-7');
      expect(find.text('From this prayer'), findsOneWidget);
      await tester.tap(find.text('Philippians 4:6-7'));
      await tester.pumpAndSettle();
      expect(find.text('Philippians 4:6–7, BSB'), findsOneWidget);
    });
  });

  testWidgets("a prayer card's Scripture can be chosen by theme", (tester) async {
    tester.view.physicalSize = const Size(440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ScripturePassage? picked;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => picked = await showScripturePickerSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a Verse'), findsOneWidget);

    await tester.tap(find.text('Comfort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Different verse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use This Verse'));
    await tester.pumpAndSettle();
    expect(picked, scriptureByTheme[ScriptureTheme.comfort]![1]);
  });

  testWidgets('the prayer card shows the verse itself for a reference we know', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PrayerCard(
            item: PrayerItem(
              id: 'p',
              category: PrayerCategory.situations,
              title: 'Work',
              scripture: 'Philippians 4:6-7',
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Be anxious for nothing'), findsOneWidget);
    expect(find.text('Philippians 4:6–7, BSB'), findsOneWidget);
  });

  test('every verse at the end of a prayer session is BSB', () {
    for (var i = 0; i < 40; i++) {
      final verse = pickRandomPrayerVerse();
      expect(verse.reference, endsWith(', BSB'));
      expect(verse.text, isNot(contains('eth ')));
    }
  });
}
