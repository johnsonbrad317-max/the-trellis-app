import 'package:flutter/material.dart';

import '../../models/dna_rhythm.dart';
import '../../models/rule_item.dart';
import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/dna_rhythm_dialog.dart';
import '../../widgets/trellis_scaffold.dart';

/// Church-configuration settings for the Cloud role — separate from the
/// read-only Congregational Health analytics dashboard. This is where a
/// Church Admin actually manages the church's DNA Rhythms (add, edit,
/// remove), so that data-shaping actions never live on an at-a-glance
/// analytics screen. (Insights offers a shortcut to add one too; both open
/// the same dialog.)
class ChurchProfileScreen extends StatelessWidget {
  const ChurchProfileScreen({super.key, required this.profile});

  final RunnerProfile profile;

  /// "Weekly · Sun" / "Weekly · Mon, Wed, Fri" / "Daily" — the schedule as the
  /// Runners who receive this rhythm will see it.
  static String _scheduleLabel(DnaRhythm rhythm) {
    if (rhythm.frequency != RuleFrequency.weekly) return rhythm.frequency.label;
    final days = [
      for (final weekday in weekdayOrder)
        if (rhythm.weeklyDays.contains(weekday)) weekdayShortLabel(weekday),
    ];
    return days.isEmpty ? 'Weekly' : 'Weekly · ${days.join(', ')}';
  }

  /// Retiring, not deleting: the church stops measuring the rhythm and stops
  /// giving it to new members, but nobody's copy or history is taken away —
  /// each member's becomes their own rhythm, open for a week to keep or let
  /// go (see RunnerProfile.retireDnaRhythm).
  Future<void> _confirmRetire(BuildContext context, DnaRhythm rhythm) async {
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Retire DNA Rhythm?',
      message: '"${rhythm.title}" leaves the church list: it stops being measured for the '
          'congregation and is no longer given to new members. Everyone who has it keeps '
          'it as their own rhythm, with their history, free to continue or remove it. '
          'This cannot be undone from here.',
      confirmLabel: 'Retire',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      final released = await profile.retireDnaRhythm(rhythm);
      if (!context.mounted) return;
      showBookplateNotice(
        context,
        released == null
            ? '"${rhythm.title}" retired.'
            : released == 1
                ? '"${rhythm.title}" retired. One member keeps it as their own rhythm.'
                : '"${rhythm.title}" retired. $released members keep it as their own rhythm.',
      );
    } catch (_) {
      if (context.mounted) showBookplateNotice(context, "Couldn't retire that rhythm. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // TrellisScaffold, like every other pushed screen: the same parchment,
    // corner vines, vine-safe app bar and insets. (This screen used to build
    // its own bare Scaffold, which left it the one page without the vines and
    // with its header sitting higher than everywhere else.)
    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'Church Profile'),
      body: ListenableBuilder(
        listenable: profile,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('DNA Rhythms', style: textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Practices your whole flock shares — measured together, for a season or '
              "year-round, and placed on every member's Rule of Life now and as they join.",
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            if (profile.dnaRhythms.isEmpty)
              _Plate(
                child: Text(
                  'No DNA Rhythms yet. Add your first below — it is placed on the Rule of '
                  'Life of every Runner in your church.',
                  style: textTheme.bodyMedium,
                ),
              )
            else
              for (final rhythm in profile.dnaRhythms) ...[
                _Plate(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rhythm.title, style: textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${rhythm.category.label} · ${_scheduleLabel(rhythm)}'
                        '${rhythm.endsOn == null ? '' : ' · ${rhythm.seasonLabel}'}',
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      // Wrap, not Row: the two buttons stack rather than
                      // overflow at a large text size.
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          BookplateButton(
                            label: 'Edit',
                            compact: true,
                            variant: BookplateButtonVariant.secondary,
                            onPressed: () =>
                                showDnaRhythmDialog(context, profile, existing: rhythm),
                          ),
                          BookplateButton(
                            label: 'Retire',
                            compact: true,
                            variant: BookplateButtonVariant.danger,
                            onPressed: () => _confirmRetire(context, rhythm),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 12),
            BookplateButton(
              label: 'Add DNA Rhythm',
              variant: BookplateButtonVariant.secondary,
              onPressed: () => showDnaRhythmDialog(context, profile),
            ),
          ],
        ),
      ),
    );
  }
}

/// The parchment plate each rhythm (and the empty state) is cut from.
class _Plate extends StatelessWidget {
  const _Plate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.vellum,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
