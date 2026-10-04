import 'package:flutter/material.dart';

import '../models/dna_rhythm.dart';
import '../models/rule_item.dart';
import '../models/runner_profile.dart';
import '../theme/app_colors.dart';
import 'bookplate_chip.dart';
import 'bookplate_dialog.dart';

/// The Cloud admin's add/edit DNA Rhythm dialog — one implementation shared by
/// the Church Profile screen and the Insights page, so both behave (and read)
/// the same.
///
/// Adding a rhythm applies it to every Runner already in the church as well as
/// everyone who joins later (the database does that in one step — see
/// supabase/migrations/016); editing one carries the change through to every
/// member's copy.
Future<void> showDnaRhythmDialog(
  BuildContext context,
  RunnerProfile profile, {
  DnaRhythm? existing,
}) async {
  final titleController = TextEditingController(text: existing?.title ?? '');
  var category = existing?.category ?? RuleCategory.abidingPrayer;
  var frequency = existing?.frequency ?? RuleFrequency.weekly;
  final weeklyDays = {...(existing?.weeklyDays ?? const {DateTime.sunday})};
  final isEditing = existing != null;
  String? error;

  final rhythm = await showBookplateForm<DnaRhythm>(
    context,
    title: isEditing ? 'Edit DNA Rhythm' : 'New DNA Rhythm',
    message: isEditing
        ? "Changes reach every member's Rule of Life — not just new members."
        : "This is added to the Rule of Life of every Runner already in your church, and of "
            'everyone who joins later, as a mandated DNA Rhythm — distinct from a Runner\'s '
            'own personal Anchor Rhythm.',
    bodyBuilder: (dialogContext, setDialogState) {
      final textTheme = Theme.of(dialogContext).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: titleController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Rhythm',
              hintText: 'e.g. Sabbath Rest',
            ),
          ),
          const SizedBox(height: 16),
          Text('Category', style: textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in RuleCategory.values)
                BookplateChip(
                  label: c.label,
                  selected: category == c,
                  compact: true,
                  onTap: () => setDialogState(() => category = c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('How often', style: textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in RuleFrequency.values)
                BookplateChip(
                  label: f.label,
                  selected: frequency == f,
                  compact: true,
                  onTap: () => setDialogState(() => frequency = f),
                ),
            ],
          ),
          if (frequency == RuleFrequency.weekly) ...[
            const SizedBox(height: 12),
            Text('On which days', style: textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final weekday in weekdayOrder)
                  BookplateChip(
                    label: weekdayShortLabel(weekday),
                    selected: weeklyDays.contains(weekday),
                    compact: true,
                    onTap: () => setDialogState(() {
                      if (!weeklyDays.add(weekday)) weeklyDays.remove(weekday);
                    }),
                  ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta)),
          ],
        ],
      );
    },
    actionsBuilder: (dialogContext, setDialogState) => [
      BookplateButton(
        label: isEditing ? 'Save' : 'Add to Everyone',
        onPressed: () {
          if (titleController.text.trim().isEmpty) {
            setDialogState(() => error = 'Give the rhythm a name.');
            return;
          }
          if (frequency == RuleFrequency.weekly && weeklyDays.isEmpty) {
            setDialogState(() => error = 'Choose at least one day of the week.');
            return;
          }
          Navigator.of(dialogContext).pop(
            DnaRhythm(
              title: titleController.text.trim(),
              category: category,
              frequency: frequency,
              weeklyDays: weeklyDays,
            ),
          );
        },
      ),
      BookplateButton(
        label: 'Cancel',
        variant: BookplateButtonVariant.secondary,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );

  // The closing fade still builds the field once more; dispose afterwards.
  Future<void>.delayed(const Duration(milliseconds: 500), titleController.dispose);

  if (rhythm == null) return;
  try {
    if (isEditing) {
      await profile.updateDnaRhythm(existing.title, rhythm);
    } else {
      await profile.addDnaRhythm(rhythm);
    }
    if (context.mounted) {
      showBookplateNotice(
        context,
        isEditing
            ? 'DNA Rhythm updated for the whole church.'
            : 'DNA Rhythm added to every member\'s Rule of Life.',
      );
    }
  } catch (_) {
    if (context.mounted) {
      showBookplateNotice(context, "Couldn't save that DNA Rhythm. Check for a duplicate name.");
    }
  }
}
