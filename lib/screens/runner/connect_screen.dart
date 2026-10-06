import 'package:flutter/material.dart';

import '../../models/meeting_proposal_engine.dart';
import '../../models/meeting_request.dart';
import '../../models/runner_profile.dart';
import '../../services/calendar_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_chip.dart';
import '../../widgets/bookplate_date_picker.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/bookplate_time_picker.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/calendar_connect_sheet.dart';
import '../../widgets/custom_toggle.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/maps_location_link.dart';
import '../../widgets/places_autocomplete_field.dart';

/// A picked date/time + typed location from the proposal modal, before it's
/// turned into a [ProposedMeeting].
class _ProposalDraft {
  const _ProposalDraft({required this.time, required this.location});

  final DateTime time;
  final String location;
}

/// The Runner's Connect tab: a smart meeting scheduler for pairing up with
/// a Witness, plus the list of pending/upcoming meetings.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  String? _selectedWitnessId;
  bool _isEmergency = false;
  bool _isSending = false;
  ProposedMeeting? _proposal;

  RunnerProfile get _profile => widget.profile;

  /// The Witness a meeting would go to: the one tapped, as long as they are
  /// still on the list — otherwise the first. Resolved on every use rather
  /// than once in initState, because the Witness list loads (and can change)
  /// after this tab is first built; a selection frozen at "none" left "Send
  /// to Witness" silently doing nothing.
  String? get _activeWitnessId {
    final witnesses = _profile.witnesses;
    if (witnesses.isEmpty) return null;
    final selected = _selectedWitnessId;
    if (selected != null && witnesses.any((w) => w.id == selected)) return selected;
    return witnesses.first.id;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Fail-soft; keeps the "Calendars" button's count current.
      CalendarService.instance.load();
      if (!_profile.hasCompletedSchedulingSetup) _showPermissionsGate();
    });
  }

  /// Whether this visit to the tab has already asked for meeting places —
  /// asked once, not on every "Suggest a Meeting".
  bool _askedForPlaces = false;

  /// "Home · 12 Elm St · Work · …", or an invitation when nothing is on file.
  String _meetingPlacesSummary() {
    final parts = <String>[];
    final home = _profile.homeAddress?.trim() ?? '';
    final work = _profile.workAddress?.trim() ?? '';
    if (home.isNotEmpty) parts.add('Home · $home');
    if (work.isNotEmpty) parts.add('Work · $work');
    if (parts.isEmpty) return 'Add your home and work so meeting spots can land midway.';
    return parts.join('\n');
  }

  /// Enter or change the home / work addresses — the same two fields the
  /// first-run gate asks for, now reachable any time. Returns true if saved.
  Future<bool> _editMeetingPlaces() async {
    final homeController = TextEditingController(text: _profile.homeAddress ?? '');
    final workController = TextEditingController(text: _profile.workAddress ?? '');

    final saved = await showBookplateForm<bool>(
      context,
      title: 'Meeting Places',
      message: 'Where you start from, so meeting suggestions can land somewhere fair '
          'between you and your Witness. Only you and the suggestion engine see these.',
      bodyBuilder: (dialogContext, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: homeController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.streetAddress,
            decoration: const InputDecoration(labelText: 'Home Address'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: workController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.streetAddress,
            decoration: const InputDecoration(labelText: 'Work Address'),
          ),
        ],
      ),
      actionsBuilder: (dialogContext, setDialogState) => [
        BookplateButton(
          label: 'Save',
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.link,
          compact: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
      ],
    );
    final home = homeController.text;
    final work = workController.text;
    disposeAfterBookplateClose([homeController, workController]);
    if (saved != true || !mounted) return false;

    try {
      await _profile.updateMeetingPlaces(homeAddress: home, workAddress: work);
    } catch (_) {
      if (mounted) {
        showBookplateNotice(context, "Couldn't save your meeting places. Check your connection.");
      }
      return false;
    }
    return true;
  }

  /// Before the first suggestion of a visit with no addresses on file: offer
  /// to add them (and carry on either way — they are a help, not a gate).
  Future<void> _offerMeetingPlacesIfMissing() async {
    if (_askedForPlaces || _profile.hasMeetingPlaces) return;
    _askedForPlaces = true;
    final add = await showBookplateConfirm(
      context,
      title: 'Add Your Meeting Places?',
      message: 'With your home and work on file, suggested meeting spots can land somewhere '
          'fair for you both. You can add them later under Meeting Places.',
      confirmLabel: 'Add now',
      cancelLabel: 'Not now',
    );
    if (!add || !mounted) return;
    await _editMeetingPlaces();
  }

  Future<void> _showProposalModal() async {
    await _offerMeetingPlacesIfMissing();
    if (!mounted) return;

    // Seed the pickers with a sensible starting point — 48 hours out (or 2
    // hours for an emergency) — but the Runner can pick any future
    // date/time and any location from here.
    final seed = _proposal?.time ?? generateMeetingProposal(isEmergency: _isEmergency, variation: 0).time;

    var pickedDate = DateTime(seed.year, seed.month, seed.day);
    var pickedTime = TimeOfDay.fromDateTime(seed);
    final locationController = TextEditingController(text: _proposal?.location ?? '');
    var locationError = false;
    // Once the Runner has chosen a date/time by hand (or tapped a suggestion),
    // arriving shared-free-time suggestions must not overwrite it.
    var timeTouched = _proposal != null;
    final witnessId = _activeWitnessId;

    final draft = await showBookplateSheet<_ProposalDraft>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Propose a Time & Place', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (witnessId != null)
              SharedTimesSuggestions(
                otherUserId: witnessId,
                // The role word, as the widget's copy expects ("Your Witness
                // hasn't connected…") — a first name here read "Your Sam…".
                otherName: 'Witness',
                // Mirrors the 48-hour rule the Emergency toggle bypasses.
                earliest: _isEmergency ? const Duration(hours: 2) : const Duration(hours: 48),
                selected: DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime.hour,
                  pickedTime.minute,
                ),
                onPick: (start) => setSheetState(() {
                  timeTouched = true;
                  pickedDate = DateTime(start.year, start.month, start.day);
                  pickedTime = TimeOfDay.fromDateTime(start);
                }),
                onLoaded: (slots) {
                  if (timeTouched) return;
                  // A real shared-free time replaces the mock suggestion.
                  final suggested = generateMeetingProposal(
                    isEmergency: _isEmergency,
                    variation: 0,
                    sharedSlots: slots,
                  ).time;
                  setSheetState(() {
                    pickedDate = DateTime(suggested.year, suggested.month, suggested.day);
                    pickedTime = TimeOfDay.fromDateTime(suggested);
                  });
                },
              ),
            BookplatePlate(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: BookplateRow(
                leading: const BrassGlyph(BrassGlyphKind.calendar, color: AppColors.antiqueBrass),
                title: formatMeetingDate(pickedDate),
                trailing: const BrassGlyph(BrassGlyphKind.forward),
                onTap: () async {
                  final date = await showBookplateDatePicker(
                    context,
                    initialDate: pickedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null && context.mounted) {
                    setSheetState(() {
                      timeTouched = true;
                      pickedDate = date;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            BookplatePlate(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: BookplateRow(
                leading: const BrassGlyph(BrassGlyphKind.clock, color: AppColors.antiqueBrass),
                title: pickedTime.format(context),
                trailing: const BrassGlyph(BrassGlyphKind.forward),
                onTap: () async {
                  final time = await showBookplateTimePicker(context, initialTime: pickedTime);
                  if (time != null && context.mounted) {
                    setSheetState(() {
                      timeTouched = true;
                      pickedTime = time;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            PlacesAutocompleteField(
              controller: locationController,
              errorText: locationError ? 'Please enter a location.' : null,
            ),
            const SizedBox(height: 20),
            BookplateButton(
              label: 'Set Proposal',
              onPressed: () {
                final location = locationController.text.trim();
                if (location.isEmpty) {
                  setSheetState(() => locationError = true);
                  return;
                }
                final combined = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime.hour,
                  pickedTime.minute,
                );
                Navigator.pop(context, _ProposalDraft(time: combined, location: location));
              },
            ),
          ],
        ),
      ),
    );

    // The sheet's closing slide still builds the field; release its
    // controller once that has finished.
    disposeAfterBookplateClose([locationController]);

    if (draft == null || !mounted) return;

    // A time already in the past (e.g. today, an hour ago) can't be met.
    if (!draft.time.isAfter(DateTime.now())) {
      showBookplateNotice(context, 'That time has already passed — pick a later one.');
      return;
    }

    setState(() {
      _proposal = ProposedMeeting(
        time: draft.time,
        timeLabel: '${formatMeetingDate(draft.time)} at ${formatMeetingTime(draft.time)}',
        location: draft.location,
      );
    });
  }

  /// Sends the proposal for real, and only says "sent" once the server has
  /// it. On failure the proposal card stays put so it can simply be re-sent.
  Future<void> _sendToWitness() async {
    final witnessId = _activeWitnessId;
    final proposal = _proposal;
    if (witnessId == null || proposal == null || _isSending) return;

    final isEmergency = _isEmergency;
    setState(() => _isSending = true);
    try {
      await _profile.proposeMeeting(
        witnessId: witnessId,
        time: proposal.time,
        location: proposal.location,
        isEmergency: isEmergency,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      showBookplateNotice(
        context,
        "Couldn't send that meeting request. Check your connection and try again.",
      );
      return;
    }
    if (!mounted) return;

    setState(() {
      _isSending = false;
      _proposal = null;
    });

    showBookplateNotice(
      context,
      isEmergency
          ? 'Sent — your Witness has been alerted immediately.'
          : 'Meeting request sent to your Witness.',
    );
    // TODO(firebase-cloud-function): once a Runner's meeting is actually
    // confirmed by the Witness (a round trip this mock doesn't model — see
    // MeetingStatus.pendingResponse above), prompt the Runner to add it to
    // their device calendar the same way the Witness's Connect tab does on
    // accept/confirm.
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) => _buildContent(context),
    );
  }

  /// The first-run scheduling gate. Shown as a bookplate dialog so its barrier
  /// dims the whole physical viewport — vines, safe-area insets, AppBar and
  /// bottom nav included — rather than just the Connect tab's padded body.
  Future<void> _showPermissionsGate() async {
    final homeController = TextEditingController();
    final workController = TextEditingController();

    await showBookplateForm<void>(
      context,
      title: 'Friction-Free Scheduling',
      message: 'Connect your calendar and addresses so The Trellis can suggest '
          'meeting times and a fair midpoint with your Witness automatically.',
      bodyBuilder: (dialogContext, setDialogState) {
        final textTheme = Theme.of(dialogContext).textTheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Share Your Calendar', style: textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              "The calendars already on this phone. Busy or free only — no event details "
              'are shared.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: CalendarService.instance,
              builder: (context, _) => BookplateButton(
                label: CalendarService.instance.isSharing
                    ? 'Calendar sharing is on'
                    : 'Share my free/busy times',
                variant: BookplateButtonVariant.secondary,
                onPressed: () => showCalendarConnectSheet(dialogContext),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: homeController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.streetAddress,
              decoration: const InputDecoration(labelText: 'Home Address'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: workController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.streetAddress,
              decoration: const InputDecoration(labelText: 'Work Address'),
            ),
          ],
        );
      },
      actionsBuilder: (dialogContext, setDialogState) => [
        BookplateButton(
          label: 'Continue',
          onPressed: () {
            _saveSchedulingSetup(
              calendarConnected: CalendarService.instance.isSharing,
              homeAddress: homeController.text.trim(),
              workAddress: workController.text.trim(),
            );
            Navigator.of(dialogContext).pop();
          },
        ),
        BookplateButton(
          label: 'Skip for now',
          variant: BookplateButtonVariant.link,
          compact: true,
          onPressed: () {
            _saveSchedulingSetup(calendarConnected: false);
            Navigator.of(dialogContext).pop();
          },
        ),
      ],
    );

    // The dialog fades out after it pops; let that finish before the fields
    // it hosted lose their controllers.
    disposeAfterBookplateClose([homeController, workController]);
  }

  /// Records the gate as done (so it isn't shown again) — applied locally at
  /// once; a failed save is reported rather than left as a silent error.
  void _saveSchedulingSetup({
    required bool calendarConnected,
    String? homeAddress,
    String? workAddress,
  }) {
    runWithFailureNotice(
      context,
      () => _profile.completeSchedulingSetup(
        calendarConnected: calendarConnected,
        homeAddress: (homeAddress?.isEmpty ?? true) ? null : homeAddress,
        workAddress: (workAddress?.isEmpty ?? true) ? null : workAddress,
      ),
      failure: "Couldn't save your scheduling details. Check your connection.",
    );
  }

  Widget _buildContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final witnesses = _profile.witnesses;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connect', style: textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Schedule friction-free time with a Witness.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (witnesses.isEmpty)
            BookplatePlate(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Invite a Witness first — once you have one, you can schedule time '
                'together here.',
                style: textTheme.bodyMedium,
              ),
            )
          else ...[
            Text('Meet with', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final witness in witnesses)
                  BookplateChip(
                    label: witness.name,
                    selected: _activeWitnessId == witness.id,
                    onTap: () => setState(() {
                      _selectedWitnessId = witness.id;
                      _proposal = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: GradientButton(label: 'Suggest a Meeting', onPressed: _showProposalModal),
            ),
            const CalendarsLinkButton(),
            const SizedBox(height: 4),
            // Home / work, editable any time (the first-run gate used to be
            // the only chance to enter them).
            BookplatePlate(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: BookplateRow(
                leading: const BrassGlyph(BrassGlyphKind.pin, color: AppColors.antiqueBrass),
                title: 'Meeting Places',
                subtitle: _meetingPlacesSummary(),
                trailing: const BrassGlyph(BrassGlyphKind.forward),
                onTap: _editMeetingPlaces,
              ),
            ),
            const SizedBox(height: 12),
            BookplatePlate(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Emergency / Urgent', style: textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          'Bypasses the 48-hour rule and sends an immediate alert to your Witness.',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CustomToggle(
                    semanticLabel: 'Emergency or urgent',
                    value: _isEmergency,
                    onChanged: (value) => setState(() => _isEmergency = value),
                  ),
                ],
              ),
            ),
            if (_proposal != null) ...[
              const SizedBox(height: 20),
              _ProposedMeetingCard(
                proposal: _proposal!,
                isEmergency: _isEmergency,
                isSending: _isSending,
                onSend: _sendToWitness,
                onRequestDifferent: _showProposalModal,
              ),
            ],
          ],
          const SizedBox(height: 32),
          Text('Upcoming Meetings', style: textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_profile.meetingRequests.isEmpty)
            BookplatePlate(
              padding: const EdgeInsets.all(20),
              child: Text('No meetings scheduled yet.', style: textTheme.bodyMedium),
            )
          else
            for (final meeting in _profile.meetingRequests) ...[
              _MeetingTile(meeting: meeting),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _ProposedMeetingCard extends StatelessWidget {
  const _ProposedMeetingCard({
    required this.proposal,
    required this.isEmergency,
    required this.isSending,
    required this.onSend,
    required this.onRequestDifferent,
  });

  final ProposedMeeting proposal;
  final bool isEmergency;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onRequestDifferent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BookplatePlate(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BrassGlyph(
                isEmergency ? BrassGlyphKind.exclamation : BrassGlyphKind.calendar,
                color: isEmergency ? AppColors.terracotta : AppColors.forestGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Proposed Meeting', style: textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrassGlyph(BrassGlyphKind.clock, size: 18, color: AppColors.antiqueBrass),
              const SizedBox(width: 8),
              Expanded(child: Text(proposal.timeLabel, style: textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: 8),
          MapsLocationLink(proposal.location),
          const SizedBox(height: 20),
          BookplateButton(label: 'Send to Witness', busy: isSending, onPressed: onSend),
          const SizedBox(height: 8),
          BookplateButton(
            label: 'Request Different Time/Place',
            variant: BookplateButtonVariant.secondary,
            onPressed: isSending ? null : onRequestDifferent,
          ),
        ],
      ),
    );
  }
}

class _MeetingTile extends StatelessWidget {
  const _MeetingTile({required this.meeting});

  final MeetingRequest meeting;

  Color _statusColor() => switch (meeting.status) {
        MeetingStatus.pendingResponse => AppColors.antiqueBrass,
        MeetingStatus.confirmed => AppColors.forestGreen,
        MeetingStatus.declined => AppColors.terracotta,
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BookplatePlate(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookplateRow(
            // "Urgent" in words — the terracotta title alone told a
            // colour-blind reader (or a screen reader) nothing.
            title: meeting.isEmergency
                ? 'Urgent · With ${meeting.witnessName}'
                : 'With ${meeting.witnessName}',
            titleStyle: meeting.isEmergency
                ? textTheme.titleMedium?.copyWith(color: AppColors.terracotta)
                : null,
            subtitle: '${formatMeetingDate(meeting.time)} at ${formatMeetingTime(meeting.time)}',
            trailing: BookplateTag(label: meeting.status.label, color: _statusColor()),
          ),
          if (meeting.location.trim().isNotEmpty) MapsLocationLink(meeting.location),
        ],
      ),
    );
  }
}
