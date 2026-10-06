import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/screens/welcome_walkthrough_screen.dart';
import 'package:trellis/theme/app_theme.dart';

/// The welcome walkthrough deck. [WelcomeWalkthroughView] is what is pumped:
/// it is the whole screen minus the profile write, which only the database can
/// supply a [RunnerProfile] for.
void main() {
  const headlines = [
    'Let us throw off everything that hinders…',
    'Anchor Your Days.',
    'Walk Alongside.',
    'Shepherd the Flock.',
    'Cultivate a Garden of Intercession.',
    'Find the Time.',
    'The Flock, Not the Confessional.',
    'Begin the Race.',
  ];

  void useScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host({required bool firstRun, VoidCallback? onFinished, double textScale = 1}) =>
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: WelcomeWalkthroughView(firstRun: firstRun, onFinished: onFinished ?? () {}),
      );

  final primary = find.byKey(const ValueKey('welcome-primary'));

  int currentPage(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!.round();

  // The dot's render box includes its 4px margin on each side; 20 is the
  // current slide's dot, 8 any other.
  double dotWidth(WidgetTester tester, int i) =>
      tester.getSize(find.byKey(ValueKey('welcome-dot-$i'))).width - 8;

  group('the deck', () {
    test('has eight slides with the headlines in order', () {
      expect(welcomeSlides, hasLength(8));
      expect(welcomeSlides.map((s) => s.headline), headlines);
      expect(
        welcomeSlides.map((s) => s.kicker),
        [
          'THE RACE',
          'THE RUNNER',
          'THE WITNESS',
          'THE CLOUD',
          'PRAYER',
          'CONNECT',
          'WHAT LEADERS SEE',
          'BEGIN',
        ],
      );
      for (final slide in welcomeSlides) {
        expect(slide.body, isNotEmpty, reason: slide.headline);
      }
    });

    test("the owner's words: scripture first, weights to throw off, no journal, no church", () {
      expect(welcomeSlides[0].isScripture, isTrue);
      expect(welcomeSlides[0].body, endsWith('— Hebrews 12:1–2'));
      expect(welcomeSlides[1].body, contains('weights you must throw off'));
      expect(welcomeSlides[6].body, contains('never the granular details'));
      for (final slide in welcomeSlides) {
        expect(slide.body.toLowerCase(), isNot(contains('journal')), reason: slide.headline);
        expect(slide.body.toLowerCase(), isNot(contains('church')), reason: slide.headline);
      }
    });

    testWidgets('Next walks through every headline in order, then reads Begin on a first run',
        (tester) async {
      useScreen(tester, const Size(440, 956));
      await tester.pumpWidget(host(firstRun: true));
      await tester.pumpAndSettle();

      for (var i = 0; i < headlines.length; i++) {
        expect(currentPage(tester), i);
        expect(find.text(headlines[i]), findsOneWidget);
        expect(dotWidth(tester, i), 20);
        if (i < headlines.length - 1) {
          expect(find.text('Next'), findsOneWidget);
          expect(find.text('Begin'), findsNothing);
          await tester.tap(primary);
          await tester.pumpAndSettle();
        }
      }
      expect(find.text('Begin'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Done'), findsNothing);
    });

    testWidgets('the last slide reads Done when opened from the menu', (tester) async {
      useScreen(tester, const Size(440, 956));
      await tester.pumpWidget(host(firstRun: false));
      await tester.pumpAndSettle();

      for (var i = 0; i < headlines.length - 1; i++) {
        await tester.tap(primary);
        await tester.pumpAndSettle();
      }
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Begin'), findsNothing);
    });

    testWidgets('Skip shows only on a first run', (tester) async {
      useScreen(tester, const Size(440, 956));
      await tester.pumpWidget(host(firstRun: true));
      await tester.pumpAndSettle();
      expect(find.text('Skip'), findsOneWidget);

      await tester.pumpWidget(host(firstRun: false));
      await tester.pumpAndSettle();
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('Begin and Skip each finish the walkthrough once', (tester) async {
      useScreen(tester, const Size(440, 956));
      var finished = 0;
      await tester.pumpWidget(host(firstRun: true, onFinished: () => finished++));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(finished, 1);

      for (var i = 0; i < headlines.length - 1; i++) {
        await tester.tap(primary);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Begin'));
      await tester.pump();
      expect(finished, 2);
    });

    testWidgets('a swipe advances the slide and the dots', (tester) async {
      useScreen(tester, const Size(440, 956));
      await tester.pumpWidget(host(firstRun: true));
      await tester.pumpAndSettle();
      expect(currentPage(tester), 0);
      expect(dotWidth(tester, 0), 20);
      expect(dotWidth(tester, 1), 8);

      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(currentPage(tester), 1);
      expect(dotWidth(tester, 0), 8);
      expect(dotWidth(tester, 1), 20);
      expect(find.text('Anchor Your Days.'), findsOneWidget);

      // Tapping a dot goes straight to that slide — here the leaders' view,
      // with its two labelled trellises.
      await tester.tap(find.byKey(const ValueKey('welcome-dot-6')));
      await tester.pumpAndSettle();
      expect(currentPage(tester), 6);
      expect(find.text('The Flock, Not the Confessional.'), findsOneWidget);
      expect(find.text('FLOURISHING'), findsOneWidget);
      expect(find.text('WEARY'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final (size, scale) in [
      (const Size(375, 667), 1.0),
      (const Size(375, 667), 1.3),
      (const Size(440, 956), 1.0),
      (const Size(440, 956), 1.3),
    ]) {
      testWidgets('nothing overflows on any slide at ${size.width}x${size.height}, text x$scale',
          (tester) async {
        useScreen(tester, size);
        await tester.pumpWidget(host(firstRun: true, textScale: scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (var i = 0; i < headlines.length; i++) {
          expect(find.text(headlines[i]), findsOneWidget);
          // The button is on screen, not below the fold.
          final button = tester.getRect(primary);
          expect(button.bottom, lessThanOrEqualTo(size.height));
          expect(button.height, greaterThanOrEqualTo(44));
          if (i < headlines.length - 1) {
            await tester.tap(primary);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull, reason: 'slide ${i + 1}');
        }
      });
    }
  });
}
