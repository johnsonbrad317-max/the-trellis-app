import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/bookplate_dialog.dart';

/// Opens the platform share sheet with [text], reliably.
///
/// Three things the bare `SharePlus.instance.share(...)` call doesn't do, and
/// each one was a way for a Share button to silently do nothing:
///  * It anchors the sheet to the tapped button ([buttonContext]'s render box).
///    iPad and macOS REQUIRE a source rectangle and otherwise show nothing.
///  * It reads the result. Where the OS can't present a share sheet at all
///    (desktop browsers, some embedded views) the status is `unavailable`.
///  * It never fails silently: in that case, or if sharing throws, the text is
///    copied to the clipboard and the user is told so, so the code is never
///    stranded.
///
/// Pass the BuildContext of the button itself (wrap it in a `Builder`) so the
/// anchor is right; any context works but the sheet may not point at the button.
Future<void> shareText(BuildContext buttonContext, String text, {String? subject}) async {
  final origin = _originOf(buttonContext);

  try {
    final result = await SharePlus.instance.share(
      ShareParams(text: text, subject: subject, sharePositionOrigin: origin),
    );
    if (result.status != ShareResultStatus.unavailable) return;
  } catch (error) {
    debugPrint('Share failed, falling back to copy: $error');
  }

  await Clipboard.setData(ClipboardData(text: text));
  if (buttonContext.mounted) {
    showBookplateNotice(
      buttonContext,
      "Sharing isn't available here, so the message was copied instead.",
    );
  }
}

/// The on-screen rectangle of the widget behind [context], or null if it
/// hasn't been laid out. Exposed for tests.
Rect? shareOriginFor(BuildContext context) => _originOf(context);

Rect? _originOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  // A zero-area rect is rejected by iOS just like a missing one.
  return rect.isEmpty ? null : rect;
}
