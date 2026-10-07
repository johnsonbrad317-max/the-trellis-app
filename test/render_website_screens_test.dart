// Renders full-height phone screens of the real app (offline sample data from
// RunnerProfile.preview()) at 3x, for the website. Skipped unless RENDER_OUT
// is set:
//   flutter test test/render_website_screens_test.dart --dart-define=RENDER_OUT=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/models/user_role.dart';
import 'package:trellis/screens/cloud_shell.dart';
import 'package:trellis/screens/runner/choose_rule_screen.dart';
import 'package:trellis/screens/runner_shell.dart';
import 'package:trellis/screens/witness_shell.dart';
import 'package:trellis/theme/app_theme.dart';

const _out = String.fromEnvironment('RENDER_OUT');

/// An iPhone 15/16-sized screen, with its status bar and home indicator.
const _size = Size(393, 852);

void main() {
  testWidgets('renders the website screens', (tester) async {
    if (_out.isEmpty) return;
    tester.view.physicalSize = _size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    CloudShell.debugShowPreviewAsLive = true;
    addTearDown(() => CloudShell.debugShowPreviewAsLive = false);

    await tester.runAsync(() async {
      final loader = FontLoader('EBGaramond');
      for (final file in Directory('assets/fonts').listSync()) {
        if (file is File && file.path.endsWith('.ttf')) {
          loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    });

    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> shoot(String name, Widget screen, {Future<void> Function()? then}) async {
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.light, home: screen),
      ));
      await settle();
      if (then != null) {
        await then();
        await settle();
      }
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
      final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      // Leave nothing (timers, listeners) running into the next screen.
      await tester.pumpWidget(const SizedBox.shrink());
    }

    Future<void> tapTab(String label) async {
      await tester.tap(find.text(label).last);
    }

    // Runner
    await shoot('runner_dashboard', RunnerShell(profile: RunnerProfile.preview()));
    await shoot(
      'runner_rule_of_life',
      RunnerShell(profile: RunnerProfile.preview(), initialTab: RunnerTab.ruleOfLife),
    );
    final chooser = RunnerProfile.preview();
    chooser.ruleItems.removeWhere((item) => !item.isChurchMandated);
    await shoot('runner_choose_rule', ChooseRuleScreen(profile: chooser));

    // Witness: the Runner who missed an anchor rhythm yesterday.
    RunnerProfile witnessProfile() {
      final profile = RunnerProfile.preview();
      final struggling = profile.watchedRunners.firstWhere(
        (runner) => runner.missedAnchorAlert != null,
        orElse: () => profile.watchedRunners.last,
      );
      profile.selectWatchedRunner(struggling.id);
      // The sample account starts as a Runner; show it in the Witness role.
      profile.setRole(UserRole.witness);
      return profile;
    }

    await shoot('witness_dashboard', WitnessShell(profile: witnessProfile()));
    await shoot(
      'witness_rule_of_life',
      WitnessShell(profile: witnessProfile()),
      then: () => tapTab('Rule of Life'),
    );

    // Cloud
    await shoot('cloud_roster', CloudShell(profile: RunnerProfile.preview()));
    await shoot(
      'cloud_insights',
      CloudShell(profile: RunnerProfile.preview()),
      then: () => tapTab('Insights'),
    );
  });
}
