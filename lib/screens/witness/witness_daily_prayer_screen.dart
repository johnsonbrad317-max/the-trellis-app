import 'package:flutter/material.dart';

import '../../models/runner_profile.dart';
import '../../models/watched_prayer_item.dart';
import '../../models/witness_messages.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/launch_link.dart';
import '../../widgets/prayer_completion_view.dart';
import '../../widgets/trellis_scaffold.dart';

/// A swipeable flashcard walk-through of today's intercession queue for one
/// watched Runner — their shared requests plus this Witness's own private
/// prayers for them, combined. Swipe a card away, or tap "Mark as Prayed
/// Today", to move to the next one.
class WitnessDailyPrayerScreen extends StatefulWidget {
  const WitnessDailyPrayerScreen({
    super.key,
    required this.profile,
    required this.runnerId,
    required this.runnerFirstName,
    required this.runnerPhoneNumber,
    required this.queue,
  });

  final RunnerProfile profile;
  final String runnerId;
  final String runnerFirstName;
  final String? runnerPhoneNumber;
  final List<WatchedPrayerItem> queue;

  @override
  State<WitnessDailyPrayerScreen> createState() => _WitnessDailyPrayerScreenState();
}

class _WitnessDailyPrayerScreenState extends State<WitnessDailyPrayerScreen> {
  late final List<WatchedPrayerItem> _remaining = [...widget.queue];
  late final PrayerVerse _completionVerse = pickRandomPrayerVerse();

  Future<void> _markPrayed(WatchedPrayerItem item) async {
    // The card leaves the stack FIRST, synchronously: a swiped-away
    // Dismissible must be out of the tree before anything is awaited (Flutter
    // asserts on a dismissed Dismissible that is still built), and it also
    // means a second tap can't mark the same card twice.
    if (!_remaining.any((i) => i.id == item.id)) return;
    setState(() => _remaining.removeWhere((i) => i.id == item.id));

    // If the save fails the Witness is told, since this prayer would otherwise
    // quietly come back tomorrow as un-prayed.
    runWithFailureNotice(
      context,
      () => widget.profile.markWatchedPrayerPrayedToday(widget.runnerId, item.id),
      failure: "Couldn't save that you prayed for this. Check your connection.",
    );

    // The "let them know" offer waits for the end of the session (the
    // completion view below), exactly as it does for a Runner praying through
    // their own list — not a dialog after every card.
    _prayedThisSession = true;
  }

  /// At least one card was prayed through in this sitting.
  bool _prayedThisSession = false;

  String? get _runnerPhone {
    final phone = widget.runnerPhoneNumber?.trim();
    return phone == null || phone.isEmpty ? null : phone;
  }

  /// Opens Messages to the Runner with a short "I prayed for you" draft. It
  /// never names a request — a text shows on a lock screen, and what someone
  /// asked prayer for is theirs to keep private.
  Future<void> _textRunner(PrayerCompletionContact contact) => launchOrNotify(
        context,
        smsUri(
          contact.phoneNumber,
          body: witnessTextFor(WitnessTextReason.prayed, firstName: widget.runnerFirstName),
        ),
        unavailable: 'No messaging app is available on this device.',
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: BookplateAppBar(title: 'Praying for ${widget.runnerFirstName}'),
      body: _remaining.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Opened with nothing left in the queue: say why there are no
                // cards, rather than congratulating a session that never ran.
                if (widget.queue.isEmpty)
                  Text(
                    'You have already prayed through '
                    "${widget.runnerFirstName}'s requests today.",
                    style: textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                PrayerCompletionView(
                  verse: _completionVerse,
                  contacts: [
                    if (_prayedThisSession && _runnerPhone != null)
                      PrayerCompletionContact(
                        label: widget.runnerFirstName,
                        phoneNumber: _runnerPhone!,
                      ),
                  ],
                  onTextContact: _textRunner,
                ),
                if (_prayedThisSession && _runnerPhone == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    "${widget.runnerFirstName} hasn't added a mobile number yet, so there is no "
                    'one to address a text to. They can add it under Account & Membership in '
                    'the menu.',
                    style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_remaining.length} left to pray through',
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var i = (_remaining.length - 1).clamp(0, 2); i >= 0; i--)
                        if (i == 0)
                          Dismissible(
                            key: ValueKey(_remaining[i].id),
                            direction: DismissDirection.horizontal,
                            onDismissed: (_) => _markPrayed(_remaining[i]),
                            child: _WitnessPrayerCard(item: _remaining[i]),
                          )
                        else
                          Transform.translate(
                            offset: Offset(0, -8.0 * i),
                            child: Transform.scale(
                              scale: 1 - (0.04 * i),
                              child: _WitnessPrayerCard(item: _remaining[i], faded: true),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: GradientButton(
                    label: 'Mark as Prayed Today',
                    onPressed: () => _markPrayed(_remaining.first),
                  ),
                ),
              ],
            ),
    );
  }
}

class _WitnessPrayerCard extends StatelessWidget {
  const _WitnessPrayerCard({required this.item, this.faded = false});

  final WatchedPrayerItem item;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: faded ? 0.5 : 1,
      child: BookplatePlate(
        padding: EdgeInsets.zero,
        child: Container(
          width: 300,
          height: 280,
          padding: const EdgeInsets.all(24),
          // The card is a fixed size, but a request's details are free text:
          // still centred when short, and scrollable (never overflowing the
          // card) when long or when the text size is set large.
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrassGlyph(BrassGlyphKind.heart, size: 32, color: AppColors.forestGreen),
                  const SizedBox(height: 16),
                  Text(item.title, style: textTheme.headlineSmall),
                  if (item.details.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(item.details, style: textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
