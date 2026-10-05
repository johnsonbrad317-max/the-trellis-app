import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';

import '../../models/meeting_proposal_engine.dart';
import '../../models/runner_profile.dart';
import '../../models/watched_runner.dart';
import '../../services/calendar_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_chip.dart';
import '../../widgets/bookplate_date_picker.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/bookplate_time_picker.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/calendar_connect_sheet.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/maps_location_link.dart';
import '../../widgets/places_autocomplete_field.dart';

/// A picked date/time + typed location from [_showProposalModal], before
/// it's turned into a [ProposedMeeting].
class _ProposalDraft {
  const _ProposalDraft({required this.time, required this.location});

  final DateTime time;
  final String location;
}

/// Best-effort native-calendar add — never lets a plugin/platform failure
/// (e.g. no calendar support on this device/browser) interrupt the meeting
/// flow itself.
Future<void> _addToDeviceCalendar({
  required String title,
  required DateTime start,
  required String location,
}) async {
  try {
    await Add2Calendar.addEvent2Cal(
      Event(
        title: title,
        location: location,
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
      ),
    );
  } catch (_) {
    // No native calendar available on this platform (e.g. web) — the
    // meeting is still saved in-app either way.
  }
}

enum _MeetingActivity { coffee, lunch, errands, kidsSports, houseProject, grillingBbq, other }

extension on _MeetingActivity {
  bool get isOrganicLife => this != _MeetingActivity.coffee && this != _MeetingActivity.lunch;

  String get chipLabel => switch (this) {
        _MeetingActivity.coffee => 'Coffee',
        _MeetingActivity.lunch => 'Lunch',
        _MeetingActivity.errands => 'Errands',
        _MeetingActivity.kidsSports => "Kids' Sports",
        _MeetingActivity.houseProject => 'House Project',
        _MeetingActivity.grillingBbq => 'Grilling/BBQ',
        _MeetingActivity.other => 'Other',
      };

  String get inviteFragment => switch (this) {
        _MeetingActivity.coffee => 'grab coffee',
        _MeetingActivity.lunch => 'grab lunch',
        _MeetingActivity.errands => 'join you for errands',
        _MeetingActivity.kidsSports => "join you at the kids' games",
        _MeetingActivity.houseProject => 'help out on a house project',
        _MeetingActivity.grillingBbq => 'grill out together',
        _MeetingActivity.other => 'spend time together',
      };
}

const _organicLifeOptions = [
  _MeetingActivity.errands,
  _MeetingActivity.kidsSports,
  _MeetingActivity.houseProject,
  _MeetingActivity.grillingBbq,
  _MeetingActivity.other,
];

enum _ContextualTone { struggling, celebrate }

class _ContextualPrompt {
  const _ContextualPrompt({required this.tone, required this.message});

  final _ContextualTone tone;
  final String message;
}

_ContextualPrompt? _buildContextualPrompt(WatchedRunner runner) {
  // Never for a Runner who hasn't committed a Rule of Life (or has no rhythms):
  // an empty week there is not a tough one. See WatchedRunner.isStruggling.
  if (runner.isStruggling) {
    return _ContextualPrompt(
      tone: _ContextualTone.struggling,
      message: '${runner.name} has had a tough week. Suggest grabbing lunch to talk it through.',
    );
  }

  if (runner.recentlyAnsweredPrayer != null) {
    return _ContextualPrompt(
      tone: _ContextualTone.celebrate,
      message: '${runner.name} had a major prayer answered! Suggest coffee to celebrate.',
    );
  }

  return null;
}

/// The Witness's Connect tab: a contextual meeting-tone prompt, a smart
/// scheduling engine (reused from the Runner side) with activity chips,
/// and pending/upcoming meeting lists.
class WitnessConnectScreen extends StatefulWidget {
  const WitnessConnectScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<WitnessConnectScreen> createState() => _WitnessConnectScreenState();
}

class _WitnessConnectScreenState extends State<WitnessConnectScreen> {
  _MeetingActivity _activity = _MeetingActivity.coffee;
  ProposedMeeting? _proposal;
  String? _lastRunnerId;
  bool _isSending = false;

