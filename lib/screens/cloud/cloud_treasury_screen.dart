import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/church_code.dart';
import '../../models/meeting_proposal_engine.dart' show monthAbbrev;
import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/cloud_preview.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/launch_link.dart';

/// The Church Admin's Treasury tab: subscription/license overview and
/// church invite-code generation for onboarding new Runners.
class CloudTreasuryScreen extends StatefulWidget {
  const CloudTreasuryScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<CloudTreasuryScreen> createState() => _CloudTreasuryScreenState();
}

class _CloudTreasuryScreenState extends State<CloudTreasuryScreen> {
  String? _justGeneratedCode;
  bool _isGenerating = false;

  /// Codes with a revoke on its way to the server (no double revoke).
  final Set<String> _revoking = {};

  RunnerProfile get _profile => widget.profile;

  /// Mints one code per tap — busy while the server works, so an impatient
  /// second tap can't mint a second (each one is a real licence invite) — and
  /// says so if it couldn't.
  Future<void> _generateCode() async {
    if (_isGenerating || refuseInPreview(context, _profile)) return;
    setState(() => _isGenerating = true);
    try {
      final code = await _profile.generateChurchCode();
      if (!mounted) return;
      setState(() => _justGeneratedCode = code);
    } catch (_) {
      if (mounted) {
        showBookplateNotice(
          context,
          "Couldn't generate a church code. Check your connection and try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _copyCode(String code) async {
    String message;
    try {
      await Clipboard.setData(ClipboardData(text: code));
      message = 'Copied $code to clipboard.';
    } catch (_) {
      message = 'Could not access the clipboard on this device.';
    }
    if (!mounted) return;
    showBookplateNotice(context, message);
  }

  /// Revoking deletes the code for good — anyone it was already given to can
  /// no longer use it — so it asks first.
  Future<void> _revokeCode(String code) async {
    if (_revoking.contains(code) || refuseInPreview(context, _profile)) return;
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Revoke This Code?',
      message: '$code will stop working. If you have already given it to someone, they will '
          'need a new one.',
      confirmLabel: 'Revoke',
      cancelLabel: 'Keep It',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _revoking.add(code));
    final revoked = await runWithFailureNotice(
      context,
      () => _profile.revokeChurchCode(code),
      failure: "Couldn't revoke that code. Check your connection and try again.",
    );
    if (!mounted) return;
    setState(() {
      _revoking.remove(code);
      if (revoked && _justGeneratedCode == code) _justGeneratedCode = null;
    });
  }

  String _generatedLabel(DateTime date) {
    final days = DateTime.now().difference(date).inDays;
    if (days <= 0) return 'Generated today';
    if (days == 1) return 'Generated yesterday';
    return 'Generated $days days ago';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final unusedCodes = _profile.churchCodes.where((c) => !c.isRedeemed).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Canopy Billing & Licenses', style: textTheme.headlineMedium),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.forestGreen,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Licenses: ${_profile.activeLicenseCount} / ${_profile.licenseCap}',
                  style: textTheme.titleMedium?.copyWith(color: AppColors.parchmentLight),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final renewalDate = _profile.annualRenewalDate;
                    final label = renewalDate == null
                        ? 'Annual Renewal Date: —'
                        : 'Annual Renewal Date: ${monthAbbrev[renewalDate.month - 1]} '
                            '${renewalDate.year}';
                    return Text(
                      label,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.parchmentLight.withValues(alpha: 0.9),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Current Rate: \$${_profile.ratePerRunner.toStringAsFixed(0)} / Runner',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.parchmentLight.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Licenses are bought outside the app (the old "Purchase Additional
          // Licenses" button had nothing behind it); point at where it happens.
          Text(
            'Need room for more Runners? Licenses are increased through Unhindered Lives.',
            style: textTheme.bodySmall,
          ),
          Center(
            child: BookplateButton(
              label: 'Increase licenses at unhinderedlives.com/trellis',
              variant: BookplateButtonVariant.link,
              compact: true,
              onPressed: () => openWebPage(context, churchLicenseUrl),
            ),
          ),
          const SizedBox(height: 20),
          Text('Invite New Runners', style: textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Give these codes to members of your congregation. When they sign up, '
            'they will bypass the individual \$12/yr paywall and automatically connect '
            'to this Cloud roster.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Center(
            child: GradientButton(
              label: 'Generate New Church Code',
              busy: _isGenerating,
              onPressed: _generateCode,
            ),
          ),
          if (_justGeneratedCode != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.antiqueBrass.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.antiqueBrass),
              ),
              // A Wrap: beside each other with room, the button beneath the
              // code on a narrow phone — so the code itself is never broken
              // across lines to make space for the button.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _justGeneratedCode!,
                      maxLines: 1,
                      style: textTheme.headlineSmall?.copyWith(
                        color: AppColors.antiqueBrass,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  BookplateButton(
                    label: 'Copy to Clipboard',
                    compact: true,
                    variant: BookplateButtonVariant.secondary,
                    onPressed: () => _copyCode(_justGeneratedCode!),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text('Unused Codes', style: textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Codes that have been generated but not yet redeemed.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (unusedCodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No unused codes right now.', style: textTheme.bodyMedium),
              ),
            )
          else
            for (final churchCode in unusedCodes) ...[
              _CodeRow(
                churchCode: churchCode,
                label: _generatedLabel(churchCode.generatedDate),
                busy: _revoking.contains(churchCode.code),
                onCopy: () => _copyCode(churchCode.code),
                onRevoke: () => _revokeCode(churchCode.code),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({
    required this.churchCode,
    required this.label,
    required this.busy,
    required this.onCopy,
    required this.onRevoke,
  });

  final ChurchCode churchCode;
  final String label;
  final bool busy;
  final VoidCallback onCopy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BookplatePlate(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  churchCode.code,
                  style: textTheme.titleMedium?.copyWith(letterSpacing: 1.2),
                ),
                Text(label, style: textTheme.bodySmall),
              ],
            ),
          ),
          // An unused code is only useful if it can be handed out again —
          // the "just generated" panel above disappears on the next visit.
          BrassGlyphButton(
            kind: BrassGlyphKind.copy,
            semanticLabel: 'Copy code ${churchCode.code}',
            color: AppColors.antiqueBrass,
            onPressed: onCopy,
          ),
          const SizedBox(width: 4),
          BookplateButton(
            label: 'Revoke',
            compact: true,
            variant: BookplateButtonVariant.danger,
            busy: busy,
            onPressed: onRevoke,
          ),
        ],
      ),
    );
  }
}
