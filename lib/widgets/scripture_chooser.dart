import 'package:flutter/material.dart';

import '../models/prayer_texts.dart';
import '../models/scripture_verses.dart';
import '../theme/app_colors.dart';
import 'bookplate_chip.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';

/// Pick a theme, see a BSB passage, "Different verse" to move on — the part
/// of choosing a verse that the prayer text sheet and a prayer card's
/// Scripture field share. Reports the passage showing (null until a theme is
/// chosen) through [onChanged]. Give it a new key to clear it.
class ScriptureChooser extends StatefulWidget {
  const ScriptureChooser({
    super.key,
    required this.onChanged,
    this.rotateFor,
  });

  final ValueChanged<ScripturePassage?> onChanged;

  /// Whose name (with today's date) picks the first passage offered in a
  /// theme, so it is not always the same one. Null starts at the top.
  final String? rotateFor;

  @override
  State<ScriptureChooser> createState() => _ScriptureChooserState();
}

class _ScriptureChooserState extends State<ScriptureChooser> {
  ScriptureTheme? _theme;
  int _index = 0;

  ScripturePassage? get _passage {
    final theme = _theme;
    if (theme == null) return null;
    final passages = scriptureByTheme[theme]!;
    return passages[_index % passages.length];
  }

  void _choose(ScriptureTheme theme) {
    final passages = scriptureByTheme[theme]!;
    final name = widget.rotateFor;
    setState(() {
      _theme = theme;
      _index = themesLedByFirstPassage.contains(theme) || name == null
          ? 0
          : firstPassageIndex(passages, name, DateTime.now());
    });
    widget.onChanged(_passage);
  }

  void _next() {
    setState(() => _index++);
    widget.onChanged(_passage);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final passage = _passage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                onTap: () => _choose(theme),
              ),
          ],
        ),
        if (passage != null) ...[
          const SizedBox(height: 16),
          ScripturePassagePlate(passage: passage),
          Align(
            alignment: Alignment.centerRight,
            child: BookplateButton(
              label: 'Different verse',
              variant: BookplateButtonVariant.link,
              compact: true,
              onPressed: _next,
            ),
          ),
        ],
      ],
    );
  }
}

/// One passage on a small plate: the verse in italics, its reference in brass
/// (", BSB" when the text is ours; the reference alone when it is not).
class ScripturePassagePlate extends StatelessWidget {
  const ScripturePassagePlate({super.key, required this.passage});

  final ScripturePassage passage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return BookplatePlate(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (passage.text.isNotEmpty) ...[
            Text(passage.text, style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
          ],
          Text(
            passage.text.isEmpty ? passage.reference : '${passage.reference}, BSB',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.antiqueBrass,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Choosing a verse for a prayer card's Scripture: resolves to the passage
/// picked, or null if closed without one.
Future<ScripturePassage?> showScripturePickerSheet(BuildContext context) {
  return showBookplateSheet<ScripturePassage>(
    context,
    builder: (sheetContext) => const _ScripturePickerSheet(),
  );
}

class _ScripturePickerSheet extends StatefulWidget {
  const _ScripturePickerSheet();

  @override
  State<_ScripturePickerSheet> createState() => _ScripturePickerSheetState();
}

class _ScripturePickerSheetState extends State<_ScripturePickerSheet> {
  ScripturePassage? _passage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choose a Verse', style: textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Pick a theme, then "Different verse" until one fits this prayer.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        ScriptureChooser(onChanged: (passage) => setState(() => _passage = passage)),
        const SizedBox(height: 16),
        BookplateButton(
          label: 'Use This Verse',
          onPressed: _passage == null ? null : () => Navigator.of(context).pop(_passage),
        ),
        const SizedBox(height: 8),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
