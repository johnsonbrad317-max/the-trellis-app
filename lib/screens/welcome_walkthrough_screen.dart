import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_chip.dart' show BookplateTag;
import '../widgets/bookplate_dialog.dart' show BookplateButton, BookplateButtonVariant;
import '../widgets/bookplate_plate.dart' show BookplateDivider, BookplatePlate;
import '../widgets/brass_glyph.dart';
import '../widgets/nav_icon.dart';
import '../widgets/prayer_medallion.dart';
import '../widgets/trellis_scaffold.dart';
import '../widgets/trimmed_asset.dart';
import '../widgets/vine_frame.dart';
import '../widgets/vine_visualizer.dart';

/// The picture at the top of a welcome slide.
enum WelcomeArt {
  /// The trellis in full leaf — the race, run well.
  flourishingTrellis,
  runner,
  witness,
  cloud,

  /// A row of prayer medallions — faces and marks from a prayer garden.
  prayerGarden,

  /// A shared-free-time suggestion, as the Connect tab shows one.
  connect,

  /// A sample of what leaders see: a roster of vines, in summary only.
  leaderRoster,

  /// No picture: the slide's glyph rows ([WelcomeSlide.lines]) are the art.
  glyphRows,

  /// A vine partway up the trellis — a season just beginning.
  growingTrellis,
}

/// One line of the "How it works" slide: a tab's illustration beside its text.
class WelcomeLine {
  const WelcomeLine(this.glyph, this.text);

  final NavGlyph glyph;
  final String text;
}

/// One slide of the welcome walkthrough. The copy is the owner's; change it
/// here only when they ask.
class WelcomeSlide {
  const WelcomeSlide({
    required this.kicker,
    required this.headline,
    required this.art,
    this.body,
    this.lines = const [],
  });

  /// The brass small-caps line above the headline, e.g. "THE RUNNER".
  final String kicker;
  final String headline;
  final WelcomeArt art;

  /// Prose beneath the headline — or null when [lines] carry the body.
  final String? body;
  final List<WelcomeLine> lines;
}

/// The deck, in order: the race, the three roles (the Runner and Witness
/// cards in the words of the website), the Prayer and Connect tabs, what
/// leaders see, begin.
const List<WelcomeSlide> welcomeSlides = [
  WelcomeSlide(
    kicker: 'THE RACE',
    headline: 'Run with endurance.',
    art: WelcomeArt.flourishingTrellis,
    body: '“Therefore, since we are surrounded by so great a cloud of witnesses… let us '
        'run with endurance the race that is set before us, looking to Jesus.” '
        '— Hebrews 12:1–2',
  ),
  WelcomeSlide(
    kicker: 'THE RUNNER',
    headline: 'Anchor Your Days.',
    art: WelcomeArt.runner,
    body: 'Build your baseline spiritual practices — and name the sins to throw off — and '
        'track your growth over seasons. Rather than striving in isolation, define your '
        'Rule of Life and invite others to walk alongside you.',
  ),
  WelcomeSlide(
    kicker: 'THE WITNESS',
    headline: 'Walk Alongside.',
    art: WelcomeArt.witness,
    body: 'Be present for the entire journey. By quietly handling the logistics of checking '
        'in, the framework frees you to offer meaningful support — extending grace when '
        'they stumble, and true encouragement in seasons of growth.',
  ),
  WelcomeSlide(
    kicker: 'THE CLOUD',
    headline: 'Shepherd with Clarity.',
    art: WelcomeArt.cloud,
    body: 'An organization can gather its Runners under one canopy: shared DNA Rhythms for '
        'the whole flock, a roster of who is growing and who needs a hand — only in '
        "summary, never anyone's daily answers.",
  ),
  WelcomeSlide(
    kicker: 'PRAYER',
    headline: 'Keep a garden.',
    art: WelcomeArt.prayerGarden,
    body: 'The Prayer tab holds the people and burdens you carry — each a card with a face '
        'or a mark, a line of Scripture, and the day you last prayed. At the time you '
        'choose, a reminder walks you through them, one at a time.',
  ),
  WelcomeSlide(
    kicker: 'CONNECT',
    headline: 'Find the time.',
    art: WelcomeArt.connect,
    body: 'The Connect tab finds a time you and your Witness are both free — connect a '
        "calendar and it reads only busy or free, never what you're doing — and suggests "
        'a place between you. A text to your Witness is one tap away.',
  ),
  WelcomeSlide(
    kicker: 'WHAT LEADERS SEE',
    headline: 'The flock, not the diary.',
    art: WelcomeArt.leaderRoster,
    body: 'Your leaders see a roster of vines — flourishing, budding, drooping — how the '
        'shared DNA Rhythms are kept across the organization, and who has gone quiet. '
        "Never a single day's answers, and never your prayers.",
  ),
  WelcomeSlide(
    kicker: 'BEGIN',
    headline: 'Abide. Grow. Be Known.',
    art: WelcomeArt.growingTrellis,
    body: 'Set up your Rule of Life, invite a Witness, and let the season begin. You can read '
        'this again any time under How The Trellis Works in the menu.',
  ),
];

