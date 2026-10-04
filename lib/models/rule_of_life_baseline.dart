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
  });

  final RuleCategory category;
  final String title;
  final RuleFrequency frequency;
  final Set<int> weeklyDays;
  final bool isAnchorRhythm;
}

/// A curated, one-tap starting Rule of Life for a common season of life —
/// shown as a horizontal carousel on the Rule of Life empty state so a new
/// Runner isn't staring at a blank category list.
class RuleOfLifeBaseline {
  const RuleOfLifeBaseline({required this.name, required this.tagline, required this.items});

  final String name;
  final String tagline;
  final List<BaselineRuleItem> items;
}

const ruleOfLifeBaselines = [
  RuleOfLifeBaseline(
    name: 'The Essential',
    tagline:
        'A simple, sustainable starting rhythm for anyone beginning their walk of accountability.',
    items: [
      BaselineRuleItem(category: RuleCategory.abidingPrayer, title: 'read Scripture'),
      BaselineRuleItem(category: RuleCategory.abidingPrayer, title: 'pray for 15 minutes'),
      BaselineRuleItem(
        category: RuleCategory.bodyPurity,
        title: 'maintain Sexual Purity in thought and deed',
        isAnchorRhythm: true,
      ),
      BaselineRuleItem(
        category: RuleCategory.bodyPurity,
        title: 'fast from food for 24 hours',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.friday},
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'gather with the local church for corporate worship',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'give at least 10% of income to the local church',
        frequency: RuleFrequency.monthly,
      ),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'The Independent',
    tagline: 'For the single adult building rhythms of faith and generosity without a '
        'built-in household of accountability.',
    items: [
      BaselineRuleItem(category: RuleCategory.abidingPrayer, title: 'read Scripture'),
      BaselineRuleItem(category: RuleCategory.abidingPrayer, title: 'pray for 15 minutes'),
      BaselineRuleItem(
        category: RuleCategory.bodyPurity,
        title: 'maintain Sexual Purity in thought and deed',
        isAnchorRhythm: true,
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'gather with the local church for corporate worship',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'give radically of time and money to the church and others',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'initiate an intentional gathering to avoid isolation',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.saturday},
      ),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'The Parent of Young Children',
    tagline: 'Realistic rhythms for a season with young kids and little margin.',
    items: [
      BaselineRuleItem(category: RuleCategory.abidingPrayer, title: 'read Scripture'),
      BaselineRuleItem(
        category: RuleCategory.marriageFamily,
        title: 'pray over the schedule and the children',
      ),
      BaselineRuleItem(
        category: RuleCategory.marriageFamily,
        title: 'have a tech-free family dinner',
        isAnchorRhythm: true,
      ),
      BaselineRuleItem(
        category: RuleCategory.marriageFamily,
        title: 'have a dedicated date night or uninterrupted connection time with spouse',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.friday},
      ),
      BaselineRuleItem(category: RuleCategory.bodyPurity, title: 'maintain Sexual Purity'),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'gather with the local church for corporate worship',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
      ),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'The Stay-At-Home Parent',
    tagline: 'Rhythms to fight isolation and stay spiritually and relationally fed while '
        'home with the kids all day.',
    items: [
      BaselineRuleItem(category: RuleCategory.abidingPrayer, title: 'read Scripture'),
      BaselineRuleItem(
        category: RuleCategory.abidingPrayer,
        title: 'pray for patience and strength',
      ),
      BaselineRuleItem(category: RuleCategory.bodyPurity, title: 'maintain Sexual Purity'),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'gather with the local church for corporate worship',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
        isAnchorRhythm: true,
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'have a meaningful conversation with another adult believer',
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'invest in a younger woman/believer',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.wednesday},
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'practice hospitality by opening the home',
        frequency: RuleFrequency.monthly,
      ),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'The Marketplace Leader',
    tagline: 'For the driven professional who needs hard boundaries between work, '
        'integrity, and home.',
    items: [
      BaselineRuleItem(
        category: RuleCategory.abidingPrayer,
        title: 'morning Solitude, Scripture, and Prayer',
      ),
      BaselineRuleItem(
        category: RuleCategory.workRest,
        title: 'disengage entirely from corporate email and professional work by 6:00 PM',
        isAnchorRhythm: true,
      ),
      BaselineRuleItem(
        category: RuleCategory.workRest,
        title: 'practice complete honesty and integrity in all contracts and business dealings',
      ),
      BaselineRuleItem(
        category: RuleCategory.bodyPurity,
        title: 'maintain Sexual Purity in thought and deed',
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'gather with the local church for corporate worship',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
      ),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'The Faithful Guide',
    tagline: 'For pastors, mentors, and spiritual guides pouring into the next generation.',
    items: [
      BaselineRuleItem(
        category: RuleCategory.abidingPrayer,
        title: 'read Scripture and engage in deep theological study',
      ),
      BaselineRuleItem(
        category: RuleCategory.abidingPrayer,
        title: 'intercede by name for the burdens of the next generation',
        isAnchorRhythm: true,
      ),
      BaselineRuleItem(category: RuleCategory.bodyPurity, title: 'maintain Sexual Purity'),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'gather with the local church for corporate worship',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
      ),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'actively disciple or mentor a younger believer',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.wednesday},
      ),
    ],
  ),
  RuleOfLifeBaseline(
    name: 'The Restorer',
    tagline: 'Closer accountability and smaller steps for anyone rebuilding trust after '
        'a breach.',
    items: [
      BaselineRuleItem(category: RuleCategory.abidingPrayer, title: 'read Scripture'),
      BaselineRuleItem(
        category: RuleCategory.abidingPrayer,
        title: 'pray a prayer of gratitude and dependence',
      ),
      BaselineRuleItem(
        category: RuleCategory.bodyPurity,
        title: 'confess temptation or relapse immediately to a Witness',
        isAnchorRhythm: true,
      ),
      BaselineRuleItem(category: RuleCategory.bodyPurity, title: 'maintain Sexual Purity'),
      BaselineRuleItem(
        category: RuleCategory.communityHospitality,
        title: 'gather with the local church, resisting the urge to isolate',
        frequency: RuleFrequency.weekly,
        weeklyDays: {DateTime.sunday},
      ),
    ],
  ),
];
