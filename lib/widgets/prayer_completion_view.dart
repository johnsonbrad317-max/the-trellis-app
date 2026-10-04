import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';

/// A short, positive-toned KJV verse shown when a prayer queue is finished
/// — public-domain text, no attribution/licensing concerns.
class PrayerVerse {
  const PrayerVerse({required this.text, required this.reference});

  final String text;
  final String reference;
}

const _prayerCompletionVerses = [
  PrayerVerse(
    text: 'Rejoice evermore. Pray without ceasing. In every thing give thanks: for this '
        'is the will of God in Christ Jesus concerning you.',
    reference: '1 Thessalonians 5:16-18, KJV',
  ),
  PrayerVerse(
    text: 'Be careful for nothing; but in every thing by prayer and supplication with '
        'thanksgiving let your requests be made known unto God.',
    reference: 'Philippians 4:6, KJV',
  ),
  PrayerVerse(
    text: 'The effectual fervent prayer of a righteous man availeth much.',
    reference: 'James 5:16, KJV',
  ),
  PrayerVerse(
    text: 'Call unto me, and I will answer thee, and shew thee great and mighty things, '
        'which thou knowest not.',
    reference: 'Jeremiah 33:3, KJV',
  ),
  PrayerVerse(
    text: 'And this is the confidence that we have in him, that, if we ask any thing '
        'according to his will, he heareth us.',
    reference: '1 John 5:14, KJV',
  ),
];

/// Picks one completion verse at random — call once per screen visit (e.g.
/// from a `late final` field) rather than from inside a `build` method, so
/// it doesn't reroll on every rebuild.
PrayerVerse pickRandomPrayerVerse() =>
    _prayerCompletionVerses[Random().nextInt(_prayerCompletionVerses.length)];

/// Someone a Runner or Witness can send a quick "I prayed for you" text to,
/// offered once their queue is finished.
class PrayerCompletionContact {
  const PrayerCompletionContact({required this.label, required this.phoneNumber});

  final String label;
  final String phoneNumber;
}

/// The shared "you finished your prayer queue" view — used identically by
/// both the Runner's and the Witness's daily prayer flow. Exclusively EB
/// Garamond typography and a randomized KJV verse; no clip-art icons.
class PrayerCompletionView extends StatelessWidget {
  const PrayerCompletionView({
    super.key,
    required this.verse,
    this.contacts = const [],
    this.onTextContact,
  });

  final PrayerVerse verse;

  /// People prayed for this session with a phone number on file — shown as
  /// optional "text to let them know" buttons beneath the verse.
  final List<PrayerCompletionContact> contacts;
  final ValueChanged<PrayerCompletionContact>? onTextContact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 48),
            Text(
              '"${verse.text}"',
              style: textTheme.headlineSmall?.copyWith(fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              verse.reference,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.antiqueBrass,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (contacts.isNotEmpty) ...[
              const SizedBox(height: 40),
              Text(
                'Send a quick text to let them know you prayed today?',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final contact in contacts)
                    BookplateButton(
                      label: 'Text ${contact.label}',
                      variant: BookplateButtonVariant.secondary,
                      compact: true,
                      onPressed: () => onTextContact?.call(contact),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