/// The welcome walkthrough: a short deck explaining the app's picture
/// (Hebrews 12), its three roles and how it works. Shown once after the first
/// sign-in (from AuthGate, [firstRun] true — with a Skip link, and Begin at the
/// end) and always available again from the menu ([firstRun] false — Done at
/// the end). Finishing by any route records it as seen and pops the screen.
class WelcomeWalkthroughScreen extends StatefulWidget {
  const WelcomeWalkthroughScreen({super.key, required this.profile, this.firstRun = true});

  final RunnerProfile profile;
  final bool firstRun;

  @override
  State<WelcomeWalkthroughScreen> createState() => _WelcomeWalkthroughScreenState();
}

class _WelcomeWalkthroughScreenState extends State<WelcomeWalkthroughScreen> {
  bool _finished = false;

  void _finish() {
    // Begin/Skip and the system back gesture can all land here; pop once.
    if (_finished) return;
    _finished = true;
    // Best-effort and never throws; the shell must not wait on the write.
    unawaited(widget.profile.markWelcomeSeen());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return WelcomeWalkthroughView(firstRun: widget.firstRun, onFinished: _finish);
  }
}

/// Everything on the welcome screen except the profile: the app bar (with
/// Skip on a first run), the slides, the dots and the Next/Begin/Done button.
/// [onFinished] fires once, on Begin/Done, Skip, or the system back gesture on
/// a first run. Split from [WelcomeWalkthroughScreen] so it can be pumped in a
/// test without a [RunnerProfile] (which only the database can construct).
class WelcomeWalkthroughView extends StatefulWidget {
  const WelcomeWalkthroughView({super.key, required this.firstRun, required this.onFinished});

  final bool firstRun;
  final VoidCallback onFinished;

  @override
  State<WelcomeWalkthroughView> createState() => _WelcomeWalkthroughViewState();
}

class _WelcomeWalkthroughViewState extends State<WelcomeWalkthroughView> {
  final _pageController = PageController(viewportFraction: 0.94);
  int _page = 0;

