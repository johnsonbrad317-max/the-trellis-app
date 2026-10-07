import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/models/user_role.dart';
import 'package:trellis/services/presence.dart';

/// Witness nudges (026_witness_nudges.sql + push-notification-engine's
/// witness_nudge event): the Witness's switch, the presence throttle, and the
/// names the app, the engine and the database must agree on.
void main() {
  group('NotificationCategory.quietRunnerAlerts', () {
    test('is stored under quiet_runner_alerts', () {
      expect(NotificationCategory.quietRunnerAlerts.dbKey, 'quiet_runner_alerts');
    });

    test('is the Witness\'s switch only', () {
      expect(NotificationCategory.quietRunnerAlerts.visibleForRole(UserRole.witness), isTrue);
      expect(NotificationCategory.quietRunnerAlerts.visibleForRole(UserRole.runner), isFalse);
      expect(NotificationCategory.quietRunnerAlerts.visibleForRole(UserRole.cloud), isFalse);
    });

    test('is labelled Check-In Alerts', () {
      expect(NotificationCategory.quietRunnerAlerts.label, 'Check-In Alerts');
    });

    test('database keys are still unique', () {
      final keys = NotificationCategory.values.map((c) => c.dbKey).toSet();
      expect(keys, hasLength(NotificationCategory.values.length));
    });
  });

  group('Presence throttle', () {
    final now = DateTime(2026, 10, 7, 9);

    test('touches when it never has', () {
      expect(Presence.shouldTouch(null, now), isTrue);
    });

    test('does not touch again within 30 minutes', () {
      expect(Presence.shouldTouch(now.subtract(const Duration(minutes: 29)), now), isFalse);
    });

    test('touches again after 30 minutes', () {
      expect(Presence.shouldTouch(now.subtract(const Duration(minutes: 30)), now), isTrue);
    });
  });

  group('names shared with the server', () {
    String read(String path) => File(path).readAsStringSync();

    test('the engine sends witness_nudge with the Witness\'s quiet_runner_alerts switch', () {
      final engine = read('supabase/functions/push-notification-engine/index.ts');
      final nudges = read('supabase/functions/push-notification-engine/witness_nudges.ts');
      expect(engine, contains("'witness_nudge'"));
      expect(engine, contains('preference: QUIET_RUNNER_ALERTS_PREFERENCE'));
      expect(
        nudges,
        contains("QUIET_RUNNER_ALERTS_PREFERENCE = '${NotificationCategory.quietRunnerAlerts.dbKey}'"),
      );
      expect(nudges, contains("type: 'presence_probe'"));
    });

    test('a tapped witness_nudge is routed', () {
      expect(read('lib/services/notification_router.dart'), contains("case 'witness_nudge':"));
    });

    test('a presence probe is ignored in the background', () {
      expect(
        read('lib/services/push_notifications.dart'),
        contains("message.data['type'] == 'presence_probe'"),
      );
    });

    test('the migration defines the RPC the app calls', () {
      expect(
        read('supabase/migrations/026_witness_nudges.sql'),
        contains('function public.touch_last_seen()'),
      );
    });
  });
}
