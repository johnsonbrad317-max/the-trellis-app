import 'package:flutter/material.dart';

import '../../models/runner_profile.dart';
import '../../models/witness.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/custom_toggle.dart';
import '../../widgets/trellis_scaffold.dart';
import '../../widgets/witness_code_dialog.dart';

/// Manage the accountability lock, active Witnesses, and invitations.
class SettingsWitnessesScreen extends StatefulWidget {
  const SettingsWitnessesScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<SettingsWitnessesScreen> createState() => _SettingsWitnessesScreenState();
}

class _SettingsWitnessesScreenState extends State<SettingsWitnessesScreen> {
  RunnerProfile get _profile => widget.profile;

  Future<void> _handleAccountabilityLockChanged(bool value) async {
    if (value) {
      await runWithFailureNotice(
        context,
        () => _profile.setAccountabilityLock(true),
        failure: "Couldn't turn that on. Check your connection and try again.",
      );
      return;
    }

    // With no Witness there is nobody who could approve, so the Runner may
    // release the lock themselves (the server allows exactly that case).
    final hasWitness = _profile.witnesses.isNotEmpty;

    final confirmed = await showBookplateConfirm(
      context,
      title: 'Turn Off Witness Permission?',
      message: hasWitness
          ? "You can't turn this off on your own — it exists to protect you in a "
              'moment of isolation. Turning it off will send an approval request '
              'to your Witness(es), and it stays on until one of them approves.'
          : 'You have no Witness yet, so there is no one to ask — you can turn this off '
              'yourself. You can turn it back on at any time.',
      confirmLabel: hasWitness ? 'Send Approval Request' : 'Turn It Off',
      cancelLabel: 'Keep It On',
    );
    if (!confirmed || !mounted) return;

    // Say what happened only once the server has really done it.
    bool? turnedOff;
    try {
      turnedOff = await _profile.requestAccountabilityLockRemoval();
    } catch (_) {
      turnedOff = null;
    }
    if (!mounted) return;

    showBookplateNotice(
      context,
      switch (turnedOff) {
        true => 'Witness permission is now off.',
        false => 'Your Witness(es) have been asked to approve turning this off.',
        null => "Couldn't do that just now. Check your connection and try again.",
      },
    );
  }

  Future<void> _removeWitness(Witness witness) async {
    // While Witness permission is on, a Witness can't be removed: the lock has
    // to be released first, and releasing it is what a Witness approves. Say
    // so plainly and offer that step — never claim a removal was requested.
    if (_profile.accountabilityLockEnabled) {
      final pending = _profile.accountabilityLockRemovalPending;
      final ask = await showBookplateConfirm(
        context,
        title: 'Witness Permission Is On',
        message: pending
            ? "${witness.name} can't be removed while Witness permission is on. Your "
                'request to turn it off is waiting on a Witness — once one of them '
                'approves, you can remove ${witness.name} here.'
            : "${witness.name} can't be removed while Witness permission is on. Ask to "
                'turn it off first; once a Witness approves, you can remove '
                '${witness.name} here.',
        confirmLabel: pending ? 'OK' : 'Ask to Turn It Off',
        cancelLabel: pending ? 'Close' : 'Not Now',
      );
      if (ask && !pending && mounted) await _handleAccountabilityLockChanged(false);
      return;
    }

    final reasonController = TextEditingController();
    var reasonMissing = false;

    final reason = await showBookplateForm<String>(
      context,
      title: 'Remove Witness',
      message: 'This removes ${witness.name} immediately.',
      bodyBuilder: (dialogContext, setDialogState) => TextField(
        controller: reasonController,
        maxLines: 3,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Reason',
          errorText: reasonMissing ? 'Please give a reason.' : null,
        ),
      ),
      actionsBuilder: (dialogContext, setDialogState) => [
        BookplateButton(
          label: 'Remove',
          variant: BookplateButtonVariant.danger,
          onPressed: () {
            final reason = reasonController.text.trim();
            if (reason.isEmpty) {
              setDialogState(() => reasonMissing = true);
              return;
            }
            Navigator.pop(dialogContext, reason);
          },
        ),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.secondary,
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ],
    );

    disposeAfterBookplateClose([reasonController]);

    if (reason == null || !mounted) return;

    final removed = await runWithFailureNotice(
      context,
      () => _profile.removeWitness(witness.id, reason: reason),
      failure: "Couldn't remove ${witness.name}. Check your connection and try again.",
    );
    if (!removed || !mounted) return;
    showBookplateNotice(context, '${witness.name} has been removed.');
  }

  Future<void> _generatePairingCode() => showWitnessCodeDialog(context, _profile);

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'My Witnesses'),
      body: ListenableBuilder(
        listenable: _profile,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BookplatePlate(
              padding: EdgeInsets.zero,
              child: ToggleRow(
                padding: const EdgeInsets.all(16),
                title: 'Require Witness permission to be removed',
                subtitle: _profile.accountabilityLockRemovalPending
                    ? 'Removal requested — waiting on your Witness to approve.'
                    : 'If enabled, you cannot remove a Witness in a moment of isolation; '
                        'they must approve the removal request.',
                value: _profile.accountabilityLockEnabled,
                onChanged: _profile.accountabilityLockRemovalPending
                    ? null
                    : _handleAccountabilityLockChanged,
              ),
            ),
            const SizedBox(height: 24),
            Text('Active Witnesses', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_profile.witnesses.isEmpty)
              BookplatePlate(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'You have no active Witnesses yet. Invite one below.',
                  style: textTheme.bodyMedium,
                ),
              )
            else
              for (final witness in _profile.witnesses) ...[
                BookplatePlate(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BookplateRow(
                        padding: EdgeInsets.zero,
                        leading: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.forestGreen,
                          ),
                          child: ExcludeSemantics(
                            child: Text(
                              witness.initials,
                              style:
                                  textTheme.labelLarge?.copyWith(color: AppColors.parchmentLight),
                            ),
                          ),
                        ),
                        title: witness.name,
                        subtitle: 'Witness since ${_formatDate(witness.since)}',
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: BookplateButton(
                          label: 'Remove',
                          variant: BookplateButtonVariant.danger,
                          compact: true,
                          onPressed: () => _removeWitness(witness),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 24),
            BookplatePlate(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invite a Witness', style: textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Generate a one-time pairing code and share it with someone you trust.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  BookplateButton(
                    label: 'Generate New Pairing Code',
                    onPressed: _generatePairingCode,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
