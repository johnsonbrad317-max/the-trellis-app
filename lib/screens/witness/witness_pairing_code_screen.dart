import 'package:flutter/material.dart';

import '../../models/pairing_code_preview.dart';
import '../../models/runner_profile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bookplate_app_bar.dart';
import '../../widgets/bookplate_dialog.dart';
import '../../widgets/bookplate_plate.dart';
import '../../widgets/brass_glyph.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/trellis_scaffold.dart';

/// Where a Witness redeems a Runner's pairing code — the counterpart to
/// settings_witnesses.dart's "Generate Pairing Code" dialog on the Runner
/// side. Successfully redeeming forms the witness_pairings row that makes
/// a Runner actually show up on [WitnessDashboardScreen].
///
/// Reached from WitnessShell's app bar (always available) and from the
/// Dashboard's empty state (shown only while this account has zero
/// Runners yet) — see witness_shell.dart and witness_dashboard.dart.
///
/// A code is checked (read-only, via [RunnerProfile.checkPairingCode])
/// before it's redeemed. If the Runner belongs to a church, pairing is
/// gated on an explicit consent checkbox — pairing puts the Witness's own
/// name into that church's Cloud Roster the moment it exists, so consent
/// has to come before that happens, not after.
class WitnessPairingCodeScreen extends StatefulWidget {
  const WitnessPairingCodeScreen({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  State<WitnessPairingCodeScreen> createState() => _WitnessPairingCodeScreenState();
}

class _WitnessPairingCodeScreenState extends State<WitnessPairingCodeScreen> {
  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  /// Null until the code currently in the field has been checked. Cleared
  /// whenever the text changes so a stale church name is never shown for a
  /// different code.
  PairingCodePreview? _preview;
  bool _consentChecked = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged(String _) {
    if (_preview != null) {
      setState(() {
        _preview = null;
        _consentChecked = false;
      });
    }
  }

  Future<void> _primaryAction() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Enter the code your Runner shared with you.');
      return;
    }

    if (_preview == null) {
      await _checkCode(code);
      return;
    }

    if (_preview!.requiresChurchConsent && !_consentChecked) return;
    await _redeem(code);
  }

  Future<void> _checkCode(String code) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    PairingCodePreview preview;
    try {
      preview = await widget.profile.checkPairingCode(code);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = "Network error — couldn't reach the server. Try again.";
      });
      return;
    }

    if (!mounted) return;

    if (!preview.isValid) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = "That code wasn't recognized. Double-check it with your Runner — "
            'codes expire after 24 hours.';
      });
      return;
    }

    setState(() {
      _isSubmitting = false;
      _preview = preview;
    });

    // No church affiliation means no consent callout to show — proceed
    // straight to redeeming, same one-tap flow as before this screen had a
    // pre-flight check at all.
    if (!preview.requiresChurchConsent) {
      await _redeem(code);
    }
  }

  Future<void> _redeem(String code) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    bool success;
    try {
      success = await widget.profile.redeemPairingCode(code, consent: _consentChecked);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = "Network error — couldn't reach the server. Try again.";
      });
      return;
    }

    if (!mounted) return;

    if (!success) {
      setState(() {
        _isSubmitting = false;
        _preview = null;
        _errorMessage = "That code wasn't recognized. Double-check it with your Runner — "
            'codes expire after 24 hours.';
      });
      return;
    }

    showBookplateNotice(context, "You're now walking alongside this Runner.");
    Navigator.of(context).pop();
  }

  bool get _buttonEnabled {
    if (_isSubmitting) return false;
    final preview = _preview;
    if (preview != null && preview.requiresChurchConsent) return _consentChecked;
    return true;
  }

  String get _buttonLabel => _preview == null ? 'Continue' : 'Connect';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final preview = _preview;

    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'Enter a Pairing Code'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Center(
                child: BrassGlyph(BrassGlyphKind.heart, size: 40, color: AppColors.forestGreen),
              ),
              const SizedBox(height: 16),
              Text(
                'Walk Alongside a Runner',
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Ask your Runner for their pairing code — Settings → My Witnesses on their '
                'side — then enter it below.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'By pairing, you are opting in to receive this Runner\'s Consumer Health Data '
                '— their spiritual rhythms, prayer requests, and check-in history — so you can '
                'support them well.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.forestGreen.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _codeController,
                enabled: !_isSubmitting,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(letterSpacing: 4),
                decoration: const InputDecoration(labelText: 'Pairing Code'),
                onChanged: _onCodeChanged,
                onSubmitted: (_) => _primaryAction(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta),
                  textAlign: TextAlign.center,
                ),
              ],
              if (preview != null && preview.requiresChurchConsent) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.antiqueBrass.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.antiqueBrass),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const BrassGlyph(
                            BrassGlyphKind.info,
                            size: 20,
                            color: AppColors.antiqueBrass,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Consumer Health Data Sharing',
                              style: textTheme.titleSmall?.copyWith(
                                color: AppColors.antiqueBrass,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The Runner you are supporting is part of ${preview.churchName}. By '
                        'accepting this invitation, your name, email, and phone number will be '
                        'shared with the church leadership so they can support and equip you in '
                        'your role as a Witness.',
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This is a separate, explicit consent from the app collecting your '
                        'Consumer Health Data — it specifically authorizes sharing your contact '
                        'details with this church as a third party. See the Consumer Health '
                        'Data Notice in Settings for the full policy.',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                BookplateCheckboxRow(
                  value: _consentChecked,
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _consentChecked = value),
                  label: Text(
                    'I opt in to sharing my contact details with ${preview.churchName}.',
                    style: textTheme.bodyMedium,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _isSubmitting
                  ? const Center(child: BookplateSpinner(size: 28, color: AppColors.forestGreen))
                  : GradientButton(
                      label: _buttonLabel,
                      onPressed: _buttonEnabled ? _primaryAction : null,
                    ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
