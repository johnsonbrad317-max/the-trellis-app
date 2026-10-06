import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart' show BookplateButton, BookplateButtonVariant;
import '../widgets/nav_icon.dart';
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

/// The deck, in order: the race, the three roles, how it works, begin.
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
    headline: 'Anchor your days.',
    art: WelcomeArt.runner,
    body: 'You build a Rule of Life — a handful of rhythms you commit to: prayer, Scripture, '
        'rest, purity, hospitality. Each day you look back on yesterday and answer honestly. '
        'Over a season, your vine grows up the trellis.',
  ),
  WelcomeSlide(
    kicker: 'THE WITNESS',
    headline: 'Be known.',
    art: WelcomeArt.witness,
    body: 'A Witness walks alongside you. They see your rhythms and how you are keeping them '
        '— never your journal — and they are the first to know when you stumble. You '
        'can text them, pray for each other, and meet.',
  ),
  WelcomeSlide(
    kicker: 'THE CLOUD',
    headline: 'Shepherd with clarity.',
    art: WelcomeArt.cloud,
    body: 'A church can gather its Runners under one canopy: shared DNA Rhythms for the whole '
        'flock, a roster of who is growing and who needs a hand — only in summary, never '
        "anyone's daily answers.",
  ),
  WelcomeSlide(
    kicker: 'HOW IT WORKS',
    headline: 'A rhythm each day, a season at a time.',
    art: WelcomeArt.glyphRows,
    lines: [
      WelcomeLine(NavGlyph.rule, 'Rule of Life — build it, commit it, check in daily.'),
      WelcomeLine(
        NavGlyph.prayer,
        'Prayer — keep a garden of the people and burdens you carry.',
      ),
      WelcomeLine(
        NavGlyph.connect,
        'Connect — find time with your Witness when you both are free.',
      ),
    ],
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
        WelcomeArt.glyphRows => const SizedBox.shrink(),
      };

  /// The role card's illustration, cropped to its opaque region as the cards
  /// do, at a fixed height instead of filling the card.
  Widget _roleArt(UserRole role, double height) => TrimmedAsset(
        asset: role.cardArtAsset,
        imageSize: role.cardArtSize,
        content: role.cardArtContent,
        height: height,
        cacheWidth: 1400,
      );

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
                Text(slide.headline, style: textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: slide.body != null
                        ? Text(
                            slide.body!,
                            style: slide.art == WelcomeArt.flourishingTrellis
                                ? bodyStyle?.copyWith(fontStyle: FontStyle.italic)
                                : bodyStyle,
                            textAlign: TextAlign.center,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