  /// Ids of pending meetings with an answer on its way to the server, so a
  /// second tap can't accept/decline the same one twice.
  final Set<String> _respondingTo = {};
  final _otherController = TextEditingController();

  RunnerProfile get _profile => widget.profile;

  @override
  void initState() {
    super.initState();
    // Fail-soft; keeps the "Calendars" button's count current.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CalendarService.instance.load();
    });
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  /// The activity as it should read in an invite or calendar entry — for
  /// "Other" that is whatever the Witness typed.
  String get _activityLabel {
    final typed = _otherController.text.trim();
    return _activity == _MeetingActivity.other && typed.isNotEmpty ? typed : _activity.chipLabel;
  }

  String get _inviteFragment {
    final typed = _otherController.text.trim();
    return _activity == _MeetingActivity.other && typed.isNotEmpty
        ? "join you for $typed"
        : _activity.inviteFragment;
  }

  void _selectActivity(_MeetingActivity activity) {
    setState(() => _activity = activity);
  }

  Future<void> _showProposalModal() async {
    // Seed the pickers with a sensible starting point — 48 hours out, biased
    // toward lunchtime when Lunch is the chosen activity — but the Witness
    // can pick any future date/time and any location from here.
    final seed = _proposal?.time ??
        generateMeetingProposal(
          isEmergency: false,
          variation: _activity == _MeetingActivity.lunch ? 1 : 0,
        ).time;

    var pickedDate = DateTime(seed.year, seed.month, seed.day);
    var pickedTime = TimeOfDay.fromDateTime(seed);
    final locationController = TextEditingController(text: _proposal?.location ?? '');
    var locationError = false;
    // Once the Witness has chosen a date/time by hand (or tapped a suggestion),
    // arriving shared-free-time suggestions must not overwrite it.
    var timeTouched = _proposal != null;
    final runnerId = _profile.selectedWatchedRunner?.id;

    final draft = await showBookplateSheet<_ProposalDraft>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Propose a Time & Place', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (runnerId != null)
              SharedTimesSuggestions(
                otherUserId: runnerId,
                otherName: 'Runner',
                // Same 48-hour lead as the mock proposal seed.
                earliest: const Duration(hours: 48),
                durationMinutes: _activity == _MeetingActivity.lunch ? 60 : 45,
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
                    isEmergency: false,
                    variation: _activity == _MeetingActivity.lunch ? 1 : 0,
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

  /// Sends the invite for real, and only says "sent" once the server has it.
  /// On failure the invite card stays put so it can simply be re-sent.
  Future<void> _sendProposal(WatchedRunner runner) async {
    final proposal = _proposal;
    if (proposal == null || _isSending) return;

    final activity = _activityLabel;
    setState(() => _isSending = true);

    final WatchedMeetingRequest? confirmed;
    try {
      confirmed = await _profile.proposeMeetingToWatchedRunner(
        runner.id,
        timeLabel: proposal.timeLabel,
        location: proposal.location,
        activity: activity,
        time: proposal.time,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      showBookplateNotice(
        context,
        "Couldn't send that invite. Check your connection and try again.",
      );
      return;
    }
    if (!mounted) return;

    setState(() {
      _isSending = false;
      _proposal = null;
    });
    showBookplateNotice(context, 'Invite sent to ${runner.firstName}.');

    if (confirmed != null) {
      await _addToDeviceCalendar(
        title: '$activity with ${runner.firstName}',
        start: proposal.time,
        location: proposal.location,
      );
    }
  }

  /// Runs one answer to a pending meeting (accept / decline / reschedule),
  /// guarding against a double tap and reporting a failed write.
  Future<T?> _respond<T>(
    WatchedMeetingRequest meeting,
    Future<T> Function() action, {
    required String failure,
  }) async {
    if (!_respondingTo.add(meeting.id)) return null;
    setState(() {});
    try {
      return await action();
    } catch (_) {
      if (mounted) showBookplateNotice(context, failure);
      return null;
    } finally {
      _respondingTo.remove(meeting.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _acceptMeeting(WatchedRunner runner, WatchedMeetingRequest meeting) async {
    final confirmed = await _respond(
      meeting,
      () => _profile.respondToWatchedMeeting(runner.id, meeting.id, accept: true),
      failure: "Couldn't accept that meeting. Check your connection and try again.",
    );
    if (confirmed == null) return;

    final time = confirmed.time;
    if (time != null) {
      await _addToDeviceCalendar(
        title: '${confirmed.activity ?? 'Meeting'} with ${runner.firstName}',
        start: time,
        location: confirmed.location,
      );
    }
  }

  Future<void> _declineMeeting(WatchedRunner runner, WatchedMeetingRequest meeting) => _respond(
        meeting,
        () => _profile.respondToWatchedMeeting(runner.id, meeting.id, accept: false),
        failure: "Couldn't decline that meeting. Check your connection and try again.",
      );

  /// "Reschedule" withdraws the Runner's proposal (that is all the backend
  /// does) — so it says so and asks first, then points at where to propose a
  /// time that does work, instead of the proposal just vanishing.
  Future<void> _rescheduleMeeting(WatchedRunner runner, WatchedMeetingRequest meeting) async {
    final confirmed = await showBookplateConfirm(
      context,
      title: 'Suggest a Different Time?',
      message: "This clears ${runner.firstName}'s proposal for ${meeting.timeLabel}. Then use "
          '"Suggest a Meeting" above to send a time that works for you.',
      confirmLabel: 'Clear Proposal',
      cancelLabel: 'Keep It',
    );
    if (!confirmed || !mounted) return;

    var cleared = false;
    await _respond(
      meeting,
      () async {
        await _profile.rescheduleWatchedMeeting(runner.id, meeting.id);
        cleared = true;
      },
      failure: "Couldn't update that meeting. Check your connection and try again.",
    );
    if (cleared && mounted) {
      showBookplateNotice(context, 'Proposal cleared. Suggest a new time above.');
    }
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
                const BrassGlyph(BrassGlyphKind.people, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Select a Runner from the Runners tab to see meeting requests.',
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (runner.id != _lastRunnerId) {
          _lastRunnerId = runner.id;
          _proposal = null;
        }

        final prompt = _buildContextualPrompt(runner);
        final inviteMessage = _proposal == null
            ? null
            : '${_proposal!.timeLabel}. Invite ${runner.firstName} to $_inviteFragment.';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Meet with ${runner.name}', style: textTheme.headlineMedium),
              const SizedBox(height: 16),
              if (prompt != null) ...[
                _ContextualPromptCard(prompt: prompt),
                const SizedBox(height: 20),
              ],
              Text('Choose an Activity', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final activity in [_MeetingActivity.coffee, _MeetingActivity.lunch])
                    BookplateChip(
                      label: activity.chipLabel,
                      selected: _activity == activity,
                      onTap: () => _selectActivity(activity),
                    ),
                  BookplateChip(
                    label: 'Organic Life',
                    selected: _activity.isOrganicLife,
                    onTap: () => _selectActivity(_MeetingActivity.errands),
                  ),
                ],
              ),
              if (_activity.isOrganicLife) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final activity in _organicLifeOptions)
                      BookplateChip(
                        label: activity.chipLabel,
                        selected: _activity == activity,
                        onTap: () => _selectActivity(activity),
                      ),
                  ],
                ),
                if (_activity == _MeetingActivity.other) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _otherController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'What would you like to do together?',
                      hintText: 'e.g. take a walk, fix the fence',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
              const SizedBox(height: 20),
              Center(
                child: GradientButton(label: 'Suggest a Meeting', onPressed: _showProposalModal),
              ),
              const CalendarsLinkButton(),
              if (_proposal != null) ...[
                const SizedBox(height: 20),
                _ProposedInviteCard(
                  message: inviteMessage!,
                  location: _proposal!.location,
                  isSending: _isSending,
                  onSend: () => _sendProposal(runner),
                  onRequestDifferent: _showProposalModal,
                ),
              ],
              const SizedBox(height: 32),
              Text('Pending', style: textTheme.titleLarge),
              const SizedBox(height: 12),
              if (runner.pendingMeetings.isEmpty)
                BookplatePlate(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No pending proposals from ${runner.firstName}.',
                    style: textTheme.bodyMedium,
                  ),
                )
              else
                for (final meeting in runner.pendingMeetings) ...[
                  _PendingMeetingTile(
                    meeting: meeting,
                    busy: _respondingTo.contains(meeting.id),
                    onAccept: () => _acceptMeeting(runner, meeting),
                    onDecline: () => _declineMeeting(runner, meeting),
                    onReschedule: () => _rescheduleMeeting(runner, meeting),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 24),
              Text('Upcoming', style: textTheme.titleLarge),
              const SizedBox(height: 12),
              if (runner.confirmedMeetings.isEmpty)
                BookplatePlate(
                  padding: const EdgeInsets.all(20),
                  child: Text('No confirmed meetings yet.', style: textTheme.bodyMedium),
                )
              else
                for (final meeting in runner.confirmedMeetings) ...[
                  _ConfirmedMeetingTile(meeting: meeting),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _ContextualPromptCard extends StatelessWidget {
  const _ContextualPromptCard({required this.prompt});

  final _ContextualPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isStruggling = prompt.tone == _ContextualTone.struggling;
    final color = isStruggling ? AppColors.terracotta : AppColors.forestGreen;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isStruggling ? AppColors.terracottaTint : AppColors.forestGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          BrassGlyph(
            isStruggling ? BrassGlyphKind.exclamation : BrassGlyphKind.heart,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(prompt.message, style: textTheme.bodyMedium?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

class _ProposedInviteCard extends StatelessWidget {
  const _ProposedInviteCard({
    required this.message,
    required this.location,
    required this.isSending,
    required this.onSend,
    required this.onRequestDifferent,
  });

  final String message;
  final String location;
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
              const BrassGlyph(BrassGlyphKind.calendar),
              const SizedBox(width: 8),
              Expanded(child: Text('Proposed Invite', style: textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 12),
          Text(message, style: textTheme.bodyMedium),
          const SizedBox(height: 4),
          MapsLocationLink(location, style: textTheme.bodySmall),
          const SizedBox(height: 16),
          BookplateButton(label: 'Send to Runner', busy: isSending, onPressed: onSend),
          const SizedBox(height: 8),
          BookplateButton(
            label: 'Request Different Time',
            variant: BookplateButtonVariant.secondary,
            onPressed: isSending ? null : onRequestDifferent,
          ),
        ],
      ),
    );
  }
}

class _PendingMeetingTile extends StatelessWidget {
  const _PendingMeetingTile({
    required this.meeting,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onReschedule,
  });

  final WatchedMeetingRequest meeting;

  /// An answer to this meeting is on its way — every action waits for it.
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BookplatePlate(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (meeting.isEmergency) ...[
                const BrassGlyph(
                  BrassGlyphKind.exclamation,
                  size: 18,
                  color: AppColors.terracotta,
                  semanticLabel: 'Urgent',
                ),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text(meeting.timeLabel, style: textTheme.titleMedium)),
            ],
          ),
          if (meeting.location.trim().isNotEmpty) MapsLocationLink(meeting.location),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: BookplateButton(label: 'Accept', busy: busy, onPressed: onAccept),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BookplateButton(
                  label: 'Decline',
                  variant: BookplateButtonVariant.secondary,
                  onPressed: busy ? null : onDecline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: BookplateButton(
              label: 'Reschedule',
              variant: BookplateButtonVariant.link,
              compact: true,
              onPressed: busy ? null : onReschedule,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmedMeetingTile extends StatelessWidget {
  const _ConfirmedMeetingTile({required this.meeting});

  final WatchedMeetingRequest meeting;

  @override
  Widget build(BuildContext context) {
    return BookplatePlate(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookplateRow(
            title: meeting.activity ?? 'Meeting',
            subtitle: meeting.timeLabel,
            trailing: const BookplateTag(label: 'Confirmed', color: AppColors.forestGreen),
          ),
          if (meeting.location.trim().isNotEmpty) MapsLocationLink(meeting.location),
        ],
      ),
    );
  }
}
