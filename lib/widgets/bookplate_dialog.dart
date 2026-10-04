import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bookplate_plate.dart' show BookplateSpinner;
import 'corner_vine_background.dart' show kVineSafeInset;

/// How a [BookplateButton] is dressed. All three share the antique-brass
/// border; they differ only in fill and ink.
enum BookplateButtonVariant {
  /// Forest-green fill, parchment lettering — the one action to take.
  primary,

  /// Parchment fill, forest-green lettering — the way out.
  secondary,

  /// Terracotta lettering on parchment — an irreversible action.
  danger,

  /// Antique-brass lettering with no fill or border — a quiet inline action
  /// (the woodcut replacement for `TextButton`).
  link,
}

/// A hand-built button: a plain [Container] with a brass border and serif
/// lettering, standing in for Material's FilledButton/TextButton/
/// ElevatedButton. A null [onPressed] renders it dimmed and inert, which is
/// also how a "working…" state is shown (change [label] while disabled).
///
/// Full-width by default; [compact] sizes it to its label for use inside a
/// row (e.g. beside a rhythm's title).
class BookplateButton extends StatelessWidget {
  const BookplateButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = BookplateButtonVariant.primary,
    this.compact = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final BookplateButtonVariant variant;
  final bool compact;

  /// Shows a turning brass arc beside the label and ignores taps — the
  /// "working…" state, replacing a `CircularProgressIndicator` in a button.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final (fill, ink) = switch (variant) {
      BookplateButtonVariant.primary => (AppColors.forestGreen, AppColors.parchmentLight),
      BookplateButtonVariant.secondary => (AppColors.parchmentLight, AppColors.forestGreen),
      BookplateButtonVariant.danger => (AppColors.parchmentLight, AppColors.terracotta),
      BookplateButtonVariant.link => (Colors.transparent, AppColors.antiqueBrass),
    };
    final borderColor = switch (variant) {
      BookplateButtonVariant.danger => AppColors.terracotta,
      BookplateButtonVariant.link => Colors.transparent,
      _ => AppColors.antiqueBrass,
    };
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = (compact ? textTheme.labelMedium : textTheme.labelLarge)?.copyWith(
      color: ink,
      fontWeight: FontWeight.w600,
      letterSpacing: compact ? 0.6 : 1.1,
      decoration: variant == BookplateButtonVariant.link ? TextDecoration.underline : null,
      decorationColor: ink,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      // excludeSemantics drops the GestureDetector's own tap action along
      // with the label's duplicate text, so the action is declared here —
      // without it a screen reader announces a button it cannot press.
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: onPressed == null ? 0.5 : 1,
          child: Container(
            width: compact ? null : double.infinity,
            // 44 is the smallest comfortable touch target; a compact button
            // never drops below it.
            constraints: BoxConstraints(minHeight: compact ? 44 : 48),
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                : const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            alignment: compact ? null : Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  BookplateSpinner(
                    size: 16,
                    color: variant == BookplateButtonVariant.primary
                        ? AppColors.parchmentLight
                        : AppColors.antiqueBrass,
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(label, textAlign: TextAlign.center, style: labelStyle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A confirm/cancel prompt on a double-bordered parchment bookplate (the same
/// edging as the sign-in panel and role cards) — the woodcut replacement for
/// `showDialog` + `AlertDialog`. Resolves to true only if the confirm button
/// is tapped; tapping outside or the cancel button resolves to false.
Future<bool> showBookplateConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final confirmed = await showBookplateForm<bool>(
    context,
    title: title,
    message: message,
    barrierLabel: cancelLabel,
    bodyBuilder: (context, setState) => const SizedBox.shrink(),
    actionsBuilder: (dialogContext, setState) => [
      BookplateButton(
        label: confirmLabel,
        variant: destructive ? BookplateButtonVariant.danger : BookplateButtonVariant.primary,
        onPressed: () => Navigator.of(dialogContext).pop(true),
      ),
      BookplateButton(
        label: cancelLabel,
        variant: BookplateButtonVariant.secondary,
        onPressed: () => Navigator.of(dialogContext).pop(false),
      ),
    ],
  );
  return confirmed ?? false;
}

/// "Pick one of these" on a bookplate — the woodcut replacement for
/// `SimpleDialog`. Resolves to the chosen value, or null if dismissed.
Future<T?> showBookplateChoice<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<({String label, T value})> options,
  String cancelLabel = 'Cancel',
}) {
  return showBookplateForm<T>(
    context,
    title: title,
    message: message,
    barrierLabel: cancelLabel,
    bodyBuilder: (context, setState) => const SizedBox.shrink(),
    actionsBuilder: (dialogContext, setState) => [
      for (final option in options)
        BookplateButton(
          label: option.label,
          onPressed: () => Navigator.of(dialogContext).pop(option.value),
        ),
      BookplateButton(
        label: cancelLabel,
        variant: BookplateButtonVariant.secondary,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );
}

/// The general bookplate dialog: a title, optional [message], a [bodyBuilder]
/// for inputs/choosers, and [actionsBuilder] for the stacked buttons. Both
/// builders receive a [StateSetter] scoped to the dialog, so a form can
/// rebuild itself without a separate StatefulWidget. Pop with a value from an
/// action to resolve the future; tapping the barrier resolves it to null.
Future<T?> showBookplateForm<T>(
  BuildContext context, {
  required String title,
  String? message,
  String barrierLabel = 'Dismiss',
  required Widget Function(BuildContext context, StateSetter setState) bodyBuilder,
  required List<Widget> Function(BuildContext dialogContext, StateSetter setState) actionsBuilder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: AppColors.forestGreen.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) => _BookplatePanel(
      title: title,
      message: message,
      bodyBuilder: bodyBuilder,
      actionsBuilder: actionsBuilder,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _BookplatePanel extends StatelessWidget {
  const _BookplatePanel({
    required this.title,
    required this.message,
    required this.bodyBuilder,
    required this.actionsBuilder,
  });

  final String title;
  final String? message;
  final Widget Function(BuildContext context, StateSetter setState) bodyBuilder;
  final List<Widget> Function(BuildContext dialogContext, StateSetter setState) actionsBuilder;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: title,
      // A dialog route has no Scaffold to resize it, so the keyboard would
      // otherwise sit on top of the lower fields and the action buttons:
      // lift the whole panel by the keyboard's height and let it scroll in
      // what is left.
      child: AnimatedPadding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              // An invisible Material ancestor: paints nothing, but supplies
              // the text style (no debug underline) and the ancestor that a
              // TextField inside a form body requires.
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.parchmentLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.antiqueBrass),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.forestGreen.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.vellum,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.6)),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        final actions = actionsBuilder(context, setState);
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              title,
                              style: textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            if (message != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                message!,
                                style: textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 16),
                            bodyBuilder(context, setState),
                            const SizedBox(height: 8),
                            for (var i = 0; i < actions.length; i++) ...[
                              const SizedBox(height: 10),
                              actions[i],
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Disposes [controllers] once the dialog or sheet that hosted their fields
/// has finished closing. A bookplate route's future resolves as soon as it is
/// popped, while its exit transition is still building the fields — so
/// disposing straight away would hand a live TextField a dead controller.
/// Call this right after the `await showBookplateForm/Sheet(...)` returns.
void disposeAfterBookplateClose(Iterable<ChangeNotifier> controllers) {
  final pending = controllers.toList();
  Future<void>.delayed(const Duration(milliseconds: 500), () {
    for (final controller in pending) {
      controller.dispose();
    }
  });
}

/// Awaits [action]; if it throws, says so with [failure] as a notice instead
/// of letting the error vanish (and the screen keep claiming it worked).
/// Resolves to whether the action succeeded.
Future<bool> runWithFailureNotice(
  BuildContext context,
  Future<void> Function() action, {
  required String failure,
}) async {
  try {
    await action();
    return true;
  } catch (error) {
    debugPrint('Action failed: $error');
    if (context.mounted) showBookplateNotice(context, failure);
    return false;
  }
}

/// A parchment panel that rises from the bottom edge — the woodcut
/// replacement for `showModalBottomSheet`. [builder] supplies the content
/// (already padded; it may scroll); pop the sheet context with a value to
/// resolve the future. Tapping the barrier resolves to null unless
/// [dismissible] is false.
Future<T?> showBookplateSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Dismiss',
    barrierColor: AppColors.forestGreen.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (sheetContext, animation, secondaryAnimation) {
      // The sheet rides on top of the keyboard (its bottom edge is lifted by
      // the keyboard's height) and is never taller than the room left above
      // it. Merely padding the sheet's contents instead left its scroll area
      // running on behind the keyboard — so focusing a field low in a sheet
      // "scrolled it into view" underneath the keys.
      final screenHeight = MediaQuery.sizeOf(sheetContext).height;
      final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      final roomAboveKeyboard =
          screenHeight - keyboard - MediaQuery.paddingOf(sheetContext).top - 8;
      final preferred = screenHeight * 0.88;
      // (Floor of 160 so a sheet is still usable on a tiny landscape screen.)
      final cap = roomAboveKeyboard < 160 ? 160.0 : roomAboveKeyboard;
      final maxHeight = preferred < cap ? preferred : cap;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.parchmentLight,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border.all(color: AppColors.antiqueBrass),
              ),
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.vellum,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.6)),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Builder(builder: builder),
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

OverlayEntry? _activeNotice;
Timer? _noticeTimer;

/// A brief status line in a forest-green plate with a brass border — the
/// woodcut replacement for `ScaffoldMessenger` + `SnackBar`. Shows one notice
/// at a time (a new one replaces the old), never intercepts touches, and sits
/// above the bottom vine inset so it stays clear of the corner foliage.
void showBookplateNotice(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _noticeTimer?.cancel();
  final previous = _activeNotice;
  if (previous != null && previous.mounted) previous.remove();

  final entry = OverlayEntry(builder: (context) => _BookplateNotice(message: message));
  _activeNotice = entry;
  overlay.insert(entry);

  _noticeTimer = Timer(duration, () {
    if (entry.mounted) entry.remove();
    if (_activeNotice == entry) _activeNotice = null;
  });
}

class _BookplateNotice extends StatelessWidget {
  const _BookplateNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              // Rides above the keyboard too — a notice raised from a form
              // (e.g. "Couldn't save…") must not be hidden behind it.
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                kVineSafeInset + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: DefaultTextStyle(
                    style: textTheme.bodyMedium ?? const TextStyle(),
                    child: Semantics(
                      liveRegion: true,
                      label: message,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.forestGreen,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.forestGreen.withValues(alpha: 0.25),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(color: AppColors.parchmentLight),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
