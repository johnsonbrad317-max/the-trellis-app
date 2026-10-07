import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trellis/widgets/vine_visualizer.dart';

/// The living vine: one grapevine in aligned layers, assembled piece by piece
/// from the Runner's season.
void main() {
  const hidden = VinePartState.hidden;
  const bare = VinePartState.bare;
  const leafed = VinePartState.leafed;
  const fruiting = VinePartState.fruiting;
  const withered = VinePartState.withered;

  VineScene scene(double consistency, {bool drooping = false, int? days, bool hasData = true}) =>
      VineScene.of(
        hasData: hasData,
        consistency: consistency,
        isDrooping: drooping,
        seasonDays: days,
      );

  group('VineScene.of', () {
    test('a brand-new Runner sees a young bare shoot and no branches', () {
      final s = scene(0.9, drooping: true, hasData: false);
      expect(s.stem, bare);
      expect(s.branches, everyElement(hidden));
      expect(s.stemReveal, lessThan(0.35));
      expect(s.stemReveal, greaterThan(0.05));
    });

    test('a branch grows each week of the season, all six from the sixth week', () {
      int grown(int days) => scene(0.7, days: days).branches.where((b) => b != hidden).length;
      expect(grown(0), 1);
      expect(grown(6), 1);
      expect(grown(7), 2);
      expect(grown(20), 3);
      expect(grown(35), 6);
      expect(grown(200), 6);
      // The stem climbs with them, to the top once all six have grown.
      expect(scene(0.7, days: 0).stemReveal, lessThan(scene(0.7, days: 14).stemReveal));
      expect(scene(0.7, days: 40).stemReveal, 1.0);
    });

    test('the newest branch is bare for its first few days', () {
      expect(scene(0.95, days: 8).branches.take(2), [fruiting, bare]);
      expect(scene(0.95, days: 11).branches.take(2), [fruiting, fruiting]);
    });

    test('fruit follows consistency, oldest branches first', () {
      expect(scene(0.95).branches, List.filled(6, fruiting));
      expect(scene(0.70).branches, [fruiting, fruiting, fruiting, leafed, leafed, leafed]);
      expect(scene(0.55).branches.where((b) => b == fruiting).length, 1);
      expect(scene(0.50).branches, List.filled(6, leafed));
    });

    test('a hard stretch withers the newest branches; the rest stand', () {
      expect(scene(0.45).branches, [leafed, leafed, leafed, leafed, leafed, withered]);
      expect(scene(0.20).branches, [leafed, leafed, leafed, leafed, withered, withered]);
      // Three missed Anchor Rhythms wither two even in a fruitful season.
      expect(
        scene(0.95, drooping: true).branches,
        [fruiting, fruiting, fruiting, fruiting, withered, withered],
      );
      // Early in the season the withering still takes the newest ones.
      expect(scene(0.2, days: 14).branches, [leafed, withered, withered, hidden, hidden, hidden]);
    });

    test('a near-empty season withers the whole vine, stem included', () {
      final s = scene(0.05);
      expect(s.stem, withered);
      expect(s.branches, List.filled(6, withered));
    });

    test('unknown season age shows the vine fully grown', () {
      expect(scene(0.95).branches.where((b) => b != hidden).length, 6);
    });

    test('daysSince counts whole days and never goes negative', () {
      final now = DateTime(2026, 10, 7, 12);
      expect(daysSince(null, now), isNull);
      expect(daysSince(DateTime(2026, 10, 1, 9), now), 6);
      expect(daysSince(DateTime(2026, 10, 9), now), 0);
    });
  });

  group('TrellisVisual', () {
    List<String> assetsShown(WidgetTester tester) => tester.widgetList<Image>(find.byType(Image)).map((i) {
          final provider = i.image;
          return ((provider is ResizeImage ? provider.imageProvider : provider) as AssetImage)
              .assetName;
        }).toList();

    testWidgets('draws the trellis, the stem and each grown branch in its state', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrellisVisual(scene: scene(0.70, days: 20))),
      ));
      await tester.pumpAndSettle();
      final shown = assetsShown(tester);
      expect(shown.first, 'assets/images/trellis_empty.png');
      expect(shown, contains('assets/images/vine/vine_stem_leafed.png'));
      expect(shown, contains('assets/images/vine/vine_branch_1_fruiting.png'));
      expect(shown, contains('assets/images/vine/vine_branch_3_leafed.png'));
      expect(shown.where((a) => a.contains('branch_4')), isEmpty);
    });

    testWidgets('the stem is revealed from the bottom', (tester) async {
      final s = scene(0.70, days: 0);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TrellisVisual(scene: s))));
      await tester.pumpAndSettle();
      final masks = tester
          .widgetList<Align>(find.byType(Align))
          .where((a) => a.heightFactor != null && a.alignment == Alignment.bottomCenter);
      expect(masks.single.heightFactor, closeTo(s.stemReveal, 0.001));
    });

    testWidgets('a change of scene crossfades without errors', (tester) async {
      Widget host(VineScene s) => MaterialApp(home: Scaffold(body: TrellisVisual(scene: s)));
      await tester.pumpWidget(host(scene(0.95)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(scene(0.95, drooping: true)));
      await tester.pump(const Duration(milliseconds: 300));
      // Mid-fade both versions of branch 6 are on screen.
      final mid = assetsShown(tester);
      expect(mid, contains('assets/images/vine/vine_branch_6_fruiting.png'));
      expect(mid, contains('assets/images/vine/vine_branch_6_withered.png'));
      await tester.pumpAndSettle();
      expect(assetsShown(tester), isNot(contains('assets/images/vine/vine_branch_6_fruiting.png')));
      expect(tester.takeException(), isNull);
    });

    test('every layer the scenes can ask for is bundled', () {
      // 3 stem states + 6 branches x 4 states.
      expect(VinePartState.values.where((s) => s != VinePartState.hidden), hasLength(4));
    });
  });

  testWidgets('a new Runner sees only the encouragement line', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VineVisualizerCard(vitalityScore: 0, isDrooping: false, hasData: false),
        ),
      ),
    );

    expect(find.text('Stick to Your Rule and Watch Yourself Grow'), findsOneWidget);
    expect(find.textContaining('Vitality'), findsNothing);
    expect(find.textContaining('missed'), findsNothing);
  });
}
