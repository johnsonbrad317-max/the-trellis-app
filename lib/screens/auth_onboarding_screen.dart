import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/runner_profile.dart';
import '../services/supabase_client.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_dialog.dart';
import '../widgets/launch_link.dart';
import '../widgets/trellis_scaffold.dart';
import 'profile_home.dart';
import 'role_walkthrough_screen.dart';

/// Entry point for Runners and Witnesses: the Sign In screen — the app's
/// true default landing state. Account creation (and the role walkthrough)
/// lives on [RoleWalkthroughScreen], reached only via the "New here? Begin
/// the journey" button below.
class AuthOnboardingScreen extends StatefulWidget {
  const AuthOnboardingScreen({super.key});

  static const routeName = '/';

  @override
  State<AuthOnboardingScreen> createState() => _AuthOnboardingScreenState();
}

class _AuthOnboardingScreenState extends State<AuthOnboardingScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Enter an email and password to continue.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      final profile = await RunnerProfile.loadCurrent();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => shellForProfile(profile)),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = "Couldn't sign in — check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _beginJourney() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const RoleWalkthroughScreen()),
    );
  }

  Future<void> _openLearnMore() => openWebPage(context, 'https://unhinderedlives.com/trellis');

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56),
              Text(
                'The Trellis',
                style: textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Abide. Grow. Be Known.',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // Deliberately not the app's generic Card chrome — the same
              // bookplate edging as OrnateRoleCard: two nested Containers
              // (each a thin 1px brass border, 4px apart) plus a very soft,
              // diffused shadow so the panel reads as a thick physical card
              // floating off the parchment, not a flat Material surface.
              Container(
                decoration: BoxDecoration(
                  color: AppColors.parchmentLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.antiqueBrass),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.forestGreen.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
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
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Sign In', style: textTheme.headlineSmall),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(labelText: 'Password'),
                          // The keyboard's own "done" signs in, like the button.
                          onSubmitted: (_) {
                            if (!_isSubmitting) _handleSignIn();
                          },
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta),
                          ),
                        ],
                        const SizedBox(height: 24),
                        BookplateButton(
                          label: 'SIGN IN',
                          busy: _isSubmitting,
                          onPressed: _isSubmitting ? null : _handleSignIn,
                        ),
                        const SizedBox(height: 12),
                        BookplateButton(
                          label: 'New here? Begin the journey',
                          variant: BookplateButtonVariant.link,
                          onPressed: _isSubmitting ? null : _beginJourney,
                        ),
                        BookplateButton(
                          label: 'Learn more about The Trellis',
                          variant: BookplateButtonVariant.link,
                          onPressed: _openLearnMore,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

