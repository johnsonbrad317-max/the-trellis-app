import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/brass_glyph.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/role_switcher_button.dart';
import '../widgets/shell_app_bar_actions.dart';
import '../widgets/role_switcher_sheet.dart';
import '../widgets/settings_drawer.dart';
import '../widgets/bottom_vine_frame.dart';
import '../widgets/corner_vine_background.dart';
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
  const RunnerShell({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<RunnerShell> createState() => _RunnerShellState();
}

class _RunnerShellState extends State<RunnerShell> with ShellDataLoad<RunnerShell> {
  int _tabIndex = 0;

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
    runShellLoad(_profile.loadRunnerData);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) {
        final pages = [
          DashboardTab(profile: _profile),
          RuleOfLifeTab(profile: _profile),
          PrayerTab(profile: _profile),
          ConnectTab(profile: _profile),
        ];

        return Scaffold(
          appBar: VineSafeAppBar(
            child: AppBar(
              toolbarHeight: VineSafeAppBar.toolbarHeight,
              automaticallyImplyLeading: false,
              leading: const ShellMenuButton(),
              title: const AppBarTitle('The Trellis'),
              actions: shellAppBarActions(
                context,
                actions: [
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
          ),
          extendBodyBehindAppBar: true,
          // The parchment gradient runs on behind the footer (see BottomVineFrame).
          extendBody: true,
          drawer: SettingsDrawer(profile: _profile),
          // The same forest-green veil as every bookplate dialog and sheet,
          // rather than Material's stock black scrim.
          drawerScrimColor: AppColors.forestGreen.withValues(alpha: 0.45),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            color: AppColors.parchmentLight,
            child: CornerVineBackground(
              bottomVines: false,
              // VineSafeArea (a SafeArea) — its bottom inset is what keeps every tab's content (and
              // the Prayer tab's round "add" button) above the bottom bar:
              // with extendBody the Scaffold reports the bar's height as
              // bottom padding, and this consumes it. Don't set bottom: false.
              child: VineSafeArea(
                child: Column(
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
                    Expanded(child: pages[_tabIndex]),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: BottomVineFrame(
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
