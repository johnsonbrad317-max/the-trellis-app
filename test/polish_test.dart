import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/services/feedback_service.dart';
import 'package:trellis/services/share_service.dart';
import 'package:trellis/theme/app_colors.dart';
import 'package:trellis/widgets/bookplate_app_bar.dart';
import 'package:trellis/widgets/bottom_vine_frame.dart';
import 'package:trellis/widgets/brass_glyph.dart';
import 'package:trellis/widgets/cloud_empty_state.dart';
import 'package:trellis/widgets/vine_safe_app_bar.dart';

void main() {
  group('FeedbackService.buildPayload', () {
    test('carries exactly the fields the function expects, and nothing identifying', () {
      final payload = FeedbackService.buildPayload(
        rating: 4,
        category: 'bug',
        message: '  The button does nothing.  ',
        replyOk: false,
        role: 'runner',
        platform: 'iOS',
      );

      expect(payload, {
        'rating': 4,
        'category': 'bug',
        'message': 'The button does nothing.',
        'reply_ok': false,
        'role': 'runner',
        'platform': 'iOS',
      });
      expect(payload.keys, isNot(contains('email')));
      expect(payload.keys, isNot(contains('user_id')));
      expect(payload.keys, isNot(contains('name')));
    });

    test('reply consent is passed through, defaulting the platform when omitted', () {
      final payload = FeedbackService.buildPayload(
        rating: 5,
        category: 'ui_usability',
        message: 'Lovely.',
        replyOk: true,
        role: 'witness',
      );
      expect(payload['reply_ok'], isTrue);
      expect(payload['platform'], isNotEmpty);
    });
  });

  group('shareText', () {
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

    /// Mocks the OS share sheet (what [reply] returns is what the plugin would
    /// report) and the clipboard, and mounts one share button. Returns the
    /// captured share arguments and clipboard text through the callbacks.
    Future<void> pumpShareButton(
      WidgetTester tester, {
      required Future<Object?> Function(MethodCall call) reply,
      required void Function(Map<Object?, Object?> shareArgs) onShare,
      required void Function(String text) onClipboard,
    }) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        onShare(call.arguments as Map<Object?, Object?>);
        return reply(call);
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          onClipboard((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(shareChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Builder(
                builder: (buttonContext) => GestureDetector(
                  onTap: () => shareText(buttonContext, 'Use pairing code ABC234.'),
                  child: const SizedBox(width: 120, height: 48, child: Text('share')),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('opens the share sheet anchored to the tapped button', (tester) async {
      Map<Object?, Object?>? args;
      String? clipboard;
      await pumpShareButton(
        tester,
        reply: (call) async => 'com.apple.UIKit.activity.Message', // shared
        onShare: (a) => args = a,
        onClipboard: (t) => clipboard = t,
      );

      await tester.tap(find.text('share'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(args!['text'], 'Use pairing code ABC234.');
      // iPad/macOS need this source rectangle or they show nothing at all.
      expect(args!['originX'], 40);
      expect(args!['originY'], 40);
      expect(args!['originWidth'], 120);
      expect(args!['originHeight'], 48);
      // A successful share must not also copy to the clipboard.
      expect(clipboard, isNull);
      expect(find.textContaining("Sharing isn't available"), findsNothing);
    });

    testWidgets('falls back to copying, and says so, when the OS cannot share', (tester) async {
      String? clipboard;
      await pumpShareButton(
        tester,
        reply: (call) async => null, // the plugin reads null as "unavailable"
        onShare: (_) {},
        onClipboard: (t) => clipboard = t,
      );

      await tester.tap(find.text('share'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(clipboard, 'Use pairing code ABC234.');
      expect(find.textContaining("Sharing isn't available here"), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // let the notice's timer finish
    });

    testWidgets('also falls back if the platform call throws', (tester) async {
      String? clipboard;
      await pumpShareButton(
        tester,
        reply: (call) async => throw PlatformException(code: 'share_failed'),
        onShare: (_) {},
        onClipboard: (t) => clipboard = t,
      );

      await tester.tap(find.text('share'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(clipboard, 'Use pairing code ABC234.');
      expect(find.textContaining("Sharing isn't available here"), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('shareOriginFor returns the tapped widget\'s on-screen rectangle', (tester) async {
      Rect? origin;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Builder(
                builder: (context) => GestureDetector(
                  onTap: () => origin = shareOriginFor(context),
                  child: const SizedBox(width: 100, height: 50, child: Text('go')),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('go'));
      expect(origin, isNotNull);
      expect(origin!.size, const Size(100, 50));
      expect(origin!.topLeft, const Offset(40, 40));
    });
  });

  group('slimmer header', () {
    test('the toolbar is 44', () {
      expect(BookplateAppBar.height, 44);
      expect(const BookplateAppBar().preferredSize.height, 44);
      expect(VineSafeAppBar.toolbarHeight, 44);
    });

    testWidgets('a BookplateAppBar renders at 44px tall', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(appBar: BookplateAppBar(title: 'Church Profile')),
      ));
      expect(tester.getSize(find.byType(AppBar)).height, 44);
    });
  });

  group('footer', () {
    testWidgets('paints no background of its own — the parchment shows through', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: BottomVineFrame(
            child: BottomNavigationBar(
              backgroundColor: Colors.transparent,
              currentIndex: 0,
              items: const [
                BottomNavigationBarItem(icon: SizedBox(width: 24, height: 24), label: 'One'),
                BottomNavigationBarItem(icon: SizedBox(width: 24, height: 24), label: 'Two'),
              ],
            ),
          ),
        ),
      ));

      final vellumBlocks = find.descendant(
        of: find.byType(BottomVineFrame),
        matching: find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == AppColors.vellum,
        ),
      );
      expect(vellumBlocks, findsNothing);
      expect(find.text('One'), findsOneWidget);
    });
  });

  group('CloudEmptyState', () {
    testWidgets('reads as a calm "No data yet", never an error, with an optional first step',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CloudEmptyState(
            message: 'Create a church code to invite your first Runner.',
            glyph: BrassGlyphKind.people,
            actionLabel: 'Open Treasury',
            onAction: () => tapped++,
          ),
        ),
      ));

      expect(find.text('No data yet'), findsOneWidget);
      expect(find.textContaining('invite your first Runner'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);

      await tester.tap(find.text('Open Treasury'));
      expect(tapped, 1);
    });
  });
}
