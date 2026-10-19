import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/prayer_texts.dart';

/// "I prayed for you" texts say when, and don't repeat day after day.
void main() {
  final monday = DateTime(2026, 10, 19);
  DateTime at(int day, int hour) => DateTime(monday.year, monday.month, monday.day + day, hour);

  test('the time of day is in the text', () {
    expect(dayPartAt(at(0, 4)), DayPart.morning);
    expect(dayPartAt(at(0, 11)), DayPart.morning);
    expect(dayPartAt(at(0, 12)), DayPart.afternoon);
    expect(dayPartAt(at(0, 17)), DayPart.evening);
    expect(dayPartAt(at(0, 21)), DayPart.night);
    expect(dayPartAt(at(0, 2)), DayPart.night);

    for (final (hour, phrase) in [(8, 'this morning'), (14, 'this afternoon'), (19, 'this evening'), (23, 'tonight')]) {
      expect(prayedForYouText(firstName: 'Kevin', now: at(0, hour)), contains(phrase));
      expect(witnessPrayedText(firstName: 'Kevin', now: at(0, hour)), contains(phrase));
    }
  });

  test('the same person gets a different text on consecutive days', () {
    for (final make in [prayedForYouText, witnessPrayedText]) {
      final week = [for (var d = 0; d < 7; d++) make(firstName: 'Melanie', now: at(d, 8))];
      for (var d = 1; d < week.length; d++) {
        expect(week[d], isNot(week[d - 1]), reason: 'day $d');
      }
      // Over a week, several distinct versions come up.
      expect(week.toSet().length, greaterThanOrEqualTo(4));
    }
  });

  test('the same draft all day, so reopening it is not a surprise', () {
    expect(
      prayedForYouText(firstName: 'Kevin', now: at(0, 8)),
      prayedForYouText(firstName: 'Kevin', now: at(0, 10)),
    );
  });

  test('first name only, a blank name still reads, and no request is named', () {
    expect(prayedForYouText(firstName: 'Kevin', now: at(0, 8)), contains('Kevin'));
    expect(witnessPrayedText(firstName: '  ', now: at(0, 8)), contains('friend'));
    for (var d = 0; d < 6; d++) {
      for (final text in [
        prayedForYouText(firstName: 'Sam', now: at(d, 9)),
        witnessPrayedText(firstName: 'Sam', now: at(d, 20)),
      ]) {
        expect(text, isNot(contains('  ')));
        expect(text, matches(RegExp('^(Hey|Hi) ')));
      }
    }
  });
}
