/// A generated invite code that lets a new Runner join this church's Cloud
/// roster directly — bypassing the individual $12/yr paywall — until it is
/// redeemed at sign-up or revoked by a Church Admin.
class ChurchCode {
  ChurchCode({required this.code, required this.generatedDate, this.isRedeemed = false});

  factory ChurchCode.fromRow(Map<String, dynamic> row) => ChurchCode(
        code: row['code'] as String,
        generatedDate: DateTime.parse(row['generated_at'] as String),
        isRedeemed: row['is_redeemed'] as bool? ?? false,
      );

  Map<String, dynamic> toInsertRow(String churchId) => {
        'church_id': churchId,
        'code': code,
      };

  final String code;
  final DateTime generatedDate;
  bool isRedeemed;
}
