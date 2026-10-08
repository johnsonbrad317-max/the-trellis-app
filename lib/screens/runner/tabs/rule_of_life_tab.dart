import 'package:flutter/material.dart';

import '../../../models/rule_item.dart';
import '../../../models/runner_profile.dart';
import '../../../widgets/bookplate_dialog.dart';
import '../../../widgets/bookplate_plate.dart';
import '../../../widgets/gradient_button.dart';
import '../choose_rule_screen.dart';
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
            // One clear way in: the chooser shows each ready-made Rule with
            // everything in it, and "Build my own" — the old carousel here
            // asked a new Runner to compare seven cards sideways.
            GradientButton(
              label: profile.ruleItems.isEmpty ? 'Create My Rule of Life' : 'Continue My Rule of Life',
              onPressed: () => profile.ruleItems.any((item) => !item.isChurchMandated)
                  ? Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => RuleBuilderScreen(profile: profile)),
                    )
                  : openChooseRule(context, profile),
            ),
            const SizedBox(height: 12),
            Text(
              'Start from a Rule made for your season of life, or build your own.',
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
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
            label: profile.checkInFor(DateTime.now().subtract(const Duration(days: 1))) == null
                ? "Today's Check-In"
                : "View Today's Check-In",
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
