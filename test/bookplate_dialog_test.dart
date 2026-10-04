import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/widgets/bookplate_dialog.dart';

/// Hosts a button that opens the dialog and records what it resolved to.
Widget _host(void Function(BuildContext) onTap) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              onTap: () => onTap(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('showBookplateConfirm resolves true on confirm, false on cancel', (tester) async {
    bool? result;
    await tester.pumpWidget(_host((context) async {
      result = await showBookplateConfirm(
        context,
        title: 'Manage Your Membership',
        message: 'Body copy.',
        confirmLabel: 'Open Subscription Settings',
        cancelLabel: 'Keep Membership',
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Your Membership'), findsOneWidget);
    // Hand-built: no stock Material dialog or buttons anywhere in the prompt.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);

    await tester.tap(find.text('Open Subscription Settings'));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep Membership'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('showBookplateConfirm resolves false when dismissed by tapping outside',
      (tester) async {
    bool? result;
    await tester.pumpWidget(_host((context) async {
      result = await showBookplateConfirm(
        context,
        title: 'Title',
        message: 'Body.',
        confirmLabel: 'Yes',
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('showBookplateNotice shows a message and removes itself', (tester) async {
    await tester.pumpWidget(_host((context) {
      showBookplateNotice(context, 'Nothing to cancel here.',
          duration: const Duration(seconds: 1));
    }));

    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nothing to cancel here.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to cancel here.'), findsNothing);
  });

  testWidgets('BookplateButton with no handler is inert', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            BookplateButton(label: 'Live', onPressed: () => taps++),
            const BookplateButton(label: 'Dimmed', onPressed: null),
          ],
        ),
      ),
    ));

    await tester.tap(find.text('Dimmed'));
    expect(taps, 0);
    await tester.tap(find.text('Live'));
    expect(taps, 1);
  });
}
