import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/runner_profile.dart';
import '../services/share_service.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';

/// Opens the Runner's "Generate Witness Code" modal — the reciprocal of the
/// Witness shell's "Enter a pairing code" screen. A code is minted as soon
/// as the modal opens (a 6-character uppercase alphanumeric string, valid
/// for 24 hours, single use) and can be copied, shared, or replaced.
Future<void> showWitnessCodeDialog(BuildContext context, RunnerProfile profile) async {
  String? code;
  var isLoading = true;
  String? error;

  // The dialog's own StateSetter, captured while it is on screen so that the
  // asynchronous code request can repaint it when it finishes.
  StateSetter? refresh;
  var isOpen = true;

  void update(VoidCallback change) {
    change();
    if (isOpen) refresh?.call(() {});
  }

  Future<void> generate() async {
    update(() {
      isLoading = true;
      error = null;
    });

    try {
      final generated = await profile.generatePairingCode();
      update(() => code = generated);
    } catch (_) {
      update(() => error = "Couldn't generate a code — check your connection and try again.");
    } finally {
      update(() => isLoading = false);
    }
  }

  Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    showBookplateNotice(context, 'Witness code copied.');
  }

  // Mint the first code as soon as the dialog opens.
  generate();

  await showBookplateForm<void>(
    context,
    title: 'Witness Code',
    message: 'Give this code to someone you trust to walk alongside you. They enter it '
        'in their Witness tab to connect. It works once and expires in 24 hours.',
    bodyBuilder: (dialogContext, setDialogState) {
      refresh = setDialogState;
      final textTheme = Theme.of(dialogContext).textTheme;
      final current = code;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.parchmentLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.antiqueBrass),
            ),
            alignment: Alignment.center,
            child: isLoading
                ? const SizedBox(
                    height: 40,
                    child: Center(child: BookplateSpinner(size: 32, color: AppColors.forestGreen)),
                  )
                // One line always: shrinks to fit a narrow phone or a large
                // text size instead of breaking the code across two lines.
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        current ?? '——————',
                        maxLines: 1,
                        semanticsLabel: current == null
                            ? 'No code yet'
                            : 'Witness code ${current.split('').join(' ')}',
                        style: textTheme.displaySmall?.copyWith(
                          letterSpacing: 8,
                          color: current == null
                              ? AppColors.forestGreen.withValues(alpha: 0.3)
                              : AppColors.forestGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      );
    },
    actionsBuilder: (dialogContext, setDialogState) {
      refresh = setDialogState;
      final current = code;
      final canUse = current != null && !isLoading;

      return [
        Row(
          children: [
            Expanded(
              child: BookplateButton(
                label: 'Copy',
                variant: BookplateButtonVariant.secondary,
                onPressed: canUse ? () => copy(current) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              // Builder: the share sheet anchors to THIS button (iPad needs it).
              child: Builder(
                builder: (buttonContext) => BookplateButton(
                  label: 'Share',
                  variant: BookplateButtonVariant.secondary,
                  onPressed: canUse
                      ? () => shareText(
                            buttonContext,
                            'Join me on The Trellis as my Witness. '
                            'Use pairing code $current to connect.',
                            subject: 'Be my Witness on The Trellis',
                          )
                      : null,
                ),
              ),
            ),
          ],
        ),
        BookplateButton(
          label: error != null ? 'Try Again' : 'Generate a New Code',
          variant: BookplateButtonVariant.link,
          compact: true,
          onPressed: isLoading ? null : generate,
        ),
        BookplateButton(
          label: 'Done',
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ];
    },
  );

  isOpen = false;
}
