import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../services/supabase_client.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_dialog.dart' show BookplateButton, BookplateButtonVariant;
import '../widgets/bookplate_plate.dart' show BookplatePlate, BookplateSpinner;
import '../widgets/trellis_scaffold.dart';
import 'auth_onboarding_screen.dart';
import 'profile_home.dart';
import 'welcome_walkthrough_screen.dart';

/// Boots straight past sign-in if a Supabase session is already active,
/// otherwise falls through to [AuthOnboardingScreen].
///
/// The session check itself is synchronous and wrapped in a try/catch, so a
/// harness that never called `initSupabase()` (e.g. the widget test, which
/// pumps [TrellisApp] directly without running `main()`) degrades to the
/// sign-in screen immediately — deliberately not dependent on Future-
/// resolution timing during a test's single pump.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final bool _hasSession = _checkForSession();

  bool _checkForSession() {
    try {
      return supabase.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _hasSession ? const _RestoringSession() : const AuthOnboardingScreen();
  }
}

/// Loads the signed-in user's profile before entering the app — only ever
/// built when a session already exists, so this can't affect the sign-in
/// screen's own behavior or timing.
class _RestoringSession extends StatefulWidget {
  const _RestoringSession();

  @override
  State<_RestoringSession> createState() => _RestoringSessionState();
}

class _RestoringSessionState extends State<_RestoringSession> {
  late Future<RunnerProfile> _profile = _load();
  bool _signedOut = false;

  void _retry() => setState(() => _profile = _load());

  /// Loads the profile. A load failure propagates untouched to the retry
  /// screen below.
  Future<RunnerProfile> _load() => RunnerProfile.loadCurrent();

  /// The way out for a session that can never load (e.g. its profile row is
  /// gone): sign out, and fall through to the Sign In screen.
  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
    } catch (_) {
      // Offline: the local session is cleared regardless.
    }
    if (mounted) setState(() => _signedOut = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_signedOut) return const AuthOnboardingScreen();

    return FutureBuilder<RunnerProfile>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.parchmentLight,
            body: Center(child: BookplateSpinner(size: 32, color: AppColors.forestGreen)),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          // The profile couldn't be loaded — most often simply no connection
          // when the app was opened. That must NOT sign the person out (it
          // used to: opening the app offline threw away a good session and
          // demanded the password again). Offer another try, and keep signing
          // out as a choice for a session that really is stale.
          return _LoadFailed(onRetry: _retry, onSignOut: _signOut);
        }
        final profile = snapshot.data!;
        // An account that has never seen the welcome deck starts there; its
        // last slide chooses how to start and replaces this screen.
        return profile.hasSeenWelcome
            ? shellForProfile(profile)
            : WelcomeWalkthroughScreen(profile: profile);
      },
    );
  }
}

/// Shown when a saved session's profile can't be loaded: what happened, a
/// retry, and a way to sign in afresh.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry, required this.onSignOut});

  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56),
              Text('The Trellis', style: textTheme.displaySmall, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              BookplatePlate(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Couldn't Reach The Trellis",
                      style: textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Your account couldn't be loaded just now. Check your connection and "
                      'try again — you are still signed in.',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    BookplateButton(label: 'Try Again', onPressed: onRetry),
                    const SizedBox(height: 4),
                    BookplateButton(
                      label: 'Sign in again instead',
                      variant: BookplateButtonVariant.link,
                      onPressed: onSignOut,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
