import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A thin strip across the top of the web build, saying what it is: a preview
/// of the iPhone app, with the phone-only parts named so nobody mistakes
/// their absence for a fault. Only ever shown on the web (see main.dart).
class WebPreviewBanner extends StatelessWidget {
  const WebPreviewBanner({super.key, required this.child});

  final Widget child;

  static const message = 'Web preview of The Trellis. Reminders, notifications, calendar '
      'sharing and texting work in the iPhone app.';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: AppColors.forestGreen,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.parchmentLight,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          ),
        ),
        Expanded(
          // The page below starts under the strip, so it needs no top inset.
          child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
        ),
      ],
    );
  }
}
