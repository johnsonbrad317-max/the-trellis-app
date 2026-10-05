import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// On-device reminders: the "Daily Check-In Reminder" and the prayer-list
/// reminder, delivered by the phone itself (no server, no push) at the time
/// of day the person picked.
///
/// How it works: rather than one repeating daily trigger, [sync] schedules a
/// plain one-off notification for each of the next 28 days, each at an
/// absolute instant worked out from the device's own local clock. That keeps
/// daylight-saving changes right without a native time-zone plugin, and lets
/// "already done today" skip just today's reminder. The window rolls forward
/// because the app calls [sync] every time it starts or resumes and whenever
/// the settings change — so a reminder keeps arriving for 28 days after the
/// app was last opened, then stops until it is opened again.
///
/// Notification text is fixed and generic: nothing personal (no names, no
/// prayer requests, no rhythm titles) ever appears on a lock screen.
///
/// Failure model: reminders are an enhancement, never something a screen
/// should wait on or break over. Every method is a silent no-op on the web
/// and on desktop, in widget tests, and when the native plugin is missing;
/// errors are logged with [debugPrint] and never thrown to the caller.
///
/// Native setup this relies on (see the flutter_local_notifications README):
/// core-library desugaring in android/app/build.gradle.kts; the
/// RECEIVE_BOOT_COMPLETED permission and the two scheduled-notification
/// receivers in AndroidManifest.xml; res/raw/keep.xml (keeps the icon in
/// release builds); and the UNUserNotificationCenter delegate line in
/// ios/Runner/AppDelegate.swift.
class LocalReminders {
  LocalReminders._();

  /// How many days ahead each reminder is scheduled. Two reminders make 56
  /// pending notifications, under the 64 that iOS keeps per app.
  static const int _windowDays = 28;

  static const _Reminder _checkIn = _Reminder(
    firstId: 1000,
    title: 'Daily Check-In',
    body: 'Take a moment to check in on your Rule of Life.',
    payload: 'check_in',
  );

  static const _Reminder _prayer = _Reminder(
    firstId: 2000,
    title: 'Prayer Garden',
    body: 'Your prayer list is waiting.',
    payload: 'prayer',
  );

  /// The status-bar silhouette already used for Firebase pushes
  /// (android/app/src/main/res/drawable/ic_stat_trellis.xml, referenced as
  /// `@drawable/ic_stat_trellis` in AndroidManifest.xml).
  static const String _androidIcon = 'ic_stat_trellis';

