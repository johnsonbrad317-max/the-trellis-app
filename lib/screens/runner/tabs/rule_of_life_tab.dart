import 'package:flutter/material.dart';

import '../../../models/rule_item.dart';
import '../../../models/rule_of_life_baseline.dart';
import '../../../models/runner_profile.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/bookplate_dialog.dart';
import '../../../widgets/bookplate_plate.dart';
import '../../../widgets/gradient_button.dart';
import '../daily_checkin_screen.dart';
import '../rule_builder_screen.dart';

class RuleOfLifeTab extends StatelessWidget {
  const RuleOfLifeTab({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (!profile.hasCommittedRule || profile.ruleItems.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 40),
            Text('Anchor Your Days', style: textTheme.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Step out of the drift. Craft a Rule of Life to build intentional, daily '
              'rhythms for spiritual growth.',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('1-Click Baselines', style: textTheme.titleLarge),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Start from a rhythm suited to your season — you can adjust everything '
                'before committing.',
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              // 220 at the default text size; grows with the reader's text
              // scale so a card's title, count and button never overflow it.
              height: 130 + MediaQuery.textScalerOf(context).scale(90),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ruleOfLifeBaselines.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _BaselineCard(
                  baseline: ruleOfLifeBaselines[index],
                  profile: profile,
                ),
              ),
            ),
            const SizedBox(height: 24),
            BookplateButton(
              // A Runner seeded with a baseline at sign-up already has
              // rhythms waiting, uncommitted — say so rather than "scratch".
              label: profile.ruleItems.isEmpty
                  ? 'Or start from scratch'
                  : 'Or review the rhythms you already have (${profile.ruleItems.length})',
              variant: BookplateButtonVariant.link,
              compact: true,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => RuleBuilderScreen(profile: profile)),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your Rule of Life', style: textTheme.headlineMedium),
          const SizedBox(height: 16),
          // Only categories that hold a rhythm — an empty one would leave
          // nothing but its 12px gap behind.
          for (final category in RuleCategory.values)
            if (profile.ruleItems.any((item) => item.category == category)) ...[
              _CategorySummary(category: category, profile: profile),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 12),
          GradientButton(
            label: "Today's Check-In",
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => DailyCheckInScreen(profile: profile)),
            ),
          ),
          const SizedBox(height: 8),
          BookplateButton(
            label: 'Edit Rule of Life',
            variant: BookplateButtonVariant.secondary,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => RuleBuilderScreen(profile: profile)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BaselineCard extends StatefulWidget {
  const _BaselineCard({required this.baseline, required this.profile});

  final RuleOfLifeBaseline baseline;
  final RunnerProfile profile;

  @override
  State<_BaselineCard> createState() => _BaselineCardState();
}

class _BaselineCardState extends State<_BaselineCard> {
  bool _applying = false;

  /// Adds this baseline's rhythms, then opens the builder to adjust them.
  ///
  /// Only rhythms the Runner doesn't already have are added: a new Runner is
  /// seeded with a baseline at sign-up, so applying one here again (or a
  /// second baseline that overlaps the first) would otherwise write every
  /// shared rhythm twice. And the builder opens only once the rhythms are
  /// really saved — a failed save says so instead of showing an empty Rule.
  Future<void> _use() async {
    if (_applying) return;
    final profile = widget.profile;
    final existing = {for (final item in profile.ruleItems) item.title.trim().toLowerCase()};
    final fresh = [
      for (final item in widget.baseline.items)
        if (!existing.contains(item.title.trim().toLowerCase())) item,
    ];

    if (fresh.isNotEmpty) {
      setState(() => _applying = true);
      final saved = await runWithFailureNotice(
        context,
        () => profile.applyRuleOfLifeBaseline(fresh),
        failure: "Couldn't add that baseline. Check your connection and try again.",
      );
      if (!mounted) return;
      setState(() => _applying = false);
      if (!saved) return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => RuleBuilderScreen(profile: profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final baseline = widget.baseline;

    return SizedBox(
      width: 240,
      child: BookplatePlate(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(baseline.name, style: textTheme.titleMedium),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                baseline.tagline,
                style: textTheme.bodySmall,
                overflow: TextOverflow.fade,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${baseline.items.length} rhythms',
              style: textTheme.labelSmall?.copyWith(color: AppColors.antiqueBrass),
            ),
            const SizedBox(height: 8),
            BookplateButton(
              label: 'Use This Baseline',
              variant: BookplateButtonVariant.secondary,
              busy: _applying,
              onPressed: _use,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySummary extends StatelessWidget {
  const _CategorySummary({required this.category, required this.profile});

  final RuleCategory category;
  final RunnerProfile profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final count = profile.ruleItems.where((item) => item.category == category).length;
    if (count == 0) return const SizedBox.shrink();

    return BookplatePlate(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: BookplateRow(
        title: category.label,
        trailing: Text('$count', style: textTheme.titleMedium),
      ),
    );
  }
}
