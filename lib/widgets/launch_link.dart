import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bookplate_dialog.dart';

/// `key=value&…` with every value percent-encoded (spaces as `%20`).
///
/// `Uri(queryParameters: …)` form-encodes instead, turning each space into a
/// `+` — and messaging and mail apps do not turn those back, so a pre-written
/// text would arrive reading "Hey+Sam,+just+checking+in". Always build
/// `sms:` / `mailto:` queries with this.
String _encodeQuery(Map<String, String> parameters) => parameters.entries
    .map((entry) => '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}')
    .join('&');

/// An `sms:` link to [phone], optionally with a pre-written [body]. The number
/// is reduced to its digits (and a leading `+`) so spaces, dashes and
/// parentheses typed by a person can't break the link.
Uri smsUri(String phone, {String? body}) {
  final trimmed = phone.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  final number = trimmed.startsWith('+') ? '+$digits' : digits;
  return Uri(
    scheme: 'sms',
    path: number,
    query: body == null || body.isEmpty ? null : _encodeQuery({'body': body}),
  );
}

/// A `mailto:` link to [email], optionally with a [subject] and [body].
Uri mailtoUri(String email, {String? subject, String? body}) {
  final parameters = {
    if (subject != null && subject.isNotEmpty) 'subject': subject,
    if (body != null && body.isNotEmpty) 'body': body,
  };
  return Uri(
    scheme: 'mailto',
    path: email.trim(),
    query: parameters.isEmpty ? null : _encodeQuery(parameters),
  );
}

/// Opens [uri] outside the app. Returns false — never throws — if nothing on
/// the device could open it.
///
/// Deliberately does NOT ask `canLaunchUrl` first: on iOS that answers false
/// for `sms:` / `mailto:` / `tel:` unless each scheme is declared in
/// Info.plist, and on Android 11+ it answers false without a manifest
/// `<queries>` entry — even when launching would have worked. Trying the
/// launch and reading its result is the reliable test.
Future<bool> tryLaunch(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
  try {
    return await launchUrl(uri, mode: mode);
  } catch (error) {
    debugPrint('Could not launch ${uri.scheme}: link — $error');
    return false;
  }
}

/// [tryLaunch], and if it fails, says so with [unavailable] as a notice.
Future<void> launchOrNotify(
  BuildContext context,
  Uri uri, {
  required String unavailable,
  LaunchMode mode = LaunchMode.platformDefault,
}) async {
  final opened = await tryLaunch(uri, mode: mode);
  if (!opened && context.mounted) showBookplateNotice(context, unavailable);
}

/// Opens a web page in the device's browser, with a notice if it can't.
Future<void> openWebPage(BuildContext context, String url) => launchOrNotify(
      context,
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      unavailable: "Couldn't open that page. Visit $url in your browser.",
    );
