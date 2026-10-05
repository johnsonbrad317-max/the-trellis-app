/// The texts a Witness can send a Runner from the app — each one written for
/// the situation it is offered in, in one place so the wording can be reviewed
/// and changed without hunting through screens. The wording below is the
/// owner's own.
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

/// The draft for [reason], addressed to [firstName].
String witnessTextFor(WitnessTextReason reason, {required String firstName}) {
  final name = firstName.trim().isEmpty ? 'friend' : firstName.trim();
  return switch (reason) {
    WitnessTextReason.missedAnchor =>
      'Hey $name - I saw you missed one of your anchor rhythms yesterday. Just wanted to '
          "let you know I'm praying for you, and I'd love to chat today if you're free.",
    WitnessTextReason.hardWeek =>
      "Hey $name, looks like it's been a tough week. Just checking in to see how you're "
          "doing. Do you have time for a call today? I'd love to catch up.",
    WitnessTextReason.goneQuiet =>
      "Hey $name - I noticed it's been a few days since you checked in. Just wanted to "
          "reach out and see how you're holding up. Let me know if you have time to connect "
          'later this week.',
    WitnessTextReason.gettingStarted =>
      "Hey $name, I'm really glad we're doing this together. Whenever you get your rhythms "
          "set up, I'd love to hear what you landed on so I can be praying for you.",
    WitnessTextReason.thriving =>
      "Hey $name - I saw you had a great week sticking to your Rule of Life. It's really "
          "encouraging to see. Just wanted to let you know I'm praying for you.",
    WitnessTextReason.prayed =>
      'Hey $name, I just spent some time praying for you and for the things you have '
          'shared with me. I am with you in this. How can I keep praying this week?',
  };
}
