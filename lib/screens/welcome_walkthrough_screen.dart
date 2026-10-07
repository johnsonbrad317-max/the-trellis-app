import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import '../theme/app_colors.dart';
import '../widgets/bookplate_app_bar.dart';
import '../widgets/bookplate_dialog.dart' show BookplateButton, BookplateButtonVariant;
import '../widgets/brass_glyph.dart';
import '../widgets/cloud_access_code_dialog.dart';
import '../widgets/nav_icon.dart';
import '../widgets/trellis_scaffold.dart';
import '../widgets/trimmed_asset.dart';
import '../widgets/vine_frame.dart';
import 'first_run.dart';

/// The picture at the top of a welcome slide.
enum WelcomeArt {
  /// A vellum card bearing the Rule of Life book — the Word that opens the
  /// deck.
  ruleCard,

  /// One or two real screens of the app (see [WelcomeSlide.screenshots]).
  screenshots,

  /// No picture: the slide's brass-marked lines ([WelcomeSlide.lines]) are
  /// the art.
  lines,

  /// The three roles to choose from (the last slide).
  roleChoice,
}

/// One brass-marked line, for a slide that lists rather than explains.
class WelcomeLine {
  const WelcomeLine(this.glyph, this.text);

  final BrassGlyphKind glyph;
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
    this.screenshots = const [],
    this.lines = const [],
    this.isScripture = false,
  });

  /// The brass small-caps line above the headline, e.g. "THE RUNNER".
  final String kicker;
  final String headline;
  final WelcomeArt art;
  final String? body;

  /// Asset paths of real screens (assets/images/welcome/), drawn in phone
  /// frames. Regenerate them with test/render_welcome_screens_test.dart when
  /// the screens change.
  final List<String> screenshots;
  final List<WelcomeLine> lines;

  /// Set in italics, as a quotation.
  final bool isScripture;
}

/// The deck, in order: the race, then each part of the app as it really
/// looks, what it costs, and where to start.
const List<WelcomeSlide> welcomeSlides = [
  WelcomeSlide(
    kicker: 'THE RACE',
    headline: 'Let us throw off everything that hinders…',
    art: WelcomeArt.ruleCard,
    isScripture: true,
    body:
        '…and the sin that so easily entangles. And let us run with perseverance the race '
        'marked out for us, fixing our eyes on Jesus, the pioneer and perfecter of faith. '
        '— Hebrews 12:1–2',
  ),
  WelcomeSlide(
    kicker: 'THE RUNNER',
    headline: 'Create a Rule of Life for this season.',
    art: WelcomeArt.screenshots,
    screenshots: ['assets/images/welcome/runner_rule.png'],
    body:
        'Pick a Rule made for your season — rhythms to put on, sins to throw off, your '
        "church's DNA Rhythms — or build your own. Each morning, a yes or no for yesterday.",
  ),
  WelcomeSlide(
    kicker: 'THE WITNESS',
    headline: 'Walk alongside a Runner.',
    art: WelcomeArt.screenshots,
    screenshots: ['assets/images/welcome/witness_rule.png'],
    body:
        'See how each Runner you walk with is keeping their Rule. When they stumble or go '
        "quiet you'll know, with a text of encouragement or a check-in one tap away.",
  ),
  WelcomeSlide(
    kicker: 'PRAYER',
    headline: 'Keep a living prayer list.',
    art: WelcomeArt.screenshots,
    screenshots: ['assets/images/welcome/prayer_cards.png'],
    body:
        'Runners and Witnesses each keep a prayer list. Pray through it card by card, watch '
        'it grow, and let someone know with a tap that you prayed for them.',
  ),
  WelcomeSlide(
    kicker: 'CONNECT',
    headline: 'Find the time to meet.',
    art: WelcomeArt.screenshots,
    screenshots: ['assets/images/welcome/connect_times.png'],
    body:
        "Choose coffee, lunch or everyday life. See times you're both free and a spot "
        'halfway between you — change anything you like.',
  ),
  WelcomeSlide(
    kicker: 'THE CLOUD',
    headline: 'See the whole flock.',
    art: WelcomeArt.screenshots,
    screenshots: [
      'assets/images/welcome/cloud_roster.png',
      'assets/images/welcome/cloud_insights.png',
    ],
    body:
        'Leaders see who is discipling whom and how the community is growing — in summary, '
        "never anyone's daily answers or prayers.",
  ),
  WelcomeSlide(
    kicker: 'WHAT IT COSTS',
    headline: 'Two weeks free. No card needed.',
    art: WelcomeArt.lines,
    lines: [
      WelcomeLine(
        BrassGlyphKind.leaf,
        'Every new account gets two weeks free to build a Rule of Life and try being a '
        'Runner — no credit card required.',
      ),
      WelcomeLine(
        BrassGlyphKind.check,
        'After that, Runners continue with a \$12-a-year subscription in the App Store, a '
        'code from their church or organization, or a code someone gifted them at '
        'unhinderedlives.com.',
      ),
      WelcomeLine(BrassGlyphKind.heart, 'Witnesses always use The Trellis free.'),
      WelcomeLine(
        BrassGlyphKind.people,
        'Churches and organizations buy seats at unhinderedlives.com/trellis.',
      ),
    ],
  ),
  WelcomeSlide(
    kicker: 'BEGIN',
    headline: 'Start your journey.',
    art: WelcomeArt.roleChoice,
    body:
        'One person can be a Runner, a Witness and a Cloud leader — you can switch any time '
        'from the top of the screen. Where would you like to start?',
  ),
];

