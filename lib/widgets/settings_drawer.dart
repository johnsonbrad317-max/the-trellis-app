import 'dart:async';

import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../screens/auth_onboarding_screen.dart';
import '../screens/runner/account_settings_screen.dart';
import '../screens/runner/settings_witnesses.dart';
import '../screens/welcome_walkthrough_screen.dart';
import '../services/calendar_service.dart';
import '../services/local_reminders.dart';
import '../theme/app_colors.dart';
import 'bookplate_chip.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';
import 'calendar_connect_sheet.dart';
import 'church_affiliation_dialog.dart';
import 'custom_toggle.dart';
import 'email_chooser_sheet.dart';
import 'launch_link.dart';

/// The "Calendars" row: opens the connect sheet, with a subtitle naming the
/// connected providers. Loads the connection list when the drawer opens.
class _CalendarsRow extends StatefulWidget {
  const _CalendarsRow({required this.padding});

  final EdgeInsets padding;

  @override
  State<_CalendarsRow> createState() => _CalendarsRowState();
}

class _CalendarsRowState extends State<_CalendarsRow> {
  @override
  void initState() {
    super.initState();
    // load() notifies listeners, so defer it past the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CalendarService.instance.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = CalendarService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => BookplateRow(
        padding: widget.padding,
        leading: const BrassGlyph(BrassGlyphKind.calendar),
        title: 'Calendars',
        subtitle: calendarConnectionsSummary(service),
        onTap: () => showCalendarConnectSheet(context),
      ),
    );
  }
}

