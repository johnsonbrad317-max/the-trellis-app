import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/witness_notice.dart';
import 'bookplate_dialog.dart';

/// Shows one departure note — "Sarah has left The Trellis" — on a bookplate,
/// with a single OK. Resolves when it is closed (OK or a tap outside; either
/// counts as read).
Future<void> showDepartureNoticeDialog(BuildContext context, WitnessNotice notice) async {
  await showBookplateForm<void>(
    context,
    title: notice.title,
    message: notice.message,
    barrierLabel: 'OK',
    bodyBuilder: (context, setState) => const SizedBox.shrink(),
    actionsBuilder: (dialogContext, setState) => [
      BookplateButton(
        label: 'OK',
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );
}

/// Shows each of [profile]'s unseen departure notes once, one after another,
/// marking each seen as it is closed (`mark_witness_notice_seen`). Does nothing
/// for a preview profile, and nothing if it is already showing notes for this
/// profile (the Witness shell calls it on every change of the profile).
///
/// Each note is claimed before its dialog opens, so neither a rebuild, a
/// refetch, nor a second Witness shell can show it twice.
Future<void> showPendingDepartureNotices(BuildContext context, RunnerProfile profile) async {
  if (profile.isPreview) return;
  if (!_showingFor.add(profile)) return;
  try {
    while (true) {
      if (!context.mounted) return;
      final pending = profile.pendingWitnessNotices;
      if (pending.isEmpty) return;
      final notice = pending.first;
      profile.claimWitnessNotice(notice);
      await showDepartureNoticeDialog(context, notice);
      await profile.markWitnessNoticeSeen(notice);
    }
  } finally {
    _showingFor.remove(profile);
  }
}

/// Profiles a [showPendingDepartureNotices] loop is currently running for.
final Set<RunnerProfile> _showingFor = Set.identity();
