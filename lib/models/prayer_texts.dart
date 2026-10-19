/// The "I prayed for you" texts offered after a prayer session: from a Runner
/// to someone in their Prayer Garden, and from a Witness to their Runner.
///
/// Two things keep them from reading like a form letter in someone's message
/// history:
///
///   * They say when: "this morning", "this afternoon", "this evening",
///     "tonight" — from the moment the text is drafted.
///   * The wording rotates. Which version is used comes from the date and the
///     person's name, so the same person gets a different text on consecutive
///     days, and two people texted on the same day usually get different ones.
///     No storage needed, and the same draft every time within a day.
///
/// Like every text the app drafts, these never name a prayer request: a text
/// shows on a lock screen. They are drafts — Messages opens with them written
/// and every word can be changed before sending.
library;

import 'scripture_verses.dart';

/// The part of the day a text is written in.
enum DayPart { morning, afternoon, evening, night }

/// Morning 4:00–11:59, afternoon 12:00–16:59, evening 17:00–20:59, and night
/// from 21:00 until 3:59.
DayPart dayPartAt(DateTime time) {
  final hour = time.hour;
  if (hour >= 4 && hour < 12) return DayPart.morning;
  if (hour >= 12 && hour < 17) return DayPart.afternoon;
  if (hour >= 17 && hour < 21) return DayPart.evening;
  return DayPart.night;
}

extension on DayPart {
  /// "I prayed for you ___."
  String get when => switch (this) {
        DayPart.morning => 'this morning',
        DayPart.afternoon => 'this afternoon',
        DayPart.evening => 'this evening',
        DayPart.night => 'tonight',
      };

  /// A short sign-off that fits the hour.
  List<String> get closers => switch (this) {
        DayPart.morning => const [
            'Hope your day goes well!',
            'Have a good day today.',
            'Praying your day goes well.',
          ],
        DayPart.afternoon => const [
            'Hope the rest of your day goes well.',
            'Hope your afternoon is a good one.',
            'Hang in there today.',
          ],
        DayPart.evening => const [
            'Hope you have a good evening.',
            'Hope you get some rest tonight.',
            'Enjoy your evening.',
          ],
        DayPart.night => const [
            'Rest well tonight.',
            'Hope you sleep well.',
            'Praying you get some good rest.',
          ],
      };
}

/// A Runner's text to someone they prayed for (who may not use the app).
String prayedForYouText({required String firstName, required DateTime now}) {
  final name = _name(firstName);
  final part = dayPartAt(now);
  final when = part.when;
  final closer = _pick(part.closers, name, now, salt: 7);
  final versions = [
    "Hey $name, just wanted to let you know I've been praying for you $when. $closer",
    'Hi $name! You were in my prayers $when. $closer',
    'Hey $name, I spent a few minutes praying for you $when. Thinking of you!',
    'Hey $name, I was praying for you $when and wanted you to know. $closer',
    'Hi $name, I lifted you up in prayer $when. Is there anything specific I can keep '
        'praying about?',
    'Hey $name, just a quick note: I prayed for you $when. $closer',
  ];
  return _pick(versions, name, now);
}

/// A Witness's text to the Runner they just prayed for. The first version is
/// the owner's own wording, with the time of day added.
String witnessPrayedText({required String firstName, required DateTime now}) {
  final name = _name(firstName);
  final when = dayPartAt(now).when;
  final versions = [
    'Hey $name, I spent some time $when praying for you and for the things you have '
        'shared with me. I am with you in this. How can I keep praying this week?',
    "Hi $name, I prayed for you $when, including what you've shared with me. I'm with "
        'you. Anything new I should be praying about?',
    'Hey $name, you were on my heart $when and I prayed for you. Keep running. How can I '
        'pray for you this week?',
    "Hey $name, I just finished praying for you $when. I'm with you in this. Let me know "
        'how I can keep praying.',
    'Hi $name, I took some time $when to pray for you and the things you have shared. '
        'Grateful to walk with you in this.',
  ];
  return _pick(versions, name, now);
}

/// [message] with a verse after it: a line leading into it (rotating, like
/// the texts), then the passage and its reference. The lead-ins never repeat
/// the time of day — the message before them has already said it.
String withScripture(
  String message,
  ScripturePassage passage, {
  required String firstName,
  required DateTime now,
}) {
  final leadIns = [
    'Praying this one over you:',
    'This passage has been encouraging me, and I thought of you:',
    'Holding onto this for you:',
    'A verse I prayed for you:',
    'Something to hold onto:',
    'This is my prayer for you:',
  ];
  final leadIn = _pick(leadIns, _name(firstName), now, salt: 3);
  final verse = passage.text.isEmpty
      ? passage.reference
      : '"${passage.text}" (${passage.reference}, BSB)';
  return '$message\n\n$leadIn\n$verse';
}

/// Where to start in a theme's passages for this person today, so the first
/// verse offered is not always the same one. "Different verse" moves on from
/// here.
int firstPassageIndex(List<ScripturePassage> passages, String firstName, DateTime now) =>
    passages.isEmpty ? 0 : passages.indexOf(_pick(passages, _name(firstName), now, salt: 11));

/// A prayer's own scripture (a reference typed on its card, e.g.
/// "Philippians 4:6-7") as a passage: with its BSB text when it is one of
/// ours, otherwise the reference alone.
ScripturePassage passageForReference(String reference) {
  String key(String r) => r.toLowerCase().replaceAll(RegExp(r'[\s–—-]+'), '');
  final wanted = key(reference);
  for (final passages in scriptureByTheme.values) {
    for (final passage in passages) {
      if (key(passage.reference) == wanted) return passage;
    }
  }
  return ScripturePassage(reference.trim(), '');
}

String _name(String firstName) {
  final trimmed = firstName.trim();
  return trimmed.isEmpty ? 'friend' : trimmed;
}

/// One of [options] for this person on this calendar day: the next day moves
/// to the next option, and different names start at different places. A
/// small hash of our own — String.hashCode is not stable between runs.
T _pick<T>(List<T> options, String name, DateTime now, {int salt = 0}) {
  var hash = 0;
  for (final unit in name.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  final day = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  return options[(day + hash + salt) % options.length];
}
