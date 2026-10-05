import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/phone_number.dart';
import '../models/user_role.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart';
import '../widgets/bookplate_plate.dart';
import '../widgets/launch_link.dart';
import '../widgets/ornate_role_card.dart';
import '../widgets/trellis_scaffold.dart';
import 'role_selection_screen.dart';

/// "New here? Begin the journey" destination: a short role walkthrough
/// (display-only — actual role picking happens on [RoleSelectionScreen],
/// reached after submitting this form) followed by the account-detail
/// fields. A back arrow (via the AppBar) returns straight to the Sign In
/// screen, same as the "Already have an account?" link below the form.
class RoleWalkthroughScreen extends StatefulWidget {
  const RoleWalkthroughScreen({super.key});

  @override
  State<RoleWalkthroughScreen> createState() => _RoleWalkthroughScreenState();
}

class _RoleWalkthroughScreenState extends State<RoleWalkthroughScreen> {
  final _pageController = PageController(viewportFraction: 0.85);

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _churchNameController = TextEditingController();
  final _churchCodeController = TextEditingController();

  int _walkthroughPage = 0;
  bool _agreedToTerms = false;
  String? _errorMessage;

  late final _termsRecognizer = TapGestureRecognizer()
    ..onTap = () => _openUrl('https://unhinderedlives.com/terms');
  late final _privacyRecognizer = TapGestureRecognizer()
    ..onTap = () => _openUrl('https://unhinderedlives.com/privacy');
  late final _chdRecognizer = TapGestureRecognizer()
    ..onTap = () => _openUrl('https://unhinderedlives.com/consumer-health-data');

  @override
  void dispose() {
    _pageController.dispose();
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

  void _goToWalkthroughPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // These are the legal documents the checkbox below asks the reader to agree
  // to, so a link that can't open says so (with the address) rather than
  // doing nothing.
  Future<void> _openUrl(String url) => openWebPage(context, url);

  void _continueToRoleSelection() {
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

    setState(() => _errorMessage = null);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RoleSelectionScreen(
          email: email,
          password: password,
          name: '$firstName $lastName'.trim(),
          phoneNumber: phone,
          churchCode: _churchCodeController.text,
        ),
      ),
    );
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
              SizedBox(
                height: 400,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (page) => setState(() => _walkthroughPage = page),
                  children: [
                    for (final role in UserRole.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: OrnateRoleCard(role: role),
                      ),
                  ],
                ),
              ),
              // The dots sit exactly where they did (20px below the cards,
              // 40px above the form); the spacing that used to be SizedBoxes
              // is now padding INSIDE each dot's tap area, making it 44px
              // tall instead of 24.
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < UserRole.values.length; i++)
                    Semantics(
                      button: true,
                      selected: _walkthroughPage == i,
                      label: 'Show ${UserRole.values[i].label}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _goToWalkthroughPage(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _walkthroughPage == i ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _walkthroughPage == i
                                  ? AppColors.forestGreen
                                  : AppColors.vellumBorder,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
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
                          onPressed: _continueToRoleSelection,
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
/// [_RoleWalkthroughScreenState._continueToRoleSelection] above. Each
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
