import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart' show BookplateButton, BookplateButtonVariant;
import '../widgets/brass_glyph.dart';
import '../widgets/nav_icon.dart';
import '../widgets/trellis_scaffold.dart';
import '../widgets/trimmed_asset.dart';
import '../widgets/vine_frame.dart';
import '../widgets/vine_visualizer.dart';

/// The picture at the top of a welcome slide. Each is one of the app's own
/// woodcuts or a composition of its parts, so the deck looks like the role
/// cards and the rest of the app.
enum WelcomeArt {
  /// A traveler on a rugged path, looking toward the cross (the Runner's
  /// woodcut) — on THE RUNNER card, as on the role card.
  raceTraveler,

  /// A vellum card bearing the Rule of Life book — the Word that opens THE
  /// RACE.
  ruleCard,

  /// Two companions on the path, one arm around the other (the Witness's
  /// woodcut).
  companions,

  /// A shepherd with a staff over the valley (the Cloud's woodcut).
  shepherd,

  /// The trellis in full leaf — a flourishing botanical vine.
  flourishingVine,

  /// A shared-free-time card on dark stone.
  connect,

  /// Two trellises side by side: one flourishing, one weary.
  communityHealth,

  /// The Trellis seal on parchment.
  seal,
}

/// One slide of the welcome walkthrough. The copy is the owner's; change it
/// here only when they ask.
class WelcomeSlide {
  const WelcomeSlide({
    required this.kicker,
    required this.headline,
    required this.art,
    required this.body,
    this.isScripture = false,
  });

  /// The brass small-caps line above the headline, e.g. "THE RUNNER".
  final String kicker;
  final String headline;
  final WelcomeArt art;
  final String body;

  /// Set in italics, as a quotation.
  final bool isScripture;
}

