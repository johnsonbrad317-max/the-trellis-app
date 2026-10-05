import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/check_in_entry.dart';
import '../models/prayer_item.dart';
import '../models/rule_item.dart';
import '../models/runner_profile.dart';
import 'local_reminders.dart';

/// Keeps this phone's own reminders (LocalReminders — the daily check-in and
/// the prayer list) in step with the signed-in Runner: the times they chose,
/// whether each reminder is switched on, and whether today's is already done.
///
/// Rather than have every setter remember to reschedule, this simply listens
/// to the profile and re-syncs (a moment after things settle) whenever
/// anything changes — a new reminder time, a toggle, a check-in, a prayer —
/// and again each time the app comes back to the foreground, which also rolls
/// the 28-day schedule forward.
///
/// Owned by RunnerShell: only there has the Runner's own data (rhythms, check-
/// ins, prayer list) been loaded. In the Witness and Cloud views nothing is
/// rescheduled and whatever was already scheduled is left alone.
class ReminderSync with WidgetsBindingObserver {
  ReminderSync(this.profile);

  final RunnerProfile profile;

  static const _settle = Duration(seconds: 1);

  Timer? _pending;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    profile.addListener(_schedule);
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _pending?.cancel();
    profile.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  void _schedule() {
    _pending?.cancel();
    _pending = Timer(_settle, _sync);
  }

  Future<void> _sync() async {
    // Until the Runner's own lists have loaded, "no prayers" and "no check-in
    // yesterday" are not facts — syncing now would cancel real reminders.
    if (!profile.isRunnerDataLoaded) return;
    final now = DateTime.now();
    await LocalReminders.sync(
      checkIn: checkInPlan(profile, now),
      prayer: prayerPlan(profile, now),
    );
  }

  static ReminderPlan checkInPlan(RunnerProfile profile, DateTime now) => checkInPlanFor(
        switchedOn: profile.notificationPreferences[NotificationCategory.checkInReminder] ?? true,
        ruleItems: profile.ruleItems,
        history: profile.checkInHistory,
        hour: profile.dailyCheckInReminder.hour,
        minute: profile.dailyCheckInReminder.minute,
        now: now,
      );

  static ReminderPlan prayerPlan(RunnerProfile profile, DateTime now) => prayerPlanFor(
        switchedOn: profile.notificationPreferences[NotificationCategory.prayerReminders] ?? true,
        prayers: profile.prayerItems,
        hour: profile.prayerReminderTime.hour,
        minute: profile.prayerReminderTime.minute,
        now: now,
      );

  /// The daily check-in reminder: on while it is switched on and there is a
  /// Rule of Life to check in on. "Done today" means yesterday — the day the
  /// check-in looks back on — has already been reported (or had nothing due).
  @visibleForTesting
  static ReminderPlan checkInPlanFor({
    required bool switchedOn,
    required List<RuleItem> ruleItems,
    required List<CheckInEntry> history,
    required int hour,
    required int minute,
    required DateTime now,
  }) {
    if (!switchedOn || ruleItems.isEmpty) return const ReminderPlan.off();

    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final nothingWasDue = !ruleItems.any((item) => item.scheduledFor(yesterday));
    final reported = history.any(
      (entry) =>
          entry.date.year == yesterday.year &&
          entry.date.month == yesterday.month &&
          entry.date.day == yesterday.day,
    );
    return ReminderPlan(
      enabled: true,
      hour: hour,
      minute: minute,
      doneToday: nothingWasDue || reported,
    );
  }

  /// The prayer-list reminder: on while it is switched on and there is at
  /// least one unanswered prayer. "Done today" means every one of them has
  /// already been prayed for today.
  @visibleForTesting
  static ReminderPlan prayerPlanFor({
    required bool switchedOn,
    required List<PrayerItem> prayers,
    required int hour,
    required int minute,
    required DateTime now,
  }) {
    final active = prayers.where((item) => !item.isAnswered).toList();
    if (!switchedOn || active.isEmpty) return const ReminderPlan.off();

    bool prayedToday(DateTime? date) =>
        date != null && date.year == now.year && date.month == now.month && date.day == now.day;
    return ReminderPlan(
      enabled: true,
      hour: hour,
      minute: minute,
      doneToday: active.every((item) => prayedToday(item.lastPrayedDate)),
    );
  }
}
