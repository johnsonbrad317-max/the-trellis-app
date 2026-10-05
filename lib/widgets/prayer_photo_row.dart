import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/prayer_photo_service.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'prayer_medallion.dart';

/// The compact "photo for this person" control: a medallion preview with
/// Add Photo — or Change / Remove once there is one — beside it, and a line
/// saying who can see it. It only reports taps; the form or sheet hosting it
/// owns the choosing, uploading and removing.
class PrayerPhotoRow extends StatelessWidget {
  const PrayerPhotoRow({
    super.key,
    required this.name,
    required this.onPick,
    required this.onRemove,
    this.photoPath,
    this.photoBytes,
    this.busy = false,
    this.service,
  });

  /// The person's name so far — the preview shows its initials until there is
  /// a photo.
  final String name;

  /// A photo already stored for this prayer.
  final String? photoPath;

  /// A photo chosen in a form but not uploaded yet.
  final Uint8List? photoBytes;

  final VoidCallback onPick;
  final VoidCallback onRemove;

  /// A photo is being uploaded or removed: the actions give way to a spinner.
  final bool busy;

  final PrayerPhotoService? service;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasPhoto = photoPath != null || photoBytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            PrayerMedallion(
              name: name,
              photoPath: photoPath,
              photoBytes: photoBytes,
              size: 56,
              service: service,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: BookplateSpinner(semanticLabel: 'Saving photo'),
                      ),
                    )
                  // A Wrap, so the two actions stack rather than overflow in a
                  // narrow dialog or at a large text size.
                  : Wrap(
                      children: [
                        BookplateButton(
                          label: hasPhoto ? 'Change' : 'Add Photo',
                          variant: BookplateButtonVariant.link,
                          compact: true,
                          onPressed: onPick,
                        ),
                        if (hasPhoto)
                          BookplateButton(
                            label: 'Remove',
                            variant: BookplateButtonVariant.link,
                            compact: true,
                            onPressed: onRemove,
                          ),
                      ],
                    ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Photos are private to you.', style: textTheme.bodySmall),
      ],
    );
  }
}
