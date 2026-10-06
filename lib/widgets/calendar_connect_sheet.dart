import 'package:flutter/material.dart';

import '../models/calendar_connection.dart';
import '../models/meeting_proposal_engine.dart' show formatSlotLabel;
import '../services/calendar_service.dart';
import '../theme/app_colors.dart';
import 'bookplate_chip.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';

/// Opens the "Your Calendars" sheet: share (or stop sharing) the free and busy
/// times from the calendars already on this phone. Resolves, once the sheet
/// closes, to whether sharing is on — handy for the first-run scheduling gate.
Future<bool> showCalendarConnectSheet(BuildContext context) async {
  await showBookplateSheet<void>(
    context,
    builder: (sheetContext) => _CalendarSheetBody(
      onDone: () => Navigator.of(sheetContext).pop(),
    ),
  );
  return CalendarService.instance.isSharing;
}

/// The one-line subtitle used by entry points (e.g. the settings drawer).
String calendarConnectionsSummary(CalendarService service) {
  if (!service.isLoaded) return 'Free/busy only — never event details';
  if (!service.isSharing) return 'Not sharing yet';
  final synced = service.lastSyncedAt;
  return synced == null
      ? "Sharing this phone's free/busy times"
      : "Sharing this phone's free/busy times · updated ${agoLabel(synced)}";
}

class _CalendarSheetBody extends StatefulWidget {
  const _CalendarSheetBody({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_CalendarSheetBody> createState() => _CalendarSheetBodyState();
}

class _CalendarSheetBodyState extends State<_CalendarSheetBody> {
  final _service = CalendarService.instance;

  @override
  void initState() {
    super.initState();
    // load() notifies listeners, so start it after the first frame rather than
    // during build.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await _service.load();
      if (!ok && !_service.isLoaded && mounted) {
        showBookplateNotice(context, "Couldn't check your calendar sharing. Check your connection.");
      }
    });
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (done != null && mounted) showBookplateNotice(context, done);
    } on CalendarServiceException catch (e) {
      if (mounted) showBookplateNotice(context, e.message);
    }
  }

  Future<void> _stop() async {
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Stop sharing your calendar?',
      message: 'Your busy times are removed from The Trellis, and shared times with your '
          'Witness or Runner can no longer be suggested. You can turn it back on any time.',
      confirmLabel: 'Stop sharing',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(_service.disable, done: 'Calendar sharing is off.');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final sharing = _service.isSharing;
        final busy = _service.isBusy;
        final synced = _service.lastSyncedAt;
        final names = _service.calendarNames;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your Calendars', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'The Trellis reads the calendars already on this phone — iCloud, Google, '
              'Outlook, whichever you use — and shares only when you are busy or free. Never '
              'what is on your calendar. Your Witness or Runner sees only times you both '
              'have open.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            BookplatePlate(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      BrassGlyph(
                        sharing ? BrassGlyphKind.checkCircle : BrassGlyphKind.calendar,
                        color: sharing ? AppColors.forestGreen : AppColors.antiqueBrass,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("This phone's calendars", style: textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              sharing
                                  ? synced == null
                                      ? 'Sharing'
                                      : 'Sharing · updated ${agoLabel(synced)}'
                                  : 'Not sharing',
                              style: textTheme.bodySmall?.copyWith(
                                color: sharing ? AppColors.forestGreen : AppColors.antiqueBrass,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (sharing && names.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final name in names)
                          BookplateTag(label: name, color: AppColors.antiqueBrass),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (sharing) ...[
                    BookplateButton(
                      label: 'Refresh now',
                      variant: BookplateButtonVariant.secondary,
                      busy: busy,
                      onPressed: busy
                          ? null
                          : () => _run(_service.refresh, done: 'Your busy times are up to date.'),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: BookplateButton(
                        label: 'Stop sharing',
                        variant: BookplateButtonVariant.link,
                        compact: true,
                        onPressed: busy ? null : _stop,
                      ),
                    ),
                  ] else
                    BookplateButton(
                      label: 'Share my free/busy times',
                      busy: busy,
                      onPressed: busy
                          ? null
                          : () => _run(
                                _service.enable,
                                done: 'Sharing is on. Your busy times refresh each time you open '
                                    'The Trellis.',
                              ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your phone will ask once for calendar access. Busy times are refreshed '
              'whenever you open The Trellis, so keep opening it now and then and your '
              'partner always sees your real week.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // Family wall calendars (Skylight and the like) mirror one of the
            // calendars on the phone, so they are covered already.
            Text(
              'Use a Skylight or another family wall calendar? It mirrors a Google, Apple or '
              'Outlook calendar — and that one is on this phone, so your Skylight is covered.',
              style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            BookplateButton(
              label: 'Done',
              variant: BookplateButtonVariant.secondary,
              onPressed: widget.onDone,
            ),
          ],
        );
      },
    );
  }
}

