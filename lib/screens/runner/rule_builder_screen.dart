import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/rule_item.dart';
import '../../models/runner_profile.dart';
import '../../services/analytics_service.dart';
import '../../services/share_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_chip.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_time_picker.dart';
import '../../widgets/brass_chevron.dart';
import '../../widgets/brass_lock.dart';
import '../../widgets/custom_toggle.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/trellis_scaffold.dart';

/// The master pre-set list of rhythms per category, shown as chips in the
/// Add Rhythm dialog for anyone building or extending their Rule of Life
/// from scratch. All hard-coded in positive, Title Case format.
const _rhythmPresets = {
  RuleCategory.abidingPrayer: [
    'Read Scripture for 15 Minutes',
    'Pray Through the Daily Burdens List',
    'Practice Solitude and Silence (15+ Minutes)',
    'Listen to the Bible on Audio',
    'Journal Prayers or Reflections',
    'Memorize One Bible Verse a Week',
  ],
  RuleCategory.marriageFamily: [
    'Have a Tech-Free Family Dinner',
    'Pray with My Spouse',
    'Pray Over the Kids',
    'Have a Weekly Date Night',
    'Lead a Family Devotional/Catechism',
    'Verbally Encourage My Spouse',
  ],
  RuleCategory.bodyPurity: [
    'Maintain Sexual Purity in Thought and Deed',
    'Fast from Food for 24 Hours',
    'Fast from Food for One Meal',
    'Exercise for 30 Minutes',
    'Get 7+ Hours of Sleep',
    'Abstain from Alcohol',
  ],
  RuleCategory.workRest: [
    'Observe a 24-Hour Sabbath',
    'No Checking Work Email After Hours',
    'Practice Complete Integrity in the Workplace',
    'Take a Lunch Break Away from the Desk',
    'Keep the Phone Out of the Bedroom at Night',
    'Limit Screen Time to Under 2 Hours',
  ],
  RuleCategory.communityHospitality: [
    'Gather with the Local Church for Corporate Worship',
    'Give at Least 10% of Income to the Local Church',
    'Attend a Small Group / Community Group',
    'Host Someone in the Home for a Meal',
    'Mentor or Disciple a Younger Believer',
    'Initiate a Conversation to Avoid Isolation',
  ],
};

/// Where a Runner builds their Rule of Life: rhythms grouped by category,
/// each with a frequency, optional weekly days, and an Anchor Rhythm flag.
class RuleBuilderScreen extends StatelessWidget {
  const RuleBuilderScreen({super.key, required this.profile});

  final RunnerProfile profile;

  Future<void> _pickReminderTime(BuildContext context) async {
    final time = await showBookplateTimePicker(
      context,
      initialTime: profile.dailyCheckInReminder,
      title: 'Daily Check-In Reminder',
    );
    if (time == null || !context.mounted) return;
    await runWithFailureNotice(
      context,
      () => profile.setDailyCheckInReminder(time),
      failure: "Couldn't save your reminder time. Check your connection.",
    );
  }

