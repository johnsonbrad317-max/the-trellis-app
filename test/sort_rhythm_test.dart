import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/rule_item.dart';

/// Anything named as something not to do belongs with the sins to throw off,
/// so its check-in reads "Did you avoid ___?" (supabase/migrations/032).
void main() {
  test('"No…", "Abstain from…" and the like become sins to throw off', () {
    expect(sortRhythm('No Checking Work Email After Hours'),
        (title: 'Checking Work Email After Hours', isThrowOff: true));
    expect(sortRhythm('Abstain from alcohol'), (title: 'alcohol', isThrowOff: true));
    expect(sortRhythm("Don't gossip"), (title: 'gossip', isThrowOff: true));
    expect(sortRhythm('do not overspend'), (title: 'overspend', isThrowOff: true));
    expect(sortRhythm('Avoid idle scrolling'), (title: 'idle scrolling', isThrowOff: true));
  });

  test('ordinary rhythms are left as they are', () {
    expect(sortRhythm('  Pray Over the Kids '), (title: 'Pray Over the Kids', isThrowOff: false));
    expect(sortRhythm('Notice three blessings'), (title: 'Notice three blessings', isThrowOff: false));
    expect(sortRhythm('No'), (title: 'No', isThrowOff: false));
    expect(sortRhythm('gossip', isThrowOff: true), (title: 'gossip', isThrowOff: true));
  });

  test('the put-on presets hold nothing negative; the avoid list has them', () {
    expect(throwOffPresets, containsAll(['checking work email after hours', 'drinking alcohol']));
    for (final preset in throwOffPresets) {
      expect(sortRhythm(preset).isThrowOff, isFalse, reason: '"$preset" is already the blank');
    }
  });
}
