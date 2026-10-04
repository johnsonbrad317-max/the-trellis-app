import 'package:flutter/material.dart';

import '../../models/prayer_item.dart';
import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_chip.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/bookplate_tabs.dart';
import '../../widgets/bookplate_time_picker.dart';
import '../../widgets/brass_chevron.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/custom_toggle.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/launch_link.dart';
import '../../widgets/prayer_garden_field.dart';
import 'daily_prayer_screen.dart';

enum _GardenView { active, answered }

/// The Runner's Prayer Garden: active burdens vs. answered prayers, grouped
/// into Witness Requests / People / Situations, plus the daily prayer flow.
class PrayerGardenScreen extends StatefulWidget {
  const PrayerGardenScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<PrayerGardenScreen> createState() => _PrayerGardenScreenState();
}

class _PrayerGardenScreenState extends State<PrayerGardenScreen> {
  _GardenView _view = _GardenView.active;
  bool _isManaging = false;

  RunnerProfile get _profile => widget.profile;

  Future<void> _pickPrayerTime() async {
    final time = await showBookplateTimePicker(
      context,
      initialTime: _profile.prayerReminderTime,
      title: 'Prayer Reminder',
    );
    if (time == null || !mounted) return;
    await runWithFailureNotice(
      context,
      () => _profile.setPrayerReminderTime(time),
      failure: "Couldn't save your prayer time. Check your connection.",
    );
  }

