import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/analytics_service.dart';
import 'services/local_reminders.dart';
import 'services/notification_router.dart';
import 'services/presence.dart';
import 'services/push_notifications.dart';
import 'services/purchases_service.dart';
import 'services/supabase_client.dart';
import 'theme/app_theme.dart';
import 'widgets/keyboard_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The bundled typeface is under the SIL Open Font License, which asks that
  // the licence travel with the font; this lists it on the licences page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['EB Garamond'],
      await rootBundle.loadString('assets/fonts/OFL.txt'),
    );
  });

  // Release builds write nothing to the device log: every diagnostic in the
  // app goes through debugPrint, and this turns it into a no-op outside debug
  // and profile builds (error text can carry ids and server messages that
  // have no business in a production log).
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // The one thing the app cannot run without.
  await initSupabase();

  // Everything else is an enhancement (push, analytics, purchases). If one of
  // them fails to start — a missing native config, no network on first
  // launch — the app must still open, so each is started independently and a
  // failure is logged rather than left to strand the user on a blank screen.
  await _startOptional('Firebase', () async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await PushNotifications.initialize();
    NotificationRouter.initialize();
  });
  // On-device reminders (daily check-in, prayer list). Starting it never
  // asks for notification permission; that happens after sign-in. A tapped
  // reminder opens the tab it is about.
  await _startOptional(
    'Reminders',
    () => LocalReminders.initialize(onTap: NotificationRouter.handleReminderTap),
  );
  await _startOptional('Analytics', AnalyticsService.initialize);
  await _startOptional('Purchases', PurchasesService.initialize);
  // "Last seen" for the server (Witness nudges when a Runner's phone goes
  // silent): on session start and on every return to the foreground.
  await _startOptional('Presence', () async => Presence.start());

  runApp(const TrellisApp());
}

/// Runs one optional start-up step with a ceiling on how long it may take, so
/// a slow or broken SDK can delay launch by a few seconds at most.
Future<void> _startOptional(String name, Future<void> Function() start) async {
  try {
    await start().timeout(const Duration(seconds: 8));
  } catch (error) {
    debugPrint('$name failed to start: $error');
  }
}

class TrellisApp extends StatelessWidget {
  const TrellisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Trellis',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: NotificationRouter.navigatorKey,
      scrollBehavior: const _AppScrollBehavior(),
      // Keyboard manners (Done bar, tap-away, stray-keyboard clean-up) and the
      // status bar's dark marks, for every route.
      builder: (context, child) => KeyboardHost(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}

/// Flutter's default [MaterialScrollBehavior] only treats touch/stylus
/// input as a drag gesture — a mouse click-and-drag on web/desktop does
/// nothing to a PageView/ListView/etc. out of the box, which is why the
/// role-selection and onboarding carousels looked "frozen" when tested
/// with a mouse. Adding [PointerDeviceKind.mouse] here is the standard fix.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
      };
}
