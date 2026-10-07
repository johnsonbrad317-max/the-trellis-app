import 'package:flutter/material.dart';

import '../../models/church_roster_entry.dart';
import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_chip.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_chevron.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/cloud_empty_state.dart';
import '../../widgets/email_chooser_sheet.dart';
import '../../widgets/launch_link.dart';
import '../../widgets/vine_visualizer.dart';

enum _RosterFilter { all, flourishing, drooping, unpaired, dormant }

extension _RosterFilterLabel on _RosterFilter {
  String get label => switch (this) {
        _RosterFilter.all => 'All',
        _RosterFilter.flourishing => 'Flourishing Vines',
        _RosterFilter.drooping => 'Drooping Vines',
        _RosterFilter.unpaired => 'Unpaired Runners',
        _RosterFilter.dormant => 'Dormant Vines',
      };
}

/// The Church Admin's Roster tab: a searchable, filterable, church-wide list
/// of every Runner and their paired Witness(es).
class CloudRosterScreen extends StatefulWidget {
  const CloudRosterScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<CloudRosterScreen> createState() => _CloudRosterScreenState();
}

class _CloudRosterScreenState extends State<CloudRosterScreen> {
  final _searchController = TextEditingController();
  _RosterFilter _filter = _RosterFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChurchRosterEntry> _visibleEntries() {
    final query = _query.trim().toLowerCase();

    return widget.profile.churchRoster.where((entry) {
      final matchesFilter = switch (_filter) {
        _RosterFilter.all => true,
        _RosterFilter.flourishing => entry.vineStatus == VineStatus.fullBloom,
        // The Runners whose season rate has fallen furthest — the ones a
        // pastor most wants to find quickly. (Someone who has never checked
        // in scores 0 too but isn't drooping; they haven't started.)
        _RosterFilter.drooping =>
          entry.vineStatus == VineStatus.drooping && !entry.hasNeverCheckedIn,
        _RosterFilter.unpaired => entry.isUnpaired,
        _RosterFilter.dormant => entry.isDormant,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;

      final names = [
        entry.runnerName,
        for (final witness in entry.witnesses) witness.name,
      ].map((name) => name.toLowerCase());
      return names.any((name) => name.contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The Roster', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Every Runner and Witness under your church canopy.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          // A church nobody has joined yet is not an error and has nothing to
          // search — say so, and point at the first step.
          if (widget.profile.churchRoster.isEmpty)
            const CloudEmptyState(
              message: 'Once Runners join with one of your church codes, they will appear '
                  'here with their vine status and their Witnesses. Create a church code in '
                  'Treasury to invite your first Runner.',
              glyph: BrassGlyphKind.people,
            )
          else ...[
          TextField(
            controller: _searchController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search Runners or Witnesses by name',
              prefixIcon: const Center(
                widthFactor: 1,
                child: BrassGlyph(BrassGlyphKind.search, size: 20),
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : BrassGlyphButton(
                      kind: BrassGlyphKind.close,
                      size: 18,
                      semanticLabel: 'Clear search',
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _query = '';
                      }),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in _RosterFilter.values)
                BookplateChip(
                  label: filter.label,
                  selected: _filter == filter,
                  onTap: () => setState(() => _filter = filter),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  // An empty filter group isn't a failed search.
                  _query.trim().isEmpty
                      ? 'No Runners in "${_filter.label}" right now.'
                      : 'No Runners match this search.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final entry in entries) ...[
              _RosterCard(
                key: ValueKey(entry.id),
                entry: entry,
                preview: widget.profile.isPreview,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _RosterCard extends StatefulWidget {
  const _RosterCard({super.key, required this.entry, required this.preview});

  final ChurchRosterEntry entry;

  /// Sample data (the Cloud preview): Text and Email say so instead of
  /// reaching out to anyone.
  final bool preview;

  @override
  State<_RosterCard> createState() => _RosterCardState();
}

class _RosterCardState extends State<_RosterCard> {
  bool _expanded = false;

  Color get _vineColor => switch (widget.entry.vineStatus) {
        VineStatus.fullBloom => AppColors.forestGreen,
        VineStatus.budding => AppColors.antiqueBrass,
        VineStatus.drooping => AppColors.terracotta,
      };

  bool _refusedInPreview(BuildContext context) {
    if (!widget.preview) return false;
    showBookplateNotice(context, PreviewModeException.message);
    return true;
  }

  Future<void> _sendSms(BuildContext context, String? phone) async {
    if (phone == null || _refusedInPreview(context)) return;
    await launchOrNotify(
      context,
      smsUri(phone),
      unavailable: 'No messaging app is available on this device.',
    );
  }

  Future<void> _sendEmail(BuildContext context, String? email) async {
    if (email == null || _refusedInPreview(context)) return;
    await showEmailChooser(context, email: email);
  }

  /// The roster stores "never checked in" as a 999-day gap; say what that
  /// means rather than "Checked in 999 days ago".
  String get _lastCheckInLabel => widget.entry.daysSinceLastCheckIn >= 999
      ? 'No check-ins yet'
      : widget.entry.lastCheckInLabel;

  /// Never checked in and nothing scored: there is no vine status to report.
  bool get _notStarted =>
      widget.entry.daysSinceLastCheckIn >= 999 && widget.entry.vitalityScore <= 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final entry = widget.entry;

    return Semantics(
      button: true,
      expanded: _expanded,
      hint: _expanded ? 'Hides contact details' : 'Shows contact details',
      child: BookplatePlate(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.runnerName, style: textTheme.titleLarge),
                        const SizedBox(height: 4),
                        if (entry.isUnpaired)
                          Text(
                            'No Active Witness — High Isolation Risk',
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.antiqueBrass,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          Text(
                            'Witnessed by ${entry.witnesses.map((w) => w.name).join(', ')}',
                            style: textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 2),
                        Text(
                          _lastCheckInLabel,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.forestGreen.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      VineGlyph(
                        vitalityScore: entry.vitalityScore,
                        isDrooping: entry.vineStatus == VineStatus.drooping,
                        hasData: entry.vitalityScore > 0,
                        height: 40,
                      ),
                      const SizedBox(height: 2),
                      // A Runner who has never checked in has no season to
                      // judge — "Drooping" in terracotta would be a false
                      // alarm about someone who simply hasn't begun.
                      if (_notStarted)
                        const BookplateTag(label: 'Not started', color: AppColors.antiqueBrass)
                      else
                        BookplateTag(label: entry.vineStatus.label, color: _vineColor),
                      if (entry.isDormant && !_notStarted) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Dormant',
                          style: textTheme.labelSmall?.copyWith(color: AppColors.terracotta),
                        ),
                      ],
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                    child: BrassChevron(
                      open: _expanded,
                      color: AppColors.forestGreen.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                const BookplateDivider(height: 24),
                Text('Runner', style: textTheme.labelLarge),
                const SizedBox(height: 6),
                _ContactRow(
                  name: entry.runnerName,
                  onSms: entry.runnerPhoneNumber == null
                      ? null
                      : () => _sendSms(context, entry.runnerPhoneNumber),
                  onEmail: entry.runnerEmail == null
                      ? null
                      : () => _sendEmail(context, entry.runnerEmail),
                ),
                const SizedBox(height: 16),
                Text('Witness(es)', style: textTheme.labelLarge),
                const SizedBox(height: 6),
                if (entry.isUnpaired)
                  Text(
                    'This Runner has not been paired with a Witness yet.',
                    style: textTheme.bodyMedium,
                  )
                else
                  for (final witness in entry.witnesses) ...[
                    _ContactRow(
                      name: witness.name,
                      onSms: witness.phoneNumber == null
                          ? null
                          : () => _sendSms(context, witness.phoneNumber),
                      onEmail:
                          witness.email == null ? null : () => _sendEmail(context, witness.email),
                      consentPending: !witness.hasSharedContact,
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ],
          ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.name,
    this.onSms,
    this.onEmail,
    this.consentPending = false,
  });

  final String name;
  final VoidCallback? onSms;
  final VoidCallback? onEmail;

  /// True for a Witness who hasn't consented to share contact details with
  /// this church — [onSms]/[onEmail] are already null in that case, but
  /// this drives a distinct "Consent Pending" label so it doesn't read as
  /// "no phone/email on file" instead.
  final bool consentPending;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: textTheme.bodyMedium),
              if (consentPending)
                Text(
                  'Consent Pending',
                  style: textTheme.labelSmall?.copyWith(
                    color: AppColors.antiqueBrass,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
        _RingedGlyphButton(
          kind: BrassGlyphKind.bubble,
          onPressed: onSms,
          semanticLabel:
              consentPending ? '$name has not consented to share contact info' : 'Text $name',
        ),
        const SizedBox(width: 8),
        _RingedGlyphButton(
          kind: BrassGlyphKind.envelope,
          onPressed: onEmail,
          semanticLabel:
              consentPending ? '$name has not consented to share contact info' : 'Email $name',
        ),
      ],
    );
  }
}

/// A [BrassGlyphButton] inside a brass ring — the outlined contact action.
/// A null [onPressed] dims it, as for a Witness who hasn't shared contact info.
class _RingedGlyphButton extends StatelessWidget {
  const _RingedGlyphButton({
    required this.kind,
    required this.onPressed,
    required this.semanticLabel,
  });

  final BrassGlyphKind kind;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
      ),
      child: BrassGlyphButton(
        kind: kind,
        size: 18,
        onPressed: onPressed,
        semanticLabel: semanticLabel,
      ),
    );
  }
}
