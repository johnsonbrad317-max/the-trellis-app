import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trellis/widgets/vine_visualizer.dart';

void main() {
  group('TrellisState.of', () {
    test('a brand-new Runner is always empty, whatever the score', () {
      expect(
        TrellisState.of(hasData: false, consistency: 0.9, isDrooping: true),
        TrellisState.empty,
      );
    });

    test('picks a tier from consistency once there is data', () {
      TrellisState state(double c, {bool drooping = false}) =>
          TrellisState.of(hasData: true, consistency: c, isDrooping: drooping);

      expect(state(0.05), TrellisState.dead);
      expect(state(0.30), TrellisState.struggling);
      expect(state(0.60), TrellisState.growing);
      expect(state(0.90), TrellisState.flourishing);
    });

    test('three missed Anchor Rhythms cap a healthy season at struggling', () {
      expect(
        TrellisState.of(hasData: true, consistency: 0.9, isDrooping: true),
        TrellisState.struggling,
      );
    });
  });

  group('TrellisVisual', () {
    Future<List<Align>> pumpAndFindMasks(
      WidgetTester tester,
      TrellisState state,
      double reveal,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrellisVisual(state: state, reveal: reveal))),
      );
      await tester.pumpAndSettle();
      return tester
          .widgetList<Align>(find.byType(Align))
          .where((a) => a.heightFactor != null && a.alignment == Alignment.bottomCenter)
          .toList();
    }

    List<String> assetsShown(WidgetTester tester) => tester.widgetList<Image>(find.byType(Image)).map((i) {
          final provider = i.image;
          return ((provider is ResizeImage ? provider.imageProvider : provider) as AssetImage)
              .assetName;
        }).toList();

    testWidgets('reveals the bottom share of the picture matching consistency', (tester) async {
      final masks = await pumpAndFindMasks(tester, TrellisState.growing, 0.6);
      expect(masks, hasLength(1));
      expect(masks.single.heightFactor, closeTo(0.6, 0.001));
    });

    testWidgets('the empty trellis is just the bare base, never masked', (tester) async {
      final masks = await pumpAndFindMasks(tester, TrellisState.empty, 0.0);
      expect(masks, isEmpty);
      expect(assetsShown(tester), ['assets/images/trellis_empty.png']);
    });

    testWidgets('keeps the whole bare trellis underneath the revealed vine', (tester) async {
      await pumpAndFindMasks(tester, TrellisState.flourishing, 0.3);
      expect(
        assetsShown(tester),
        ['assets/images/trellis_empty.png', 'assets/images/trellis_flourishing.png'],
      );
    });

    testWidgets('loads the image for the current state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TrellisVisual(state: TrellisState.struggling, reveal: 0.5)),
        ),
      );
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(
        images.map((i) {
          final provider = i.image;
          return ((provider is ResizeImage ? provider.imageProvider : provider) as AssetImage)
              .assetName;
        }),
        contains('assets/images/trellis_struggling.png'),
      );
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