  Future<void> _showAddItemDialog(BuildContext context, RuleCategory category) async {
    final titleController = TextEditingController();
    var frequency = RuleFrequency.daily;
    final weeklyDays = <int>{};
    var isAnchor = false;
    String? error;

    final confirmed = await showBookplateForm<bool>(
      context,
      title: 'Add to ${category.label}',
      bodyBuilder: (dialogContext, setDialogState) {
        final textTheme = Theme.of(dialogContext).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in _rhythmPresets[category] ?? const [])
                  BookplateChip(
                    label: preset,
                    selected: false,
                    compact: true,
                    onTap: () => setDialogState(() => titleController.text = preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Rhythm',
                hintText: 'e.g. pray for 15 minutes',
                helperText: 'Frame your rhythm positively (e.g., "Maintain purity", not '
                    '"Did I view porn?") so that checking "Yes" always means growth.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text('Frequency', style: textTheme.labelLarge),
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Anchor Rhythm', style: textTheme.titleMedium),
                      Text(
                        'Missing this notifies your Witness immediately.',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CustomToggle(
                  semanticLabel: 'Anchor Rhythm',
                  value: isAnchor,
                  onChanged: (value) => setDialogState(() => isAnchor = value),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta)),
            ],
          ],
        );
      },
      actionsBuilder: (dialogContext, setDialogState) => [
        BookplateButton(
          label: 'Add',
          onPressed: () {
            if (titleController.text.trim().isEmpty) {
              setDialogState(() => error = 'Give the rhythm a name.');
              return;
            }
            // A weekly rhythm with no days is never due: it could never be
            // met or missed, which is no rhythm at all.
            if (frequency == RuleFrequency.weekly && weeklyDays.isEmpty) {
              setDialogState(() => error = 'Choose at least one day of the week.');
              return;
            }
            Navigator.of(dialogContext).pop(true);
          },
        ),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.secondary,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
      ],
    );

    // Read what was typed, then release the controller once the dialog's
    // closing fade (which still builds the field) has finished.
    final title = titleController.text.trim();
    disposeAfterBookplateClose([titleController]);

    if (confirmed != true) return;
    try {
      await profile.addRuleItem(
        category: category,
        title: title,
        frequency: frequency,
        weeklyDays: weeklyDays,
        isAnchorRhythm: isAnchor,
      );
    } catch (_) {
      if (context.mounted) showBookplateNotice(context, "Couldn't add that rhythm. Try again.");
    }
  }

  Future<void> _commitRule(BuildContext context) async {
    if (profile.ruleItems.isEmpty) {
      showBookplateNotice(context, 'Add at least one rhythm before committing.');
      return;
    }

    final String code;
    try {
      code = await profile.commitRuleOfLife();
    } catch (_) {
      if (context.mounted) {
        showBookplateNotice(context, "Couldn't commit your Rule of Life. Try again.");
      }
      return;
    }
    AnalyticsService.logRuleUpdated(activeRhythmCount: profile.ruleItems.length);
    if (!context.mounted) return;

    await showBookplateForm<void>(
      context,
      title: 'Your Rule of Life is Set',
      message: "You're starting a 14-day free trial of The Trellis (\$12/yr after). "
          'Cancel anytime from Settings — you will not be charged until your trial ends.',
      bodyBuilder: (dialogContext, setDialogState) {
        final textTheme = Theme.of(dialogContext).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Share this pairing code with your first Witness:',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // One line always — shrinks to fit a narrow phone or a large
            // text size rather than breaking the code in two.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                code,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: textTheme.displaySmall?.copyWith(
                  letterSpacing: 4,
                  color: AppColors.forestGreen,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Wrap, not Row: the two buttons stack instead of overflowing
            // when the dialog is narrow or the text is large.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                BookplateButton(
                  label: 'Copy Code',
                  compact: true,
                  variant: BookplateButtonVariant.secondary,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (dialogContext.mounted) {
                      showBookplateNotice(dialogContext, 'Pairing code copied.');
                    }
                  },
                ),
                Builder(
                  builder: (buttonContext) => BookplateButton(
                    label: 'Share',
                    compact: true,
                    variant: BookplateButtonVariant.secondary,
                    onPressed: () => shareText(
                      buttonContext,
                      'Join me on The Trellis as my Witness. '
                      'Use pairing code $code to connect.',
                      subject: 'Be my Witness on The Trellis',
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
      actionsBuilder: (dialogContext, setDialogState) => [
        BookplateButton(label: 'Done', onPressed: () => Navigator.of(dialogContext).pop()),
      ],
    );

    // Done (or tapping away) both return to the previous screen.
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      // BookplateAppBar, not a bare AppBar: a bare one draws Material's stock
      // back arrow on this pushed screen.
      appBar: const BookplateAppBar(title: 'Rule of Life'),
      body: ListenableBuilder(
        listenable: profile,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Craft Your Rule of Life', style: textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'For centuries, Christians have created intentional patterns of '
              'living — a Rule of Life — to abide more fully in Christ. Build '
              'yours below, one rhythm at a time.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (profile.hasCommittedRule)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Your Rule of Life is committed — rhythms can be added, but removing one '
                  'or changing its Anchor status waits for your next Season Reset.',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.antiqueBrass,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            for (final category in RuleCategory.values) ...[
              _CategorySection(
                category: category,
                profile: profile,
                onAddItem: () => _showAddItemDialog(context, category),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            Text('Global Settings', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label: 'Change the daily check-in reminder time',
              child: GestureDetector(
              onTap: () => _pickReminderTime(context),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.vellum,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Daily Check-In Reminder Time', style: textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            profile.dailyCheckInReminder.format(context),
                            style: textTheme.bodyMedium?.copyWith(color: AppColors.antiqueBrass),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Change',
                      style: textTheme.labelLarge?.copyWith(color: AppColors.antiqueBrass),
                    ),
                  ],
                ),
              ),
              ),
            ),
            const SizedBox(height: 32),
            Center(child: _CommitButton(onCommit: () => _commitRule(context))),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// "Commit to My Rule of Life", with the busy state the commit needs: it mints
/// a pairing code and writes the commitment, so a second tap while the first
/// is still in flight must not mint a second code or open a second dialog.
class _CommitButton extends StatefulWidget {
  const _CommitButton({required this.onCommit});

  final Future<void> Function() onCommit;

  @override
  State<_CommitButton> createState() => _CommitButtonState();
}

class _CommitButtonState extends State<_CommitButton> {
  bool _busy = false;

  Future<void> _commit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onCommit();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientButton(label: 'Commit to My Rule of Life', busy: _busy, onPressed: _commit);
  }
}

/// One category's collapsible block: a parchment plate whose header (title,
/// count, a hand-drawn chevron) opens to the rhythms inside — built from
/// plain containers rather than Material's ExpansionTile.
class _CategorySection extends StatefulWidget {
  const _CategorySection({
    required this.category,
    required this.profile,
    required this.onAddItem,
  });

  final RuleCategory category;
  final RunnerProfile profile;
  final VoidCallback onAddItem;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final profile = widget.profile;
    final items = profile.ruleItems.where((item) => item.category == widget.category).toList();

    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: widget.category.label,
            child: GestureDetector(
              onTap: () => setState(() => _open = !_open),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                color: _open ? AppColors.antiqueBrass.withValues(alpha: 0.10) : Colors.transparent,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.category.label, style: textTheme.titleMedium),
                          Text(
                            items.isEmpty ? 'No rhythms yet' : '${items.length} rhythm(s)',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    BrassChevron(open: _open),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in items) ...[
                          _RuleItemTile(
                            item: item,
                            profile: profile,
                            isCommitted: profile.hasCommittedRule,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Align(
                          alignment: Alignment.centerLeft,
                          child: BookplateButton(
                            label: 'Add Rhythm',
                            compact: true,
                            variant: BookplateButtonVariant.secondary,
                            onPressed: widget.onAddItem,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _RuleItemTile extends StatelessWidget {
  const _RuleItemTile({required this.item, required this.profile, required this.isCommitted});

  final RuleItem item;
  final RunnerProfile profile;

  /// Once a Rule of Life is committed, a rhythm can't be deleted or have its
  /// Anchor status changed until the next Season Reset — closes the
  /// loophole where a Runner could quietly un-anchor a rhythm they're
  /// struggling with.
  final bool isCommitted;

  /// DNA Rhythms are locked from deletion/un-anchoring at all times —
  /// the Runner didn't choose them, so only their church can retire them.
  /// [_requestUnlock] is the one way out: asking a Witness to lift it.
  bool get _isLocked => isCommitted || item.isChurchMandated;

  /// Files a DNA Rhythm unlock request with one of this account's
  /// Witnesses — auto-picked when there's only one, otherwise the Runner
  /// chooses. See RunnerProfile.requestRuleItemUnlock.
  Future<void> _requestUnlock(BuildContext context) async {
    if (profile.witnesses.isEmpty) {
      showBookplateNotice(context, 'Add a Witness before requesting an unlock.');
      return;
    }

    var witnessId = profile.witnesses.length == 1 ? profile.witnesses.first.id : null;
    if (witnessId == null) {
      witnessId = await showBookplateChoice<String>(
        context,
        title: 'Ask which Witness?',
        options: [
          for (final witness in profile.witnesses) (label: witness.name, value: witness.id),
        ],
      );
      if (witnessId == null || !context.mounted) return;
    }

    try {
      await profile.requestRuleItemUnlock(item.id, witnessId);
    } catch (_) {
      if (context.mounted) {
        showBookplateNotice(context, "Couldn't send the unlock request. Try again.");
      }
      return;
    }
    if (!context.mounted) return;
    showBookplateNotice(context, 'Your Witness has been asked to approve unlocking this rhythm.');
  }

  /// Applies an edit to this rhythm, and says so if it didn't stick —
  /// [RunnerProfile.updateRuleItem] rolls the screen back and rethrows when
  /// the database refuses a write.
  Future<void> _edit(BuildContext context, void Function(RuleItem item) change) async {
    try {
      await profile.updateRuleItem(item.id, change);
    } catch (_) {
      if (context.mounted) showBookplateNotice(context, "Couldn't save that change. Try again.");
    }
  }

  /// Switching to weekly must land on a real day — a weekly rhythm with no
  /// days is never due, so it could never be met or missed.
  void _setFrequency(BuildContext context, RuleFrequency frequency) {
    _edit(context, (i) {
      i.frequency = frequency;
      if (frequency == RuleFrequency.weekly && i.weeklyDays.isEmpty) {
        i.weeklyDays = {DateTime.now().weekday};
      }
    });
  }

  void _toggleWeekday(BuildContext context, int weekday) {
    if (item.weeklyDays.length == 1 && item.weeklyDays.contains(weekday)) {
      showBookplateNotice(context, 'A weekly rhythm needs at least one day.');
      return;
    }
    _edit(context, (i) {
      if (!i.weeklyDays.add(weekday)) i.weeklyDays.remove(weekday);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // The double-line bookplate border (1px outer, 4px gap, 1px inner) used
    // for the role cards and sign-in panel, plus a soft diffused shadow, so
    // each rhythm reads as its own small elevated card rather than a flat
    // bordered box.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isChurchMandated ? AppColors.antiqueBrass : AppColors.antiqueBrass.withValues(alpha: 0.5),
          width: item.isChurchMandated ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.vellumBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A full-width Wrap rather than a Row: with room, the title sits
            // left and its action right, as before; on a narrow phone or at
            // a large text size the action drops beneath a title that keeps
            // the whole width — instead of the title being squeezed to a
            // few characters a line, or the row overflowing the card.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text(item.displayTitle, style: textTheme.titleMedium),
                  if (item.isChurchMandated)
                    profile.pendingUnlockRuleItemIds.contains(item.id)
                        ? Text(
                            'Pending Witness Approval',
                            style: textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: AppColors.antiqueBrass,
                            ),
                          )
                        : BookplateButton(
                            label: 'Request Unlock',
                            compact: true,
                            variant: BookplateButtonVariant.secondary,
                            onPressed: () => _requestUnlock(context),
                          )
                  else if (!_isLocked)
                    BookplateButton(
                      label: 'Remove',
                      compact: true,
                      variant: BookplateButtonVariant.danger,
                      onPressed: () async {
                        try {
                          await profile.removeRuleItem(item.id);
                        } catch (_) {
                          if (context.mounted) {
                            showBookplateNotice(context, "Couldn't remove that rhythm. Try again.");
                          }
                        }
                      },
                    ),
                ],
              ),
            ),
            if (item.isChurchMandated) ...[
              const SizedBox(height: 6),
              const Row(
                children: [
                  BrassLock(size: 16),
                  SizedBox(width: 8),
                  Flexible(
                    child: BookplateTag(
                      label: 'DNA Rhythm · Mandated',
                      color: AppColors.antiqueBrass,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text('Frequency', style: textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final frequency in RuleFrequency.values)
                  BookplateChip(
                    label: frequency.label,
                    selected: item.frequency == frequency,
                    compact: true,
                    enabled: !item.isChurchMandated,
                    onTap: () => _setFrequency(context, frequency),
                  ),
              ],
            ),
            if (item.frequency == RuleFrequency.weekly) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final weekday in weekdayOrder)
                    BookplateChip(
                      label: weekdayShortLabel(weekday),
                      selected: item.weeklyDays.contains(weekday),
                      compact: true,
                      enabled: !item.isChurchMandated,
                      onTap: () => _toggleWeekday(context, weekday),
                    ),
                ],
              ),
            ],
            if (item.isChurchMandated) ...[
              const SizedBox(height: 10),
              Text(
                'Set by your church. To change this schedule, ask a Witness to unlock it.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.antiqueBrass,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Text('Anchor Rhythm', style: textTheme.bodyMedium),
                  ),
                ),
                CustomToggle(
                  semanticLabel: 'Anchor Rhythm, ${item.displayTitle}',
                  value: item.isAnchorRhythm,
                  onChanged: _isLocked
                      ? null
                      : (value) => _edit(context, (i) => i.isAnchorRhythm = value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
