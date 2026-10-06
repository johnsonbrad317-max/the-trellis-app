import 'package:flutter/material.dart';

import '../../models/church_roster_entry.dart';
import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_chip.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/brass_lock.dart';
import '../../widgets/cloud_empty_state.dart';
import '../../widgets/dna_rhythm_dialog.dart';
import '../../widgets/email_chooser_sheet.dart';
import '../../widgets/launch_link.dart';

/// Below this many actively-tracked Runners, per-rhythm aggregates could be
/// reverse-engineered back to an individual — so Congregational Health
/// stays locked until the congregation is large enough to protect anyone
/// in it. (The database enforces the same floor, and additionally hides any
/// rhythm fewer than this many Runners hold.)
const kAnonymityThreshold = 15;

/// How many people a triage card lists before it folds the rest away.
const _triagePreviewCount = 4;

/// Church-wide analytics and pastoral triage for the Cloud role.
///
/// Deliberately aggregate-only: this screen never surfaces an individual
/// Runner's daily check-in answers or private prayer requests — only
/// congregation-wide rollups, and named alerts a Church Admin needs to act on.
/// Every figure here is computed by the database from the strict season score
/// (every scheduled day counts; an unanswered one is a miss), including who
/// lands on the Needs Attention list.
class CloudInsightsScreen extends StatelessWidget {
  const CloudInsightsScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mandatedTitles = profile.dnaRhythms.map((r) => r.title).toSet();

    final metrics = [...profile.churchRhythmMetrics]
      ..sort((a, b) {
        final aMandated = mandatedTitles.contains(a.title);
        final bMandated = mandatedTitles.contains(b.title);
        if (aMandated != bMandated) return aMandated ? -1 : 1;
        return a.completionRate.compareTo(b.completionRate);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Congregational Health', style: textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Aggregate Rule of Life data across the church — last 30 days.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _Plate(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DNA Rhythms', style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Core rhythms defining our congregational baseline.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (profile.dnaRhythms.isEmpty)
                  Text(
                    'No DNA Rhythms yet. Add your church\'s core rhythms — each one is placed '
                    'on the Rule of Life of every Runner already in your church, and of '
                    'everyone who joins later.',
                    style: textTheme.bodyMedium,
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final rhythm in profile.dnaRhythms)
                        BookplateTag(label: rhythm.title, color: AppColors.antiqueBrass),
                    ],
                  ),
                const SizedBox(height: 12),
                // The same dialog as Church Profile's — added here so the very
                // first rhythm doesn't require finding the gear menu.
                Align(
                  alignment: Alignment.centerLeft,
                  child: BookplateButton(
                    label: 'Add DNA Rhythm',
                    compact: true,
                    variant: BookplateButtonVariant.secondary,
                    onPressed: () => showDnaRhythmDialog(context, profile),
                  ),
                ),
                const BookplateDivider(height: 32),
                // The server's own verdict — not a head-count of the roster,
                // which includes Runners who aren't tracking at all.
                if (profile.isCongregationalHealthLocked)
                  _KAnonymityLock(currentCount: profile.trackedRunnerCount)
                else ...[
                  if (metrics.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'No rhythm is held by $kAnonymityThreshold or more Runners yet, so none '
                        'can be shown without singling someone out.',
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  for (final metric in metrics)
                    _StatBar(
                      label: metric.title,
                      percent: metric.completionRate,
                      color: metric.completionRate >= 0.6
                          ? AppColors.forestGreen
                          : AppColors.antiqueBrass,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Every scheduled day counts; a day with no check-in counts as missed. Use '
                    'these insights to inform corporate prayer and upcoming sermon topics.',
                    style: textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: AppColors.forestGreen.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('Needs Attention', style: textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Live from the last 180 days — who may need a pastoral touch.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _NeedsAttention(profile: profile),
          const SizedBox(height: 28),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'To preserve the sanctity of the accountability relationship, specific '
                'daily check-in data and private prayer requests are never visible to '
                'the Cloud.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.forestGreen.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The parchment plate every block on this screen is cut from.
class _Plate extends StatelessWidget {
  const _Plate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.vellum.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.vellumBorder),
      ),
      child: child,
    );
  }
}

/// The k-anonymity guardrail's locked state — replaces the metrics list
/// entirely when the congregation is too small to keep individuals
/// anonymous inside the aggregate.
class _KAnonymityLock extends StatelessWidget {
  const _KAnonymityLock({required this.currentCount});