  static const _scaffoldPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 8);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _next() {
    if (_page >= welcomeSlides.length - 1) {
      widget.onFinished();
    } else {
      _goTo(_page + 1);
    }
  }

  /// The room [TrellisScaffold]'s scroll view leaves on this screen, so the
  /// whole deck — slide, dots, button — fits one screen with the button never
  /// below the fold. Read above the scaffold, where the MediaQuery still has
  /// the status bar in it (VineFrame takes it out for its child). The floor
  /// only matters on a screen too small for the deck at all, which then simply
  /// scrolls.
  double _deckHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final chrome = VineFrame.topBand(context) +
        BookplateAppBar.height +
        VineFrame.gap +
        _scaffoldPadding.vertical +
        VineFrame.bottomRestInset(context, keyboardOpen: false) +
        media.padding.bottom;
    return math.max(360, media.size.height - chrome);
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == welcomeSlides.length - 1;
    final deckHeight = _deckHeight(context);

    return PopScope(
      // On a first run the only ways out are Skip and Begin: a back gesture
      // counts as Skip, so the deck is still recorded as seen.
      canPop: !widget.firstRun,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onFinished();
      },
      child: TrellisScaffold(
        padding: _scaffoldPadding,
        appBar: BookplateAppBar(
          showBack: widget.firstRun ? false : null,
          actions: [
            if (widget.firstRun)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: BookplateButton(
                  label: 'Skip',
                  variant: BookplateButtonVariant.link,
                  compact: true,
                  onPressed: widget.onFinished,
                ),
              ),
          ],
        ),
        body: SizedBox(
          height: deckHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (page) => setState(() => _page = page),
                      children: [
                        for (var i = 0; i < welcomeSlides.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                            child: WelcomeSlideView(welcomeSlides[i]),
                          ),
                      ],
                    ),
                  ),
                  // Page dots, as on the role walkthrough: the 44px tap area is
                  // padding inside each dot.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < welcomeSlides.length; i++)
                        Semantics(
                          button: true,
                          selected: _page == i,
                          label: 'Show slide ${i + 1} of ${welcomeSlides.length}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _goTo(i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              child: AnimatedContainer(
                                key: ValueKey('welcome-dot-$i'),
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: _page == i ? 20 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _page == i ? AppColors.forestGreen : AppColors.vellumBorder,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  BookplateButton(
                    key: const ValueKey('welcome-primary'),
                    label: isLast ? (widget.firstRun ? 'Begin' : 'Done') : 'Next',
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One slide on a double-ruled bookplate (the same nested-Container edging as
/// OrnateRoleCard): the picture on top, a brass small-caps kicker, the
/// headline, and the body — which scrolls inside the plate if the screen or
/// text size leaves it no other room, so nothing ever overflows.
class WelcomeSlideView extends StatelessWidget {
  const WelcomeSlideView(this.slide, {super.key});

  final WelcomeSlide slide;

  Widget _art(double height) => switch (slide.art) {
        WelcomeArt.flourishingTrellis =>
          TrellisVisual(state: TrellisState.flourishing, reveal: 1, height: height),
        WelcomeArt.growingTrellis =>
          TrellisVisual(state: TrellisState.growing, reveal: 0.4, height: height),
        WelcomeArt.runner => _roleArt(UserRole.runner, height),
        WelcomeArt.witness => _roleArt(UserRole.witness, height),
        WelcomeArt.cloud => _roleArt(UserRole.cloud, height),
        // The composed pictures are laid out at a comfortable size and then
        // scaled down to the room the plate gives them, so a small phone or a
        // large text size can never make them overflow.
        WelcomeArt.prayerGarden => _fitted(const _PrayerGardenArt()),
        WelcomeArt.connect => _fitted(const _ConnectArt()),
        WelcomeArt.leaderRoster => _fitted(const _LeaderRosterArt()),
        WelcomeArt.glyphRows => const SizedBox.shrink(),
      };

  // A picture, not prose: it follows the slide's scale, not the text size (a
  // medallion's initials at a large text size would otherwise burst it).
  static Widget _fitted(Widget child) => MediaQuery.withNoTextScaling(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: 300, child: child),
        ),
      );

  /// The role card's illustration, cropped to its opaque region as the cards
  /// do, at a fixed height instead of filling the card.
  Widget _roleArt(UserRole role, double height) => TrimmedAsset(
        asset: role.cardArtAsset,
        imageSize: role.cardArtSize,
        content: role.cardArtContent,
        height: height,
        cacheWidth: 1400,
      );

  /// The body scrolls inside the plate if it must, so this never clips; it
  /// only keeps the longest cards' text from forcing a scroll at an enlarged
  /// text size, by easing the scale back a little for long bodies.
  TextScaler _bodyScaler(BuildContext context, String body) {
    final scaler = MediaQuery.textScalerOf(context);
    if (body.length < 220) return scaler;
    final current = scaler.scale(10) / 10;
    return TextScaler.linear(math.max(1, current * 0.92));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bodyStyle = textTheme.bodyMedium?.copyWith(height: 1.4);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.antiqueBrass),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.10),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.vellum,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.6)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The picture takes a share of the plate and leaves the words the
            // rest; a short plate (small phone, large text) gives it less.
            final plateHeight = constraints.maxHeight;
            final artHeight =
                (plateHeight * (plateHeight < 340 ? 0.30 : 0.38)).clamp(80.0, 240.0);
            final hasArt = slide.art != WelcomeArt.glyphRows;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasArt) ...[
                  SizedBox(height: artHeight, child: Center(child: _art(artHeight))),
                  const SizedBox(height: 14),
                ] else
                  const SizedBox(height: 8),
                Text(
                  slide.kicker,
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.antiqueBrass,
                    letterSpacing: 2.4,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                // The headline scrolls with the body: on a small phone at a
                // large text size a long headline can run to four lines, and
                // fixed in place it pushed the words off the plate.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          slide.headline,
                          style: textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        if (slide.body != null)
                          Text(
                            slide.body!,
                            style: slide.art == WelcomeArt.flourishingTrellis
                                ? bodyStyle?.copyWith(fontStyle: FontStyle.italic)
                                : bodyStyle,
                            textAlign: TextAlign.center,
                            textScaler: _bodyScaler(context, slide.body!),
                          )
                        else
                          for (var i = 0; i < slide.lines.length; i++) ...[
                            if (i > 0) const SizedBox(height: 14),
                            Row(
                              children: [
                                NavIcon(slide.lines[i].glyph),
                                const SizedBox(width: 14),
                                Expanded(child: Text(slide.lines[i].text, style: bodyStyle)),
                              ],
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Three prayer medallions — a face (initials), a mark for a situation, another
/// face — the way the Prayer tab's photo row reads. Sample names only.
class _PrayerGardenArt extends StatelessWidget {
  const _PrayerGardenArt();

  @override
  Widget build(BuildContext context) {
    // Drawn at the prayer card's own medallion size (where the initials are
    // known to fit at every text size) and scaled down by the slide.
    return const Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PrayerMedallion(name: 'Maria Lopez', size: 76),
        SizedBox(width: 18),
        PrayerMedallion(name: 'Healing', glyph: BrassGlyphKind.cross, size: 96),
        SizedBox(width: 18),
        PrayerMedallion(name: 'Sam Okafor', size: 76),
      ],
    );
  }
}

/// A shared-free-time suggestion on a small plate: calendar mark, "Both free",
/// a day and time, a place — the shape the Connect tab's suggestions take.
/// Laid out at its natural size; the slide scales it to fit.
class _ConnectArt extends StatelessWidget {
  const _ConnectArt();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return BookplatePlate(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrassGlyph(BrassGlyphKind.calendar, color: AppColors.antiqueBrass),
              const SizedBox(width: 10),
              Expanded(child: Text('Both free', style: textTheme.titleMedium, maxLines: 1)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Thursday at 12:00 PM', style: textTheme.bodyMedium, maxLines: 1),
          const SizedBox(height: 4),
          Row(
            children: [
              const BrassGlyph(BrassGlyphKind.pin, size: 16, color: AppColors.antiqueBrass),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Halfway between you',
                  style: textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Three roster rows, as a leader sees them: a small vine, a name, a status
/// word — and nothing else. Sample names only. Laid out at its natural size;
/// the slide scales it to fit.
class _LeaderRosterArt extends StatelessWidget {
  const _LeaderRosterArt();

  static const _rows = [
    ('Maria L.', 0.86, 'Full Bloom', AppColors.forestGreen),
    ('Sam O.', 0.55, 'Budding', AppColors.antiqueBrass),
    ('Jon P.', 0.30, 'Drooping', AppColors.terracotta),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return BookplatePlate(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _rows.length; i++) ...[
            if (i > 0) const BookplateDivider(),
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  VineGlyph(
                    vitalityScore: _rows[i].$2,
                    isDrooping: _rows[i].$2 < 0.45,
                    height: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _rows[i].$1,
                      style: textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  BookplateTag(label: _rows[i].$3, color: _rows[i].$4),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
