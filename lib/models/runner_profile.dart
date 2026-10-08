import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/analytics_service.dart';
import '../services/local_reminders.dart';
import '../services/meeting_spot_service.dart';
import '../services/prayer_photo_service.dart';
import '../services/push_notifications.dart';
import '../services/purchases_service.dart';
import '../services/supabase_client.dart';
import 'check_in_entry.dart';
import 'church_code.dart';
import 'church_rhythm_metric.dart';
import 'church_roster_entry.dart';
import 'cloud_triage.dart';
import 'dna_rhythm.dart';
import 'meeting_proposal_engine.dart';
import 'meeting_request.dart';
import 'membership_gate.dart';
import 'pairing_code_preview.dart';
import 'pending_unlock_request.dart';
import 'prayer_item.dart';
import 'preview_sample_data.dart';
import 'rhythm_analytics.dart';
import 'rule_item.dart';
import 'rule_of_life_baseline.dart';
import 'support_request.dart';
import 'user_role.dart';
import 'watched_prayer_item.dart';
import 'watched_runner.dart';
import 'witness.dart';
import 'witness_notice.dart';

enum MembershipStatus { trial, active, cancelled }

extension MembershipStatusDb on MembershipStatus {
  String get dbValue => switch (this) {
        MembershipStatus.trial => 'trial',
        MembershipStatus.active => 'active',
        MembershipStatus.cancelled => 'cancelled',
      };
}

MembershipStatus membershipStatusFromDb(String value) => switch (value) {
      'trial' => MembershipStatus.trial,
      'active' => MembershipStatus.active,
      'cancelled' => MembershipStatus.cancelled,
      _ => throw ArgumentError('Unknown membership_status: $value'),
    };

/// What [RunnerProfile.cancelMembership] did. Membership is billed by the
/// App Store / Google Play (via RevenueCat), so it can only be cancelled
/// there — this app never edits `membership_status` itself; the
/// revenuecat-webhook Edge Function is its sole writer.
enum MembershipCancellationOutcome {
  /// The store's subscription-management page was opened.
  openedStoreSettings,

  /// No store subscription is attached to this account (e.g. membership came
  /// from a church code), so there is nothing to cancel in a store.
  notStoreBilled,

  /// A store subscription exists but its management page couldn't be opened.
  couldNotOpenStoreSettings,
}

/// The `profiles` columns this client may read. Column-level SELECT is all
/// the database grants (supabase/migrations/011_security_lockdown.sql), so
/// `select('*')` on `profiles` is rejected outright — always name columns.
/// `fcm_token`, `home_address`, and `work_address` are deliberately absent:
/// the first is write-only from the client, the other two come from
/// `get_my_private_profile()` (see [RunnerProfile._fetchPrivateFields]).
const _profileColumns = 'id, name, email, role, membership_status, church_id, '
    'is_church_affiliation_locked, accountability_lock_enabled, '
    'accountability_lock_removal_pending, notification_preferences, '
    'daily_check_in_reminder, has_committed_rule, consumer_health_data_consent, '
    'prayer_reminder_time, has_completed_scheduling_setup, calendar_connected, '
    'cloud_admin_church_id';

enum NotificationCategory {
  checkInReminder,
  prayerReminders,
  anchorRhythmAlerts,
  weeklyRollUp,
  meetingRequests,
  quietRunnerAlerts,
}

extension NotificationCategoryLabel on NotificationCategory {
  String get label => switch (this) {
        NotificationCategory.checkInReminder => 'Daily check-in reminder',
        NotificationCategory.prayerReminders => 'Prayer list reminder',
        NotificationCategory.anchorRhythmAlerts => 'Anchor Rhythm alerts',
        NotificationCategory.weeklyRollUp => 'Weekly roll-up from my Runners',
        NotificationCategory.meetingRequests => 'Meeting & prayer requests',
        NotificationCategory.quietRunnerAlerts => 'Check-In Alerts',
      };

  /// Whether this category is relevant to `role` — the Notification
  /// Settings screen only renders toggles that apply to the active role.
  bool visibleForRole(UserRole role) => switch (this) {
        // A Runner's own reminders, sent by this phone at the times they chose
        // (LocalReminders) — the only two a Runner can switch off.
        NotificationCategory.checkInReminder => role == UserRole.runner,
        NotificationCategory.prayerReminders => role == UserRole.runner,
        // A Witness is the one alerted when their Runner misses an Anchor
        // Rhythm — the Runner isn't notified about their own miss this way.
        NotificationCategory.anchorRhythmAlerts => role == UserRole.witness,
        // The weekly roll-up is the WITNESS's to mute. A Runner cannot stop
        // their own roll-up going out — that would defeat the point of having
        // a Witness.
        NotificationCategory.weeklyRollUp => role == UserRole.witness,
        // Both Runner and Witness send/receive meeting proposals.
        NotificationCategory.meetingRequests => role != UserRole.cloud,
        // A Runner who goes quiet, hasn't started a Rule of Life, or may have
        // removed the app (push-notification-engine's witness_nudge). Like the
        // roll-up, the WITNESS's to mute — never the Runner's.
        NotificationCategory.quietRunnerAlerts => role == UserRole.witness,
      };
}

extension NotificationCategoryDb on NotificationCategory {
  String get dbKey => switch (this) {
        NotificationCategory.checkInReminder => 'check_in_reminder',
        NotificationCategory.prayerReminders => 'prayer_reminders',
        NotificationCategory.anchorRhythmAlerts => 'anchor_rhythm_alerts',
        NotificationCategory.weeklyRollUp => 'weekly_roll_up',
        NotificationCategory.meetingRequests => 'meeting_requests',
        NotificationCategory.quietRunnerAlerts => 'quiet_runner_alerts',
      };
}

String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;

