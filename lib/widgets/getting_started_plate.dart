import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../screens/runner/choose_rule_screen.dart';
import '../screens/runner/daily_checkin_screen.dart';
import '../screens/runner/rule_builder_screen.dart';
import '../theme/app_colors.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';
import 'witness_code_dialog.dart';

/// One step of [GettingStartedPlate].
@immutable
class GettingStartedStep {
  const GettingStartedStep({
    required this.title,
    required this.detail,
    required this.done,
    required this.available,
  });

  final String title;
  final String detail;
  final bool done;

  /// False while an earlier step must come first (no check-in before the
  /// Rule of Life is committed).
  final bool available;
}

/// The three steps every new Runner takes, in order: choose and commit a Rule
/// of Life, invite a Witness, make the first check-in. Pure, for tests.
List<GettingStartedStep> gettingStartedSteps({
  required bool hasCommittedRule,
  required bool hasOwnRhythms,
  required bool hasWitness,
  required bool hasCheckedIn,
}) =>
    [
      GettingStartedStep(
        title: 'Choose your Rule of Life',
        detail: hasCommittedRule
            ? 'Committed.'
            : hasOwnRhythms
                ? 'Your rhythms are waiting — review them and commit.'
                : 'Start from a ready-made Rule or build your own.',
        done: hasCommittedRule,
        available: true,
      ),
      GettingStartedStep(
        title: 'Invite a Witness',
        detail: hasWitness
            ? 'Someone is walking alongside you.'
            : 'Send a pairing key to someone you trust to walk alongside you.',
        done: hasWitness,
        available: true,
      ),
      GettingStartedStep(
        title: 'Make your first check-in',
        detail: hasCheckedIn
            ? 'Done — your vine has begun.'
            : hasCommittedRule
                ? 'Each morning, a yes or no for each rhythm, about yesterday.'
                : 'Opens once your Rule of Life is committed.',
        done: hasCheckedIn,
        available: hasCommittedRule,
      ),
    ];

/// "Getting Started" at the top of a new Runner's dashboard: the three steps
/// with what each one does, each tappable straight into it. Disappears for
/// good once all three are done. Nothing else is added to the screen — the
/// point is one obvious next thing to do.
class GettingStartedPlate extends StatelessWidget {
  const GettingStartedPlate({super.key, required this.profile});

  final RunnerProfile profile;

  /// Whether there is anything left to show.
  static bool isNeeded(RunnerProfile profile) =>
      _steps(profile).any((step) => !step.done);

  static List<GettingStartedStep> _steps(RunnerProfile profile) => gettingStartedSteps(
        hasCommittedRule: profile.hasCommittedRule,
        hasOwnRhythms: profile.ruleItems.any((item) => !item.isChurchMandated),
        hasWitness: profile.witnesses.isNotEmpty,
        hasCheckedIn: profile.checkInHistory.isNotEmpty,
      );

  void _open(BuildContext context, int index) {
    final navigator = Navigator.of(context);
    switch (index) {
      case 0:
        navigator.push(
          MaterialPageRoute(
            builder: (context) => hasOwnRule(profile)
                ? RuleBuilderScreen(profile: profile)
                : ChooseRuleScreen(profile: profile),
          ),
        );
      case 1:
        showWitnessCodeDialog(context, profile);
      case 2:
        navigator.push(
          MaterialPageRoute(builder: (context) => DailyCheckInScreen(profile: profile)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final steps = _steps(profile);
    final remaining = steps.where((step) => !step.done).length;

    return BookplatePlate(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Getting Started', style: textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            remaining == 1 ? 'One step left.' : '$remaining steps to begin.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.antiqueBrass),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              number: i + 1,
              step: steps[i],
              onTap: steps[i].done || !steps[i].available ? null : () => _open(context, i),
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.step, required this.onTap});

  final int number;
  final GettingStartedStep step;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = step.done || !step.available;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A numbered brass ring, or a tick once done.
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: step.done ? AppColors.forestGreen : AppColors.parchmentLight,
              border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
            ),
            child: step.done
                ? const BrassGlyph(BrassGlyphKind.check, size: 14, color: AppColors.parchmentLight)
                : Text(
                    '$number',
                    style: textTheme.labelLarge?.copyWith(color: AppColors.forestGreen),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: textTheme.titleMedium?.copyWith(
                    color: muted ? AppColors.forestGreen.withValues(alpha: 0.55) : null,
                    decoration: step.done ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.antiqueBrass,
                  ),
                ),
                const SizedBox(height: 2),
                Text(step.detail, style: textTheme.bodySmall),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: BrassGlyph(BrassGlyphKind.forward, size: 18),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: '${step.title}. ${step.detail}',
      excludeSemantics: true,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row),
    );
  }
}
