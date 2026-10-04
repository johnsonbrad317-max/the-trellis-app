import 'package:flutter/material.dart';

import '../models/calendar_connection.dart';
import '../services/calendar_service.dart';
import '../theme/app_colors.dart';
import '../models/meeting_proposal_engine.dart' show formatSlotLabel;
import 'bookplate_chip.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';

/// Opens the "Your Calendars" sheet: one plate per provider with its status
/// and a Connect / Disconnect button. Resolves, once the sheet closes, to
/// whether at least one calendar is connected and usable — handy for the
/// first-run scheduling gate.
Future<bool> showCalendarConnectSheet(BuildContext context) async {
  await showBookplateSheet<void>(
    context,
    builder: (sheetContext) => _CalendarConnectBody(
      onDone: () => Navigator.of(sheetContext).pop(),
    ),
  );
  return CalendarService.instance.hasActiveConnection;
}

/// The one-line subtitle used by entry points (e.g. the settings drawer):
/// which calendars are connected, or an invitation to connect one.
String calendarConnectionsSummary(CalendarService service) {
  if (!service.isLoaded) return 'Free/busy only — never event details';
  final active = service.connections.where((c) => c.isActive).map((c) => c.provider.label).toList();
  final needsReconnect = service.connections.any((c) => !c.isActive);
  if (active.isEmpty) {
    return needsReconnect ? 'Needs reconnecting' : 'None connected';
  }
  final summary = active.join(', ');
  return needsReconnect ? '$summary · one needs reconnecting' : summary;
}

class _CalendarConnectBody extends StatefulWidget {
  const _CalendarConnectBody({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_CalendarConnectBody> createState() => _CalendarConnectBodyState();
}

class _CalendarConnectBodyState extends State<_CalendarConnectBody> {
  final _service = CalendarService.instance;
  CalendarProvider? _busyProvider;
  bool _awaitingReturn = false;

  @override
  void initState() {
    super.initState();
    // load() notifies listeners, so start it after the first frame rather than
    // during build.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await _service.load();
      if (!ok && !_service.isLoaded && mounted) {
        showBookplateNotice(context, "Couldn't load your calendars. Check your connection.");
      }
    });
  }

