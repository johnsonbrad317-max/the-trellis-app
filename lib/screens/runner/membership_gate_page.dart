import 'package:flutter/material.dart';

import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/church_affiliation_dialog.dart';
import '../../widgets/gift_code_dialog.dart';
import '../../widgets/paywall_sheet.dart';

/// What the Runner view shows in place of its tabs once the free trial is
/// over and there is no membership ([RunnerProfile.needsMembership], which is
/// never true until `app_settings.enforce_membership` is switched on at
/// launch — supabase/migrations/029). Three ways to keep going as a Runner,
/// and the reminder that witnessing is always free. Nothing the Runner has
/// built is touched; it is all there again the moment the gate lifts.
///
/// The shell around it keeps its menu (so Sign Out is where it always is)
/// and its role switcher.
class MembershipGatePage extends StatefulWidget {
  const MembershipGatePage({
    super.key,
    required this.profile,
    required this.onSwitchToWitness,
  });

  final RunnerProfile profile;

  /// Takes the person to the Witness view, which is never gated.
  final VoidCallback onSwitchToWitness;

  @override
  State<MembershipGatePage> createState() => _MembershipGatePageState();
}

class _MembershipGatePageState extends State<MembershipGatePage> {
  bool _busy = false;

  RunnerProfile get _profile => widget.profile;

  /// Runs one of the three ways in, then asks the server again. The shell
  /// listens to the profile, so the page disappears by itself once the gate
  /// has lifted.
  Future<void> _attempt(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final succeeded = await action();
      if (!succeeded) return;
      await _profile.refreshMembership();
      if (!mounted) return;
      if (!_profile.needsMembership) {
        showBookplateNotice(context, 'Thank you. Welcome back to your Rule of Life.');
      } else {
        showBookplateNotice(
          context,
          "That went through, but your membership isn't showing yet. Give it a moment and "
          'try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _subscribe() async {
    await showPaywallSheet(context, _profile);
    // A purchase marks the membership active on this phone straight away
    // (RunnerProfile.applyLocalMembershipStatus); anything else changed nothing.
    return !_profile.needsMembership;
  }

  Future<bool> _churchCode() =>
      showChurchAffiliationDialog(context, _profile, acceptMembershipCodes: true);

  Future<bool> _giftCode() => showGiftCodeDialog(context, _profile);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final quiet = textTheme.bodySmall?.copyWith(
      color: AppColors.forestGreen.withValues(alpha: 0.75),
    );

    Widget option({
      required String label,
      required String note,
      required VoidCallback onPressed,
      BookplateButtonVariant variant = BookplateButtonVariant.secondary,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BookplateButton(label: label, variant: variant, onPressed: _busy ? null : onPressed),
          const SizedBox(height: 6),
          Text(note, style: quiet, textAlign: TextAlign.center),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: BookplatePlate(
            emphasized: true,
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrassGlyph(BrassGlyphKind.leaf, size: 40)),
                const SizedBox(height: 14),
                Text(
                  'Your two free weeks are over',
                  style: textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Everything you have built is kept just as you left it. Keep going as a '
                  'Runner with one of these:',
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                option(
                  label: 'Subscribe — \$12 a year',
                  note: 'Renews yearly. Cancel any time.',
                  variant: BookplateButtonVariant.primary,
                  onPressed: () => _attempt(_subscribe),
                ),
                const SizedBox(height: 16),
                option(
                  label: 'Enter a church or organization code',
                  note: 'If your church or organization gave you a code.',
                  onPressed: () => _attempt(_churchCode),
                ),
                const SizedBox(height: 16),
                option(
                  label: 'Enter a gift code',
                  note: 'If someone gave you The Trellis as a gift.',
                  onPressed: () => _attempt(_giftCode),
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const Center(child: BookplateSpinner(size: 24, color: AppColors.forestGreen)),
                ],
                const SizedBox(height: 24),
                Text('Witnessing is always free.', style: quiet, textAlign: TextAlign.center),
                Center(
                  child: BookplateButton(
                    label: 'Switch to Witness',
                    variant: BookplateButtonVariant.link,
                    compact: true,
                    onPressed: _busy ? null : widget.onSwitchToWitness,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
