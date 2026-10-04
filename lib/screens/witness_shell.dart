import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/role_switcher_button.dart';
import '../widgets/shell_app_bar_actions.dart';
import '../widgets/role_switcher_sheet.dart';
import '../widgets/settings_drawer.dart';
import '../widgets/bottom_vine_frame.dart';
import '../widgets/corner_vine_background.dart';
import '../widgets/brass_glyph.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/nav_icon.dart';
import '../widgets/vine_safe_app_bar.dart';
import 'witness/witness_connect_screen.dart';
import 'witness/witness_dashboard.dart';
import 'witness/witness_pairing_code_screen.dart';
import 'witness/witness_prayer_screen.dart';
import 'witness/witness_rule_screen.dart';

/// Primary navigation shell for the Witness role: bottom tab bar, the same
/// hamburger settings drawer as the Runner shell, and a role-switcher chip.
///
/// The Runners tab picks which watched Runner's data populates the other
/// three tabs (Rule of Life, Prayer, Connect) via
/// [RunnerProfile.selectedRunnerId] — that's the "Runner Global State" this
/// shell reads from.
class WitnessShell extends StatefulWidget {
  const WitnessShell({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<WitnessShell> createState() => _WitnessShellState();
}

class _WitnessShellState extends State<WitnessShell> with ShellDataLoad<WitnessShell> {
  int _tabIndex = 0;

  RunnerProfile get _profile => widget.profile;

  static const _navItems = [
    BottomNavigationBarItem(
      icon: NavIcon(NavGlyph.dashboard, selected: false),
      activeIcon: NavIcon(NavGlyph.dashboard),
      label: 'Runners',
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
    // Tracked (not fired and forgotten): this is the slow, multi-Runner load,
    // and until it lands — or if it fails — the dashboard would otherwise say
    // "No Runners yet" to a Witness who has Runners.
    runShellLoad(_profile.loadWitnessData);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) {
        final selected = _profile.selectedWatchedRunner;
        final pages = [
          WitnessDashboardScreen(profile: _profile, isLoading: shellLoadPending),
          WitnessRuleScreen(
            profile: _profile,
            onNavigateToConnect: () => setState(() => _tabIndex = 3),
          ),
          WitnessPrayerScreen(profile: _profile),
          WitnessConnectScreen(profile: _profile),
        ];

        return Scaffold(
          appBar: VineSafeAppBar(
            child: AppBar(
              toolbarHeight: VineSafeAppBar.toolbarHeight,
              automaticallyImplyLeading: false,
              leading: const ShellMenuButton(),
              title: AppBarTitle(
                selected == null ? 'The Trellis' : 'Walking with ${selected.name}',
              ),
              actions: shellAppBarActions(
                context,
                actions: [
                  ShellAction(
                    glyph: BrassGlyphKind.personAdd,
                    label: 'Enter a pairing code',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => WitnessPairingCodeScreen(profile: _profile),
                      ),
                    ),
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
                            "Couldn't load your Runners, so the tabs look empty below. "
                            'Check your connection and try again.',
                        onRetry: () => runShellLoad(_profile.loadWitnessData),
                      )
                    else if (shellLoadingVisible)
                      const ShellLoadingLine(label: 'Loading your Runners…'),
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
