import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';

/// Below this width the shells' secondary AppBar actions collapse into a
/// single overflow menu so the title and role switcher still fit — three
/// icons plus the role chip leave only ~14px for a title on a 320px phone.
const double kNarrowAppBarWidth = 420;

class ShellAction {
  const ShellAction({required this.glyph, required this.label, required this.onPressed});

  final BrassGlyphKind glyph;
  final String label;
  final VoidCallback onPressed;
}

/// The `actions` for a shell's AppBar: each [ShellAction] as its own glyph
/// button on wide screens, or gathered behind one "more" choice panel on
/// narrow ones, always followed by the [roleSwitcher].
List<Widget> shellAppBarActions(
  BuildContext context, {
  required List<ShellAction> actions,
  required Widget roleSwitcher,
}) {
  final narrow = MediaQuery.sizeOf(context).width < kNarrowAppBarWidth;

  if (!narrow) {
    return [
      for (final action in actions)
        BrassGlyphButton(
          kind: action.glyph,
          semanticLabel: action.label,
          onPressed: action.onPressed,
        ),
      roleSwitcher,
    ];
  }

  return [
    BrassGlyphButton(
      kind: BrassGlyphKind.more,
      semanticLabel: 'More',
      onPressed: () async {
        final index = await showBookplateChoice<int>(
          context,
          title: 'More',
          options: [
            for (var i = 0; i < actions.length; i++) (label: actions[i].label, value: i),
          ],
        );
        if (index != null) actions[index].onPressed();
      },
    ),
    roleSwitcher,
  ];
}

/// Tracks a shell's one-off data load so the shell can say "loading" and
/// "couldn't load" — instead of every tab quietly showing its "nothing here
/// yet" panel while the data is still on its way, or after it failed to come.
///
/// The "loading" line is held back for a moment ([_showAfter]) so an instant
/// load (e.g. switching back to a role whose data is already in memory)
/// doesn't flash it for a single frame.
mixin ShellDataLoad<T extends StatefulWidget> on State<T> {
  static const _showAfter = Duration(milliseconds: 350);

  Timer? _loadingLineTimer;

  /// The load has not finished (successfully or otherwise) yet.
  bool shellLoadPending = false;

  /// The load has been running long enough to be worth mentioning.
  bool shellLoadingVisible = false;

  /// The load threw. (An account with nothing in it is not a failure.)
  bool shellLoadFailed = false;

  /// Runs [load], keeping the three flags above in step with it. Never throws.
  Future<void> runShellLoad(Future<void> Function() load) async {
    _loadingLineTimer?.cancel();
    shellLoadPending = true;
    shellLoadFailed = false;
    _loadingLineTimer = Timer(_showAfter, () {
      if (mounted && shellLoadPending) setState(() => shellLoadingVisible = true);
    });

    var failed = false;
    try {
      await load();
    } catch (error) {
      debugPrint('Shell data load failed: $error');
      failed = true;
    }

    _loadingLineTimer?.cancel();
    shellLoadPending = false;
    shellLoadingVisible = false;
    shellLoadFailed = failed;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _loadingLineTimer?.cancel();
    super.dispose();
  }
}

/// The quiet "still loading" line a shell shows above its tabs: a turning
/// brass arc and a few words.
class ShellLoadingLine extends StatelessWidget {
  const ShellLoadingLine({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Row(
        children: [
          BookplateSpinner(size: 16, semanticLabel: label),
          const SizedBox(width: 10),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: AppColors.forestGreen.withValues(alpha: 0.75),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The plate a shell shows above its tabs when its data could not be loaded —
/// so the empty panels beneath are not mistaken for the truth.
class ShellLoadFailedPlate extends StatelessWidget {
  const ShellLoadFailedPlate({super.key, required this.message, this.onRetry});

  final String message;

  /// Shown as a "Retry" button when the load can actually be run again.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: BookplatePlate(
        padding: const EdgeInsets.all(12),
        accent: AppColors.terracotta,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 12),
              BookplateButton(
                label: 'Retry',
                compact: true,
                variant: BookplateButtonVariant.secondary,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The hand-drawn three-rule "hamburger" that opens the enclosing
/// [Scaffold]'s drawer — the woodcut stand-in for the AppBar's automatic
/// Material menu icon. Used as the shells' AppBar `leading`.
class ShellMenuButton extends StatelessWidget {
  const ShellMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open menu',
      onTap: () => Scaffold.of(context).openDrawer(),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => Scaffold.of(context).openDrawer(),
        behavior: HitTestBehavior.opaque,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(painter: _MenuPainter()),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuPainter extends CustomPainter {
  const _MenuPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.forestGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final fraction in const [0.2, 0.5, 0.8]) {
      final y = size.height * fraction;
      canvas.drawLine(Offset(size.width * 0.08, y), Offset(size.width * 0.92, y), paint);
    }
  }

  @override
  bool shouldRepaint(_MenuPainter oldDelegate) => false;
}
