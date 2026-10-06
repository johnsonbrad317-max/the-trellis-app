import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../screens/runner_shell.dart';
import '../screens/witness_shell.dart';
import 'local_reminders.dart';

/// Routes a tapped notification to the right screen.
///
/// Pushes: every notification the server sends carries a `data.type`
/// matching one of push-notification-engine's event types (see
/// supabase/functions/push-notification-engine/index.ts) — this is the
/// client-side mirror of that same small set of cases. Two delivery paths
/// both end up here:
///   - the app was already running (background or foreground) and the user
///     taps the system notification -> [FirebaseMessaging.onMessageOpenedApp]
///   - the app was fully killed and the notification tap is what launched
///     it -> [FirebaseMessaging.getInitialMessage]
///
/// On-device reminders ([LocalReminders]) arrive through
/// [handleReminderTap] instead, with the reminder's payload.
class NotificationRouter {
  NotificationRouter._();

  /// Attached to [MaterialApp] in main.dart — lets this class push routes
  /// without needing a BuildContext of its own, since a notification tap
  /// can arrive before any screen exists to hand it one.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static void initialize() {
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleTap(message);
    });
  }

  /// A tapped check-in or prayer reminder lands on the tab it is about —
  /// the Rule of Life tab (where the Daily Check-In lives) or the Prayer tab
  /// — rather than wherever the app happened to be left. Unknown payloads
  /// are ignored.
  static Future<void> handleReminderTap(String payload) async {
    final tab = switch (payload) {
      LocalReminders.checkInPayload => RunnerTab.ruleOfLife,
      LocalReminders.prayerPayload => RunnerTab.prayer,
      _ => null,
    };
    if (tab == null) return;

    final ready = await _waitForProfileAndNavigator();
    if (ready == null) return;
    _goToRunnerShell(ready.navigator, ready.profile, tab: tab);
  }

  /// Cold start from a killed app: main() is still racing loadCurrent()
  /// against this tap — RunnerProfile.current only exists once that finishes
  /// and the navigator only once runApp has built — so wait for both (a few
  /// seconds at most) rather than silently dropping the tap. Null if the
  /// person isn't signed in by then.
  static Future<({RunnerProfile profile, NavigatorState navigator})?>
      _waitForProfileAndNavigator() async {
    var profile = RunnerProfile.current;
    var navigator = navigatorKey.currentState;
    var waited = 0;
    while ((profile == null || navigator == null) && waited < 8000) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      waited += 250;
      profile = RunnerProfile.current;
      navigator = navigatorKey.currentState;
    }
    if (profile == null || navigator == null) return null;
    return (profile: profile, navigator: navigator);
  }

  static Future<void> _handleTap(RemoteMessage message) async {
    final ready = await _waitForProfileAndNavigator();
    if (ready == null) return;
    final profile = ready.profile;
    final navigator = ready.navigator;

    final data = message.data;
    switch (data['type']) {
      case 'unlock_request':
      case 'grace_nudge':
      case 'support_request':
      case 'weekly_roll_up':
        // Only ever sent to a Witness — land on their Runners tab with the
        // relevant Runner already selected (a support request also shows in
        // that tab's "Requests for You" list).
        _goToWitnessShell(navigator, profile, selectRunnerId: data['runnerId'] as String?);
        break;
      case 'meeting_proposal':
        // Sent to whichever side didn't propose — could be either.
        if (data['witnessId'] == profile.id) {
          _goToWitnessShell(navigator, profile, selectRunnerId: data['runnerId'] as String?);
        } else {
          _goToRunnerShell(navigator, profile);
        }
        break;
      case 'account_deleted':
        // Only ever sent to a Witness whose paired Runner just deleted
        // their account — the pairing row is already gone (cascaded), so
        // this just lands them back on an updated Runners list.
        _goToWitnessShell(navigator, profile, selectRunnerId: null);
        break;
      default:
        break;
    }
  }

  static void _goToWitnessShell(
    NavigatorState navigator,
    RunnerProfile profile, {
    required String? selectRunnerId,
  }) {
    if (selectRunnerId != null) profile.selectWatchedRunner(selectRunnerId);
    if (profile.role != UserRole.witness) profile.setRole(UserRole.witness);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => WitnessShell(profile: profile)),
      (route) => false,
    );
  }

  static void _goToRunnerShell(
    NavigatorState navigator,
    RunnerProfile profile, {
    RunnerTab tab = RunnerTab.dashboard,
  }) {
    if (profile.role != UserRole.runner) profile.setRole(UserRole.runner);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => RunnerShell(profile: profile, initialTab: tab)),
      (route) => false,
    );
  }
}
