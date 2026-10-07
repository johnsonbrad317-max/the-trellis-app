import 'package:flutter/material.dart';

import '../models/membership_gate.dart';
import '../models/runner_profile.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';

/// "Enter a gift code": redeems a gift membership bought for this person on
/// unhinderedlives.com (`redeem_gift_code`, supabase/migrations/029). Reached
/// from Account & Membership ("Have a gift code?") at any time, and from the
/// "two free weeks are over" page. Resolves to true if a code was redeemed.
Future<bool> showGiftCodeDialog(BuildContext context, RunnerProfile profile) async {
  if (profile.isPreview) {
    showBookplateNotice(context, PreviewModeException.message);
    return false;
  }

  final controller = TextEditingController();
  var isBusy = false;
  String? error;
  // Set by the actions builder so the keyboard's Done key runs the same
  // routine as the Redeem button.
  VoidCallback? redeemAction;

  final redeemed = await showBookplateForm<bool>(
    context,
    title: 'Gift Code',
    message: 'Were you given The Trellis as a gift? Enter the code from your gift email.',
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
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Gift Code'),
            onSubmitted: (_) => redeemAction?.call(),
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
      Future<void> redeem() async {
        if (isBusy) return;
        if (normalizeGiftCode(controller.text).isEmpty) {
          setState(() => error = 'Enter the code from your gift email.');
          return;
        }
        setState(() {
          isBusy = true;
          error = null;
        });
        try {
          final result = await profile.redeemGiftCode(controller.text);
          if (!dialogContext.mounted) return;
          if (result.ok) {
            // Said from the dialog's own context: the screen that opened it
            // may already be gone (the "free weeks are over" page lifts the
            // moment the membership lands).
            final until = result.paidUntil;
            showBookplateNotice(
              dialogContext,
              // The date is only mentioned once memberships are actually
              // required; through the beta nothing talks about when anything
              // ends.
              until != null && profile.membershipGate.enforced
                  ? 'Gift redeemed. Your membership is active through '
                      '${formatMembershipDate(until)}.'
                  : 'Gift redeemed. Your membership is active.',
            );
            Navigator.of(dialogContext).pop(true);
            return;
          }
          setState(() => error = result.message ?? GiftCodeRedemption.notRecognizedMessage);
        } catch (_) {
          if (!dialogContext.mounted) return;
          setState(() => error = "Couldn't reach The Trellis to check that code. Try again.");
        } finally {
          if (dialogContext.mounted) setState(() => isBusy = false);
        }
      }

      redeemAction = redeem;

      return [
        BookplateButton(label: 'Redeem', busy: isBusy, onPressed: isBusy ? null : redeem),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.secondary,
          onPressed: isBusy ? null : () => Navigator.of(dialogContext).pop(false),
        ),
      ];
    },
  );

  disposeAfterBookplateClose([controller]);
  return redeemed ?? false;
}
