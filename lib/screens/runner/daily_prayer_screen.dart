import 'package:flutter/material.dart';

import '../../models/prayer_item.dart';
import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/launch_link.dart';
import '../../widgets/prayer_completion_view.dart';
import '../../widgets/trellis_scaffold.dart';

/// A swipeable flashcard walk-through of today's prayer queue. Swipe a card
/// away, or tap "Mark as Prayed Today", to move to the next one.
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
                SizedBox(
                  height: 360,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var i = (_remaining.length - 1).clamp(0, 2); i >= 0; i--)
                        if (i == 0)
                          Dismissible(
                            key: ValueKey(_remaining[i].id),
                            direction: DismissDirection.horizontal,
                            onDismissed: (_) => _markPrayed(_remaining[i]),
                            child: _PrayerCard(item: _remaining[i]),
                          )
                        else
                          Transform.translate(
                            offset: Offset(0, -8.0 * i),
                            child: Transform.scale(
                              scale: 1 - (0.04 * i),
                              child: _PrayerCard(item: _remaining[i], faded: true),
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

class _PrayerCard extends StatelessWidget {
  const _PrayerCard({required this.item, this.faded = false});

  final PrayerItem item;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: faded ? 0.5 : 1,
      child: SizedBox(
        width: 300,
        height: 340,
        child: BookplatePlate(
          padding: const EdgeInsets.all(24),
          emphasized: true,
          // The card is a fixed size, but a prayer's details are free text:
          // still centred when short, and scrollable (never overflowing the
          // card) when long or when the text size is set large.
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrassGlyph(item.category.glyph, size: 32, color: AppColors.forestGreen),
                  const SizedBox(height: 16),
                  Text(item.title, style: textTheme.headlineSmall),
                  if (item.details.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(item.details, style: textTheme.bodyMedium),
                  ],
                  if (item.scripture != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      item.scripture!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.antiqueBrass,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
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
