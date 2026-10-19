import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/runner_profile.dart';
import '../services/supabase_client.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart';
import '../widgets/bookplate_plate.dart';
import '../widgets/trellis_scaffold.dart';
import 'profile_home.dart';
import 'welcome_walkthrough_screen.dart';

/// "Forgot your password?" from the Sign In screen.
///
/// A code, not a link: Supabase emails a short code (the Reset Password
/// template must include `{{ .Token }}` — see supabase/AUTH_EMAILS.md), the
/// person types it here with a new password, and they are signed in. A link
/// would have to open the app on this phone, which fails when the email is
/// read on a computer.
///
/// It never says whether an account exists for an email: the same "if an
/// account uses that address" answer either way.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail = ''});

  /// Whatever was already typed in the Sign In screen's Email field.
  final String initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

/// Shortest password the app accepts (as in Account & Membership).
const int minimumPasswordLength = 7;

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final _emailController = TextEditingController(text: widget.initialEmail.trim());
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  /// The code has been sent; now asking for it and the new password.
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim();

  Future<void> _sendCode() async {
    if (!_email.contains('@')) {
      setState(() => _error = 'Enter the email address you signed up with.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await supabase.auth.resetPasswordForEmail(_email);
      if (!mounted) return;
      setState(() => _codeSent = true);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't send the code. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.replaceAll(RegExp(r'\s'), '');
    final password = _passwordController.text;
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code from the email.');
      return;
    }
    if (password.length < minimumPasswordLength) {
      setState(() => _error = 'Your new password needs at least $minimumPasswordLength characters.');
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _error = "The two passwords don't match.");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The code signs this phone in; the new password is then set on that
      // session.
      await supabase.auth.verifyOTP(email: _email, token: code, type: OtpType.recovery);
      await supabase.auth.updateUser(UserAttributes(password: password));
      final profile = await RunnerProfile.loadCurrent();
      if (!mounted) return;
      showBookplateNotice(context, 'Your password is changed. Welcome back.');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => profile.hasSeenWelcome
              ? shellForProfile(profile)
              : WelcomeWalkthroughScreen(profile: profile),
        ),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't change your password. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Supabase's messages, in the app's words where they matter.
  static String _friendly(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('expired') || message.contains('invalid') || message.contains('token')) {
      return 'That code is wrong or has expired. Check the newest email, or send a new code.';
    }
    if (message.contains('rate') || message.contains('seconds') || error.statusCode == '429') {
      return 'Please wait a minute before asking for another code.';
    }
    return error.message;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'Reset Password'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: BookplatePlate(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _codeSent ? 'Check your email' : 'Forgot your password?',
                    style: textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _codeSent
                        ? 'If an account uses $_email, we sent it a code. Enter it below with '
                            'a new password. (Check your spam folder if it is not there in a '
                            'minute.)'
                        : "Enter the email you signed up with and we'll send you a code to set "
                            'a new password.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  if (!_codeSent)
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(labelText: 'Email'),
                      onSubmitted: (_) {
                        if (!_busy) _sendCode();
                      },
                    )
                  else ...[
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Code from the email'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'New password'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmController,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(labelText: 'New password again'),
                      onSubmitted: (_) {
                        if (!_busy) _resetPassword();
                      },
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta)),
                  ],
                  const SizedBox(height: 24),
                  BookplateButton(
                    label: _codeSent ? 'Set New Password' : 'Send Code',
                    busy: _busy,
                    onPressed: _busy ? null : (_codeSent ? _resetPassword : _sendCode),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 8),
                    BookplateButton(
                      label: 'Send a new code',
                      variant: BookplateButtonVariant.link,
                      onPressed: _busy ? null : _sendCode,
                    ),
                    BookplateButton(
                      label: 'Use a different email',
                      variant: BookplateButtonVariant.link,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _codeSent = false;
                                _error = null;
                              }),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