  Future<void> _showAddPrayerDialog() async {
    final titleController = TextEditingController();
    final detailsController = TextEditingController();
    final phoneController = TextEditingController();
    final scriptureController = TextEditingController();
    var category = PrayerCategory.people;
    var shareWithWitnesses = false;
    var isSaving = false;
    String? error;

    await showBookplateForm<void>(
      context,
      title: 'Add to Prayer Garden',
      bodyBuilder: (dialogContext, setDialogState) {
        final textTheme = Theme.of(dialogContext).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Category', style: textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final c in PrayerCategory.values)
                  if (c == PrayerCategory.witnessRequests && _profile.isWitnessRequestsLocked)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BookplateChip(
                          label: c.label,
                          selected: category == c,
                          compact: true,
                          enabled: false,
                        ),
                        const SizedBox(width: 4),
                        const BrassGlyph(
                          BrassGlyphKind.lock,
                          size: 16,
                          color: AppColors.antiqueBrass,
                          semanticLabel: 'Locked',
                        ),
                      ],
                    )
                  else
                    BookplateChip(
                      label: c.label,
                      selected: category == c,
                      compact: true,
                      onTap: () => setDialogState(() => category = c),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: category == PrayerCategory.people ? 'Name' : 'Title',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: detailsController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
            if (category == PrayerCategory.people) ...[
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number (optional)',
                  helperText: 'Adding a phone number allows you to quickly send an '
                      'automated text of encouragement after you pray.',
                  helperMaxLines: 3,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: scriptureController,
              decoration: const InputDecoration(
                labelText: 'Scripture (optional)',
                hintText: 'e.g. Philippians 4:6-7',
              ),
            ),
            const SizedBox(height: 4),
            ToggleRow(
              title: 'Share with Witness(es)',
              value: shareWithWitnesses,
              onChanged: (value) => setDialogState(() => shareWithWitnesses = value),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta)),
            ],
          ],
        );
      },
      actionsBuilder: (dialogContext, setDialogState) => [
        BookplateButton(
          label: 'Add',
          busy: isSaving,
          // The dialog closes only once the prayer is really saved: an empty
          // name or a failed write is explained here, with everything typed
          // still in place, rather than the dialog vanishing with nothing
          // added.
          onPressed: () async {
            if (isSaving) return;
            final title = titleController.text.trim();
            if (title.isEmpty) {
              setDialogState(() {
                error = category == PrayerCategory.people
                    ? 'Enter a name to pray for.'
                    : 'Give this prayer a title.';
              });
              return;
            }
            setDialogState(() {
              isSaving = true;
              error = null;
            });
            try {
              await _profile.addPrayerItem(
                category: category,
                title: title,
                details: detailsController.text.trim(),
                phoneNumber: category == PrayerCategory.people &&
                        phoneController.text.trim().isNotEmpty
                    ? phoneController.text.trim()
                    : null,
                scripture: scriptureController.text.trim().isEmpty
                    ? null
                    : scriptureController.text.trim(),
                shareWithWitnesses: shareWithWitnesses,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } catch (_) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                isSaving = false;
                error = "Couldn't add that to your garden. Check your connection and try again.";
              });
            }
          },
        ),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.secondary,
          onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
        ),
      ],
    );

    disposeAfterBookplateClose([
      titleController,
      detailsController,
      phoneController,
      scriptureController,
    ]);
  }

  Future<void> _toggleAnswered(PrayerItem item) => runWithFailureNotice(
        context,
        () => _profile.setPrayerAnswered(item.id, !item.isAnswered),
        failure: "Couldn't update that prayer. Check your connection.",
      );

  /// Removing a prayer deletes it for good, so it asks first.
  Future<void> _remove(PrayerItem item) async {
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Remove from Your Garden?',
      message: '"${item.title}" will be removed for good.',
      confirmLabel: 'Remove',
      cancelLabel: 'Keep It',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await runWithFailureNotice(
      context,
      () => _profile.removePrayerItem(item.id),
      failure: "Couldn't remove that prayer. Check your connection.",
    );
  }

  void _beginDailyPrayer() {
    final today = DateTime.now();
    final active = _profile.prayerItems.where((item) => !item.isAnswered);
    // An empty garden has nothing to walk through — say how to begin rather
    // than opening straight onto the "you finished" page.
    if (active.isEmpty) {
      showBookplateNotice(context, 'Your garden is empty. Tap + to plant your first prayer.');
      return;
    }
    final queue = active.where((item) => !item.wasPrayedOn(today)).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DailyPrayerScreen(profile: _profile, queue: queue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) {
        final items = _profile.prayerItems
            .where((item) => item.isAnswered == (_view == _GardenView.answered))
            .toList();

        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BookplateTabs<_GardenView>(
                    tabs: const {
                      _GardenView.active: 'Active Burdens',
                      _GardenView.answered: 'Answered Prayers',
                    },
                    selected: _view,
                    onChanged: (view) => setState(() => _view = view),
                  ),
                  const SizedBox(height: 16),
                  _GardenHeader(
                    view: _view,
                    isManaging: _isManaging,
                    onToggleManage: () => setState(() => _isManaging = !_isManaging),
                    onSetPrayerTime: _pickPrayerTime,
                    prayerTimeLabel: _profile.prayerReminderTime.format(context),
                    entries: [
                      for (final item in items)
                        GardenEntry(
                          title: item.title,
                          details: item.details,
                          scripture: item.scripture,
                          answeredDate: item.answeredDate,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  for (final category in PrayerCategory.values) ...[
                    _CategorySection(
                      category: category,
                      items: items.where((item) => item.category == category).toList(),
                      isLocked: category == PrayerCategory.witnessRequests &&
                          _profile.isWitnessRequestsLocked,
                      isManaging: _isManaging,
                      onToggleAnswered: _toggleAnswered,
                      onRemove: _remove,
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),
                  Center(
                    child: GradientButton(
                      label: 'Begin Daily Prayer',
                      onPressed: _beginDailyPrayer,
                    ),
                  ),
                  const SizedBox(height: 88),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Semantics(
                button: true,
                label: 'Add to Prayer Garden',
                onTap: _showAddPrayerDialog,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: _showAddPrayerDialog,
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
                          blurRadius: 14,
                          offset: const Offset(0, 6),
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

class _GardenHeader extends StatelessWidget {
  const _GardenHeader({
    required this.view,
    required this.isManaging,
    required this.onToggleManage,
    required this.onSetPrayerTime,
    required this.prayerTimeLabel,
    required this.entries,
  });

  final _GardenView view;
  final bool isManaging;
  final VoidCallback onToggleManage;
  final VoidCallback onSetPrayerTime;
  final String prayerTimeLabel;

  /// One garden plant per prayer in the current (Active / Answered) view.
  final List<GardenEntry> entries;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isAnswered = view == _GardenView.answered;

    return BookplatePlate(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          children: [
            PrayerGardenField(entries: entries, answered: isAnswered),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // A bare field with a cheerful caption reads as broken;
                      // an empty garden says what belongs here.
                      entries.isEmpty
                          ? (isAnswered
                              ? 'No answered prayers yet'
                              : 'No active burdens — tap + to add one')
                          : (isAnswered ? 'Blooming garden' : 'Seeds sprouting'),
                      style: textTheme.titleMedium,
                    ),
                  ),
                  BrassGlyphButton(
                    kind: isManaging ? BrassGlyphKind.check : BrassGlyphKind.pencil,
                    semanticLabel: isManaging ? 'Done managing' : 'Edit/Manage',
                    onPressed: onToggleManage,
                  ),
                  BrassGlyphButton(
                    kind: BrassGlyphKind.clock,
                    semanticLabel: 'Set Prayer Time ($prayerTimeLabel)',
                    onPressed: onSetPrayerTime,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatefulWidget {
  const _CategorySection({
    required this.category,
    required this.items,
    required this.isLocked,
    required this.isManaging,
    required this.onToggleAnswered,
    required this.onRemove,
  });

  final PrayerCategory category;
  final List<PrayerItem> items;
  final bool isLocked;
  final bool isManaging;
  final ValueChanged<PrayerItem> onToggleAnswered;
  final ValueChanged<PrayerItem> onRemove;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final category = widget.category;
    final items = widget.items;
    final isLocked = widget.isLocked;

    // A collapsible parchment plate built from plain containers: an
    // antique-brass border, a brass-tinted header while open, and a
    // hand-drawn chevron (or a brass lock) instead of Material's expansion tile.
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
            label: category.label,
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
                          Text(category.label, style: textTheme.titleMedium),
                          Text(
                            isLocked
                                ? 'Premium — upgrade to view'
                                : items.isEmpty
                                    ? 'Nothing here yet'
                                    : '${items.length} item(s)',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (isLocked)
                      const BrassGlyph(
                        BrassGlyphKind.lock,
                        size: 22,
                        color: AppColors.antiqueBrass,
                        semanticLabel: 'Locked',
                      )
                    else
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isLocked)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Prayer requests shared by your Witnesses show up here. Upgrade your '
                              'membership to view and pray over them.',
                              style: textTheme.bodyMedium,
                            ),
                          )
                        else if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text('Nothing here yet.', style: textTheme.bodyMedium),
                          )
                        else
                          for (final item in items) ...[
                            _PrayerItemTile(
                              item: item,
                              isManaging: widget.isManaging,
                              onToggleAnswered: () => widget.onToggleAnswered(item),
                              onRemove: () => widget.onRemove(item),
                            ),
                            const SizedBox(height: 12),
                          ],
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

class _PrayerItemTile extends StatelessWidget {
  const _PrayerItemTile({
    required this.item,
    required this.isManaging,
    required this.onToggleAnswered,
    required this.onRemove,
  });

  final PrayerItem item;
  final bool isManaging;
  final VoidCallback onToggleAnswered;
  final VoidCallback onRemove;

  Future<void> _textOrCall(BuildContext context, String phone) => launchOrNotify(
        context,
        smsUri(phone),
        unavailable: 'No messaging app is available on this device.',
      );

  // TODO(image-picker): let the Runner upload or sync a real contact photo
  // instead of this initials placeholder — no image-handling package is
  // wired into the project yet.
  //
  // `characters`, not `substring`: a name that opens with an emoji or an
  // accented letter must not be cut mid-character.
  String get _initials {
    final parts = item.title.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first.characters.first;
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isPerson = item.category == PrayerCategory.people;

    // The double-line bookplate border (1px outer, 4px gap, 1px inner) used
    // for the role cards and sign-in panel, plus a soft diffused shadow, so
    // each burden/request reads as its own small elevated card.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.5)),
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
          Row(
            children: [
              if (isPerson) ...[
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.forestGreen,
                  ),
                  child: Text(
                    _initials,
                    style: textTheme.labelMedium?.copyWith(color: AppColors.parchmentLight),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(item.title, style: textTheme.titleMedium)),
              if (item.shareWithWitnesses)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    'Shared',
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.antiqueBrass,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (isManaging)
                BrassGlyphButton(
                  kind: BrassGlyphKind.trash,
                  semanticLabel: 'Remove',
                  onPressed: onRemove,
                )
              else
                BrassGlyphButton(
                  kind: item.isAnswered ? BrassGlyphKind.undo : BrassGlyphKind.checkCircle,
                  semanticLabel: item.isAnswered ? 'Mark as active' : 'Mark as answered',
                  onPressed: onToggleAnswered,
                ),
            ],
          ),
          if (item.details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.details, style: textTheme.bodyMedium),
          ],
          if (item.scripture != null) ...[
            const SizedBox(height: 8),
            Text(
              item.scripture!,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.antiqueBrass,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (item.phoneNumber != null) ...[
            Semantics(
              button: true,
              label: 'Text ${item.title} at ${item.phoneNumber}',
              onTap: () => _textOrCall(context, item.phoneNumber!),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _textOrCall(context, item.phoneNumber!),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: Text(
                      item.phoneNumber!,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.forestGreen,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          ],
        ),
      ),
    );
  }
}
