import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/prayer_item.dart';
import '../../models/runner_profile.dart';
import '../../services/prayer_photo_service.dart';
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
import '../../widgets/prayer_medallion.dart';
import '../../widgets/prayer_photo_row.dart';
import 'daily_prayer_screen.dart';

enum _GardenView { active, answered }

/// Stores [bytes] as the photo for the prayer [prayerId] and records where it
/// went. Resolves to whether the photo is now attached; never throws — the
/// prayer itself is already saved, so a photo that would not upload is
/// something to mention, not a failure of the whole action.
Future<bool> _savePrayerPhoto(RunnerProfile profile, String prayerId, Uint8List bytes) async {
  final service = PrayerPhotoService.instance;
  String? uploadedTo;
  try {
    final path = await service.upload(prayerId: prayerId, bytes: bytes);
    uploadedTo = path;
    // Replacing a photo reuses the same path, so there is nothing new to
    // record on the prayer.
    final alreadyRecorded = profile.prayerItems.any(
      (item) => item.id == prayerId && item.photoPath == path,
    );
    if (!alreadyRecorded) await profile.setPrayerPhoto(prayerId, path);
    return true;
  } catch (error) {
    debugPrint('Prayer photo save failed: ${error.runtimeType}');
    // Uploaded but never recorded on the prayer: nothing would ever show or
    // clean up that file, so take it back out.
    if (uploadedTo != null) unawaited(service.remove(uploadedTo));
    return false;
  }
}

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

  /// Marks where the full list of prayers begins, so the field's "+N" marker
  /// can scroll to it.
  final GlobalKey _listKey = GlobalKey();

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

    // A prayer has no id — and so nowhere to store a photo — until it has
    // been saved, so a chosen photo waits here and is uploaded straight after
    // the prayer is created.
    Uint8List? photoBytes;
    var photoSaveFailed = false;

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
              // A person's name is capitalised word by word; a situation's
              // title reads as a sentence.
              textCapitalization: category == PrayerCategory.people
                  ? TextCapitalization.words
                  : TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              // Rebuilds so the photo row's initials follow the name as typed.
              onChanged: (_) => setDialogState(() {}),
              decoration: InputDecoration(
                labelText: category == PrayerCategory.people ? 'Name' : 'Title',
              ),
            ),
            if (category == PrayerCategory.people) ...[
              const SizedBox(height: 8),
              PrayerPhotoRow(
                name: titleController.text,
                photoBytes: photoBytes,
                onPick: () async {
                  final pick = await PrayerPhotoService.instance.pick();
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    // Too large, wrong kind, or no access to photos: said in
                    // the form's own error line, with any earlier photo kept.
                    if (pick.notice != null) error = pick.notice;
                    if (pick.bytes != null) {
                      photoBytes = pick.bytes;
                      error = null;
                    }
                  });
                },
                onRemove: () => setDialogState(() => photoBytes = null),
              ),
            ],
            const SizedBox(height: 16),
            // Several lines, so its return key stays a line break rather
            // than "next".
            TextField(
              controller: detailsController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
            if (category == PrayerCategory.people) ...[
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
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
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
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
            final String prayerId;
            try {
              prayerId = await _profile.addPrayerItem(
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
            } catch (_) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                isSaving = false;
                error = "Couldn't add that to your garden. Check your connection and try again.";
              });
              return;
            }
            // The prayer now exists, so from here the dialog always closes:
            // a photo that will not upload must not leave the form open
            // inviting a second "Add" (and a duplicate prayer).
            final photo = category == PrayerCategory.people ? photoBytes : null;
            if (photo != null) {
              photoSaveFailed = !await _savePrayerPhoto(_profile, prayerId, photo);
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
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

    if (photoSaveFailed && mounted) {
      showBookplateNotice(
        context,
        "Saved, but the photo couldn't be uploaded. You can add it again later.",
      );
    }
  }

  /// Opens one prayer's detail: its text, and — for a person — the photo with
  /// its Add / Change / Remove actions. Reached by tapping the prayer's plant
  /// in the field or its row in the list.
  void _showPrayerDetail(String prayerId) {
    showBookplateSheet<void>(
      context,
      builder: (sheetContext) => _PrayerDetailSheet(profile: _profile, prayerId: prayerId),
    );
  }

  /// The field's "+N" marker: brings the full list into view and says so.
  void _showFullList() {
    final list = _listKey.currentContext;
    if (list != null) {
      Scrollable.ensureVisible(
        list,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    final count = _profile.prayerItems
        .where((item) => item.isAnswered == (_view == _GardenView.answered))
        .length;
    showBookplateNotice(context, 'All $count are listed below.');
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
    final photoPath = item.photoPath;
    final removed = await runWithFailureNotice(
      context,
      () => _profile.removePrayerItem(item.id),
      failure: "Couldn't remove that prayer. Check your connection.",
    );
    // The profile deletes the stored photo along with the prayer; this drops
    // what was remembered about it here (its link, and the photo itself if it
    // was chosen this session).
    if (removed && photoPath != null) PrayerPhotoService.instance.invalidate(photoPath);
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
                          id: item.id,
                          title: item.title,
                          details: item.details,
                          scripture: item.scripture,
                          answeredDate: item.answeredDate,
                        ),
                    ],
                    onEntryTap: (entry) => _showPrayerDetail(entry.id!),
                    onShowAll: _showFullList,
                  ),
                  SizedBox(key: _listKey, height: 24),
                  for (final category in PrayerCategory.values) ...[
                    _CategorySection(
                      category: category,
                      items: items.where((item) => item.category == category).toList(),
                      isLocked: category == PrayerCategory.witnessRequests &&
                          _profile.isWitnessRequestsLocked,
                      isManaging: _isManaging,
                      onOpen: (item) => _showPrayerDetail(item.id),
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
    required this.onEntryTap,
    required this.onShowAll,
  });

  final _GardenView view;
  final bool isManaging;
  final VoidCallback onToggleManage;
  final VoidCallback onSetPrayerTime;
  final String prayerTimeLabel;

  /// One garden plant per prayer in the current (Active / Answered) view.
  final List<GardenEntry> entries;

  /// A plant was tapped — open that prayer.
  final ValueChanged<GardenEntry> onEntryTap;

  /// The field's "+N" marker was tapped — show where the rest are.
  final VoidCallback onShowAll;

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
            PrayerGardenField(
              entries: entries,
              answered: isAnswered,
              onEntryTap: onEntryTap,
              onShowAll: onShowAll,
            ),
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
    required this.onOpen,
    required this.onToggleAnswered,
    required this.onRemove,
  });

  final PrayerCategory category;
  final List<PrayerItem> items;
  final bool isLocked;
  final bool isManaging;
  final ValueChanged<PrayerItem> onOpen;
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
                              onOpen: () => widget.onOpen(item),
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
    required this.onOpen,
    required this.onToggleAnswered,
    required this.onRemove,
  });

  final PrayerItem item;
  final bool isManaging;

  /// The name (and, for a person, the medallion) was tapped — open this
  /// prayer's detail, which is where its photo is added or changed.
  final VoidCallback onOpen;
  final VoidCallback onToggleAnswered;
  final VoidCallback onRemove;

  Future<void> _textOrCall(BuildContext context, String phone) => launchOrNotify(
        context,
        smsUri(phone),
        unavailable: 'No messaging app is available on this device.',
      );

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
              // The medallion and name together are one button that opens the
              // prayer — at least 44 high, however short the name.
              Expanded(
                child: Semantics(
                  button: true,
                  label: item.title,
                  hint: 'Opens this prayer',
                  onTap: onOpen,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          if (isPerson) ...[
                            // The person's photo in a brass ring, or their
                            // initials until one is added.
                            PrayerMedallion(
                              name: item.title,
                              photoPath: item.photoPath,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(child: Text(item.title, style: textTheme.titleMedium)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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

/// One prayer's detail, shown in a bottom sheet: what it says, when it was
/// answered, and — for a person — their photo with Add / Change / Remove.
/// It watches the profile, so a photo added here appears in the sheet (and
/// in the list behind it) the moment it is saved.
class _PrayerDetailSheet extends StatefulWidget {
  const _PrayerDetailSheet({required this.profile, required this.prayerId});

  final RunnerProfile profile;
  final String prayerId;

  @override
  State<_PrayerDetailSheet> createState() => _PrayerDetailSheetState();
}

class _PrayerDetailSheetState extends State<_PrayerDetailSheet> {
  /// A photo is being uploaded or removed.
  bool _busy = false;

  PrayerItem? get _item {
    for (final item in widget.profile.prayerItems) {
      if (item.id == widget.prayerId) return item;
    }
    return null;
  }

  Future<void> _choosePhoto(PrayerItem item) async {
    final pick = await PrayerPhotoService.instance.pick();
    if (!mounted) return;
    final notice = pick.notice;
    if (notice != null) showBookplateNotice(context, notice);
    final bytes = pick.bytes;
    if (bytes == null) return;

    setState(() => _busy = true);
    final saved = await _savePrayerPhoto(widget.profile, item.id, bytes);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!saved) {
      showBookplateNotice(
        context,
        "Couldn't save that photo. Check your connection and try again.",
      );
    }
  }

  /// Removing a photo deletes it for good, so it asks first.
  Future<void> _removePhoto(PrayerItem item) async {
    final path = item.photoPath;
    if (path == null) return;
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Remove This Photo?',
      message: 'The photo for "${item.title}" will be deleted. You can add another any time.',
      confirmLabel: 'Remove',
      cancelLabel: 'Keep It',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    // The prayer forgets the photo first; only then is the file itself
    // deleted (best-effort) — never a prayer left pointing at a missing photo.
    final cleared = await runWithFailureNotice(
      context,
      () => widget.profile.setPrayerPhoto(item.id, null),
      failure: "Couldn't remove that photo. Check your connection.",
    );
    if (cleared) await PrayerPhotoService.instance.remove(path);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.profile,
      builder: (context, _) {
        final item = _item;
        // Removed from the garden while this sheet was open.
        if (item == null) return const SizedBox.shrink();
        final textTheme = Theme.of(context).textTheme;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item.category == PrayerCategory.people) ...[
              PrayerPhotoRow(
                name: item.title,
                photoPath: item.photoPath,
                busy: _busy,
                onPick: () => _choosePhoto(item),
                onRemove: () => _removePhoto(item),
              ),
              const SizedBox(height: 12),
              const BookplateDivider(),
              const SizedBox(height: 16),
            ],
            Text(item.title, style: textTheme.headlineSmall),
            if (item.details.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(item.details, style: textTheme.bodyMedium),
            ],
            if (item.scripture != null) ...[
              const SizedBox(height: 12),
              Text(
                item.scripture!,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.antiqueBrass,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (item.isAnswered) ...[
              const SizedBox(height: 16),
              Text(
                item.answeredDate == null
                    ? 'Answered'
                    : 'Answered ${formatGardenDate(item.answeredDate!)}',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.forestGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