  final int currentCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          BrassLock(size: 34, color: AppColors.antiqueBrass.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            'More data needed. To protect individual privacy, congregational metrics '
            'unlock once $kAnonymityThreshold+ Runners are actively tracking.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '$currentCount of $kAnonymityThreshold Runners so far.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.antiqueBrass),
          ),
        ],
      ),
    );
  }
}

/// A single elegant horizontal bar showing one rhythm's completion rate.
/// Deliberately icon-free — an Anchor Rhythm is a Runner's own personal
/// distress-signal, never a badge on an aggregate congregational metric.
class _StatBar extends StatelessWidget {
  const _StatBar({required this.label, required this.percent, required this.color});

  final String label;
  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: textTheme.bodyMedium)),
              Text(
                '${(percent * 100).round()}%',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(height: 10, width: constraints.maxWidth, color: color.withValues(alpha: 0.15)),
                  Container(height: 10, width: constraints.maxWidth * percent.clamp(0.0, 1.0), color: color),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Needs Attention — live triage
// -----------------------------------------------------------------------------

class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({required this.profile});

  final RunnerProfile profile;

  /// Contact details for a Runner come from the roster, which the database
  /// already scopes to this church; triage itself carries names only.
  ChurchRosterEntry? _rosterEntry(String runnerId) {
    for (final entry in profile.churchRoster) {
      if (entry.id == runnerId) return entry;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final triage = profile.cloudTriage;

    // Nobody has joined yet: there is no one to flag, and "no one needs
    // attention" would be a claim about people who don't exist. (Checked
    // before the unavailable notice — triage for an empty church isn't
    // something to apologise for.)
    if (profile.churchRoster.isEmpty) {
      return const CloudEmptyState(
        message: 'When Runners join your church and begin checking in, the people who may '
            'need a pastoral touch will appear here.',
        glyph: BrassGlyphKind.heart,
      );
    }

    if (profile.cloudTriageUnavailable) {
      return _Plate(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Needs Attention couldn't be loaded just now. That isn't an all-clear — it "
              "simply hasn't been checked.",
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            BookplateButton(
              label: 'Try Again',
              variant: BookplateButtonVariant.secondary,
              onPressed: profile.refreshCloudTriage,
            ),
          ],
        ),
      );
    }

    if (triage.isEmpty) {
      return _Plate(
        child: Text(
          'No one is flagged right now. Every Runner is checking in, paired with a Witness, '
          'and holding steady.',
          style: textTheme.bodyMedium,
        ),
      );
    }

    final strugglingPct = (triage.strugglingBelow * 100).round();

    return Column(
      children: [
        if (triage.struggling.isNotEmpty) ...[
          _TriageCard(
            accentColor: AppColors.terracotta,
            heading: _count(triage.struggling.length, 'Runner is struggling', 'Runners are struggling'),
            blurb: 'Under $strugglingPct% of their scheduled days this season (a day with no '
                'check-in counts as missed), or an Anchor Rhythm missed three times running.',
            rows: [
              for (final runner in triage.struggling)
                _TriageRowData(
                  name: runner.name,
                  detail: [
                    if (runner.score != null) '${(runner.score! * 100).round()}% of the season',
                    if (runner.isDrooping) 'Anchor Rhythm missed 3+ times',
                  ].join(' · '),
                  phone: _rosterEntry(runner.id)?.runnerPhoneNumber,
                  email: _rosterEntry(runner.id)?.runnerEmail,
                  message: 'Hi ${runner.firstName}, I\'ve been thinking of you this week and '
                      'wanted to check in. How are you doing, and how can I pray for you?',
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (triage.witnessAlerts.isNotEmpty) ...[
          _TriageCard(
            accentColor: AppColors.antiqueBrass,
            heading: _count(
              triage.witnessAlerts.length,
              'Witness is walking with a struggling Runner',
              'Witnesses are walking with a struggling Runner',
            ),
            blurb: 'Carrying someone through a hard stretch is heavy — worth asking how they '
                'are doing themselves.',
            rows: [
              for (final witness in triage.witnessAlerts)
                _TriageRowData(
                  name: witness.name,
                  detail: witness.hasSharedContact
                      ? _count(witness.runnerCount, 'struggling Runner', 'struggling Runners')
                      : '${_count(witness.runnerCount, 'struggling Runner', 'struggling Runners')}'
                          ' · Consent pending',
                  phone: witness.phoneNumber,
                  email: witness.email,
                  message: 'Hi ${witness.firstName}, I know you\'re walking with someone through a '
                      'hard stretch. How are your own burdens? Can I pray for you?',
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (triage.isolated.isNotEmpty) ...[
          _TriageCard(
            accentColor: AppColors.antiqueBrass,
            heading: _count(
              triage.isolated.length,
              'Runner has no Witness',
              'Runners have no Witness',
            ),
            blurb: 'In the church ${triage.staleDays}+ days without anyone walking alongside them.',
            rows: [
              for (final runner in triage.isolated)
                _TriageRowData(
                  name: runner.name,
                  detail: runner.daysInChurch == null
                      ? 'No Witness'
                      : 'No Witness · ${runner.daysInChurch} days in the church',
                  phone: _rosterEntry(runner.id)?.runnerPhoneNumber,
                  email: _rosterEntry(runner.id)?.runnerEmail,
                  message: 'Hi ${runner.firstName}, I\'d love to help you find someone to walk '
                      'alongside you in The Trellis. Could we talk this week?',
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (triage.dormant.isNotEmpty)
          _TriageCard(
            accentColor: AppColors.forestGreen,
            heading: _count(
              triage.dormant.length,
              'Runner has gone quiet',
              'Runners have gone quiet',
            ),
            blurb: 'No check-in for ${triage.staleDays}+ days.',
            rows: [
              for (final runner in triage.dormant)
                _TriageRowData(
                  name: runner.name,
                  detail: runner.daysSinceCheckIn == null
                      ? 'Has never checked in'
                      : 'Last check-in ${runner.daysSinceCheckIn} days ago',
                  phone: _rosterEntry(runner.id)?.runnerPhoneNumber,
                  email: _rosterEntry(runner.id)?.runnerEmail,
                  message: 'Hi ${runner.firstName}, we\'ve missed you — how are you doing? No '
                      'pressure at all; I just wanted you to know I\'m thinking of you.',
                ),
            ],
          ),
      ],
    );
  }

  static String _count(int n, String singular, String plural) =>
      n == 1 ? '1 $singular' : '$n $plural';
}

class _TriageRowData {
  const _TriageRowData({
    required this.name,
    required this.detail,
    required this.message,
    this.phone,
    this.email,
  });

  final String name;
  final String detail;
  final String message;
  final String? phone;
  final String? email;
}

/// One category of triage: an accent stripe, a heading and blurb, and the
/// people in it — each with a pre-written, pastoral text or email.
class _TriageCard extends StatefulWidget {
  const _TriageCard({
    required this.accentColor,
    required this.heading,
    required this.blurb,
    required this.rows,
  });

  final Color accentColor;
  final String heading;
  final String blurb;
  final List<_TriageRowData> rows;

  @override
  State<_TriageCard> createState() => _TriageCardState();
}

class _TriageCardState extends State<_TriageCard> {
  bool _showAll = false;

  Future<void> _contact(Uri uri, String unavailableNotice) =>
      launchOrNotify(context, uri, unavailable: unavailableNotice);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hidden = widget.rows.length - _triagePreviewCount;
    final visible = _showAll || hidden <= 0
        ? widget.rows
        : widget.rows.take(_triagePreviewCount).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.vellum.withValues(alpha: 0.9),
          border: Border.all(color: AppColors.vellumBorder),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: widget.accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.heading, style: textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(widget.blurb, style: textTheme.bodySmall),
                      const SizedBox(height: 12),
                      for (final row in visible) ...[
                        const BookplateDivider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(row.name, style: textTheme.bodyLarge),
                                    if (row.detail.isNotEmpty)
                                      Text(
                                        row.detail,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: AppColors.antiqueBrass,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (row.phone != null) ...[
                                const SizedBox(width: 8),
                                BookplateButton(
                                  label: 'Text',
                                  compact: true,
                                  variant: BookplateButtonVariant.secondary,
                                  onPressed: () => _contact(
                                    smsUri(row.phone!, body: row.message),
                                    'No messaging app is available on this device.',
                                  ),
                                ),
                              ],
                              if (row.email != null) ...[
                                const SizedBox(width: 8),
                                BookplateButton(
                                  label: 'Email',
                                  compact: true,
                                  variant: BookplateButtonVariant.secondary,
                                  onPressed: () => showEmailChooser(
                                    context,
                                    email: row.email!,
                                    subject: 'Thinking of you',
                                    body: row.message,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (hidden > 0) ...[
                        const BookplateDivider(),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: BookplateButton(
                            label: _showAll ? 'Show fewer' : 'Show all (${widget.rows.length})',
                            compact: true,
                            variant: BookplateButtonVariant.secondary,
                            onPressed: () => setState(() => _showAll = !_showAll),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
