import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// PostHog project token (Project Settings -> Project API Key — the public
/// client-side key, not a secret) and ingestion host.
const _projectToken = 'phc_CoBRAtJSiKxeJffdMW4uRQFzGLPaV2Uff6znPFKpUBv7';
const _host = 'https://us.i.posthog.com';

/// Privacy-first wrapper around the PostHog SDK. Every event this app sends
/// has a fixed, non-PII shape — a category, a count, a role, a 1-5 rating —
/// never a name, raw email, or free-text note tied back to a real identity.
///
/// [initialize] must run before any other method is useful; every method
/// here is a silent no-op (never a thrown error) if it hasn't, and swallows
/// its own network/SDK errors afterward too — a PostHog hiccup should never
/// interrupt the feature the caller is actually performing (submitting a
/// check-in, opening a screen).
class AnalyticsService {
  AnalyticsService._();

  static bool _initialized = false;

  /// Requires native `AUTO_INIT` to be disabled (see
  /// android/app/src/main/AndroidManifest.xml and ios/Runner/Info.plist) —
  /// otherwise the native SDK has already configured itself before Dart
  /// runs, using none of the privacy settings below, and this call is a
  /// documented no-op.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final config = PostHogConfig(_projectToken)
      ..host = _host
      // No screen recording at all, mobile or web — there is nothing left
      // for autocapture to read a typed value out of.
      ..sessionReplay = false
      // Belt-and-suspenders in case session replay is ever turned on later
      // (e.g. by a remote project-settings change): every text field and
      // image still stays masked by default.
      ..sessionReplayConfig.maskAllTexts = true
      ..sessionReplayConfig.maskAllImages = true
      // Don't create a PostHog person profile from anonymous activity —
      // only once identifyUser() is called for a signed-in account.
      ..personProfiles = PostHogPersonProfiles.identifiedOnly
      // Defense-in-depth against any future property accidentally carrying
      // something identifying. PostHog's own IP-derived geolocation is a
      // server-side pipeline stage this SDK can't reach from the client —
      // full IP anonymization also requires "Discard client IP data" under
      // Project Settings in the PostHog dashboard.
      ..beforeSend = [_stripSensitiveProperties];

    try {
      await Posthog().setup(config);
    } catch (error) {
      debugPrint('AnalyticsService.initialize failed: $error');
    }
  }

  static const _sensitiveKeys = {'\$ip', 'ip', 'ip_address', 'email'};

  static PostHogEvent _stripSensitiveProperties(PostHogEvent event) {
    event.properties?.removeWhere((key, _) => _sensitiveKeys.contains(key));
    return event;
  }

  static Future<void> logRhythmCompleted({
    required String category,
    required bool isDnaRhythm,
  }) =>
      _capture('rhythm_completed', {
        'category': category,
        'is_dna_rhythm': isDnaRhythm,
      });

  static Future<void> logRuleUpdated({required int activeRhythmCount}) =>
      _capture('rule_updated', {'rhythm_count': activeRhythmCount});

  static Future<void> logRoleViewed({required String role}) =>
      _capture('role_viewed', {'role': role});

  /// Dispatched by [FeedbackDialog] (lib/widgets/feedback_dialog.dart) on
  /// submit. [message] is free text the person chose to type into the
  /// feedback form itself — not lifted from anywhere else in the app — and
  /// [churchId] is the only account-linking property attached.
  /// Deliberately carries NO free text: the note itself goes to the team
  /// through the submit-feedback function. Analytics only learns that
  /// feedback happened, how it was rated, and what it was about — a typed
  /// note can name people or health details and has no business in a
  /// third-party analytics pipeline.
  static Future<void> logFeedbackSubmitted({
    required int rating,
    required String category,
    String? churchId,
  }) =>
      _capture('beta_feedback_submitted', {
        'rating': rating,
        'category': category,
        'church_id': ?churchId,
      });

  /// Associates this device with [hashedUserId] (never a raw email or
  /// name) and, if known, the church it belongs to — no other profile
  /// property is ever attached.
  static Future<void> identifyUser({required String hashedUserId, String? churchId}) async {
    if (!_initialized) return;
    try {
      await Posthog().identify(
        userId: hashedUserId,
        userProperties: {'church_id': ?churchId},
      );
    } catch (error) {
      debugPrint('AnalyticsService.identifyUser failed: $error');
    }
  }

  /// Clears the identified user and rotates PostHog's local device/session
  /// id, so events captured after this point are never attributed back to
  /// whoever was just [identifyUser]'d. Call this on sign-out, before the
  /// next account (or an anonymous session) starts generating events.
  static Future<void> reset() async {
    if (!_initialized) return;
    try {
      await Posthog().reset();
    } catch (error) {
      debugPrint('AnalyticsService.reset failed: $error');
    }
  }

  static Future<void> _capture(String eventName, Map<String, Object> properties) async {
    if (!_initialized) return;
    try {
      await Posthog().capture(eventName: eventName, properties: properties);
    } catch (error) {
      debugPrint('AnalyticsService.$eventName failed: $error');
    }
  }
}
