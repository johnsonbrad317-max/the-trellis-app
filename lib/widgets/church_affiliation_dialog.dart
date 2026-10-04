import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../screens/church_data_sharing_consent_screen.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';

/// The drawer's "Church Affiliation" dialog. A Runner joins a church by
/// entering the church-gifted code their church leadership generated; the
/// `redeem_church_code` RPC validates it against `church_codes`, looks up the
/// church, writes `profiles.church_id`, locks the affiliation, and copies the
/// church's DNA Rhythms into the Runner's Rule of Life — atomically,
/// server-side (a Runner has no read access to `church_codes`, by design).
///
/// Joining shares the Runner's rolled-up consistency with church leadership,
/// so the Tier 2 sharing consent screen must be accepted before any code is
/// redeemed. Resolves to true if the Runner joined a church.
Future<bool> showChurchAffiliationDialog(BuildContext context, RunnerProfile profile) async {
  final controller = TextEditingController();
  final locked = profile.isChurchAffiliationLocked;
  var isBusy = false;
  String? error;
  // Set by the actions builder so the text field's keyboard action (built in
  // the body) triggers the same routine as the Join Church button.
  VoidCallback? joinAction;

  try {
    final joined = await showBookplateForm<bool>(
      context,
      title: 'Church Affiliation',
      message: locked
          ? null
          : 'Joined through a church? Enter the code they gave you to connect to your '
              "church's rhythms.",
      barrierLabel: locked ? 'Close' : 'Cancel',
      bodyBuilder: (bodyContext, setState) {
        final textTheme = Theme.of(bodyContext).textTheme;

        if (locked) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                profile.churchName ?? 'Your church',
                style: textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Locked — you joined with a church-gifted code.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              enabled: !isBusy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Church-Gifted Code'),
              onSubmitted: (_) => joinAction?.call(),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta),
              ),
            ],
          ],
        );
      },
      actionsBuilder: (dialogContext, setState) {
        Future<void> join() async {
          final code = controller.text.trim();
          if (code.isEmpty) {
            setState(() => error = 'Enter the code your church gave you.');
            return;
          }
          if (isBusy) return;

          final consented = await Navigator.of(dialogContext).push<bool>(
            MaterialPageRoute(builder: (context) => const ChurchDataSharingConsentScreen()),
          );
          if (!dialogContext.mounted) return;
          if (consented != true) {
            setState(() {
              error = 'Joining a church shares your rhythm consistency with its leaders, so we '
                  'need your OK first. Nothing was shared.';
            });
            return;
          }

          setState(() {
            isBusy = true;
            error = null;
          });

          try {
            final success = await profile.redeemChurchCode(code);
            if (!dialogContext.mounted) return;
            if (success) {
              Navigator.of(dialogContext).pop(true);
              return;
            }
            setState(() {
              error = "That code wasn't recognized, or it has already been used. (A Cloud "
                  'Access Code goes in the role switcher instead.)';
            });
          } catch (_) {
            if (!dialogContext.mounted) return;
            setState(() => error = "Couldn't reach The Trellis to check that code. Try again.");
          } finally {
            if (dialogContext.mounted) setState(() => isBusy = false);
          }
        }

        joinAction = join;

        return [
          if (!locked)
            BookplateButton(
              label: 'Join Church',
              busy: isBusy,
              onPressed: isBusy ? null : join,
            ),
          BookplateButton(
            label: locked ? 'Close' : 'Cancel',
            variant: BookplateButtonVariant.secondary,
            onPressed: isBusy ? null : () => Navigator.of(dialogContext).pop(false),
          ),
        ];
      },
    );
    return joined ?? false;
  } finally {
    // The dialog's exit fade is still running when the future resolves, so
    // let it finish before releasing the controller.
    Future<void>.delayed(const Duration(milliseconds: 500), controller.dispose);
  }
}
