import 'package:flutter/material.dart';

import '../models/prayer_texts.dart';
import '../models/scripture_verses.dart';
import 'bookplate_chip.dart';
import 'bookplate_dialog.dart';
import 'scripture_chooser.dart';

/// The step between "Text Kevin" and Messages: add a verse, or not.
///
/// Pick a theme and a BSB passage is offered ("Different verse" moves on);
/// a prayer that already has its own scripture offers that first. Resolves to
/// the text to send — [message] alone, or with the verse after it — or null
/// if the sheet was closed without choosing.
Future<String?> showPrayerTextSheet(
  BuildContext context, {
  required String firstName,
  required String message,
  String? savedScripture,
}) {
  return showBookplateSheet<String>(
    context,
    builder: (sheetContext) => _PrayerTextSheet(
      firstName: firstName,
      message: message,
      savedScripture: savedScripture?.trim().isEmpty ?? true ? null : savedScripture!.trim(),
    ),
  );
}

class _PrayerTextSheet extends StatefulWidget {
  const _PrayerTextSheet({required this.firstName, required this.message, this.savedScripture});

  final String firstName;
  final String message;
  final String? savedScripture;

  @override
  State<_PrayerTextSheet> createState() => _PrayerTextSheetState();
}

class _PrayerTextSheetState extends State<_PrayerTextSheet> {
  /// The passage picked from a theme, if any.
  ScripturePassage? _fromTheme;

  /// The prayer's own scripture was picked instead.
  bool _useSaved = false;

  /// Bumped to clear the theme chooser when the prayer's own verse is picked.
  int _chooserKey = 0;

  ScripturePassage? get _passage =>
      _useSaved ? passageForReference(widget.savedScripture!) : _fromTheme;

  void _send({required bool withVerse}) {
    final passage = _passage;
    Navigator.of(context).pop(
      withVerse && passage != null
          ? withScripture(widget.message, passage, firstName: widget.firstName, now: DateTime.now())
          : widget.message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final passage = _passage;
    final saved = widget.savedScripture;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add a verse?', style: textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Send ${widget.firstName} a passage along with your text, or just the text.',
          style: textTheme.bodyMedium,
        ),
        if (saved != null) ...[
          const SizedBox(height: 16),
          Text('From this prayer', style: textTheme.labelLarge),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: BookplateChip(
              label: saved,
              selected: _useSaved,
              compact: true,
              onTap: () => setState(() {
                _useSaved = true;
                _fromTheme = null;
                _chooserKey++;
              }),
            ),
          ),
          if (_useSaved) ...[
            const SizedBox(height: 12),
            ScripturePassagePlate(passage: passage!),
          ],
        ],
        const SizedBox(height: 16),
        ScriptureChooser(
          key: ValueKey(_chooserKey),
          rotateFor: widget.firstName,
          onChanged: (picked) => setState(() {
            _fromTheme = picked;
            if (picked != null) _useSaved = false;
          }),
        ),
        const SizedBox(height: 16),
        BookplateButton(
          label: 'Send with this verse',
          onPressed: passage == null ? null : () => _send(withVerse: true),
        ),
        const SizedBox(height: 8),
        BookplateButton(
          label: 'Just send the text',
          variant: BookplateButtonVariant.secondary,
          onPressed: () => _send(withVerse: false),
        ),
      ],
    );
  }
}
