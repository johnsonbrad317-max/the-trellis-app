import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/screens/auth_onboarding_screen.dart';
import 'package:trellis/screens/reset_password_screen.dart';
import 'package:trellis/theme/app_theme.dart';

/// "Forgot your password?": a code by email, then a new password.
void main() {
  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('Sign In offers it, carrying the email already typed', (tester) async {
    await pump(tester, const AuthOnboardingScreen());
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'brad@example.org');
    await tester.tap(find.text('Forgot your password?'));
    await tester.pumpAndSettle();

    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'brad@example.org'), findsOneWidget);
    expect(find.text('Send Code'), findsOneWidget);
  });

  testWidgets('asks for a real email before sending anything', (tester) async {
    await pump(tester, const ResetPasswordScreen());
    await tester.tap(find.text('Send Code'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the email address you signed up with.'), findsOneWidget);
  });

  test('passwords follow the same minimum as Account & Membership', () {
    expect(minimumPasswordLength, 7);
  });
}
