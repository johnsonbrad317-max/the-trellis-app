import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';

/// "Home · 12 Elm St\nWork · …", or an invitation when nothing is on file.
String meetingPlacesSummary(RunnerProfile profile) {
  final parts = <String>[];
  final home = profile.homeAddress?.trim() ?? '';
  final work = profile.workAddress?.trim() ?? '';
  if (home.isNotEmpty) parts.add('Home · $home');
  if (work.isNotEmpty) parts.add('Work · $work');
  if (parts.isEmpty) return 'Add your home and work so meeting spots can land midway.';
  return parts.join('\n');
}

/// Enter or change the home / work addresses — the same two fields the
/// Runner's first-run gate asks for, reachable any time from either Connect
/// tab. [partnerWord] is "Witness" or "Runner". Returns true if saved.
///
/// Saving also has the phone work out the map points of these addresses for
/// the midway meeting-spot suggestion (RunnerProfile.updateMeetingPlaces).
Future<bool> editMeetingPlaces(
  BuildContext context,
  RunnerProfile profile, {
  required String partnerWord,
}) async {
  final homeController = TextEditingController(text: profile.homeAddress ?? '');
  final workController = TextEditingController(text: profile.workAddress ?? '');

  final saved = await showBookplateForm<bool>(
    context,
    title: 'Meeting Places',
    message: 'Where you start from, so coffee and lunch spots can be suggested midway '
        'between you and your $partnerWord. Your $partnerWord never sees these.',
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
  if (saved != true || !context.mounted) return false;

  try {
    await profile.updateMeetingPlaces(homeAddress: home, workAddress: work);
  } catch (_) {
    if (context.mounted) {
      showBookplateNotice(context, "Couldn't save your meeting places. Check your connection.");
    }
    return false;
  }
  return true;
}

/// The "Meeting Places" row on a Connect tab: the addresses on file (or an
/// invitation), tap to edit.
class MeetingPlacesRow extends StatelessWidget {
  const MeetingPlacesRow({super.key, required this.profile, required this.partnerWord});

  final RunnerProfile profile;
  final String partnerWord;

  @override
  Widget build(BuildContext context) {
    return BookplatePlate(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: BookplateRow(
        leading: const BrassGlyph(BrassGlyphKind.pin, color: AppColors.antiqueBrass),
        title: 'Meeting Places',
        subtitle: meetingPlacesSummary(profile),
        trailing: const BrassGlyph(BrassGlyphKind.forward),
        onTap: () => editMeetingPlaces(context, profile, partnerWord: partnerWord),
      ),
    );
  }
}
