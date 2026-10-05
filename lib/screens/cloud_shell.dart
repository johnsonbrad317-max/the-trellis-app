import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/role_switcher_button.dart';
import '../widgets/shell_app_bar_actions.dart';
import '../widgets/role_switcher_sheet.dart';
import '../widgets/settings_drawer.dart';
import '../widgets/bottom_vine_frame.dart';
import '../widgets/vine_frame.dart';
import '../widgets/bookplate_dialog.dart';
import '../widgets/bookplate_plate.dart';
import '../widgets/brass_glyph.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/nav_icon.dart';
import '../widgets/vine_safe_app_bar.dart';
import 'cloud/church_profile_screen.dart';
import 'cloud/cloud_insights_screen.dart';
import 'cloud/cloud_roster_screen.dart';
import 'cloud/cloud_treasury_screen.dart';

/// Primary navigation shell for the Cloud (Church Admin) role: bottom tab
/// bar, the same hamburger settings drawer as the other shells, and a
/// role-switcher chip.
class CloudShell extends StatefulWidget {
  const CloudShell({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<CloudShell> createState() => _CloudShellState();
}

class _CloudShellState extends State<CloudShell>
    with ShellDataLoad<CloudShell> {
  int _tabIndex = 0;

  RunnerProfile get _profile => widget.profile;

  static const _navItems = [
    BottomNavigationBarItem(
      icon: NavIcon(NavGlyph.roster, selected: false),
      activeIcon: NavIcon(NavGlyph.roster),
      label: 'Roster',
    ),
    BottomNavigationBarItem(
      icon: NavIcon(NavGlyph.insights, selected: false),
      activeIcon: NavIcon(NavGlyph.insights),
      label: 'Insights',
    ),
    BottomNavigationBarItem(
      icon: NavIcon(NavGlyph.treasury, selected: false),
      activeIcon: NavIcon(NavGlyph.treasury),
      label: 'Treasury',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadCloud();
  }

  /// Loads (or, from a Retry, re-loads) the church's data. While it runs the
  /// shell says so — otherwise a church with Runners briefly reads "No data
  /// yet" on every tab.
  Future<void> _loadCloud() {
    if (shellLoadFailed && mounted) setState(() => shellLoadFailed = false);
    return runShellLoad(_profile.loadCloudData);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) {
        final pages = [
          CloudRosterScreen(profile: _profile),
          CloudInsightsScreen(profile: _profile),
          CloudTreasuryScreen(profile: _profile),
        ];

        return Scaffold(
          // The parchment gradient runs on behind the footer (see BottomVineFrame).
          extendBody: true,
          drawer: SettingsDrawer(profile: _profile, inCloud: true),
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
              title: AppBarTitle(_profile.churchName ?? 'Church Canopy'),
              actions: shellAppBarActions(
                context,
                actions: [
                  ShellAction(
                    glyph: BrassGlyphKind.gear,
                    label: 'Church Profile',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            ChurchProfileScreen(profile: _profile),
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
                  // profile.role only ever tracks Runner/Witness now — while
                  // actually inside the Cloud shell, show "Cloud" rather than
                  // whichever of those two was last active.
                  label: 'Cloud',
                  onPressed: () =>
                      showRoleSwitcherSheet(context, _profile, inCloud: true),
                ),
              ),
            ),
            child: Column(
              children: [
                // Still loading: say so, or every tab reads "No data yet".
                if (shellLoadingVisible)
                  const ShellLoadingLine(label: "Loading your church's data…")
                // Everything failed: a connection or sign-in problem —
                // a real error. (An EMPTY church is not one; the tabs
                // show their own "No data yet" panels for that.)
                else if (shellLoadFailed)
                  _LoadNotice(
                    accent: AppColors.terracotta,
                    message: "Couldn't load your church's data. Check your connection.",
                    detail: _profile.cloudLoadDetail,
                    onRetry: _loadCloud,
                  )
                // Some parts failed, the rest loaded: say which, quietly.
                else if (_profile.cloudLoadIssues.isNotEmpty)
                  _LoadNotice(
                    accent: AppColors.antiqueBrass,
                    message:
                        "Some of your church's data couldn't be loaded "
                        '(${_profile.cloudLoadIssues.join(', ')}).',
                    detail: _profile.cloudLoadDetail,
                    onRetry: _loadCloud,
                  ),
                Expanded(child: pages[_tabIndex]),
              ],
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

/// The inline notice above the Cloud tabs when loading went wrong: an accent
/// stripe (terracotta for a real failure, brass for a partial one), what
/// happened, a small technical reason so it can be reported precisely, and a
/// Retry.
class _LoadNotice extends StatelessWidget {
  const _LoadNotice({
    required this.accent,
    required this.message,
    required this.onRetry,
    this.detail,
  });

  final Color accent;
  final String message;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: BookplatePlate(
        padding: const EdgeInsets.all(12),
        accent: accent,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: textTheme.bodyMedium),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail!,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.forestGreen.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            BookplateButton(
              label: 'Retry',
              compact: true,
              variant: BookplateButtonVariant.secondary,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
