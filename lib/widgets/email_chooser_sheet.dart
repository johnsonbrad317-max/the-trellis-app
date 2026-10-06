import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';
import 'launch_link.dart';

/// Lets the person pick how to write an email to [email]: the phone's mail
/// app (`mailto:`), Gmail, Outlook, or simply copying the address.
///
/// A plain `mailto:` link only ever opens whatever the OS calls the default
/// mail app — on an iPhone that is Apple Mail even for someone who lives in
/// Gmail, and with Mail never set up the link did nothing at all. So the
/// Gmail and Outlook rows are offered whenever the OS says those apps are
/// installed (their URL schemes are declared in Info.plist and the Android
/// manifest so that question can be asked), and the copy row is always
/// there as the way that cannot fail.
Future<void> showEmailChooser(
  BuildContext context, {
  required String email,
  String? subject,
  String? body,
}) async {
  final address = email.trim();
  if (address.isEmpty) return;

  final gmail = gmailComposeUri(address, subject: subject, body: body);
  final outlook = outlookComposeUri(address, subject: subject, body: body);
  final available = await Future.wait([canOpen(gmail), canOpen(outlook)]);
  if (!context.mounted) return;

  await showBookplateSheet<void>(
    context,
    builder: (sheetContext) => _EmailChooserBody(
      address: address,
      mail: mailtoUri(address, subject: subject, body: body),
      gmail: available[0] ? gmail : null,
      outlook: available[1] ? outlook : null,
    ),
  );
}

class _EmailChooserBody extends StatelessWidget {
  const _EmailChooserBody({
    required this.address,
    required this.mail,
    required this.gmail,
    required this.outlook,
  });

  final String address;
  final Uri mail;
  final Uri? gmail;
  final Uri? outlook;

  Future<void> _open(BuildContext context, Uri uri, String appName) async {
    final navigator = Navigator.of(context);
    final opened = await tryLaunch(uri);
    if (!context.mounted) return;
    if (opened) {
      navigator.pop();
      return;
    }
    showBookplateNotice(context, "$appName couldn't be opened. Copy the address instead.");
  }

  Future<void> _copy(BuildContext context) async {
    final navigator = Navigator.of(context);
    await Clipboard.setData(ClipboardData(text: address));
    if (!context.mounted) return;
    navigator.pop();
    showBookplateNotice(context, 'Copied $address.');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const glyphColor = AppColors.antiqueBrass;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Write to $address', style: textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Choose where to write the email.', style: textTheme.bodySmall),
        const SizedBox(height: 8),
        BookplateRow(
          leading: const BrassGlyph(BrassGlyphKind.envelope, color: glyphColor),
          title: 'Mail',
          subtitle: "This phone's mail app",
          trailing: const BrassGlyph(BrassGlyphKind.forward),
          onTap: () => _open(context, mail, 'Mail'),
        ),
        if (gmail != null) ...[
          const BookplateDivider(),
          BookplateRow(
            leading: const BrassGlyph(BrassGlyphKind.envelope, color: glyphColor),
            title: 'Gmail',
            trailing: const BrassGlyph(BrassGlyphKind.forward),
            onTap: () => _open(context, gmail!, 'Gmail'),
          ),
        ],
        if (outlook != null) ...[
          const BookplateDivider(),
          BookplateRow(
            leading: const BrassGlyph(BrassGlyphKind.envelope, color: glyphColor),
            title: 'Outlook',
            trailing: const BrassGlyph(BrassGlyphKind.forward),
            onTap: () => _open(context, outlook!, 'Outlook'),
          ),
        ],
        const BookplateDivider(),
        BookplateRow(
          leading: const BrassGlyph(BrassGlyphKind.copy, color: glyphColor),
          title: 'Copy address',
          subtitle: 'Paste it wherever you write email',
          onTap: () => _copy(context),
        ),
        const SizedBox(height: 8),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.link,
          compact: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
