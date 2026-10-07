import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/church_roster_entry.dart';
import 'package:trellis/models/preview_sample_data.dart';
import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/screens/cloud_shell.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/cloud_access_code_dialog.dart';

/// The Cloud preview ("See Preview" on the Cloud Access Code dialog): a
/// sample church that works entirely offline. Supabase is never initialised
/// in tests, so any call that reached it would throw — these tests passing
/// is itself the proof that the preview never touches the network.
void main() {
  const previewNotice = 'This is a preview — nothing here is saved.';

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Lets a bookplate notice's 4-second timer run out, so no timer is left
  /// pending when the test ends.
  Future<void> outlastNotice(WidgetTester tester) => tester.pump(const Duration(seconds: 5));

  /// Scrolls [finder] into view (clear of the bottom bar), then taps it.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  group('RunnerProfile.preview()', () {
    final profile = RunnerProfile.preview();

    test('is a preview of a church of 300 with 220 Runners', () {
      expect(profile.isPreview, isTrue);
      expect(profile.churchName, 'Grace Community Church');
      expect(profile.cloudAdminChurchId, isNotNull);
      expect(profile.licenseCap, 300);
      expect(profile.activeLicenseCount, 220);
      expect(profile.churchRoster, hasLength(220));
      expect(profile.churchRoster.map((e) => e.runnerName).toSet(), hasLength(220),
          reason: 'every name on the roster is distinct');
      expect(RunnerProfile.current, isNot(same(profile)));
    });

    test('the roster has a realistic vitality spread', () {
      final roster = profile.churchRoster;
      double share(VineStatus status) =>
          roster.where((e) => e.vineStatus == status).length / roster.length;
      expect(share(VineStatus.fullBloom), closeTo(0.55, 0.05));
      expect(share(VineStatus.budding), closeTo(0.30, 0.05));
      expect(share(VineStatus.drooping), closeTo(0.15, 0.05));
      expect(roster.where((e) => e.isDormant), isNotEmpty);
      expect(roster.where((e) => e.hasNeverCheckedIn), hasLength(5));
      expect(roster.where((e) => e.isUnpaired), isNotEmpty);
      expect(roster.where((e) => e.witnesses.length == 2), isNotEmpty);
    });

    test('is identical every time', () {
      final again = RunnerProfile.preview();
      expect(
        [for (final e in again.churchRoster) '${e.runnerName} ${e.vitalityScore}'],
        [for (final e in profile.churchRoster) '${e.runnerName} ${e.vitalityScore}'],
      );
      expect(again.analytics.score, profile.analytics.score);
    });

    test('every Cloud tab has something to show', () {
      expect(profile.isCongregationalHealthLocked, isFalse);
      expect(profile.churchRhythmMetrics, isNotEmpty);
      expect(profile.dnaRhythms, hasLength(3));
      expect(profile.dnaRhythms.where((r) => r.endsOn != null), hasLength(1));
      expect(profile.cloudTriage.isEmpty, isFalse);
      expect(profile.cloudTriageUnavailable, isFalse);
      expect(profile.churchCodes.where((c) => !c.isRedeemed), isNotEmpty);
      expect(profile.annualRenewalDate, isNotNull);
    });

    test('Sarah is a Runner with a committed Rule of Life and a Witness of two', () {
      expect(profile.name, PreviewSampleData.userName);
      expect(profile.hasCommittedRule, isTrue);
      expect(profile.ruleItems.where((i) => i.isThrowOff), isNotEmpty);
      expect(profile.ruleItems.where((i) => i.isChurchMandated), hasLength(1));
      expect(profile.witnesses.single.name, 'Rachel Adams');
      expect(profile.prayerItems.length, greaterThanOrEqualTo(5));
      expect(profile.meetingRequests, hasLength(2));
      expect(profile.analyticsLoaded, isTrue);
      expect(profile.analytics.score, closeTo(0.8, 0.05));      expect(profile.watchedRunners, hasLength(2));
      expect(profile.watchedRunners.where((r) => r.missedAnchorAlert != null), hasLength(1));
    });

    test('loads return quietly and writes refuse, without reaching Supabase', () async {
      await profile.loadCloudData();
      await profile.loadRunnerData();
      await profile.loadWitnessData();
      await profile.refreshAnalytics();
      await profile.refreshCloudTriage();
      final refused = throwsA(isA<PreviewModeException>());
      await expectLater(profile.generateChurchCode(), refused);
      await expectLater(profile.revokeChurchCode('K7QM4XRT'), refused);
      await expectLater(profile.retireDnaRhythm(profile.dnaRhythms.first), refused);
      await expectLater(profile.addDnaRhythm(profile.dnaRhythms.first), refused);
      await expectLater(profile.redeemCloudAccessCode('ABCDEFGH'), refused);
      await expectLater(profile.signOut(), refused);
      await expectLater(profile.deleteAccount(), refused);
      expect(profile.churchCodes.where((c) => !c.isRedeemed), hasLength(6));
    });
  });

  group('CloudShell in preview', () {
    Future<void> pumpPreview(WidgetTester tester) async {
      usePhone(tester);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: CloudShell(profile: RunnerProfile.preview(), preview: true),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('renders every tab, with the preview banner', (tester) async {
      await pumpPreview(tester);
      expect(find.text('Preview · sample data for a church of 300'), findsOneWidget);
      expect(find.text('Exit preview'), findsOneWidget);
      expect(find.text('Grace Community Church'), findsOneWidget);

      // Roster
      expect(find.text('The Roster'), findsOneWidget);
      expect(find.textContaining('Witnessed by'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Insights
      await tester.tap(find.text('Insights'));
      await tester.pumpAndSettle();
      expect(find.text('Congregational Health'), findsOneWidget);
      expect(find.text('Sabbath Rest'), findsWidgets);
      expect(find.textContaining('Runners are struggling'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Treasury
      await tester.tap(find.text('Treasury'));
      await tester.pumpAndSettle();
      expect(find.text('Active Licenses: 220 / 300'), findsOneWidget);
      expect(find.text('K7QM4XRT'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Church Profile (the gear)
      await tester.tap(find.bySemanticsLabel('Church Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Forty Days of Fasting'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('writes show a notice instead of being attempted', (tester) async {
      await pumpPreview(tester);

      // The role switcher does not offer the real account's roles.
      await tester.tap(find.bySemanticsLabel('Switch role, currently Cloud'));
      await tester.pump();
      expect(find.text('Switch role'), findsNothing);
      expect(find.text(previewNotice), findsOneWidget);
      await outlastNotice(tester);

      // Nor is there a settings drawer: the menu is an Exit button instead.
      expect(find.bySemanticsLabel('Open menu'), findsNothing);
      // (One in the app bar, one in the banner.)
      expect(find.bySemanticsLabel('Exit preview'), findsNWidgets(2));

      await tester.tap(find.text('Treasury'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Generate New Church Code'));
      await tester.pump();
      expect(find.text(previewNotice), findsOneWidget);
      await outlastNotice(tester);

      await tapVisible(tester, find.text('Revoke').first);
      await tester.pump();
      expect(find.text(previewNotice), findsOneWidget);
      expect(find.text('Revoke This Code?'), findsNothing);
      await outlastNotice(tester);

      await tester.tap(find.text('Insights'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Add DNA Rhythm'));
      await tester.pump();
      expect(find.text(previewNotice), findsOneWidget);
      await outlastNotice(tester);

      await tapVisible(tester, find.text('Text').first);
      await tester.pump();
      expect(find.text(previewNotice), findsOneWidget);
      await outlastNotice(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Cloud Access Code dialog', () {
    Future<List<CloudAccessResult>> pumpOpener(WidgetTester tester) async {
      usePhone(tester);
      final results = <CloudAccessResult>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () async =>
                    results.add(await showCloudAccessCodeDialog(context, RunnerProfile.preview())),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('offers Unlock, See Preview and Cancel, and where to get a code',
        (tester) async {
      await pumpOpener(tester);
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.text('See Preview'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        find.text("Don't have a code? Church licenses are set up through Unhindered Lives."),
        findsOneWidget,
      );

      // Unlock without a code asks for one rather than calling anything.
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      expect(find.text('Enter the code your church gave you.'), findsOneWidget);
    });

    testWidgets('Cancel resolves to cancelled', (tester) async {
      final results = await pumpOpener(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [CloudAccessResult.cancelled]);
      // The text field's controller is released once the dialog has faded.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('See Preview shows the sample church, then returns on exit', (tester) async {
      final results = await pumpOpener(tester);
      await tester.tap(find.text('See Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Preview · sample data for a church of 300'), findsOneWidget);
      expect(find.text('The Roster'), findsOneWidget);
      expect(results, isEmpty, reason: 'resolves only once the preview is exited');

      await tester.tap(find.text('Exit preview'));
      await tester.pumpAndSettle();
      expect(results, [CloudAccessResult.previewed]);
      expect(find.text('Open'), findsOneWidget);
    });
  });
}
