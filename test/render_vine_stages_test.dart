// Renders the living vine through a season, and the colour treatments side by
// side, for a human look. Skipped unless RENDER_OUT is set:
//   flutter test test/render_vine_stages_test.dart --dart-define=RENDER_OUT=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/theme/app_colors.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/vine_visualizer.dart';

const _out = String.fromEnvironment('RENDER_OUT');

void main() {
  testWidgets('renders the vine through a season', (tester) async {
    if (_out.isEmpty) return;
    tester.view.physicalSize = const Size(1500, 560) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final loader = FontLoader('EBGaramond');
      for (final file in Directory('assets/fonts').listSync()) {
        if (file is File && file.path.endsWith('.ttf')) {
          loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    });

    Widget panel(String label, VineScene scene, VineTone tone) => SizedBox(
          width: 230,
          child: Column(
            children: [
              TrellisVisual(scene: scene, tone: tone, height: 320),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
            ],
          ),
        );

    Future<void> shoot(String name, List<Widget> panels) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppColors.vellum,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: AppColors.vellum,
                padding: const EdgeInsets.all(20),
                child: Row(mainAxisSize: MainAxisSize.min, children: panels),
              ),
            ),
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
      final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    VineScene s(double score, {int? days, bool drooping = false, bool data = true}) =>
        VineScene.of(hasData: data, consistency: score, isDrooping: drooping, seasonDays: days);

    await shoot('season_growth', [
      panel('Day one', s(0, data: false), vineTone),
      panel('Week 1 · 80%', s(0.8, days: 4), vineTone),
      panel('Week 3 · 80%', s(0.8, days: 18), vineTone),
      panel('Week 5 · 85%', s(0.85, days: 30), vineTone),
      panel('Week 7 · 92%', s(0.92, days: 46), vineTone),
      panel('Grown · 70%', s(0.70, days: 60), vineTone),
    ]);
    await shoot('hard_stretches', [
      panel('92%', s(0.92), vineTone),
      panel('92% · 3 anchor misses', s(0.92, drooping: true), vineTone),
      panel('45%', s(0.45), vineTone),
      panel('25%', s(0.25), vineTone),
      panel('10%', s(0.10), vineTone),
      panel('Week 2 · 30%', s(0.30, days: 10), vineTone),
    ]);
    await shoot('colour_options', [
      panel('As drawn', s(0.92), VineTone.original),
      panel('Muted (in use)', s(0.92), VineTone.muted),
      panel('Sepia', s(0.92), VineTone.sepia),
      panel('As drawn · stretch', s(0.92, drooping: true), VineTone.original),
      panel('Muted · stretch', s(0.92, drooping: true), VineTone.muted),
      panel('Sepia · stretch', s(0.92, drooping: true), VineTone.sepia),
    ]);
  });
}
