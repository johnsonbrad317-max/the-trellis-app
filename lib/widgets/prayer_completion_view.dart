import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';

/// A short, positive-toned verse shown when a prayer queue is finished — in
/// the Berean Standard Bible, like every verse in the app (public domain).
class PrayerVerse {
  const PrayerVerse({required this.text, required this.reference});

  final String text;
  final String reference;
}

const _prayerCompletionVerses = [
  PrayerVerse(
    text: 'Rejoice at all times. Pray without ceasing. Give thanks in every circumstance, for '
        'this is God’s will for you in Christ Jesus.',
    reference: '1 Thessalonians 5:16–18, BSB',
  ),
  PrayerVerse(
    text: 'Be anxious for nothing, but in everything, by prayer and petition, with '
        'thanksgiving, present your requests to God.',
    reference: 'Philippians 4:6, BSB',
  ),
  PrayerVerse(
    text: 'The prayer of a righteous man has great power to prevail.',
    reference: 'James 5:16, BSB',
  ),
  PrayerVerse(
    text: 'Call to Me, and I will answer and show you great and unsearchable things you do '
        'not know.',
    reference: 'Jeremiah 33:3, BSB',
  ),
  PrayerVerse(
    text: 'And this is the confidence that we have before Him: If we ask anything according '
        'to His will, He hears us.',
    reference: '1 John 5:14, BSB',
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
  const PrayerCompletionContact({required this.label, required this.phoneNumber, this.scripture});

  final String label;
  final String phoneNumber;

  /// The scripture saved on their prayer card, if any — offered first when
  /// adding a verse to the text.
  final String? scripture;

  /// How a text greets them: "Kevin" for "Kevin Barb". A prayer's title is
  /// usually a full name; nobody texts a friend "Hey Kevin Barb".
  String get firstName {
    final words = label.trim().split(RegExp(r'\s+'));
    return words.first.isEmpty ? label.trim() : words.first;
  }
}

/// The shared "you finished your prayer queue" view — used identically by
/// both the Runner's and the Witness's daily prayer flow. Exclusively EB
/// Garamond typography and a randomized BSB verse; no clip-art icons.
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
