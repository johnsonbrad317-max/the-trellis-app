// Renders the welcome deck's screenshots from the REAL screens, filled with
// the offline sample data behind the Cloud preview (RunnerProfile.preview()),
// into assets/images/welcome/. Skipped unless RENDER_OUT is set — run it again
// whenever one of these screens changes:
//   flutter test test/render_welcome_screens_test.dart --dart-define=RENDER_OUT=assets/images/welcome
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/calendar_connection.dart';
import 'package:trellis/models/meeting_activity.dart';
import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/models/shared_free_windows.dart';
import 'package:trellis/screens/cloud/cloud_insights_screen.dart';
import 'package:trellis/screens/cloud/cloud_roster_screen.dart';
import 'package:trellis/screens/runner/choose_rule_screen.dart';
import 'package:trellis/screens/runner/daily_prayer_screen.dart';
import 'package:trellis/screens/witness/witness_rule_screen.dart';
import 'package:trellis/services/calendar_service.dart';
import 'package:trellis/services/meeting_spot_service.dart';
import 'package:trellis/services/places_service.dart';
import 'package:trellis/theme/app_colors.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/calendar_connect_sheet.dart';
import 'package:trellis/widgets/midway_spot_suggestions.dart';
import 'package:trellis/widgets/places_autocomplete_field.dart';

const _out = String.fromEnvironment('RENDER_OUT');

/// A whole phone screen; the deck's frames show its top 620 points (so the
/// screen's bottom corner vines fall outside the frame).
const _size = Size(390, 844);

void main() {
  testWidgets('renders the welcome deck screenshots', (tester) async {
    if (_out.isEmpty) return;
    tester.view.physicalSize = _size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // The test renderer draws placeholder blocks for a font it was not given.
    await tester.runAsync(() async {
      final loader = FontLoader('EBGaramond');
      for (final file in Directory('assets/fonts').listSync()) {
        if (file is File && file.path.endsWith('.ttf')) {
          loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    });

    Future<void> shoot(String name, Widget screen, {Future<void> Function()? then}) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: screen,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      if (then != null) await then();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump(const Duration(milliseconds: 100));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
      final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    /// A tab's body as the app shows it: parchment, with room for the header.
    Widget tab(Widget body) => Scaffold(
          backgroundColor: AppColors.parchmentLight,
          body: SafeArea(child: body),
        );

    // The Runner: "Let's create your Rule of Life" — the church's DNA Rhythm
    // already in, the ready-made Rules below.
    final runner = RunnerProfile.preview();
    runner.ruleItems.removeWhere((item) => !item.isChurchMandated);
    await shoot('runner_rule', ChooseRuleScreen(profile: runner));

    // The Witness: a Runner who missed an anchor rhythm yesterday, with the
    // text-encouragement and check-in options.
    final witness = RunnerProfile.preview();
    final struggling = witness.watchedRunners.firstWhere(
      (runner) => runner.missedAnchorAlert != null,
      orElse: () => witness.watchedRunners.last,
    );
    witness.selectWatchedRunner(struggling.id);
    await shoot('witness_rule', tab(WitnessRuleScreen(profile: witness, onNavigateToConnect: () {})));

    // Prayer: the card-by-card session.
    final praying = RunnerProfile.preview();
    await shoot(
      'prayer_cards',
      DailyPrayerScreen(
        profile: praying,
        queue: [for (final item in praying.prayerItems) if (!item.isAnswered) item],
      ),
    );

    // Connect: coffee times free for both, and a spot midway.
    final now = DateTime.now();
    final days = candidateMeetingDays(MeetingKind.coffee, now: now);
    CalendarService.instance.debugAvailability = PairAvailability(
      suggestions: const [],
      meSharing: true,
      otherSharing: true,
      otherSyncedAt: now,
      myBusy: [
        if (days.isNotEmpty)
          TimeSpan(days.first.starts.first, days.first.starts.first.add(const Duration(hours: 1))),
      ],
      otherBusy: [
        if (days.length > 1) TimeSpan(days[1].starts.first, days[1].starts.first.add(const Duration(minutes: 90))),
      ],
    );
    MeetingSpotService.instance.debugSuggestion = const MidwaySuggestion(MidwayStatus.found, [
      PlaceSuggestion(name: 'Common Grounds Coffee', address: '412 Main St'),
      PlaceSuggestion(name: 'The Daily Grind', address: '88 Elm Ave'),
      PlaceSuggestion(name: 'Bluebird Roasters', address: '1290 Oak Blvd'),
    ]);
    addTearDown(() {
      CalendarService.instance.debugAvailability = null;
      MeetingSpotService.instance.debugSuggestion = null;
    });
    final location = TextEditingController();
    addTearDown(location.dispose);
    await shoot(
      'connect_times',
      Scaffold(
        backgroundColor: AppColors.vellum,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Builder(
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Propose a Time & Place', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  SharedTimesSuggestions(
                    otherUserId: 'preview-watched-emma',
                    otherName: 'Runner',
                    kind: MeetingKind.coffee,
                    selected: null,
                    onPick: (_) {},
                  ),
                  PlacesAutocompleteField(controller: location),
                  MidwaySpotSuggestions(
                    otherUserId: 'preview-watched-emma',
                    partnerWord: 'Runner',
                    kind: MeetingKind.coffee,
                    controller: location,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // The Cloud: who is discipling whom, and how the flock is growing.
    final cloud = RunnerProfile.preview();
    await shoot('cloud_roster', tab(CloudRosterScreen(profile: cloud)));
    await shoot('cloud_insights', tab(CloudInsightsScreen(profile: cloud)));
  });
}
