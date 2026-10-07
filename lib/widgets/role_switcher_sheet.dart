import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../screens/cloud_shell.dart';
import '../screens/runner_shell.dart';
import '../screens/witness_shell.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';
import 'cloud_access_code_dialog.dart';

/// The "Switch role" bottom sheet shared by all three shells' app bars.
///
/// Runner and Witness are a free, ungated two-way switch on the same
/// account. Cloud is different: it's always listed, but tapping it either
/// jumps straight into [CloudShell] (if this account already redeemed a
/// church's Cloud Access Code — see [RunnerProfile.cloudAdminChurchId]) or
/// opens a dialog to redeem one — never a plain role value to flip.
///
/// [inCloud] is true when opened from the Cloud shell itself. `profile.role`
/// only ever holds Runner or Witness (whichever view was open last), so from
/// inside Cloud it can't say where the user is: without this the sheet ticked
/// that last role as "current", and tapping it did nothing at all — there was
/// no direct way back out of Cloud to it.
Future<void> showRoleSwitcherSheet(
  BuildContext context,
  RunnerProfile profile, {
  bool inCloud = false,
}) {
  return showBookplateSheet<void>(
    context,
    builder: (sheetContext) {
      final textTheme = Theme.of(sheetContext).textTheme;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Switch role', style: textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: profile,
            builder: (_, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final role in [UserRole.runner, UserRole.witness])
                  BookplateRow(
                    leading: BrassGlyph(role.glyph, color: AppColors.forestGreen),
                    title: role.label,
                    trailing: !inCloud && role == profile.role
                        ? const BrassGlyph(
                            BrassGlyphKind.check,
                            color: AppColors.antiqueBrass,
                            semanticLabel: 'Current role',
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _switchToFreeRole(context, profile, role, leavingCloud: inCloud);
                    },
                  ),
                const BookplateDivider(height: 24),
                BookplateRow(
                  leading: BrassGlyph(UserRole.cloud.glyph, color: AppColors.forestGreen),
                  title: UserRole.cloud.label,
                  subtitle: profile.cloudAdminChurchId != null
                      ? UserRole.cloud.tagline
                      : "Enter your church's Cloud Access Code",
                  trailing: inCloud
                      ? const BrassGlyph(
                          BrassGlyphKind.check,
                          color: AppColors.antiqueBrass,
                          semanticLabel: 'Current role',
                        )
                      : BrassGlyph(
                          profile.cloudAdminChurchId != null
                              ? BrassGlyphKind.forward
                              : BrassGlyphKind.lock,
                          color: AppColors.antiqueBrass,
                        ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    // Already here.
                    if (inCloud) return;
                    if (profile.cloudAdminChurchId != null) {
                      // CloudShell retries (and reports) a failed load itself, so a
                      // hiccup here must not strand the user on this sheet.
                      try {
                        await profile.loadCloudData();
                      } catch (_) {}
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (context) => CloudShell(profile: profile)),
                        );
                      }
                    } else {
                      await _showCloudAccessCodeDialog(context, profile);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

void _switchToFreeRole(
  BuildContext context,
  RunnerProfile profile,
  UserRole role, {
  required bool leavingCloud,
}) {
  // Already in that view — unless this is the Cloud shell, where `profile.role`
  // is merely the view that was open before Cloud and tapping it must still
  // take the user there.
  if (role == profile.role && !leavingCloud) return;
  profile.setRole(role);
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (context) =>
          role == UserRole.runner ? RunnerShell(profile: profile) : WitnessShell(profile: profile),
    ),
  );
}

Future<void> _showCloudAccessCodeDialog(BuildContext context, RunnerProfile profile) async {
  // A preview has already been shown and exited by the time this returns, and
  // a cancel changes nothing: only a redeemed code moves on into the Cloud.
  final result = await showCloudAccessCodeDialog(context, profile);
  if (result != CloudAccessResult.unlocked || !context.mounted) return;

  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (context) => CloudShell(profile: profile)),
  );
}
