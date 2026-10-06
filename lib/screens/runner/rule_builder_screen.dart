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

  /// Where a committed Rule of Life stands: still in its first week (free to
  /// adjust), or set (changes need a Witness). Adding is always open.
  static String _committedNote(RunnerProfile profile) {
    final settlesAt = profile.ruleSettlesAt;
    if (settlesAt != null) {
      return 'Your Rule of Life is committed. Until ${_formatDay(settlesAt)}, you can still '
          'change or remove any rhythm freely. After that, changing or removing one needs '
          "your Witness's approval. You can always add a rhythm.";
    }
    if (profile.witnesses.isEmpty) {
      return 'Your Rule of Life is committed. You can always add a rhythm — and with no '
          'Witness yet, you can still change one yourself.';
    }
    return 'Your Rule of Life is set. You can always add a rhythm; changing or removing one '
        'needs your Witness\'s approval (a rhythm added later has its own first week).';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDay(DateTime date) => '${_months[date.month - 1]} ${date.day}';

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
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
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
              Row(
                children: [
                  for (final weekday in weekdayOrder)
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: BookplateChip(
                          label: weekdayShortLabel(weekday),
                          selected: weeklyDays.contains(weekday),
                          compact: true,
                          onTap: () => setDialogState(() {
                            if (!weeklyDays.add(weekday)) weeklyDays.remove(weekday);
                          }),
                        ),
                      ),
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

  /// Adding a sin to throw off (Hebrews 12:1): the blank in "Avoid ___",
  /// always daily, optionally an Anchor. Every throw-off is filed under Body &
  /// Purity in the database (a rhythm must have a category; this one is not
  /// shown for throw-offs, which have their own section).
  Future<void> _showAddThrowOffDialog(BuildContext context) async {
    final titleController = TextEditingController();
    var isAnchor = false;
    String? error;

    final confirmed = await showBookplateForm<bool>(
      context,
      title: 'A Sin to Throw Off',
      message: '"Let us throw off everything that hinders and the sin that so easily '
          'entangles." Name it plainly; each day you\'ll be asked whether you avoided it.',
      bodyBuilder: (dialogContext, setDialogState) {
        final textTheme = Theme.of(dialogContext).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in throwOffPresets)
                  BookplateChip(
                    label: preset,
                    selected: titleController.text == preset,
                    compact: true,
                    onTap: () => setDialogState(() => titleController.text = preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              autofocus: true,
              // A phrase mid-sentence ("Avoid looking at…"), so no capital.
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Avoid…',
                prefixText: 'Avoid ',
                hintText: 'looking at pornography',
                helperText: 'Checked every day. "Yes" means you avoided it.',
              ),
              onChanged: (_) => setDialogState(() {}),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Anchor Rhythm', style: textTheme.titleMedium),
                      Text(
                        'A fall here notifies your Witness immediately.',
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
              setDialogState(() => error = 'Name the sin to throw off.');
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

    // Stored without the "Avoid": the model supplies it wherever it is shown.
    var title = titleController.text.trim();
    if (title.toLowerCase().startsWith('avoid ')) title = title.substring(6).trim();
    disposeAfterBookplateClose([titleController]);

    if (confirmed != true || title.isEmpty) return;
    try {
      await profile.addRuleItem(
        category: RuleCategory.bodyPurity,
        title: title,
        isAnchorRhythm: isAnchor,
        isThrowOff: true,
      );
    } catch (_) {
      if (context.mounted) showBookplateNotice(context, "Couldn't add that. Try again.");
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
      message: 'Your first week is a trial fit. Until '
          "${_formatDay(DateTime.now().add(ruleSettlePeriod))}, you can change or remove any "
          "rhythm as you learn what's realistic. After that, your Witness helps hold them in "
          'place.\n\n'
          "You're starting a 14-day free trial of The Trellis (\$12/yr after). "
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
                  _committedNote(profile),
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.antiqueBrass,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            if (profile.ruleSeasonReopenEndsAt != null) ...[
              SeasonReopenPlate(endsAt: profile.ruleSeasonReopenEndsAt!),
              const SizedBox(height: 16),
            ],
            // Hebrews 12:1 has two movements, and so does the Rule of Life:
            // what to put on, and what to throw off.
            Text('Rhythms to Practice', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Practices to put on — the race run with perseverance.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final category in RuleCategory.values) ...[
              _CategorySection(
                category: category,
                profile: profile,
                onAddItem: () => _showAddItemDialog(context, category),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            Text('Sins to Throw Off', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '"Everything that hinders and the sin that so easily entangles." Each is checked '
              'daily: did you avoid it?',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _ThrowOffSection(
              profile: profile,
              onAddItem: () => _showAddThrowOffDialog(context),
            ),
            const SizedBox(height: 24),
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
            // Committing happens once; afterwards the note at the top says
            // where things stand instead of offering the button again.
            if (!profile.hasCommittedRule) ...[
              const SizedBox(height: 32),
              Center(child: _CommitButton(onCommit: () => _commitRule(context))),
              const SizedBox(height: 12),
              // Said before the button is pressed, so the first-week rule is
              // never a surprise.
              Text(
                "After you commit, you'll have seven days to live with these rhythms and "
                'adjust them freely. After that, changing or removing a rhythm requires '
                "your Witness's approval first. Adding a rhythm is always open.",
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.forestGreen.withValues(alpha: 0.75),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
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
    // Throw-offs have their own section below the categories.
    final items = profile.ruleItems
        .where((item) => item.category == widget.category && !item.isThrowOff)
        .toList();

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
                            items.isEmpty
                                ? 'No rhythms yet'
                                : '${items.length} ${items.length == 1 ? 'rhythm' : 'rhythms'}',
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
                          _RuleItemTile(item: item, profile: profile),
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

/// The Runner's sins to throw off, as one open plate: each on its own tile
/// (frequency fixed at daily), and the button to name another.
class _ThrowOffSection extends StatelessWidget {
  const _ThrowOffSection({required this.profile, required this.onAddItem});

  final RunnerProfile profile;
  final VoidCallback onAddItem;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final items = profile.ruleItems.where((item) => item.isThrowOff).toList();

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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Nothing named yet. A sin named is a sin half thrown off — and your Witness '
                'will know what to pray for.',
                style: textTheme.bodySmall,
              ),
            )
          else
            for (final item in items) ...[
              _RuleItemTile(item: item, profile: profile),
              const SizedBox(height: 12),
            ],
          Align(
            alignment: Alignment.centerLeft,
            child: BookplateButton(
              label: 'Name a Sin to Throw Off',
              compact: true,
              variant: BookplateButtonVariant.secondary,
              onPressed: onAddItem,
            ),
          ),
        ],
      ),
    );
  }
}

/// The season-end week: a plate saying the Rule of Life is open again, and
/// until when. Shown on the Rule of Life screen while the window is open; the
/// shell also says so once when the Runner first arrives in the window.
class SeasonReopenPlate extends StatelessWidget {
  const SeasonReopenPlate({super.key, required this.endsAt});

  final DateTime endsAt;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// The plain-words message, shared with the shell's one-time notice.
  static String message(DateTime endsAt) =>
      'A season of your Rule of Life is complete. Until '
      '${_months[endsAt.month - 1]} ${endsAt.day}, you\'re invited to tweak it — change or '
      'remove any rhythm, add new ones — or leave it just as it is. After that it is set '
      'again for the next season.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.antiqueBrass, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A New Season', style: textTheme.titleMedium?.copyWith(color: AppColors.antiqueBrass)),
          const SizedBox(height: 4),
          Text(message(endsAt), style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _RuleItemTile extends StatelessWidget {
  const _RuleItemTile({required this.item, required this.profile});

  final RuleItem item;
  final RunnerProfile profile;

  /// A rhythm is "set" once its first week has passed (see
  /// RunnerProfile.isRuleItemSet): from then on it can't be changed or removed
  /// without a Witness's approval — which closes the loophole of quietly
  /// moving a weekly rhythm's days, or un-anchoring one, to avoid ever
  /// missing it. The database enforces the same rule.
  bool get _isSet => !item.isChurchMandated && profile.isRuleItemSet(item);

  /// DNA Rhythms are locked at all times — the Runner didn't choose them, so
  /// only their church can retire them. Either way, [_requestUnlock] is the
  /// one way out: asking a Witness to lift it.
  bool get _isLocked => item.isChurchMandated || _isSet;

  /// A Witness approved changes and that approval is still running.
  bool get _isUnlockedForNow => !item.isChurchMandated && item.isUnlockedAt(DateTime.now());

  /// Files an unlock request (for a DNA Rhythm, or a rhythm that has become
  /// set) with one of this account's Witnesses — auto-picked when there's
  /// only one, otherwise the Runner chooses. See
  /// RunnerProfile.requestRuleItemUnlock.
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

  Future<void> _remove(BuildContext context) async {
    try {
      await profile.removeRuleItem(item.id);
    } catch (_) {
      if (context.mounted) {
        showBookplateNotice(context, "Couldn't remove that rhythm. Try again.");
      }
    }
  }

  /// Folds this rhythm into the church DNA Rhythm it duplicates (see
  /// RunnerProfile.mergeCandidateFor): check-ins move across, the duplicate
  /// goes. Confirmed first — it removes a rhythm.
  Future<void> _merge(BuildContext context, RuleItem into) async {
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Merge into the church rhythm?',
      message: '"${item.title}" will be folded into "${into.title}". Your check-ins for it '
          'move across (where both were answered on the same day, the church rhythm\'s '
          'answer stands), and "${item.title}" is removed from your Rule of Life.',
      confirmLabel: 'Merge',
      cancelLabel: 'Keep both',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await profile.mergeRuleItemIntoDna(ownItemId: item.id, dnaItemId: into.id);
    } catch (_) {
      if (context.mounted) showBookplateNotice(context, "Couldn't merge those rhythms. Try again.");
      return;
    }
    if (!context.mounted) return;
    showBookplateNotice(context, 'Merged — your check-ins now count toward "${into.title}".');
  }

  static String _formatUnlockDeadline(DateTime until) {
    final hour = until.hour % 12 == 0 ? 12 : until.hour % 12;
    final minute = until.minute.toString().padLeft(2, '0');
    final period = until.hour < 12 ? 'AM' : 'PM';
    final now = DateTime.now();
    final sameDay = until.year == now.year && until.month == now.month && until.day == now.day;
    return '${sameDay ? 'today' : 'tomorrow'} at $hour:$minute $period';
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
    final mergeInto = profile.mergeCandidateFor(item);

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
                  if (_isLocked)
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
                  else
                    BookplateButton(
                      label: 'Remove',
                      compact: true,
                      variant: BookplateButtonVariant.danger,
                      onPressed: () => _remove(context),
                    ),
                ],
              ),
            ),
            if (mergeInto != null) ...[
              const SizedBox(height: 8),
              // The Runner's own rhythm merges INTO the church's, never the
              // other way round: the DNA Rhythm stays, with the history of both.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Already doing this as "${mergeInto.title}"?',
                    style: textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: AppColors.antiqueBrass,
                    ),
                  ),
                  BookplateButton(
                    label: 'Merge them',
                    compact: true,
                    variant: BookplateButtonVariant.link,
                    onPressed: () => _merge(context, mergeInto),
                  ),
                ],
              ),
            ],
            if (item.isChurchMandated || _isSet) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const BrassLock(size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: BookplateTag(
                      label: item.isChurchMandated ? 'DNA Rhythm · From your church' : 'Set',
                      color: AppColors.antiqueBrass,
                    ),
                  ),
                ],
              ),
            ] else if (_isUnlockedForNow) ...[
              const SizedBox(height: 6),
              Text(
                'Unlocked by your Witness until '
                '${_formatUnlockDeadline(item.unlockedUntil!)}.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.antiqueBrass,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // A sin to throw off is a daily resolve; there is no schedule to
            // choose, so the frequency chips are left off its tile.
            if (item.isThrowOff)
              Text(
                'Checked every day: did you avoid it?',
                style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              )
            else ...[
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
                      enabled: !_isLocked,
                      onTap: () => _setFrequency(context, frequency),
                    ),
                ],
              ),
            ],
            if (!item.isThrowOff && item.frequency == RuleFrequency.weekly) ...[
              const SizedBox(height: 12),
              // One row of seven that shrinks to fit, rather than a Wrap that
              // left Sunday alone on a second line.
              Row(
                children: [
                  for (final weekday in weekdayOrder)
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: BookplateChip(
                          label: weekdayShortLabel(weekday),
                          selected: item.weeklyDays.contains(weekday),
                          compact: true,
                          enabled: !_isLocked,
                          onTap: () => _toggleWeekday(context, weekday),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (_isSet) ...[
              const SizedBox(height: 10),
              Text(
                'This rhythm is set. To change or remove it, ask a Witness to unlock it — '
                'their approval opens it for a day.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.antiqueBrass,
                  fontStyle: FontStyle.italic,
                ),
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