  static const InitializationSettings _initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings(_androidIcon),
    // All three off so that starting the plugin never shows the iOS
    // permission prompt — [requestPermission] asks, after sign-in. The
    // foreground presentation defaults (banner, list, sound) are left on.
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );

  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Daily check-in and prayer reminders',
      // Named here as well as in the initialization settings so a reminder
      // still has its icon if it is scheduled before initialize() has run.
      icon: _androidIcon,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// A platform call that takes longer than this is treated as failed, so one
  /// stuck call can never block every later [sync] behind it.
  static const Duration _callTimeout = Duration(seconds: 10);

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// The in-flight or successful start-up of the plugin. Cleared again after
  /// a failure so that a later call gets another try.
  static Future<bool>? _initializing;

  /// The tail of the queue that [sync] and [cancelAll] run through, one at a
  /// time, in the order they were called.
  static Future<void> _queue = Future<void>.value();

  /// Counts [sync] and [cancelAll] calls; a queued or running [sync] that is
  /// no longer the newest gives way to the one behind it.
  static int _latestRequest = 0;

  /// Reminders are only ever scheduled on phones. (In `flutter test` the
  /// target platform reads as Android, but no plugin is registered there —
  /// see [_pluginAvailable].)
  static bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Call once at app start. No-op on web / unsupported platforms. Does NOT
  /// trigger the OS permission prompt (permission is asked after sign-in, by
  /// [requestPermission]).
  static Future<void> initialize() async {
    await _ensureInitialized();
  }

  /// Asks the OS for notification permission if not already decided (iOS:
  /// alert + sound + badge; Android 13+: POST_NOTIFICATIONS; older Android
  /// has no prompt and simply reports the current setting). Returns whether
  /// notifications are allowed — always false on web and desktop. If the
  /// person has already answered, the OS returns that answer without
  /// prompting again.
  ///
  /// Call [sync] again after this returns true: iOS refuses to schedule
  /// anything until permission has been granted.
  static Future<bool> requestPermission() async {
    if (!_isSupportedPlatform || !_pluginAvailable()) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (android == null) return false;
        try {
          final granted = await android.requestNotificationsPermission();
          if (granted != null) return granted;
        } catch (error) {
          // The plugin rejects a request made while another permission
          // dialog is still open; fall through and report the current state.
          debugPrint('LocalReminders.requestPermission could not prompt: $error');
        }
        return await android.areNotificationsEnabled() ?? false;
      }

      final ios =
          _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios == null) return false;
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (error) {
      debugPrint('LocalReminders.requestPermission failed: $error');
      return false;
    }
  }

  /// Replaces everything this service has scheduled with a fresh 28-day
  /// window. A reminder that is off ([ReminderPlan.off], or `enabled: false`,
  /// or an hour/minute outside the clock) is cancelled. `doneToday` skips
  /// today's notification for that reminder (the person has already checked
  /// in / already prayed today).
  ///
  /// Safe to call often and from anywhere: calls run one at a time in the
  /// order they were made, and when several pile up only the newest does any
  /// work, so a slow earlier call can never overwrite a newer schedule. Only
  /// this service's own notification ids (1000–1027 and 2000–2027) are ever
  /// touched; pushes and anything else in the tray are left alone. A reminder
  /// that has already been delivered stays in the tray until it is tapped,
  /// dismissed, or its reminder is switched off.
  static Future<void> sync({
    required ReminderPlan checkIn,
    required ReminderPlan prayer,
  }) async {
    if (!_isSupportedPlatform) return;
    final request = ++_latestRequest;
    await _enqueue('sync', () async {
      // A newer sync (or a cancelAll) is queued behind this one and is about
      // to replace whatever this one would have scheduled.
      if (request != _latestRequest) return;
      if (!await _ensureInitialized()) return;

      final now = DateTime.now();
      final schedule = <_Reminder, List<DateTime>>{
        _checkIn: _fireTimesFor(checkIn, now),
        _prayer: _fireTimesFor(prayer, now),
      };

      // Each slot (id) is either re-scheduled or cancelled. Scheduling over
      // an id that is already pending replaces it, on both platforms, so
      // there is never a moment with nothing scheduled. The cancels go first
      // because they cannot be refused; scheduling can be (iOS, before
      // permission is granted), and that ends the run.
      for (final entry in schedule.entries) {
        for (var slot = entry.value.length; slot < _windowDays; slot++) {
          if (request != _latestRequest) return;
          await _cancel(entry.key.firstId + slot);
        }
      }
      for (final entry in schedule.entries) {
        final times = entry.value;
        for (var slot = 0; slot < times.length; slot++) {
          if (request != _latestRequest) return;
          await _schedule(entry.key, entry.key.firstId + slot, times[slot]);
        }
      }
    });
  }

  /// Cancels everything this service scheduled (call on sign-out). Like
  /// [sync], it only touches this service's own notification ids.
  static Future<void> cancelAll() async {
    if (!_isSupportedPlatform) return;
    // Any sync still waiting in the queue is now out of date.
    _latestRequest++;
    await _enqueue('cancelAll', () async {
      if (!_pluginAvailable()) return;
      for (final reminder in const [_checkIn, _prayer]) {
        for (var slot = 0; slot < _windowDays; slot++) {
          await _cancel(reminder.firstId + slot);
        }
      }
    });
  }

  /// Pure, for tests: the local DateTimes at which a reminder should fire.
  /// Starts today; omits today if [doneToday] or if today's time is not at
  /// least one minute in the future; returns at most [days] entries,
  /// ascending, one per calendar day. Empty if [hour]/[minute] are not a real
  /// time of day or [days] is not positive.
  ///
  /// Each entry is built from calendar fields in the device's local zone, so
  /// across a daylight-saving change the reminder stays at the same wall-clock
  /// time (the gap between two entries is then 23 or 25 hours, not 24).
  @visibleForTesting
  static List<DateTime> upcomingFireTimes({
    required DateTime now,
    required int hour,
    required int minute,
    required bool doneToday,
    int days = 28,
  }) {
    if (days <= 0 || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return const <DateTime>[];
    }
    final localNow = now.toLocal();
    final earliest = localNow.add(const Duration(minutes: 1));
    final times = <DateTime>[];
    for (var offset = 0; times.length < days; offset++) {
      // DateTime normalises a day past the end of the month into the next
      // month (and year), so "today + offset" is always a real date.
      final fireTime =
          DateTime(localNow.year, localNow.month, localNow.day + offset, hour, minute);
      if (offset == 0 && (doneToday || fireTime.isBefore(earliest))) continue;
      times.add(fireTime);
    }
    return times;
  }

  static List<DateTime> _fireTimesFor(ReminderPlan plan, DateTime now) {
    if (!plan.enabled) return const <DateTime>[];
    return upcomingFireTimes(
      now: now,
      hour: plan.hour,
      minute: plan.minute,
      doneToday: plan.doneToday,
      days: _windowDays,
    );
  }

  static Future<void> _schedule(_Reminder reminder, int id, DateTime fireTime) async {
    try {
      await _plugin
          .zonedSchedule(
            id: id,
            title: reminder.title,
            body: reminder.body,
            // An absolute instant. The UTC location is built into the
            // timezone package, so its database never has to be loaded.
            scheduledDate: tz.TZDateTime.from(fireTime, tz.UTC),
            notificationDetails: _notificationDetails,
            // Inexact on purpose: needs no exact-alarm permission. Android
            // may deliver a little late, most noticeably in battery saver.
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: reminder.payload,
          )
          .timeout(_callTimeout);
    } on ArgumentError catch (error) {
      // The plugin refuses a time that is no longer in the future (only
      // possible if this run was held up for over a minute). Drop that one
      // day rather than the whole window.
      debugPrint('LocalReminders skipped reminder $id: $error');
      await _cancel(id);
    }
  }

  /// Removes one of this service's notifications, whether still pending or
  /// already showing in the tray. Never the plugin's own cancelAll(), which
  /// would also clear notifications this service does not own.
  static Future<void> _cancel(int id) => _plugin.cancel(id: id).timeout(_callTimeout);

  /// Runs [job] after everything queued before it has finished. A failure
  /// inside [job] ends that job only: it is logged, never thrown, and the
  /// queue carries on.
  static Future<void> _enqueue(String label, Future<void> Function() job) {
    return _queue = _queue.then((_) async {
      try {
        await job();
      } catch (error) {
        debugPrint('LocalReminders.$label failed: $error');
      }
    });
  }

  static Future<bool> _ensureInitialized() {
    if (!_isSupportedPlatform) return Future<bool>.value(false);
    return _initializing ??= _startPlugin().then((started) {
      if (!started) _initializing = null;
      return started;
    });
  }

  static Future<bool> _startPlugin() async {
    if (!_pluginAvailable()) return false;
    try {
      // The returned bool is not a success flag: on iOS it is "were the
      // requested permissions granted", which is false here by design since
      // none are requested at start-up. Failure is signalled by a throw.
      await _plugin.initialize(settings: _initializationSettings).timeout(_callTimeout);
      return true;
    } catch (error) {
      debugPrint('LocalReminders.initialize failed: $error');
      return false;
    }
  }

  /// Whether the plugin's Android or iOS implementation is registered. It is
  /// not in widget tests (nothing is registered, or the host desktop's
  /// implementation is), which is what makes every method a quiet no-op there.
  static bool _pluginAvailable() {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return _plugin
                .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>() !=
            null;
      }
      return _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>() !=
          null;
    } catch (_) {
      // No implementation has registered itself at all.
      return false;
    }
  }
}

/// What [LocalReminders.sync] needs to know about one reminder: whether it is
/// on, the time of day it fires (24-hour [hour], [minute]), and whether the
/// thing it reminds about has already been done today.
class ReminderPlan {
  const ReminderPlan({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.doneToday,
  });

  /// A reminder that is switched off, or has no time set.
  const ReminderPlan.off()
      : enabled = false,
        hour = 0,
        minute = 0,
        doneToday = false;

  final bool enabled;

  /// Hour of the day, 0–23, in the device's local time.
  final int hour;

  /// Minute of the hour, 0–59.
  final int minute;

  /// True once the person has checked in / prayed today: today's reminder is
  /// then skipped and the next one is tomorrow's.
  final bool doneToday;
}

/// The fixed wording and id range of one of the two reminders. Its ids are
/// [firstId] to `firstId + 27`, one per day ahead.
class _Reminder {
  const _Reminder({
    required this.firstId,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int firstId;
  final String title;
  final String body;

  /// Handed back by the plugin when the notification is tapped.
  final String payload;
}
