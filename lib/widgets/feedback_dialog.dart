import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../services/analytics_service.dart';
import '../services/feedback_service.dart';
import '../theme/app_colors.dart';
import 'bookplate_chip.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';

enum _FeedbackCategory { bug, spiritualFlow, uiUsability }

extension on _FeedbackCategory {
  String get label => switch (this) {
        _FeedbackCategory.bug => 'Bug',
        _FeedbackCategory.spiritualFlow => 'Spiritual Flow / Content',
        _FeedbackCategory.uiUsability => 'UI / Usability',
      };

  String get dbValue => switch (this) {
        _FeedbackCategory.bug => 'bug',
        _FeedbackCategory.spiritualFlow => 'spiritual_flow_content',
        _FeedbackCategory.uiUsability => 'ui_usability',
      };
}

/// Opens the beta feedback sheet — a rating, a category, and a free-text
/// note, dispatched to PostHog as `beta_feedback_submitted`. No account
/// identifier beyond [RunnerProfile.churchId] is ever attached.
Future<void> showFeedbackDialog(BuildContext context, RunnerProfile profile) {
  return showBookplateSheet<void>(
    context,
    builder: (sheetContext) => FeedbackDialog(profile: profile),
  );
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  int? _rating;
  _FeedbackCategory? _category;
  final _messageController = TextEditingController();
  bool _isSubmitting = false;

  /// Opt-in: lets support reply to the sender's account email. Off by default
  /// so feedback stays anonymous unless they choose otherwise.
  bool _replyOk = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _rating != null && _category != null && _messageController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      await FeedbackService.submit(
        rating: _rating!,
        category: _category!.dbValue,
        message: _messageController.text,
        replyOk: _replyOk,
        role: widget.profile.role.dbValue,
      );
    } on FeedbackException catch (error) {
      // Keep the sheet open with everything they typed so nothing is lost.
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showBookplateNotice(context, error.message);
      return;
    }

    // Analytics learns only that it happened (no note text).
    AnalyticsService.logFeedbackSubmitted(
      rating: _rating!,
      category: _category!.dbValue,
      churchId: widget.profile.churchId,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    showBookplateNotice(context, 'Thank you for tending the Trellis.');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // showBookplateSheet already supplies the parchment panel, padding, safe
    // area, keyboard inset and scrolling.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tend the Trellis', style: textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Your note goes straight to our team. We attach no name or email unless you ask '
          'us to reply.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Text('How is it going?', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              Expanded(
                child: Center(
                  // The chosen rating is otherwise shown by colour alone.
                  child: Semantics(
                    selected: _rating == i,
                    child: BrassGlyphButton(
                      kind: BrassGlyphKind.leaf,
                      semanticLabel: 'Rate $i of 5',
                      onPressed: () => setState(() => _rating = i),
                      color: (_rating ?? 0) >= i
                          ? AppColors.antiqueBrass
                          : AppColors.forestGreen.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('What is this about?', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in _FeedbackCategory.values)
              BookplateChip(
                label: category.label,
                selected: _category == category,
                onTap: () => setState(() => _category = category),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Tell us more', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _messageController,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'What did you notice?'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        BookplateCheckboxRow(
          value: _replyOk,
          onChanged: _isSubmitting ? null : (value) => setState(() => _replyOk = value),
          label: Text(
            'You may reply to me at my account email.',
            style: textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        BookplateButton(
          onPressed: _canSubmit && !_isSubmitting ? _submit : null,
          busy: _isSubmitting,
          label: _isSubmitting ? 'Sending…' : 'Submit Feedback',
        ),
      ],
    );
  }
}
