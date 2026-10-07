import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Tells the server, now and then, that the signed-in person has opened the
/// app — `profiles.last_seen_at`, written only by the `touch_last_seen()` RPC
/// (supabase/migrations/026_witness_nudges.sql).
///
/// Why the server needs it: a Runner's daily reminders are local
/// notifications, so day to day the server never otherwise hears from their
/// phone. `last_seen_at` is how push-notification-engine's daily presence
/// probe picks the Runners whose phones are worth checking ("not seen for two
/// days"); an uninstalled app then shows up as a rejected push token, and the
/// Runner's Witness is told. Opening the app also clears an earlier
/// "may have removed the app" mark.
///
/// Started once from main(). It touches when a session starts (a stored
/// session restored at launch, or a fresh sign-in) and every time the app
/// comes back to the foreground — at most once per [throttle] per account.
/// Every failure is silent: presence is bookkeeping, never something to show.
class Presence with WidgetsBindingObserver {
  Presence._();

  static final Presence _instance = Presence._();

  /// The server ignores a touch within ten minutes of the last one anyway;
  /// this keeps the phone from even asking more than twice an hour.
  static const throttle = Duration(minutes: 30);

  static bool _started = false;
  static DateTime? _lastTouch;
  static String? _lastUserId;

  static void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_instance);
    try {
      // Listens for the life of the app (start() runs once), so the
      // subscription is never cancelled.
      supabase.auth.onAuthStateChange.listen(
        (state) {
          switch (state.event) {
            case AuthChangeEvent.initialSession:
            case AuthChangeEvent.signedIn:
            // A launch whose stored access token had expired: the first
            // touch below fails, and this is the moment it can succeed.
            case AuthChangeEvent.tokenRefreshed:
              if (state.session != null) unawaited(touch());
            case AuthChangeEvent.signedOut:
              _lastTouch = null;
              _lastUserId = null;
            default:
              break;
          }
        },
        onError: (Object _) {},
      );
    } catch (error) {
      debugPrint('Presence.start failed: ${error.runtimeType}');
    }
    // A session restored at launch may already be in place before the
    // listener above hears about it; touch() is a no-op without one.
    unawaited(touch());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(touch());
  }

  /// Records "seen now" for the signed-in person, unless this account was
  /// already recorded within [throttle]. No session = nothing to do.
  static Future<void> touch() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      final now = DateTime.now();
      final last = userId == _lastUserId ? _lastTouch : null;
      if (!shouldTouch(last, now)) return;
      _lastTouch = now;
      _lastUserId = userId;
      await supabase.rpc<void>('touch_last_seen');
    } catch (error) {
      // Offline, an old database without the RPC, anything: try again on the
      // next resume rather than waiting out the full throttle.
      _lastTouch = null;
      debugPrint('Presence.touch failed: ${error.runtimeType}');
    }
  }

  /// The client-side throttle, on its own so it can be tested.
  @visibleForTesting
  static bool shouldTouch(DateTime? lastTouch, DateTime now) =>
      lastTouch == null || now.difference(lastTouch) >= throttle;
}
