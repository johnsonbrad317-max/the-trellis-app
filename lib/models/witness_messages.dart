/// The texts a Witness can send a Runner from the app — each one written for
/// the situation it is offered in, in one place so the wording can be reviewed
/// and changed without hunting through screens.
///
/// Two rules every draft here keeps:
///
///   * It never names a rhythm. A text shows on a lock screen, and a rhythm's
///     title ("maintain sexual purity…") is exactly the kind of thing that
///     must not appear there. "One of your anchor rhythms" is as specific as
///     a text gets; the conversation it starts can say the rest.
///   * It is a draft. The app opens Messages with it written; the Witness can
///     change every word before sending.
library;

/// Why a Witness is being offered a text to send.
enum WitnessTextReason {
  /// The Runner missed an Anchor Rhythm yesterday.
  missedAnchor,

  /// Fewer than half of this week's rhythms were kept.
  hardWeek,

  /// No check-in for a few days. (Also covers "may have deleted the app" —
  /// the app can't see an uninstall, only the silence that follows it.)
  goneQuiet,

  /// The Runner has not committed a Rule of Life yet.
  gettingStarted,

  /// A strong week.
  thriving,

  /// The Witness has just prayed for the Runner.
  prayed,
}

/// The draft for [reason], addressed to [firstName]. [daysQuiet] is used only
/// by [WitnessTextReason.goneQuiet].
String witnessTextFor(WitnessTextReason reason, {required String firstName, int daysQuiet = 0}) {
  final name = firstName.trim().isEmpty ? 'friend' : firstName.trim();
  return switch (reason) {
    WitnessTextReason.missedAnchor =>
      'Hey $name, I saw yesterday was a hard day for one of your anchor rhythms in your '
          "Rule of Life. No judgment at all — I'm in your corner and praying for you. "
          'Want to talk today?',
    WitnessTextReason.hardWeek =>
      "Hey $name, it looks like it's been an uphill week with your Rule of Life. I'm not "
          "keeping score — I just want to know how you're really doing. Can I call you, or "
          'could we get together this week?',
    WitnessTextReason.goneQuiet =>
      "Hey $name, I haven't seen a check-in on your Rule of Life in ${_quietSpan(daysQuiet)} "
          "and wanted to reach out. No pressure — how are you doing? I'm here whenever you "
          'want to talk.',
    WitnessTextReason.gettingStarted =>
      "Hey $name, I'm glad to be walking with you on the Trellis. Whenever you're ready to "
          "commit your Rule of Life, I'd love to hear what you're choosing and pray through "
          'it with you.',
    WitnessTextReason.thriving =>
      'Hey $name, I can see how faithful you have been with your Rule of Life this week, '
          "and it encourages me. Keep going — I'm proud of you and praying for you.",
    WitnessTextReason.prayed =>
      'Hey $name, I just spent some time praying for you and for the things you have '
          'shared with me. I am with you in this. How can I keep praying this week?',
  };
}

String _quietSpan(int days) {
  if (days <= 2) return 'a couple of days';
  if (days <= 6) return '$days days';
  if (days <= 13) return 'about a week';
  return 'a while';
}
