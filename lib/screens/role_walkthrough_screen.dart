import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/phone_number.dart';
import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../services/supabase_client.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart';
import '../widgets/bookplate_plate.dart';
import '../widgets/launch_link.dart';
import '../widgets/trellis_scaffold.dart';
import 'church_data_sharing_consent_screen.dart';
import 'welcome_walkthrough_screen.dart';

/// "New here? Begin the journey" destination: the Create Account form.
///
/// Creating the account happens right here (as a Runner, the base role every
/// account has); the welcome deck follows, and its last slide asks how the
/// person wants to start — Runner, Witness or Cloud — and opens that role's
/// first step. (Role cards used to be shown here, then a role picker after the
/// form; the deck now explains the roles with real screens and asks once, at
/// the end.) A back arrow returns to the Sign In screen, as does the "Already
/// have an account?" link below the form.
class RoleWalkthroughScreen extends StatefulWidget {
  const RoleWalkthroughScreen({super.key});

  @override
  State<RoleWalkthroughScreen> createState() => _RoleWalkthroughScreenState();
}

class _RoleWalkthroughScreenState extends State<RoleWalkthroughScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _churchNameController = TextEditingController();
  final _churchCodeController = TextEditingController();

  bool _agreedToTerms = false;
  bool _isSubmitting = false;

  /// The account this screen has already created, kept if a later step then
  /// failed — so "try again" resumes from that step instead of signing up a
  /// second time (which Auth refuses: the address is now taken).
  RunnerProfile? _createdProfile;
  String? _errorMessage;

  late final _termsRecognizer = TapGestureRecognizer()
    ..onTap = () => _openUrl('https://unhinderedlives.com/terms');
  late final _privacyRecognizer = TapGestureRecognizer()
    ..onTap = () => _openUrl('https://unhinderedlives.com/privacy');
  late final _chdRecognizer = TapGestureRecognizer()
    ..onTap = () => _openUrl('https://unhinderedlives.com/consumer-health-data');

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _churchNameController.dispose();
    _churchCodeController.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    _chdRecognizer.dispose();
    super.dispose();
  }

  // These are the legal documents the checkbox below asks the reader to agree
  // to, so a link that can't open says so (with the address) rather than
  // doing nothing.
  Future<void> _openUrl(String url) => openWebPage(context, url);

  Future<void> _createAccount() async {
    if (_isSubmitting) return;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Enter an email and password to continue.');
      return;
    }
    if (firstName.isEmpty) {
      setState(() => _errorMessage = 'Enter your first name to continue.');
      return;
    }
    // Required: it is how the people this person is paired with reach them.
    final phone = normalizePhoneNumber(_phoneController.text);
    if (phone == null) {
      setState(() {
        _errorMessage = _phoneController.text.trim().isEmpty
            ? 'Enter your mobile number to continue.'
            : "That doesn't look like a mobile number. Enter all 10 digits, or start with + "
                'and your country code if you are outside the US.';
      });
      return;
    }
    if (!_agreedToTerms) {
      setState(() {
        _errorMessage = 'You must agree to the Terms of Service, Privacy Policy, and '
            'Consumer Health Data Notice to continue.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final profile = await _ensureAccount(
        email: email,
        password: password,
        name: '$firstName $lastName'.trim(),
        phone: phone,
      );
      // Tier 1 MHMDA consent (the checkbox above) gated account creation
      // itself — record it now that the account exists.
      await profile.recordConsumerHealthDataConsent();
      await _joinChurchIfCodeGiven(profile);
      if (!mounted) return;
      // The welcome deck, then the role this person chooses to start with.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => WelcomeWalkthroughScreen(profile: profile)),
        (route) => false,
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

  /// Signs up (as a Runner — every account's base role) and loads the new
  /// profile, once.
  Future<RunnerProfile> _ensureAccount({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    final existing = _createdProfile;
    if (existing != null) return existing;

    await supabase.auth.signUp(
      email: email,
      password: password,
      // 'phone' is copied into the new profile by the database's sign-up
      // trigger (migration 021).
      data: {'name': name, 'role': UserRole.runner.dbValue, 'phone': phone},
    );

    // If the Supabase project requires email confirmation, sign-up succeeds
    // but there is no session until the link is followed — say exactly that.
    if (supabase.auth.currentSession == null) {
      throw const AuthException(
        'Your account is created. Check your email for a confirmation link, then come '
        'back and sign in.',
      );
    }

    final profile = await RunnerProfile.loadCurrent();
    _createdProfile = profile;
    // Belt and braces for a database whose sign-up trigger doesn't copy the
    // number yet. Best-effort — it can be added later under Account.
    if (profile.phoneNumber == null) {
      try {
        await profile.setPhoneNumber(phone);
      } catch (error) {
        debugPrint('Saving the phone number at sign-up failed: ${error.runtimeType}');
      }
    }
    return profile;
  }

  /// A church-gifted code entered on the form: ask for the separate Tier 2
  /// consent (joining shares this person's summary with church leadership),
  /// then join. A bad code never blocks sign-up — it is said plainly instead.
  Future<void> _joinChurchIfCodeGiven(RunnerProfile profile) async {
    final churchCode = _churchCodeController.text.trim();
    if (churchCode.isEmpty || profile.churchId != null || !mounted) return;
    final consented = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const ChurchDataSharingConsentScreen()),
    );
    if (consented != true) return;
    var joined = false;
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: const BookplateAppBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Begin the Journey.',
                style: textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Abide. Grow. Be Known.',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Same bookplate double-border edging as OrnateRoleCard /
              // the Sign In panel — two nested Containers plus a soft,
              // diffused shadow.
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
                        Text('Create Account', style: textTheme.headlineSmall),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _firstNameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.givenName],
                          decoration: const InputDecoration(labelText: 'First Name'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _lastNameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.familyName],
                          decoration: const InputDecoration(labelText: 'Last Name'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: const InputDecoration(labelText: 'Mobile Number'),
                        ),
                        const SizedBox(height: 6),
                        // Said plainly, before they type it: who will see it
                        // and what for.
                        Text(
                          'Required. Only the people you are paired with can see it — your '
                          'Witness, or the Runners you walk with — so they can text you '
                          'encouragement and check in on you. It is never shown to anyone else.',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.forestGreen.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 16),
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
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(labelText: 'Password'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _churchNameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Church Name (optional)'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _churchCodeController,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Church-Gifted Code (optional)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ConsentCheckbox(
                          value: _agreedToTerms,
                          onChanged: (value) => setState(() => _agreedToTerms = value),
                          termsRecognizer: _termsRecognizer,
                          privacyRecognizer: _privacyRecognizer,
                          chdRecognizer: _chdRecognizer,
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
                          label: 'Create Account',
                          busy: _isSubmitting,
                          onPressed: _isSubmitting ? null : _createAccount,
                        ),
                        const SizedBox(height: 4),
                        BookplateButton(
                          label: 'Already have an account? Sign in',
                          variant: BookplateButtonVariant.link,
                          onPressed: () => Navigator.of(context).pop(),
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

/// The Tier 1 MHMDA (Washington's My Health My Data Act) collection
/// consent — required before an account can be created at all, per
/// [_RoleWalkthroughScreenState._createAccount] above. Each
/// hyperlinked term opens its web page via a [TapGestureRecognizer] owned
/// (and disposed) by the parent state, since a new one built every frame
/// would leak.
class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.value,
    required this.onChanged,
    required this.termsRecognizer,
    required this.privacyRecognizer,
    required this.chdRecognizer,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final TapGestureRecognizer termsRecognizer;
  final TapGestureRecognizer privacyRecognizer;
  final TapGestureRecognizer chdRecognizer;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodySmall;
    final linkStyle = baseStyle?.copyWith(
      color: AppColors.antiqueBrass,
      decoration: TextDecoration.underline,
    );

    return BookplateCheckboxRow(
      value: value,
      onChanged: onChanged,
      label: Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'I agree to the '),
            TextSpan(text: 'Terms of Service', style: linkStyle, recognizer: termsRecognizer),
            const TextSpan(
              text: ' and consent to the collection of my data as described in the ',
            ),
            TextSpan(text: 'Privacy Policy', style: linkStyle, recognizer: privacyRecognizer),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Consumer Health Data Notice',
              style: linkStyle,
              recognizer: chdRecognizer,
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}
