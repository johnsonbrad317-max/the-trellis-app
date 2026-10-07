import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import '../models/calendar_connection.dart';
import '../models/meeting_activity.dart';
import '../models/meeting_proposal_engine.dart' show formatMeetingDate, formatSlotLabel;
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
              'The Trellis shares only when you are busy or free — never what is on your '
              'calendar. Your Witness or Runner sees only times you both have open.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            // The disclaimer, before anything is shared: most people's work
            // calendar lives only in the Outlook (or Gmail) app, where no
            // other app can read it. The calendar tags further down show
            // which accounts are on the phone.
            BookplatePlate(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BrassGlyph(BrassGlyphKind.info, size: 18, color: AppColors.antiqueBrass),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Only calendars synced to this phone's Calendar app",
                          style: textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(calendarAccountHelp(defaultTargetPlatform), style: textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 12),
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
            // calendars on the phone, so they are covered once that is.
            Text(
              'Use a Skylight or another family wall calendar? It mirrors a Google, Apple or '
              'Outlook calendar — share that calendar here and your Skylight is covered.',
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

/// The coffee / lunch times on offer in the proposal sheets, one row per day
/// ("Mon, Oct 12") with small time chips ("6:00 · 6:30 · 7:00").
///
/// The times come from [MeetingKind] (meeting_activity.dart) — coffee never
/// shows lunch times and lunch never shows coffee times. When both the
/// signed-in person and [otherUserId] share a calendar, only the times both
/// are free for the whole meeting are shown; when either doesn't, the usual
/// times are shown unchecked with a one-line note saying so. Never reveals
/// anything about the other person's calendar beyond "sharing or not", which
/// times are free for both, and how long ago their phone last uploaded. Any
/// failure degrades to the unchecked times; the pickers below always work.
///
/// Tapping a chip calls [onPick] with that start. [onLoaded] is called once
/// with the first time on offer (e.g. to pre-fill the pickers).
class SharedTimesSuggestions extends StatefulWidget {
  const SharedTimesSuggestions({
    super.key,
    required this.otherUserId,
    required this.otherName,
    required this.kind,
    required this.selected,
    required this.onPick,
    this.emergency = false,
    this.onLoaded,
  });

  final String otherUserId;

  /// How to refer to the other person in the explanatory line, e.g. "Witness".
  final String otherName;

  /// Coffee or lunch. Organic Life offers no times, so this shows nothing.
  final MeetingKind kind;

  /// The Runner's Emergency toggle: today's and tomorrow's remaining times.
  final bool emergency;

  /// The date/time currently picked in the sheet, so a matching chip shows
  /// as selected.
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<DateTime>? onLoaded;

  @override
  State<SharedTimesSuggestions> createState() => _SharedTimesSuggestionsState();
}

class _SharedTimesSuggestionsState extends State<SharedTimesSuggestions> {
  /// The usual times for the coming days, before any calendar is checked.
  List<MeetingDaySlots> _candidates = const [];

  /// What is shown: [_candidates], filtered when both calendars are shared.
  List<MeetingDaySlots> _days = const [];
  PairAvailability? _availability;
  bool _loading = true;

  /// Bumped on every fetch so a slow, superseded answer is ignored.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(SharedTimesSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.emergency != widget.emergency ||
        oldWidget.otherUserId != widget.otherUserId) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final generation = ++_generation;
    final kind = widget.kind;
    final candidates = candidateMeetingDays(kind, now: DateTime.now(), emergency: widget.emergency);
    final window = meetingSearchWindow(candidates, durationMinutes: kind.durationMinutes);
    setState(() {
      _candidates = candidates;
      _days = candidates;
      _availability = null;
      _loading = window != null;
    });
    if (window == null) return;

    final result = await CalendarService.instance.availabilityWith(
      widget.otherUserId,
      from: window.start,
      to: window.end,
      durationMinutes: kind.durationMinutes,
    );
    if (!mounted || generation != _generation) return;

    final bothSharing = result != null && result.bothSharing;
    final days = filterFreeForBoth(
      candidates,
      durationMinutes: kind.durationMinutes,
      busyA: bothSharing ? result.myBusy : null,
      busyB: bothSharing ? result.otherBusy : null,
    );
    setState(() {
      _availability = result;
      _days = days;
      _loading = false;
    });
    if (days.isNotEmpty) widget.onLoaded?.call(days.first.starts.first);
  }

  Future<void> _shareCalendar() async {
    await showCalendarConnectSheet(context);
    if (mounted) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    final noteStyle = textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic);
    final availability = _availability;
    final checked = availability != null && availability.bothSharing;
    final noun = widget.kind.timesNoun;

    final children = <Widget>[];
    if (_loading) {
      children.add(
        Row(
          children: [
            const BookplateSpinner(size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Checking $noun times you both have free…', style: textTheme.bodySmall),
            ),
          ],
        ),
      );
    } else {
      children.add(
        Text(
          checked ? 'Free for you both' : 'Usual $noun times',
          style: textTheme.titleMedium,
        ),
      );
      children.add(const SizedBox(height: 6));
      if (_days.isEmpty) {
        children.add(
          Text(
            'No $noun time in the next few days works for you both. Pick a time below.',
            style: textTheme.bodySmall,
          ),
        );
      } else {
        for (final day in _days) {
          children.add(
            _DayTimesRow(
              day: day,
              selected: widget.selected,
              onPick: widget.onPick,
            ),
          );
        }
      }
      children.add(const SizedBox(height: 4));
      if (availability == null) {
        children.add(Text("Couldn't check calendars just now.", style: noteStyle));
      } else if (!availability.meSharing) {
        children.add(
          Text(
            "Calendars aren't being checked — share yours so these show only times you "
            'are both free.',
            style: noteStyle,
          ),
        );
        children.add(
          BookplateButton(
            label: 'Share my calendar',
            variant: BookplateButtonVariant.link,
            compact: true,
            onPressed: _shareCalendar,
          ),
        );
      } else if (!availability.otherSharing) {
        children.add(
          Text(
            "Calendars aren't being checked — your ${widget.otherName} isn't sharing one yet.",
            style: noteStyle,
          ),
        );
      } else {
        final staleDays = availability.otherStaleDays();
        if (staleDays != null && staleDays >= 2) {
          children.add(
            Text(
              "Your ${widget.otherName}'s calendar was last shared $staleDays days ago — newer "
              'plans may not show here.',
              style: noteStyle,
            ),
          );
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// "Mon, Oct 12" over its time chips. The day sits on its own line so a full
/// morning of five coffee times fits on one row even on a small phone (side by
/// side, the chips wrapped and the day floated between two rows).
class _DayTimesRow extends StatelessWidget {
  const _DayTimesRow({required this.day, required this.selected, required this.onPick});

  final MeetingDaySlots day;
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatMeetingDate(day.day),
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.forestGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final start in day.starts)
                Semantics(
                  label: formatSlotLabel(start),
                  excludeSemantics: true,
                  button: true,
                  onTap: () => onPick(start),
                  child: BookplateChip(
                    label: formatChipTime(start),
                    compact: true,
                    selected: selected == start,
                    onTap: () => onPick(start),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How to get a calendar that lives in an email account (Outlook, Gmail) onto
/// the phone's own calendar list, which is what The Trellis reads.
String calendarAccountHelp(TargetPlatform platform) => platform == TargetPlatform.android
    ? "The Trellis can only see calendars your phone itself syncs. If your calendar lives in "
        'the Outlook app, open its Settings, tap your account and turn on Sync calendars. A '
        'Google account added to the phone is seen automatically.'
    : "The Trellis can only see calendars synced to your iPhone's own Calendar app — iCloud, "
        'or an account added in Settings. A work or personal calendar that lives only in the '
        'Outlook or Gmail app is not seen. To include it: Settings → Apps → Calendar → '
        'Calendar Accounts → Add Account → Microsoft Exchange (work or school), Outlook.com or '
        'Google, and switch Calendars on. Then tap Refresh now.';