/// The Runner's hamburger-menu drawer: account, membership, church
/// affiliation, notifications, support, and the sign-out / delete footer.
class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key, required this.profile, this.inCloud = false});

  final RunnerProfile profile;

  /// True when opened from the Cloud shell. `profile.role` only ever holds
  /// Runner or Witness (the view that was open before Cloud), so the drawer
  /// can't tell from it that it is showing a Church Admin their menu.
  final bool inCloud;

  /// The role this drawer is being shown for.
  UserRole get _viewRole => inCloud ? UserRole.cloud : profile.role;

  String _membershipLabel(MembershipStatus status) => switch (status) {
        MembershipStatus.trial => 'Trial',
        MembershipStatus.active => 'Active',
        MembershipStatus.cancelled => 'Cancelled',
      };

  static const _supportEmail = 'support@unhinderedlives.com';

  // Mail / Gmail / Outlook / copy — a bare mailto: opened only the phone's
  // default mail app, which did nothing for people who never set one up.
  Future<void> _contactSupport(BuildContext context) =>
      showEmailChooser(context, email: _supportEmail, subject: 'The Trellis App Support');

  Future<void> _openLegal(BuildContext context, String url) => openWebPage(context, url);

  Future<void> _editChurchAffiliation(BuildContext context) async {
    final joined = await showChurchAffiliationDialog(context, profile);
    if (!joined || !context.mounted) return;
    showBookplateNotice(context, "You've joined ${profile.churchName ?? 'your church'}.");
  }

  /// A line under a notification switch saying when it fires and where its
  /// time is set — or what it is, for the ones whose name doesn't say.
  String? _notificationHint(BuildContext context, NotificationCategory category) =>
      switch (category) {
        NotificationCategory.checkInReminder =>
          'Each day at ${profile.dailyCheckInReminder.format(context)}. Change the time on '
              'the Rule of Life screen.',
        NotificationCategory.prayerReminders =>
          'Each day at ${profile.prayerReminderTime.format(context)}. Change the time in '
              'the Prayer Garden.',
        NotificationCategory.weeklyRollUp =>
          'Once a week: how many rhythms each Runner you walk with kept.',
        NotificationCategory.anchorRhythmAlerts => null,
        NotificationCategory.meetingRequests => null,
      };

  Future<void> _editNotificationSettings(BuildContext context) async {
    final categories =
        NotificationCategory.values.where((c) => c.visibleForRole(_viewRole)).toList();

    await showBookplateForm<void>(
      context,
      title: 'Notification Settings',
      bodyBuilder: (dialogContext, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (categories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No notification settings for this role yet.',
                style: Theme.of(dialogContext).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final category in categories)
              ToggleRow(
                title: category.label,
                subtitle: _notificationHint(dialogContext, category),
                value: profile.notificationPreferences[category] ?? true,
                // The write is async, so it must NOT be the setState callback
                // itself (setState rejects a callback that returns a Future).
                // The preference flips locally at once; a failed save says so
                // and the toggle is put back.
                onChanged: (value) async {
                  final save = profile.toggleNotification(category, value);
                  setDialogState(() {});
                  // Switching one of this phone's own reminders on is the
                  // moment to make sure the phone will allow it.
                  if (value &&
                      (category == NotificationCategory.checkInReminder ||
                          category == NotificationCategory.prayerReminders)) {
                    unawaited(LocalReminders.requestPermission());
                  }
                  final saved = await runWithFailureNotice(
                    dialogContext,
                    () => save,
                    failure: "Couldn't save that setting. Check your connection.",
                  );
                  if (!saved) {
                    profile.notificationPreferences[category] = !value;
                    if (dialogContext.mounted) setDialogState(() {});
                  }
                },
              ),
        ],
      ),
      actionsBuilder: (dialogContext, setDialogState) => [
        BookplateButton(
          label: 'Done',
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
    );

    if (!confirmed || !context.mounted) return;

    try {
      await profile.signOut();
    } catch (_) {
      if (!context.mounted) return;
      showBookplateNotice(context, "Network error — couldn't sign out. Try again.");
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthOnboardingScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Delete Account & Data',
      message: 'This permanently deletes your account, Rule of Life, prayer list, and '
          'Witness connections. Your Witness will be notified. This cannot be undone.',
      confirmLabel: 'Delete Everything',
      destructive: true,
    );

    if (!confirmed || !context.mounted) return;

    // A non-dismissible "working" veil: just the brass spinner over the scrim.
    // PopScope keeps the system back button/gesture from closing it mid-delete
    // (the error path below pops exactly one route and expects it to be this).
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Deleting account',
      barrierColor: AppColors.forestGreen.withValues(alpha: 0.45),
      pageBuilder: (context, animation, secondaryAnimation) => const PopScope(
        canPop: false,
        child: Center(
          child: BookplateSpinner(
            size: 36,
            color: AppColors.parchmentLight,
            semanticLabel: 'Deleting your account',
          ),
        ),
      ),
    );

    try {
      await profile.deleteAccount();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthOnboardingScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showBookplateNotice(
        context,
        "Couldn't delete your account — check your connection and try again.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const rowPadding = EdgeInsets.symmetric(vertical: 12);
    const gutter = EdgeInsets.symmetric(horizontal: 20);

    Widget row(Widget child) => Padding(padding: gutter, child: child);

    return Drawer(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: profile,
          builder: (context, _) => ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                decoration: const BoxDecoration(
                  color: AppColors.parchmentLight,
                  border: Border(bottom: BorderSide(color: AppColors.vellumBorder)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.forestGreen,
                        border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
                      ),
                      // `characters`, not `[0]`: a name that opens with an emoji
                      // or accented letter must not be cut mid-character.
                      child: ExcludeSemantics(
                        child: Text(
                          profile.name.trim().isNotEmpty
                              ? profile.name.trim().characters.first.toUpperCase()
                              : '?',
                          style: textTheme.titleLarge?.copyWith(color: AppColors.parchmentLight),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(profile.name, style: textTheme.titleLarge),
                    const SizedBox(height: 4),
                    BookplateTag(label: _viewRole.shortLabel, color: AppColors.antiqueBrass),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              row(
                BookplateRow(
                  padding: rowPadding,
                  leading: const BrassGlyph(BrassGlyphKind.person),
                  title: 'Account & Membership',
                  subtitle: 'Email, password · ${_membershipLabel(profile.membershipStatus)}',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AccountSettingsScreen(profile: profile),
                      ),
                    );
                  },
                ),
              ),
              row(
                BookplateRow(
                  padding: rowPadding,
                  leading: const BrassGlyph(BrassGlyphKind.cross),
                  title: 'Church Affiliation',
                  subtitle:
                      (profile.churchName?.isNotEmpty ?? false) ? profile.churchName! : 'Not set',
                  onTap: () => _editChurchAffiliation(context),
                ),
              ),
              row(
                BookplateRow(
                  padding: rowPadding,
                  leading: const BrassGlyph(BrassGlyphKind.people),
                  title: 'My Witnesses',
                  subtitle: '${profile.witnesses.length} active',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => SettingsWitnessesScreen(profile: profile),
                      ),
                    );
                  },
                ),
              ),
              if (_viewRole != UserRole.cloud)
                row(const _CalendarsRow(padding: rowPadding)),
              row(
                BookplateRow(
                  padding: rowPadding,
                  leading: const BrassGlyph(BrassGlyphKind.bell),
                  title: 'Notification Settings',
                  onTap: () => _editNotificationSettings(context),
                ),
              ),
              row(
                BookplateRow(
                  padding: rowPadding,
                  leading: const BrassGlyph(BrassGlyphKind.leaf),
                  title: 'How The Trellis Works',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            WelcomeWalkthroughScreen(profile: profile, firstRun: false),
                      ),
                    );
                  },
                ),
              ),
              row(
                BookplateRow(
                  padding: rowPadding,
                  leading: const BrassGlyph(BrassGlyphKind.envelope),
                  title: 'Support',
                  onTap: () => _contactSupport(context),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: BookplateDivider(),
              ),
              row(
                BookplateRow(
                  padding: rowPadding,
                  title: 'Terms of Service',
                  onTap: () => _openLegal(context, 'https://unhinderedlives.com/terms'),
                ),
              ),
              row(
                BookplateRow(
                  padding: rowPadding,
                  title: 'Privacy Policy',
                  onTap: () => _openLegal(context, 'https://unhinderedlives.com/privacy'),
                ),
              ),
              row(
                BookplateRow(
                  padding: rowPadding,
                  title: 'Consumer Health Data Notice',
                  onTap: () =>
                      _openLegal(context, 'https://unhinderedlives.com/consumer-health-data'),
                ),
              ),
              row(
                BookplateRow(
                  padding: rowPadding,
                  leading: const BrassGlyph(BrassGlyphKind.logout),
                  title: 'Sign Out',
                  onTap: () => _confirmSignOut(context),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BookplateButton(
                  variant: BookplateButtonVariant.danger,
                  onPressed: () => _confirmDeleteAccount(context),
                  label: 'Delete Account & Data',
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