/// The deck, in order: the race, the three roles, prayer, connect, what
/// leaders see, begin.
const List<WelcomeSlide> welcomeSlides = [
  WelcomeSlide(
    kicker: 'THE RACE',
    headline: 'Let us throw off everything that hinders…',
    art: WelcomeArt.ruleCard,
    isScripture: true,
    body: '…and the sin that so easily entangles. And let us run with perseverance the race '
        'marked out for us, fixing our eyes on Jesus, the pioneer and perfecter of faith. '
        '— Hebrews 12:1–2',
  ),
  WelcomeSlide(
    kicker: 'THE RUNNER',
    headline: 'Anchor Your Days.',
    art: WelcomeArt.raceTraveler,
    body: 'Shed the friction of merely managing life to pursue the life you were made for. '
        'Define your Rule of Life—building daily rhythms of abiding, family, and purity—and '
        'explicitly name the weights you must throw off. Do not strive in isolation; build '
        'your rhythms and run your race with trusted companions.',
  ),
  WelcomeSlide(
    kicker: 'THE WITNESS',
    headline: 'Walk Alongside.',
    art: WelcomeArt.companions,
    body: 'We were never meant to run alone. Stand as a trusted witness for those who invite '
        'you into their race. Carry one another’s burdens, offer truth in the quiet '
        'struggles, and hold the light for your friends when the path grows dark.',
  ),
  WelcomeSlide(
    kicker: 'THE CLOUD',
    headline: 'Shepherd the Flock.',
    art: WelcomeArt.shepherd,
    body: 'Gather your people to oversee their spiritual health, foster deep one-on-one '
        'connections, and cultivate a community of care without the exhausting '
        'administrative friction.',
  ),
  WelcomeSlide(
    kicker: 'PRAYER',
    headline: 'Cultivate a Garden of Intercession.',
    art: WelcomeArt.flourishingVine,
    body: 'Keep a living record of the people and burdens you are carrying. Anchor your mind '
        'on what matters most, moving beyond passing thoughts to build a sustained, '
        'intentional rhythm of prayer for your family, your witnesses, and your community.',
  ),
  WelcomeSlide(
    kicker: 'CONNECT',
    headline: 'Find the Time.',
    art: WelcomeArt.connect,
    body: 'Strip away the logistical friction of finding time to meet. Whether gathering for '
        'a shared meal, a one-on-one walk, or a spontaneous moment of outreach, simply see '
        'where your rhythms align so you can focus entirely on showing up for one another.',
  ),
  WelcomeSlide(
    kicker: 'WHAT LEADERS SEE',
    headline: 'The Flock, Not the Confessional.',
    art: WelcomeArt.communityHealth,
    body: 'The Cloud provides leaders with clear visibility into the overarching spiritual '
        'health of the community—revealing who is flourishing and who is quietly drooping. '
        'But the sacred privacy of the Runner remains secure: leadership sees the season you '
        'are in, never the granular details of your daily struggles or private prayers.',
  ),
  WelcomeSlide(
    kicker: 'BEGIN',
    headline: 'Begin the Race.',
    art: WelcomeArt.seal,
    body: 'Step onto the path. Build your rhythms. Invite your witnesses.',
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
/// OrnateRoleCard): the picture on top, a brass small-caps kicker, then the
/// headline and body — which scroll inside the plate if the screen or text
/// size leaves them no other room, so nothing ever overflows.
class WelcomeSlideView extends StatelessWidget {
  const WelcomeSlideView(this.slide, {super.key});

  final WelcomeSlide slide;

  Widget _art(double height) => switch (slide.art) {
        WelcomeArt.raceTraveler => _roleArt(UserRole.runner, height),
        WelcomeArt.companions => _roleArt(UserRole.witness, height),
        WelcomeArt.shepherd => _roleArt(UserRole.cloud, height),
        WelcomeArt.flourishingVine =>
          TrellisVisual(state: TrellisState.flourishing, reveal: 1, height: height),
        WelcomeArt.ruleCard => _VellumCard(
            child: TrimmedAsset(
              asset: NavGlyph.rule.asset,
              imageSize: NavGlyph.rule.imageSize,
              content: NavGlyph.rule.content,
              height: height * 0.7,
              cacheWidth: 900,
            ),
          ),
        // Compositions are laid out at a comfortable size and scaled down to
        // the room the plate gives them, so a small phone or a large text
        // size can never make them overflow.
        WelcomeArt.connect => _fitted(const _ConnectArt()),
        WelcomeArt.communityHealth => _fitted(const _CommunityHealthArt()),
        WelcomeArt.seal => Image.asset(
            'assets/images/the_trellis_icon_transparent.png',
            height: height,
            fit: BoxFit.contain,
            cacheWidth: 600,
          ),
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

  // A picture, not prose: it follows the slide's scale, not the text size.
  static Widget _fitted(Widget child) => MediaQuery.withNoTextScaling(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: 300, child: child),
        ),
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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: artHeight, child: Center(child: _art(artHeight))),
                const SizedBox(height: 14),
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
                        Text(
                          slide.body,
                          style: slide.isScripture
                              ? bodyStyle?.copyWith(fontStyle: FontStyle.italic)
                              : bodyStyle,
                          textAlign: TextAlign.center,
                          textScaler: _bodyScaler(context, slide.body),
                        ),
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

/// A small vellum card with a brass hairline, for an illustration that is
/// itself a picture of a card.
class _VellumCard extends StatelessWidget {
  const _VellumCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.antiqueBrass.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A shared-free-time card on dark stone: calendar mark, "Both free", a day
/// and time, a place — the shape the Connect tab's suggestions take, set on
/// forest green with parchment lettering. Laid out at its natural size; the
/// slide scales it to fit.
class _ConnectArt extends StatelessWidget {
  const _ConnectArt();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final light = AppColors.parchmentLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.forestGreen,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrassGlyph(BrassGlyphKind.calendar, color: AppColors.antiqueBrass),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Both free',
                  style: textTheme.titleMedium?.copyWith(color: light),
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Thursday at 12:00 PM',
            style: textTheme.bodyMedium?.copyWith(color: light),
            maxLines: 1,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const BrassGlyph(BrassGlyphKind.pin, size: 16, color: AppColors.antiqueBrass),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Halfway between you',
                  style: textTheme.bodySmall?.copyWith(color: light.withValues(alpha: 0.85)),
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

/// Two trellises side by side — one flourishing, one weary — the community's
/// health as a leader sees it: a season, never a day. Laid out at its natural
/// size; the slide scales it to fit.
class _CommunityHealthArt extends StatelessWidget {
  const _CommunityHealthArt();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget vine(TrellisState state, double reveal, String label) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrellisVisual(state: state, reveal: reveal, height: 118),
            const SizedBox(height: 6),
            Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.antiqueBrass,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        vine(TrellisState.flourishing, 1, 'FLOURISHING'),
        const SizedBox(width: 36),
        vine(TrellisState.struggling, 0.45, 'WEARY'),
      ],
    );
  }
}