  Future<void> _connect(CalendarProvider provider) async {
    setState(() => _busyProvider = provider);
    try {
      await _service.connect(provider);
      if (mounted) setState(() => _awaitingReturn = true);
    } on CalendarServiceException catch (e) {
      if (mounted) showBookplateNotice(context, e.message);
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  Future<void> _disconnect(CalendarProvider provider) async {
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Disconnect ${provider.label}?',
      message: 'The Trellis will stop using this calendar to find times you are free. '
          'You can connect it again at any time.',
      confirmLabel: 'Disconnect',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyProvider = provider);
    try {
      await _service.disconnect(provider);
    } on CalendarServiceException catch (e) {
      if (mounted) showBookplateNotice(context, e.message);
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final showSpinner = !_service.isLoaded && _service.isLoading;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your Calendars', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'The Trellis only asks whether you are free or busy — never what is on your '
              'calendar. Your partner sees only times you both have open.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (showSpinner)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: BookplateSpinner()),
              )
            else
              for (final provider in CalendarProvider.values) ...[
                _ProviderPlate(
                  provider: provider,
                  connection: _service.connectionFor(provider),
                  busy: _busyProvider == provider,
                  disabled: _busyProvider != null,
                  onConnect: () => _connect(provider),
                  onDisconnect: () => _disconnect(provider),
                ),
                const SizedBox(height: 10),
              ],
            if (_awaitingReturn) ...[
              Text(
                'Finish connecting in your browser, then come back here — this list '
                'updates by itself.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
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

class _ProviderPlate extends StatelessWidget {
  const _ProviderPlate({
    required this.provider,
    required this.connection,
    required this.busy,
    required this.disabled,
    required this.onConnect,
    required this.onDisconnect,
  });

  final CalendarProvider provider;
  final CalendarConnection? connection;
  final bool busy;
  final bool disabled;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final conn = connection;
    final connected = conn != null && conn.isActive;
    final needsReconnect = conn != null && !conn.isActive;

    final (statusLabel, statusColor) = connected
        ? ('Connected', AppColors.forestGreen)
        : needsReconnect
            ? ('Needs reconnect', AppColors.terracotta)
            : ('Not connected', AppColors.antiqueBrass);

    return BookplatePlate(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BrassGlyph(
                connected ? BrassGlyphKind.checkCircle : BrassGlyphKind.calendar,
                color: connected ? AppColors.forestGreen : AppColors.antiqueBrass,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.label, style: textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      statusLabel,
                      style: textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (provider == CalendarProvider.apple && !connected) ...[
            const SizedBox(height: 8),
            Text(
              'Apple asks for an app-specific password, which you create at '
              'appleid.apple.com — never your Apple ID password.',
              style: textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          if (connected)
            BookplateButton(
              label: 'Disconnect',
              variant: BookplateButtonVariant.secondary,
              busy: busy,
              onPressed: disabled ? null : onDisconnect,
            )
          else ...[
            BookplateButton(
              label: needsReconnect ? 'Reconnect' : 'Connect',
              busy: busy,
              onPressed: disabled ? null : onConnect,
            ),
            if (needsReconnect) ...[
              const SizedBox(height: 6),
              Center(
                child: BookplateButton(
                  label: 'Disconnect',
                  variant: BookplateButtonVariant.link,
                  compact: true,
                  onPressed: disabled ? null : onDisconnect,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A quiet link-style button that opens the calendar sheet; its label tracks
/// how many calendars are connected. Used on both Connect screens.
class CalendarsLinkButton extends StatelessWidget {
  const CalendarsLinkButton({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CalendarService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final count = service.connections.where((c) => c.isActive).length;
        return BookplateButton(
          label: count == 0 ? 'Connect a calendar' : 'Calendars ($count connected)',
          variant: BookplateButtonVariant.link,
          onPressed: () => showCalendarConnectSheet(context),
        );
      },
    );
  }
}

/// "Times you both have free" for the proposal sheets: asks the server for
/// windows when both the signed-in person and [otherUserId] are open, and shows
/// them as chips. Tapping a chip calls [onPick] with that window's start. If
/// either side hasn't connected a calendar it says so quietly instead — never
/// revealing anything about the other person's calendar beyond "connected or
/// not". Any failure degrades to a one-line note; manual entry always works.
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

  /// Called once with the shared windows when both people are connected and
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
    if (result != null && result.bothConnected && result.suggestions.isNotEmpty) {
      widget.onLoaded?.call(result.suggestions);
    }
  }

  Future<void> _chooseCalendars() async {
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
    } else if (availability.isRateLimited) {
      // Checked before "not connected": a rate-limited answer knows nothing
      // about either calendar, so it must not read as "connect one".
      content = Text(
        "You've checked calendars a lot just now. Try again in "
        '${availability.retryAfterLabel}, or pick a time below.',
        style: textTheme.bodySmall,
      );
    } else if (!availability.meConnected) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect a calendar and The Trellis can suggest times you both have free.',
            style: textTheme.bodySmall,
          ),
          BookplateButton(
            label: 'Choose calendars',
            variant: BookplateButtonVariant.link,
            onPressed: _chooseCalendars,
          ),
        ],
      );
    } else if (!availability.otherConnected) {
      content = Text(
        "Your ${widget.otherName} hasn't connected a calendar yet, so there are no shared "
        'times to suggest. Pick a time below.',
        style: textTheme.bodySmall,
      );
    } else if (availability.suggestions.isEmpty) {
      content = Text(
        'No shared open times in the next ${widget.searchDays} days. Pick a time below.',
        style: textTheme.bodySmall,
      );
    } else {
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
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: content,
    );
  }
}
