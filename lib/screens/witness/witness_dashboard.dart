import 'package:flutter/material.dart';

import '../../models/pending_unlock_request.dart';
import '../../models/runner_profile.dart';
import '../../models/support_request.dart';
import '../../models/watched_runner.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/vine_visualizer.dart';
import 'witness_pairing_code_screen.dart';

/// The Witness's first tab: what is waiting on them (Runners' prayer and
/// meeting requests, DNA Rhythm unlock requests), a horizontal carousel to
/// pick which Runner is active, that Runner's read-only 180-Day Trellis, and
/// their recent activity feed. Selecting a Runner here sets
/// [RunnerProfile.selectedRunnerId], which the Rule of Life, Prayer, and
/// Connect tabs read from.
class WitnessDashboardScreen extends StatelessWidget {
  const WitnessDashboardScreen({super.key, required this.profile, this.isLoading = false});

  final RunnerProfile profile;

  /// The shell is still fetching this Witness's Runners. While that is true
  /// an empty list means "not here yet", not "you have none" — so the
  /// "No Runners yet" invitation waits until the answer is actually known.
  final bool isLoading;

  void _openPairingCode(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => WitnessPairingCodeScreen(profile: profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        final runners = profile.watchedRunners;
        final selected = profile.selectedWatchedRunner;
        // Runners who have asked to turn their accountability lock off and
        // are waiting on this Witness's answer.
        final lockRequests = [
          for (final runner in runners)
            if (runner.lockRemovalRequested) runner,
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (profile.incomingSupportRequests.isNotEmpty || lockRequests.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text('Requests for You', style: textTheme.headlineMedium),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      for (final runner in lockRequests) ...[
                        _LockRemovalTile(
                          key: ValueKey('lock-${runner.id}'),
                          profile: profile,
                          runner: runner,
                        ),
                        const SizedBox(height: 12),
                      ],
                      for (final request in profile.incomingSupportRequests) ...[
                        _SupportRequestTile(
                          key: ValueKey('support-${request.id}'),
                          profile: profile,
                          request: request,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (profile.incomingUnlockRequests.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text('Unlock Requests', style: textTheme.headlineMedium),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      for (final request in profile.incomingUnlockRequests) ...[
                        _UnlockRequestTile(
                          key: ValueKey('unlock-${request.id}'),
                          profile: profile,
                          request: request,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(child: Text('Your Runners', style: textTheme.headlineMedium)),
                    BrassGlyphButton(
                      kind: BrassGlyphKind.personAdd,
                      semanticLabel: 'Enter a pairing code',
                      onPressed: () => _openPairingCode(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (runners.isEmpty && isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: Center(child: BookplateSpinner(semanticLabel: 'Loading your Runners')),
                )
              else if (runners.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: BookplatePlate(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'No Runners yet. Ask a Runner for their pairing code to get '
                          'started.',
                          style: textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        GradientButton(
                          label: 'Enter a Pairing Code',
                          onPressed: () => _openPairingCode(context),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SizedBox(
                  // 164 at the default text size; grows with the reader's
                  // text scale so the name and status never overflow a card.
                  height: 128 + MediaQuery.textScalerOf(context).scale(36),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: runners.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final runner = runners[index];
                      return _RunnerCarouselCard(
                        runner: runner,
                        selected: runner.id == profile.selectedRunnerId,
                        onTap: () => profile.selectWatchedRunner(runner.id),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 24),
              if (runners.isEmpty)
                // Nothing to select from (still loading, or no Runners yet):
                // the panel above already says which.
                const SizedBox.shrink()
              else if (selected == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: BookplatePlate(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Select a Runner above to see their Trellis and recent activity.',
                      style: textTheme.bodyMedium,
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text("${selected.name}'s Trellis", style: textTheme.titleLarge),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: VineVisualizerCard(
                    // The same 180-day season the Runner sees on their own
                    // dashboard — computed once, server-side.
                    vitalityScore: selected.vitalityScore,
                    // A Runner still getting started has nothing to droop.
                    isDrooping: !selected.isGettingStarted &&
                        (selected.isSeasonDrooping || selected.missedAnchorAlert != null),
                    hasData: selected.hasSeasonData || selected.lastCheckInDate != null,
                    showTitle: false,
                    emptyCaption: 'Hold them accountable, and watch them grow.',
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text('Recent Activity', style: textTheme.titleLarge),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: selected.recentActivity.isEmpty
                      ? BookplatePlate(
                          padding: const EdgeInsets.all(20),
                          child: Text('No recent activity yet.', style: textTheme.bodyMedium),
                        )
                      : Column(
                          children: [
                            for (final event in selected.recentActivity) _ActivityTile(event: event),
                          ],
                        ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RunnerCarouselCard extends StatelessWidget {
  const _RunnerCarouselCard({required this.runner, required this.selected, required this.onTap});

  final WatchedRunner runner;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // "Needs Support" is only ever said of a Runner who has committed a Rule
    // of Life and is missing it — never of one who is still setting up.
    final (statusColor, statusLabel) = switch (runner.standing) {
      RunnerStanding.gettingStarted => (AppColors.antiqueBrass, 'Getting Started'),
      RunnerStanding.thriving => (AppColors.forestGreen, 'Thriving'),
      RunnerStanding.needsSupport => (AppColors.terracotta, 'Needs Support'),
    };
    final trimmedName = runner.name.trim();

    return Semantics(
      button: true,
      selected: selected,
      label: '${runner.name}, $statusLabel',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.vellum.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.forestGreen : AppColors.vellumBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.forestGreen,
                  ),
                  // `characters`, not `[0]`: a name that opens with an emoji
                  // or accented letter must not be cut mid-character.
                  child: Text(
                    trimmedName.isNotEmpty ? trimmedName.characters.first.toUpperCase() : '?',
                    style: textTheme.titleLarge?.copyWith(color: AppColors.parchmentLight),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.vellum, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              runner.name,
              style: textTheme.titleSmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                statusLabel,
                maxLines: 1,
                style: textTheme.labelSmall?.copyWith(color: statusColor),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.event});

  final RunnerActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BookplatePlate(
        child: Row(
          children: [
            BrassGlyph(event.glyph),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.message, style: textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    event.relativeTime,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.antiqueBrass),
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

/// A Runner's real request for prayer or a meeting (support_requests) —
/// acknowledging it tells the system it has been seen, once.
///
/// Keyed by request id where it is listed: the tile stays busy after a
/// successful acknowledge (it is about to leave the list), and without a key
/// the next request would inherit that busy state and never respond.
class _SupportRequestTile extends StatefulWidget {
  const _SupportRequestTile({super.key, required this.profile, required this.request});

  final RunnerProfile profile;
  final SupportRequest request;

  @override
  State<_SupportRequestTile> createState() => _SupportRequestTileState();
}

class _SupportRequestTileState extends State<_SupportRequestTile> {
  bool _busy = false;

  Future<void> _acknowledge() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.profile.acknowledgeSupportRequest(widget.request);
    } catch (_) {
      if (mounted) {
        showBookplateNotice(context, "Couldn't mark that as seen. Check your connection.");
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final textTheme = Theme.of(context).textTheme;
    final isPrayer = request.kind == SupportRequestKind.prayer;

    return BookplatePlate(
      accent: AppColors.antiqueBrass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BrassGlyph(isPrayer ? BrassGlyphKind.heart : BrassGlyphKind.calendar),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isPrayer ? 'Prayer Request' : 'Meeting Request',
                  style: textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(request.summary, style: textTheme.bodyMedium),
          if (request.note != null) ...[
            const SizedBox(height: 6),
            Text(
              '"${request.note}"',
              style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 12),
          BookplateButton(
            label: isPrayer ? "I'm Praying" : "I'll Reach Out",
            busy: _busy,
            onPressed: _acknowledge,
          ),
        ],
      ),
    );
  }
}

/// One pending DNA Rhythm unlock request — tapping "Review" opens the
/// Approve/Deny choice. See RunnerProfile.respondToUnlockRequest.
class _UnlockRequestTile extends StatefulWidget {
  const _UnlockRequestTile({super.key, required this.profile, required this.request});

  final RunnerProfile profile;
  final PendingUnlockRequest request;

  @override
  State<_UnlockRequestTile> createState() => _UnlockRequestTileState();
}

class _UnlockRequestTileState extends State<_UnlockRequestTile> {
  bool _busy = false;

  Future<void> _review() async {
    final request = widget.request;
    final approve = await showBookplateChoice<bool>(
      context,
      title: 'Unlock Request',
      message: '${request.runnerName} is asking to unlock "${request.ruleItemTitle}" so they '
          'can change or remove it. Approving opens it to them for the next 24 hours.',
      options: const [(label: 'Approve', value: true), (label: 'Deny', value: false)],
      cancelLabel: 'Decide Later',
    );
    if (approve == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.profile.respondToUnlockRequest(request, approve: approve);
    } catch (_) {
      if (mounted) {
        showBookplateNotice(context, "Couldn't record your answer. Check your connection.");
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final textTheme = Theme.of(context).textTheme;

    return BookplatePlate(
      child: Row(
        children: [
          const BrassGlyph(BrassGlyphKind.unlock, color: AppColors.antiqueBrass),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '${request.runnerName} wants to unlock "${request.ruleItemTitle}"',
              style: textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 12),
          BookplateButton(label: 'Review', compact: true, busy: _busy, onPressed: _review),
        ],
      ),
    );
  }
}

/// A Runner's request to turn their accountability lock off ("Require Witness
/// permission to be removed"). The Runner is told it stays on until a Witness
/// approves — this is where that Witness answers, through
/// [RunnerProfile.resolveLockRemoval]. Approving lifts the lock; declining
/// clears the request and leaves it on.
class _LockRemovalTile extends StatefulWidget {
  const _LockRemovalTile({super.key, required this.profile, required this.runner});

  final RunnerProfile profile;
  final WatchedRunner runner;

  @override
  State<_LockRemovalTile> createState() => _LockRemovalTileState();
}

class _LockRemovalTileState extends State<_LockRemovalTile> {
  /// Which answer is on its way to the server (null when idle).
  bool? _sending;

  Future<void> _answer(bool approve) async {
    if (_sending != null) return;
    final runner = widget.runner;

    if (approve) {
      final confirmed = await showBookplateConfirm(
        context,
        title: 'Lift the Accountability Lock?',
        message: '${runner.firstName} will be able to remove a Witness — including you — '
            'without anyone approving it.',
        confirmLabel: 'Approve',
        cancelLabel: 'Not Now',
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _sending = approve);
    try {
      await widget.profile.resolveLockRemoval(runner.id, approve: approve);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = null);
      showBookplateNotice(context, "Couldn't record your answer. Check your connection.");
      return;
    }
    if (!mounted) return;
    showBookplateNotice(
      context,
      approve
          ? "${runner.firstName}'s accountability lock has been lifted."
          : "The lock stays on. ${runner.firstName}'s request has been cleared.",
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final runner = widget.runner;

    return BookplatePlate(
      accent: AppColors.antiqueBrass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BrassGlyph(BrassGlyphKind.unlock, color: AppColors.antiqueBrass),
              const SizedBox(width: 12),
              Expanded(child: Text('Accountability Lock', style: textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${runner.name} is asking to turn off the rule that a Witness must approve being '
            'removed. It stays on unless you approve.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: BookplateButton(
                  label: 'Keep It On',
                  // The button whose answer is in flight turns busy; the
                  // other one is dimmed until it lands.
                  busy: _sending == false,
                  onPressed: _sending == true ? null : () => _answer(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BookplateButton(
                  label: 'Approve',
                  variant: BookplateButtonVariant.secondary,
                  busy: _sending == true,
                  onPressed: _sending == false ? null : () => _answer(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
