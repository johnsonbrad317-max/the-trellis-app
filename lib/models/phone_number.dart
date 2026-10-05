/// Phone numbers, kept in one shape: international ("E.164") form, a plus sign
/// followed by digits, e.g. `+18165551234`.
///
/// Why it matters: the app hands numbers to the phone's Messages app, and a
/// number with its country code is the form Apple matches most reliably when
/// deciding whether a message can go as an iMessage. (The app cannot choose
/// iMessage itself — iOS decides, per recipient.)
library;

/// Turns what a person typed into `+<country><number>`, or null if it can't be
/// a phone number.
///
/// Accepts US/Canada numbers as most people write them — `(816) 555-1234`,
/// `816-555-1234`, `1 816 555 1234` — and any number already written with a
/// leading `+`. A number with no `+` that is not 10 digits (or 11 starting
/// with 1) is rejected rather than guessed at.
String? normalizePhoneNumber(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  // Anything other than digits and common punctuation is not a phone number.
  if (RegExp(r'[^0-9+\-\s().]').hasMatch(trimmed)) return null;

  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (trimmed.startsWith('+')) {
    // E.164 allows up to 15 digits; 8 is the shortest real international number.
    return digits.length >= 8 && digits.length <= 15 ? '+$digits' : null;
  }
  if (digits.length == 10) return _northAmerican(digits);
  if (digits.length == 11 && digits.startsWith('1')) return _northAmerican(digits.substring(1));
  return null;
}

/// North American numbers never start an area code or an exchange with 0 or 1,
/// which catches the commonest typos (a dropped or doubled digit).
String? _northAmerican(String tenDigits) {
  if (tenDigits[0] == '0' || tenDigits[0] == '1') return null;
  if (tenDigits[3] == '0' || tenDigits[3] == '1') return null;
  return '+1$tenDigits';
}

/// The number to hand to the Messages app: normalized when it can be, otherwise
/// just the digits the person typed (and a leading `+` if they wrote one), so
/// an unusual number still opens a message rather than nothing.
String phoneNumberForMessaging(String input) {
  final normalized = normalizePhoneNumber(input);
  if (normalized != null) return normalized;
  final trimmed = input.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  return trimmed.startsWith('+') ? '+$digits' : digits;
}

/// A stored number shown back to a person: `+18165551234` → `(816) 555-1234`.
/// Anything that is not a North American number is shown as stored.
String formatPhoneNumber(String stored) {
  final match = RegExp(r'^\+1(\d{3})(\d{3})(\d{4})$').firstMatch(stored.trim());
  if (match == null) return stored.trim();
  return '(${match.group(1)}) ${match.group(2)}-${match.group(3)}';
}
