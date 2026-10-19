// From the Berean Standard Bible (public domain, BereanBible.com), word for word.
// The owner reviews this list (docs/scripture-verses-for-review.md); edit the
// passages here, keeping each to three verses or fewer so a text stays short.
// ignore_for_file: lines_longer_than_80_chars

/// A theme someone can choose when adding a verse to an "I prayed for you" text.
enum ScriptureTheme { peace, strength, hope, comfort, wisdom, worry, courage, patience, forgiveness, joy, provision, guidance }

extension ScriptureThemeLabel on ScriptureTheme {
  String get label => switch (this) {
        ScriptureTheme.peace => 'Peace',
        ScriptureTheme.strength => 'Strength',
        ScriptureTheme.hope => 'Hope',
        ScriptureTheme.comfort => 'Comfort',
        ScriptureTheme.wisdom => 'Wisdom',
        ScriptureTheme.worry => 'Worry',
        ScriptureTheme.courage => 'Courage',
        ScriptureTheme.patience => 'Patience',
        ScriptureTheme.forgiveness => 'Forgiveness',
        ScriptureTheme.joy => 'Joy',
        ScriptureTheme.provision => 'Provision',
        ScriptureTheme.guidance => 'Guidance',
      };
}

/// One passage, in the BSB, ready to paste into a text.
class ScripturePassage {
  const ScripturePassage(this.reference, this.text);

  /// "Philippians 4:6–7"
  final String reference;

  /// The verse text, word for word.
  final String text;
}

/// Themes whose first passage is always the one offered first. In every
/// other theme the starting passage rotates by day and person.
const Set<ScriptureTheme> themesLedByFirstPassage = {ScriptureTheme.comfort};

