import 'package:flutter/material.dart';

import '../models/prayer_texts.dart';
import '../models/scripture_verses.dart';
import '../theme/app_colors.dart';
import 'bookplate_chip.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';

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
  ScriptureTheme? _theme;
  int _index = 0;
  bool _useSaved = false;

  ScripturePassage? get _passage {
    if (_useSaved) return passageForReference(widget.savedScripture!);
    final theme = _theme;
    if (theme == null) return null;
    final passages = scriptureByTheme[theme]!;
    return passages[_index % passages.length];
  }

  void _chooseTheme(ScriptureTheme theme) {
    setState(() {
      _useSaved = false;
      _theme = theme;
      _index = themesLedByFirstPassage.contains(theme)
          ? 0
          : firstPassageIndex(scriptureByTheme[theme]!, widget.firstName, DateTime.now());
    });
  }

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
                _theme = null;
              }),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Choose a theme', style: textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final theme in ScriptureTheme.values)
              BookplateChip(
                label: theme.label,
                selected: _theme == theme,
                compact: true,
                onTap: () => _chooseTheme(theme),
              ),
          ],
        ),
        if (passage != null) ...[
          const SizedBox(height: 16),
          BookplatePlate(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (passage.text.isNotEmpty)
                  Text(
                    passage.text,
                    style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                  ),
                const SizedBox(height: 8),
                Text(
                  passage.text.isEmpty ? passage.reference : '${passage.reference}, BSB',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.antiqueBrass,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_theme != null)
            Align(
              alignment: Alignment.centerRight,
              child: BookplateButton(
                label: 'Different verse',
                variant: BookplateButtonVariant.link,
                compact: true,
                onPressed: () => setState(() => _index++),
              ),
            ),
        ],
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
