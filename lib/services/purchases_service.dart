import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat public SDK keys (Dashboard -> Project Settings -> API Keys —
/// one per store; public values, not secrets). Supplied at build time:
///   flutter build ipa       --dart-define=REVENUECAT_APPLE_API_KEY=appl_...
///   flutter build appbundle --dart-define=REVENUECAT_GOOGLE_API_KEY=goog_...
/// (codemagic.yaml passes both from the `trellis_app_config` variable group.)
/// A build without a key still runs: every method below is a silent no-op
/// and the paywall reports that subscriptions aren't available.
const _appleApiKey = String.fromEnvironment('REVENUECAT_APPLE_API_KEY');
const _googleApiKey = String.fromEnvironment('REVENUECAT_GOOGLE_API_KEY');

/// Wraps the RevenueCat SDK: configuring it once at app start, identifying
/// the signed-in Supabase user so `app_user_id` in every RevenueCat
/// webhook event matches `profiles.id` (see supabase/functions/
/// revenuecat-webhook/), and the purchase/restore calls the paywall uses.
class PurchasesService {
  PurchasesService._();

  static bool _initialized = false;

  // dart:io's Platform throws outright on web (not just "returns false" —
  // an actual UnsupportedError), so kIsWeb has to short-circuit before
  // Platform.isIOS is ever touched. This app has no RevenueCat web SDK
  // wired up regardless — the paywall is mobile-only, same as every other
  // App Store/Play Store-specific piece of this feature.
  static bool get _hasApiKey {
    if (kIsWeb) return false;
    return Platform.isIOS ? _appleApiKey.isNotEmpty : _googleApiKey.isNotEmpty;
  }

  static Future<void> initialize() async {
    if (_initialized || !_hasApiKey) return;
    _initialized = true;

    // Quiet in production; chatty only while developing.
    await Purchases.setLogLevel(kReleaseMode ? LogLevel.error : LogLevel.info);
    final apiKey = Platform.isIOS ? _appleApiKey : _googleApiKey;
    await Purchases.configure(PurchasesConfiguration(apiKey));
  }

  /// Ties this device to the signed-in account so RevenueCat's webhook
  /// events carry the Supabase user id as `app_user_id` — see
  /// RunnerProfile.loadCurrent, which calls this the same way it calls
  /// PushNotifications.registerForCurrentUser.
  static Future<void> identify(String userId) async {
    if (!_initialized) return;
    try {
      await Purchases.logIn(userId);
    } catch (error) {
      debugPrint('PurchasesService.identify failed: $error');
    }
  }

  /// The App Store / Google Play page where this account's subscription can
  /// be cancelled, or null when RevenueCat has no store subscription for it
  /// (never subscribed, or membership came from a church code) or isn't
  /// configured in this build.
  static Future<String?> managementUrl() async {
    if (!_initialized) return null;
    final info = await Purchases.getCustomerInfo();
    return info.managementURL;
  }

  /// The offering to sell, or null when there is nothing to show: no key in
  /// this build, the store is unreachable, or no offering is configured.
  /// Never throws — the paywall treats null as "not available right now".
  static Future<Offering?> getCurrentOffering() async {
    if (!_initialized) return null;
    try {
      final offerings = await Purchases.getOfferings().timeout(const Duration(seconds: 15));
      return offerings.current;
    } catch (error) {
      debugPrint('PurchasesService.getCurrentOffering failed: $error');
      return null;
    }
  }

  static Future<CustomerInfo> purchase(Package package) => Purchases.purchasePackage(package);

  static Future<CustomerInfo> restore() => Purchases.restorePurchases();
}
