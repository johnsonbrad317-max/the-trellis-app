import 'package:flutter/material.dart';

import '../../models/prayer_item.dart';
import '../../models/runner_profile.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/launch_link.dart';
import '../../widgets/prayer_card.dart';
import '../../widgets/prayer_completion_view.dart';
import '../../widgets/trellis_scaffold.dart';

/// A swipeable flashcard walk-through of today's prayer queue. Swipe a card
/// away, or tap "Mark as Prayed Today", to move to the next one. Each card is
/// a [PrayerCard] — the framed devotional bookplate with the person's photo
/// or initials.
class DailyPrayerScreen extends StatefulWidget {
  const DailyPrayerScreen({super.key, required this.profile, required this.queue});

  final RunnerProfile profile;
  final List<PrayerItem> queue;

  @override
  State<DailyPrayerScreen> createState() => _DailyPrayerScreenState();
}

class _DailyPrayerScreenState extends State<DailyPrayerScreen> {
  late final List<PrayerItem> _remaining = [...widget.queue];
  late final PrayerVerse _completionVerse = pickRandomPrayerVerse();

  /// People (with a phone number) prayed for this session — the "let them
  /// know" text offer moves here, to the end-of-session summary, instead of
  /// interrupting with a dialog after every single card.
  final List<PrayerItem> _prayedForWithPhone = [];

  /// How far each waiting card's top edge shows above the card in front.
  static const _peek = 10.0;

  void _markPrayed(PrayerItem item) {
    // The card moves on at once; if the save fails the Runner is told, since
    // this prayer would otherwise quietly come back tomorrow as un-prayed.
    runWithFailureNotice(
      context,
      () => widget.profile.markPrayedToday(item.id),
      failure: "Couldn't save that you prayed for ${item.title}. Check your connection.",
    );

    final phone = item.phoneNumber?.trim();
    if (item.category == PrayerCategory.people && (phone?.isNotEmpty ?? false)) {
      _prayedForWithPhone.add(item);
    }

    setState(() => _remaining.removeWhere((i) => i.id == item.id));
  }

  Future<void> _sendEncouragement(PrayerCompletionContact contact) => launchOrNotify(
        context,
        smsUri(
          contact.phoneNumber,
          body: "Hey ${contact.label}, just wanted to let you know I've been praying for you "
              'today. Hope you have a wonderful day!',
        ),
        unavailable: 'No messaging app is available on this device.',
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'Daily Prayer'),
      body: _remaining.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Opened with nothing left in the queue: say why there are no
                // cards, rather than congratulating a session that never ran.
                if (widget.queue.isEmpty)
                  Text(
                    'You have already prayed through your garden today.',
                    style: textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                PrayerCompletionView(
                  verse: _completionVerse,
                  contacts: [
                    for (final item in _prayedForWithPhone)
                      PrayerCompletionContact(label: item.title, phoneNumber: item.phoneNumber!),
                  ],
                  onTextContact: _sendEncouragement,
                ),
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    // The card takes the width it is given (up to a readable
                    // 340) and about half the screen's height: on a small
                    // phone the count, the card and the button still fit
                    // without the page scrolling, and a tall phone is not left
                    // mostly empty. Long prayers scroll inside the card.
                    final cardWidth = constraints.maxWidth < 340 ? constraints.maxWidth : 340.0;
                    final cardHeight =
                        (MediaQuery.sizeOf(context).height * 0.52).clamp(340.0, 440.0).toDouble();

                    return SizedBox(
                      // Room above the top card for the two behind it to show.
                      height: cardHeight + 2 * _peek,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          for (var i = (_remaining.length - 1).clamp(0, 2); i >= 0; i--)
                            if (i == 0)
                              Dismissible(
                                key: ValueKey(_remaining[i].id),
                                direction: DismissDirection.horizontal,
                                onDismissed: (_) => _markPrayed(_remaining[i]),
                                child: SizedBox(
                                  width: cardWidth,
                                  height: cardHeight,
                                  child: PrayerCard(item: _remaining[i]),
                                ),
                              )
                            else
                              // Each waiting card is a little smaller and
                              // lifted so its top edge shows above the one in
                              // front. (Scaling shrinks a card toward its
                              // centre, which lowers its top edge by half of
                              // what it lost — hence the second term.)
                              Transform.translate(
                                offset: Offset(0, -(_peek * i + cardHeight * 0.02 * i)),
                                child: Transform.scale(
                                  scale: 1 - (0.04 * i),
                                  child: SizedBox(
                                    width: cardWidth,
                                    height: cardHeight,
                                    child: PrayerCard(item: _remaining[i], faded: true),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    );
                  },
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
