import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Why a feedback submission didn't go through, in words fit to show.
class FeedbackException implements Exception {
  const FeedbackException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What came back from a successful submission.
class FeedbackReceipt {
  const FeedbackReceipt({required this.delivered});

  /// True if the email to support went out. False means the note is safely
  /// stored but the email provider was unavailable — still a success from the
  /// user's side, never something to scare them with.
  final bool delivered;
}

/// Sends "Tend the Trellis" feedback to the team via the `submit-feedback`
/// Edge Function (supabase/functions/submit-feedback), which stores it and
/// emails support@unhinderedlives.com.
class FeedbackService {
  FeedbackService._();

  /// The exact JSON the function expects. Pure, so it can be tested: nothing
  /// identifying goes in it (the function reads the signed-in user from the
  /// session itself, and only uses their email — as Reply-To — if [replyOk]).
  static Map<String, dynamic> buildPayload({
    required int rating,
    required String category,
    required String message,
    required bool replyOk,
    required String role,
    String? platform,
  }) =>
      {
        'rating': rating,
        'category': category,
        'message': message.trim(),
        'reply_ok': replyOk,
        'role': role,
        'platform': platform ?? defaultTargetPlatform.name,
      };

  static Future<FeedbackReceipt> submit({
    required int rating,
    required String category,
    required String message,
    required bool replyOk,
    required String role,
  }) async {
    try {
      final response = await supabase.functions.invoke(
        'submit-feedback',
        body: buildPayload(
          rating: rating,
          category: category,
          message: message,
          replyOk: replyOk,
          role: role,
        ),
      );

      final data = response.data;
      return FeedbackReceipt(delivered: data is Map && data['delivered'] == true);
    } on FunctionException catch (error) {
      // The function answers 4xx with {"error": "..."}; surface that sentence.
      final details = error.details;
      final reason = details is Map && details['error'] is String
          ? details['error'] as String
          : null;
      // The function adds a short setup code to server-side failures (e.g.
      // feedback_table_missing). It goes to the debug log only (debugPrint is
      // silenced in release builds); users see just the calm sentence.
      final code = details is Map && details['code'] is String ? details['code'] as String : null;
      debugPrint('submit-feedback failed: HTTP ${error.status} ${code ?? ''}');
      throw FeedbackException(
        error.status == 429
            ? (reason ?? 'Too many submissions — please try again in a little while.')
            : (reason ?? "Couldn't send your feedback. Please try again."),
      );
    } catch (_) {
      throw const FeedbackException(
        "Couldn't reach The Trellis. Check your connection and try again.",
      );
    }
  }
}
