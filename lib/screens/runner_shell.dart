import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import 'runner/account_settings_screen.dart';
import 'runner/membership_gate_page.dart';
import 'witness_shell.dart';
import 'runner/rule_builder_screen.dart' show SeasonReopenPlate;
import '../services/reminder_sync.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_dialog.dart' show showBookplateConfirm;
import '../widgets/brass_glyph.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/role_switcher_button.dart';
import '../widgets/shell_app_bar_actions.dart';
import '../widgets/role_switcher_sheet.dart';
import '../widgets/settings_drawer.dart';
import '../widgets/bottom_vine_frame.dart';
import '../widgets/vine_frame.dart';
import '../widgets/nav_icon.dart';
import '../widgets/vine_safe_app_bar.dart';
import '../widgets/witness_code_dialog.dart';
import 'runner/tabs/connect_tab.dart';
import 'runner/tabs/dashboard_tab.dart';
import 'runner/tabs/prayer_tab.dart';
import 'runner/tabs/rule_of_life_tab.dart';

/// Primary navigation shell once a role has been chosen: bottom tab bar,
/// hamburger settings drawer, and a role-switcher chip in the app bar.
///
/// [profile] is shared across shells — switching roles via the chip keeps
/// the same underlying profile rather than resetting to a fresh mock, so
/// membership/Witnesses/Rule of Life/etc. all carry over.
class RunnerShell extends StatefulWidget {
  const RunnerShell({super.key, required this.profile, this.initialTab = RunnerTab.dashboard});

  final RunnerProfile profile;

  /// The tab shown first — the Dashboard, except when a tapped reminder opens
  /// the shell on the tab it is about (see NotificationRouter).
  final RunnerTab initialTab;

  @override
  State<RunnerShell> createState() => _RunnerShellState();
}

/// The Runner shell's bottom tabs, in bar order.
enum RunnerTab { dashboard, ruleOfLife, prayer, connect }

