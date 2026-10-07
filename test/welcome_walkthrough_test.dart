import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/user_role.dart';
import 'package:trellis/screens/welcome_walkthrough_screen.dart';
import 'package:trellis/theme/app_theme.dart';

/// The welcome walkthrough deck. [WelcomeWalkthroughView] is what is pumped:
/// it is the whole screen minus the profile, which only the database can
/// supply.
void main() {
  const headlines = [
    'Let us throw off everything that hinders…',
    'Create a Rule of Life for this season.',
    'Walk alongside a Runner.',
    'Keep a living prayer list.',
    'Find the time to meet.',
    'See the whole flock.',
    'Two weeks free. No card needed.',
    'Start your journey.',
  ];

  void useScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host({
    required bool firstRun,
    VoidCallback? onFinished,
    ValueChanged<UserRole>? onRoleChosen,
    double textScale = 1,
  }) =>
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: WelcomeWalkthroughView(
          firstRun: firstRun,
          onFinished: onFinished ?? () {},
          onRoleChosen: onRoleChosen ?? (_) {},
        ),
      );

  final primary = find.byKey(const ValueKey('welcome-primary'));

  int currentPage(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!.round();

  Future<void> goToLast(WidgetTester tester) async {
    await tester.tap(find.byKey(ValueKey('welcome-dot-${headlines.length - 1}')));
    await tester.pumpAndSettle();
  }

  group('the deck', () {
    test('eight slides: the race, each part of the app, the cost, and where to start', () {
      expect(welcomeSlides, hasLength(8));
      expect(welcomeSlides.map((s) => s.headline), headlines);
      expect(
        welcomeSlides.map((s) => s.kicker),
        [
          'THE RACE',
          'THE RUNNER',
          'THE WITNESS',
          'PRAYER',
          'CONNECT',
          'THE CLOUD',
          'WHAT IT COSTS',
          'BEGIN',
        ],
      );
      // The front card stays the scripture; every part of the app is shown
      // with real screens, the Cloud with two.
      expect(welcomeSlides.first.isScripture, isTrue);
      for (final slide in welcomeSlides.sublist(1, 6)) {
        expect(slide.art, WelcomeArt.screenshots, reason: slide.kicker);
        expect(slide.screenshots, isNotEmpty, reason: slide.kicker);
      }
      expect(welcomeSlides[5].screenshots, hasLength(2));
    });

    test('the cost card says what the owner set out', () {
      final text = welcomeSlides[6].lines.map((line) => line.text).join(' ');
      expect(text, contains('two weeks free'));
      expect(text, contains('no credit card'));
      expect(text, contains(r'$12-a-year'));
      expect(text, contains('Witnesses always use The Trellis free'));
      expect(text, contains('unhinderedlives.com/trellis'));
    });

    testWidgets('Next walks through every slide in order', (tester) async {
      useScreen(tester, const Size(440, 956));
      await tester.pumpWidget(host(firstRun: true));
      await tester.pumpAndSettle();

      for (var i = 0; i < headlines.length; i++) {
        expect(currentPage(tester), i);
        expect(find.text(headlines[i]), findsOneWidget);
        if (i < headlines.length - 1) {
          await tester.tap(primary);
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('a first run ends by choosing a role, each leading somewhere', (tester) async {
      useScreen(tester, const Size(440, 956));
      final chosen = <UserRole>[];
      await tester.pumpWidget(host(firstRun: true, onRoleChosen: chosen.add));
      await tester.pumpAndSettle();
      await goToLast(tester);

      expect(find.text('Create my Rule of Life'), findsOneWidget);
      expect(find.text('Enter the pairing key my Runner shared'), findsOneWidget);
      expect(find.text("Enter my church or organization's access code"), findsOneWidget);
      // The role buttons are the way forward; there is no Begin/Done.
      expect(tester.widget<Visibility>(find.ancestor(of: primary, matching: find.byType(Visibility))).visible, isFalse);

      for (final role in UserRole.values) {
        await tester.tap(find.byKey(ValueKey('welcome-role-${role.name}')));
        await tester.pump();
      }
      expect(chosen, UserRole.values);
    });

    testWidgets('from the menu the last slide reads Done and offers no roles', (tester) async {
      useScreen(tester, const Size(440, 956));
      var finished = 0;
      await tester.pumpWidget(host(firstRun: false, onFinished: () => finished++));
      await tester.pumpAndSettle();
      await goToLast(tester);

      expect(find.text('Create my Rule of Life'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      await tester.tap(primary);
      await tester.pump();
      expect(finished, 1);
    });

    testWidgets('Skip shows only on a first run and finishes the deck', (tester) async {
      useScreen(tester, const Size(440, 956));
      var finished = 0;
      await tester.pumpWidget(host(firstRun: true, onFinished: () => finished++));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(finished, 1);

      await tester.pumpWidget(host(firstRun: false));
      await tester.pumpAndSettle();
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('a swipe advances the slide', (tester) async {
      useScreen(tester, const Size(440, 956));
      await tester.pumpWidget(host(firstRun: true));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(currentPage(tester), 1);
      expect(find.text('Create a Rule of Life for this season.'), findsOneWidget);
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
          final button = tester.getRect(primary);
          expect(button.bottom, lessThanOrEqualTo(size.height));
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
