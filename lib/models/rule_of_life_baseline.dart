import 'rule_item.dart';

/// One rhythm inside a [RuleOfLifeBaseline] — the same shape
/// [RunnerProfile.addRuleItem] takes, bundled for one-tap application.
class BaselineRuleItem {
  const BaselineRuleItem({
    required this.category,
    required this.title,
    this.frequency = RuleFrequency.daily,
    this.weeklyDays = const {},
    this.isAnchorRhythm = false,
    this.isThrowOff = false,
  });

  /// A sin to throw off: [title] is the blank in "Avoid ___", always daily
  /// (see [RuleItem.isThrowOff]). Filed under Body & Purity, like every
  /// throw-off the Rule Builder adds.
  const BaselineRuleItem.throwOff(this.title, {this.isAnchorRhythm = false})
      : category = RuleCategory.bodyPurity,
        frequency = RuleFrequency.daily,
        weeklyDays = const {},
        isThrowOff = true;

  final RuleCategory category;
  final String title;
  final RuleFrequency frequency;
  final Set<int> weeklyDays;
  final bool isAnchorRhythm;
  final bool isThrowOff;

  /// How the rhythm reads on a template card: "Read Scripture · daily",
  /// "Avoid gossip · daily", "Gather with my church · Sundays".
  String get summary {
    final what = isThrowOff ? 'Avoid $title' : _capitalised(title);
    return '$what · ${_scheduleLabel()}';
  }

  String _scheduleLabel() {
    switch (frequency) {
      case RuleFrequency.daily:
        return 'daily';
      case RuleFrequency.monthly:
        return 'monthly';
      case RuleFrequency.annual:
        return 'yearly';
      case RuleFrequency.weekly:
        final days = [for (final day in weekdayOrder) if (weeklyDays.contains(day)) day];
        if (days.length == 5 && !days.contains(DateTime.saturday) && !days.contains(DateTime.sunday)) {
          return 'weekdays';
        }
        if (days.length == 1) return '${_dayNames[days.single]}s';
        return 'weekly';
    }
  }

  static const _dayNames = {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  static String _capitalised(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

/// A ready-made starting Rule of Life for a common season of life. Kept small
/// on purpose — three to five rhythms, at most one or two sins to throw off —
/// and each fitted to the person it is for: a stay-at-home parent is far more
/// likely to wrestle with gossip than pornography, a young single adult the
/// reverse. Everything can be changed before committing.
class RuleOfLifeBaseline {
  const RuleOfLifeBaseline({required this.name, required this.tagline, required this.items});

  final String name;

  /// One line: who this is for.
  final String tagline;
  final List<BaselineRuleItem> items;
}

const _weekdays = {
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
};

const _church = BaselineRuleItem(
  category: RuleCategory.communityHospitality,
  title: 'gather with my church',
  frequency: RuleFrequency.weekly,
  weeklyDays: {DateTime.sunday},
);

const _scripture = BaselineRuleItem(category: RuleCategory.abidingPrayer, title: 'read Scripture');

const ruleOfLifeBaselines = [
  RuleOfLifeBaseline(
    name: 'First Steps',
    tagline: 'For anyone just beginning. Three simple rhythms, nothing more.',
    items: [
      _scripture,
      BaselineRuleItem(category: RuleCategory.abidingPrayer, title: 'spend time in prayer'),
      _church,
    ],
  ),
  RuleOfLifeBaseline(
    name: 'Home with Little Ones',
    tagline: 'For the parent at home all day: small rhythms that fit around nap time.',
    items: [
      _scripture,
      BaselineRuleItem(category: RuleCategory.marriageFamily, title: 'pray over my children'),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'have a real conversation with another adult believer',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.wednesday},
      ),
      _church,
      BaselineRuleItem.throwOff('gossip'),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'Working Parent',
    tagline: 'For the parent balancing a job and a household.',
    items: [
      _scripture,
      BaselineRuleItem(
        category: RuleCategory.marriageFamily,
        title: 'put my phone away at family dinner',
      ),
      BaselineRuleItem(
        category: RuleCategory.marriageFamily,
        title: 'have a date night with my spouse',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.friday},
      ),
      _church,
      BaselineRuleItem.throwOff('outbursts of anger'),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'Single Adult',
    tagline: 'For the single adult building faith, real friendships and purity.',
    items: [
      _scripture,
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'share a meal with friends from church',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.saturday},
      ),
      _church,
      BaselineRuleItem.throwOff('looking at pornography'),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'Marketplace',
    tagline: 'For the professional who needs clear lines between work, integrity and home.',
    items: [
      BaselineRuleItem(
        category: RuleCategory.abidingPrayer,
        title: 'start the day with Scripture and prayer',
      ),
      BaselineRuleItem(
        category: RuleCategory.workRest,
        title: 'be done with work by 6 PM',
        frequency: RuleFrequency.weekly,
        weeklyDays: _weekdays,
      ),
      _church,
      BaselineRuleItem.throwOff('lying or exaggerating'),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'Fighting for Purity',
    tagline: 'Closer accountability for anyone battling lust. Your Witness hears right away '
        'if you fall.',
    items: [
      _scripture,
      BaselineRuleItem(
        category: RuleCategory.bodyPurity,
        title: 'keep my phone out of the bedroom at night',
      ),
      _church,
      BaselineRuleItem.throwOff('looking at pornography', isAnchorRhythm: true),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'Leading Others',
    tagline: 'For pastors, mentors and ministry leaders who pour out all week.',
    items: [
      BaselineRuleItem(
        category: RuleCategory.abidingPrayer,
        title: 'read Scripture for my own soul',
      ),
      BaselineRuleItem(
        category: RuleCategory.abidingPrayer,
        title: 'pray by name for the people I lead',
      ),
      BaselineRuleItem(
        category: RuleCategory.workRest,
        title: 'keep a weekly Sabbath',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.monday},
      ),
    ],
  ),
];