/// The welcome walkthrough: the race (Hebrews 12), then each part of the app
/// as it really looks, what it costs, and where to start.
///
/// First run ([firstRun] true — shown after sign-up and on an account's first
/// sign-in): Skip in the app bar, and the last slide asks how to start —
/// Runner, Witness or Cloud — and goes straight into that role's first step
/// (see [startJourney]). From the menu ([firstRun] false) it is a reference:
/// the last slide just reads Done. Either way the deck is recorded as seen.
class WelcomeWalkthroughScreen extends StatefulWidget {
  const WelcomeWalkthroughScreen({super.key, required this.profile, this.firstRun = true});

  final RunnerProfile profile;
  final bool firstRun;

  @override
  State<WelcomeWalkthroughScreen> createState() => _WelcomeWalkthroughScreenState();
}

class _WelcomeWalkthroughScreenState extends State<WelcomeWalkthroughScreen> {
  bool _finished = false;

  RunnerProfile get _profile => widget.profile;

  void _markSeen() {
    // Best-effort and never throws; nothing waits on the write.
    unawaited(_profile.markWelcomeSeen());
  }

  /// Skip (first run), Done (menu), or the system back gesture.
  void _finish() {
    if (_finished) return;
    _finished = true;
    _markSeen();
    if (widget.firstRun) {
      enterApp(Navigator.of(context), _profile);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _start(UserRole role) async {
    if (_finished) return;
    if (role == UserRole.cloud && _profile.cloudAdminChurchId == null) {
      // The code dialog offers Unlock, See Preview or Cancel; only a real
      // unlock leaves the deck.
      final unlocked = await unlockCloud(context, _profile);
      if (!unlocked || !mounted) return;
    }
    _finished = true;
    _markSeen();
    startJourney(Navigator.of(context), _profile, role);
  }

  @override
  Widget build(BuildContext context) {
    return WelcomeWalkthroughView(
      firstRun: widget.firstRun,
      onFinished: _finish,
      onRoleChosen: _start,
    );
  }
}

/// Everything on the welcome screen except the profile: the app bar (with
/// Skip on a first run), the slides, the dots and the Next button.
/// [onFinished] fires on Skip, Done, or the system back gesture on a first
/// run; [onRoleChosen] when a role is picked on the last slide (first run
/// only). Split from [WelcomeWalkthroughScreen] so it can be pumped in a test
/// without a [RunnerProfile].
class WelcomeWalkthroughView extends StatefulWidget {
  const WelcomeWalkthroughView({
    super.key,
    required this.firstRun,
    required this.onFinished,
    this.onRoleChosen,
  });

  final bool firstRun;
  final VoidCallback onFinished;
  final ValueChanged<UserRole>? onRoleChosen;

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
    final chrome =
        VineFrame.topBand(context) +
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
    // On a first run the last slide's own role buttons are the way forward.
    final showPrimary = !(isLast && widget.firstRun);
    final deckHeight = _deckHeight(context);

    return PopScope(
      // On a first run the only ways out are Skip and a role: a back gesture
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
                            child: WelcomeSlideView(
                              welcomeSlides[i],
                              onRoleChosen: widget.firstRun ? widget.onRoleChosen : null,
                            ),
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
                                  color: _page == i
                                      ? AppColors.forestGreen
                                      : AppColors.vellumBorder,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // The button keeps its height on the last first-run slide
                  // (invisible there), so the slide doesn't jump as it arrives.
                  Visibility(
                    visible: showPrimary,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: BookplateButton(
                      key: const ValueKey('welcome-primary'),
                      label: isLast ? 'Done' : 'Next',
                      onPressed: showPrimary ? _next : null,
                    ),
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
/// headline and words — which scroll inside the plate if the screen or text
/// size leaves them no other room, so nothing ever overflows.
class WelcomeSlideView extends StatelessWidget {
  const WelcomeSlideView(this.slide, {super.key, this.onRoleChosen});

  final WelcomeSlide slide;

  /// Set on the last slide of a first run: the role buttons call it. Null
  /// (from the menu) shows the slide's words only.
  final ValueChanged<UserRole>? onRoleChosen;

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
            final plateHeight = constraints.maxHeight;
            // Screens are the point of their slides and get most of the
            // plate; a book or a list needs less.
            final share = switch (slide.art) {
              WelcomeArt.screenshots => plateHeight < 420 ? 0.46 : 0.56,
              WelcomeArt.ruleCard => plateHeight < 340 ? 0.30 : 0.38,
              WelcomeArt.lines || WelcomeArt.roleChoice => 0.0,
            };
            final artHeight = share == 0 ? 0.0 : (plateHeight * share).clamp(80.0, 380.0);
            final kickerText = Text(
              slide.kicker,
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.antiqueBrass,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (artHeight > 0) ...[
                  SizedBox(
                    height: artHeight,
                    child: Center(child: _art(artHeight)),
                  ),
                  const SizedBox(height: 12),
                ] else
                  const SizedBox(height: 6),
                // With a picture the kicker sits under it; without one it moves
                // into the centred words below.
                if (artHeight > 0) ...[kickerText, const SizedBox(height: 6)],
                // The headline scrolls with the words: on a small phone at a
                // large text size a long headline can run to four lines, and
                // fixed in place it pushed the words off the plate.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, area) => SingleChildScrollView(
                      child: ConstrainedBox(
                        // A slide with no picture sits in the middle of its
                        // plate rather than leaving the bottom half empty.
                        constraints: BoxConstraints(minHeight: artHeight > 0 ? 0 : area.maxHeight),
                        child: Column(
                          mainAxisAlignment: artHeight > 0
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (artHeight == 0) ...[kickerText, const SizedBox(height: 6)],
                            Text(
                              slide.headline,
                              style: textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            if (slide.body != null)
                              Text(
                                slide.body!,
                                style: slide.isScripture
                                    ? bodyStyle?.copyWith(fontStyle: FontStyle.italic)
                                    : bodyStyle,
                                textAlign: TextAlign.center,
                                textScaler: _bodyScaler(context, slide.body!),
                              ),
                            for (var i = 0; i < slide.lines.length; i++) ...[
                              SizedBox(height: i == 0 ? 6 : 14),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: BrassGlyph(
                                      slide.lines[i].glyph,
                                      size: 20,
                                      color: AppColors.antiqueBrass,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(slide.lines[i].text, style: bodyStyle)),
                                ],
                              ),
                            ],
                            if (slide.art == WelcomeArt.roleChoice && onRoleChosen != null) ...[
                              const SizedBox(height: 16),
                              for (final choice in _roleChoices) ...[
                                _RoleChoice(
                                  choice: choice,
                                  onTap: () => onRoleChosen!(choice.role),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ],
                        ),
                      ),
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

  Widget _art(double height) => switch (slide.art) {
    WelcomeArt.ruleCard => _VellumCard(
      child: TrimmedAsset(
        asset: NavGlyph.rule.asset,
        imageSize: NavGlyph.rule.imageSize,
        content: NavGlyph.rule.content,
        height: height * 0.7,
        cacheWidth: 900,
      ),
    ),
    WelcomeArt.screenshots => _Screenshots(assets: slide.screenshots, height: height),
    WelcomeArt.lines || WelcomeArt.roleChoice => const SizedBox.shrink(),
  };
}

/// A role on the last slide: its woodcut, its name and what starting there
/// does first.
class _RoleChoiceData {
  const _RoleChoiceData(this.role, this.title, this.action);

  final UserRole role;
  final String title;
  final String action;
}

const _roleChoices = [
  _RoleChoiceData(UserRole.runner, 'Runner', 'Create my Rule of Life'),
  _RoleChoiceData(UserRole.witness, 'Witness', 'Enter the pairing key my Runner shared'),
  _RoleChoiceData(UserRole.cloud, 'Cloud', "Enter my church or organization's access code"),
];

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({required this.choice, required this.onTap});

  final _RoleChoiceData choice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final role = choice.role;
    return Semantics(
      button: true,
      label: 'Start as a ${choice.title}: ${choice.action}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('welcome-role-${role.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(
            color: AppColors.parchmentLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 48,
                child: TrimmedAsset(
                  asset: role.cardArtAsset,
                  imageSize: role.cardArtSize,
                  content: role.cardArtContent,
                  height: 48,
                  cacheWidth: 400,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(choice.title, style: textTheme.titleMedium),
                    Text(choice.action, style: textTheme.bodySmall),
                  ],
                ),
              ),
              const BrassGlyph(BrassGlyphKind.forward, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// One real screen in a phone-like frame, or two side by side, slightly
/// overlapped, when a part of the app is best shown by two screens.
class _Screenshots extends StatelessWidget {
  const _Screenshots({required this.assets, required this.height});

  final List<String> assets;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final count = assets.length;
        // As tall as the slide allows, but never wider than the plate.
        final widthEach = (constraints.maxWidth - gap * (count - 1)) / count;
        final shotHeight = math.min(height, widthEach / _PhoneShot.aspect);
        return SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                _PhoneShot(asset: assets[i], height: shotHeight),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A screenshot (390 × 620 logical, the top of a phone screen) behind glass:
/// rounded corners, a brass hairline and a soft shadow, sized by height.
class _PhoneShot extends StatelessWidget {
  const _PhoneShot({required this.asset, required this.height});

  final String asset;
  final double height;

  static const double aspect = 390 / 620;

  @override
  Widget build(BuildContext context) {
    final width = height * aspect;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.antiqueBrass, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        cacheWidth: 600,
        // A missing screenshot leaves a quiet parchment frame, never an error.
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
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

/// Asks for the church or organization's Cloud access code. The dialog also
/// offers See Preview (a sample Cloud for a church of 300, closed with Exit —
/// which comes back here, to the deck) and Cancel. True only once Cloud access
/// is really unlocked.
Future<bool> unlockCloud(BuildContext context, RunnerProfile profile) async =>
    await showCloudAccessCodeDialog(context, profile) == CloudAccessResult.unlocked;
