import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart';
import '../widgets/bookplate_plate.dart';
import '../widgets/brass_glyph.dart';
import '../widgets/gradient_button.dart';
import '../widgets/launch_link.dart';
import '../widgets/trellis_scaffold.dart';

/// The Tier 2 MHMDA (Washington's My Health My Data Act) sharing opt-in —
/// shown only when a Runner enters a church-gifted code at sign-up, before
/// [RunnerProfile.redeemChurchCode] runs. Separate from the ToS/Privacy/CHD
/// collection checkbox on auth_onboarding_screen.dart (Tier 1 — consenting
/// to The Trellis collecting the data at all): this is the explicit,
/// per-third-party opt-in to actually *sharing* it, mirroring
/// witness_pairing_code_screen.dart's own consent gate for the Witness side
/// of that same sharing relationship.
///
/// Joining a church makes this Runner's aggregate rhythm consistency
/// (vitality score) and check-in activity visible to that church's
/// leadership on their Cloud Roster (see
/// supabase/migrations/002_grants_and_cloud_access.sql's church_roster
/// view) — raw rule items/journal entries are never exposed, only that
/// rolled-up summary.
///
/// Returns `true` via [Navigator.pop] once the Runner consents, `false`/
/// `null` if declined — the caller must not call `redeemChurchCode` on
/// anything but `true`.
class ChurchDataSharingConsentScreen extends StatefulWidget {
  const ChurchDataSharingConsentScreen({super.key});

  @override
  State<ChurchDataSharingConsentScreen> createState() => _ChurchDataSharingConsentScreenState();
}

class _ChurchDataSharingConsentScreenState extends State<ChurchDataSharingConsentScreen> {
  bool _consentChecked = false;

  // The notice this screen asks consent under — a link that can't open says
  // so (with the address) rather than doing nothing.
  Future<void> _openNotice() =>
      openWebPage(context, 'https://unhinderedlives.com/consumer-health-data');

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'Sharing With Your Church'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: BrassGlyph(BrassGlyphKind.cross, size: 40)),
              const SizedBox(height: 16),
              Text(
                'Consumer Health Data Sharing',
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                "You're joining with a church-gifted code. By proceeding, you are opting "
                "in to share Consumer Health Data — specifically your aggregate rhythm "
                "consistency (the share of your rhythms you keep) and check-in activity — with that church's "
                'leadership on their Roster, so they can support your congregation well. '
                'Your individual rhythm entries and journal content are never shared — '
                'only that rolled-up summary.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Center(
                child: BookplateButton(
                  label: 'Read the Consumer Health Data Notice',
                  variant: BookplateButtonVariant.link,
                  onPressed: _openNotice,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.antiqueBrass.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.antiqueBrass),
                ),
                child: BookplateCheckboxRow(
                  value: _consentChecked,
                  onChanged: (value) => setState(() => _consentChecked = value),
                  label: Text(
                    'I opt in to sharing my Consumer Health Data (aggregate rhythm '
                    "consistency) with this church's leadership.",
                    style: textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: 'Continue',
                onPressed: _consentChecked ? () => Navigator.of(context).pop(true) : null,
              ),
              const SizedBox(height: 12),
              Center(
                child: BookplateButton(
                  label: 'Not Now',
                  variant: BookplateButtonVariant.link,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
