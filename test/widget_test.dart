import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/main.dart';
import 'package:trellis/widgets/bookplate_dialog.dart';

void main() {
  testWidgets('App launches straight to the Sign In screen', (WidgetTester tester) async {
    await tester.pumpWidget(const TrellisApp());

    expect(find.text('The Trellis'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.widgetWithText(BookplateButton, 'SIGN IN'), findsOneWidget);
    expect(find.text('New here? Begin the journey'), findsOneWidget);
    expect(find.text('Skip to Sign In'), findsNothing);

    // The woodcut rule: no stock Material buttons on the first screen.
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
