import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../models/membership_gate.dart';
import '../../models/phone_number.dart';
import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/gift_code_dialog.dart';
import '../../widgets/paywall_sheet.dart';
import '../../widgets/trellis_scaffold.dart';

/// A single full-screen destination combining Account Details (email,
/// password) and Membership — previously two separate pop-up dialogs.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _passwordFormKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  RunnerProfile get _profile => widget.profile;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: _profile.email);
    _phoneController = TextEditingController(
      text: _profile.phoneNumber == null ? '' : formatPhoneNumber(_profile.phoneNumber!),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  bool _isSavingEmail = false;
  bool _isSavingPhone = false;

  /// Saves this person's own mobile number — the one the people they are
  /// paired with use to text them.
  Future<void> _savePhone() async {
    if (_isSavingPhone) return;
    final number = normalizePhoneNumber(_phoneController.text);
    if (number == null) {
      showBookplateNotice(
        context,
        _phoneController.text.trim().isEmpty
            ? 'Enter your mobile number.'
            : "That doesn't look like a mobile number. Enter all 10 digits, or start with + "
                'and your country code if you are outside the US.',
      );
      return;
    }
    if (number == _profile.phoneNumber) {
      showBookplateNotice(context, 'That is already your mobile number.');
      return;
    }

    setState(() => _isSavingPhone = true);
    final saved = await runWithFailureNotice(
      context,
      () => _profile.setPhoneNumber(number),
      failure: "Couldn't save your mobile number. Check your connection and try again.",
    );
    if (!mounted) return;
    setState(() => _isSavingPhone = false);
    if (!saved) return;
    _phoneController.text = formatPhoneNumber(number);
    showBookplateNotice(context, 'Mobile number saved.');
  }
  bool _isChangingPassword = false;

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Starts a real change of sign-in address. Supabase Auth emails a
  /// confirmation link to the new address; nothing changes until it is
  /// followed, and this says exactly that rather than claiming it's done.
  Future<void> _saveEmail() async {
    if (_isSavingEmail) return;
    final value = _emailController.text.trim();

    if (value.toLowerCase() == _profile.email.toLowerCase()) {
      showBookplateNotice(context, 'That is already your email address.');
      return;
    }
    if (!_emailShape.hasMatch(value)) {
      showBookplateNotice(context, 'Enter a valid email address.');
      return;
    }

    setState(() => _isSavingEmail = true);
    String notice;
    try {
      await _profile.requestEmailChange(value);
      notice = 'Check $value for a confirmation link. Your email changes once you confirm it.';
      // The field shows the address the account actually has until then.
      _emailController.text = _profile.email;
    } on AuthException catch (error) {
      notice = error.message;
    } catch (_) {
      notice = "Couldn't reach The Trellis. Check your connection and try again.";
    } finally {
      if (mounted) setState(() => _isSavingEmail = false);
    }
    if (mounted) showBookplateNotice(context, notice, duration: const Duration(seconds: 6));
  }

  /// Verifies the current password, then sets the new one — for real.
  Future<void> _changePassword() async {
    if (_isChangingPassword) return;
    if (!(_passwordFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isChangingPassword = true);
    String notice;
    try {
      await _profile.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      notice = 'Password updated.';
    } on AuthException catch (error) {
      // Supabase reports a wrong current password as invalid credentials.
      final message = error.message.toLowerCase();
      notice = message.contains('invalid') && message.contains('credential')
          ? 'Your current password is not right.'
          : error.message;
    } catch (_) {
      notice = "Couldn't reach The Trellis. Check your connection and try again.";
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
    if (mounted) showBookplateNotice(context, notice);
  }

  String _membershipLabel(MembershipStatus status) {
    // Trial and gift dates appear only once memberships are switched on at
    // launch (migration 029); until then this reads exactly as it always has.
    final trialEndsAt = _profile.trialEndsAt;
    if (_profile.isTrialPeriod && trialEndsAt != null) {
      return 'Free trial — ends ${formatMembershipDate(trialEndsAt)}';
    }
    final gate = _profile.membershipGate;
    final paidUntil = gate.paidUntil;
    if (gate.enforced && paidUntil != null && paidUntil.isAfter(DateTime.now())) {
      return 'Your membership is active through ${formatMembershipDate(paidUntil)}.';
    }
    return switch (status) {
      MembershipStatus.trial => "You're on a free trial.",
      MembershipStatus.active => 'Your membership is active.',
      MembershipStatus.cancelled => 'Your membership has been cancelled.',
    };
  }

  Future<void> _showGiftCodeDialog() async {
    await showGiftCodeDialog(context, _profile);
  }

  bool _isOpeningStoreSettings = false;

  /// A store subscription can only be cancelled in the App Store / Google
  /// Play, so this explains that and sends the Runner there. Nothing here (or
  /// in [RunnerProfile.cancelMembership]) edits the membership status — the
  /// RevenueCat webhook does that once the paid period actually ends.
  Future<void> _confirmCancelMembership() async {
    if (_isOpeningStoreSettings) return;

    final proceed = await showBookplateConfirm(
      context,
      title: 'Manage Your Membership',
      message: 'Your membership is billed through the App Store or Google Play, so it is '
          'cancelled there. We will take you to your subscription settings. You keep full '
          'access until the end of the period you have already paid for.',
      confirmLabel: 'Open Subscription Settings',
      cancelLabel: 'Keep Membership',
    );
    if (!proceed || !mounted) return;

    setState(() => _isOpeningStoreSettings = true);
    String? notice;
    try {
      notice = switch (await _profile.cancelMembership()) {
        MembershipCancellationOutcome.openedStoreSettings => null,
        MembershipCancellationOutcome.notStoreBilled =>
          'This membership is not billed through the App Store or Google Play — for '
              'example, it was unlocked with a church code — so there is nothing to cancel '
              'here.',
        MembershipCancellationOutcome.couldNotOpenStoreSettings =>
          "Couldn't open your subscription settings. You can cancel from your App Store or "
              'Google Play account instead.',
      };
    } catch (_) {
      notice = "Couldn't reach the store to find your subscription. Check your connection "
          'and try again.';
    } finally {
      if (mounted) setState(() => _isOpeningStoreSettings = false);
    }

    if (notice != null && mounted) showBookplateNotice(context, notice);
  }

  Future<void> _showChurchCodeDialog() async {
    final codeController = TextEditingController();
    var isSubmitting = false;
    String? errorMessage;

    Future<void> submit(BuildContext dialogContext, StateSetter setDialogState) async {
      final code = codeController.text.trim();
      if (code.isEmpty) {
        setDialogState(() => errorMessage = "Enter your church's code.");
        return;
      }

      setDialogState(() {
        isSubmitting = true;
        errorMessage = null;
      });

      bool success;
      try {
        success = await _profile.redeemEnterpriseChurchCode(code);
      } catch (_) {
        if (!dialogContext.mounted) return;
        setDialogState(() {
          isSubmitting = false;
          errorMessage = "Network error — couldn't reach the server. Try again.";
        });
        return;
      }

      if (!dialogContext.mounted) return;
      if (!success) {
        setDialogState(() {
          isSubmitting = false;
          errorMessage = "That code wasn't recognized. Check it with your church.";
        });
        return;
      }

      Navigator.pop(dialogContext);
    }

    await showBookplateForm<void>(
      context,
      title: 'Church Code',
      message: "If your church has purchased memberships for its congregation, enter "
          'the code they gave you to unlock full access.',
      bodyBuilder: (dialogContext, setDialogState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: codeController,
            autofocus: true,
            enabled: !isSubmitting,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Church Code'),
            onSubmitted: (_) => submit(dialogContext, setDialogState),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              style: Theme.of(dialogContext)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.terracotta),
            ),
          ],
        ],
      ),
      actionsBuilder: (dialogContext, setDialogState) => [
        BookplateButton(
          label: 'Redeem',
          busy: isSubmitting,
          onPressed: isSubmitting ? null : () => submit(dialogContext, setDialogState),
        ),
        BookplateButton(
          label: 'Cancel',
          variant: BookplateButtonVariant.secondary,
          onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
        ),
      ],
    );

    disposeAfterBookplateClose([codeController]);

    if (!mounted) return;
    if (_profile.membershipStatus == MembershipStatus.active) {
      showBookplateNotice(context, 'Membership unlocked — welcome!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'Account & Membership'),
      body: ListenableBuilder(
        listenable: _profile,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Account Details', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            BookplatePlate(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: BookplateButton(
                      label: 'Save Email',
                      compact: true,
                      busy: _isSavingEmail,
                      onPressed: _saveEmail,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Mobile Number', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            BookplatePlate(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(labelText: 'Mobile Number'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Only the people you are paired with can see this — your Witness, or the '
                    'Runners you walk with — so they can text you encouragement and check in '
                    'on you.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.forestGreen.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: BookplateButton(
                      label: 'Save Number',
                      compact: true,
                      busy: _isSavingPhone,
                      onPressed: _savePhone,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Change Password', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            BookplatePlate(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _passwordFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Current Password'),
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Enter your current password.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(labelText: 'New Password'),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Enter a new password.';
                        if (value.length < 7) {
                          return 'Password must be at least 7 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: BookplateButton(
                        label: 'Update Password',
                        compact: true,
                        busy: _isChangingPassword,
                        onPressed: _changePassword,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Membership', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            BookplatePlate(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rate: \$12/yr', style: textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(_membershipLabel(_profile.membershipStatus), style: textTheme.bodyMedium),
                  if (_profile.membershipStatus == MembershipStatus.trial ||
                      _profile.membershipStatus == MembershipStatus.cancelled) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: BookplateButton(
                        label: _profile.membershipStatus == MembershipStatus.trial
                            ? 'Subscribe'
                            : 'Resubscribe',
                        compact: true,
                        onPressed: () => showPaywallSheet(context, _profile),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: BookplateButton(
                        label: 'Have a Church Code?',
                        variant: BookplateButtonVariant.link,
                        compact: true,
                        onPressed: _showChurchCodeDialog,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    BookplateButton(
                      label: _isOpeningStoreSettings ? 'Opening…' : 'Cancel Membership',
                      variant: BookplateButtonVariant.danger,
                      onPressed: _isOpeningStoreSettings ? null : _confirmCancelMembership,
                    ),
                  ],
                  // Open to anyone at any time: a gift adds its months on top
                  // of whatever membership is already there.
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: BookplateButton(
                      label: 'Have a gift code?',
                      variant: BookplateButtonVariant.link,
                      compact: true,
                      onPressed: _showGiftCodeDialog,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
