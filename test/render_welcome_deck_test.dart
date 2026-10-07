// Renders each welcome-deck slide to a PNG for a human look, using the real
// bundled images. Skipped unless RENDER_OUT is set:
//   flutter test test/render_welcome_deck_test.dart --dart-define=RENDER_OUT=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/screens/welcome_walkthrough_screen.dart';
import 'package:trellis/theme/app_theme.dart';

const _out = String.fromEnvironment('RENDER_OUT');

void main() {
  testWidgets('renders every welcome slide', (tester) async {
    if (_out.isEmpty) return;
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The test renderer draws placeholder blocks for any font it has not been
    // handed; load the app's own face so the render reads as the app does.
    await tester.runAsync(() async {
      final loader = FontLoader('EBGaramond');
      for (final file in Directory('assets/fonts').listSync()) {
        if (file is File && file.path.endsWith('.ttf')) {
          loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    });

    for (var i = 0; i < welcomeSlides.length; i++) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: const Color(0xFFF9F6F0),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 400,
                height: 640,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: WelcomeSlideView(welcomeSlides[i], onRoleChosen: (_) {}),
                ),
              ),
            ),
          ),
        ),
      ));
      // Let the images decode and any reveal animation finish.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
      final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      File('$_out/welcome_${i + 1}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
