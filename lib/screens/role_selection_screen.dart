import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/rule_of_life_baseline.dart';
import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../services/supabase_client.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart' show showBookplateNotice;
import '../widgets/bookplate_plate.dart' show BookplateSpinner;
import '../widgets/gradient_button.dart';
import '../widgets/ornate_role_card.dart';
import '../widgets/trellis_scaffold.dart';
import 'church_data_sharing_consent_screen.dart';
import 'cloud_access_code_screen.dart';
import 'cloud_shell.dart';
import 'runner_shell.dart';
import 'witness_shell.dart';

/// Asks a newly-signing-up user which role they're starting as, then
/// actually creates the Supabase account. All three roles are offered here
/// as a swipeable carousel; Cloud is handled differently from the other two
/// — see [_beginCloudJourney] — since `profiles.role` only ever stores
/// 'runner'/'witness' (Cloud access is the separate `cloud_admin_church_id`
/// grant redeemed via a Church Access Code, same mechanism as
/// lib/widgets/role_switcher_sheet.dart's existing "enter a Cloud Access
/// Code" dialog for an already-signed-in account).
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({
    super.key,
    required this.email,
    required this.password,
    required this.name,
    this.churchCode,
  });

  final String email;
  final String password;
  final String name;

  /// A church-gifted code entered at sign-up (Runner path only) — redeemed
  /// once the Runner role is confirmed, injecting that church's DNA
  /// Rhythms into their new Rule of Life.
  final String? churchCode;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  static const _selectableRoles = UserRole.values;

  final _pageController = PageController(viewportFraction: 0.85);
  int _currentPage = 0;
  bool _isSubmitting = false;
  String? _errorMessage;

  UserRole get _currentRole => _selectableRoles[_currentPage];

  /// The account this screen has already created, kept if a later step then
  /// failed — so "try again" resumes from that step instead of signing up a
  /// second time (which Auth refuses: the address is now taken, leaving the
  /// person stuck on this screen with an account they can't finish).
  RunnerProfile? _createdProfile;

  /// Signs up with [baseRole] and loads the new profile — once.
  Future<RunnerProfile> _ensureAccount(UserRole baseRole) async {
    final existing = _createdProfile;
    if (existing != null) return existing;

    await supabase.auth.signUp(
      email: widget.email,
      password: widget.password,
      data: {'name': widget.name, 'role': baseRole.dbValue},
    );

    // If the Supabase project requires email confirmation, sign-up succeeds
    // but there is no session until the link is followed — so there is nothing
    // to load yet. Say exactly that (the callers show an AuthException's
    // message as-is) instead of failing as if account creation went wrong.
    if (supabase.auth.currentSession == null) {
      throw const AuthException(
        'Your account is created. Check your email for a confirmation link, then come '
        'back and sign in.',
      );
    }

    final profile = await RunnerProfile.loadCurrent();
    _createdProfile = profile;
    return profile;
  }

  /// Seeds "The Essential" so a new Runner lands on a populated Rule of Life.
  /// Best-effort: the account already exists by now, so a hiccup here must not
  /// block entering the app — the Rule of Life tab offers the same baselines.
  Future<void> _seedBaseline(RunnerProfile profile) async {
    if (profile.ruleItems.isNotEmpty) return;
    try {
      await profile.applyRuleOfLifeBaseline(ruleOfLifeBaselines.first.items);
    } catch (error) {
      debugPrint('Seeding the starter baseline failed: $error');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _beginJourney() async {
    if (_currentRole == UserRole.cloud) {
      await _beginCloudJourney();
      return;
    }

    final role = _currentRole;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final profile = await _ensureAccount(role);
      // A retry after a failed later step may have been made with the other
      // role selected than the one the account was created under.
      if (profile.role != role) profile.setRole(role);

      // Tier 1 MHMDA consent (agreeing to the ToS/Privacy Policy/Consumer
      // Health Data Notice on auth_onboarding_screen.dart) already gated
      // account creation itself — record it now that the account exists.
      await profile.recordConsumerHealthDataConsent();

      final churchCode = widget.churchCode?.trim() ?? '';
      if (role == UserRole.runner && churchCode.isNotEmpty) {
        // Tier 2 MHMDA consent: joining a church shares this Runner's
        // aggregate rhythm consistency with that church's leadership — a
        // separate, explicit opt-in from Tier 1's collection consent above,
        // mirroring the Witness side's own sharing gate in
        // witness_pairing_code_screen.dart.
        if (!mounted) return;
        final consented = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (context) => const ChurchDataSharingConsentScreen()),
        );
        // The code is optional, so a bad one never blocks sign-up — but it is
        // said plainly (the Runner believes they joined their church), and
        // they start from the same baseline as anyone with no code.
        var joined = false;
        if (consented == true) {
          try {
            joined = await profile.redeemChurchCode(churchCode);
          } catch (error) {
            debugPrint('redeemChurchCode at sign-up failed: $error');
          }
          if (!joined && mounted) {
            showBookplateNotice(
              context,
              "That church code wasn't recognized. You can enter it again from Church "
              'Affiliation in the menu.',
              duration: const Duration(seconds: 6),
            );
          }
        }
        // Declining sharing doesn't mean declining The Trellis — fall back
        // to the same unaffiliated baseline as no code at all.
        if (!joined) await _seedBaseline(profile);
      } else if (role == UserRole.runner) {
        // No church code means no real DNA Rhythms were just injected —
        // seed "The Essential" so a brand-new Runner lands on a populated
        // Rule of Life instead of a blank one. Never fabricated as DNA
        // Rhythms (is_church_mandated stays false here, same as picking
        // this baseline manually) — those are meant to represent a real
        // church's actual requirements, not an arbitrary default.
        await _seedBaseline(profile);
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => role == UserRole.witness
              ? WitnessShell(profile: profile)
              : RunnerShell(profile: profile),
        ),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Something went wrong creating your account. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Cloud never saves to the database on tap alone: the Church Access Code
  /// has to be collected first, and (per
  /// RunnerProfile.redeemCloudAccessCode) can only actually be *validated*
  /// once an authenticated account exists. So the order is: collect the
  /// code -> create the account (base role 'runner', matching every other
  /// account) -> attempt to redeem the code -> land in CloudShell on
  /// success, or RunnerShell with an explanation on failure, exactly like
  /// an unrecognized church code falls back rather than stranding the user.
  Future<void> _beginCloudJourney() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const CloudAccessCodeScreen()),
    );
    if (code == null || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final profile = await _ensureAccount(UserRole.runner);
      await profile.recordConsumerHealthDataConsent();

      final redeemed = await profile.redeemCloudAccessCode(code);
      if (!mounted) return;

      if (redeemed) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => CloudShell(profile: profile)),
        );
        return;
      }

      // Invalid code: the account still exists (as a plain Runner) rather
      // than being stranded — they can redeem a valid code later from the
      // role switcher, same recovery path as settings_witnesses.dart.
      await _seedBaseline(profile);
      if (!mounted) return;
      // A notice, not this screen's inline error: the screen is replaced on
      // the very next line, and the notice (on the root overlay) is what
      // actually stays up to explain why they landed in the Runner view.
      showBookplateNotice(
        context,
        "That access code wasn't recognized. Your account was created — you can enter a "
        'valid code later from the role switcher.',
        duration: const Duration(seconds: 7),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => RunnerShell(profile: profile)),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Something went wrong creating your account. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: BookplateAppBar(
        showBack: true,
        // Returns straight to the Sign In screen, skipping back over the
        // walkthrough/account-detail screen this was pushed from.
        onBack: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'Welcome to the Journey.',
                style: textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'How do you plan to use this app to start?',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 400,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _selectableRoles.length,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: OrnateRoleCard(
                      role: _selectableRoles[index],
                      selected: index == _currentPage,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _selectableRoles.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
                      width: _currentPage == i ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            _currentPage == i ? AppColors.forestGreen : AppColors.vellumBorder,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.terracotta),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              Center(
                child: _isSubmitting
                    ? const BookplateSpinner(size: 32, color: AppColors.forestGreen)
                    : GradientButton(
                        label: 'Begin as a ${_currentRole.shortLabel}',
                        onPressed: _beginJourney,
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
