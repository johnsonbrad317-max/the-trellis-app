import 'package:flutter/material.dart';

import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart';
import '../widgets/brass_glyph.dart';
import '../widgets/gradient_button.dart';
import '../widgets/launch_link.dart';
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
                'The Cloud is for church leadership. Enter the access code that came '
                "with your church's license.",
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Where a code comes from, for the pastor who arrives here
              // without one — the screen used to assume everyone had one.
              Text(
                "Don't have a code? Church licenses are set up through Unhindered Lives.",
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              Center(
                child: BookplateButton(
                  label: 'Learn how it works at unhinderedlives.com/trellis',
                  variant: BookplateButtonVariant.link,
                  compact: true,
                  onPressed: () => openWebPage(context, churchLicenseUrl),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                autocorrect: false,
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