class _RunnerShellState extends State<RunnerShell>
    with ShellDataLoad<RunnerShell> {
  late int _tabIndex = widget.initialTab.index;

  RunnerProfile get _profile => widget.profile;

  static const _navItems = [
    BottomNavigationBarItem(
      icon: NavIcon(NavGlyph.dashboard, selected: false),
      activeIcon: NavIcon(NavGlyph.dashboard),
      label: 'Dashboard',
    ),
    BottomNavigationBarItem(
      icon: NavIcon(NavGlyph.rule, selected: false),
      activeIcon: NavIcon(NavGlyph.rule),
      label: 'Rule of Life',
    ),
    BottomNavigationBarItem(
      icon: NavIcon(NavGlyph.prayer, selected: false),
      activeIcon: NavIcon(NavGlyph.prayer),
      label: 'Prayer',
    ),
    BottomNavigationBarItem(
      icon: NavIcon(NavGlyph.connect, selected: false),
      activeIcon: NavIcon(NavGlyph.connect),
      label: 'Connect',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Tracked (not fired and forgotten): until this lands the Connect and
    // Prayer tabs have no Witnesses/prayers/meetings to show, and if it fails
    // they would otherwise sit on their "nothing here yet" panels as if that
    // were true.
    runShellLoad(_profile.loadRunnerData).then((_) => _announceSeasonReopen());
    // Keeps this phone's check-in and prayer reminders in step with the
    // Runner's settings and with what they have already done today.
    _reminders = ReminderSync(_profile)..start();
  }

  late final ReminderSync _reminders;

  /// Which season-end window the Runner has already been told about this
  /// run of the app (its closing moment) — so the notice comes once per
  /// arrival in a window, not on every tab change.
  static DateTime? _seasonReopenAnnounced;

  /// A season of the Rule of Life has ended: say so once, with the way to the
  /// Rule of Life screen, where the same words stay on a plate all week.
  Future<void> _announceSeasonReopen() async {
    if (!mounted || _profile.needsMembership) return;
    final endsAt = _profile.ruleSeasonReopenEndsAt;
    if (endsAt == null || _seasonReopenAnnounced == endsAt) return;
    _seasonReopenAnnounced = endsAt;
    final open = await showBookplateConfirm(
      context,
      title: 'A New Season',
      message: SeasonReopenPlate.message(endsAt),
      confirmLabel: 'Open my Rule of Life',
      cancelLabel: 'Leave it as it is',
    );
    if (open && mounted) setState(() => _tabIndex = RunnerTab.ruleOfLife.index);
  }

  @override
  void dispose() {
    _reminders.dispose();
    super.dispose();
  }

  /// "Witnessing is always free" on the membership gate: the same move as
  /// choosing Witness in the role switcher.
  void _switchToWitness() {
    _profile.setRole(UserRole.witness);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => WitnessShell(profile: _profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) {
        // Never true until memberships are switched on at launch (migration
        // 029), and only ever for this Runner view — the Witness and Cloud
        // shells have no gate.
        final gated = _profile.needsMembership;
        final pages = [
          DashboardTab(profile: _profile),
          RuleOfLifeTab(profile: _profile),
          PrayerTab(profile: _profile),
          ConnectTab(profile: _profile),
        ];

        return Scaffold(
          // The parchment gradient runs on behind the footer (see BottomVineFrame).
          extendBody: true,
          drawer: SettingsDrawer(profile: _profile),
          // The same forest-green veil as every bookplate dialog and sheet,
          // rather than Material's stock black scrim.
          drawerScrimColor: AppColors.forestGreen.withValues(alpha: 0.45),
          // VineFrame stops the page at the bottom bar (with extendBody the
          // Scaffold reports the bar's height as bottom padding, which the
          // frame consumes) and slides the header away while a tab is scrolled.
          body: VineFrame(
            bottomVines: false,
            headerResetToken: _tabIndex,
            header: AppBar(
              toolbarHeight: VineSafeAppBar.toolbarHeight,
              automaticallyImplyLeading: false,
              leading: const ShellMenuButton(),
              title: const AppBarTitle('The Trellis'),
              actions: shellAppBarActions(
                context,
                actions: [
                  if (!gated)
                    ShellAction(
                      glyph: BrassGlyphKind.personAdd,
                      label: 'Generate Witness Code',
                      onPressed: () => showWitnessCodeDialog(context, _profile),
                    ),
                  ShellAction(
                    glyph: BrassGlyphKind.leaf,
                    label: 'Send Feedback',
                    onPressed: () => showFeedbackDialog(context, _profile),
                  ),
                ],
                roleSwitcher: RoleSwitcherButton(
                  label: _profile.role.shortLabel,
                  onPressed: () => showRoleSwitcherSheet(context, _profile),
                ),
              ),
            ),
            child: gated
                ? MembershipGatePage(profile: _profile, onSwitchToWitness: _switchToWitness)
                : Column(
                    children: [
                      if (shellLoadFailed)
                        ShellLoadFailedPlate(
                          message:
                              "Couldn't load your Witnesses, prayers and meetings, so they "
                              'look empty below. Check your connection and try again.',
                          onRetry: () => runShellLoad(_profile.loadRunnerData),
                        )
                      else if (shellLoadingVisible)
                        const ShellLoadingLine(
                          label: 'Loading your Witnesses, prayers and meetings…',
                        ),
                      // Shown only once the profile is loaded and has no number.
                      if (_profile.phoneNumber == null && !shellLoadPending)
                        MissingPhonePlate(
                          onAdd: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => AccountSettingsScreen(profile: _profile),
                            ),
                          ),
                        ),
                      Expanded(child: pages[_tabIndex]),
                    ],
                  ),
          ),
          bottomNavigationBar: gated
              ? null
              : BottomVineFrame(
                  child: BottomNavigationBar(
                    backgroundColor: Colors.transparent,
                    currentIndex: _tabIndex,
                    onTap: (index) => setState(() => _tabIndex = index),
                    items: _navItems,
                  ),
                ),
        );
      },
    );
  }
}