/// Every theme's passages, in the order they are offered.
const Map<ScriptureTheme, List<ScripturePassage>> scriptureByTheme = {
  ScriptureTheme.peace: [
    ScripturePassage(
      'John 14:27',
      'Peace I leave with you; My peace I give to you. I do not give to you as the world gives. Do not let your hearts be troubled; do not be afraid.',
    ),
    ScripturePassage(
      'Philippians 4:6–7',
      'Be anxious for nothing, but in everything, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which surpasses all understanding, will guard your hearts and your minds in Christ Jesus.',
    ),
    ScripturePassage(
      'Isaiah 26:3',
      'You will keep in perfect peace the steadfast of mind, because he trusts in You.',
    ),
    ScripturePassage(
      'Numbers 6:24–26',
      '‘May the LORD bless you and keep you; may the LORD cause His face to shine upon you and be gracious to you; may the LORD lift up His countenance toward you and give you peace.’',
    ),
    ScripturePassage(
      '2 Thessalonians 3:16',
      'Now may the Lord of peace Himself give you peace at all times and in every way. The Lord be with all of you.',
    ),
    ScripturePassage(
      'Colossians 3:15',
      'Let the peace of Christ rule in your hearts, for to this you were called as members of one body. And be thankful.',
    ),
    ScripturePassage(
      'Psalm 4:8',
      'I will lie down and sleep in peace, for You alone, O LORD, make me dwell in safety.',
    ),
  ],
  ScriptureTheme.strength: [
    ScripturePassage(
      'Isaiah 40:29–31',
      'He gives power to the faint and increases the strength of the weak. Even youths grow tired and weary, and young men stumble and fall. But those who wait upon the LORD will renew their strength; they will mount up with wings like eagles; they will run and not grow weary, they will walk and not faint.',
    ),
    ScripturePassage(
      '2 Corinthians 12:9',
      'But He said to me, “My grace is sufficient for you, for My power is perfected in weakness.” Therefore I will boast all the more gladly in my weaknesses, so that the power of Christ may rest on me.',
    ),
    ScripturePassage(
      'Psalm 46:1',
      'God is our refuge and strength, an ever-present help in times of trouble.',
    ),
    ScripturePassage(
      'Isaiah 41:10',
      'Do not fear, for I am with you; do not be afraid, for I am your God. I will strengthen you; I will surely help you; I will uphold you with My righteous right hand.',
    ),
    ScripturePassage(
      'Psalm 73:26',
      'My flesh and my heart may fail, but God is the strength of my heart and my portion forever.',
    ),
    ScripturePassage(
      'Ephesians 6:10',
      'Finally, be strong in the Lord and in His mighty power.',
    ),
    ScripturePassage(
      'Psalm 28:7',
      'The LORD is my strength and my shield; my heart trusts in Him, and I am helped. Therefore my heart rejoices, and I give thanks to Him with my song.',
    ),
  ],
  ScriptureTheme.hope: [
    ScripturePassage(
      'Romans 15:13',
      'Now may the God of hope fill you with all joy and peace as you believe in Him, so that you may overflow with hope by the power of the Holy Spirit.',
    ),
    ScripturePassage(
      'Lamentations 3:22–23',
      'Because of the loving devotion of the LORD we are not consumed, for His mercies never fail. They are new every morning; great is Your faithfulness!',
    ),
    ScripturePassage(
      'Hebrews 10:23',
      'Let us hold resolutely to the hope we profess, for He who promised is faithful.',
    ),
    ScripturePassage(
      'Romans 5:5',
      'And hope does not disappoint us, because God has poured out His love into our hearts through the Holy Spirit, whom He has given us.',
    ),
    ScripturePassage(
      'Psalm 62:5',
      'Rest in God alone, O my soul, for my hope comes from Him.',
    ),
    ScripturePassage(
      'Psalm 42:11',
      'Why are you downcast, O my soul? Why the unease within me? Put your hope in God, for I will yet praise Him, my Savior and my God.',
    ),
    ScripturePassage(
      'Romans 8:28',
      'And we know that God works all things together for the good of those who love Him, who are called according to His purpose.',
    ),
  ],
  ScriptureTheme.comfort: [
    // The owner's choice: always offered first for Comfort (see
    // themesLedByFirstPassage). Habakkuk 3:19's closing note ("For the
    // choirmaster. With stringed instruments.") is left off.
    ScripturePassage(
      'Habakkuk 3:17–19',
      'Though the fig tree does not bud and no fruit is on the vines, though the olive crop fails and the fields produce no food, though the sheep are cut off from the fold and no cattle are in the stalls, yet I will exult in the LORD; I will rejoice in the God of my salvation! GOD the Lord is my strength; He makes my feet like those of a deer; He makes me walk upon the heights!',
    ),
    ScripturePassage(
      'Psalm 34:18',
      'The LORD is near to the brokenhearted; He saves the contrite in spirit.',
    ),
    ScripturePassage(
      'Matthew 5:4',
      'Blessed are those who mourn, for they will be comforted.',
    ),
    ScripturePassage(
      '2 Corinthians 1:3–4',
      'Blessed be the God and Father of our Lord Jesus Christ, the Father of compassion and the God of all comfort, who comforts us in all our troubles, so that we can comfort those in any trouble with the comfort we ourselves have received from God.',
    ),
    ScripturePassage(
      'Psalm 23:4',
      'Even though I walk through the valley of the shadow of death, I will fear no evil, for You are with me; Your rod and Your staff, they comfort me.',
    ),
    ScripturePassage(
      'Revelation 21:4',
      '‘He will wipe away every tear from their eyes,’ and there will be no more death or mourning or crying or pain, for the former things have passed away.',
    ),
    ScripturePassage(
      'Psalm 147:3',
      'He heals the brokenhearted and binds up their wounds.',
    ),
    ScripturePassage(
      'Isaiah 43:2',
      'When you pass through the waters, I will be with you; and when you go through the rivers, they will not overwhelm you. When you walk through the fire, you will not be scorched; the flames will not set you ablaze.',
    ),
  ],
  ScriptureTheme.wisdom: [
    ScripturePassage(
      'James 1:5',
      'Now if any of you lacks wisdom, he should ask God, who gives generously to all without finding fault, and it will be given to him.',
    ),
    ScripturePassage(
      'Proverbs 2:6',
      'For the LORD gives wisdom; from His mouth come knowledge and understanding.',
    ),
    ScripturePassage(
      'James 3:17',
      'But the wisdom from above is first of all pure, then peace-loving, gentle, accommodating, full of mercy and good fruit, impartial, and sincere.',
    ),
    ScripturePassage(
      'Proverbs 19:20',
      'Listen to counsel and accept discipline, that you may be wise the rest of your days.',
    ),
    ScripturePassage(
      'Proverbs 9:10',
      'The fear of the LORD is the beginning of wisdom, and knowledge of the Holy One is understanding.',
    ),
    ScripturePassage(
      'Psalm 90:12',
      'So teach us to number our days, that we may present a heart of wisdom.',
    ),
    ScripturePassage(
      'Proverbs 4:7',
      'Wisdom is supreme; so acquire wisdom. And whatever you may acquire, gain understanding.',
    ),
  ],
  ScriptureTheme.worry: [
    ScripturePassage(
      'Matthew 6:33–34',
      'But seek first the kingdom of God and His righteousness, and all these things will be added unto you. Therefore do not worry about tomorrow, for tomorrow will worry about itself. Today has enough trouble of its own.',
    ),
    ScripturePassage(
      '1 Peter 5:7',
      'Cast all your anxiety on Him, because He cares for you.',
    ),
    ScripturePassage(
      'Psalm 94:19',
      'When anxiety overwhelms me, Your consolation delights my soul.',
    ),
    ScripturePassage(
      'Psalm 55:22',
      'Cast your burden upon the LORD and He will sustain you; He will never let the righteous be shaken.',
    ),
    ScripturePassage(
      'Matthew 11:28–30',
      'Come to Me, all you who are weary and burdened, and I will give you rest. Take My yoke upon you and learn from Me, for I am gentle and humble in heart, and you will find rest for your souls. For My yoke is easy and My burden is light.',
    ),
    ScripturePassage(
      'John 16:33',
      'I have told you these things so that in Me you may have peace. In the world you will have tribulation. But take courage; I have overcome the world!',
    ),
    ScripturePassage(
      'Isaiah 41:13',
      'For I am the LORD your God, who takes hold of your right hand and tells you: Do not fear, I will help you.',
    ),
  ],
  ScriptureTheme.courage: [
    ScripturePassage(
      'Joshua 1:9',
      'Have I not commanded you to be strong and courageous? Do not be afraid; do not be discouraged, for the LORD your God is with you wherever you go.',
    ),
    ScripturePassage(
      'Deuteronomy 31:6',
      'Be strong and courageous; do not be afraid or terrified of them, for it is the LORD your God who goes with you; He will never leave you nor forsake you.',
    ),
    ScripturePassage(
      'Psalm 27:1',
      'The LORD is my light and my salvation—whom shall I fear? The LORD is the stronghold of my life—whom shall I dread?',
    ),
    ScripturePassage(
      '2 Timothy 1:7',
      'For God has not given us a spirit of fear, but of power, love, and self-control.',
    ),
    ScripturePassage(
      'Psalm 56:3–4',
      'When I am afraid, I put my trust in You. In God, whose word I praise—in God I trust. I will not be afraid. What can man do to me?',
    ),
    ScripturePassage(
      'Psalm 31:24',
      'Be strong and courageous, all you who hope in the LORD.',
    ),
    ScripturePassage(
      'Isaiah 43:1',
      'But now, this is what the LORD says—He who created you, O Jacob, and He who formed you, O Israel: “Do not fear, for I have redeemed you; I have called you by your name; you are Mine!”',
    ),
  ],
  ScriptureTheme.patience: [
    ScripturePassage(
      'Psalm 27:14',
      'Wait patiently for the LORD; be strong and courageous. Wait patiently for the LORD!',
    ),
    ScripturePassage(
      'Galatians 6:9',
      'Let us not grow weary in well-doing, for in due time we will reap a harvest if we do not give up.',
    ),
    ScripturePassage(
      'Romans 12:12',
      'Be joyful in hope, patient in affliction, persistent in prayer.',
    ),
    ScripturePassage(
      'Lamentations 3:25–26',
      'The LORD is good to those who wait for Him, to the soul who seeks Him. It is good to wait quietly for the salvation of the LORD.',
    ),
    ScripturePassage(
      'Psalm 40:1',
      'I waited patiently for the LORD; He inclined to me and heard my cry.',
    ),
    ScripturePassage(
      'Micah 7:7',
      'But as for me, I will look to the LORD; I will wait for the God of my salvation. My God will hear me.',
    ),
    ScripturePassage(
      'Hebrews 12:1–2',
      'Therefore, since we are surrounded by such a great cloud of witnesses, let us throw off every encumbrance and the sin that so easily entangles, and let us run with endurance the race set out for us. Let us fix our eyes on Jesus, the author and perfecter of our faith, who for the joy set before Him endured the cross, scorning its shame, and sat down at the right hand of the throne of God.',
    ),
  ],
  ScriptureTheme.forgiveness: [
    ScripturePassage(
      '1 John 1:9',
      'If we confess our sins, He is faithful and just to forgive us our sins and to cleanse us from all unrighteousness.',
    ),
    ScripturePassage(
      'Psalm 103:12',
      'As far as the east is from the west, so far has He removed our transgressions from us.',
    ),
    ScripturePassage(
      'Ephesians 4:32',
      'Be kind and tenderhearted to one another, forgiving each other just as in Christ God forgave you.',
    ),
    ScripturePassage(
      'Colossians 3:13',
      'Bear with one another and forgive any complaint you may have against someone else. Forgive as the Lord forgave you.',
    ),
    ScripturePassage(
      'Isaiah 1:18',
      '“Come now, let us reason together,” says the LORD. “Though your sins are like scarlet, they will be as white as snow; though they are as red as crimson, they will become like wool.”',
    ),
    ScripturePassage(
      'Romans 8:1',
      'Therefore, there is now no condemnation for those who are in Christ Jesus.',
    ),
    ScripturePassage(
      'Psalm 51:10',
      'Create in me a clean heart, O God, and renew a right spirit within me.',
    ),
  ],
  ScriptureTheme.joy: [
    ScripturePassage(
      'Psalm 16:11',
      'You have made known to me the path of life; You will fill me with joy in Your presence, with eternal pleasures at Your right hand.',
    ),
    ScripturePassage(
      'Philippians 4:4',
      'Rejoice in the Lord always. I will say it again: Rejoice!',
    ),
    ScripturePassage(
      'John 15:11',
      'I have told you these things so that My joy may be in you and your joy may be complete.',
    ),
    ScripturePassage(
      'Psalm 118:24',
      'This is the day that the LORD has made; we will rejoice and be glad in it.',
    ),
    ScripturePassage(
      'Psalm 30:5',
      'For His anger is fleeting, but His favor lasts a lifetime. Weeping may stay the night, but joy comes in the morning.',
    ),
    ScripturePassage(
      '1 Thessalonians 5:16–18',
      'Rejoice at all times. Pray without ceasing. Give thanks in every circumstance, for this is God’s will for you in Christ Jesus.',
    ),
    ScripturePassage(
      'Zephaniah 3:17',
      'The LORD your God is among you; He is mighty to save. He will rejoice over you with gladness; He will quiet you with His love; He will rejoice over you with singing.',
    ),
  ],
  ScriptureTheme.provision: [
    ScripturePassage(
      'Philippians 4:19',
      'And my God will supply all your needs according to His glorious riches in Christ Jesus.',
    ),
    ScripturePassage(
      'Matthew 6:26',
      'Look at the birds of the air: They do not sow or reap or gather into barns, and yet your heavenly Father feeds them. Are you not much more valuable than they?',
    ),
    ScripturePassage(
      'Psalm 23:1–3',
      'The LORD is my shepherd; I shall not want. He makes me lie down in green pastures; He leads me beside quiet waters. He restores my soul; He guides me in the paths of righteousness for the sake of His name.',
    ),
    ScripturePassage(
      '2 Corinthians 9:8',
      'And God is able to make all grace abound to you, so that in all things, at all times, having all that you need, you will abound in every good work.',
    ),
    ScripturePassage(
      'Psalm 84:11',
      'For the LORD God is a sun and a shield; the LORD gives grace and glory; He withholds no good thing from those who walk with integrity.',
    ),
    ScripturePassage(
      'Psalm 145:15–16',
      'The eyes of all look to You, and You give them their food in season. You open Your hand and satisfy the desire of every living thing.',
    ),
    ScripturePassage(
      'Psalm 34:10',
      'Young lions go lacking and hungry, but those who seek the LORD lack no good thing.',
    ),
  ],
  ScriptureTheme.guidance: [
    ScripturePassage(
      'Proverbs 3:5–6',
      'Trust in the LORD with all your heart, and lean not on your own understanding; in all your ways acknowledge Him, and He will make your paths straight.',
    ),
    ScripturePassage(
      'Psalm 32:8',
      'I will instruct you and teach you the way you should go; I will give you counsel and watch over you.',
    ),
    ScripturePassage(
      'Psalm 119:105',
      'Your word is a lamp to my feet and a light to my path.',
    ),
    ScripturePassage(
      'Isaiah 30:21',
      'And whether you turn to the right or to the left, your ears will hear this command behind you: “This is the way. Walk in it.”',
    ),
    ScripturePassage(
      'Proverbs 16:3',
      'Commit your works to the LORD and your plans will be achieved.',
    ),
    ScripturePassage(
      'Psalm 25:4–5',
      'Show me Your ways, O LORD; teach me Your paths. Guide me in Your truth and teach me, for You are the God of my salvation; all day long I wait for You.',
    ),
    ScripturePassage(
      'Proverbs 16:9',
      'A man’s heart plans his course, but the LORD determines his steps.',
    ),
  ],
};
