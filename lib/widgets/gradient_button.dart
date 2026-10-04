import 'package:flutter/material.dart';

import 'bookplate_dialog.dart';

/// The app's single primary call-to-action style: a solid Forest Green fill
/// with parchment lettering inside a brass hairline — used for every primary
/// full-width action (e.g. "Commit to My Rule of Life"). A thin wrapper over
/// [BookplateButton] so the whole app shares one hand-built button.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Shows the turning brass arc and ignores taps while work is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return BookplateButton(label: label, onPressed: onPressed, busy: busy);
  }
}