/// A quiet link-style button that opens the calendar sheet; its label tracks
/// whether sharing is on. Used on both Connect screens.
class CalendarsLinkButton extends StatelessWidget {
  const CalendarsLinkButton({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CalendarService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => BookplateButton(
        label: service.isSharing ? 'Calendar (sharing)' : 'Share your calendar',
        variant: BookplateButtonVariant.link,
        onPressed: () => showCalendarConnectSheet(context),
      ),
    );
  }
}

/// "Times you both have free" for the proposal sheets: works out windows when
/// both the signed-in person and [otherUserId] are open, and shows them as
/// chips. Tapping a chip calls [onPick] with that window's start. If either
/// side isn't sharing a calendar it says so quietly instead — never revealing
/// anything about the other person's calendar beyond "sharing or not" and how
/// long ago their phone last uploaded. Any failure degrades to a one-line
/// note; manual entry always works.
class SharedTimesSuggestions extends StatefulWidget {
  const SharedTimesSuggestions({
    super.key,
    required this.otherUserId,
    required this.otherName,
    required this.earliest,
    required this.selected,
    required this.onPick,
    this.onLoaded,
    this.durationMinutes = 60,
    this.searchDays = 14,
  });

  final String otherUserId;

  /// How to refer to the other person in the explanatory line, e.g. "Witness".
  final String otherName;

  /// How far from now suggestions may start (e.g. the 48-hour rule).
  final Duration earliest;

  /// The date/time currently picked in the sheet, so a matching chip shows
  /// as selected.
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;

  /// Called once with the shared windows when both people are sharing and
  /// at least one exists (e.g. to pre-fill the first suggestion).
  final ValueChanged<List<SharedSlot>>? onLoaded;
  final int durationMinutes;
  final int searchDays;

  @override
  State<SharedTimesSuggestions> createState() => _SharedTimesSuggestionsState();
}

class _SharedTimesSuggestionsState extends State<SharedTimesSuggestions> {
  PairAvailability? _availability;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final from = DateTime.now().add(widget.earliest);
    final result = await CalendarService.instance.availabilityWith(
      widget.otherUserId,
      from: from,
      to: from.add(Duration(days: widget.searchDays)),
      durationMinutes: widget.durationMinutes,
    );
    if (!mounted) return;
    setState(() {
      _availability = result;
      _loading = false;
    });
    if (result != null && result.bothSharing && result.suggestions.isNotEmpty) {
      widget.onLoaded?.call(result.suggestions);
    }
  }

  Future<void> _shareCalendar() async {
    await showCalendarConnectSheet(context);
    if (mounted) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final availability = _availability;

    final Widget content;
    if (_loading) {
      content = Row(
        children: [
          const BookplateSpinner(size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Looking for times you both have free…', style: textTheme.bodySmall),
          ),
        ],
      );
    } else if (availability == null) {
      content = Text(
        "Couldn't check calendars just now — pick a time below.",
        style: textTheme.bodySmall,
      );
    } else if (!availability.meSharing) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Share this phone's calendar and The Trellis can suggest times you both have free.",
            style: textTheme.bodySmall,
          ),
          BookplateButton(
            label: 'Share my calendar',
            variant: BookplateButtonVariant.link,
            onPressed: _shareCalendar,
          ),
        ],
      );
    } else if (!availability.otherSharing) {
      content = Text(
        "Your ${widget.otherName} isn't sharing a calendar yet, so there are no shared times "
        'to suggest. Pick a time below.',
        style: textTheme.bodySmall,
      );
    } else if (availability.suggestions.isEmpty) {
      content = Text(
        'No shared open times in the next ${widget.searchDays} days. Pick a time below.',
        style: textTheme.bodySmall,
      );
    } else {
      final staleDays = availability.otherStaleDays();
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Times you both have free', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in availability.suggestions)
                BookplateChip(
                  label: formatSlotLabel(slot.start),
                  selected: widget.selected == slot.start,
                  onTap: () => widget.onPick(slot.start),
                ),
            ],
          ),
          if (staleDays != null && staleDays >= 2) ...[
            const SizedBox(height: 8),
            Text(
              "Your ${widget.otherName}'s calendar was last shared "
              '${staleDays == 1 ? 'yesterday' : '$staleDays days ago'} — newer plans may not '
              'show here.',
              style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: content,
    );
  }
}
