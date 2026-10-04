import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The Google Maps web search URL — the universal fallback (works in any
/// browser, and opens the Google Maps app where one is installed).
Uri googleMapsWebUri(String address) => Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeQueryComponent(address.trim())}',
    );

/// The URL that shows [address] in the platform's native maps app.
///
///  * iOS / macOS: Apple Maps (`https://maps.apple.com/?q=...`).
///  * Android: a `geo:` intent, which opens whichever maps app the user has
///    set as default (Google Maps on nearly every device).
///  * Everything else (web, Windows, Linux): Google Maps in the browser.
///
/// Pure — no I/O — so the encoding can be unit-tested.
Uri mapsUriFor(String address, TargetPlatform platform) {
  final query = Uri.encodeQueryComponent(address.trim());
  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return Uri.parse('https://maps.apple.com/?q=$query');
    case TargetPlatform.android:
      return Uri.parse('geo:0,0?q=$query');
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return googleMapsWebUri(address);
  }
}

/// Opens [address] in Apple Maps (iOS/macOS) or Google Maps (everywhere
/// else). Returns true if a maps app or browser was launched; false on any
/// failure (blank address, no handler, platform error). Never throws.
Future<bool> openAddressInMaps(String address) async {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return false;

  // On the web the "platform" is the visitor's OS, but a geo:/Apple Maps URL
  // can't be relied on in a browser tab — always use the Google Maps site.
  final candidates = <Uri>[
    if (kIsWeb)
      googleMapsWebUri(trimmed)
    else ...[
      mapsUriFor(trimmed, defaultTargetPlatform),
      // Android: if no app handles geo:, fall back to the https URL.
      if (defaultTargetPlatform == TargetPlatform.android) googleMapsWebUri(trimmed),
    ],
  ];

  for (final uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {
      // Try the next candidate.
    }
  }
  return false;
}
