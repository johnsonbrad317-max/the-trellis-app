/// Result of [RunnerProfile.checkPairingCode] — a read-only preview of who a
/// pairing code belongs to before it's actually redeemed, so
/// witness_pairing_code_screen.dart can show the church-consent callout
/// ahead of finalizing the pairing rather than after.
class PairingCodePreview {
  const PairingCodePreview({required this.isValid, this.churchId, this.churchName});

  factory PairingCodePreview.fromJson(Map<String, dynamic> json) => PairingCodePreview(
        isValid: json['valid'] as bool,
        churchId: json['church_id'] as String?,
        churchName: json['church_name'] as String?,
      );

  final bool isValid;
  final String? churchId;
  final String? churchName;

  /// Whether accepting this pairing requires the Witness to consent to
  /// sharing their contact details with [churchName]'s leadership.
  bool get requiresChurchConsent => isValid && churchName != null;
}