TimeOfDay _timeFromDb(String value) {
  final parts = value.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

String _timeToDb(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

WatchedPrayerItem _watchedPrayerFromRow(Map<String, dynamic> row) => WatchedPrayerItem(
      id: row['id'] as String,
      title: row['title'] as String,
      details: row['details'] as String? ?? '',
      isAnswered: row['is_answered'] as bool? ?? false,
      lastPrayedDate: row['last_prayed_date'] == null
          ? null
          : DateTime.parse(row['last_prayed_date'] as String),
      answeredDate: row['answered_date'] == null
          ? null
          : DateTime.parse(row['answered_date'] as String),
    );

/// The signed-in user's profile and settings, backed by the live Supabase
/// project (see supabase/migrations/). A single instance is shared across
/// all three shells — Runner and Witness are just two free-switching views
/// on the same account; Cloud is a separate grant (see [cloudAdminChurchId])
/// unlocked by redeeming a church's Cloud Access Code.
///
/// Data is loaded in layers rather than all at once: [loadCurrent] (called
/// once at sign-in) fetches only this user's own profile/rule items/check-
/// ins — cheap, single-user-scoped. [loadRunnerData], [loadWitnessData], and
/// [loadCloudData] each fire once, lazily, the first time their respective
/// shell is actually entered, since the Witness and Cloud views require
/// multi-user fan-out queries that have no business running on cold boot.
class RunnerProfile extends ChangeNotifier {
  /// The signed-in user's profile, if one has finished loading — a
  /// pragmatic global handle for code that has no BuildContext to thread
  /// one through, namely [NotificationRouter] reacting to a push
  /// notification tap that may arrive before any screen has a reference to
  /// this object. Set at the end of [loadCurrent]; cleared on sign-out.
  static RunnerProfile? current;

  RunnerProfile._({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.membershipStatus,
    this.churchName,
    this.churchId,
    required this.isChurchAffiliationLocked,
    required this.accountabilityLockEnabled,
    this.accountabilityLockRemovalPending = false,
    required this.notificationPreferences,
    required this.witnesses,
    required this.ruleItems,
    required this.dailyCheckInReminder,
    required this.hasCommittedRule,
    this.ruleCommittedAt,
    this.phoneNumber,
    this.hasSeenWelcome = true,
    required this.consumerHealthDataConsent,
    required this.checkInHistory,
    required this.prayerReminderTime,
    required this.prayerItems,
    required this.hasCompletedSchedulingSetup,
    required this.calendarConnected,
    this.homeAddress,
    this.workAddress,
    required this.meetingRequests,
    required this.watchedRunners,
    required this.churchRoster,
    this.cloudAdminChurchId,
    required this.activeLicenseCount,
    required this.licenseCap,
    required this.churchCodes,
    required this.dnaRhythms,
    required this.churchRhythmMetrics,
    required this.graceNudgeLog,
    required this.pendingUnlockRuleItemIds,
    required this.incomingUnlockRequests,
    this.isPreview = false,
  });

  /// Fetches only the signed-in user's own profile, Rule of Life, and
  /// trailing-180-day check-in history — deliberately lean, no multi-user
  /// queries. Call [loadRunnerData]/[loadWitnessData]/[loadCloudData]
  /// afterwards as each respective shell is entered.
  static Future<RunnerProfile> loadCurrent() async {
    final userId = supabase.auth.currentUser!.id;

    final profileRow = await _fetchProfileRow(userId);
    final privateFields = await _fetchPrivateFields(userId);

    final ruleItemRows = await supabase.from('rule_items').select().eq('runner_id', userId);

    final since = DateTime.now().subtract(const Duration(days: 180));
    final checkInRows = await supabase
        .from('check_ins')
        .select()
        .eq('runner_id', userId)
        .gte('check_in_date', _dateOnly(since));

    final notificationPrefsJson =
        profileRow['notification_preferences'] as Map<String, dynamic>? ?? const {};
    final optional = await _fetchOptionalProfileFields(userId);

    // Fire-and-forget: registering a device token (and the permission
    // prompt that can come with it) has no business blocking cold boot —
    // see PushNotifications.registerForCurrentUser's own error handling.
    unawaited(PushNotifications.registerForCurrentUser(userId));
    unawaited(PurchasesService.identify(userId));
    unawaited(
      AnalyticsService.identifyUser(
        hashedUserId: _hashUserId(userId),
        churchId: profileRow['church_id'] as String?,
      ),
    );

    final profile = RunnerProfile._(
      id: userId,
      name: profileRow['name'] as String,
      email: profileRow['email'] as String,
      role: userRoleFromDb(profileRow['role'] as String),
      membershipStatus: membershipStatusFromDb(profileRow['membership_status'] as String),
      churchName: (profileRow['church'] as Map<String, dynamic>?)?['name'] as String?,
      churchId: profileRow['church_id'] as String?,
      isChurchAffiliationLocked: profileRow['is_church_affiliation_locked'] as bool? ?? false,
      accountabilityLockEnabled: profileRow['accountability_lock_enabled'] as bool? ?? false,
      accountabilityLockRemovalPending:
          profileRow['accountability_lock_removal_pending'] as bool? ?? false,
      notificationPreferences: {
        for (final category in NotificationCategory.values)
          category: notificationPrefsJson[category.dbKey] as bool? ?? true,
      },
      witnesses: [],
      ruleItems: [for (final row in ruleItemRows) RuleItem.fromRow(row)],
      dailyCheckInReminder: _timeFromDb(profileRow['daily_check_in_reminder'] as String),
      hasCommittedRule: profileRow['has_committed_rule'] as bool? ?? false,
      ruleCommittedAt: optional.ruleCommittedAt,
      phoneNumber: optional.phoneNumber,
      hasSeenWelcome: optional.hasSeenWelcome,
      consumerHealthDataConsent: profileRow['consumer_health_data_consent'] as bool? ?? false,
      checkInHistory: CheckInEntry.fromRows(List<Map<String, dynamic>>.from(checkInRows)),
      prayerReminderTime: _timeFromDb(profileRow['prayer_reminder_time'] as String),
      prayerItems: [],
      hasCompletedSchedulingSetup: profileRow['has_completed_scheduling_setup'] as bool? ?? false,
      calendarConnected: profileRow['calendar_connected'] as bool? ?? false,
      homeAddress: privateFields.homeAddress,
      workAddress: privateFields.workAddress,
      meetingRequests: [],
      watchedRunners: [],
      churchRoster: [],
      cloudAdminChurchId: profileRow['cloud_admin_church_id'] as String?,
      activeLicenseCount: 0,
      licenseCap: 0,
      churchCodes: [],
      dnaRhythms: [],
      churchRhythmMetrics: [],
      graceNudgeLog: [],
      pendingUnlockRuleItemIds: {},
      incomingUnlockRequests: [],
    );
    // Before the first screen is built, so a gated Runner never glimpses the
    // shell behind the gate. Never throws (see refreshMembership).
    await profile.refreshMembership();
    current = profile;
    return profile;
  }

  /// The signed-in user's own `profiles` row (plus their church's name),
  /// limited to [_profileColumns]. Shared by [loadCurrent] and
  /// [redeemChurchCode] so the two can never drift apart.
  static Future<Map<String, dynamic>> _fetchProfileRow(String userId) async {
    return await supabase
        .from('profiles')
        .select('$_profileColumns, church:church_id(name)')
        .eq('id', userId)
        .single();
  }

  /// Columns newer than the oldest database this build must still open
  /// against, each read on its own so that a column that isn't there yet
  /// (migration 021 not applied) costs only that one value — never sign-in.
  static Future<({String? phoneNumber, DateTime? ruleCommittedAt, bool hasSeenWelcome})>
      _fetchOptionalProfileFields(String userId) async {
    Future<Object?> read(String column) async {
      try {
        final row = await supabase.from('profiles').select(column).eq('id', userId).single();
        return row[column];
      } catch (error) {
        debugPrint('profiles.$column unavailable: ${error.runtimeType}');
        return null;
      }
    }

    final phone = await read('phone_number');
    final committedAt = await read('rule_committed_at');
    final seenWelcome = await read('has_seen_welcome');
    return (
      phoneNumber: phone is String && phone.trim().isNotEmpty ? phone.trim() : null,
      ruleCommittedAt: committedAt is String ? DateTime.tryParse(committedAt)?.toLocal() : null,
      // Without the column (migration 023 not applied) nobody is shown the
      // welcome walkthrough automatically; it stays reachable from the menu.
      hasSeenWelcome: seenWelcome is bool ? seenWelcome : true,
    );
  }

  /// Home/work address, which the database withholds from every direct read
  /// of `profiles` (a Witness or Cloud admin can see the rest of a row, never
  /// these) and releases to the owner only through `get_my_private_profile()`.
  ///
  /// Falls back to a direct column read if that RPC isn't deployed yet, so
  /// this build also works against a database that hasn't had migration 011
  /// applied — and degrades to "no address on file" rather than failing
  /// sign-in if neither path works.
  static Future<({String? homeAddress, String? workAddress})> _fetchPrivateFields(
    String userId,
  ) async {
    ({String? homeAddress, String? workAddress}) fromRow(Object? row) => row is Map
        ? (
            homeAddress: row['home_address'] as String?,
            workAddress: row['work_address'] as String?,
          )
        : (homeAddress: null, workAddress: null);

    try {
      // A `returns table` function comes back as a list of rows.
      final result = await supabase.rpc('get_my_private_profile');
      return fromRow(result is List ? (result.isEmpty ? null : result.first) : result);
    } catch (rpcError) {
      debugPrint('get_my_private_profile unavailable, trying direct read: $rpcError');
    }

    try {
      final row = await supabase
          .from('profiles')
          .select('home_address, work_address')
          .eq('id', userId)
          .single();
      return fromRow(row);
    } catch (readError) {
      debugPrint('Could not load private profile fields: $readError');
      return (homeAddress: null, workAddress: null);
    }
  }

  /// One-way SHA-256 of the Supabase auth user id — analytics identifies
  /// "the same person came back", never the raw account id itself.
  static String _hashUserId(String userId) => sha256.convert(utf8.encode(userId)).toString();

  final String id;
  String name;
  String email;
  UserRole role;
  MembershipStatus membershipStatus;
  String? churchName;
  String? churchId;
  bool isChurchAffiliationLocked;
  bool accountabilityLockEnabled;

  /// True while a request to disable [accountabilityLockEnabled] is
  /// awaiting a Witness's approval — see [requestAccountabilityLockRemoval].
  bool accountabilityLockRemovalPending;
  final Map<NotificationCategory, bool> notificationPreferences;
  final List<Witness> witnesses;
  String? pairingCode;
  final List<RuleItem> ruleItems;
  TimeOfDay dailyCheckInReminder;
  bool hasCommittedRule;

  /// When the Rule of Life was committed (stamped by the database, migration
  /// 021). Starts the first-week settle period — see [isRuleItemSet] — and is
  /// the day after which a Witness starts seeing missed days. Null if not
  /// committed, or on a database that doesn't record it yet.
  DateTime? ruleCommittedAt;

  /// Whether this account has been shown the welcome walkthrough (the slides
  /// explaining Runner, Witness and Cloud). Shown once, after the first
  /// sign-in; always available again from the menu.
  bool hasSeenWelcome;

  /// Records that the welcome walkthrough has been seen. Best-effort: a
  /// failed write only means it may be shown once more.
  Future<void> markWelcomeSeen() async {
    hasSeenWelcome = true;
    notifyListeners();
    if (isPreview) return;
    try {
      await supabase.from('profiles').update({'has_seen_welcome': true}).eq('id', id);
    } catch (error) {
      debugPrint('markWelcomeSeen failed: ${error.runtimeType}');
    }
  }

  /// This person's own mobile number in international form (`+1…`), asked
  /// for at sign-up. Shown to the people they are paired with — their
  /// Witnesses, and the Runners they walk with — so those people can text
  /// them. Null for an account created before it was asked for.
  String? phoneNumber;

  /// True once this account agreed to the Terms of Service/Privacy
  /// Policy/Consumer Health Data Notice checkbox on
  /// auth_onboarding_screen.dart's Create Account form — the Tier 1 MHMDA
  /// (Washington's My Health My Data Act) collection consent, required
  /// before the account itself is even created. See
  /// [recordConsumerHealthDataConsent]. Tier 2 (sharing that data with a
  /// specific third party — a church or a Witness) is gated separately, per
  /// relationship: church_data_sharing_consent_screen.dart for church
  /// joining, witness_pairing_code_screen.dart for Witness pairing.
  bool consumerHealthDataConsent;
  final List<CheckInEntry> checkInHistory;
  TimeOfDay prayerReminderTime;
  final List<PrayerItem> prayerItems;
  bool hasCompletedSchedulingSetup;
  bool calendarConnected;
  String? homeAddress;
  String? workAddress;
  final List<MeetingRequest> meetingRequests;
  String? selectedRunnerId;
  final List<WatchedRunner> watchedRunners;

  /// Church-wide roster of every Runner under this church's canopy, as
  /// visible to a Cloud admin. Independent of [watchedRunners], which is
  /// scoped to a single Witness's own paired Runners.
  final List<ChurchRosterEntry> churchRoster;

  /// Non-null once this account has redeemed a church's Cloud Access Code —
  /// the sole gate on Cloud access; independent of [role], which only ever
  /// toggles between Runner and Witness. See
  /// supabase/migrations/002_grants_and_cloud_access.sql.
  String? cloudAdminChurchId;

  int activeLicenseCount;
  int licenseCap;
  DateTime? annualRenewalDate;
  double ratePerRunner = 15;

  /// Church-wide invite codes (Cloud Treasury tab), both unredeemed and
  /// redeemed — filter on [ChurchCode.isRedeemed] for the "Unused Codes"
  /// list.
  final List<ChurchCode> churchCodes;

  /// Rhythms the Cloud role mandates congregation-wide — injected into a
  /// new Runner's Rule of Life when they redeem this church's code. Kept
  /// entirely separate from a Runner's personal Anchor Rhythms; see
  /// [DnaRhythm].
  final List<DnaRhythm> dnaRhythms;

  /// Aggregate, church-wide completion rate per rhythm — drives the Cloud's
  /// Congregational Health metrics. Populated by [loadCloudData] from the
  /// k-anonymity-gated `get_congregational_health()` RPC; see
  /// [isCongregationalHealthLocked].
  final List<ChurchRhythmMetric> churchRhythmMetrics;

  /// Whether Congregational Health is still below the k-anonymity floor —
  /// mirrors `get_congregational_health()`'s `is_locked` result. True until
  /// [loadCloudData] has actually run.
  bool isCongregationalHealthLocked = true;

  /// How many Runners in the church are actively tracked (a real check-in
  /// in the trailing 30 days) — shown on the k-anonymity lock screen.
  int trackedRunnerCount = 0;

  /// Grace Mechanics: rhythms that just crossed three consecutive Anchor
  /// misses. Never surfaced to the Runner — this is populated (by
  /// [loadWitnessData]) purely for a future Witness-facing surface; the
  /// silent detection itself now happens server-side (see the
  /// check_ins_grace_nudge trigger in supabase/migrations/init_schema.sql).
  final List<String> graceNudgeLog;

  /// Rule items this account (as a Runner) has an outstanding Witness-
  /// unlock request pending for — drives the "Pending Witness Approval"
  /// button state in the Rule Builder. See [requestRuleItemUnlock] and
  /// supabase/migrations/003_accountability_unlocks.sql.
  final Set<String> pendingUnlockRuleItemIds;

  /// Incoming DNA Rhythm unlock requests awaiting this account's
  /// decision (as a Witness) — populated by [loadWitnessData] and kept
  /// live via Realtime. See [respondToUnlockRequest].
  final List<PendingUnlockRequest> incomingUnlockRequests;

  /// This Runner's real 180-day season — the score behind the Trellis, the
  /// Insights cards, and every per-rhythm figure on the dashboard. Computed
  /// by the database (see [refreshAnalytics]); empty until the first load.
  RunnerAnalytics analytics = const RunnerAnalytics.empty();

  /// True once [analytics] holds a real answer from the server.
  bool analyticsLoaded = false;

  /// The last [refreshAnalytics] failed and nothing has loaded yet — lets the
  /// dashboard say so instead of passing off an empty trellis as a verdict.
  bool analyticsFailed = false;
  int _analyticsRequest = 0;

  /// The Cloud's live "Needs Attention" list (see [loadCloudData]).
  CloudTriage cloudTriage = const CloudTriage.empty();

  /// Triage couldn't be loaded — distinct from "loaded, and nothing needs
  /// attention", which is good news and must not be confused with it.
  bool cloudTriageUnavailable = false;

  /// Prayer/meeting requests addressed to this account (as a Witness) that it
  /// hasn't acknowledged yet — populated by [loadWitnessData] and kept live by
  /// a Realtime subscription. See [acknowledgeSupportRequest].
  final List<SupportRequest> incomingSupportRequests = [];

  /// "kind:ruleItemId" for every request this account (as a Runner) sent in
  /// the last 24 hours — what lets an Insight card show "Requested" instead of
  /// inviting a second tap. See [requestSupport].
  final Set<String> _recentSupportKeys = {};
  bool _supportRequestsSubscribed = false;

  bool _runnerDataLoaded = false;

  /// Whether this account's own Runner-side lists (Witnesses, prayers,
  /// meetings) have loaded — until then an empty list is not yet a fact.
  bool get isRunnerDataLoaded => _runnerDataLoaded;
  bool _witnessDataLoaded = false;
  bool _cloudDataLoaded = false;
  bool _unlockRequestsSubscribed = false;

  /// The watched Runner currently selected on the Witness shell's Runners
  /// tab — drives the Rule of Life, Prayer, and Connect tabs there.
  WatchedRunner? get selectedWatchedRunner {
    final selectedId = selectedRunnerId;
    if (selectedId == null) return null;
    return _findWatchedRunner(selectedId);
  }

  /// Whether the "Burdens from my Witness(es)" prayer category is behind the
  /// membership. Every account has it in 1.0 — membership tiers don't gate
  /// prayer categories yet — so this is always false; the UI's locked state
  /// stays wired for when they do.
  bool get isWitnessRequestsLocked => false;

  WatchedRunner? _findWatchedRunner(String runnerId) {
    for (final runner in watchedRunners) {
      if (runner.id == runnerId) return runner;
    }
    return null;
  }

  WatchedPrayerItem? _findWatchedPrayerItem(WatchedRunner runner, String prayerId) {
    for (final item in [...runner.sharedPrayerRequests, ...runner.witnessPrayers]) {
      if (item.id == prayerId) return item;
    }
    return null;
  }

  String _witnessNameFor(String witnessId) {
    for (final witness in witnesses) {
      if (witness.id == witnessId) return witness.name;
    }
    return 'Witness';
  }

  /// One Realtime channel covers both directions this account might care
  /// about: new requests addressed to it (as a Witness) and status changes
  /// on requests it filed itself (as a Runner). Started lazily, at most
  /// once, from whichever of [loadRunnerData]/[loadWitnessData] runs first
  /// — mirrors the rest of this class's lazy-load-once convention rather
  /// than adding a separate per-screen subscribe/dispose lifecycle.
  void _ensureUnlockRequestsSubscribed() {
    if (_unlockRequestsSubscribed || isPreview) return;
    _unlockRequestsSubscribed = true;

    supabase
        .channel('public:pending_unlock_requests:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pending_unlock_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'witness_id',
            value: id,
          ),
          callback: (payload) => _handleIncomingUnlockRequestInsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pending_unlock_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'runner_id',
            value: id,
          ),
          callback: (payload) => _handleMyUnlockRequestUpdate(payload.newRecord),
        )
        .subscribe();
  }

  /// A new unlock request has been filed against this account (as a
  /// Witness). Realtime payloads carry only the raw row, so the Runner's
  /// name and the rhythm's title still need a follow-up fetch to display.
  Future<void> _handleIncomingUnlockRequestInsert(Map<String, dynamic> newRecord) async {
    final runnerId = newRecord['runner_id'] as String;
    final ruleItemId = newRecord['rule_item_id'] as String;

    final runnerRow = await supabase.from('profiles').select('name').eq('id', runnerId).single();
    final ruleItemRow =
        await supabase.from('rule_items').select('title').eq('id', ruleItemId).single();

    incomingUnlockRequests.add(PendingUnlockRequest(
      id: newRecord['id'] as String,
      runnerId: runnerId,
      witnessId: newRecord['witness_id'] as String,
      ruleItemId: ruleItemId,
      ruleItemTitle: ruleItemRow['title'] as String,
      runnerName: runnerRow['name'] as String,
      status: UnlockRequestStatus.pending,
      requestedAt: DateTime.parse(newRecord['requested_at'] as String),
    ));
    notifyListeners();
  }

  /// One of this account's own outgoing requests (as a Runner) was
  /// resolved by its Witness — clears the "Pending Witness Approval" state
  /// and, if approved, flips the rhythm's lock off locally so the Rule
  /// Builder doesn't need a manual reload to reflect it.
  void _handleMyUnlockRequestUpdate(Map<String, dynamic> newRecord) {
    final status = newRecord['status'] as String;
    if (status == 'pending') return;

    final ruleItemId = newRecord['rule_item_id'] as String;
    pendingUnlockRuleItemIds.remove(ruleItemId);

    if (status == 'approved') {
      for (final item in ruleItems) {
        if (item.id == ruleItemId) {
          item.isChurchMandated = false;
          // The approval opens the rhythm for a day (the database sets the
          // real deadline; this matches it closely enough for the screen).
          item.unlockedUntil = DateTime.now().add(ruleUnlockWindow);
          break;
        }
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Lazy loaders
  // ---------------------------------------------------------------------

  /// This account's own witnesses, prayer items, and meetings — still
  /// single-user-scoped, just not needed for the very first frame. Fires
  /// once from RunnerShell.initState().
  ///
  /// Loads once: a second call while the first is in flight shares it, and a
  /// call after success is a no-op. A FAILED load is not remembered as done —
  /// it rethrows (the shell shows its "couldn't load" plate) and the next call
  /// tries again, so Retry works without restarting the app.
  Future<void> loadRunnerData() {
    if (_runnerDataLoaded || isPreview) return Future<void>.value();
    return _runnerDataLoad ??= () async {
      try {
        await _fetchRunnerData();
        _runnerDataLoaded = true;
      } finally {
        _runnerDataLoad = null;
      }
    }();
  }

  Future<void>? _runnerDataLoad;

  Future<void> _fetchRunnerData() async {

    final witnessRows = await supabase
        .from('witness_pairings')
        .select('paired_since, witness:profiles!witness_id(id, name)')
        .eq('runner_id', id)
        .eq('status', 'active');
    witnesses
      ..clear()
      ..addAll([for (final row in witnessRows) Witness.fromRow(row)]);

    final prayerRows = await supabase.from('prayer_items').select().eq('runner_id', id);
    prayerItems
      ..clear()
      ..addAll([for (final row in prayerRows) PrayerItem.fromRow(row)]);

    final meetingRows = await supabase.from('meetings').select().eq('runner_id', id);
    meetingRequests
      ..clear()
      ..addAll([
        for (final row in meetingRows)
          MeetingRequest.fromRow(row, witnessName: _witnessNameFor(row['witness_id'] as String)),
      ]);

    final myPendingUnlockRows = await supabase
        .from('pending_unlock_requests')
        .select('rule_item_id')
        .eq('runner_id', id)
        .eq('status', 'pending');
    pendingUnlockRuleItemIds
      ..clear()
      ..addAll([for (final row in myPendingUnlockRows) row['rule_item_id'] as String]);

    // Which prayer/meeting requests this Runner already sent today. Fail-soft:
    // an older database without support_requests just shows every button live.
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(hours: 24));
      final sentRows = await supabase
          .from('support_requests')
          .select('kind, rule_item_id')
          .eq('runner_id', id)
          .gte('created_at', since.toIso8601String());
      _recentSupportKeys
        ..clear()
        ..addAll([
          for (final row in sentRows)
            _supportKey(
              supportRequestKindFromDb(row['kind'] as String),
              row['rule_item_id'] as String?,
            ),
        ]);
    } catch (error) {
      debugPrint('Could not load recent support requests: $error');
    }

    _ensureUnlockRequestsSubscribed();
    notifyListeners();
    await refreshAnalytics();
  }

  static String _supportKey(SupportRequestKind kind, String? ruleItemId) =>
      '${kind.dbValue}:${ruleItemId ?? ''}';

  /// Whether this Runner already asked for [kind] (about [ruleItemId]) in the
  /// last 24 hours — the Insight cards show "Requested" instead of a button.
  bool hasRequestedSupport(SupportRequestKind kind, {String? ruleItemId}) =>
      _recentSupportKeys.contains(_supportKey(kind, ruleItemId));

  /// Asks this Runner's active Witness(es) for prayer or a meeting — a real
  /// row per Witness (`create_support_request`), and a real push to each. The
  /// server refuses a repeat of the same ask within 24 hours rather than
  /// pinging a Witness twice.
  Future<SupportRequestOutcome> requestSupport(
    SupportRequestKind kind, {
    String? ruleItemId,
    String? note,
  }) async {
    _refuseInPreview();
    final int asked;
    try {
      asked = await supabase.rpc('create_support_request', params: {
        'p_kind': kind.dbValue,
        'p_rule_item_id': ruleItemId,
        'p_note': note,
      }) as int;
    } on PostgrestException catch (error) {
      if (error.message.contains('NO_WITNESS')) return SupportRequestOutcome.noWitness;
      rethrow;
    }

    _recentSupportKeys.add(_supportKey(kind, ruleItemId));
    notifyListeners();
    return asked > 0 ? SupportRequestOutcome.sent : SupportRequestOutcome.alreadyAsked;
  }

  /// Fetches this Runner's real season from `get_runner_analytics`. The score
  /// averages every rhythm over the last 180 days and counts a scheduled day
  /// with no check-in as a miss — all computed in the database so nothing on
  /// the client can drift from it. Never throws: on failure the previous
  /// numbers stay (or, if there are none yet, [analyticsFailed] is set).
  ///
  /// Called after anything that can change the answer — a check-in, or adding,
  /// removing, or rescheduling a rhythm. Overlapping calls are safe: only the
  /// newest request's result is kept.
  Future<void> refreshAnalytics() async {
    if (isPreview) return;
    final request = ++_analyticsRequest;
    try {
      final json = await supabase.rpc('get_runner_analytics') as Map<String, dynamic>;
      if (request != _analyticsRequest) return;
      analytics = RunnerAnalytics.fromJson(json);
      analyticsLoaded = true;
      analyticsFailed = false;
    } catch (error) {
      debugPrint('get_runner_analytics failed: $error');
      if (request != _analyticsRequest) return;
      if (!analyticsLoaded) analyticsFailed = true;
    }
    notifyListeners();
  }

  /// Builds [watchedRunners] from every active Runner<->Witness pairing
  /// where this account is the witness — the one genuinely expensive,
  /// multi-user fan-out load. Fires once from WitnessShell.initState().
  ///
  /// Same once-only, retry-after-failure contract as [loadRunnerData].
  Future<void> loadWitnessData() {
    if (_witnessDataLoaded || isPreview) return Future<void>.value();
    return _witnessDataLoad ??= () async {
      // Departure notes (028) ride along with every Witness load, on their
      // own and fail-soft: they never hold up or fail the Runners list.
      unawaited(refreshWitnessNotices());
      try {
        await _fetchWitnessData();
        _witnessDataLoaded = true;
      } finally {
        _witnessDataLoad = null;
      }
    }();
  }

  Future<void>? _witnessDataLoad;

  Future<void> _fetchWitnessData() async {

    final pairingRows = await supabase
        .from('witness_pairings')
        .select(
          'runner:profiles!runner_id(id, name, phone_number, has_committed_rule, '
          'accountability_lock_enabled, accountability_lock_removal_pending)',
        )
        .eq('witness_id', id)
        .eq('status', 'active');

    // When each Runner committed their Rule of Life. Asked for separately and
    // fail-soft: the column arrives with migration 021, and without it the
    // Runners must still load (a committed Runner is then simply treated as
    // having committed long ago, as before).
    final committedAtByRunner = <String, DateTime>{};
    try {
      final runnerIds = [
        for (final pairing in pairingRows) (pairing['runner'] as Map<String, dynamic>)['id'] as String,
      ];
      if (runnerIds.isNotEmpty) {
        final rows = await supabase
            .from('profiles')
            .select('id, rule_committed_at')
            .inFilter('id', runnerIds);
        for (final row in rows) {
          final value = row['rule_committed_at'];
          final parsed = value is String ? DateTime.tryParse(value) : null;
          if (parsed != null) committedAtByRunner[row['id'] as String] = parsed.toUtc();
        }
      }
    } catch (error) {
      debugPrint('rule_committed_at unavailable: ${error.runtimeType}');
    }

    final built = <WatchedRunner>[];
    for (final pairing in pairingRows) {
      final runnerRow = pairing['runner'] as Map<String, dynamic>;
      final runnerId = runnerRow['id'] as String;
      final hasCommittedRule = runnerRow['has_committed_rule'] as bool? ?? false;
      final committedAt = committedAtByRunner[runnerId];

      final ruleItemRows = await supabase.from('rule_items').select().eq('runner_id', runnerId);

      // Fetched window is wider than the 7 days actually displayed — up to
      // 3 extra days of slack either direction so the real window can't
      // fall outside what got fetched no matter how far the Witness's
      // device clock/timezone differs from the Runner's, since the display
      // window itself is anchored below to the Runner's own latest
      // reported day, not to DateTime.now() on whichever device is asking.
      final fetchSince = DateTime.now().toUtc().subtract(const Duration(days: 9));
      final checkInRows = await supabase
          .from('check_ins')
          .select()
          .eq('runner_id', runnerId)
          .gte('check_in_date', _dateOnly(fetchSince));

      // "Today" from the Runner's own perspective is whatever day they
      // most recently reported on — immune to the Witness's local clock,
      // which has no bearing on which calendar day the Runner meant. Falls
      // back to UTC-now only for a Runner with zero check-ins yet, where
      // there's no Runner-reported day to anchor to regardless.
      DateTime? referenceDate;
      for (final row in checkInRows) {
        final date = DateTime.parse(row['check_in_date'] as String);
        if (referenceDate == null || date.isAfter(referenceDate)) referenceDate = date;
      }
      referenceDate ??= DateTime.now().toUtc();

      final watchedRuleItems = <WatchedRuleItem>[];
      for (final ruleRow in ruleItemRows) {
        final ruleItem = RuleItem.fromRow(ruleRow);
        final byDate = {
          for (final c in checkInRows)
            if (c['rule_item_id'] == ruleItem.id)
              c['check_in_date'] as String: c['answered_yes'] as bool,
        };
        // A dense, always-7-element array (referenceDate-6 .. referenceDate).
        // A day with no obligation is `null` — neither a hit nor a miss:
        // the rhythm wasn't scheduled that day (e.g. a Wed/Fri-only fast on
        // a Tuesday), or it didn't count yet (see [missedDayCounts]). A day
        // the Runner actually answered always shows as answered. Only a day
        // that WAS due, counted, and has no check-in reads as "not done"
        // (false) — see WatchedRuleItem.weekCompletion.
        final weekCompletion = <bool?>[
          for (var i = 6; i >= 0; i--)
            _watchedDayStatus(
              ruleItem,
              referenceDate.subtract(Duration(days: i)),
              answered: byDate[_dateOnly(referenceDate.subtract(Duration(days: i)))],
              hasCommittedRule: hasCommittedRule,
              committedAt: committedAt,
            ),
        ];
        final scheduledDays = weekCompletion.whereType<bool>().toList();
        watchedRuleItems.add(WatchedRuleItem(
          id: ruleItem.id,
          title: ruleItem.displayTitle,
          completionRate: scheduledDays.isEmpty
              ? 0
              : scheduledDays.where((done) => done).length / scheduledDays.length,
          frequency: ruleItem.frequency,
          isAnchorRhythm: ruleItem.isAnchorRhythm,
          isChurchMandated: ruleItem.isChurchMandated,
          weekCompletion: weekCompletion,
        ));
      }

      final sharedRows = await supabase
          .from('prayer_items')
          .select()
          .eq('runner_id', runnerId)
          .eq('share_with_witnesses', true);
      final sharedPrayers = [for (final row in sharedRows) _watchedPrayerFromRow(row)];

      final myPrayerRows = await supabase
          .from('witness_prayers')
          .select()
          .eq('witness_id', id)
          .eq('runner_id', runnerId);
      final myPrayers = [for (final row in myPrayerRows) _watchedPrayerFromRow(row)];

      final meetingRows = await supabase
          .from('meetings')
          .select()
          .eq('witness_id', id)
          .eq('runner_id', runnerId);
      final pending = <WatchedMeetingRequest>[];
      final confirmed = <WatchedMeetingRequest>[];
      for (final row in meetingRows) {
        final time = DateTime.parse(row['scheduled_time'] as String);
        final status = meetingStatusFromDb(row['status'] as String);
        final watchedMeeting = WatchedMeetingRequest(
          id: row['id'] as String,
          timeLabel: '${formatMeetingDate(time)} at ${formatMeetingTime(time)}',
          location: row['location'] as String,
          isEmergency: row['is_emergency'] as bool? ?? false,
          status: status,
          activity: row['activity'] as String?,
          time: time,
        );
        if (status == MeetingStatus.pendingResponse) {
          pending.add(watchedMeeting);
        } else if (status == MeetingStatus.confirmed) {
          confirmed.add(watchedMeeting);
        }
      }

      final checkInDates = [
        for (final c in checkInRows) DateTime.parse(c['check_in_date'] as String),
      ];
      DateTime? lastCheckIn;
      for (final date in checkInDates) {
        if (lastCheckIn == null || date.isAfter(lastCheckIn)) lastCheckIn = date;
      }

      // The Runner's season exactly as they see it themselves. A failure
      // leaves the season fields empty, and WatchedRunner falls back to the
      // trailing week rather than hiding the Runner.
      RunnerAnalytics? season;
      try {
        final json = await supabase
            .rpc('get_runner_analytics', params: {'p_runner_id': runnerId}) as Map<String, dynamic>;
        season = RunnerAnalytics.fromJson(json);
      } catch (error) {
        debugPrint('get_runner_analytics($runnerId) failed: $error');
      }

      built.add(WatchedRunner(
        id: runnerId,
        name: runnerRow['name'] as String,
        phoneNumber: runnerRow['phone_number'] as String?,
        hasCommittedRule: hasCommittedRule,
        ruleCommittedAt: committedAt?.toLocal(),
        // A request only means something while the lock is actually on.
        lockRemovalRequested: (runnerRow['accountability_lock_enabled'] as bool? ?? false) &&
            (runnerRow['accountability_lock_removal_pending'] as bool? ?? false),
        seasonScore: season?.score,
        hasSeasonData: season?.hasData ?? false,
        isSeasonDrooping: season?.isDrooping ?? false,
        ruleItems: watchedRuleItems,
        sharedPrayerRequests: sharedPrayers,
        witnessPrayers: myPrayers,
        pendingMeetings: pending,
        confirmedMeetings: confirmed,
        lastCheckInDate: lastCheckIn,
        referenceDate: referenceDate,
      ));
    }

    watchedRunners
      ..clear()
      ..addAll(built);
    // A selected Runner whose pairing has since ended (or whose account was
    // deleted) is no longer in the list — fall back to the first one.
    final previouslySelected = selectedRunnerId;
    if (previouslySelected != null && _findWatchedRunner(previouslySelected) == null) {
      selectedRunnerId = null;
    }
    selectedRunnerId ??= watchedRunners.isEmpty ? null : watchedRunners.first.id;

    final graceRows = await supabase
        .from('grace_nudges')
        .select('message')
        .inFilter('runner_id', [for (final r in built) r.id]);
    graceNudgeLog
      ..clear()
      ..addAll([for (final row in graceRows) row['message'] as String]);

    final incomingUnlockRows = await supabase
        .from('pending_unlock_requests')
        .select('*, runner:profiles!runner_id(name), rule_item:rule_items!rule_item_id(title)')
        .eq('witness_id', id)
        .eq('status', 'pending');
    incomingUnlockRequests
      ..clear()
      ..addAll([for (final row in incomingUnlockRows) PendingUnlockRequest.fromRow(row)]);

    // Prayer/meeting requests waiting on this Witness. Fail-soft, like the
    // Runner side: a database that predates support_requests just shows none.
    try {
      final requestRows = await supabase
          .from('support_requests')
          .select('*, runner:profiles!runner_id(name), rule_item:rule_items!rule_item_id(title)')
          .eq('witness_id', id)
          .eq('status', 'open')
          .order('created_at', ascending: false);
      incomingSupportRequests
        ..clear()
        ..addAll([for (final row in requestRows) SupportRequest.fromRow(row)]);
      _ensureSupportRequestsSubscribed();
    } catch (error) {
      debugPrint('Could not load support requests: $error');
    }

    _ensureUnlockRequestsSubscribed();
    notifyListeners();
  }

  /// Whether an unanswered, scheduled [day] counts as a miss for a Witness.
  ///
  /// Nothing counts until the Runner has committed their Rule of Life — a
  /// draft is not a promise — and then only from the day AFTER they committed,
  /// and never before the rhythm itself existed. (Dates are compared as UTC
  /// calendar days, the same way the database does it in migration 021.)
  /// [committedAt] null with [hasCommittedRule] true means "committed, date
  /// not recorded" (an older database): everything counts, as it used to.
  ///
  /// Nor does a day count while the Runner can still report on it: the daily
  /// check-in looks back on YESTERDAY, so yesterday stays open all of today.
  /// Until today is over, an unanswered yesterday is "not reported yet", not
  /// a miss — otherwise every Runner would look like they had missed their
  /// Anchor each morning until they opened the app.
  @visibleForTesting
  static bool missedDayCounts(
    DateTime day, {
    required bool hasCommittedRule,
    required DateTime? committedAt,
    required DateTime? rhythmCreatedAt,
    DateTime? now,
  }) {
    if (!hasCommittedRule) return false;
    final date = DateTime.utc(day.year, day.month, day.day);
    final today = now ?? DateTime.now();
    final yesterday = DateTime.utc(today.year, today.month, today.day - 1);
    if (!date.isBefore(yesterday)) return false;
    if (committedAt != null) {
      final committed = committedAt.toUtc();
      final firstCountedDay = DateTime.utc(committed.year, committed.month, committed.day + 1);
      if (date.isBefore(firstCountedDay)) return false;
    }
    if (rhythmCreatedAt != null) {
      final created = rhythmCreatedAt.toUtc();
      if (date.isBefore(DateTime.utc(created.year, created.month, created.day))) return false;
    }
    return true;
  }

  /// One cell of a watched rhythm's week: null = nothing was due, true/false =
  /// kept / missed. See [missedDayCounts].
  static bool? _watchedDayStatus(
    RuleItem item,
    DateTime day, {
    required bool? answered,
    required bool hasCommittedRule,
    required DateTime? committedAt,
  }) {
    if (!item.scheduledFor(day)) return null;
    if (answered != null) return answered;
    return missedDayCounts(
      day,
      hasCommittedRule: hasCommittedRule,
      committedAt: committedAt,
      rhythmCreatedAt: item.createdAt,
    )
        ? false
        : null;
  }

  /// A separate Realtime channel from the unlock-request one, so a database
  /// that hasn't published `support_requests` yet can't take the unlock
  /// channel down with it.
  void _ensureSupportRequestsSubscribed() {
    if (_supportRequestsSubscribed || isPreview) return;
    _supportRequestsSubscribed = true;

    supabase
        .channel('public:support_requests:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'witness_id',
            value: id,
          ),
          callback: (payload) => _handleIncomingSupportRequestInsert(payload.newRecord),
        )
        .subscribe();
  }

  /// Realtime carries only the raw row, so the Runner's name and the rhythm's
  /// title need a follow-up fetch to display.
  Future<void> _handleIncomingSupportRequestInsert(Map<String, dynamic> newRecord) async {
    try {
      final row = await supabase
          .from('support_requests')
          .select('*, runner:profiles!runner_id(name), rule_item:rule_items!rule_item_id(title)')
          .eq('id', newRecord['id'] as String)
          .single();
      if (incomingSupportRequests.any((r) => r.id == row['id'])) return;
      incomingSupportRequests.insert(0, SupportRequest.fromRow(row));
      notifyListeners();
    } catch (error) {
      debugPrint('Could not load incoming support request: $error');
    }
  }

  /// Marks a Runner's prayer/meeting request as seen by this Witness. Only the
  /// addressed Witness can do this, once (support_requests' RLS + guard).
  Future<void> acknowledgeSupportRequest(SupportRequest request) async {
    _refuseInPreview();
    await supabase
        .from('support_requests')
        .update({'status': 'acknowledged'})
        .eq('id', request.id);
    incomingSupportRequests.removeWhere((r) => r.id == request.id);
    notifyListeners();
  }

  /// Congregational Health, the Roster, DNA Rhythms, and Treasury data —
  /// only ever meaningful once [cloudAdminChurchId] is set. Fires once from
  /// CloudShell.initState().
  ///
  /// A brand-new church has no Runners, no codes, and maybe no DNA Rhythms —
  /// that is NOT an error, and nothing here treats it as one: an empty result
  /// simply leaves a list empty (the screens show a themed "No data yet"). Each
  /// piece loads independently, so one unexpected failure can't blank — or
  /// falsely error — the whole shell. What did fail is named in
  /// [cloudLoadIssues] (with a short reason in [cloudLoadDetail]); only when
  /// EVERYTHING fails (offline, signed out) does this throw, which is what the
  /// shell's Retry plate is for.
  Future<void> loadCloudData() async {
    final targetChurchId = cloudAdminChurchId;
    if (targetChurchId == null || _cloudDataLoaded || isPreview) return;

    final issues = <String>[];
    String? firstDetail;

    Future<void> section(String name, Future<void> Function() load) async {
      try {
        await load();
      } catch (error) {
        debugPrint('loadCloudData: "$name" failed: $error');
        issues.add(name);
        firstDetail ??= '$name — ${_briefError(error)}';
      }
    }

    await section('church details', () async {
      final row =
          await supabase.from('churches').select().eq('id', targetChurchId).maybeSingle();
      if (row == null) return; // Nothing to show yet — not a failure.
      churchName = row['name'] as String? ?? churchName;
      licenseCap = (row['license_cap'] as num?)?.toInt() ?? 0;
      ratePerRunner = (row['rate_per_runner'] as num?)?.toDouble() ?? ratePerRunner;
      final renewal = row['annual_renewal_date'] as String?;
      annualRenewalDate = renewal == null ? null : DateTime.tryParse(renewal);
    });

    await section('license usage', () async {
      final usageRow = await supabase
          .from('church_license_usage')
          .select()
          .eq('church_id', targetChurchId)
          .maybeSingle();
      activeLicenseCount = (usageRow?['active_license_count'] as num?)?.toInt() ?? 0;
    });

    await section('roster', () async {
      final rosterRows =
          await supabase.from('church_roster').select().eq('church_id', targetChurchId);
      churchRoster
        ..clear()
        ..addAll([for (final row in rosterRows) ChurchRosterEntry.fromRow(row)]);
    });

    await section('DNA Rhythms', () async {
      final dnaRows = await supabase.from('dna_rhythms').select().eq('church_id', targetChurchId);
      dnaRhythms
        ..clear()
        ..addAll([for (final row in dnaRows) DnaRhythm.fromRow(row)]);
      // An empty table says nothing either way; keep the previous answer.
      if (dnaRows.isNotEmpty) {
        _dnaSeasonsSupported = dnaRows.any((row) => row.containsKey('ends_on'));
      }
    });

    await section('church codes', () async {
      final codeRows =
          await supabase.from('church_codes').select().eq('church_id', targetChurchId);
      churchCodes
        ..clear()
        ..addAll([for (final row in codeRows) ChurchCode.fromRow(row)]);
    });

    await section('congregational health', () async {
      final health = await supabase.rpc(
        'get_congregational_health',
        params: {'p_church_id': targetChurchId},
      ) as Map<String, dynamic>;
      isCongregationalHealthLocked = health['is_locked'] as bool? ?? true;
      trackedRunnerCount = (health['tracked_runner_count'] as num?)?.toInt() ?? 0;
      churchRhythmMetrics
        ..clear()
        ..addAll([
          for (final metric in (health['metrics'] as List<dynamic>? ?? const []))
            ChurchRhythmMetric.fromJson(metric as Map<String, dynamic>),
        ]);
    });

    // Fail-soft on its own: the rest of the Cloud shell works without triage,
    // and the Insights screen says so rather than showing an all-clear it
    // hasn't earned.
    await _loadCloudTriage(targetChurchId);

    cloudLoadIssues = issues;
    cloudLoadDetail = firstDetail;
    // Only a fully clean load is "done" — otherwise the next entry into the
    // Cloud shell retries what failed.
    _cloudDataLoaded = issues.isEmpty;
    notifyListeners();

    // All six pieces failed: that's a connection or sign-in problem, not an
    // empty church. Say so (the shell turns this into its Retry plate).
    if (issues.length >= 6) {
      throw StateError(firstDetail ?? 'The church data could not be loaded.');
    }
  }

  /// Which parts of the last Cloud load failed (empty when it was clean, or
  /// when the church is simply empty). See [loadCloudData].
  List<String> cloudLoadIssues = const [];

  /// A short technical reason for the first failure, for the Cloud shell to
  /// show beneath its notice so a problem can be reported precisely.
  String? cloudLoadDetail;

  static String _briefError(Object error) {
    final text = error is PostgrestException
        ? '${error.message}${error.code == null ? '' : ' (${error.code})'}'
        : error.toString();
    return text.length > 160 ? '${text.substring(0, 157)}…' : text;
  }

  /// Fetches the Cloud's "Needs Attention" list from `get_cloud_triage`,
  /// which flags Runners by the strict 180-day season score (unanswered
  /// scheduled days count as misses). Never throws; sets
  /// [cloudTriageUnavailable] on failure.
  Future<void> _loadCloudTriage(String churchId) async {
    try {
      final triage = await supabase
          .rpc('get_cloud_triage', params: {'p_church_id': churchId}) as Map<String, dynamic>;
      cloudTriage = CloudTriage.fromJson(triage);
      cloudTriageUnavailable = false;
    } catch (error) {
      debugPrint('get_cloud_triage failed: $error');
      cloudTriageUnavailable = true;
    }
  }

  /// Re-fetches just the triage list (the Insights screen's "Try Again").
  Future<void> refreshCloudTriage() async {
    if (isPreview) return;
    final churchId = cloudAdminChurchId;
    if (churchId == null) return;
    await _loadCloudTriage(churchId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------

  /// The tail of the role-write queue — see [setRole].
  Future<void> _pendingRoleWrite = Future<void>.value();

  /// Only accepts Runner/Witness — Cloud is reached via
  /// [redeemCloudAccessCode], never a role value. Updates optimistically,
  /// then persists in the background through the `set_my_role` RPC (clients
  /// can't write `profiles.role` directly — migration 011); the UI never
  /// needs to wait on this one.
  ///
  /// Writes are queued so a quick Runner -> Witness -> Runner toggle lands in
  /// the order it happened. A failed write is logged, not surfaced: the role
  /// is only which view the Runner last had open, so the worst case is the
  /// next sign-in opening the other view.
  void setRole(UserRole newRole) {
    assert(
      newRole != UserRole.cloud,
      'Cloud is reached via redeemCloudAccessCode, not setRole.',
    );
    if (role == newRole) return;
    role = newRole;
    notifyListeners();
    _pendingRoleWrite = _pendingRoleWrite.then((_) => _persistRole(newRole));
  }

  Future<void> _persistRole(UserRole newRole) async {
    if (isPreview) return;
    try {
      await supabase.rpc('set_my_role', params: {'p_role': newRole.dbValue});
    } catch (error) {
      debugPrint('set_my_role failed: $error');
    }
  }

  /// Asks Supabase Auth to change this account's sign-in address to [value].
  /// Auth emails a confirmation link; the address (here and on the profile
  /// row, which the database mirrors from auth.users — migration 019) changes
  /// only once that link is followed. So nothing is updated locally: the
  /// account keeps its current address until the change is confirmed, and the
  /// next sign-in picks the new one up. Throws [AuthException] with a
  /// displayable message if Auth refuses (invalid address, already in use,
  /// rate limited).
  Future<void> requestEmailChange(String value) async {
    _refuseInPreview();
    await supabase.auth.updateUser(UserAttributes(email: value.trim()));
  }

  /// Changes this account's password after proving [currentPassword] is right
  /// (by signing in again with it — which is how Supabase re-authenticates;
  /// it refreshes this same session rather than starting another).
  ///
  /// Throws [AuthException]: a wrong current password surfaces as an
  /// "invalid login credentials" error from the first step, before anything
  /// is changed.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _refuseInPreview();
    await supabase.auth.signInWithPassword(email: email, password: currentPassword);
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Turns the accountability lock ON. (Turning it off is a request a Witness
  /// answers — see [requestAccountabilityLockRemoval].) The screen changes only
  /// once the database has accepted it.
  Future<void> setAccountabilityLock(bool enabled) async {
    _refuseInPreview();
    await supabase
        .from('profiles')
        .update({'accountability_lock_enabled': enabled})
        .eq('id', id);
    accountabilityLockEnabled = enabled;
    if (!enabled) accountabilityLockRemovalPending = false;
    notifyListeners();
  }

  /// Asks to turn the accountability lock off, and returns true if it is now
  /// OFF, false if the request is waiting on a Witness.
  ///
  /// With at least one active Witness the lock stays on until one of them
  /// approves (the database refuses a direct change — migration 011); the
  /// request shows on each Witness's dashboard, where [resolveLockRemoval]
  /// answers it. With NO active Witness there is nobody who could approve, so
  /// the database lets the Runner release it themselves (migration 019) —
  /// otherwise a lock set before pairing could never be removed.
  Future<bool> requestAccountabilityLockRemoval() async {
    _refuseInPreview();
    if (witnesses.isEmpty) {
      await setAccountabilityLock(false);
      return true;
    }

    await supabase
        .from('profiles')
        .update({'accountability_lock_removal_pending': true})
        .eq('id', id);
    accountabilityLockRemovalPending = true;
    notifyListeners();
    return false;
  }

  /// A Witness's answer to a watched Runner's request to turn their
  /// accountability lock off (`resolve_accountability_lock_removal`,
  /// migration 019): approving lifts the lock; declining clears the request
  /// and leaves the lock on. Only an active Witness of that Runner can call it.
  Future<void> resolveLockRemoval(String runnerId, {required bool approve}) async {
    _refuseInPreview();
    await supabase.rpc(
      'resolve_accountability_lock_removal',
      params: {'p_runner_id': runnerId, 'p_approve': approve},
    );
    _findWatchedRunner(runnerId)?.lockRemovalRequested = false;
    notifyListeners();
  }

  Future<void> toggleNotification(NotificationCategory category, bool value) async {
    _refuseInPreview();
    notificationPreferences[category] = value;
    notifyListeners();
    final updated = {for (final entry in notificationPreferences.entries) entry.key.dbKey: entry.value};
    await supabase.from('profiles').update({'notification_preferences': updated}).eq('id', id);
  }

  /// Sends the Runner to the App Store / Google Play subscription page, the
  /// only place a store subscription can actually be cancelled.
  ///
  /// Deliberately changes nothing locally and writes nothing to the
  /// database: `membership_status` is owned by the revenuecat-webhook Edge
  /// Function (clients can no longer write it — see
  /// supabase/migrations/011_security_lockdown.sql). Turning off auto-renew
  /// leaves access in place until the paid period ends, at which point
  /// RevenueCat sends EXPIRATION, the webhook marks the account 'cancelled',
  /// and the next [loadCurrent] picks that up. Marking it cancelled here
  /// would be wrong for the whole period still paid for.
  Future<MembershipCancellationOutcome> cancelMembership() async {
    _refuseInPreview();
    final managementUrl = await PurchasesService.managementUrl();
    if (managementUrl == null) return MembershipCancellationOutcome.notStoreBilled;

    final opened = await launchUrl(
      Uri.parse(managementUrl),
      mode: LaunchMode.externalApplication,
    );
    return opened
        ? MembershipCancellationOutcome.openedStoreSettings
        : MembershipCancellationOutcome.couldNotOpenStoreSettings;
  }

  /// Redeems an enterprise Church Code — grants active membership without
  /// going through RevenueCat/Apple IAP, for a church that already paid
  /// for a block of memberships out-of-band. See
  /// supabase/migrations/005_enterprise_church_codes.sql.
  Future<bool> redeemEnterpriseChurchCode(String code) async {
    _refuseInPreview();
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;

    final success = await supabase.rpc(
      'redeem_enterprise_church_code',
      params: {'p_code': trimmed},
    ) as bool;
    if (!success) return false;

    membershipStatus = MembershipStatus.active;
    notifyListeners();
    await refreshMembership();
    return true;
  }

  /// Reflects a RevenueCat purchase result immediately after checkout, so
  /// the paywall doesn't look stale waiting on revenuecat-webhook — which
  /// remains the authoritative writer (see supabase/functions/
  /// revenuecat-webhook/) and will reconcile this shortly after regardless.
  void applyLocalMembershipStatus(MembershipStatus status) {
    membershipStatus = status;
    // A purchase just went through: lift the membership gate for this run of
    // the app even if the webhook hasn't reached the server yet.
    if (status == MembershipStatus.active) _membershipUnlockedLocally = true;
    notifyListeners();
  }

  Future<void> removeWitness(String witnessId, {required String reason}) async {
    _refuseInPreview();
    await supabase
        .from('witness_pairings')
        .update({'status': 'removed'})
        .eq('runner_id', id)
        .eq('witness_id', witnessId);
    witnesses.removeWhere((witness) => witness.id == witnessId);
    notifyListeners();
  }

  Future<String> generatePairingCode() async {
    _refuseInPreview();
    final code = await supabase.rpc('generate_pairing_code') as String;
    pairingCode = code;
    notifyListeners();
    return code;
  }

  Future<String> addRuleItem({
    required RuleCategory category,
    required String title,
    RuleFrequency frequency = RuleFrequency.daily,
    Set<int>? weeklyDays,
    bool isAnchorRhythm = false,
    bool isThrowOff = false,
  }) async {
    _refuseInPreview();
    // "No…", "Abstain from…" and the like are sins to throw off.
    final sorted = sortRhythm(title, isThrowOff: isThrowOff);
    title = sorted.title;
    isThrowOff = sorted.isThrowOff;
    final row = await supabase
        .from('rule_items')
        .insert({
          'runner_id': id,
          'category': category.dbValue,
          'title': title,
          // A sin to throw off is a daily resolve, always.
          'frequency': (isThrowOff ? RuleFrequency.daily : frequency).dbValue,
          'weekly_days': isThrowOff ? const <int>[] : (weeklyDays ?? <int>{}).toList(),
          'is_anchor_rhythm': isAnchorRhythm,
          'is_church_mandated': false,
          // Only sent when true (see RuleItem.toInsertRow).
          if (isThrowOff) 'is_throw_off': true,
        })
        .select()
        .single();
    final saved = RuleItem.fromRow(row);
    ruleItems.add(saved);
    notifyListeners();
    unawaited(refreshAnalytics());
    return saved.id;
  }

  Future<void> applyRuleOfLifeBaseline(List<BaselineRuleItem> items) async {
    _refuseInPreview();
    final rows = await supabase
        .from('rule_items')
        .insert([
          for (final item in items)
            {
              'runner_id': id,
              'category': item.category.dbValue,
              'title': item.title,
              'frequency': item.frequency.dbValue,
              'weekly_days': item.weeklyDays.toList(),
              'is_anchor_rhythm': item.isAnchorRhythm,
              'is_church_mandated': false,
              // Only sent when true (see RuleItem.toInsertRow).
              if (item.isThrowOff) 'is_throw_off': true,
            },
        ])
        .select();
    ruleItems.addAll([for (final row in rows) RuleItem.fromRow(row)]);
    notifyListeners();
    unawaited(refreshAnalytics());
  }

  Future<void> updateRuleItem(String id, void Function(RuleItem item) update) async {
    _refuseInPreview();
    RuleItem? item;
    for (final candidate in ruleItems) {
      if (candidate.id == id) {
        item = candidate;
        break;
      }
    }
    if (item == null) return;
    // A DNA Rhythm is read-only until a Witness approves an unlock — the
    // database enforces this too (guard_rule_item_update in migration 011),
    // so don't pretend to edit one locally.
    if (item.isChurchMandated) return;

    final before = (
      title: item.title,
      frequency: item.frequency,
      weeklyDays: {...item.weeklyDays},
      isAnchorRhythm: item.isAnchorRhythm,
    );
    update(item);
    notifyListeners();
    try {
      await supabase.from('rule_items').update({
        'title': item.title,
        'frequency': item.frequency.dbValue,
        'weekly_days': item.weeklyDays.toList(),
        'is_anchor_rhythm': item.isAnchorRhythm,
      }).eq('id', id);
      // A new schedule changes which days count — and a rhythm's score.
      unawaited(refreshAnalytics());
    } catch (_) {
      // The write was refused or never arrived — put the screen back so it
      // doesn't show a change the database doesn't have.
      item
        ..title = before.title
        ..frequency = before.frequency
        ..weeklyDays = before.weeklyDays
        ..isAnchorRhythm = before.isAnchorRhythm;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeRuleItem(String id) async {
    _refuseInPreview();
    await supabase.from('rule_items').delete().eq('id', id);
    ruleItems.removeWhere((item) => item.id == id);
    notifyListeners();
    unawaited(refreshAnalytics());
  }

  /// The church DNA Rhythm that [item] (one of the Runner's own rhythms)
  /// looks like a duplicate of — same category, and a title that matches or
  /// contains the other's — or null. A Runner who had "Sabbath" on their
  /// Rule of Life before their church added "Sabbath Rest" ends up tracking
  /// the same practice twice; this is what the Rule Builder's "Merge them"
  /// offer is built on.
  RuleItem? mergeCandidateFor(RuleItem item) {
    if (item.isChurchMandated) return null;
    String normalize(String title) =>
        title.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ');
    final own = normalize(item.title);
    if (own.length < 3) return null;
    for (final candidate in ruleItems) {
      if (!candidate.isChurchMandated || candidate.category != item.category) continue;
      final dna = normalize(candidate.title);
      if (dna.length < 3) continue;
      if (own == dna || own.contains(dna) || dna.contains(own)) return candidate;
    }
    return null;
  }

  /// Folds one of the Runner's own rhythms into the church DNA Rhythm it
  /// duplicates: its check-ins move onto the DNA Rhythm (on a day both were
  /// answered, the DNA Rhythm's answer stands) and the duplicate is removed
  /// — all server-side in one transaction (merge_rule_item_into_dna,
  /// migration 023). Returns how many check-ins moved. Throws if the
  /// database refuses (not the Runner's rows, wrong kind of pair).
  Future<int> mergeRuleItemIntoDna({required String ownItemId, required String dnaItemId}) async {
    _refuseInPreview();
    final moved = await supabase.rpc(
      'merge_rule_item_into_dna',
      params: {'p_own_item_id': ownItemId, 'p_dna_item_id': dnaItemId},
    );
    ruleItems.removeWhere((item) => item.id == ownItemId);
    notifyListeners();
    unawaited(refreshAnalytics());
    return moved is int ? moved : int.tryParse('$moved') ?? 0;
  }

  /// Asks [witnessId] for permission to unlock a rhythm — a church-mandated
  /// DNA Rhythm, or any rhythm that has become set ([isRuleItemSet]) — so it
  /// can be edited or removed. The caller (rule_builder_screen.dart) picks
  /// which of this account's Witnesses to ask; this only persists the request.
  Future<void> requestRuleItemUnlock(String ruleItemId, String witnessId) async {
    _refuseInPreview();
    final wasPending = pendingUnlockRuleItemIds.contains(ruleItemId);
    pendingUnlockRuleItemIds.add(ruleItemId);
    notifyListeners();

    try {
      await supabase.from('pending_unlock_requests').insert({
        'runner_id': id,
        'witness_id': witnessId,
        'rule_item_id': ruleItemId,
      });
    } catch (_) {
      // The request never reached the Witness — don't leave the rhythm showing
      // "Pending Witness Approval" for something that was never sent.
      if (!wasPending) pendingUnlockRuleItemIds.remove(ruleItemId);
      notifyListeners();
      rethrow;
    }
  }

  /// Approves or denies an incoming DNA Rhythm unlock request (as a
  /// Witness). Approving cascades server-side into clearing the rhythm's
  /// is_church_mandated flag (see the apply_unlock_request_approval
  /// trigger in supabase/migrations/003_accountability_unlocks.sql) — this
  /// only needs to keep the local watchedRunners mirror in sync so the
  /// Rule of Life tab reflects it without a reload.
  Future<void> respondToUnlockRequest(PendingUnlockRequest request, {required bool approve}) async {
    _refuseInPreview();
    await supabase
        .from('pending_unlock_requests')
        .update({'status': approve ? 'approved' : 'denied'})
        .eq('id', request.id);

    incomingUnlockRequests.removeWhere((r) => r.id == request.id);

    if (approve) {
      final watchedRunner = _findWatchedRunner(request.runnerId);
      if (watchedRunner != null) {
        final index =
            watchedRunner.ruleItems.indexWhere((item) => item.id == request.ruleItemId);
        if (index != -1) {
          final old = watchedRunner.ruleItems[index];
          watchedRunner.ruleItems[index] = WatchedRuleItem(
            id: old.id,
            title: old.title,
            completionRate: old.completionRate,
            frequency: old.frequency,
            isAnchorRhythm: old.isAnchorRhythm,
            isChurchMandated: false,
            weekCompletion: old.weekCompletion,
          );
        }
      }
    }

    notifyListeners();
  }

  Future<void> setDailyCheckInReminder(TimeOfDay time) async {
    _refuseInPreview();
    dailyCheckInReminder = time;
    notifyListeners();
    await supabase
        .from('profiles')
        .update({'daily_check_in_reminder': _timeToDb(time)})
        .eq('id', id);
  }

  Future<String> commitRuleOfLife() async {
    _refuseInPreview();
    final code = await generatePairingCode();
    hasCommittedRule = true;
    // The database stamps the real time (and is what enforces the settle
    // period); this keeps the screen right until it is read back just below.
    ruleCommittedAt ??= DateTime.now();
    notifyListeners();
    await supabase.from('profiles').update({'has_committed_rule': true}).eq('id', id);
    final optional = await _fetchOptionalProfileFields(id);
    if (optional.ruleCommittedAt != null) {
      ruleCommittedAt = optional.ruleCommittedAt;
      notifyListeners();
    }
    return code;
  }

  /// Saves this person's own mobile number. [number] must already be in
  /// international form (see normalizePhoneNumber in models/phone_number.dart).
  Future<void> setPhoneNumber(String number) async {
    _refuseInPreview();
    await supabase.from('profiles').update({'phone_number': number}).eq('id', id);
    phoneNumber = number;
    notifyListeners();
  }

  /// Whether [item] is "set": the first-week settle period has passed and a
  /// Witness must approve before it can be changed or removed. Mirrors the
  /// rule the database enforces (migration 021), so the screen never offers
  /// an edit the server would refuse. See [RuleItem.isSetAt].
  bool isRuleItemSet(RuleItem item) => hasCommittedRule &&
      item.isSetAt(
        DateTime.now(),
        ruleCommittedAt: ruleCommittedAt,
        hasWitness: witnesses.isNotEmpty,
      );

  /// When the open season-end window closes — a season (180 days) after
  /// committing, the Rule of Life opens for a week to be tweaked or left as
  /// it is — or null when no such window is open. See [isRuleSeasonReopenAt].
  DateTime? get ruleSeasonReopenEndsAt =>
      hasCommittedRule ? ruleSeasonReopenEndFor(DateTime.now(), ruleCommittedAt) : null;

  /// The last moment the whole Rule of Life can still be adjusted freely, or
  /// null once that has passed (or before committing).
  DateTime? get ruleSettlesAt {
    final committedAt = ruleCommittedAt;
    if (!hasCommittedRule || committedAt == null) return null;
    final settles = committedAt.add(ruleSettlePeriod);
    return settles.isAfter(DateTime.now()) ? settles : null;
  }

  /// Persists the Tier 1 MHMDA collection consent already given on
  /// auth_onboarding_screen.dart's Create Account checkbox — called from
  /// role_walkthrough_screen.dart's `_createAccount` right after the account
  /// is created, for every role (the checkbox itself already blocked
  /// getting this far without agreeing).
  Future<void> recordConsumerHealthDataConsent() async {
    _refuseInPreview();
    consumerHealthDataConsent = true;
    notifyListeners();
    await supabase
        .from('profiles')
        .update({'consumer_health_data_consent': true})
        .eq('id', id);
  }

  /// The check-in already given for [date]'s calendar day, or null.
  CheckInEntry? checkInFor(DateTime date) {
    for (final entry in checkInHistory) {
      if (entry.date.year == date.year &&
          entry.date.month == date.month &&
          entry.date.day == date.day) {
        return entry;
      }
    }
    return null;
  }

  /// Batch-inserts one day's worth of responses into `check_ins`. Grace
  /// Mechanics (three consecutive Anchor Rhythm misses) fire server-side
  /// automatically via the check_ins_grace_nudge trigger — no client-side
  /// port of the old _fireGraceNudge/_consecutiveAnchorMisses logic needed.
  ///
  /// A day's check-in is locked in once given: a plain insert, and the
  /// server refuses any change (supabase/migrations/031). Throws
  /// [CheckInAlreadyGivenException] if that day was already checked in
  /// (say from another phone).
  Future<void> recordCheckIn(DateTime date, Map<String, bool> responses) async {
    _refuseInPreview();
    if (checkInFor(date) != null) throw const CheckInAlreadyGivenException();
    final entry = CheckInEntry(date: date, responses: responses);
    try {
      await supabase.from('check_ins').insert(entry.toInsertRows(id));
    } on PostgrestException catch (error) {
      if (error.code == '23505') throw const CheckInAlreadyGivenException();
      rethrow;
    }
    checkInHistory.add(entry);
    notifyListeners();
    unawaited(refreshAnalytics());
  }

  Future<String> addPrayerItem({
    required PrayerCategory category,
    required String title,
    String details = '',
    String? phoneNumber,
    String? scripture,
    bool shareWithWitnesses = false,
  }) async {
    _refuseInPreview();
    final row = await supabase
        .from('prayer_items')
        .insert({
          'runner_id': id,
          'category': category.dbValue,
          'title': title,
          'details': details,
          'phone_number': phoneNumber,
          'scripture': scripture,
          'share_with_witnesses': shareWithWitnesses,
        })
        .select()
        .single();
    final saved = PrayerItem.fromRow(row);
    prayerItems.add(saved);
    notifyListeners();
    return saved.id;
  }

  Future<void> removePrayerItem(String id) async {
    _refuseInPreview();
    // Looked up before the row goes: once the prayer is deleted, nothing else
    // remembers where its photo was stored.
    String? photoPath;
    for (final item in prayerItems) {
      if (item.id == id) photoPath = item.photoPath;
    }
    await supabase.from('prayer_items').delete().eq('id', id);
    prayerItems.removeWhere((item) => item.id == id);
    notifyListeners();
    if (photoPath != null) unawaited(_deletePrayerPhoto(photoPath));
  }

  /// Records where a prayer's photo is stored (see PrayerPhotoService, which
  /// does the uploading) — or, with null, that it no longer has one.
  Future<void> setPrayerPhoto(String id, String? photoPath) async {
    _refuseInPreview();
    await supabase.from('prayer_items').update({'photo_path': photoPath}).eq('id', id);
    for (final item in prayerItems) {
      if (item.id == id) {
        item.photoPath = photoPath;
        break;
      }
    }
    notifyListeners();
  }

  /// Deletes a removed prayer's photo from the private bucket. Best-effort: a
  /// photo left behind is private and harmless, so a failed clean-up must
  /// never make removing the prayer itself look as if it failed.
  Future<void> _deletePrayerPhoto(String path) async {
    try {
      await supabase.storage.from(prayerPhotoBucket).remove([path]);
    } catch (error) {
      // The error's class only — its text can carry the path.
      debugPrint('Prayer photo clean-up failed: ${error.runtimeType}');
    }
  }

  Future<void> setPrayerAnswered(String id, bool answered) async {
    _refuseInPreview();
    final answeredDate = answered ? _dateOnly(DateTime.now()) : null;
    await supabase
        .from('prayer_items')
        .update({'is_answered': answered, 'answered_date': answeredDate})
        .eq('id', id);
    for (final item in prayerItems) {
      if (item.id == id) {
        item.isAnswered = answered;
        item.answeredDate = answered ? DateTime.now() : null;
        break;
      }
    }
    notifyListeners();
  }

  Future<void> markPrayedToday(String id) async {
    _refuseInPreview();
    final today = _dateOnly(DateTime.now());
    await supabase.from('prayer_items').update({'last_prayed_date': today}).eq('id', id);
    for (final item in prayerItems) {
      if (item.id == id) {
        item.lastPrayedDate = DateTime.now();
        break;
      }
    }
    notifyListeners();
  }

  Future<void> setPrayerReminderTime(TimeOfDay time) async {
    _refuseInPreview();
    prayerReminderTime = time;
    notifyListeners();
    await supabase
        .from('profiles')
        .update({'prayer_reminder_time': _timeToDb(time)})
        .eq('id', id);
  }

  Future<void> completeSchedulingSetup({
    required bool calendarConnected,
    String? homeAddress,
    String? workAddress,
  }) async {
    _refuseInPreview();
    this.calendarConnected = calendarConnected;
    this.homeAddress = homeAddress;
    this.workAddress = workAddress;
    hasCompletedSchedulingSetup = true;
    notifyListeners();
    await supabase.from('profiles').update({
      'calendar_connected': calendarConnected,
      'home_address': homeAddress,
      'work_address': workAddress,
      'has_completed_scheduling_setup': true,
    }).eq('id', id);
    // The midway meeting-spot suggestion: this phone geocodes its own
    // addresses (fail-soft, in the background).
    unawaited(MeetingSpotService.instance.syncMyCoordinates(home: homeAddress, work: workAddress));
  }

  /// Whether at least one meeting place (home or work) is on file.
  bool get hasMeetingPlaces =>
      (homeAddress?.trim().isNotEmpty ?? false) || (workAddress?.trim().isNotEmpty ?? false);

  /// Changes the home / work addresses on their own, any time after the
  /// first-run scheduling gate — which used to be the only place they could
  /// be entered, so skipping it meant never having them. Blank clears one.
  Future<void> updateMeetingPlaces({String? homeAddress, String? workAddress}) async {
    _refuseInPreview();
    String? clean(String? value) {
      final trimmed = value?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    }

    final previousHome = this.homeAddress;
    final previousWork = this.workAddress;
    this.homeAddress = clean(homeAddress);
    this.workAddress = clean(workAddress);
    notifyListeners();
    try {
      await supabase.from('profiles').update({
        'home_address': this.homeAddress,
        'work_address': this.workAddress,
      }).eq('id', id);
    } catch (_) {
      this.homeAddress = previousHome;
      this.workAddress = previousWork;
      notifyListeners();
      rethrow;
    }
    // The midway meeting-spot suggestion: this phone geocodes its own
    // addresses (fail-soft, in the background).
    unawaited(
      MeetingSpotService.instance.syncMyCoordinates(home: this.homeAddress, work: this.workAddress),
    );
  }

  Future<String> proposeMeeting({
    required String witnessId,
    required DateTime time,
    required String location,
    bool isEmergency = false,
  }) async {
    _refuseInPreview();
    final row = await supabase
        .from('meetings')
        .insert({
          'runner_id': id,
          'witness_id': witnessId,
          'scheduled_time': time.toIso8601String(),
          'location': location,
          'is_emergency': isEmergency,
          'status': MeetingStatus.pendingResponse.dbValue,
          'proposed_by': 'runner',
        })
        .select()
        .single();
    final saved = MeetingRequest.fromRow(row, witnessName: _witnessNameFor(witnessId));
    meetingRequests.add(saved);
    notifyListeners();
    return saved.id;
  }

  void selectWatchedRunner(String id) {
    selectedRunnerId = id;
    notifyListeners();
  }

  Future<WatchedMeetingRequest?> respondToWatchedMeeting(
    String runnerId,
    String meetingId, {
    required bool accept,
  }) async {
    _refuseInPreview();
    final newStatus = accept ? MeetingStatus.confirmed : MeetingStatus.declined;
    final row = await supabase
        .from('meetings')
        .update({'status': newStatus.dbValue})
        .eq('id', meetingId)
        .select()
        .single();

    final runner = _findWatchedRunner(runnerId);
    if (runner == null) return null;
    runner.pendingMeetings.removeWhere((meeting) => meeting.id == meetingId);

    final time = DateTime.parse(row['scheduled_time'] as String);
    final updated = WatchedMeetingRequest(
      id: row['id'] as String,
      timeLabel: '${formatMeetingDate(time)} at ${formatMeetingTime(time)}',
      location: row['location'] as String,
      isEmergency: row['is_emergency'] as bool? ?? false,
      status: newStatus,
      activity: row['activity'] as String?,
      time: time,
    );
    if (accept) runner.confirmedMeetings.add(updated);
    notifyListeners();
    return accept ? updated : null;
  }

  Future<void> rescheduleWatchedMeeting(String runnerId, String meetingId) async {
    _refuseInPreview();
    await supabase.from('meetings').delete().eq('id', meetingId);
    _findWatchedRunner(runnerId)?.pendingMeetings.removeWhere((m) => m.id == meetingId);
    notifyListeners();
  }

  /// Unlike [proposeMeeting] (a Runner proposing to their Witness, which
  /// waits on a response), a Witness proposing to their own Runner is
  /// confirmed immediately — the accountability relationship already
  /// trusts the Witness with scheduling authority here.
  Future<WatchedMeetingRequest?> proposeMeetingToWatchedRunner(
    String runnerId, {
    required String timeLabel,
    required String location,
    required String activity,
    DateTime? time,
  }) async {
    _refuseInPreview();
    final scheduledTime = time ?? DateTime.now().add(const Duration(days: 2));
    final row = await supabase
        .from('meetings')
        .insert({
          'runner_id': runnerId,
          'witness_id': id,
          'scheduled_time': scheduledTime.toIso8601String(),
          'location': location,
          'activity': activity,
          'status': MeetingStatus.confirmed.dbValue,
          'proposed_by': 'witness',
        })
        .select()
        .single();

    final watchedMeeting = WatchedMeetingRequest(
      id: row['id'] as String,
      timeLabel: timeLabel,
      location: location,
      status: MeetingStatus.confirmed,
      activity: activity,
      time: scheduledTime,
    );
    _findWatchedRunner(runnerId)?.confirmedMeetings.add(watchedMeeting);
    notifyListeners();
    return watchedMeeting;
  }

  Future<void> addWitnessPrayer(
    String runnerId, {
    required String title,
    String details = '',
  }) async {
    _refuseInPreview();
    final row = await supabase
        .from('witness_prayers')
        .insert({'witness_id': id, 'runner_id': runnerId, 'title': title, 'details': details})
        .select()
        .single();
    _findWatchedRunner(runnerId)?.witnessPrayers.add(_watchedPrayerFromRow(row));
    notifyListeners();
  }

  Future<void> removeWitnessPrayer(String runnerId, String prayerId) async {
    _refuseInPreview();
    await supabase.from('witness_prayers').delete().eq('id', prayerId);
    _findWatchedRunner(runnerId)?.witnessPrayers.removeWhere((item) => item.id == prayerId);
    notifyListeners();
  }

  /// A shared prayer item is owned by the Runner's own `prayer_items` row;
  /// a Witness's private intercession lives in `witness_prayers` instead —
  /// tries the private table first (it's this Witness's own row if it
  /// exists there at all), then falls back to the shared one.
  Future<void> setWatchedPrayerAnswered(String runnerId, String prayerId, bool answered) async {
    _refuseInPreview();
    final answeredDate = answered ? _dateOnly(DateTime.now()) : null;
    final witnessRows = await supabase
        .from('witness_prayers')
        .update({'is_answered': answered, 'answered_date': answeredDate})
        .eq('id', prayerId)
        .select();

    if (witnessRows.isEmpty) {
      await supabase
          .from('prayer_items')
          .update({'is_answered': answered, 'answered_date': answeredDate})
          .eq('id', prayerId);
    }

    final runner = _findWatchedRunner(runnerId);
    final item = runner == null ? null : _findWatchedPrayerItem(runner, prayerId);
    if (item != null) {
      item.isAnswered = answered;
      item.answeredDate = answered ? DateTime.now() : null;
    }
    notifyListeners();
  }

  Future<void> markWatchedPrayerPrayedToday(String runnerId, String prayerId) async {
    _refuseInPreview();
    final today = _dateOnly(DateTime.now());
    final witnessRows = await supabase
        .from('witness_prayers')
        .update({'last_prayed_date': today})
        .eq('id', prayerId)
        .select();

    if (witnessRows.isEmpty) {
      await supabase.from('prayer_items').update({'last_prayed_date': today}).eq('id', prayerId);
    }

    final runner = _findWatchedRunner(runnerId);
    final item = runner == null ? null : _findWatchedPrayerItem(runner, prayerId);
    item?.lastPrayedDate = DateTime.now();
    notifyListeners();
  }

  Future<String> generateChurchCode() async {
    _refuseInPreview();
    final targetChurchId = cloudAdminChurchId;
    if (targetChurchId == null) {
      throw StateError("Only a church's Cloud admin can generate a church code.");
    }
    // Minted server-side from a cryptographically secure source — clients can
    // no longer write church_codes at all (supabase/migrations/014).
    final row = await supabase.rpc(
      'generate_church_code',
      params: {'p_church_id': targetChurchId},
    ) as Map<String, dynamic>;
    final saved = ChurchCode.fromRow(row);
    churchCodes.add(saved);
    notifyListeners();
    return saved.code;
  }

  Future<void> revokeChurchCode(String code) async {
    _refuseInPreview();
    await supabase.from('church_codes').delete().eq('code', code);
    churchCodes.removeWhere((churchCode) => churchCode.code == code);
    notifyListeners();
  }

  /// Redeems a church-gifted code at sign-up: locks church affiliation and
  /// injects that church's DNA Rhythms into the new Runner's Rule of
  /// Life as real, church-mandated rhythms — all handled server-side by the
  /// redeem_church_code() RPC in one transaction. Returns false if the code
  /// wasn't recognized (or was already used) — sign-up still proceeds
  /// either way, since the field is optional.
  Future<bool> redeemChurchCode(String code) async {
    _refuseInPreview();
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;

    final success = await supabase.rpc('redeem_church_code', params: {'p_code': trimmed}) as bool;
    if (!success) return false;

    final profileRow = await _fetchProfileRow(id);
    churchName =(profileRow['church'] as Map<String, dynamic>?)?['name'] as String?;
    churchId = profileRow['church_id'] as String?;
    isChurchAffiliationLocked = profileRow['is_church_affiliation_locked'] as bool? ?? false;

    final ruleItemRows = await supabase.from('rule_items').select().eq('runner_id', id);
    ruleItems
      ..clear()
      ..addAll([for (final row in ruleItemRows) RuleItem.fromRow(row)]);

    notifyListeners();
    unawaited(refreshAnalytics());
    // A church member holds one of the church's seats (migration 029).
    unawaited(refreshMembership());
    return true;
  }

  /// Whether the database knows about DNA Rhythm seasons (migration 023's
  /// `ends_on`). Learned from the rows already loaded: the select is
  /// table-wide, so the key is present — null or dated — once the column
  /// exists. False (no seasons offered) while nothing is loaded.
  bool get dnaSeasonsSupported => _dnaSeasonsSupported;
  bool _dnaSeasonsSupported = false;

  Future<void> addDnaRhythm(DnaRhythm rhythm) async {
    _refuseInPreview();
    final targetChurchId = cloudAdminChurchId;
    if (targetChurchId == null) return;
    final row = await supabase
        .from('dna_rhythms')
        .insert(rhythm.toInsertRow(targetChurchId))
        .select()
        .single();
    dnaRhythms.add(DnaRhythm.fromRow(row));
    _dnaSeasonsSupported = row.containsKey('ends_on');
    notifyListeners();
  }

  Future<void> removeDnaRhythm(String title) async {
    _refuseInPreview();
    final targetChurchId = cloudAdminChurchId;
    if (targetChurchId == null) return;
    await supabase
        .from('dna_rhythms')
        .delete()
        .eq('church_id', targetChurchId)
        .eq('title', title);
    dnaRhythms.removeWhere((rhythm) => rhythm.title == title);
    notifyListeners();
  }

  /// Retires a DNA Rhythm for the whole church: nobody's copy is deleted —
  /// each member's becomes their own rhythm (no longer mandated, open for a
  /// week so they can keep or remove it), with its check-in history intact
  /// (retire_dna_rhythm, migration 023; a plain delete releases the copies
  /// the same way through a trigger, which is the path taken for a rhythm
  /// read without an id). Returns how many members' copies were released,
  /// or null when that isn't known.
  Future<int?> retireDnaRhythm(DnaRhythm rhythm) async {
    _refuseInPreview();
    final rhythmId = rhythm.id;
    if (rhythmId == null) {
      await removeDnaRhythm(rhythm.title);
      return null;
    }
    final released = await supabase.rpc('retire_dna_rhythm', params: {'p_dna_rhythm_id': rhythmId});
    dnaRhythms.removeWhere((candidate) => candidate.id == rhythmId);
    notifyListeners();
    return released is int ? released : int.tryParse('$released');
  }

  Future<void> updateDnaRhythm(String oldTitle, DnaRhythm updated) async {
    _refuseInPreview();
    final targetChurchId = cloudAdminChurchId;
    if (targetChurchId == null) return;
    // The database re-normalizes the days (a weekly rhythm always has at
    // least one) and carries the edit through to every Runner's mandated
    // copy (propagate_dna_rhythm_edit, migration 012) — so read the saved
    // row back rather than trusting what was typed.
    // The season (ends_on) is only written once the database has the column
    // (migration 023) — known from the rows read back carrying an id.
    final row = await supabase
        .from('dna_rhythms')
        .update(updated.toUpdateRow(includeSeason: updated.endsOn != null || dnaSeasonsSupported))
        .eq('church_id', targetChurchId)
        .eq('title', oldTitle)
        .select()
        .single();
    final index = dnaRhythms.indexWhere((rhythm) => rhythm.title == oldTitle);
    if (index != -1) dnaRhythms[index] = DnaRhythm.fromRow(row);
    notifyListeners();
  }

  /// Mints a new Cloud Access Code for this account's own church — only
  /// meaningful once this account is already that church's Cloud admin (so
  /// a pastor can hand codes out to staff); the very first code for a new
  /// church is provisioned out-of-band when it purchases a Cloud
  /// membership, same as church creation itself.
  Future<String> generateCloudAccessCode() async {
    _refuseInPreview();
    final targetChurchId = cloudAdminChurchId;
    if (targetChurchId == null) {
      throw StateError('You need Cloud access yourself before you can generate more codes.');
    }
    return await supabase.rpc(
      'generate_cloud_access_code',
      params: {'p_church_id': targetChurchId},
    ) as String;
  }

  Future<bool> redeemCloudAccessCode(String code) async {
    _refuseInPreview();
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;

    final success =
        await supabase.rpc('redeem_cloud_access_code', params: {'p_code': trimmed}) as bool;
    if (!success) return false;

    // The code is now spent and the grant is real, so everything below is
    // best-effort: a failure fetching the church's data must not read as
    // "invalid code" (the shell retries the load on entry).
    final profileRow =
        await supabase.from('profiles').select('cloud_admin_church_id').eq('id', id).single();
    cloudAdminChurchId = profileRow['cloud_admin_church_id'] as String?;
    _cloudDataLoaded = false;
    try {
      await loadCloudData();
    } catch (_) {
      _cloudDataLoaded = false;
    }
    notifyListeners();
    return true;
  }

  /// Read-only lookup of who a pairing code belongs to — specifically
  /// whether that Runner is affiliated with a church — without consuming
  /// the code. Lets witness_pairing_code_screen.dart show the mandatory
  /// data-sharing consent callout *before* [redeemPairingCode] actually
  /// finalizes anything.
  Future<PairingCodePreview> checkPairingCode(String code) async {
    _refuseInPreview();
    final trimmed = code.trim();
    if (trimmed.isEmpty) return const PairingCodePreview(isValid: false);

    final json = await supabase.rpc('check_pairing_code', params: {'p_code': trimmed})
        as Map<String, dynamic>;
    return PairingCodePreview.fromJson(json);
  }

  /// Redeems a Runner's pairing code (as a Witness) — the counterpart to
  /// [generatePairingCode], which a Runner calls from
  /// settings_witnesses.dart. On success, forces [loadWitnessData] to
  /// refetch so the newly paired Runner shows up immediately rather than
  /// waiting for the next cold boot.
  ///
  /// [consent] must be true when [checkPairingCode] reported
  /// [PairingCodePreview.requiresChurchConsent] — the server enforces this
  /// itself too (see supabase/migrations/007_witness_church_consent.sql),
  /// rejecting the redemption rather than trusting the client's claim.
  Future<bool> redeemPairingCode(String code, {bool consent = false}) async {
    _refuseInPreview();
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;

    final success = await supabase.rpc(
      'redeem_pairing_code',
      params: {'p_code': trimmed, 'p_consent': consent},
    ) as bool;
    if (!success) return false;

    _witnessDataLoaded = false;
    await loadWitnessData();
    return true;
  }

  Future<void> signOut() async {
    _refuseInPreview();
    // Best-effort, and deliberately BEFORE auth.signOut() — once the
    // session is invalidated this account no longer has a JWT to update
    // its own row with. A failure here (e.g. offline) shouldn't block
    // signing out locally; a stale token left behind just means this
    // device might receive one push meant for whoever signs in next on
    // it, not a real security issue, so it's not worth blocking on.
    try {
      await supabase.from('profiles').update({'fcm_token': null}).eq('id', id);
    } catch (_) {
      // Ignored — see above.
    }
    await supabase.auth.signOut();
    current = null;
    // This phone's reminders belong to the account that set them.
    unawaited(LocalReminders.cancelAll());
    PrayerPhotoService.instance.clear();
    // After this, events captured for whoever signs in next (or an
    // anonymous session) must never be attributed back to this account.
    unawaited(AnalyticsService.reset());
  }

  /// Notifies this account's Witness(es) that the account is being deleted,
  /// then permanently deletes it — server-side (see
  /// supabase/functions/delete-account/), since removing an `auth.users` row
  /// needs the service-role key, which never reaches this client. The
  /// notify-then-delete ordering happens inside that function, not here, so
  /// it can't be skipped by killing the app mid-flow.
  Future<void> deleteAccount() async {
    _refuseInPreview();
    final response = await supabase.functions.invoke('delete-account');
    if (response.status != 200) {
      throw Exception('Failed to delete account (HTTP ${response.status}).');
    }
    // The account is gone server-side; drop the now-dead local session too so
    // the next launch starts at Sign In instead of trying to restore it.
    try {
      await supabase.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Nothing to revoke — the user no longer exists.
    }
    current = null;
    unawaited(LocalReminders.cancelAll());
    PrayerPhotoService.instance.clear();
    unawaited(AnalyticsService.reset());
  }

  // ---------------------------------------------------------------------
  // Preview (sample data, offline)
  // ---------------------------------------------------------------------

  /// A fully populated profile that never touches the network: Sarah
  /// Mitchell, Cloud admin of Grace Community Church (300 licenses, 220
  /// Runners using The Trellis), who is also a Runner with a committed Rule
  /// of Life and a Witness to two Runners. Shown by "See Preview" on the
  /// Cloud Access Code dialog, so anyone can see what the Cloud does before
  /// they have a code. See [PreviewSampleData] for every figure.
  ///
  /// Every lazy load is already marked done, nothing subscribes to Realtime,
  /// and every method that would read or write Supabase either returns
  /// quietly (loads) or throws [PreviewModeException] (writes). Never set as
  /// [current].
  factory RunnerProfile.preview() {
    final now = DateTime.now();
    final roster = PreviewSampleData.roster();
    final ruleItems = PreviewSampleData.ruleItems(now);
    final history = PreviewSampleData.checkInHistory(ruleItems, now);
    final watched = PreviewSampleData.watchedRunners(now);

    final profile = RunnerProfile._(
      id: PreviewSampleData.userId,
      name: PreviewSampleData.userName,
      email: PreviewSampleData.userEmail,
      role: UserRole.runner,
      membershipStatus: MembershipStatus.active,
      churchName: PreviewSampleData.churchName,
      churchId: PreviewSampleData.churchId,
      isChurchAffiliationLocked: true,
      accountabilityLockEnabled: false,
      notificationPreferences: {
        for (final category in NotificationCategory.values) category: true,
      },
      witnesses: PreviewSampleData.witnesses(now),
      ruleItems: ruleItems,
      dailyCheckInReminder: const TimeOfDay(hour: 7, minute: 30),
      hasCommittedRule: true,
      ruleCommittedAt: PreviewSampleData.ruleCommittedAt(now),
      phoneNumber: PreviewSampleData.userPhone,
      consumerHealthDataConsent: true,
      checkInHistory: history,
      prayerReminderTime: const TimeOfDay(hour: 21, minute: 0),
      prayerItems: PreviewSampleData.prayerItems(now),
      hasCompletedSchedulingSetup: true,
      calendarConnected: false,
      homeAddress: '1200 Maple Avenue',
      meetingRequests: PreviewSampleData.meetingRequests(now),
      watchedRunners: watched,
      churchRoster: roster,
      cloudAdminChurchId: PreviewSampleData.churchId,
      activeLicenseCount: PreviewSampleData.rosterSize,
      licenseCap: PreviewSampleData.licenseCap,
      churchCodes: PreviewSampleData.churchCodes(now),
      dnaRhythms: PreviewSampleData.dnaRhythms(now),
      churchRhythmMetrics: [...PreviewSampleData.metrics],
      graceNudgeLog: [],
      pendingUnlockRuleItemIds: {},
      incomingUnlockRequests: [],
      isPreview: true,
    );

    return profile
      ..annualRenewalDate = PreviewSampleData.annualRenewalDate(now)
      ..isCongregationalHealthLocked = false
      ..trackedRunnerCount = PreviewSampleData.trackedRunnerCount(roster)
      ..cloudTriage = PreviewSampleData.triage(roster)
      ..cloudTriageUnavailable = false
      ..analytics = PreviewSampleData.analytics(ruleItems, history, now)
      ..analyticsLoaded = true
      ..selectedRunnerId = watched.first.id
      .._dnaSeasonsSupported = true
      .._runnerDataLoaded = true
      .._witnessDataLoaded = true
      .._cloudDataLoaded = true;
  }

  /// True only for [RunnerProfile.preview]: sample data with no account
  /// behind it. Screens check it to say "nothing here is saved" instead of
  /// attempting a write.
  final bool isPreview;

  /// Writes on a preview profile go nowhere — and must never reach the real
  /// signed-in session (many RPCs act on `auth.uid()`, not on [id]).
  void _refuseInPreview() {
    if (isPreview) throw const PreviewModeException();
  }

  // ---------------------------------------------------------------------
  // Membership gate (supabase/migrations/029_membership_gate.sql)
  // ---------------------------------------------------------------------

  /// What `my_membership()` last said. [MembershipGate.notEnforced] until it
  /// has been read, in a preview, and whenever it can't be read — the gate
  /// never closes on a failure.
  MembershipGate membershipGate = MembershipGate.notEnforced;

  /// Set once a store purchase/restore succeeds in this run of the app, so
  /// the gate lifts at once rather than waiting on the RevenueCat webhook.
  bool _membershipUnlockedLocally = false;

  /// Whether the Runner view must show the "two free weeks are over" page
  /// instead of the Runner's tabs. Only ever true for [UserRole.runner], and
  /// only once `app_settings.enforce_membership` is switched on at launch.
  /// The Witness and Cloud views never consult it.
  bool get needsMembership => !_membershipUnlockedLocally && membershipGate.gates(role);

  /// When the free trial ends (or ended); null if not known.
  DateTime? get trialEndsAt => membershipGate.trialEndsAt;

  /// The free trial is running and should be described as such. Always false
  /// while the launch switch is off.
  bool get isTrialPeriod => membershipGate.isTrialPeriodAt(DateTime.now());

  /// Re-reads `my_membership()`. Never throws: if the RPC is missing (029 not
  /// applied) or unreachable, the last answer stands — which, before any
  /// answer, is "not enforced".
  Future<void> refreshMembership() async {
    if (isPreview) return;
    try {
      membershipGate = MembershipGate.fromJson(await supabase.rpc('my_membership'));
    } catch (error) {
      debugPrint('my_membership unavailable: ${error.runtimeType}');
      return;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Departure notes for a Witness (supabase/migrations/028_departure_notices.sql)
  // ---------------------------------------------------------------------

  final List<WitnessNotice> _witnessNotices = [];

  /// Ids already handed to the screen (shown or being shown) this session, so
  /// a refetch that lands before `mark_witness_notice_seen` does can never
  /// bring the same note back a second time.
  final Set<String> _handledWitnessNoticeIds = {};

  /// Unseen notes for this account as a Witness — today only "a Runner you
  /// walked with deleted their account" — oldest first, in the order the
  /// Witness shell shows them. Always empty for a preview profile.
  List<WitnessNotice> get pendingWitnessNotices =>
      isPreview ? const [] : List.unmodifiable(_witnessNotices);

  /// Fetches this account's unseen notes (`get_my_witness_notices`). Called
  /// with every [loadWitnessData] and when a tapped `account_deleted` push
  /// opens the Witness shell. Never throws: a failure — including a database
  /// without migration 028 — leaves the list as it was.
  Future<void> refreshWitnessNotices() async {
    if (isPreview) return;
    try {
      final rows = await supabase.rpc('get_my_witness_notices') as List<dynamic>;
      final fresh = <WitnessNotice>[
        for (final row in rows)
          if (row is Map<String, dynamic>) ?WitnessNotice.fromRow(row),
      ]
        ..removeWhere((notice) => _handledWitnessNoticeIds.contains(notice.id))
        // The server sends newest first; show the oldest first.
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _witnessNotices
        ..clear()
        ..addAll(fresh);
      notifyListeners();
    } catch (error) {
      debugPrint('get_my_witness_notices unavailable: ${error.runtimeType}');
    }
  }

  /// Takes [notice] off [pendingWitnessNotices] for good this session, before
  /// it is shown — so it is shown once even if a rebuild or a second shell
  /// asks again while the dialog is up.
  void claimWitnessNotice(WitnessNotice notice) {
    _handledWitnessNoticeIds.add(notice.id);
    _witnessNotices.removeWhere((n) => n.id == notice.id);
  }

  /// The Witness has read [notice] (`mark_witness_notice_seen`). Best effort:
  /// if it fails the note is still gone for this session and will simply be
  /// shown again on a later launch. Nothing is sent for a preview profile.
  Future<void> markWitnessNoticeSeen(WitnessNotice notice) async {
    claimWitnessNotice(notice);
    if (isPreview) return;
    try {
      await supabase.rpc('mark_witness_notice_seen', params: {'p_id': notice.id});
    } catch (error) {
      debugPrint('mark_witness_notice_seen failed: ${error.runtimeType}');
    }
  }

  /// A Runner this account walks with has left (a tapped `account_deleted`
  /// push, carrying their id as [departedRunnerId]): their pairing is already
  /// gone, so they are dropped from [watchedRunners] (and the selection) at
  /// once, and the next [loadWitnessData] fetches the list afresh — which also
  /// fetches the departure note.
  void markWitnessDataStale({String? departedRunnerId}) {
    if (isPreview) return;
    _witnessDataLoaded = false;
    // A load already under way may have asked for notes before this one was
    // written; ask again rather than wait for the next launch.
    if (_witnessDataLoad != null) unawaited(refreshWitnessNotices());
    if (departedRunnerId != null) {
      watchedRunners.removeWhere((runner) => runner.id == departedRunnerId);
      if (selectedRunnerId == departedRunnerId) {
        selectedRunnerId = watchedRunners.isEmpty ? null : watchedRunners.first.id;
      }
      notifyListeners();
    }
  }

  /// Test hook: puts [notice] on a profile's pending list (a preview profile
  /// still never reports it — see [pendingWitnessNotices]).
  @visibleForTesting
  void debugAddWitnessNotice(WitnessNotice notice) => _witnessNotices.add(notice);
}

/// Thrown by a [RunnerProfile] write attempted on a preview profile
/// ([RunnerProfile.isPreview]). Screens normally check `isPreview` first and
/// show a notice; this is the backstop.
/// The day was already checked in; check-ins are locked in once given.
class CheckInAlreadyGivenException implements Exception {
  const CheckInAlreadyGivenException();
}

class PreviewModeException implements Exception {
  const PreviewModeException();

  static const message = 'This is a preview — nothing here is saved.';

  @override
  String toString() => 'PreviewModeException: $message';
}
