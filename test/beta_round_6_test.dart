import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/rule_item.dart';
import 'package:trellis/models/rule_of_life_baseline.dart';
import 'package:trellis/models/witness_notice.dart';

/// TestFlight round 6: only Anchor Rhythms lock; a removed rhythm is a note
/// for the Witness; "6 PM" stays in capitals.
void main() {
  RuleItem rhythm(String title) => RuleItem(id: 'r', category: RuleCategory.workRest, title: title);

  test('an abbreviation in capitals stays that way in a title', () {
    expect(rhythm('Finish Work by 6 PM').displayTitle, 'Finish Work by 6 PM');
    expect(rhythm('finish work by 6 PM').checkInPrompt, 'Did you finish work by 6 PM?');
    expect(rhythm('go to an AA meeting').displayTitle, 'Go to an AA Meeting');
    expect(rhythm('read scripture').displayTitle, 'Read Scripture');
  });

  test('no starter Rule asks "Did you be done…?"', () {
    for (final template in ruleOfLifeBaselines) {
      for (final item in template.items) {
        expect(item.title.toLowerCase(), isNot(startsWith('be done')), reason: template.name);
      }
    }
  });

  test('a removed-rhythm note reads with the rhythm named', () {
    final note = WitnessNotice.fromRow({
      'id': 'n1',
      'kind': 'rhythm_removed',
      'runner_first_name': 'Brad',
      'detail': 'Exercise for 30 Minutes',
      'created_at': '2026-10-17T12:00:00Z',
    })!;
    expect(note.kind, WitnessNoticeKind.rhythmRemoved);
    expect(note.title, 'Brad removed a rhythm');
    expect(note.message, 'Brad removed "Exercise for 30 Minutes" from their Rule of Life. You might '
        'ask them about it.');

    final departed = WitnessNotice.fromRow({
      'id': 'n2',
      'kind': 'runner_left',
      'runner_first_name': 'Sarah',
    })!;
    expect(departed.title, 'Sarah has left The Trellis');
  });

  test('every starter Rule saves as rows with the same columns, throw-offs included', () {
    for (final baseline in ruleOfLifeBaselines) {
      final rows = baselineInsertRows('runner-1', baseline.items);
      expect(rows, hasLength(baseline.items.length), reason: baseline.name);
      final columns = rows.first.keys.toSet();
      for (final row in rows) {
        expect(row.keys.toSet(), columns, reason: baseline.name);
        expect(row['is_throw_off'], isA<bool>(), reason: baseline.name);
      }
    }
    // The Rule Grok hit: put-ons and a throw-off in one insert.
    final working = ruleOfLifeBaselines.firstWhere((b) => b.name == 'Working Parent');
    final rows = baselineInsertRows('runner-1', working.items);
    expect(rows.where((r) => r['is_throw_off'] == true), isNotEmpty);
    expect(rows.where((r) => r['is_throw_off'] == false), isNotEmpty);
  });
}
