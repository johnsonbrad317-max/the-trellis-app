import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'supabase_client.dart';

/// A Web Push certificate key pair (Firebase Console -> Project Settings ->
/// Cloud Messaging -> Web configuration -> "Web Push certificates") — only
/// needed to obtain a token on the web target; Android/iOS don't use it.
/// Leave blank until you've generated one; web push registration is simply
/// skipped without it (mobile push is unaffected).
const _webVapidKey = '';

/// Registers this device with Firebase Cloud Messaging and keeps the
/// signed-in account's `profiles.fcm_token` column pointed at it — the one
/// thing push-notification-engine (see supabase/functions/
/// push-notification-engine/) reads to know where to deliver.
///
/// Call [initialize] once at app start (before sign-in even happens, so a
/// background message tapped while signed out still routes correctly), and
/// [registerForCurrentUser] once a [RunnerProfile] has actually loaded —
/// see RunnerProfile.loadCurrent, which fires this itself.
class PushNotifications {
  PushNotifications._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
  }

  /// Requests notification permission (a no-op prompt on Android <13 and
  /// desktop, a real system prompt on iOS/Android 13+/web) and, if granted,
  /// obtains this device's token and saves it. Safe to call every time
  /// [RunnerProfile.loadCurrent] runs — a denied/unchanged permission or an
  /// unavailable token is a silent no-op, never a thrown error, since push
  /// delivery is a "nice to have" layered on top of this app's in-app
  /// Realtime surfaces (see RunnerProfile's unlock-request/grace-nudge/
  /// meeting-proposal handling), never the only way to see one of these.
  static Future<void> registerForCurrentUser(String profileId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      if (kIsWeb) {
        if (_webVapidKey.isEmpty) return;
        final token = await messaging.getToken(vapidKey: _webVapidKey);
        await _saveToken(profileId, token);
      } else {
        if (Platform.isIOS) await _waitForApnsToken(messaging);
        final token = await messaging.getToken();
        await _saveToken(profileId, token);
      }

      // A token can rotate at any time (app reinstall, token expiry, etc.)
      // — keep it current for the life of this session.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) => _saveToken(profileId, token));
    } catch (error) {
      debugPrint('PushNotifications.registerForCurrentUser failed: $error');
    }
  }

  /// On iOS, FCM's getToken() needs the device's APNs token to already be
  /// set on the native side first — immediately after requestPermission()
  /// it often isn't yet, especially on a fresh install, and calling
  /// getToken() too early fails outright rather than just returning null.
  /// Polls briefly rather than failing the whole registration on that
  /// startup race.
  static Future<void> _waitForApnsToken(FirebaseMessaging messaging) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      if (await messaging.getAPNSToken() != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  static Future<void> _saveToken(String profileId, String? token) async {
    if (token == null) return;
    await supabase.from('profiles').update({'fcm_token': token}).eq('id', profileId);
  }
}

/// Runs in a separate background isolate when a push arrives while the app
/// isn't in the foreground — Firebase needs its own [Firebase.initializeApp]
/// call here since isolate state isn't shared with the main one.
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
