import 'package:flutter/material.dart';

import '../../models/rule_item.dart';
import '../../models/rule_of_life_baseline.dart';
import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/trellis_scaffold.dart';
import 'rule_builder_screen.dart';

/// "Let's create your Rule of Life for this season": the first thing a new
/// Runner sees after the welcome deck, and where the Rule of Life tab sends
/// anyone who hasn't built one yet.
///
/// One decision, plainly put: start from a ready-made Rule fitted to a season
/// of life (each shows exactly what is in it), or build your own. Either way
/// the Rule Builder opens next, where everything can be changed before
/// committing. Any DNA Rhythms the Runner's church shares are already in their
/// Rule, and the screen says so.
class ChooseRuleScreen extends StatefulWidget {
  const ChooseRuleScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<ChooseRuleScreen> createState() => _ChooseRuleScreenState();
}

class _ChooseRuleScreenState extends State<ChooseRuleScreen> {
  /// The template being applied, so its button shows busy and the others wait.
  RuleOfLifeBaseline? _applying;

  RunnerProfile get _profile => widget.profile;

  void _openBuilder() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => RuleBuilderScreen(profile: _profile)),
    );
  }

  /// Adds the template's rhythms the Runner doesn't already have (by title),
  /// then opens the builder. A failed save says so and stays here.
  Future<void> _use(RuleOfLifeBaseline baseline) async {
    if (_applying != null) return;
    final existing = {for (final item in _profile.ruleItems) item.title.trim().toLowerCase()};
    final fresh = [
      for (final item in baseline.items)
        if (!existing.contains(item.title.trim().toLowerCase())) item,
    ];

    if (fresh.isNotEmpty) {
      setState(() => _applying = baseline);
      final saved = await runWithFailureNotice(
        context,
        () => _profile.applyRuleOfLifeBaseline(fresh),
        failure: "Couldn't add that Rule. Check your connection and try again.",
      );
      if (!mounted) return;
      setState(() => _applying = null);
      if (!saved) return;
    }
    _openBuilder();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dnaRhythms = _profile.ruleItems.where((item) => item.isChurchMandated).toList();
    final hasOwnRhythms = _profile.ruleItems.any((item) => !item.isChurchMandated);

    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'Your Rule of Life'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Let's create your Rule of Life for this season.", style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Start from a Rule made for your season of life, or build your own. You can change '
            'anything before you commit.',
            style: textTheme.bodyMedium,
          ),
          if (dnaRhythms.isNotEmpty) ...[
            const SizedBox(height: 16),
            BookplatePlate(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrassGlyph(BrassGlyphKind.people, size: 20, color: AppColors.antiqueBrass),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Already included from your church: '
                      '${dnaRhythms.map((item) => item.displayTitle).join(', ')}.',
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasOwnRhythms) ...[
            const SizedBox(height: 12),
            BookplateButton(
              label: 'Keep the rhythms I already have',
              variant: BookplateButtonVariant.link,
              compact: true,
              onPressed: _applying == null ? _openBuilder : null,
            ),
          ],
          const SizedBox(height: 20),
          for (final baseline in ruleOfLifeBaselines) ...[
            _TemplateCard(
              baseline: baseline,
              busy: _applying == baseline,
              enabled: _applying == null,
              onUse: () => _use(baseline),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          BookplatePlate(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Build Your Own', style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Start blank: add rhythms to practice and sins to throw off, one at a time.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                BookplateButton(
                  label: 'Build my own',
                  variant: BookplateButtonVariant.secondary,
                  onPressed: _applying == null ? _openBuilder : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: BookplateButton(
              label: 'Not now',
              variant: BookplateButtonVariant.link,
              compact: true,
              onPressed: _applying == null ? () => Navigator.of(context).pop() : null,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// One ready-made Rule: its name, who it is for, and every rhythm in it.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.baseline,
    required this.busy,
    required this.enabled,
    required this.onUse,
  });

  final RuleOfLifeBaseline baseline;
  final bool busy;
  final bool enabled;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final practices = baseline.items.where((item) => !item.isThrowOff).toList();
    final throwOffs = baseline.items.where((item) => item.isThrowOff).toList();

    Widget line(BaselineRuleItem item) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: BrassGlyph(
                  item.isThrowOff ? BrassGlyphKind.close : BrassGlyphKind.leaf,
                  size: 12,
                  color: item.isThrowOff ? AppColors.terracotta : AppColors.antiqueBrass,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.isAnchorRhythm ? '${item.summary} · Anchor' : item.summary,
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );

    return BookplatePlate(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(baseline.name, style: textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            baseline.tagline,
            style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
          for (final item in practices) line(item),
          for (final item in throwOffs) line(item),
          const SizedBox(height: 12),
          BookplateButton(
            label: 'Start with this Rule',
            busy: busy,
            onPressed: enabled ? onUse : null,
          ),
        ],
      ),
    );
  }
}

/// Opens [ChooseRuleScreen] for [profile] — the Runner's first step.
Future<void> openChooseRule(BuildContext context, RunnerProfile profile) =>
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ChooseRuleScreen(profile: profile)),
    );

/// Whether a rhythm is one the Runner can simply keep — used by callers that
/// decide whether to offer the chooser at all.
bool hasOwnRule(RunnerProfile profile) =>
    profile.hasCommittedRule || profile.ruleItems.any((RuleItem item) => !item.isChurchMandated);
