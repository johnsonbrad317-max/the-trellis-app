import 'package:flutter/material.dart';

import '../../models/rule_item.dart';
import '../../models/runner_profile.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/trellis_scaffold.dart';

/// A short retrospective on yesterday: every rhythm scheduled for that date
/// gets a Yes/No answer, then Anchor Rhythm misses are called out before
/// submitting.
class DailyCheckInScreen extends StatefulWidget {
  const DailyCheckInScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<DailyCheckInScreen> createState() => _DailyCheckInScreenState();
}

class _DailyCheckInScreenState extends State<DailyCheckInScreen> {
  late final DateTime _yesterday;
  late final List<RuleItem> _dueItems;
  final Map<String, bool> _responses = {};

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    _yesterday = startOfToday.subtract(const Duration(days: 1));
    _dueItems = widget.profile.ruleItems.where((item) => item.scheduledFor(_yesterday)).toList();
  }

  bool get _missedAnchor =>
      _dueItems.any((item) => item.isAnchorRhythm && _responses[item.id] == false);

  bool get _allAnswered => _dueItems.every((item) => _responses.containsKey(item.id));

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// True from the confirm prompt until the write lands — a second tap on
  /// Submit while the first is still in flight would otherwise submit again
  /// and pop twice (taking the shell with it).
  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_allAnswered) {
      showBookplateNotice(context, 'Answer every rhythm before submitting.');
      return;
    }

    setState(() => _submitting = true);
    var submitted = false;
    try {
      submitted = await _confirmAndSubmit();
    } finally {
      // After a successful submit the screen is already closing — stay busy
      // rather than re-arm the button for the length of the exit transition.
      if (mounted && !submitted) setState(() => _submitting = false);
    }
  }

  /// Resolves to true once the check-in is saved (and this screen popped).
  Future<bool> _confirmAndSubmit() async {
    final missedAnchor = _missedAnchor;

    final confirmed = await showBookplateConfirm(
      context,
      title: missedAnchor ? 'Anchor Rhythm Missed' : 'Check-In Ready',
      message: missedAnchor
          ? 'An Anchor Rhythm was missed. Your Witness will be gently notified so they '
              "can support you — not to keep score."
          : 'Responses will be included in your weekly Witness roll-up.',
      confirmLabel: 'Submit',
      cancelLabel: 'Go Back',
    );

    if (!confirmed || !mounted) return false;

    try {
      await widget.profile.recordCheckIn(_yesterday, Map.of(_responses));
      for (final item in _dueItems) {
        if (_responses[item.id] == true) {
          AnalyticsService.logRhythmCompleted(
            category: item.category.dbValue,
            isDnaRhythm: item.isChurchMandated,
          );
        }
      }
    } catch (_) {
      if (!mounted) return false;
      showBookplateNotice(context, "Network error — couldn't submit your check-in. Try again.");
      return false;
    }
    if (!mounted) return true;

    // The notice lives on the root overlay, so it outlasts this route.
    showBookplateNotice(
      context,
      missedAnchor
          ? 'Check-in submitted. Your Witness has been notified.'
          : 'Check-in submitted.',
    );
    Navigator.of(context).pop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'Daily Check-In'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Looking back on ${_formatDate(_yesterday)}', style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('A short retrospective — how did yesterday go?', style: textTheme.bodyMedium),
          const SizedBox(height: 24),
          if (_dueItems.isEmpty)
            BookplatePlate(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Nothing was scheduled for yesterday. Come back tomorrow.',
                style: textTheme.bodyMedium,
              ),
            )
          else ...[
            for (final item in _dueItems) ...[
              _CheckInQuestion(
                item: item,
                value: _responses[item.id],
                onChanged: (value) {
                  // Answers are frozen once the check-in is on its way.
                  if (!_submitting) setState(() => _responses[item.id] = value);
                },
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            GradientButton(label: 'Submit Check-In', busy: _submitting, onPressed: _submit),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CheckInQuestion extends StatelessWidget {
  const _CheckInQuestion({required this.item, required this.value, required this.onChanged});

  final RuleItem item;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BookplatePlate(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.checkInPrompt, style: textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AnswerButton(
                  label: 'Yes',
                  color: AppColors.forestGreen,
                  selected: value == true,
                  onPressed: () => onChanged(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AnswerButton(
                  label: 'No',
                  color: AppColors.terracotta,
                  selected: value == false,
                  onPressed: () => onChanged(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A Yes/No answer: parchment with coloured lettering and border until it is
/// chosen, then filled solid in its colour with parchment lettering.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color : AppColors.parchmentLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 1.2),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? AppColors.parchmentLight : color,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
          ),
        ),
      ),
    );
  }
}
