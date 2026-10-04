import 'package:flutter/material.dart';

import '../../models/runner_profile.dart';
import '../../models/watched_prayer_item.dart';
import '../../models/watched_runner.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/bookplate_tabs.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/prayer_garden_field.dart';
import '../../widgets/gradient_button.dart';
import 'witness_daily_prayer_screen.dart';

// Backend notification triggers (Cloud Functions) relevant to this screen:
// - push_new_shared_prayer: sent to the Witness when the Runner shares a
//   new prayer request with them.
// - push_prayer_answered: sent to the Runner when their Witness marks a
//   shared request as answered — a small moment of shared rejoicing.

enum _PrayerView { shared, mine }

/// The Witness's Prayer Garden for the active Runner: the requests the
/// Runner shared, the Witness's own private intercessions, a daily prayer
/// flow through both combined, and an Answered Prayers garden.
class WitnessPrayerScreen extends StatefulWidget {
  const WitnessPrayerScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<WitnessPrayerScreen> createState() => _WitnessPrayerScreenState();
}

class _WitnessPrayerScreenState extends State<WitnessPrayerScreen> {
  _PrayerView _view = _PrayerView.shared;

  RunnerProfile get _profile => widget.profile;

  Future<void> _showAddPrayerDialog(WatchedRunner runner) async {
    final titleController = TextEditingController();
    final detailsController = TextEditingController();
    var isSaving = false;
    String? error;

    await showBookplateForm<void>(
      context,
      title: 'Add a Prayer for ${runner.firstName}',
      bodyBuilder: (ctx, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: detailsController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Details (optional)'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppColors.terracotta),
            ),
          ],
        ],
      ),
      actionsBuilder: (dialogContext, setDialogState) => [
        BookplateButton(
          label: 'Add',
          busy: isSaving,
          // Closes only once the prayer is really saved; an empty title or a
          // failed write is explained here with everything typed still in
          // place.
          onPressed: () async {
            if (isSaving) return;
            final title = titleController.text.trim();
            if (title.isEmpty) {
              setDialogState(() => error = 'Give this prayer a title.');
              return;
            }
            setDialogState(() {
              isSaving = true;
              error = null;
            });
            try {
              await _profile.addWitnessPrayer(
                runner.id,
                title: title,
                details: detailsController.text.trim(),
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            } catch (_) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                isSaving = false;
                error = "Couldn't add that prayer. Check your connection and try again.";
              });
            }
          },
        ),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.secondary,
          onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
        ),
      ],
    );

    disposeAfterBookplateClose([titleController, detailsController]);
  }

  Future<void> _setAnswered(WatchedRunner runner, WatchedPrayerItem item, bool answered) =>
      runWithFailureNotice(
        context,
        () => _profile.setWatchedPrayerAnswered(runner.id, item.id, answered),
        failure: "Couldn't update that prayer. Check your connection.",
      );

  /// Removing one of the Witness's own prayers deletes it for good, so it
  /// asks first.
  Future<void> _removePrayer(WatchedRunner runner, WatchedPrayerItem item) async {
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Remove This Prayer?',
      message: '"${item.title}" will be removed for good.',
      confirmLabel: 'Remove',
      cancelLabel: 'Keep It',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await runWithFailureNotice(
      context,
      () => _profile.removeWitnessPrayer(runner.id, item.id),
      failure: "Couldn't remove that prayer. Check your connection.",
    );
  }

  void _beginPrayNow(WatchedRunner runner) {
    final today = DateTime.now();
    final active = [...runner.sharedPrayerRequests, ...runner.witnessPrayers]
        .where((item) => !item.isAnswered);
    // Nothing to pray through at all — say so, rather than opening straight
    // onto the "you finished" page.
    if (active.isEmpty) {
      showBookplateNotice(
        context,
        '${runner.firstName} has no open prayer requests yet. Add one of your own under '
        '"My Prayers for Runner".',
      );
      return;
    }
    final queue = active.where((item) => !item.wasPrayedOn(today)).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WitnessDailyPrayerScreen(
          profile: _profile,
          runnerId: runner.id,
          runnerFirstName: runner.firstName,
          runnerPhoneNumber: runner.phoneNumber,
          queue: queue,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) {
        final runner = _profile.selectedWatchedRunner;

        if (runner == null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 72),
                const BrassGlyph(BrassGlyphKind.people, size: 48, color: AppColors.forestGreen),
                const SizedBox(height: 16),
                Text(
                  'Select a Runner from the Runners tab to see what they need prayer for.',
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final activeItems =
            (_view == _PrayerView.shared ? runner.sharedPrayerRequests : runner.witnessPrayers)
                .where((item) => !item.isAnswered)
                .toList();

        final answeredItems = [...runner.sharedPrayerRequests, ...runner.witnessPrayers]
            .where((item) => item.isAnswered)
            .toList();

        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Praying for ${runner.name}', style: textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  BookplateTabs<_PrayerView>(
                    tabs: const {
                      _PrayerView.shared: "Runner's Requests",
                      _PrayerView.mine: 'My Prayers for Runner',
                    },
                    selected: _view,
                    onChanged: (view) => setState(() => _view = view),
                  ),
                  const SizedBox(height: 16),
                  BookplatePlate(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: PrayerGardenField(
                        answered: false,
                        entries: [
                          for (final item in activeItems)
                            GardenEntry(title: item.title, details: item.details),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (activeItems.isEmpty)
                    BookplatePlate(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _view == _PrayerView.shared
                            ? 'Nothing shared yet.'
                            : "You haven't added a private prayer yet.",
                        style: textTheme.bodyMedium,
                      ),
                    )
                  else
                    for (final item in activeItems) ...[
                      _PrayerTile(
                        item: item,
                        canRemove: _view == _PrayerView.mine,
                        onToggleAnswered: () => _setAnswered(runner, item, true),
                        onRemove: () => _removePrayer(runner, item),
                      ),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 12),
                  Center(
                    child: GradientButton(
                      label: 'Pray Now',
                      onPressed: () => _beginPrayNow(runner),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text('Answered Prayers', style: textTheme.titleLarge),
                  const SizedBox(height: 12),
                  BookplatePlate(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: PrayerGardenField(
                        answered: true,
                        entries: [
                          for (final item in answeredItems)
                            GardenEntry(
                              title: item.title,
                              details: item.details,
                              answeredDate: item.answeredDate,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (answeredItems.isEmpty)
                    BookplatePlate(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Nothing here yet — answered prayers will bloom here.',
                        style: textTheme.bodyMedium,
                      ),
                    )
                  else
                    for (final item in answeredItems) ...[
                      _PrayerTile(
                        item: item,
                        canRemove: false,
                        onToggleAnswered: () => _setAnswered(runner, item, false),
                        onRemove: () {},
                      ),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 88),
                ],
              ),
            ),
            if (_view == _PrayerView.mine)
              Positioned(
                right: 16,
                bottom: 16,
                child: Semantics(
                  button: true,
                  label: 'Add a Prayer',
                  onTap: () => _showAddPrayerDialog(runner),
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => _showAddPrayerDialog(runner),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.forestGreen,
                        border: Border.all(color: AppColors.antiqueBrass, width: 1.6),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.forestGreen.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: BrassGlyph(
                          BrassGlyphKind.plus,
                          size: 26,
                          color: AppColors.parchmentLight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PrayerTile extends StatelessWidget {
  const _PrayerTile({
    required this.item,
    required this.canRemove,
    required this.onToggleAnswered,
    required this.onRemove,
  });

  final WatchedPrayerItem item;
  final bool canRemove;
  final VoidCallback onToggleAnswered;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BookplatePlate(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: textTheme.bodyMedium),
                  if (item.details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.details,
                      style: textTheme.bodySmall?.copyWith(color: AppColors.antiqueBrass),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (canRemove)
            BrassGlyphButton(
              kind: BrassGlyphKind.trash,
              semanticLabel: 'Remove',
              onPressed: onRemove,
            ),
          BrassGlyphButton(
            kind: item.isAnswered ? BrassGlyphKind.undo : BrassGlyphKind.checkCircle,
            semanticLabel: item.isAnswered ? 'Mark as active' : 'Mark as answered',
            onPressed: onToggleAnswered,
          ),
        ],
      ),
    );
  }
}
