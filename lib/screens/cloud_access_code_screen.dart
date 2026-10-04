import 'package:flutter/material.dart';

import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart';
import '../widgets/brass_glyph.dart';
import '../widgets/gradient_button.dart';
import '../widgets/trellis_scaffold.dart';

/// Collects a church's enterprise-level Cloud Access Code before an account
/// is ever created — reached only from role_selection_screen.dart's "Begin
/// as The Cloud" action. Nothing is saved here: this screen just returns
/// the typed code via [Navigator.pop]; the caller is responsible for
/// actually creating the account and redeeming the code afterward
/// (RunnerProfile.redeemCloudAccessCode requires an authenticated user, so
/// the code can't be validated until the account exists).
class CloudAccessCodeScreen extends StatefulWidget {
  const CloudAccessCodeScreen({super.key});

  @override
  State<CloudAccessCodeScreen> createState() => _CloudAccessCodeScreenState();
}

class _CloudAccessCodeScreenState extends State<CloudAccessCodeScreen> {
  final _codeController = TextEditingController();
  bool _codeMissing = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TrellisScaffold(
      appBar: const BookplateAppBar(title: 'Church Access Code'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: BrassGlyph(BrassGlyphKind.people, size: 40)),
              const SizedBox(height: 16),
              Text(
                'Enter Your Church Access Code',
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "The Cloud is an enterprise-level role for church leadership. Enter the "
                "access code your church's enterprise license generated.",
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _codeController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(letterSpacing: 4),
                decoration: InputDecoration(
                  labelText: 'Church Access Code',
                  // Continue used to do nothing, silently, with this blank.
                  errorText: _codeMissing ? 'Enter the access code to continue.' : null,
                ),
                onChanged: (_) {
                  if (_codeMissing) setState(() => _codeMissing = false);
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              GradientButton(label: 'Continue', onPressed: _submit),
              const SizedBox(height: 12),
              Center(
                child: BookplateButton(
                  label: 'Back',
                  variant: BookplateButtonVariant.link,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _codeMissing = true);
      return;
    }
    Navigator.of(context).pop(code);
  }
}
