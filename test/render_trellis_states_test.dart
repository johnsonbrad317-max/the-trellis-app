// Renders the dashboard vine in each state to PNG files for a human look,
// using the real bundled images. Skipped unless RENDER_OUT is set:
//   flutter test test/render_trellis_states_test.dart --dart-define=RENDER_OUT=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/vine_visualizer.dart';

const _out = String.fromEnvironment('RENDER_OUT');

void main() {
  testWidgets('renders every trellis state', (tester) async {
    if (_out.isEmpty) return;
    tester.view.physicalSize = const Size(440, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cases = <(String, double, bool, bool)>[
      ('new', 0.0, false, false),
      ('growing_35', 0.35, true, false),
      ('growing_60', 0.60, true, false),
      ('flourishing_90', 0.90, true, false),
      ('struggling_30', 0.30, true, false),
      ('drooping_70', 0.70, true, true),
      ('dead_10', 0.10, true, false),
    ];
    for (final (name, score, hasData, drooping) in cases) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 400,
                child: VineVisualizerCard(
                  vitalityScore: score,
                  isDrooping: drooping,
                  hasData: hasData,
                ),
              ),
            ),
          ),
        ),
      ));
      // Let the images decode and the reveal animation finish.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
      final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      File('$_out/trellis_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
