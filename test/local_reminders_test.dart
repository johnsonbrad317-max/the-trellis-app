import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/services/local_reminders.dart';

/// The calendar date of [time], as a zone-free value that can be compared and
/// stepped a day at a time without daylight-saving getting in the way.
DateTime _dateOf(DateTime time) => DateTime.utc(time.year, time.month, time.day);

/// Every entry is exactly one calendar day after the one before it.
void _expectOnePerConsecutiveDay(List<DateTime> times) {
  for (var i = 1; i < times.length; i++) {
    expect(
      _dateOf(times[i]),
      _dateOf(times[i - 1]).add(const Duration(days: 1)),
      reason: 'entry $i (${times[i]}) should be the day after ${times[i - 1]}',
    );
  }
}

void _expectStrictlyAscending(List<DateTime> times) {
  for (var i = 1; i < times.length; i++) {
    expect(times[i].isAfter(times[i - 1]), isTrue, reason: 'entry $i is not after entry ${i - 1}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _fireTimeTests();
  // Order matters from here on: LocalReminders keeps static state (whether the
  // plugin has started), and the plugin's platform implementation, once
  // registered by the later group, cannot be unregistered.
  _noPluginTests();
  _mockedPluginTests();
}

// ---------------------------------------------------------------------------
// upcomingFireTimes — pure
// ---------------------------------------------------------------------------
void _fireTimeTests() {
  group('LocalReminders.upcomingFireTimes', () {
    // A Monday lunchtime, well away from any daylight-saving change.
    final noon = DateTime(2026, 10, 5, 12, 0);

    test('a time later today is included, and comes first', () {
      final times = LocalReminders.upcomingFireTimes(
        now: noon,
        hour: 19,
        minute: 30,
        doneToday: false,
      );
      expect(_dateOf(times.first), DateTime.utc(2026, 10, 5));
      expect(times.first.hour, 19);
      expect(times.first.minute, 30);
      expect(times.first.isAfter(noon), isTrue);
    });

    test('a time already passed today is skipped; the first is tomorrow', () {
      final times = LocalReminders.upcomingFireTimes(
        now: noon,
        hour: 7,
        minute: 0,
        doneToday: false,
      );
      expect(_dateOf(times.first), DateTime.utc(2026, 10, 6));
      expect(times.first.hour, 7);
      expect(times.first.minute, 0);
    });

    test('today needs at least a full minute of notice', () {
      List<DateTime> at(DateTime now) =>
          LocalReminders.upcomingFireTimes(now: now, hour: 12, minute: 30, doneToday: false);

      // Exactly one minute ahead: included.
      expect(_dateOf(at(DateTime(2026, 10, 5, 12, 29, 0)).first), DateTime.utc(2026, 10, 5));
      // 59 seconds ahead, right now, and just gone: all skipped.
      expect(_dateOf(at(DateTime(2026, 10, 5, 12, 29, 1)).first), DateTime.utc(2026, 10, 6));
      expect(_dateOf(at(DateTime(2026, 10, 5, 12, 30, 0)).first), DateTime.utc(2026, 10, 6));
      expect(_dateOf(at(DateTime(2026, 10, 5, 12, 30, 1)).first), DateTime.utc(2026, 10, 6));
    });

    test('doneToday skips today even when the time is still ahead', () {
      final times = LocalReminders.upcomingFireTimes(
        now: noon,
        hour: 19,
        minute: 30,
        doneToday: true,
      );
      expect(_dateOf(times.first), DateTime.utc(2026, 10, 6));
      expect(times.first.hour, 19);
      expect(times.first.minute, 30);
    });

    test('returns exactly `days` entries, 28 by default, whether or not today counts', () {
      for (final doneToday in [false, true]) {
        for (final hour in [7, 19]) {
          expect(
            LocalReminders.upcomingFireTimes(
              now: noon,
              hour: hour,
              minute: 0,
              doneToday: doneToday,
            ),
            hasLength(28),
          );
          for (final days in [1, 3, 64]) {
            expect(
              LocalReminders.upcomingFireTimes(
                now: noon,
                hour: hour,
                minute: 0,
                doneToday: doneToday,
                days: days,
              ),
              hasLength(days),
            );
          }
        }
      }
    });

    test('entries are ascending, one per calendar day, all at the requested time', () {
      for (final doneToday in [false, true]) {
        final times = LocalReminders.upcomingFireTimes(
          now: noon,
          hour: 19,
          minute: 45,
          doneToday: doneToday,
        );
        _expectStrictlyAscending(times);
        _expectOnePerConsecutiveDay(times);
        expect(times.every((t) => t.hour == 19 && t.minute == 45), isTrue);
        expect(times.every((t) => t.second == 0 && t.millisecond == 0), isTrue);
        expect(times.every((t) => !t.isUtc), isTrue, reason: 'device-local wall-clock times');
      }
    });

    test('rolls over the end of a month, including February in a leap year', () {
      final january = LocalReminders.upcomingFireTimes(
        now: DateTime(2026, 1, 30, 12, 0),
        hour: 8,
        minute: 15,
        doneToday: false,
        days: 5,
      );
      expect(january.map(_dateOf).toList(), [
        DateTime.utc(2026, 1, 31),
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 2, 2),
        DateTime.utc(2026, 2, 3),
        DateTime.utc(2026, 2, 4),
      ]);

      final leapFebruary = LocalReminders.upcomingFireTimes(
        now: DateTime(2028, 2, 27, 6, 0),
        hour: 8,
        minute: 15,
        doneToday: false,
        days: 4,
      );
      expect(leapFebruary.map(_dateOf).toList(), [
        DateTime.utc(2028, 2, 27),
        DateTime.utc(2028, 2, 28),
        DateTime.utc(2028, 2, 29),
        DateTime.utc(2028, 3, 1),
      ]);
    });

    test('rolls over the end of a year', () {
      final times = LocalReminders.upcomingFireTimes(
        now: DateTime(2026, 12, 20, 6, 0),
        hour: 7,
        minute: 0,
        doneToday: false,
      );
      expect(times, hasLength(28));
      expect(_dateOf(times.first), DateTime.utc(2026, 12, 20));
      expect(_dateOf(times[11]), DateTime.utc(2026, 12, 31));
      expect(_dateOf(times[12]), DateTime.utc(2027, 1, 1));
      expect(_dateOf(times.last), DateTime.utc(2027, 1, 16));
      _expectOnePerConsecutiveDay(times);
      expect(times.every((t) => t.hour == 7 && t.minute == 0), isTrue);
    });

    // US clocks go forward on 8 March 2026 and back on 1 November 2026. The
    // assertions are on calendar fields, so they hold in any zone (in one
    // without daylight saving they are simply ordinary days).
    test('across spring-forward: still one per day, at the same wall-clock time', () {
      final times = LocalReminders.upcomingFireTimes(
        now: DateTime(2026, 3, 5, 12, 0),
        hour: 7,
        minute: 0,
        doneToday: false,
        days: 7,
      );
      expect(times.map(_dateOf).toList(), [
        for (var day = 6; day <= 12; day++) DateTime.utc(2026, 3, day),
      ]);
      expect(times.every((t) => t.hour == 7 && t.minute == 0), isTrue);
      _expectStrictlyAscending(times);
    });

    test('across fall-back: still one per day, at the same wall-clock time', () {
      final times = LocalReminders.upcomingFireTimes(
        now: DateTime(2026, 10, 29, 12, 0),
        hour: 7,
        minute: 0,
        doneToday: false,
        days: 7,
      );
      expect(times.map(_dateOf).toList(), [
        DateTime.utc(2026, 10, 30),
        DateTime.utc(2026, 10, 31),
        for (var day = 1; day <= 5; day++) DateTime.utc(2026, 11, day),
      ]);
      expect(times.every((t) => t.hour == 7 && t.minute == 0), isTrue);
      _expectStrictlyAscending(times);
    });

    test('a whole year of mornings: every clock change everywhere keeps 07:30', () {
      final times = LocalReminders.upcomingFireTimes(
        now: DateTime(2026, 1, 1, 12, 0),
        hour: 7,
        minute: 30,
        doneToday: false,
        days: 400,
      );
      expect(times, hasLength(400));
      _expectOnePerConsecutiveDay(times);
      _expectStrictlyAscending(times);
      expect(times.every((t) => t.hour == 7 && t.minute == 30), isTrue);
      // A day is 24 hours long except on a clock-change day (usually 23 or 25).
      for (var i = 1; i < times.length; i++) {
        final gap = times[i].difference(times[i - 1]);
        expect(gap, greaterThanOrEqualTo(const Duration(hours: 22)));
        expect(gap, lessThanOrEqualTo(const Duration(hours: 26)));
      }
    });

    test('a time the clocks skip or repeat still gives exactly one entry per day', () {
      // 02:30 does not exist on spring-forward night in the US and 01:30
      // happens twice on fall-back night; whatever the device makes of those
      // two days, neither is dropped or doubled.
      final skipped = LocalReminders.upcomingFireTimes(
        now: DateTime(2026, 3, 5, 12, 0),
        hour: 2,
        minute: 30,
        doneToday: false,
        days: 7,
      );
      expect(skipped, hasLength(7));
      _expectOnePerConsecutiveDay(skipped);
      _expectStrictlyAscending(skipped);

      final repeated = LocalReminders.upcomingFireTimes(
        now: DateTime(2026, 10, 29, 12, 0),
        hour: 1,
        minute: 30,
        doneToday: false,
        days: 7,
      );
      expect(repeated, hasLength(7));
      _expectOnePerConsecutiveDay(repeated);
      _expectStrictlyAscending(repeated);
    });

    test('the edges of the clock: 0:00 and 23:59', () {
      final midnight = LocalReminders.upcomingFireTimes(
        now: noon,
        hour: 0,
        minute: 0,
        doneToday: false,
        days: 3,
      );
      // Today's midnight is long gone.
      expect(midnight.map(_dateOf).toList(), [
        DateTime.utc(2026, 10, 6),
        DateTime.utc(2026, 10, 7),
        DateTime.utc(2026, 10, 8),
      ]);
      expect(midnight.every((t) => t.hour == 0 && t.minute == 0), isTrue);

      final lastMinute = LocalReminders.upcomingFireTimes(
        now: noon,
        hour: 23,
        minute: 59,
        doneToday: false,
        days: 3,
      );
      expect(lastMinute.map(_dateOf).toList(), [
        DateTime.utc(2026, 10, 5),
        DateTime.utc(2026, 10, 6),
        DateTime.utc(2026, 10, 7),
      ]);
      expect(lastMinute.every((t) => t.hour == 23 && t.minute == 59), isTrue);

      // 23:59 asked for with exactly a minute to spare, and with less.
      List<DateTime> lateAt(DateTime now) =>
          LocalReminders.upcomingFireTimes(now: now, hour: 23, minute: 59, doneToday: false);
      expect(_dateOf(lateAt(DateTime(2026, 12, 31, 23, 58, 0)).first), DateTime.utc(2026, 12, 31));
      expect(_dateOf(lateAt(DateTime(2026, 12, 31, 23, 58, 30)).first), DateTime.utc(2027, 1, 1));

      // 0:00 asked for at the very start of the day is already "now".
      final atMidnight = LocalReminders.upcomingFireTimes(
        now: DateTime(2026, 10, 5, 0, 0),
        hour: 0,
        minute: 0,
        doneToday: false,
      );
      expect(_dateOf(atMidnight.first), DateTime.utc(2026, 10, 6));
    });

    test('a time that is not on the clock, or no days at all, gives nothing', () {
      List<DateTime> at(int hour, int minute, {int days = 28}) => LocalReminders.upcomingFireTimes(
            now: noon,
            hour: hour,
            minute: minute,
            doneToday: false,
            days: days,
          );
      expect(at(24, 0), isEmpty);
      expect(at(-1, 0), isEmpty);
      expect(at(7, 60), isEmpty);
      expect(at(7, -1), isEmpty);
      expect(at(7, 0, days: 0), isEmpty);
      expect(at(7, 0, days: -5), isEmpty);
    });

    test('a UTC `now` is read as the same moment on the local clock', () {
      final fromLocal =
          LocalReminders.upcomingFireTimes(now: noon, hour: 19, minute: 30, doneToday: false);
      final fromUtc = LocalReminders.upcomingFireTimes(
        now: noon.toUtc(),
        hour: 19,
        minute: 30,
        doneToday: false,
      );
      expect(fromUtc, fromLocal);
    });
  });

  group('ReminderPlan', () {
    test('off() is disabled', () {
      const plan = ReminderPlan.off();
      expect(plan.enabled, isFalse);
      expect(plan.doneToday, isFalse);
    });

    test('keeps what it was given', () {
      const plan = ReminderPlan(enabled: true, hour: 7, minute: 5, doneToday: true);
      expect(plan.enabled, isTrue);
      expect(plan.hour, 7);
      expect(plan.minute, 5);
      expect(plan.doneToday, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// The test environment as it comes: no notifications plugin registered
// ---------------------------------------------------------------------------
void _noPluginTests() {
  group('LocalReminders without the native plugin', () {
    test('initialize, sync, requestPermission and cancelAll all complete without throwing',
        () async {
      await expectLater(LocalReminders.initialize(), completes);
      await expectLater(
        LocalReminders.sync(
          checkIn: const ReminderPlan(enabled: true, hour: 7, minute: 0, doneToday: false),
          prayer: const ReminderPlan(enabled: true, hour: 21, minute: 30, doneToday: true),
        ),
        completes,
      );
      await expectLater(
        LocalReminders.sync(checkIn: const ReminderPlan.off(), prayer: const ReminderPlan.off()),
        completes,
      );
      expect(await LocalReminders.requestPermission(), isFalse);
      await expectLater(LocalReminders.cancelAll(), completes);
      // And again, to show a first failure leaves nothing broken behind.
      await expectLater(LocalReminders.initialize(), completes);
      await expectLater(LocalReminders.cancelAll(), completes);
    });
  });
}

// ---------------------------------------------------------------------------
// The real plugin's Dart side, talking to a fake native side
// ---------------------------------------------------------------------------

/// Stands in for the native half of flutter_local_notifications: records
/// every call and keeps the set of notifications that would be pending.
class _FakeNativeNotifications {
  final List<MethodCall> calls = [];

  /// Scheduled and not since cancelled, by notification id.
  final Map<int, Map<Object?, Object?>> pending = {};

  bool failInitialize = false;

  /// What `initialize` answers. Real iOS answers false when, as here, no
  /// permissions are requested at start-up.
  bool initializeResult = true;
  bool permissionGranted = true;
  Duration delay = Duration.zero;
  void Function(MethodCall call)? onCall;

  List<MethodCall> callsTo(String method) => calls.where((c) => c.method == method).toList();

  List<int> get cancelledIds => callsTo('cancel').map((call) {
        final arguments = call.arguments;
        // Android sends {id, tag}; iOS sends the bare id.
        return (arguments is Map ? arguments['id'] : arguments) as int;
      }).toList();

  List<int> get scheduledIds => callsTo('zonedSchedule')
      .map((call) => (call.arguments as Map<Object?, Object?>)['id']! as int)
      .toList();

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    onCall?.call(call);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    switch (call.method) {
      case 'initialize':
        if (failInitialize) {
          throw PlatformException(code: 'invalid_icon', message: 'no such drawable');
        }
        return initializeResult;
      case 'zonedSchedule':
        final arguments = call.arguments as Map<Object?, Object?>;
        pending[arguments['id']! as int] = arguments;
        return null;
      case 'cancel':
        final arguments = call.arguments;
        pending.remove(arguments is Map ? arguments['id'] : arguments);
        return null;
      case 'requestNotificationsPermission':
      case 'requestPermissions':
      case 'areNotificationsEnabled':
        return permissionGranted;
      default:
        return null;
    }
  }
}

void _mockedPluginTests() {
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final checkInIds = [for (var id = 1000; id <= 1027; id++) id];
  final prayerIds = [for (var id = 2000; id <= 2027; id++) id];

  late _FakeNativeNotifications native;

  /// A plan for two hours from now, so "is today's still ahead?" cannot flip
  /// between the test working out what to expect and the service doing it.
  ReminderPlan planForSoon({bool doneToday = false}) {
    final soon = DateTime.now().add(const Duration(hours: 2));
    return ReminderPlan(
      enabled: true,
      hour: soon.hour,
      minute: soon.minute,
      doneToday: doneToday,
    );
  }

  List<DateTime> expectedTimes(ReminderPlan plan) => LocalReminders.upcomingFireTimes(
        now: DateTime.now(),
        hour: plan.hour,
        minute: plan.minute,
        doneToday: plan.doneToday,
      );

  /// The instant a pending notification was scheduled for (Android reads the
  /// zone-less form together with the zone name).
  DateTime scheduledInstant(Map<Object?, Object?> arguments) =>
      DateTime.parse('${arguments['scheduledDateTime']}Z');

  void expectScheduledAt(List<int> ids, List<DateTime> expected) {
    expect(expected, hasLength(ids.length));
    for (var i = 0; i < ids.length; i++) {
      final arguments = native.pending[ids[i]];
      expect(arguments, isNotNull, reason: 'id ${ids[i]} should be pending');
      expect(arguments!['timeZoneName'], 'Etc/UTC');
      expect(
        scheduledInstant(arguments).isAtSameMomentAs(expected[i]),
        isTrue,
        reason: 'id ${ids[i]}: ${arguments['scheduledDateTime']} UTC should be ${expected[i]}',
      );
    }
  }

  group('LocalReminders with the plugin (fake native side)', () {
    setUp(() {
      native = _FakeNativeNotifications();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, native.handle);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    // --- Start-up. These two must come first: once the plugin has started,
    // --- LocalReminders does not start it again for the rest of the run.

    test('Android: a start-up failure is contained, nothing is scheduled, and it is retried',
        () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      native.failInitialize = true;

      await expectLater(LocalReminders.initialize(), completes);
      await expectLater(
        LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon()),
        completes,
      );

      final attempts = native.callsTo('initialize');
      expect(attempts, hasLength(2), reason: 'initialize(), then again from sync()');
      for (final attempt in attempts) {
        expect(attempt.arguments, {'defaultIcon': 'ic_stat_trellis'});
      }
      expect(native.callsTo('zonedSchedule'), isEmpty);
      expect(native.pending, isEmpty);
    });

    test('iOS: start-up requests no permission; requestPermission asks for alert, sound, badge',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      native.initializeResult = false;

      await LocalReminders.initialize();
      await LocalReminders.initialize();

      final started = native.callsTo('initialize');
      expect(started, hasLength(1), reason: 'the plugin is started once');
      final settings = started.single.arguments as Map<Object?, Object?>;
      expect(settings['requestAlertPermission'], isFalse);
      expect(settings['requestBadgePermission'], isFalse);
      expect(settings['requestSoundPermission'], isFalse);
      expect(settings['requestProvisionalPermission'], isFalse);
      expect(settings['requestCriticalPermission'], isFalse);
      expect(settings['defaultPresentBanner'], isTrue);
      expect(settings['defaultPresentList'], isTrue);
      expect(settings['defaultPresentSound'], isTrue);
      expect(native.callsTo('requestPermissions'), isEmpty);

      // A `false` from iOS's initialize is not a failure: scheduling goes on.
      final plan = planForSoon();
      final expected = expectedTimes(plan);
      await LocalReminders.sync(checkIn: plan, prayer: const ReminderPlan.off());
      expect(native.pending.keys.toList()..sort(), checkInIds);
      expectScheduledAt(checkInIds, expected);
      final first = native.pending[1000]!;
      expect(first['title'], 'Daily Check-In');
      expect(first['body'], 'Take a moment to check in on your Rule of Life.');
      expect(first['payload'], 'check_in');
      expect(first['matchDateTimeComponents'], isNull, reason: 'one-off, not repeating');
      expect(first['scheduledDateTimeISO8601'], endsWith('Z'));
      expect(native.cancelledIds, prayerIds);

      expect(await LocalReminders.requestPermission(), isTrue);
      expect(native.callsTo('requestPermissions').single.arguments, {
        'sound': true,
        'alert': true,
        'badge': true,
        'provisional': false,
        'critical': false,
        'carPlay': false,
        'providesAppNotificationSettings': false,
      });

      native.permissionGranted = false;
      expect(await LocalReminders.requestPermission(), isFalse);

      await LocalReminders.cancelAll();
      expect(native.pending, isEmpty);
      expect(native.callsTo('cancelAll'), isEmpty);
    });

    // --- Everything below runs as Android (the test default).

    test('sync schedules a 28-day window for an enabled reminder and cancels a disabled one',
        () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final plan = planForSoon();
      final expected = expectedTimes(plan);

      await LocalReminders.sync(checkIn: plan, prayer: const ReminderPlan.off());

      expect(native.pending.keys.toList()..sort(), checkInIds);
      expectScheduledAt(checkInIds, expected);
      expect(native.cancelledIds, prayerIds, reason: 'only the disabled reminder is cancelled');

      for (final id in checkInIds) {
        final arguments = native.pending[id]!;
        expect(arguments['title'], 'Daily Check-In');
        expect(arguments['body'], 'Take a moment to check in on your Rule of Life.');
        expect(arguments['payload'], 'check_in');
        expect(arguments['matchDateTimeComponents'], isNull, reason: 'one-off, not repeating');
        final android = arguments['platformSpecifics']! as Map<Object?, Object?>;
        expect(android['scheduleMode'], 'inexactAllowWhileIdle');
        expect(android['channelId'], 'reminders');
        expect(android['channelName'], 'Reminders');
        expect(android['channelDescription'], 'Daily check-in and prayer reminders');
        expect(android['importance'], Importance.defaultImportance.value);
        expect(android['icon'], 'ic_stat_trellis');
        expect(android['fullScreenIntent'], isFalse);
      }
    });

    test('the prayer reminder has its own wording, payload and id range', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final plan = planForSoon();
      final expected = expectedTimes(plan);

      await LocalReminders.sync(checkIn: const ReminderPlan.off(), prayer: plan);

      expect(native.pending.keys.toList()..sort(), prayerIds);
      expectScheduledAt(prayerIds, expected);
      expect(native.cancelledIds, checkInIds);
      for (final id in prayerIds) {
        final arguments = native.pending[id]!;
        expect(arguments['title'], 'Prayer Garden');
        expect(arguments['body'], 'Your prayer list is waiting.');
        expect(arguments['payload'], 'prayer');
      }
    });

    test('both on: 56 pending, nothing cancelled', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final plan = planForSoon();

      await LocalReminders.sync(checkIn: plan, prayer: plan);

      expect(native.pending.keys.toList()..sort(), [...checkInIds, ...prayerIds]);
      expect(native.cancelledIds, isEmpty);
    });

    test('doneToday leaves today out and still fills all 28 slots', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final plan = planForSoon(doneToday: true);
      final expected = expectedTimes(plan);
      final today = _dateOf(DateTime.now());

      await LocalReminders.sync(checkIn: plan, prayer: const ReminderPlan.off());

      expectScheduledAt(checkInIds, expected);
      final first = scheduledInstant(native.pending[1000]!).toLocal();
      expect(_dateOf(first).isAfter(today), isTrue, reason: 'first reminder is not today');
    });

    test('a later sync replaces the earlier schedule in place', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      await LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon());
      expect(native.pending, hasLength(56));

      // The check-in time moves and the prayer reminder is switched off.
      final later = DateTime.now().add(const Duration(hours: 5));
      final moved =
          ReminderPlan(enabled: true, hour: later.hour, minute: later.minute, doneToday: false);
      await LocalReminders.sync(checkIn: moved, prayer: const ReminderPlan.off());

      expect(native.pending.keys.toList()..sort(), checkInIds);
      expectScheduledAt(checkInIds, expectedTimes(moved));
    });

    test('a plan with an impossible time is treated as off', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      await LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon());

      await LocalReminders.sync(
        checkIn: const ReminderPlan(enabled: true, hour: 24, minute: 0, doneToday: false),
        prayer: const ReminderPlan(enabled: true, hour: 7, minute: 75, doneToday: false),
      );

      expect(native.pending, isEmpty);
    });

    test('cancelAll removes both reminders, one id at a time, and nothing else', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      await LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon());
      expect(native.pending, hasLength(56));
      native.calls.clear();

      await LocalReminders.cancelAll();

      expect(native.pending, isEmpty);
      expect(native.cancelledIds, [...checkInIds, ...prayerIds]);
      expect(native.calls.map((c) => c.method).toSet(), {'cancel'});
    });

    test('the plugin-wide cancelAll is never used, so other notifications are left alone',
        () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      await LocalReminders.sync(checkIn: planForSoon(), prayer: const ReminderPlan.off());
      await LocalReminders.sync(checkIn: const ReminderPlan.off(), prayer: const ReminderPlan.off());
      await LocalReminders.cancelAll();

      expect(native.callsTo('cancelAll'), isEmpty);
      expect(native.callsTo('cancelAllPendingNotifications'), isEmpty);
      final touched = {...native.cancelledIds, ...native.scheduledIds};
      expect(touched.difference({...checkInIds, ...prayerIds}), isEmpty);
    });

    test('calls made back to back: only the newest does any work', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      native.delay = const Duration(milliseconds: 1);

      final first = LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon());
      final second =
          LocalReminders.sync(checkIn: const ReminderPlan.off(), prayer: const ReminderPlan.off());
      final third = LocalReminders.sync(checkIn: const ReminderPlan.off(), prayer: planForSoon());
      await Future.wait([first, second, third]);

      expect(native.pending.keys.toList()..sort(), prayerIds);
      expect(native.scheduledIds, prayerIds, reason: 'the superseded calls scheduled nothing');
      expect(native.cancelledIds, checkInIds);
    });

    test('a newer sync takes over from one that is still running', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      native.delay = const Duration(milliseconds: 2);
      final running = Completer<void>();
      native.onCall = (call) {
        if (call.method == 'zonedSchedule' && !running.isCompleted) running.complete();
      };

      final older = LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon());
      await running.future;
      final newer =
          LocalReminders.sync(checkIn: const ReminderPlan.off(), prayer: const ReminderPlan.off());
      await Future.wait([older, newer]);

      expect(native.pending, isEmpty, reason: 'the newer (everything off) call has the last word');
      expect(native.scheduledIds.length, lessThan(56), reason: 'the older run stopped early');
    });

    test('cancelAll outranks a sync that was queued before it', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      native.delay = const Duration(milliseconds: 1);

      final sync = LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon());
      final cancel = LocalReminders.cancelAll();
      await Future.wait([sync, cancel]);

      expect(native.pending, isEmpty);
      expect(native.scheduledIds, isEmpty);
    });

    test('a native failure part-way through is logged, not thrown, and the next sync works',
        () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      var failed = false;
      native.onCall = (call) {
        if (call.method == 'zonedSchedule' && !failed) {
          failed = true;
          throw PlatformException(code: 'Error 1', message: 'Notifications are not allowed');
        }
      };

      await expectLater(
        LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon()),
        completes,
      );
      expect(native.pending, isEmpty, reason: 'the refused run stops rather than retrying 56 times');
      expect(native.scheduledIds, hasLength(1));

      await LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon());
      expect(native.pending, hasLength(56));
    });

    test('requestPermission reports what Android answers', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();

      expect(await LocalReminders.requestPermission(), isTrue);
      expect(native.callsTo('requestNotificationsPermission'), hasLength(1));

      native.permissionGranted = false;
      expect(await LocalReminders.requestPermission(), isFalse);
    });

    test('nothing at all happens on desktop platforms', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        await LocalReminders.initialize();
        await LocalReminders.sync(checkIn: planForSoon(), prayer: planForSoon());
        expect(await LocalReminders.requestPermission(), isFalse);
        await LocalReminders.cancelAll();
      }
      expect(native.calls, isEmpty);
    });
  });
}
