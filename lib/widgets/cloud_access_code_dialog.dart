import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';

/// The "Enter Cloud Access Code" dialog (role switcher). Validation happens
/// server-side in the `redeem_cloud_access_code` RPC — `cloud_access_codes`
/// deliberately has no client-readable policy, so the app can't (and
/// shouldn't) look codes up itself. Resolves to true once redeemed.
///
/// Unlike a bare button handler this tracks a busy state (no double-submit
/// of a single-use code) and reports every failure inline instead of
/// letting an exception vanish.
Future<bool> showCloudAccessCodeDialog(BuildContext context, RunnerProfile profile) async {
  final controller = TextEditingController();
  var isBusy = false;
  String? error;
  // Set by the actions builder so the text field's keyboard action (built in
  // the body) triggers the same routine as the Unlock button.
  VoidCallback? submitAction;

  try {
    final redeemed = await showBookplateForm<bool>(
      context,
      title: 'Enter Cloud Access Code',
      barrierLabel: 'Cancel',
      bodyBuilder: (bodyContext, setState) {
        final textTheme = Theme.of(bodyContext).textTheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              Navigator.of(dialogContext).pop(true);
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
            label: 'Cancel',
            variant: BookplateButtonVariant.secondary,
            onPressed: isBusy ? null : () => Navigator.of(dialogContext).pop(false),
          ),
        ];
      },
    );
    return redeemed ?? false;
  } finally {
    // The dialog's exit fade is still running when the future resolves, so
    // let it finish before releasing the controller.
    Future<void>.delayed(const Duration(milliseconds: 500), controller.dispose);
  }
}
