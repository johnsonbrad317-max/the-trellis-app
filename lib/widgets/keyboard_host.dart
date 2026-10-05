import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart' show darkStatusBarMarks;
import 'bookplate_dialog.dart' show BookplateButton, BookplateButtonVariant;

/// App-wide keyboard manners, wrapped around the whole app (see main.dart) so
/// no screen has to remember them:
///
///   * a "Done" bar rides on top of the keyboard whenever it is up — iOS gives
///     a multi-line field no key that closes the keyboard, so without this
///     there is no way out of one;
///   * tapping any empty part of the screen puts the keyboard away;
///   * so does dragging a page to scroll it (never a text field's own lines);
///   * a keyboard that is up while NO text field has focus is put away at
///     once. iOS can bring the keyboard back on its own after a system sheet
///     closes (the TestFlight feedback sheet does this); Flutter, which did
///     not ask for it, would otherwise never dismiss it.
///
/// Everything beneath is told the keyboard is [barHeight] taller than it is,
/// so scaffolds, dialogs and sheets lift their content clear of the bar.
///
/// It also sets dark status-bar marks for screens that have no app bar.
class KeyboardHost extends StatefulWidget {
  const KeyboardHost({super.key, required this.child});

  final Widget child;

  /// Height of the "Done" bar.
  static const double barHeight = 44;

  /// Puts the keyboard away: drops text focus and, belt and braces, tells the
  /// platform to hide it (which also clears a keyboard Flutter never opened).
  static void dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// Whether a text field currently has the keyboard's attention.
  static bool textFieldHasFocus() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  State<KeyboardHost> createState() => _KeyboardHostState();
}

class _KeyboardHostState extends State<KeyboardHost> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _keyboardUp => mounted && View.of(context).viewInsets.bottom > 0;

  /// After the frame, so focus has settled: a keyboard nobody is typing into
  /// goes away. (A field that is opening the keyboard already has focus by
  /// the time the keyboard starts to rise, so this never fights a real one.)
  void _checkForOrphanKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_keyboardUp && !KeyboardHost.textFieldHasFocus()) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
    });
  }

  @override
  void didChangeMetrics() => _checkForOrphanKeyboard();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkForOrphanKeyboard();
  }

  void _onTapEmptySpace() {
    if (_keyboardUp || KeyboardHost.textFieldHasFocus()) KeyboardHost.dismissKeyboard();
  }

  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.direction == ScrollDirection.idle) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    if (!_keyboardUp) return false;
    // Scrolling through one's own long text is not leaving the field.
    if (notification.context?.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    KeyboardHost.dismissKeyboard();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final keyboardUp = keyboard > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: darkStatusBarMarks,
      child: NotificationListener<UserScrollNotification>(
        onNotification: _onUserScroll,
        // Translucent: every button, field and scroll view beneath still gets
        // its own taps first; only a tap nothing else wanted lands here.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _onTapEmptySpace,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Always present (never conditionally wrapped), so the app
              // beneath is not rebuilt from scratch when the keyboard moves.
              MediaQuery(
                data: media.copyWith(
                  viewInsets: media.viewInsets.copyWith(
                    bottom: keyboardUp ? keyboard + KeyboardHost.barHeight : keyboard,
                  ),
                ),
                child: widget.child,
              ),
              if (keyboardUp)
                Positioned(left: 0, right: 0, bottom: keyboard, child: const _DoneBar()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The strip above the keyboard: parchment, a brass hairline, and "Done".
class _DoneBar extends StatelessWidget {
  const _DoneBar();

  @override
  Widget build(BuildContext context) {
    // An invisible Material ancestor only so the label takes the theme's text
    // style; it paints nothing.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: KeyboardHost.barHeight,
        decoration: BoxDecoration(
          color: AppColors.vellum,
          border: Border(
            top: BorderSide(color: AppColors.antiqueBrass.withValues(alpha: 0.6)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerRight,
        child: const BookplateButton(
          label: 'Done',
          variant: BookplateButtonVariant.link,
          compact: true,
          onPressed: KeyboardHost.dismissKeyboard,
        ),
      ),
    );
  }
}
