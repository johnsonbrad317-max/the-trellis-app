import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../models/runner_profile.dart';
import '../services/purchases_service.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';
import 'gradient_button.dart';
import 'launch_link.dart';

/// Fetches RevenueCat's current offering and, if one exists, shows the paywall
/// sheet. If there is nothing to sell — the store is unreachable, or this
/// build has no RevenueCat key — it says so plainly. There is no bypass of any
/// kind: membership is granted only by a real purchase, a restore, or a church
/// code, and `profiles.membership_status` is written only by the server.
Future<void> showPaywallSheet(BuildContext context, RunnerProfile profile) async {
  // The offering takes a moment to load; a second tap in that window must not
  // stack a second sheet.
  if (_paywallOpening) return;
  _paywallOpening = true;
  final Offering? offering;
  try {
    offering = await PurchasesService.getCurrentOffering();
  } finally {
    _paywallOpening = false;
  }
  if (!context.mounted) return;

  if (offering == null || offering.availablePackages.isEmpty) {
    showBookplateNotice(context, 'Subscriptions are not available right now.');
    return;
  }

  final package = offering.annual ?? offering.availablePackages.first;

  await showBookplateSheet<void>(
    context,
    builder: (sheetContext) => _PaywallSheet(package: package, profile: profile),
  );
}

/// True while [showPaywallSheet] is waiting on the store for the offering.
bool _paywallOpening = false;

const _termsUrl = 'https://unhinderedlives.com/terms';
const _privacyUrl = 'https://unhinderedlives.com/privacy';

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({required this.package, required this.profile});

  final Package package;
  final RunnerProfile profile;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  bool _isPurchasing = false;

  /// A trial length is a StoreKit/Play Console concept configured on the
  /// product itself, not something this app hardcodes — this reads back
  /// whatever introductory offer is actually attached to the package, so
  /// the copy never drifts out of sync with what App Store Connect /
  /// Play Console are really offering.
  String? get _trialLabel {
    final period = widget.package.storeProduct.introductoryPrice?.periodNumberOfUnits;
    final unit = widget.package.storeProduct.introductoryPrice?.periodUnit;
    if (period == null || unit == null) return null;
    // A hyphenated adjective takes the singular: "14-day free trial".
    return '$period-${unit.name.toLowerCase()} free trial, then ';
  }

  Future<void> _purchase() async {
    setState(() => _isPurchasing = true);
    try {
      final info = await PurchasesService.purchase(widget.package);
      if (info.entitlements.active.isNotEmpty) {
        widget.profile.applyLocalMembershipStatus(MembershipStatus.active);
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        // The store accepted it but the entitlement hasn't arrived yet (it can
        // lag by a few seconds). Say so rather than leaving the sheet silent.
        showBookplateNotice(
          context,
          "Your purchase went through, but your membership isn't showing yet. Give it a "
          'moment, then tap Restore Purchases.',
        );
      }
    } on PlatformException catch (error) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code != PurchasesErrorCode.purchaseCancelledError && mounted) {
        showBookplateNotice(context, error.message ?? 'Purchase failed. Try again.');
      }
    } catch (_) {
      // Anything that isn't a store error (e.g. the plugin isn't available).
      if (mounted) showBookplateNotice(context, 'Purchase failed. Try again.');
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _isPurchasing = true);
    try {
      final info = await PurchasesService.restore();
      if (!mounted) return;
      if (info.entitlements.active.isNotEmpty) {
        widget.profile.applyLocalMembershipStatus(MembershipStatus.active);
        Navigator.pop(context);
      } else {
        showBookplateNotice(context, 'No active subscription found for this account.');
      }
    } catch (_) {
      if (mounted) {
        showBookplateNotice(context, "Couldn't restore purchases. Check your connection.");
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = widget.package.storeProduct;
    final trialLabel = _trialLabel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: BrassGlyph(BrassGlyphKind.leaf, size: 40)),
        const SizedBox(height: 12),
        Text('The Trellis Membership', style: textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Full access to your Rule of Life, Witness pairing, and DNA Rhythms.',
          style: textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Text.rich(
          TextSpan(
            style: textTheme.titleLarge,
            children: [
              if (trialLabel != null) TextSpan(text: trialLabel, style: textTheme.bodyMedium),
              TextSpan(text: '${product.priceString} / year'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_isPurchasing)
          const Center(child: BookplateSpinner(size: 32, color: AppColors.forestGreen))
        else ...[
          GradientButton(
            label: trialLabel != null ? 'Start Free Trial' : 'Subscribe',
            onPressed: _purchase,
          ),
          const SizedBox(height: 8),
          Center(
            child: BookplateButton(
              variant: BookplateButtonVariant.link,
              compact: true,
              onPressed: _restore,
              label: 'Restore Purchases',
            ),
          ),
        ],
        const SizedBox(height: 12),
        // What the stores require beside an auto-renewing subscription: the
        // price and period, that it renews until cancelled and how to cancel,
        // and working links to the terms and the privacy policy.
        Text(
          '${trialLabel != null ? 'After the free trial, your' : 'Your'} membership is '
          '${product.priceString} per year and renews automatically each year until you '
          'cancel. Cancel any time, at least 24 hours before the renewal date, in your '
          'App Store or Google Play account settings.',
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.forestGreen.withValues(alpha: 0.75),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            BookplateButton(
              variant: BookplateButtonVariant.link,
              compact: true,
              label: 'Terms of Use',
              onPressed: () => openWebPage(context, _termsUrl),
            ),
            BookplateButton(
              variant: BookplateButtonVariant.link,
              compact: true,
              label: 'Privacy Policy',
              onPressed: () => openWebPage(context, _privacyUrl),
            ),
          ],
        ),
      ],
    );
  }
}
