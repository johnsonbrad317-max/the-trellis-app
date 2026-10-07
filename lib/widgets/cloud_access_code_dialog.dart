import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../screens/cloud_shell.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'launch_link.dart';

/// How the Cloud Access Code dialog ended.
enum CloudAccessResult {
  /// A code was redeemed: this account is now its church's Cloud admin, and
  /// the caller should open the real [CloudShell].
  unlocked,

  /// "See Preview": the sample-church preview was shown and has since been
  /// exited — the caller stays where it was.
  previewed,

  /// Cancelled (or dismissed): nothing happened.
  cancelled,
}

/// Opens the Cloud preview — Grace Community Church, sample data, nothing
/// saved (see [RunnerProfile.preview]) — and completes once it is exited.
Future<void> openCloudPreview(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => CloudShell(profile: RunnerProfile.preview(), preview: true),
    ),
  );
}

/// The "Enter Cloud Access Code" dialog (role switcher, welcome deck), with
/// three ways out: Unlock (redeem the code), See Preview (a sample church, so
/// anyone can see what the Cloud does before they have a code), and Cancel.
///
/// Validation happens server-side in the `redeem_cloud_access_code` RPC —
/// `cloud_access_codes` deliberately has no client-readable policy, so the
/// app can't (and shouldn't) look codes up itself.
///
/// Unlike a bare button handler this tracks a busy state (no double-submit
/// of a single-use code) and reports every failure inline instead of
/// letting an exception vanish.
///
/// For [CloudAccessResult.previewed] the dialog closes, the preview is pushed
/// on [context]'s navigator, and the future completes only after the preview
/// has been exited — so the caller is simply back where it started.
Future<CloudAccessResult> showCloudAccessCodeDialog(
  BuildContext context,
  RunnerProfile profile,
) async {
  final controller = TextEditingController();
  var isBusy = false;
  String? error;
  // Set by the actions builder so the text field's keyboard action (built in
  // the body) triggers the same routine as the Unlock button.
  VoidCallback? submitAction;

  final CloudAccessResult? result;
  try {
    result = await showBookplateForm<CloudAccessResult>(
      context,
      title: 'Enter Cloud Access Code',
      barrierLabel: 'Cancel',
      bodyBuilder: (bodyContext, setState) {
        final textTheme = Theme.of(bodyContext).textTheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              enabled: !isBusy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Cloud Access Code'),
              onSubmitted: (_) => submitAction?.call(),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta),
              ),
            ],
            const SizedBox(height: 12),
            // Where a code comes from, for the pastor who arrives without one
            // (the same words as the Cloud Access Code screen).
            Text(
              "Don't have a code? Church licenses are set up through Unhindered Lives.",
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            Center(
              child: BookplateButton(
                label: 'Learn how it works at unhinderedlives.com/trellis',
                variant: BookplateButtonVariant.link,
                compact: true,
                onPressed: () => openWebPage(bodyContext, churchLicenseUrl),
              ),
            ),
          ],
        );
      },
      actionsBuilder: (dialogContext, setState) {
        Future<void> submit() async {
          final code = controller.text.trim();
          if (code.isEmpty) {
            setState(() => error = 'Enter the code your church gave you.');
            return;
          }
          if (isBusy) return;

          setState(() {
            isBusy = true;
            error = null;
          });

          try {
            final success = await profile.redeemCloudAccessCode(code);
            if (!dialogContext.mounted) return;
            if (success) {
              Navigator.of(dialogContext).pop(CloudAccessResult.unlocked);
              return;
            }
            setState(() {
              error = "That code wasn't recognized, or it has already been used. Codes work "
                  'once — ask your church for a new one.';
            });
          } catch (_) {
            if (!dialogContext.mounted) return;
            setState(() {
              error = "Couldn't reach The Trellis to check that code. If it was accepted, sign "
                  'out and back in to find Cloud in the role switcher; otherwise try again.';
            });
          } finally {
            if (dialogContext.mounted) setState(() => isBusy = false);
          }
        }

        submitAction = submit;

        return [
          BookplateButton(
            label: 'Unlock',
            busy: isBusy,
            onPressed: isBusy ? null : submit,
          ),
          BookplateButton(
            label: 'See Preview',
            variant: BookplateButtonVariant.secondary,
            onPressed: isBusy
                ? null
                : () => Navigator.of(dialogContext).pop(CloudAccessResult.previewed),
          ),
          BookplateButton(
            label: 'Cancel',
            variant: BookplateButtonVariant.link,
            onPressed: isBusy
                ? null
                : () => Navigator.of(dialogContext).pop(CloudAccessResult.cancelled),
          ),
        ];
      },
    );
  } finally {
    // The dialog's exit fade is still running when the future resolves, so
    // let it finish before releasing the controller.
    disposeAfterBookplateClose([controller]);
  }

  if (result == CloudAccessResult.previewed) {
    if (context.mounted) await openCloudPreview(context);
    return CloudAccessResult.previewed;
  }
  return result ?? CloudAccessResult.cancelled;
}
