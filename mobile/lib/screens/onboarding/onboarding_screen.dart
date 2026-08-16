import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/media_item.dart';
import '../../services/collections_prefs_service.dart';
import '../../services/locale_service.dart';
import '../../services/log_theme_service.dart';
import '../../services/media_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/interest_picker.dart';
import '../../widgets/poster_tile.dart';
import '../../widgets/share_sheet.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../import/import_screen.dart';
import '../../services/app_translations.dart';

/// Shown exactly once, right after a brand-new account is created (see
/// AppState.justRegistered). Nine steps, all living in one continuous
/// "evening falling" visual world (a dark, star-scattered canvas with warm
/// light as the throughline) rather than nine separate form screens:
/// a quiet opening, a short illustrated tour of what teamira actually does,
/// title language, the logging ritual (same choice as Settings, just
/// surfaced up front, now presented as three little "worlds" that tint the
/// whole screen when previewed), what Collections should lead with (same
/// choice, same CollectionsPrefsService, as the picker in the Collections
/// tab), a few favorite films (so "for you" on Home has something to work
/// with from minute one), a short reassurance, a one-line "plan" that types
/// itself out from those same two earlier choices — and once it finishes,
/// can settle into a small shareable card built from that exact sentence
/// plus the favorites just picked, rather than a separate summary bolted
/// on afterward — and finally an offer to bring over a watch history from
/// Letterboxd or elsewhere. Every step but
/// the first can go forward (skip) or back to the one before it — there's
/// just no way back out to register/login from here, only forward into
/// the app.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  int _page = 0;
  // Started the instant onboarding opens — see _PosterDeckLoader below —
  // rather than only once the features-tour step (now the last one)
  // actually mounts. By the time someone reaches it they've been through
  // every other step first, so the fetch has had that whole span as a
  // head start instead of a few hundred milliseconds.
  final _PosterDeckLoader _deckLoader = _PosterDeckLoader();
  // Filled in by _FavoritesStep as picks happen — read once, at share
  // time, by _PlanRevealStep's card (see _PlanCard below). A notifier
  // rather than a plain field so _FavoritesStep can hand picks up
  // without _PlanRevealStep needing to rebuild every time one changes —
  // it only reads .value once, when the card is actually shared.
  final ValueNotifier<List<MediaItem>> _favoritesPicked = ValueNotifier(const []);
  // Only set while a transition is in flight — the outgoing step, kept
  // alive just long enough to animate off. Cleared the instant the
  // spring settles so idle frames render a single, cheap layer.
  int? _previousPage;
  bool _forward = true;
  static const _pageCount = 9;

  // Built once so switching steps never rebuilds their internal state —
  // only the per-page transform below changes on every frame.
  late final List<Widget> _steps = [
    _WelcomeStep(onNext: () {
      _fireConfetti();
      _next();
    }),
    // Second step, right after Welcome. Its poster fan is real search
    // results (see _PosterDeckLoader above) — but the fetch is started
    // from _deckLoader.start() in initState, the instant onboarding
    // opens, not when this step mounts. So even sitting this early,
    // the network calls already have a beat of head start by the time
    // anyone actually reaches it, rather than starting from zero right
    // as the step appears.
    _FeaturesTourStep(onNext: _next, deckLoader: _deckLoader),
    _LanguageStep(onNext: _next),
    _RitualStep(onNext: () {
      _fireConfetti();
      _next();
    }),
    _InterestsStep(onNext: _next),
    _FavoritesStep(onNext: _next, onPicked: (items) => _favoritesPicked.value = items),
    _MotivationStep(onNext: _next),
    // New 8th step: reads back the interests and ritual picked a few
    // steps ago (CollectionsPrefsService / LogThemeService — nothing
    // new is stored here) and types them out as one sentence. Sits
    // right before Import so the last thing anyone sees before "bring
    // your history over" is a concrete little proof that the app was
    // actually listening. Once the sentence finishes, it can also
    // settle into a small shareable card (_PlanCard) built from exactly
    // the same read-back — interests, ritual, favorites, language —
    // rather than a separate summary invented from scratch.
    _PlanRevealStep(onNext: _next, favorites: _favoritesPicked),
    ImportScreen(embedded: true, onDone: _next),
  ];

  // Every page-to-page move is driven by one physically-simulated spring
  // rather than a fixed-duration curve. A curve always takes the same
  // time and always arrives dead-stopped; a spring's speed responds to
  // how far it still has to travel and settles with a real, felt give
  // instead of snapping to rest — that's the difference between motion
  // that looks "played" and motion that feels handled. The ratio sits
  // clearly under 1 (underdamped) so the incoming step overshoots by a
  // visible hair and settles back, rather than just stopping short.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 210,
    ratio: 0.78,
  );

  // Starts unsettled (0.0) on purpose: the very first step now plays the
  // same entrance every later step gets, drifting and blooming into
  // place instead of appearing fully-formed. That first beat is the one
  // most likely to land — it's the only moment nobody has to tap
  // anything to see.
  late final AnimationController _transition = AnimationController.unbounded(vsync: this, value: 0)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && _previousPage != null) {
        setState(() => _previousPage = null);
      }
    });

  // The very last beat of the flow: instead of the final button just
  // calling widget.onFinished() and cutting straight to the real app in
  // a single frame, the whole night sky floods with warm light first —
  // see _playFinale and _FinaleFloodPainter below. onFinished() fires
  // mid-flood, once the colour has fully covered the screen, so the
  // widget-tree swap in app.dart's _AuthGate happens while there's
  // nothing visible to cut between — then the flood fades back out on
  // its own, and what's revealed underneath is Home, not this screen.
  // _AuthGate's own AnimatedSwitcher picks up right where this leaves
  // off with a matching soft cross-fade, so the two effects read as one
  // continuous reveal rather than two separate animations landing back
  // to back.
  bool _finishing = false;
  bool _finishCalled = false; // guards onFinished() firing exactly once
  late final AnimationController _finale = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  )..addListener(() {
      if (!_finishCalled && _finale.value >= 0.6) {
        _finishCalled = true;
        widget.onFinished();
      }
    });

  // A gentler, shorter motion for the small chrome around the steps
  // (dots, back button) — deliberately quicker than the spring so the
  // frame settles a beat before the content does, instead of every
  // element arriving at once.
  static const _chromeDuration = Duration(milliseconds: 320);
  static const _chromeCurve = Curves.easeOutCubic;

  // The base tone of the whole flow — deep, warm, near-night rather than
  // flat black, so it still reads as "evening" and not "dark mode".
  static const _nightColor = Color(0xFF241A22);

  // A single overlay, stacked above everything else, that any step can
  // fire a burst of colour into for a genuine "moment" — first tap,
  // choosing a ritual world, arriving at the reassurance step. Kept as
  // one shared instance rather than one per step so bursts never stack
  // or fight each other.
  final GlobalKey<_ConfettiOverlayState> _confettiKey = GlobalKey<_ConfettiOverlayState>();
  void _fireConfetti() {
    HapticFeedback.mediumImpact();
    _confettiKey.currentState?.burst();
  }

  void _goTo(int target) {
    if (target < 0 || target >= _pageCount || target == _page) return;
    HapticFeedback.selectionClick();
    setState(() {
      _forward = target > _page;
      _previousPage = _page;
      _page = target;
    });
    _transition.value = 0;
    _transition.animateWith(SpringSimulation(_spring, 0, 1, 0));
    // Arriving at the reassurance step is its own small "you made it
    // this far" moment — worth a burst even though nothing was tapped
    // to get here.
    if (target == 6) _fireConfetti();
  }

  void _next() {
    if (_page >= _pageCount - 1) {
      _playFinale();
      return;
    }
    // Page 7 is _PlanRevealStep — since _TearTicketAction replaced its
    // plain "continue" button, this is now only ever reached by
    // actually tearing the ticket, so the burst reads as the payoff for
    // that specific gesture rather than a generic "next step" flourish.
    if (_page == 7) _fireConfetti();
    _goTo(_page + 1);
  }

  void _back() => _goTo(_page - 1);

  void _playFinale() {
    if (_finishing) return;
    HapticFeedback.heavyImpact();
    setState(() => _finishing = true);
    _finale.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    // Kick off the opening entrance right away — no tap required. A
    // post-frame callback so the very first frame paints the resting
    // starfield before the step blooms in on top of it, rather than the
    // whole screen materializing mid-motion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _transition.animateWith(SpringSimulation(_spring, 0, 1, 0));
    });
    try {
      _deckLoader.start(context.read<AppState>().media);
      debugPrint('[_PosterDeckLoader] start() called');
    } catch (e, st) {
      debugPrint('[_PosterDeckLoader] start() itself threw: $e');
      debugPrint('$st');
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    _finale.dispose();
    _deckLoader.dispose();
    _favoritesPicked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _nightColor,
      body: Stack(
        children: [
          // Slow-drifting colour behind the stars — the same palette used
          // everywhere else in the app (coral, periwinkle, mustard, pink,
          // sage), blurred into soft anchored blobs that bleed into one
          // another over ~20 seconds. This is what keeps all eight steps
          // feeling like one lively, saturated evening instead of one
          // flat dark background with occasional bright accents on top.
          const Positioned.fill(child: _AuroraBackdrop()),
          // A faint, slowly twinkling scatter of stars behind every step —
          // costs no new art, and it's what ties eight very different
          // screens (a wordmark, a search grid, a breathing wave...) into
          // one continuous night sky instead of eight separate
          // backgrounds that happen to be dark.
          const Positioned.fill(child: _StarfieldBackdrop()),
          // Every so often, something actually moves across the whole
          // sky rather than just twinkling in place — a comet with a
          // fading tail, gone in under a second. Rare on purpose: if it
          // happened often it would stop reading as a surprise.
          const Positioned.fill(child: _ShootingStarBackdrop()),
          // The whole journey, drawn in the sky. Eight stars in a gentle
          // arc across the upper part of every step — one lights up and
          // connects to the last as you arrive at each new step, so
          // progress isn't just the little dots in the header, it's the
          // night itself slowly filling in with a constellation. Sits
          // above the ambient starfield but below step content, so it
          // reads as part of the sky rather than UI chrome — the same
          // "this world is one continuous evening" idea as the aurora
          // and starfield above, just one that visibly remembers how far
          // you've come.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _finale,
              // _finale sits at 0 for the ~two minutes someone's actually
              // moving through the flow, so this costs nothing until the
              // very last button press — see _playFinale.
              builder: (context, _) => _ConstellationBackdrop(
                page: _page,
                pageCount: _pageCount,
                finalePulse: (_finale.value / 0.4).clamp(0.0, 1.0),
              ),
            ),
          ),
          // Tap any empty patch of sky and it notices — a small burst of
          // motes blooms right under your finger. Sits below the actual
          // step content in this stack so buttons and the carousels keep
          // first claim on every tap; this only ever catches taps that
          // land on bare background, never one meant for a button.
          Positioned.fill(
            child: Builder(
              builder: (skyContext) => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) {
                  final box = skyContext.findRenderObject() as RenderBox?;
                  if (box == null || box.size.width <= 0 || box.size.height <= 0) return;
                  final fraction = Offset(
                    details.localPosition.dx / box.size.width,
                    details.localPosition.dy / box.size.height,
                  );
                  HapticFeedback.selectionClick();
                  _confettiKey.currentState?.sparkle(fraction);
                },
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < _pageCount; i++)
                            AnimatedContainer(
                              duration: _chromeDuration,
                              curve: _chromeCurve,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _page ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _page ? SeenlyPalette.paper : Colors.white.withOpacity(0.22),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
                      ),
                      // Always present so it can fade in/out smoothly
                      // instead of popping in the moment page 1 is
                      // reached — an abrupt appearance was the one
                      // jarring beat left in an otherwise calm header.
                      Positioned(
                        left: 4,
                        child: IgnorePointer(
                          ignoring: _page == 0,
                          child: AnimatedOpacity(
                            opacity: _page > 0 ? 1 : 0,
                            duration: _chromeDuration,
                            curve: _chromeCurve,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.arrow_back, size: 18, color: Colors.white70),
                              onPressed: _back,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: Stack(
                      children: [
                        AnimatedBuilder(
                          animation: _transition,
                          builder: (context, _) {
                            // `raw` is allowed to run past 1 — that's the
                            // spring's brief overshoot, and it's what
                            // gives the incoming step its real "settle"
                            // instead of a hard stop. `settled` is the
                            // same progress clamped to a legal opacity
                            // value for the outgoing step, which only
                            // ever fades out, never past fully gone.
                            final raw = _transition.value;
                            final settled = raw.clamp(0.0, 1.0).toDouble();
                            final dir = _forward ? 1.0 : -1.0;

                            Widget layer(int index, Widget child, {required bool incoming}) {
                              final t = incoming ? raw : settled;
                              final opacity =
                                  (incoming ? settled : 1 - settled).clamp(0.0, 1.0).toDouble();
                              final slide = incoming ? (1 - t) * 54 * dir : -settled * 60 * dir;
                              final scale = incoming ? 1 - 0.08 * (1 - t) : 1 - 0.08 * settled;
                              // A faint page-turn tilt around the vertical
                              // axis — barely there, but it's what tips
                              // this from "sliding" to "arriving with
                              // depth." Perspective entry keeps it subtle
                              // rather than a full 3D card flip.
                              final tilt = incoming ? (1 - t) * -0.05 * dir : settled * 0.045 * dir;

                              final content = Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.0012)
                                  ..rotateY(tilt),
                                child: Transform.translate(
                                  offset: Offset(slide, 0),
                                  child: Transform.scale(scale: scale, child: child),
                                ),
                              );
                              return Opacity(key: ValueKey(index), opacity: opacity, child: content);
                            }

                            return Stack(
                              children: [
                                if (_previousPage != null)
                                  IgnorePointer(
                                    child:
                                        layer(_previousPage!, _steps[_previousPage!], incoming: false),
                                  ),
                                layer(_page, _steps[_page], incoming: true),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Above absolutely everything, including the header — a burst
          // needs to read against any step's content or the ritual
          // step's own colour-shifting background.
          Positioned.fill(child: _ConfettiOverlay(key: _confettiKey)),
          // Above even the confetti — the last thing anyone sees of this
          // screen at all. Only ever built while _finishing, so it costs
          // nothing for the other ~two minutes someone spends here.
          if (_finishing)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _finale,
                  builder: (context, _) => CustomPaint(
                    painter: _FinaleFloodPainter(t: _finale.value),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The flood that closes the whole flow. Rises from the bottom of the
// screen like warm light spilling in — rather than a flat fade-to-white
// — fully covering everything by t=0.6 (the exact instant
// _OnboardingScreenState calls widget.onFinished(), see _finale above),
// then softens back out over the remaining life of the animation to
// reveal Home underneath. A quiet radial glow at the point the light
// first breaks in gives it one focal point instead of reading as a
// generic wipe.
// ---------------------------------------------------------------------
class _FinaleFloodPainter extends CustomPainter {
  final double t; // 0..1 over _finale's whole life
  const _FinaleFloodPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // Rising phase: 0 -> 0.6. Fading-out phase: 0.6 -> 1.
    final riseT = (t / 0.6).clamp(0.0, 1.0);
    final fadeT = t <= 0.6 ? 0.0 : ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    final coverage = Curves.easeInCubic.transform(riseT);
    final opacity = 1.0 - Curves.easeOutCubic.transform(fadeT);
    if (opacity <= 0) return;

    final rect = Offset.zero & size;
    final floodTop = size.height * (1 - coverage);
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        SeenlyPalette.mustard.withOpacity(opacity),
        SeenlyPalette.coral.withOpacity(opacity * 0.92),
        SeenlyPalette.paper.withOpacity(opacity * 0.88),
      ],
    );
    final floodRect = Rect.fromLTRB(0, floodTop - 40, size.width, size.height);
    final paint = Paint()..shader = gradient.createShader(floodRect);
    canvas.drawRect(rect, paint);

    // A soft blurred seam right at the leading edge, so the flood reads
    // as light spilling upward rather than a hard-edged panel sliding
    // into place.
    if (riseT < 1.0) {
      final seamPaint = Paint()
        ..color = SeenlyPalette.paper.withOpacity(opacity * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36);
      canvas.drawRect(Rect.fromLTWH(0, floodTop - 6, size.width, 12), seamPaint);
    }

    // One focal bloom, roughly where the final button sits, brightest
    // right as the flood finishes covering the screen.
    final bloomT = (riseT).clamp(0.0, 1.0);
    final bloomOpacity = (math.sin(math.pi * bloomT.clamp(0.0, 1.0)) * opacity).clamp(0.0, 1.0);
    if (bloomOpacity > 0) {
      final bloomCenter = Offset(size.width * 0.5, size.height * 0.72);
      final bloomPaint = Paint()
        ..color = SeenlyPalette.paper.withOpacity(bloomOpacity * 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
      canvas.drawCircle(bloomCenter, 120 + 40 * bloomT, bloomPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FinaleFloodPainter oldDelegate) => oldDelegate.t != t;
}

// ---------------------------------------------------------------------
// A page that breathes as it's swiped rather than cutting in at full
// strength — used by every internal carousel (the features tour, the
// logging-ritual worlds) so swiping through them feels like the same
// soft, considered motion as moving between onboarding steps, not a
// second, cheaper-feeling paging widget bolted on inside one.
// ---------------------------------------------------------------------
// ---------------------------------------------------------------------
// A coverflow-style page: the neighbours peek in at the edges (the
// PageController driving this is given a viewportFraction under 1) and
// visibly turn away in 3D as they lose the center, rather than just
// shrinking flat. That peek is the point — it reads as a shelf of
// things to browse the instant it appears, before a single drag.
// ---------------------------------------------------------------------
class _CarouselPage extends StatelessWidget {
  final PageController controller;
  final int index;
  final Widget child;
  const _CarouselPage({required this.controller, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        double page = index.toDouble();
        if (controller.hasClients) {
          try {
            page = controller.page ?? controller.initialPage.toDouble();
          } catch (_) {
            // Not attached to a single position yet (e.g. first frame) —
            // fall back to a settled, fully-visible state.
          }
        }
        final delta = (page - index).clamp(-1.0, 1.0);
        final proximity = 1 - delta.abs(); // 1 when centered, 0 a page away
        // Neighbours stay dimly, visibly present rather than fading to
        // nothing — with a peeking viewport there's always a sliver of
        // them on screen, so vanishing would read as a glitch, not
        // restraint.
        final opacity = 0.32 + 0.68 * proximity;
        final scale = 0.78 + 0.22 * proximity;
        final tilt = -delta * 0.58; // radians — a shallow, believable turn
        final lift = delta.abs() * 10; // neighbours sit a hair lower
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, lift),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0018)
                ..rotateY(tilt)
                ..scale(scale),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Shared "night sky" pieces — a starfield backdrop, a soft warm glow that
// breathes, and a single spark that drifts slowly around a center point.
// Every step below is built out of these same three ingredients plus
// typography, so the whole flow reads as one visual language rather than
// eight separately-invented looks.
// ---------------------------------------------------------------------

/// Four soft, blurred blobs of colour anchored near the corners, drifting
/// gently and cross-fading between palette hues over roughly 20 seconds.
/// Sits behind the starfield so it never competes with it for attention —
/// it's ambient colour, not a shape to look at directly — but it's the
/// single biggest reason the flow now reads as saturated and alive rather
/// than a dark screen with occasional bright accents.
class _AuroraBackdrop extends StatefulWidget {
  const _AuroraBackdrop();

  @override
  State<_AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<_AuroraBackdrop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 22))..repeat();

  static const _blobColors = [
    SeenlyPalette.coral,
    SeenlyPalette.periwinkle,
    SeenlyPalette.mustard,
    SeenlyPalette.pink,
    SeenlyPalette.sage,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _AuroraPainter(t: _controller.value, colors: _blobColors),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  const _AuroraPainter({required this.t, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final anchors = [
      Offset(size.width * 0.16, size.height * 0.14),
      Offset(size.width * 0.88, size.height * 0.20),
      Offset(size.width * 0.22, size.height * 0.84),
      Offset(size.width * 0.84, size.height * 0.88),
    ];
    for (int i = 0; i < anchors.length; i++) {
      final phase = (t + i / anchors.length) % 1.0;
      final colorA = colors[i % colors.length];
      final colorB = colors[(i + 1) % colors.length];
      final mix = math.sin(phase * 2 * math.pi) * 0.5 + 0.5;
      final color = Color.lerp(colorA, colorB, mix)!;
      final drift = Offset(
        math.sin((t + i) * 2 * math.pi) * 20,
        math.cos((t + i * 1.3) * 2 * math.pi) * 16,
      );
      final paint = Paint()
        ..color = color.withOpacity(0.17)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70);
      canvas.drawCircle(anchors[i] + drift, size.shortestSide * 0.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => oldDelegate.t != t;
}

/// A single comet that streaks across the sky at random, irregular
/// intervals — not on a fixed loop, so it never reads as a scheduled
/// animation, and never more than one in flight at a time so it stays a
/// small surprise rather than a recurring effect competing with the rest
/// of the screen.
class _ShootingStarBackdrop extends StatefulWidget {
  const _ShootingStarBackdrop();

  @override
  State<_ShootingStarBackdrop> createState() => _ShootingStarBackdropState();
}

class _ShootingStarBackdropState extends State<_ShootingStarBackdrop> with SingleTickerProviderStateMixin {
  static const _flightDuration = Duration(milliseconds: 850);
  final _rnd = math.Random();

  late final AnimationController _controller = AnimationController(vsync: this, duration: _flightDuration);
  Timer? _scheduleTimer;

  // Chosen fresh for every flight: a start point near one edge, an end
  // point diagonally opposite-ish, and a fixed tilt for the trail.
  Offset _start = Offset.zero;
  Offset _end = Offset.zero;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    final wait = Duration(milliseconds: 6000 + _rnd.nextInt(5000));
    _scheduleTimer = Timer(wait, _fly);
  }

  void _fly() {
    if (!mounted) return;
    // Enters from a top corner, exits lower on the opposite side — a
    // believable falling-star angle rather than a straight horizontal
    // wipe.
    final fromLeft = _rnd.nextBool();
    setState(() {
      _start = Offset(fromLeft ? -0.08 : 1.08, 0.02 + _rnd.nextDouble() * 0.22);
      _end = Offset(fromLeft ? 0.55 + _rnd.nextDouble() * 0.35 : 0.10 - _rnd.nextDouble() * 0.35,
          0.42 + _rnd.nextDouble() * 0.3);
    });
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) _scheduleNext();
    });
    // A comet is easy to miss if you're not looking right at the sky —
    // a very light haptic gives it a second, felt channel, the same way
    // the header dots already confirm a step change by touch.
    HapticFeedback.selectionClick();
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ShootingStarPainter(t: _controller.value, start: _start, end: _end),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ShootingStarPainter extends CustomPainter {
  final double t; // 0..1 over one flight
  final Offset start;
  final Offset end;
  const _ShootingStarPainter({required this.t, required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    // Eases in fast, tails off slowly — a real streak decelerates rather
    // than covering the whole distance at a constant rate.
    final eased = Curves.easeOutCubic.transform(t);
    final head = Offset(
      (start.dx + (end.dx - start.dx) * eased) * size.width,
      (start.dy + (end.dy - start.dy) * eased) * size.height,
    );
    // The tail is simply "a bit earlier" along the same eased path,
    // giving a trail that's longer while the comet is still fast and
    // naturally shortens as it decelerates.
    final tailEased = Curves.easeOutCubic.transform((t - 0.16).clamp(0.0, 1.0));
    final tail = Offset(
      (start.dx + (end.dx - start.dx) * tailEased) * size.width,
      (start.dy + (end.dy - start.dy) * tailEased) * size.height,
    );
    // Fades in over the first tenth, fades out over the last quarter.
    final opacity = t < 0.10 ? t / 0.10 : (t > 0.75 ? (1 - t) / 0.25 : 1.0);
    if (opacity <= 0) return;

    final trailPaint = Paint()
      ..shader = ui.Gradient.linear(tail, head, [
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(0.85 * opacity.clamp(0.0, 1.0)),
      ])
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tail, head, trailPaint);

    final headPaint = Paint()..color = Colors.white.withOpacity(opacity.clamp(0.0, 1.0));
    canvas.drawCircle(head, 1.8, headPaint);
    final glowPaint = Paint()
      ..color = SeenlyPalette.mustard.withOpacity(0.35 * opacity.clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(head, 4, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _ShootingStarPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.start != start || oldDelegate.end != end;
}

// ---------------------------------------------------------------------
// The whole flow's progress, drawn as a constellation instead of a
// progress bar. Eight fixed points in a loose arc across the upper sky;
// as [page] advances, the segment to the newly-reached star draws itself
// in over ~600ms and that star blooms brighter than the rest, while
// everything already passed stays lit at a calmer glow and everything
// still ahead sits as the faintest hint of a point — so glancing at the
// sky at any moment tells you both how far you've come and that there's
// more waiting to be found, without reading as a literal progress meter.
//
// One more beat this same constellation gets: right as the finale's
// flood of light begins (see _playFinale / _finale on
// _OnboardingScreenState), [finalePulse] ramps 0 -> 1 and every star —
// not just the current one — flares and connects at once, the lines
// between them brightening to match. By the last step all eight are
// already lit but sitting calm (progress has caught up to nodeCount, so
// nothing's "current" anymore); this is the one moment the whole shape
// gets to actually shine, right before the flood — which rises from the
// bottom and only reaches this top strip of sky at the very end of its
// rise — washes over it. The last thing visible is the whole night
// someone just built, lit all at once.
// ---------------------------------------------------------------------
class _ConstellationBackdrop extends StatefulWidget {
  final int page;
  final int pageCount;
  final double finalePulse;
  const _ConstellationBackdrop({required this.page, required this.pageCount, this.finalePulse = 0.0});

  @override
  State<_ConstellationBackdrop> createState() => _ConstellationBackdropState();
}

class _ConstellationBackdropState extends State<_ConstellationBackdrop> with SingleTickerProviderStateMixin {
  // A slow, perpetual breathing glow on top of the progress state itself
  // — without it every lit star would sit perfectly static, which reads
  // as UI rather than sky. Independent of page changes on purpose.
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: widget.page.toDouble(), end: widget.page.toDouble()),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return AnimatedBuilder(
          animation: _twinkle,
          builder: (context, __) => CustomPaint(
            painter: _ConstellationPainter(
              progress: progress,
              twinkle: _twinkle.value,
              nodeCount: widget.pageCount,
              finalePulse: widget.finalePulse,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  final double progress; // fractional current step, 0..nodeCount-1
  final double twinkle; // 0..1 ambient pulse, shared by every lit star
  final int nodeCount;
  // 0..1, only nonzero during the finale flood's first ~40% — see
  // _ConstellationBackdrop's doc comment above. Makes every star flare
  // and every line brighten together, regardless of individual progress.
  final double finalePulse;
  const _ConstellationPainter({
    required this.progress,
    required this.twinkle,
    required this.nodeCount,
    this.finalePulse = 0.0,
  });

  // Fractional (0..1, 0..1) positions — a loose, hand-placed arc rather
  // than an evenly-spaced row, so it reads as a found constellation and
  // not a ruler. Kept within the top quarter of the screen, clear of
  // every step's own content and the header's dots/back button.
  static const _nodesFrac = [
    Offset(0.10, 0.13),
    Offset(0.23, 0.07),
    Offset(0.38, 0.11),
    Offset(0.52, 0.05),
    Offset(0.66, 0.10),
    Offset(0.78, 0.06),
    Offset(0.90, 0.14),
    Offset(0.82, 0.22),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final count = math.min(nodeCount, _nodesFrac.length);
    final nodes = [for (int i = 0; i < count; i++) Offset(_nodesFrac[i].dx * size.width, _nodesFrac[i].dy * size.height)];
    final pulse = 0.72 + 0.28 * twinkle;
    final flare = Curves.easeOut.transform(finalePulse.clamp(0.0, 1.0));

    final glowLine = Paint()
      ..color = SeenlyPalette.paper.withOpacity(0.14 + 0.55 * flare)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 + 3.5 * flare
      ..strokeCap = StrokeCap.round;
    final crispLine = Paint()
      ..color = SeenlyPalette.paper.withOpacity(0.45 + 0.5 * flare)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 + 1.3 * flare
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < nodes.length - 1; i++) {
      // During the flare every segment is drawn full regardless of
      // progress — by the time the finale can even fire (see _next(),
      // only reachable once _page is the last page) every segment has
      // already finished connecting on its own anyway, so this only
      // ever matters as a safety net, never as a visible jump.
      final segT = flare > 0 ? 1.0 : (progress - i).clamp(0.0, 1.0);
      if (segT <= 0) continue;
      final a = nodes[i];
      final b = Offset.lerp(nodes[i], nodes[i + 1], segT)!;
      canvas.drawLine(a, b, glowLine);
      canvas.drawLine(a, b, crispLine);
    }

    for (int i = 0; i < nodes.length; i++) {
      final reached = progress >= i - 0.001 || flare > 0;
      if (!reached) {
        final dim = Paint()..color = Colors.white.withOpacity(0.14);
        canvas.drawCircle(nodes[i], 1.6, dim);
        continue;
      }
      final isCurrent = (progress - i).abs() < 0.5 || flare > 0;
      final glowR = (isCurrent ? 11.0 * pulse : 5.0) + 9.0 * flare;
      final glow = Paint()
        ..color = SeenlyPalette.paper.withOpacity(((isCurrent ? 0.4 * pulse : 0.16) + 0.5 * flare).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 + 5 * flare);
      canvas.drawCircle(nodes[i], glowR, glow);
      final core = Paint()..color = SeenlyPalette.paper.withOpacity(((isCurrent ? 0.95 : 0.65) + 0.3 * flare).clamp(0.0, 1.0));
      canvas.drawCircle(nodes[i], (isCurrent ? 2.6 : 1.7) + 1.3 * flare, core);
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.twinkle != twinkle || oldDelegate.finalePulse != finalePulse;
}

class _StarfieldBackdrop extends StatefulWidget {
  const _StarfieldBackdrop();

  @override
  State<_StarfieldBackdrop> createState() => _StarfieldBackdropState();
}

class _StarfieldBackdropState extends State<_StarfieldBackdrop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _StarfieldPainter(t: _controller.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  final double t;
  const _StarfieldPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // Fixed seed so the stars sit still frame to frame — only their
    // twinkle (opacity) moves, never their position.
    final rnd = math.Random(11);
    final paint = Paint()..style = PaintingStyle.fill;
    // Most stars stay plain white; a handful pick up a warm palette tint
    // instead, so the sky itself carries a little of the same colour as
    // the aurora behind it rather than reading as pure monochrome.
    const tints = [SeenlyPalette.mustard, SeenlyPalette.coral, SeenlyPalette.periwinkle, SeenlyPalette.pink];
    for (int i = 0; i < 58; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final r = 0.6 + rnd.nextDouble() * 1.3;
      final phase = rnd.nextDouble();
      final twinkle = 0.14 + 0.58 * (0.5 + 0.5 * math.sin((t + phase) * 2 * math.pi));
      final tinted = i % 7 == 0;
      paint.color = tinted ? tints[i % tints.length].withOpacity(twinkle * 0.9) : Colors.white.withOpacity(twinkle);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) => oldDelegate.t != t;
}

/// A soft warm glow that breathes very slowly — the one recurring "light"
/// motif every step uses, at a different size and color. Built as several
/// stacked, plainly-colored circles of decreasing size and increasing
/// opacity (rather than a single RadialGradient) — a RadialGradient gets
/// hard-clipped exactly at its own circular edge, which reads as a flat
/// disc with a rim; layering soft circles the way a real light source
/// falls off gives a genuinely luminous, slightly hazy core instead,
/// without ever becoming one big flat wash of color.
class _GlowOrb extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;
  const _GlowOrb({required this.size, required this.color, this.duration = const Duration(seconds: 4)});

  @override
  State<_GlowOrb> createState() => _GlowOrbState();
}

class _GlowOrbState extends State<_GlowOrb> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);

  static const _layers = [
    (2.6, 0.05), // widest haze, barely there
    (1.9, 0.10),
    (1.35, 0.20),
    (0.95, 0.38),
    (0.62, 0.62),
    (0.34, 0.92), // small bright core
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = widget.size * 2.6;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(
          scale: 1 + t * 0.06,
          child: SizedBox(
            width: outer,
            height: outer,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final (relSize, baseOpacity) in _layers)
                  Container(
                    width: widget.size * relSize,
                    height: widget.size * relSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withOpacity((baseOpacity + t * 0.06).clamp(0.0, 1.0)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A faint ring marking the path something drifts along — purely a visual
/// cue so a lone spark reads as "orbiting" rather than "floating at a
/// random point," even in a still frame.
class _OrbitRing extends StatelessWidget {
  final double radius;
  final Color color;
  const _OrbitRing({required this.radius, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.14), width: 1),
      ),
    );
  }
}

/// A single small spark drifting in a slow circle around whatever it's
/// centered on, with its own tiny glow and a short fading trail behind
/// it — enough for the motion itself to read clearly, not just imply it.
class _OrbitSpark extends StatefulWidget {
  final double radius;
  final Color color;
  final Duration duration;
  final bool showRing;
  const _OrbitSpark({
    required this.radius,
    required this.color,
    this.duration = const Duration(seconds: 9),
    this.showRing = true,
  });

  @override
  State<_OrbitSpark> createState() => _OrbitSparkState();
}

class _OrbitSparkState extends State<_OrbitSpark> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.showRing) _OrbitRing(radius: widget.radius, color: widget.color),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                for (final trail in const [0.10, 0.06, 0.0]) _spark(trail),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _spark(double behindBy) {
    final angle = (_controller.value - behindBy) * 2 * math.pi;
    final isLead = behindBy == 0.0;
    final size = isLead ? 6.0 : 3.5;
    return Transform.translate(
      offset: Offset(math.cos(angle) * widget.radius, math.sin(angle) * widget.radius),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(isLead ? 0.95 : 0.3),
        ),
      ),
    );
  }
}

/// The Welcome step's hero, one step further than a passive orbit — this
/// spark can be grabbed. Drag it anywhere around the ring and it follows
/// your finger exactly; let go and it springs back onto the live orbit
/// from wherever you released it, picking up speed again rather than
/// snapping straight back. The only interactive element on a step with
/// no carousel to compete with, so a real drag gesture here never risks
/// stealing a swipe meant for a PageView on a later step.
class _DraggableOrbitHero extends StatefulWidget {
  const _DraggableOrbitHero();

  @override
  State<_DraggableOrbitHero> createState() => _DraggableOrbitHeroState();
}

class _DraggableOrbitHeroState extends State<_DraggableOrbitHero> with TickerProviderStateMixin {
  static const _radius = 74.0;
  static const _size = Size(190, 190);

  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 11))
    ..repeat();
  late final AnimationController _return = AnimationController(vsync: this, duration: const Duration(milliseconds: 550))
    ..addListener(() {
      if (mounted) setState(() {});
    });

  // Non-null only while a finger is actively moving the spark; the
  // moment it's released this goes back to null and `_returning` takes
  // over instead.
  double? _dragAngle;
  bool _returning = false;
  double _releaseAngle = 0;

  double get _autoAngle => _spin.value * 2 * math.pi;

  @override
  void dispose() {
    _spin.dispose();
    _return.dispose();
    super.dispose();
  }

  Offset get _center => Offset(_size.width / 2, _size.height / 2);

  double _angleFor(Offset local) {
    final v = local - _center;
    return math.atan2(v.dy, v.dx);
  }

  // Shortest signed distance from `from` to `to` around the circle, so
  // the spring-back always takes the near way round rather than
  // occasionally doing an almost-full lap because of how radians wrap.
  double _shortestDelta(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return d;
  }

  void _onPanStart(DragStartDetails d) {
    HapticFeedback.selectionClick();
    setState(() {
      _returning = false;
      _dragAngle = _angleFor(d.localPosition);
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _dragAngle = _angleFor(d.localPosition));
  }

  void _onPanEnd(DragEndDetails d) {
    _releaseAngle = _dragAngle ?? _autoAngle;
    setState(() {
      _dragAngle = null;
      _returning = true;
    });
    HapticFeedback.lightImpact();
    _return.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _returning = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final held = _dragAngle != null;
    return SizedBox(
      width: _size.width,
      height: _size.height,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _return]),
          builder: (context, _) {
            double angle;
            if (_dragAngle != null) {
              angle = _dragAngle!;
            } else if (_returning) {
              final t = Curves.easeOutBack.transform(_return.value);
              angle = _releaseAngle + _shortestDelta(_releaseAngle, _autoAngle) * t;
            } else {
              angle = _autoAngle;
            }
            final pos = Offset(math.cos(angle) * _radius, math.sin(angle) * _radius);
            return Stack(
              alignment: Alignment.center,
              children: [
                const _OrbitRing(radius: _radius, color: SeenlyPalette.paper),
                Transform.translate(
                  offset: const Offset(-22, 0),
                  child: const _GlowOrb(size: 84, color: SeenlyPalette.coral, duration: Duration(seconds: 4)),
                ),
                Transform.translate(
                  offset: const Offset(20, 6),
                  child: const _GlowOrb(size: 64, color: SeenlyPalette.mustard, duration: Duration(seconds: 5)),
                ),
                Transform.translate(
                  offset: pos,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    width: held ? 11 : 6,
                    height: held ? 11 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SeenlyPalette.paper.withOpacity(held ? 1.0 : 0.95),
                      boxShadow: held
                          ? [BoxShadow(color: SeenlyPalette.paper.withOpacity(0.5), blurRadius: 10, spreadRadius: 1)]
                          : null,
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

/// Wraps a subtree in a slow, smoothed offset driven by the device's own
/// tilt, and hands that offset to [builder] so different children inside
/// can react to it by different amounts — see _WelcomeStep, the only
/// place this is used, where the hero orbit drifts further than the
/// wordmark below it for a real sense of depth rather than everything
/// panning together as one flat layer.
///
/// Reads the accelerometer's gravity component (`event.x`/`event.y`)
/// rather than the raw gyroscope. A gyroscope reports angular
/// *velocity*, not absolute tilt — turning that into a steady "how far
/// is the phone leaning right now" number means integrating it and
/// correcting for drift, real machinery for what's meant to be one
/// quiet touch on a single screen. The accelerometer's gravity vector
/// gives that absolute lean directly, no drift to correct — the
/// trade-off is it also picks up genuine linear acceleration (someone
/// briskly lifting the phone), which the exponential smoothing below
/// absorbs anyway, since it's tuned for a slow lean, not a jolt.
///
/// Only ever mounted while the Welcome step itself is — _steps only
/// ever keeps the current (and briefly outgoing) step in the tree, see
/// the `layer()` helper in _OnboardingScreenState.build() — so the
/// sensor subscription starts the instant someone lands here and stops
/// the instant they move on, entirely for free via this State's own
/// initState/dispose.
class _TiltParallax extends StatefulWidget {
  final Widget Function(BuildContext context, Offset tilt) builder;
  const _TiltParallax({required this.builder});

  @override
  State<_TiltParallax> createState() => _TiltParallaxState();
}

class _TiltParallaxState extends State<_TiltParallax> {
  // Smoothed, clamped to roughly -1..1 on each axis. Exponential moving
  // average rather than the raw sample — accelerometer readings are
  // noisy enough moment to moment that using them directly would read
  // as a jitter, not a drift.
  Offset _tilt = Offset.zero;
  StreamSubscription<AccelerometerEvent>? _sub;

  @override
  void initState() {
    super.initState();
    try {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen(_onEvent, onError: (_) {/* no accelerometer on this device — hero just stays put */});
    } catch (_) {
      // Same fallback as onError above, just for the synchronous case
      // (some platforms throw right away rather than erroring the
      // stream) — either way this is a purely decorative touch, never
      // worth surfacing as a real failure.
    }
  }

  void _onEvent(AccelerometerEvent event) {
    if (!mounted) return;
    // ~9.8 m/s^2 is one full "g" — dividing by it turns "how hard is
    // gravity pulling on this axis" into a roughly -1..1 lean, clamped
    // in case of a genuine shake rather than a lean.
    final targetX = (event.x / 9.8).clamp(-1.0, 1.0);
    final targetY = (event.y / 9.8).clamp(-1.0, 1.0);
    setState(() {
      _tilt = Offset(
        _tilt.dx + (targetX - _tilt.dx) * 0.12,
        _tilt.dy + (targetY - _tilt.dy) * 0.12,
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _tilt);
}

/// The small ghost circle used to step back through an inner carousel
/// (features tour, ritual worlds) — distinct from the header's own back
/// button, which steps back through the *outer* onboarding flow instead.
class _DarkBackCircle extends StatelessWidget {
  final VoidCallback? onTap;
  const _DarkBackCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: onTap == null ? 0.25 : 1,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.22)),
          ),
          child: const Icon(Icons.chevron_left, size: 20, color: Colors.white70),
        ),
      ),
    );
  }
}

/// A row of small dots marking position within an *inner* carousel
/// (features tour, ritual worlds) — visually lighter than the header's
/// own eight-step dots so the two don't get confused for one another.
class _InnerDots extends StatelessWidget {
  final int count;
  final int index;
  const _InnerDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? SeenlyPalette.paper : Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Step 1 — opening
// ---------------------------------------------------------------------

class _WelcomeStep extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomeStep({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _TiltParallax(
      builder: (context, tilt) {
        return Stack(
          children: [
            Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 190,
                child: Center(
                  // The nearest layer — moves the most, so tilting the
                  // phone reads as looking *around* the orbit rather
                  // than the whole screen just sliding as one flat image.
                  child: Transform.translate(
                    offset: Offset(tilt.dx * 16, tilt.dy * 10),
                    child: const _DraggableOrbitHero(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 10, 28, 24),
              child: Column(
                children: [
                  const Spacer(flex: 5),
                  // The furthest layer — same direction as the hero
                  // above, just a fraction of the distance, so the two
                  // visibly move at different speeds instead of together.
                  Transform.translate(
                    offset: Offset(tilt.dx * 5, tilt.dy * 3),
                    child: const _AssemblingWordmark(text: 'teamira'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'a cozy evening diary for what you watch — not a tracker dashboard, not a leaderboard. just a quiet place to remember the evenings.'.tr,
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(size: 14, color: Colors.white.withOpacity(0.62)),
                  ),
                  const Spacer(flex: 3),
                  PrimaryButton(label: "let's go", onTap: onNext),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The very first thing anyone sees of the whole app. Rather than the
/// wordmark simply appearing intact, each letter starts scattered like
/// a handful of loose stars pulled from the sky behind it and drifts
/// into place with a slight overshoot-and-settle, one beat after its
/// neighbour rather than all landing at once. A soft warm bloom breathes
/// in behind the finished word right as the last letter locks — as if
/// this were the one thing the whole night sky had been assembling
/// toward.
class _AssemblingWordmark extends StatefulWidget {
  final String text;
  const _AssemblingWordmark({required this.text});

  @override
  State<_AssemblingWordmark> createState() => _AssemblingWordmarkState();
}

class _AssemblingWordmarkState extends State<_AssemblingWordmark> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 900 + widget.text.length * 90),
  );

  // Fixed per-letter scatter, hand-picked rather than Random() — the
  // same letter drifts in from the same direction on every launch
  // instead of reshuffling and reading as noise rather than intent.
  static const _scatter = [
    Offset(-30, -22),
    Offset(26, -30),
    Offset(-38, 18),
    Offset(34, 24),
    Offset(-22, -34),
    Offset(30, 14),
    Offset(-30, -14),
    Offset(20, -20),
  ];

  @override
  void initState() {
    super.initState();
    // A post-frame callback rather than starting immediately — this
    // step's own entrance (the outer spring in OnboardingScreen) is
    // already animating it into view; letting one frame pass first
    // means the assembly begins once the step has actually arrived,
    // not mid-flight while it's still sliding in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letters = widget.text.split('');
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final bloom = (Curves.easeOut.transform(_controller.value) * 0.55).clamp(0.0, 0.55);
        return Stack(
          alignment: Alignment.center,
          children: [
            IgnorePointer(
              child: Opacity(
                opacity: bloom,
                child: Container(
                  width: 170,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [SeenlyPalette.mustard.withOpacity(0.5), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (int i = 0; i < letters.length; i++) _buildLetter(i, letters[i])],
            ),
          ],
        );
      },
    );
  }

  Widget _buildLetter(int i, String ch) {
    final start = (i * 0.07).clamp(0.0, 0.7);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0), curve: Curves.easeOutBack),
    ).value; // can dip slightly below 0 before start and overshoot past 1 on settle
    final settle = curved.clamp(0.0, 1.0);
    final drift = (1 - curved).clamp(0.0, 1.0);
    final scatter = _scatter[i % _scatter.length];
    return Opacity(
      opacity: settle,
      child: Transform.translate(
        offset: scatter * drift,
        child: Transform.scale(
          scale: 0.4 + 0.6 * curved.clamp(0.0, 1.3),
          child: Text(ch, style: SeenlyText.serif(size: 32, weight: FontWeight.w600, color: SeenlyPalette.paper)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Step 2 — a short illustrated tour of what teamira does, replacing the
// old "would you like a rabbit companion?" step entirely. An inner
// carousel of four cards, each its own small scene, swipeable but never
// blocking — "continue" always works from any card.
// ---------------------------------------------------------------------

class _FeatureCard {
  final String tag;
  final String title;
  final String text;
  final Color color;
  final Color color2;
  const _FeatureCard({
    required this.tag,
    required this.title,
    required this.text,
    required this.color,
    required this.color2,
  });
}

const _kFeatures = [
  _FeatureCard(
    tag: 'collections',
    title: 'shelves built around you',
    text: 'collections leads with whatever you\'re into, from day one — '
        'change what it leads with anytime.',
    color: SeenlyPalette.sage,
    color2: SeenlyPalette.mustard,
  ),
  _FeatureCard(
    tag: 'for you',
    title: 'something for tonight',
    text: 'home learns from what you\'ve watched and loved, and ask '
        'teamira helps when you can\'t decide.',
    color: SeenlyPalette.mustard,
    color2: SeenlyPalette.coral,
  ),
  _FeatureCard(
    tag: 'together',
    title: 'watch it together',
    text: 'pair up with a partner or friends, vote on what\'s next, and '
        'keep a shared thread of evenings.',
    color: SeenlyPalette.periwinkle,
    color2: SeenlyPalette.periwinkle,
  ),
  // Deliberately last: its art is the live poster deck rather than the
  // abstract glow/dot illustrations every other card uses (see
  // _FeatureCardView.build / _PosterDeckArt below), and that deck is
  // fetched over the network. Being the last card in this carousel
  // means someone has already swiped through three other cards before
  // reaching it, on top of the deck having had this whole step's worth
  // of onboarding as a head start already (see _PosterDeckLoader) — by
  // far the best odds of the posters actually being in by the time it's
  // seen.
  _FeatureCard(
    tag: 'diary',
    title: 'log an evening, your way',
    text: 'movies, shows, books, games, manga — one diary for all of it, '
        'with a little ritual to close it out.',
    color: SeenlyPalette.coral,
    color2: SeenlyPalette.mustard,
  ),
];

// A poster pulled from the real search behind Favorites/Collections — the
// "diary" card's whole point is to make "movies, shows, books, games,
// manga — one diary for all of it" something you can actually *see*
// rather than read, so it borrows real cover art instead of drawing more
// abstract dots like every other card here.
class _DeckPoster {
  final String title;
  final String? posterUrl;
  final String mediaType;
  const _DeckPoster({required this.title, required this.posterUrl, required this.mediaType});
}

// Picked for being instantly recognisable worldwide, not for taste — the
// deck's job is "oh, I know that one", which is what sells "thousands of
// movies and series" faster than the words ever could.
const _kDeckPrimaryQueries = [
  'Dune',
  'Stranger Things',
  'Spider-Man',
  'Breaking Bad',
  'Inception',
  'The Last of Us',
];

// (media type, query) — fetched alongside the primary titles now (see
// _PosterDeckLoader._load), then held back from view for a 260ms beat
// by _FeatureCardViewState so "movies and series" still reads first and
// "and it's not just that" lands as its own small reveal. Weighted
// toward games since that's the type people are least likely to expect
// from a watch-diary app, so it's the one worth showing off most.
const _kDeckSecondaryQueries = [
  ('game', 'The Legend of Zelda'),
  ('game', 'The Witcher 3'),
  ('game', 'Minecraft'),
  ('game', 'God of War'),
  ('book', 'Harry Potter'),
  ('book', 'The Hobbit'),
  ('manga', 'Attack on Titan'),
  ('manga', 'One Piece'),
];

// (media type, query) — the "collections" card's own shelf, deliberately
// picked to span very different tastes (classic drama, a novel, anime,
// a game, manga, a prestige comedy) so the row itself sells "shelves
// built around you" — whatever you're into, this is that shelf. null
// type means a plain title search, same as the primary deck above.
const _kShelfQueries = [
  (null, 'The Godfather'),
  ('book', 'Pride and Prejudice'),
  (null, 'Your Name'),
  ('game', 'Elden Ring'),
  ('manga', 'Death Note'),
  (null, 'Fleabag'),
];

// The "together" card's head-to-head pair — deliberately two hugely
// different, both hugely popular titles (real "which one tonight"
// energy) rather than two similar ones, so the contrast itself sells
// "vote on what's next" at a glance.
const _kTogetherQueries = [
  'Oppenheimer',
  'Barbie',
];

// (media type, query) — the "for you" card's own little recommendation
// stack, deliberately mixed media again (a film, a show, a game, a
// manga) so the same "movies, shows, books, games, manga" idea keeps
// showing up in real covers rather than only being said once up front.
const _kForYouQueries = [
  (null, 'Everything Everywhere All at Once'),
  (null, 'The Bear'),
  ('game', 'Hades'),
  ('manga', 'Chainsaw Man'),
];

// Tiny counting semaphore — caps how many `_PosterDeckLoader` fetches run
// concurrently (see its `_gate` field) without giving up the "each result
// streams in on its own" behavior: callers still just `await acquire()`
// then `release()` in a `finally`, no batching/Future.wait involved.
class _Semaphore {
  _Semaphore(this._maxConcurrent);
  final int _maxConcurrent;
  int _active = 0;
  final List<Completer<void>> _waiting = [];

  Future<void> acquire() {
    if (_active < _maxConcurrent) {
      _active++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}

// Owns the poster-deck fetch independently of whether the features-tour
// step is even on screen yet. Created once by _OnboardingScreenState and
// started the moment onboarding opens, so by the time someone actually
// swipes to that step (now the last one) the search results — or at
// least most of them — are already sitting here waiting, instead of the
// step starting from zero and racing the user's next tap.
class _PosterDeckLoader extends ChangeNotifier {
  List<_DeckPoster> primaryDeck = const [];
  List<_DeckPoster> secondaryDeck = const [];
  List<_DeckPoster> shelfDeck = const [];
  List<_DeckPoster> togetherDeck = const [];
  List<_DeckPoster> forYouDeck = const [];

  bool _started = false;
  bool _disposed = false;

  // All five query groups below used to fire every request at once — 26
  // in total. Each one lands on GET /media/search, which (for a book/
  // manga hit) can itself fan out up to 24 *more* concurrent requests to
  // Open Library for the ru-text overlay — Open Library's own docs cap
  // an unidentified caller at ~1 req/sec, so that alone was enough to
  // 429 the whole burst. The blanket concurrency on this side made every
  // downstream limit (the DB connection pool, TMDB, Open Library) visible
  // at once. Routing every fetch through one small semaphore keeps the
  // "each poster pops in the moment its own search resolves" feel (still
  // no Future.wait, still no batching) while capping how many of those
  // searches are ever in flight together — gentle on every backend limit
  // instead of just the first one that happens to break.
  final _gate = _Semaphore(6);

  Future<_DeckPoster?> _fetchOne(
    MediaService media,
    String query, {
    bool games = false,
    bool books = false,
    bool manga = false,
    String? preferType,
  }) async {
    await _gate.acquire();
    try {
      final results = await media.search(
        query,
        includeGames: games,
        includeBooks: books,
        includeManga: manga,
      );
      if (results.isEmpty) {
        debugPrint('[_PosterDeckLoader] "$query" returned zero results');
        return null;
      }
      final item = preferType == null
          ? results.first
          : results.firstWhere((m) => m.mediaType == preferType, orElse: () => results.first);
      final poster = item.posterUrl;
      if (poster == null || poster.isEmpty) {
        debugPrint('[_PosterDeckLoader] "$query" matched "${item.title.display}" but has no poster');
        return null;
      }
      return _DeckPoster(title: item.title.display, posterUrl: poster, mediaType: item.mediaType);
    } catch (e, st) {
      // No connection yet, or the search failed — the card just keeps
      // its quieter fallback art, but log it so a totally-empty deck is
      // debuggable instead of silently looking like "nothing happened".
      debugPrint('[_PosterDeckLoader] "$query" threw: $e');
      debugPrint('$st');
      return null;
    } finally {
      _gate.release();
    }
  }

  // Idempotent — onboarding only ever calls this once (from initState),
  // but guarding here means nothing gets fetched twice if that ever
  // changes.
  void start(MediaService media) {
    if (_started) return;
    _started = true;
    _load(media);
  }

  Future<void> _load(MediaService media) async {
    // Fired independently rather than behind one Future.wait — a batch
    // wait is only as fast as its slowest single request, so one slow
    // title used to hold back every card that was already back. Each
    // poster now lands the moment its own search resolves, which is
    // what actually made the deck feel slow to appear before.
    //
    // Queued onto `_gate` in the same order the person actually swipes
    // through this step's cards — collections (shelf) first, then for
    // you, then together, and primary/secondary (which only back the
    // last "diary" card) last. `_gate` is FIFO, so whichever group is
    // enqueued first also clears first: with only a handful of requests
    // in flight at once (see `_gate`'s own doc comment for why), firing
    // primary/secondary first used to mean the *last*-seen card's art
    // finished first while collections — the very first card someone
    // actually swipes to — sat queued behind 14 requests it didn't need
    // at all. This ordering fixes that without changing the cap itself.
    for (final q in _kShelfQueries) {
      _fetchOne(
        media,
        q.$2,
        games: q.$1 == 'game',
        books: q.$1 == 'book',
        manga: q.$1 == 'manga',
        preferType: q.$1,
      ).then((poster) {
        if (poster == null || _disposed) return;
        shelfDeck = [...shelfDeck, poster];
        notifyListeners();
      });
    }
    for (final q in _kForYouQueries) {
      _fetchOne(
        media,
        q.$2,
        games: q.$1 == 'game',
        books: q.$1 == 'book',
        manga: q.$1 == 'manga',
        preferType: q.$1,
      ).then((poster) {
        if (poster == null || _disposed) return;
        forYouDeck = [...forYouDeck, poster];
        notifyListeners();
      });
    }
    for (final q in _kTogetherQueries) {
      _fetchOne(media, q).then((poster) {
        if (poster == null || _disposed) return;
        togetherDeck = [...togetherDeck, poster];
        notifyListeners();
      });
    }
    for (final q in _kDeckPrimaryQueries) {
      _fetchOne(media, q).then((poster) {
        if (poster == null || _disposed) return;
        primaryDeck = [...primaryDeck, poster];
        notifyListeners();
      });
    }
    for (final q in _kDeckSecondaryQueries) {
      _fetchOne(
        media,
        q.$2,
        games: q.$1 == 'game',
        books: q.$1 == 'book',
        manga: q.$1 == 'manga',
        preferType: q.$1,
      ).then((poster) {
        if (poster == null || _disposed) return;
        secondaryDeck = [...secondaryDeck, poster];
        notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _FeaturesTourStep extends StatefulWidget {
  final VoidCallback onNext;
  final _PosterDeckLoader deckLoader;
  const _FeaturesTourStep({required this.onNext, required this.deckLoader});

  @override
  State<_FeaturesTourStep> createState() => _FeaturesTourStepState();
}

class _FeaturesTourStepState extends State<_FeaturesTourStep> {
  // A touch under full width so the next and previous cards peek in at
  // the edges — the whole point of the coverflow treatment below. Without
  // this every card would fill the screen and there'd be nothing to peek.
  final _controller = PageController(viewportFraction: 0.82);
  int _index = 0;

  void _go(int delta) {
    final next = (_index + delta).clamp(0, _kFeatures.length - 1);
    if (next == _index) return;
    _controller.animateToPage(next, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _kFeatures.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      child: Column(
        children: [
          Text('a quick look around'.tr,
              textAlign: TextAlign.center, style: SeenlyText.serif(size: 16, color: SeenlyPalette.paper)),
          const SizedBox(height: 4),
          Text(
            'swipe through, or just continue — you\'ll find it all later anyway'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(0.42)),
          ),
          const SizedBox(height: 10),
          Expanded(
            // Listens to the loader rather than owning its own state now —
            // it may already have posters waiting the instant this step
            // first builds, and rebuilds here whenever more stream in.
            child: AnimatedBuilder(
              animation: widget.deckLoader,
              builder: (context, _) => PageView.builder(
                controller: _controller,
                itemCount: _kFeatures.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _CarouselPage(
                  controller: _controller,
                  index: i,
                  child: _FeatureCardView(
                    card: _kFeatures[i],
                    slot: i,
                    deckLoader: widget.deckLoader,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _InnerDots(count: _kFeatures.length, index: _index),
          const SizedBox(height: 14),
          PrimaryButton(
            label: isLast ? 'continue' : 'next feature',
            onTap: isLast ? widget.onNext : () => _go(1),
          ),
        ],
      ),
    );
  }
}

class _FeatureCardView extends StatefulWidget {
  final _FeatureCard card;
  final int slot;
  // The whole loader, rather than picking specific lists out ahead of
  // time — different cards read different decks off it (the diary card
  // reads primary/secondary, the collections card reads the shelf), and
  // this way a card that doesn't use any of it just never touches it.
  final _PosterDeckLoader deckLoader;
  const _FeatureCardView({
    required this.card,
    required this.slot,
    required this.deckLoader,
  });

  @override
  State<_FeatureCardView> createState() => _FeatureCardViewState();
}

class _FeatureCardViewState extends State<_FeatureCardView> {
  // Deliberately separate from whether the secondary data has actually
  // arrived (widget.deckLoader.secondaryDeck) — that may well already be
  // sitting in _PosterDeckLoader by the time this card is first seen,
  // since loading starts at onboarding open and this is the last step.
  // Gating on a timer that starts the moment *this card* mounts means
  // the person always gets the same "movies first, then — 260ms later —
  // games, manga, and books too" beat, instead of everything arriving
  // pre-loaded and popping in all at once with no reveal at all. Only
  // the diary card's two-stage deck needs this — the collections shelf
  // below is a single deck with no staged reveal to protect.
  bool _revealSecondary = false;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    _revealTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _revealSecondary = true);
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final loader = widget.deckLoader;
    final primaryDeck = loader.primaryDeck;
    final secondaryDeck = _revealSecondary ? loader.secondaryDeck : const <_DeckPoster>[];
    final useDeck = card.tag == 'diary' && primaryDeck.isNotEmpty;
    final useShelf = card.tag == 'collections' && loader.shelfDeck.isNotEmpty;
    final useVersus = card.tag == 'together' && loader.togetherDeck.length >= 2;
    final useSwipe = card.tag == 'for you' && loader.forYouDeck.length >= 3;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 130,
            child: useDeck
                ? _PosterDeckArt(primary: primaryDeck, secondary: secondaryDeck)
                : useShelf
                    ? _ShelfArt(covers: loader.shelfDeck)
                    : useVersus
                        ? _VersusArt(a: loader.togetherDeck[0], b: loader.togetherDeck[1])
                        : useSwipe
                            ? _SwipeStackArt(posters: loader.forYouDeck)
                            : Stack(alignment: Alignment.center, children: _artFor(card)),
          ),
          const SizedBox(height: 14),
          Container(width: 26, height: 2, color: card.color),
          const SizedBox(height: 10),
          Text(card.tag, style: SeenlyText.mono(size: 9, color: Colors.white.withOpacity(0.48))),
          const SizedBox(height: 4),
          Text(card.title,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 16, weight: FontWeight.w700, color: SeenlyPalette.paper)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: useDeck
                ? _DeckCaption(hasSecondary: secondaryDeck.isNotEmpty)
                : Text(card.text,
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(size: 12, color: Colors.white.withOpacity(0.55))),
          ),
        ],

      ),
    );
  }

  List<Widget> _artFor(_FeatureCard card) {
    // Keyed on the card's tag rather than its position in _kFeatures —
    // the diary card moved to the end of that list (see _kFeatures
    // above) to give its poster deck more time to load, and switching
    // on tag means the fallback art below still finds the right card
    // regardless of where anything sits in the carousel.
    switch (card.tag) {
      case 'diary': // a single glow with one spark circling it
        return [
          _GlowOrb(size: 98, color: card.color),
          const _OrbitSpark(radius: 62, color: SeenlyPalette.paper, duration: Duration(seconds: 5)),
        ];
      case 'collections': // a gentle arc of spines, each one quietly
        // bobbing and breathing on its own stagger, like a tiny shelf
        // that's actually alive rather than a printed illustration of one
        return [
          for (int i = 0; i < 7; i++)
            _BobbingDot(
              offset: Offset((i - 3) * 22.0, -math.sin(i / 6 * math.pi) * 26),
              size: 6.0 + (i % 3) * 4,
              color: (i.isEven ? card.color : card.color2).withOpacity(0.75),
              seed: i,
            ),
        ];
      case 'for you': // a glow with a few motes drawn in toward it,
        // literally: each one drifts a little closer on every breath,
        // the same idea the copy is making ("home learns... draws in")
        return [
          _GlowOrb(size: 82, color: card.color),
          for (final entry in const [Offset(-46, -34), Offset(48, -30), Offset(-38, 32), Offset(42, 30)]
              .asMap()
              .entries)
            _BobbingDot(
              offset: entry.value,
              size: 5,
              color: card.color2.withOpacity(0.8),
              seed: entry.key + 12,
              bobAmplitude: 4,
              approach: 9,
            ),
        ];
      default: // together — two glows with a few small dots actually
        // travelling between them, arcing up and fading at each end, so
        // it reads as messages passing back and forth rather than a
        // static bridge of dots
        return [
          Transform.translate(offset: const Offset(-40, 0), child: _GlowOrb(size: 62, color: card.color)),
          Transform.translate(offset: const Offset(40, 0), child: _GlowOrb(size: 62, color: card.color)),
          for (int i = 0; i < 3; i++) _FlowingDot(seed: i, color: SeenlyPalette.paper),
        ];
    }
  }
}

// ---------------------------------------------------------------------
// The "diary" card's poster deck — a small hand-fan of real covers
// (movies/series first, then games/books/manga peeking out from behind
// a beat later) standing in for the abstract glow-orb every other card
// still uses. Nudge it and it tilts like an actual stack of cards; tap
// any one cover and it pops up on its own. Falls back to the plain art
// automatically whenever the deck comes back empty — see _FeatureCardView.
// ---------------------------------------------------------------------

class _PosterDeckArt extends StatefulWidget {
  final List<_DeckPoster> primary;
  final List<_DeckPoster> secondary;
  const _PosterDeckArt({required this.primary, required this.secondary});

  @override
  State<_PosterDeckArt> createState() => _PosterDeckArtState();
}

class _PosterDeckArtState extends State<_PosterDeckArt> {
  // -1..1, nudged by dragging across the deck — a small whole-deck tilt
  // so the "interactive" part of this isn't only the per-card tap.
  double _rock = 0;

  // Six primary slots, arranged as a wide symmetric fan. Each card
  // handles its own entrance the moment it mounts (see _LiveDeckCard) —
  // since posters now stream in one search result at a time rather than
  // as one all-or-nothing batch, whichever slot fills first is simply
  // whichever title came back first.
  static const _primarySlots = [
    (dx: -88.0, dy: 26.0, angle: -0.40),
    (dx: -54.0, dy: 10.0, angle: -0.26),
    (dx: -18.0, dy: 0.0, angle: -0.09),
    (dx: 18.0, dy: 0.0, angle: 0.09),
    (dx: 54.0, dy: 10.0, angle: 0.26),
    (dx: 88.0, dy: 26.0, angle: 0.40),
  ];
  // Drawn *before* the primary cards below (see build), so at rest these
  // sit tucked behind the fan — tiny corners peeking out — until each
  // one mounts and slides properly into view. Eight slots (up from
  // five) to fit the wider secondary query list above, arranged on the
  // same rise-toward-center arc as before, just with finer steps.
  static const _secondarySlots = [
    (dx: -124.0, dy: -8.0, angle: -0.44),
    (dx: -88.5, dy: -30.5, angle: -0.31),
    (dx: -53.0, dy: -45.5, angle: -0.19),
    (dx: -17.5, dy: -53.0, angle: -0.06),
    (dx: 17.5, dy: -53.0, angle: 0.06),
    (dx: 53.0, dy: -45.5, angle: 0.19),
    (dx: 88.5, dy: -30.5, angle: 0.31),
    (dx: 124.0, dy: -8.0, angle: 0.44),
  ];
  // Center pair drawn last (on top), farthest-out first — a proper
  // shingled fan instead of strict left-to-right stacking.
  static const _primaryDrawOrder = [0, 5, 1, 4, 2, 3];

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary.take(_primarySlots.length).toList();
    final secondary = widget.secondary.take(_secondarySlots.length).toList();
    return GestureDetector(
      onPanUpdate: (d) => setState(() => _rock = (_rock + d.delta.dx / 90).clamp(-1.0, 1.0)),
      onPanEnd: (_) => setState(() => _rock = 0),
      onPanCancel: () => setState(() => _rock = 0),
      child: AnimatedRotation(
        turns: _rock * 0.018,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (int i = 0; i < secondary.length; i++)
              _LiveDeckCard(
                key: ValueKey('sec-${secondary[i].title}-$i'),
                poster: secondary[i],
                width: 36,
                dx: _secondarySlots[i].dx,
                dy: _secondarySlots[i].dy,
                angle: _secondarySlots[i].angle,
                seed: i + 20,
                collapsedStart: true,
              ),
            for (final i in _primaryDrawOrder)
              if (i < primary.length)
                _LiveDeckCard(
                  key: ValueKey('pri-${primary[i].title}-$i'),
                  poster: primary[i],
                  width: 50,
                  dx: _primarySlots[i].dx,
                  dy: _primarySlots[i].dy,
                  angle: _primarySlots[i].angle,
                  seed: i,
                ),
          ],
        ),
      ),
    );
  }
}

/// One cover in the deck: fans/slides into place from a collapsed start
/// the instant it mounts. Posters stream in one at a time (see
/// _PosterDeckLoader above) as each search result comes back, and since
/// loading now starts well before this step is ever shown, most cards
/// mount already-populated and just play their entrance immediately —
/// this still holds for any stragglers that land after. Also idles with
/// a slow independent bob so the
/// deck never sits dead still, and pops up on its own spring the
/// instant it's tapped.
class _LiveDeckCard extends StatefulWidget {
  final _DeckPoster poster;
  final double width;
  final double dx;
  final double dy;
  final double angle;
  final int seed;
  // True for the secondary (games/books/manga) cards, which start
  // pulled in toward center and shrunk down, tucked behind the primary
  // fan, rather than merely invisible in place.
  final bool collapsedStart;
  const _LiveDeckCard({
    super.key,
    required this.poster,
    required this.width,
    required this.dx,
    required this.dy,
    required this.angle,
    required this.seed,
    this.collapsedStart = false,
  });

  @override
  State<_LiveDeckCard> createState() => _LiveDeckCardState();
}

class _LiveDeckCardState extends State<_LiveDeckCard> with TickerProviderStateMixin {
  late final _idle = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 2600 + (widget.seed * 331) % 1400),
  )..repeat(reverse: true);
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

  // Starts hidden and flips true on the very next frame — the implicit
  // animated widgets below only animate a *change*, so this card has to
  // actually paint once in its "closed" state before opening, or it
  // would just appear already in place with no entrance at all. Doing
  // this per-card (rather than once for the whole deck) is what lets
  // each poster pop in the moment it personally arrives.
  bool _show = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _idle.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _onTap() {
    HapticFeedback.selectionClick();
    _pop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final startOffset = widget.collapsedStart
        ? Offset(-widget.dx / 140, -widget.dy / 140)
        : Offset(-widget.dx / 260, (widget.dy - 22) / 220);
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: _show ? 1 : (widget.collapsedStart ? 0.4 : 0.72),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: AnimatedSlide(
          offset: _show ? Offset.zero : startOffset,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: AnimatedBuilder(
            animation: Listenable.merge([_idle, _pop]),
            builder: (context, child) {
              final idleT = Curves.easeInOut.transform(_idle.value);
              final bob = -idleT * 3.0;
              final wobble = (idleT - 0.5) * 0.05;
              final popT = _pop.value;
              final popScale = 1 + math.sin(popT * math.pi) * 0.12;
              final popLift = -math.sin(popT * math.pi) * 10;
              return Transform.translate(
                offset: Offset(widget.dx, widget.dy + bob + popLift),
                child: Transform.rotate(
                  angle: widget.angle + wobble,
                  child: Transform.scale(scale: popScale, child: child),
                ),
              );
            },
            child: GestureDetector(
              onTap: _onTap,
              child: SizedBox(
                width: widget.width,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: PosterTile(
                        title: widget.poster.title,
                        posterUrl: widget.poster.posterUrl,
                        fallbackColor: SeenlyPalette.mediaColor(widget.poster.mediaType),
                        showLabel: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The "collections" card's own live art — a small shelf of real covers
// standing upright on a line, each leaning slightly like an actual
// stack of books/discs rather than sitting perfectly straight. Where
// the diary deck is a fanned-out hand of cards, this is deliberately a
// row, so the two live decks in this tour never read as the same trick
// twice — same idea (real covers instead of abstract art), different
// shape entirely.
// ---------------------------------------------------------------------

class _ShelfArt extends StatelessWidget {
  final List<_DeckPoster> covers;
  const _ShelfArt({required this.covers});

  // A little varied lean per position rather than a single repeated
  // angle — small alternating tilts read as books that have actually
  // been reached past, not a printed pattern.
  static const _leans = [-0.07, 0.05, -0.04, 0.08, -0.06, 0.03];

  @override
  Widget build(BuildContext context) {
    final shown = covers.take(_leans.length).toList();
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // The shelf itself, drawn under the books so only a sliver
        // shows beneath each spine.
        Positioned(
          bottom: 15,
          child: Container(
            width: 210,
            height: 3,
            decoration: BoxDecoration(
              color: SeenlyPalette.paper.withOpacity(0.16),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 17,
          child: SizedBox(
            height: 108,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < shown.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: _ShelfBook(
                      key: ValueKey('shelf-${shown[i].title}-$i'),
                      poster: shown[i],
                      seed: i,
                      lean: _leans[i],
                      // Alternating heights so it reads as a real,
                      // slightly mismatched shelf rather than a uniform
                      // printed row — the same instinct as _DeckCaption
                      // and the diary fan, just applied to a straight
                      // line instead of an arc.
                      height: 92.0 - (i.isOdd ? 10 : 0) - (i % 3 == 0 ? 4 : 0),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One spine on the shelf: rises up from below the shelf line and fades
/// in the instant it mounts, then idles with a slow independent sway —
/// deliberately a different entrance shape from _LiveDeckCard's
/// collapse-toward-center, so the two live decks in this tour feel like
/// two different pieces of craft rather than one animation reused twice.
/// Tapping one gives it a small satisfied bounce, like pulling it an
/// inch off the shelf and letting it settle back.
class _ShelfBook extends StatefulWidget {
  final _DeckPoster poster;
  final int seed;
  final double lean;
  final double height;
  const _ShelfBook({
    super.key,
    required this.poster,
    required this.seed,
    required this.lean,
    required this.height,
  });

  @override
  State<_ShelfBook> createState() => _ShelfBookState();
}

class _ShelfBookState extends State<_ShelfBook> with TickerProviderStateMixin {
  late final _idle = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 3200 + (widget.seed * 401) % 1600),
  )..repeat(reverse: true);
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

  // Same "paint hidden once, then open" trick as _LiveDeckCard — the
  // implicit animated widgets below only animate a change, so this has
  // to render closed on the very first frame or there's no entrance to
  // see at all.
  bool _show = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _idle.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _onTap() {
    HapticFeedback.selectionClick();
    _pop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.height * (2 / 3);
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        // Rises up out of the shelf line rather than sliding in
        // sideways — a book being set upright, not a card being dealt.
        offset: _show ? Offset.zero : const Offset(0, 0.55),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _pop]),
          builder: (context, child) {
            final idleT = Curves.easeInOut.transform(_idle.value);
            final sway = widget.lean + (idleT - 0.5) * 0.035;
            final popT = _pop.value;
            final popLift = -math.sin(popT * math.pi) * 8;
            final popScale = 1 + math.sin(popT * math.pi) * 0.08;
            return Transform.translate(
              offset: Offset(0, popLift),
              child: Transform.rotate(
                angle: sway,
                child: Transform.scale(scale: popScale, alignment: Alignment.bottomCenter, child: child),
              ),
            );
          },
          child: GestureDetector(
            onTap: _onTap,
            child: SizedBox(
              width: width,
              height: widget.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: PosterTile(
                    title: widget.poster.title,
                    posterUrl: widget.poster.posterUrl,
                    fallbackColor: SeenlyPalette.mediaColor(widget.poster.mediaType),
                    showLabel: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The "together" card's live art — two real posters facing off with a
// pulsing "VS" badge between them and a friendly split that drifts back
// and forth on its own. Third shape in the same family as the diary fan
// and the collections shelf (real covers instead of abstract art), but
// head-to-head instead of fanned or shelved — each live deck in this
// tour reads as its own bit of craft, not one trick reused three times.
// ---------------------------------------------------------------------

class _VersusArt extends StatefulWidget {
  final _DeckPoster a;
  final _DeckPoster b;
  const _VersusArt({required this.a, required this.b});

  @override
  State<_VersusArt> createState() => _VersusArtState();
}

class _VersusArtState extends State<_VersusArt> with TickerProviderStateMixin {
  late final _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))..repeat(reverse: true);
  // Loops back and forth forever rather than ever settling on a number —
  // this was never a real tally, just a bit of "the vote's still going"
  // life under the posters.
  late final _tally = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
  late final _badgePop = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  bool _show = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _show = true);
      // The badge pops in a beat after both posters have had time to
      // slide into place, rather than all three landing in one flat
      // instant.
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _badgePop.forward();
    });
  }

  @override
  void dispose() {
    _idle.dispose();
    _tally.dispose();
    _badgePop.dispose();
    super.dispose();
  }

  Widget _poster(_DeckPoster poster, {required bool leftSide}) {
    final startOffset = Offset(leftSide ? -0.55 : 0.55, 0);
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _show ? Offset.zero : startOffset,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: _idle,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_idle.value);
            final lean = (leftSide ? -1 : 1) * (0.05 + t * 0.03);
            final bob = -t * 3;
            return Transform.translate(
              offset: Offset(0, bob),
              child: Transform.rotate(angle: lean, child: child),
            );
          },
          child: SizedBox(
            width: 58,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 6)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PosterTile(
                    title: poster.title,
                    posterUrl: poster.posterUrl,
                    fallbackColor: SeenlyPalette.mediaColor(poster.mediaType),
                    showLabel: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _poster(widget.a, leftSide: true),
                  const SizedBox(width: 30),
                  _poster(widget.b, leftSide: false),
                ],
              ),
              ScaleTransition(
                scale: CurvedAnimation(parent: _badgePop, curve: Curves.easeOutBack),
                child: AnimatedBuilder(
                  animation: _idle,
                  builder: (context, child) {
                    final t = Curves.easeInOut.transform(_idle.value);
                    return Transform.scale(scale: 1 + t * 0.06, child: child);
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _OnboardingScreenState._nightColor,
                      border: Border.all(color: SeenlyPalette.paper.withOpacity(0.75), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text('VS'.tr,
                        style: SeenlyText.mono(size: 10, weight: FontWeight.w700, color: SeenlyPalette.paper)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: _tally,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_tally.value);
            final aPct = (52 + t * 12).round();
            final bPct = 100 - aPct;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$aPct%',
                    style: SeenlyText.mono(size: 10, weight: FontWeight.w700, color: SeenlyPalette.coral)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('·'.tr, style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(0.35))),
                ),
                Text('$bPct%',
                    style: SeenlyText.mono(size: 10, weight: FontWeight.w700, color: SeenlyPalette.periwinkle)),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// The "for you" card's live art — a small stack of real posters that
// takes its own turn every couple seconds: the front card slides off
// like a swiped recommendation, everything behind it steps forward one
// slot, and a fresh one settles in at the back — looping forever
// through the same handful of posters. Fourth shape in the family (fan,
// shelf, head-to-head, now a cycling stack), and the only one that
// keeps moving on its own without being tapped.
// ---------------------------------------------------------------------

class _CardParams {
  final double dx, dy, scale, rotation, opacity;
  const _CardParams({
    required this.dx,
    required this.dy,
    required this.scale,
    required this.rotation,
    required this.opacity,
  });
}

double _lerpD(double a, double b, double t) => a + (b - a) * t;

class _SwipeStackArt extends StatefulWidget {
  final List<_DeckPoster> posters;
  const _SwipeStackArt({required this.posters});

  @override
  State<_SwipeStackArt> createState() => _SwipeStackArtState();
}

class _SwipeStackArtState extends State<_SwipeStackArt> with TickerProviderStateMixin {
  // A working copy we rotate in place each cycle (front moves to the
  // back) — keeping it separate from widget.posters means a late-
  // arriving poster from the loader can't reshuffle a cycle that's
  // already mid-swing.
  late List<_DeckPoster> _order = List.of(widget.posters);
  late final _cycle = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  Timer? _pause;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _show = true);
    });
    _scheduleNext();
  }

  void _scheduleNext() {
    _pause = Timer(const Duration(milliseconds: 2100), () {
      if (!mounted) return;
      _cycle.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _order = [..._order.skip(1), _order.first];
          _cycle.value = 0;
        });
        _scheduleNext();
      });
    });
  }

  @override
  void dispose() {
    _pause?.cancel();
    _cycle.dispose();
    super.dispose();
  }

  // Depth 0 is the front card; each step back sits a little further
  // down-right and a little smaller/dimmer, like a real stack of prints.
  _CardParams _paramsForDepth(double d) {
    return _CardParams(
      dx: d * 13.0,
      dy: d * 7.0,
      scale: (1 - d * 0.09).clamp(0.0, 1.0),
      rotation: d * 0.05,
      opacity: d <= 0 ? 1.0 : (1 - d * 0.24).clamp(0.0, 1.0),
    );
  }

  static const _exitParams = _CardParams(dx: 118, dy: -10, scale: 0.9, rotation: 0.34, opacity: 0);

  @override
  Widget build(BuildContext context) {
    final visible = _order.length.clamp(0, 4);
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedBuilder(
        animation: _cycle,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_cycle.value);
          final children = <Widget>[];
          // Painted back-to-front so the front card ends up on top.
          for (int i = visible - 1; i >= 0; i--) {
            final from = _paramsForDepth(i.toDouble());
            final isExiting = i == 0;
            final to = isExiting ? _exitParams : _paramsForDepth((i - 1).toDouble());
            final dx = _lerpD(from.dx, to.dx, t);
            final dy = _lerpD(from.dy, to.dy, t);
            final scale = _lerpD(from.scale, to.scale, t);
            final rotation = _lerpD(from.rotation, to.rotation, t);
            final opacity = _lerpD(from.opacity, to.opacity, t).clamp(0.0, 1.0);
            final poster = _order[i];
            children.add(
              Transform.translate(
                offset: Offset(dx, dy),
                child: Transform.rotate(
                  angle: rotation,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: SizedBox(
                        width: 66,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5)),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: PosterTile(
                                title: poster.title,
                                posterUrl: poster.posterUrl,
                                fallbackColor: SeenlyPalette.mediaColor(poster.mediaType),
                                showLabel: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return Stack(alignment: Alignment.center, children: children);
        },
      ),
    );
  }
}

/// The two-line pitch under the deck: opens on "thousands of movies and
/// series", then swaps to "and it's not just that" as soon as the first
/// game/book/manga poster actually lands — reactive to the real data
/// rather than a fixed timer, so it can never drift ahead of or lag
/// behind what's on screen.
class _DeckCaption extends StatelessWidget {
  final bool hasSecondary;
  const _DeckCaption({required this.hasSecondary});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: Text(
        hasSecondary
            ? 'and it\'s not just that — games, manga, and books too.'
            : 'choose from thousands of movies and series —',
        key: ValueKey(hasSecondary),
        textAlign: TextAlign.center,
        style: SeenlyText.serif(size: 12, color: Colors.white.withOpacity(0.55)),
      ),
    );
  }
}

/// A small circle that gently bobs and breathes in place, and can
/// optionally drift a little closer to the stack's center on every
/// breath — the shared building block behind every "little scatter of
/// dots" moment in the features tour, so none of them ever sits
/// perfectly still the way a plain Container would.
class _BobbingDot extends StatefulWidget {
  final Offset offset; // base position, relative to the stack's center
  final double size;
  final Color color;
  final int seed; // staggers phase/period so dots never move in lockstep
  final double bobAmplitude;
  final double approach; // px drifted toward center at the peak of each breath, 0 = none
  const _BobbingDot({
    required this.offset,
    required this.size,
    required this.color,
    required this.seed,
    this.bobAmplitude = 6,
    this.approach = 0,
  });

  @override
  State<_BobbingDot> createState() => _BobbingDotState();
}

class _BobbingDotState extends State<_BobbingDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 2400 + (widget.seed * 397) % 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dist = widget.offset.distance;
    final towardCenter = dist == 0 ? Offset.zero : -widget.offset / dist;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final pos = widget.offset + Offset(0, -t * widget.bobAmplitude) + towardCenter * (t * widget.approach);
        final scale = 0.85 + 0.15 * t;
        return Transform.translate(offset: pos, child: Transform.scale(scale: scale, child: child));
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
      ),
    );
  }
}

/// One dot travelling in a slow, looping arc from the left glow to the
/// right one — [seed] staggers its start so three of these read as an
/// unhurried back-and-forth rather than three dots moving in unison.
class _FlowingDot extends StatefulWidget {
  final int seed;
  final Color color;
  const _FlowingDot({required this.seed, required this.color});

  @override
  State<_FlowingDot> createState() => _FlowingDotState();
}

class _FlowingDotState extends State<_FlowingDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value + widget.seed / 3) % 1.0;
        final x = -34 + t * 68;
        final y = math.sin(t * math.pi) * -7; // a shallow arc, not a flat slide
        final fade = t < 0.12 ? t / 0.12 : (t > 0.88 ? (1 - t) / 0.12 : 1.0);
        return Transform.translate(
          offset: Offset(x, y),
          child: Opacity(opacity: fade.clamp(0.0, 1.0), child: child),
        );
      },
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withOpacity(0.7)),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Step 3 — title language. The one step in the flow that used to sit
// outside the "evening" world entirely: a plain heading, a paragraph,
// two static cards. Everything else here earns its place by showing,
// not telling — the sample card below actually retitles itself the
// instant either choice is tapped, so the setting demonstrates its own
// effect before anyone leaves the step, instead of asking for trust
// that "title cards" means something later. Entrance is staggered
// (heading, then copy, then the demo, then the choices) rather than the
// whole block appearing in one frame, matching the small entrance every
// other step already gets from the outer spring transition.
// ---------------------------------------------------------------------

class _LanguageStep extends StatefulWidget {
  final VoidCallback onNext;
  const _LanguageStep({required this.onNext});

  @override
  State<_LanguageStep> createState() => _LanguageStepState();
}

class _LanguageStepState extends State<_LanguageStep> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  void _choose(bool preferRussian) {
    HapticFeedback.selectionClick();
    context.read<LocaleService>().setPreferRussian(preferRussian);
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          _StaggerIn(
            controller: _entrance,
            index: 0,
            child: Text('title language'.tr,
                textAlign: TextAlign.center, style: SeenlyText.serif(size: 18, color: SeenlyPalette.paper)),
          ),
          const SizedBox(height: 6),
          _StaggerIn(
            controller: _entrance,
            index: 1,
            child: Text(
              "teamira's own words stay in English everywhere — this just decides whether title cards prefer Russian when there's a translation for them. change this anytime in settings.".tr,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12, color: Colors.white.withOpacity(0.55)),
            ),
          ),
          const SizedBox(height: 20),
          _StaggerIn(
            controller: _entrance,
            index: 2,
            child: _LiveTitleCard(preferRussian: locale.preferRussian),
          ),
          const SizedBox(height: 20),
          _StaggerIn(
            controller: _entrance,
            index: 3,
            child: Row(
              children: [
                Expanded(
                  child: _ChoiceCard(
                    flag: '🇬🇧',
                    label: 'English',
                    subtitle: 'always available',
                    selected: !locale.preferRussian,
                    onTap: () => _choose(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ChoiceCard(
                    flag: '🇷🇺',
                    label: 'Russian',
                    subtitle: 'when a title has one',
                    selected: locale.preferRussian,
                    onTap: () => _choose(true),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _StaggerIn(controller: _entrance, index: 4, child: PrimaryButton(label: 'continue', onTap: widget.onNext)),
        ],
      ),
    );
  }
}

/// Fades and slides a child up into place using one slice of a shared
/// controller — [index] offsets when that slice starts, so several of
/// these driven by the same controller read as elements arriving one
/// unhurried beat after another rather than all snapping in at once.
/// Generic enough that any step could reach for it, not just this one.
class _StaggerIn extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final Widget child;
  const _StaggerIn({required this.controller, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.1).clamp(0.0, 0.55);
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.45).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, child) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - anim.value) * 14), child: child),
      ),
    );
  }
}

/// A small mock title card — not a real search result, just enough of
/// one to make "title language" concrete. Its title crossfades between
/// the English and Russian sample the instant a choice card is tapped,
/// so this step's whole point is visible rather than described.
class _LiveTitleCard extends StatelessWidget {
  final bool preferRussian;
  const _LiveTitleCard({required this.preferRussian});

  static const _sampleEn = 'Spirited Away';
  static final _sampleRu = 'Унесённые призраками'.tr;
  static const _sampleMeta = '2001 · anime';

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [SeenlyPalette.mustard.withOpacity(0.85), SeenlyPalette.coral.withOpacity(0.85)],
              ),
            ),
            child: const Icon(Icons.movie_creation_outlined, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 340),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      preferRussian ? _sampleRu : _sampleEn,
                      key: ValueKey(preferRussian),
                      style: SeenlyText.serif(size: 15, weight: FontWeight.w600, color: SeenlyPalette.paper),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(_sampleMeta, style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(0.45))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String flag;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.flag,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent.withOpacity(0.22) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SeenlyPalette.accent : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: Column(
          children: [
            Text(flag, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 8),
            Text(label,
                style: SeenlyText.serif(
                  size: 16,
                  weight: FontWeight.w600,
                  color: selected ? SeenlyPalette.paper : Colors.white.withOpacity(0.8),
                )),
            const SizedBox(height: 2),
            Text(subtitle, style: SeenlyText.mono(size: 9, color: Colors.white.withOpacity(0.4))),
            const SizedBox(height: 6),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? SeenlyPalette.accent : Colors.white.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Step 4 — the logging ritual, presented as three little "worlds" you
// swipe between rather than three stacked cards. The whole screen tints
// toward whichever world is centered; "choose this world" both saves the
// pick (through the same LogThemeService Settings uses) and advances.
// ---------------------------------------------------------------------

enum _RitualBadgeType { ticket, train, garden }

class _RitualWorld {
  final _RitualBadgeType type;
  final LogTheme theme;
  final String label;
  final String diary;
  final Color color;
  final Color bg;
  const _RitualWorld({
    required this.type,
    required this.theme,
    required this.label,
    required this.diary,
    required this.color,
    required this.bg,
  });
}

const _kWorlds = [
  _RitualWorld(
    type: _RitualBadgeType.ticket,
    theme: LogTheme.ticket,
    label: 'a ticket, torn open',
    diary: 'your diary becomes a jar, filling up with stubs',
    color: SeenlyPalette.coral,
    bg: Color(0xFF2B1F28),
  ),
  _RitualWorld(
    type: _RitualBadgeType.train,
    theme: LogTheme.coach,
    label: 'an evening route, by train',
    diary: 'your diary becomes a board of journeys taken',
    color: SeenlyPalette.mustard,
    bg: Color(0xFF2A2318),
  ),
  _RitualWorld(
    type: _RitualBadgeType.garden,
    theme: LogTheme.garden,
    label: 'a window garden, in bloom',
    diary: 'your diary becomes a garden, filling in over time',
    color: SeenlyPalette.sage,
    bg: Color(0xFF1E2620),
  ),
];

class _RitualStep extends StatefulWidget {
  final VoidCallback onNext;
  const _RitualStep({required this.onNext});

  @override
  State<_RitualStep> createState() => _RitualStepState();
}

class _RitualStepState extends State<_RitualStep> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    final current = context.read<LogThemeService>().theme;
    final found = _kWorlds.indexWhere((w) => w.theme == current);
    _index = found < 0 ? 0 : found;
    // A touch under full width so neighbouring worlds peek in at the
    // edges, matching the features-tour carousel.
    _controller = PageController(initialPage: _index, viewportFraction: 0.86);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _choose() {
    context.read<LogThemeService>().setTheme(_kWorlds[_index].theme);
    widget.onNext();
  }

  void _go(int delta) {
    final next = (_index + delta) % _kWorlds.length;
    _controller.animateToPage(next, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // The backdrop color now tracks the drag itself rather than only
      // snapping once a page settles — mid-swipe, the screen is already
      // blending between the two worlds you're passing through. That
      // live response is worth far more than any one-off flourish: it
      // makes the whole screen feel like it's actually listening.
      animation: _controller,
      builder: (context, _) {
        double page = _index.toDouble();
        if (_controller.hasClients) {
          try {
            page = _controller.page ?? _index.toDouble();
          } catch (_) {
            // Not attached yet — fall back to the settled index.
          }
        }
        final lower = page.floor().clamp(0, _kWorlds.length - 1).toInt();
        final upper = page.ceil().clamp(0, _kWorlds.length - 1).toInt();
        final frac = (page - page.floor()).clamp(0.0, 1.0).toDouble();
        final bg = Color.lerp(_kWorlds[lower].bg, _kWorlds[upper].bg, frac) ?? _kWorlds[_index].bg;
        return Container(
          color: bg,
          child: Stack(
            children: [
              const Positioned.fill(child: _StarfieldBackdrop()),
              // Full-screen atmosphere for whichever world is centered —
              // confetti scraps drifting down for the ticket, sparks
              // streaming past for the train, fireflies meandering for
              // the garden. The small motif icon above already breathes
              // on its own; this is what makes the *whole screen*, not
              // just a 130px box, feel like that world.
              Positioned.fill(child: _RitualAmbience(world: _kWorlds[_index])),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Column(
                  children: [
                    Text('how should logging feel?'.tr,
                        textAlign: TextAlign.center,
                        style: SeenlyText.serif(size: 16, color: SeenlyPalette.paper)),
                    const SizedBox(height: 4),
                    Text(
                      'same diary either way — just a different little ritual for closing out an evening'.tr,
                      textAlign: TextAlign.center,
                      style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(0.42)),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: _kWorlds.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (context, i) => _CarouselPage(
                          controller: _controller,
                          index: i,
                          child: _RitualWorldView(world: _kWorlds[i]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InnerDots(count: _kWorlds.length, index: _index),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _DarkBackCircle(onTap: () => _go(-1)),
                        const SizedBox(width: 10),
                        Expanded(child: PrimaryButton(label: 'choose this world', onTap: _choose)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Full-screen atmosphere for whichever ritual world is centered — the
/// thing that makes a whole screen feel like "a ticket" or "a train" or
/// "a garden" rather than just the small motif icon in the middle of it.
/// Switches its particle set (and colour) the instant the centered page
/// changes; each set is a handful of independent loops on fixed, hand-
/// staggered timings rather than a spawn/despawn particle system, which
/// keeps it cheap and keeps every particle's path identical (and so
/// unnoticeable as a loop) run after run.
class _RitualAmbience extends StatefulWidget {
  final _RitualWorld world;
  const _RitualAmbience({required this.world});

  @override
  State<_RitualAmbience> createState() => _RitualAmbienceState();
}

class _RitualAmbienceState extends State<_RitualAmbience> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _RitualAmbiencePainter(type: widget.world.type, color: widget.world.color, t: _controller.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _RitualAmbiencePainter extends CustomPainter {
  final _RitualBadgeType type;
  final Color color;
  final double t; // 0..1, looping every 8s

  const _RitualAmbiencePainter({required this.type, required this.color, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case _RitualBadgeType.ticket:
        _paintConfetti(canvas, size);
        break;
      case _RitualBadgeType.train:
        _paintEmbers(canvas, size);
        break;
      case _RitualBadgeType.garden:
        _paintFireflies(canvas, size);
        break;
    }
  }

  // Torn stubs, not generic confetti — small rectangles that flutter
  // (rotation wobbles rather than spinning steadily) as they drift down,
  // like scraps shaken loose from a jar of ticket stubs.
  void _paintConfetti(Canvas canvas, Size size) {
    const count = 14;
    for (int i = 0; i < count; i++) {
      final seed = i * 0.6180339887 % 1.0; // golden-ratio spread, no clustering
      final speed = 0.7 + (i % 5) * 0.09;
      final loopT = (t * speed + seed) % 1.0;
      final x = size.width * ((seed * 1.7) % 1.0);
      final y = -20 + loopT * (size.height + 40);
      final wobble = math.sin((t * 6 + i) * math.pi) * 10;
      final rot = math.sin((t * 3 + i) * math.pi) * 0.5;
      final fade = loopT < 0.08 ? loopT / 0.08 : (loopT > 0.9 ? (1 - loopT) / 0.1 : 1.0);
      final paint = Paint()..color = (i.isEven ? color : SeenlyPalette.paper).withOpacity(0.4 * fade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x + wobble, y);
      canvas.rotate(rot);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-4, -2.5, 8, 5), const Radius.circular(1.5)),
        paint,
      );
      canvas.restore();
    }
  }

  // Sparks streaming past horizontally at a few different depths, plus
  // a couple of soft, slow-rising smoke motes — the window-streak idea
  // from the small motif, escaped out to fill the whole screen.
  void _paintEmbers(Canvas canvas, Size size) {
    const count = 10;
    for (int i = 0; i < count; i++) {
      final row = i % 5;
      final rowY = size.height * (0.12 + row * 0.16);
      final speed = 0.8 + (i % 3) * 0.25;
      final seed = i * 0.382;
      final loopT = (t * speed + seed) % 1.0;
      final x = size.width * 1.15 - loopT * (size.width * 1.3);
      final fade = loopT < 0.1 ? loopT / 0.1 : (loopT > 0.85 ? (1 - loopT) / 0.15 : 1.0);
      final glow = Paint()
        ..color = color.withOpacity(0.5 * fade.clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(x, rowY), 2.2, glow);
      final trail = Paint()
        ..color = SeenlyPalette.paper.withOpacity(0.35 * fade.clamp(0.0, 1.0))
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, rowY), Offset(x + 16, rowY), trail);
    }
    for (int i = 0; i < 3; i++) {
      final loopT = (t * 0.4 + i * 0.33) % 1.0;
      final x = size.width * (0.2 + i * 0.32);
      final y = size.height * (0.85 - loopT * 0.6);
      final fade = math.sin(loopT * math.pi);
      final smoke = Paint()
        ..color = Colors.white.withOpacity(0.05 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawCircle(Offset(x, y), 18 + loopT * 14, smoke);
    }
  }

  // Fireflies — soft glows that meander on a lazy Lissajous-ish path
  // and pulse independently of their own drift, rather than a straight
  // fall or slide, so they read as alive rather than falling debris.
  void _paintFireflies(Canvas canvas, Size size) {
    const count = 11;
    for (int i = 0; i < count; i++) {
      final seed = i * 0.618;
      final cx = size.width * (0.15 + (seed * 1.3) % 0.7);
      final cy = size.height * (0.2 + ((i * 0.41) % 1.0) * 0.55);
      final phase = t * 2 * math.pi + i;
      final x = cx + math.sin(phase * 0.8) * 26;
      final y = cy + math.cos(phase * 0.6) * 20;
      final pulse = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase * 2.3));
      final glow = Paint()
        ..color = color.withOpacity(0.55 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(x, y), 5 * pulse, glow);
      final core = Paint()..color = SeenlyPalette.paper.withOpacity(0.85 * pulse);
      canvas.drawCircle(Offset(x, y), 1.4, core);
    }
  }

  @override
  bool shouldRepaint(covariant _RitualAmbiencePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.type != type || oldDelegate.color != color;
}

class _RitualWorldView extends StatelessWidget {
  final _RitualWorld world;
  const _RitualWorldView({required this.world});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 150, child: Center(child: _artFor(world))),
          const SizedBox(height: 18),
          Text(world.label,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 17, weight: FontWeight.w700, color: SeenlyPalette.paper)),
          const SizedBox(height: 8),
          Text(world.diary,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12, color: Colors.white.withOpacity(0.55))),
        ],
      ),
    );
  }

  Widget _artFor(_RitualWorld world) {
    switch (world.type) {
      case _RitualBadgeType.ticket:
        return _TicketMotif(color: world.color);
      case _RitualBadgeType.train:
        return _TrainMotif(color: world.color);
      case _RitualBadgeType.garden:
        return _GardenMotif(color: world.color);
    }
  }
}

/// A torn-ticket silhouette: a rounded outline with a dashed stub divider.
/// The outline breathes very slowly and the stub's dashes light up one
/// after another like a tiny chase — the same "something here is quietly
/// alive" idea the train's light streaks and the garden's rising motes
/// already carry, so the ticket world doesn't stand out as the one still
/// picture next to two moving ones.
class _TicketMotif extends StatefulWidget {
  final Color color;
  const _TicketMotif({required this.color});

  @override
  State<_TicketMotif> createState() => _TicketMotifState();
}

class _TicketMotifState extends State<_TicketMotif> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final breathe = 0.5 + 0.5 * math.sin(_controller.value * 2 * math.pi);
        return Stack(
          alignment: Alignment.center,
          children: [
            // Used to be a second, larger low-opacity bordered box behind
            // this one — at this size a 9px border on a 132x84 frame
            // reads as a solid card rather than a glow, which is exactly
            // what made this motif look like it was sitting on its own
            // background tile instead of floating on the shared night
            // sky like every other step. A soft shadow around the real
            // ticket shape gets the same "breathing" idea across without
            // ever reading as a rectangle of its own.
            Container(
              width: 112,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.color.withOpacity(0.84 + breathe * 0.12), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.14 + breathe * 0.12),
                    blurRadius: 20 + breathe * 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 34,
              child: SizedBox(
                height: 52,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (i) {
                    final phase = 0.5 + 0.5 * math.sin((_controller.value + i * 0.12) * 2 * math.pi);
                    return Container(width: 2, height: 6, color: widget.color.withOpacity(0.32 + 0.5 * phase));
                  }),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A train-window frame with a few streaks of light passing through it —
/// the only step where the motion itself (not a shape) carries the idea.
class _TrainMotif extends StatefulWidget {
  final Color color;
  const _TrainMotif({required this.color});

  @override
  State<_TrainMotif> createState() => _TrainMotifState();
}

class _TrainMotifState extends State<_TrainMotif> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Same fix as the ticket motif: the second, larger low-opacity
        // bordered box that used to sit behind this one read as a solid
        // background card at this size, not a glow — dropped it in
        // favour of a soft shadow on the real window frame instead.
        Container(
          width: 102,
          height: 76,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.color.withOpacity(0.92), width: 2),
            boxShadow: [
              BoxShadow(color: widget.color.withOpacity(0.20), blurRadius: 22, spreadRadius: 1),
            ],
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Stack(children: [for (int i = 0; i < 3; i++) _streak(i)]),
          ),
        ),
      ],
    );
  }

  Widget _streak(int i) {
    final t = (_controller.value + i * 0.33) % 1.0;
    final dx = 100 - t * 132;
    final opacity = t < 0.1 ? t / 0.1 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
    return Positioned(
      top: 16.0 + i * 20,
      left: dx,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(width: 22, height: 2.5, color: SeenlyPalette.paper.withOpacity(0.85)),
      ),
    );
  }
}

/// A stem growing into a single bud, drawn as two thin strokes (a soft
/// wide pass behind a crisp bright one) rather than a filled illustration
/// — with a couple of tiny motes rising past it like pollen catching
/// the light.
class _GardenMotif extends StatefulWidget {
  final Color color;
  const _GardenMotif({required this.color});

  @override
  State<_GardenMotif> createState() => _GardenMotifState();
}

class _GardenMotifState extends State<_GardenMotif> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 140,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(size: const Size(120, 140), painter: _SproutPainter(color: widget.color)),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Stack(children: [_mote(0.0, -8), _mote(0.35, 10), _mote(0.65, -1)]),
          ),
        ],
      ),
    );
  }

  Widget _mote(double delay, double dx) {
    final t = (_controller.value + delay) % 1.0;
    return Positioned(
      left: 58 + dx,
      bottom: 44 + t * 66,
      child: Opacity(
        opacity: (t < 0.3 ? t / 0.3 : (1 - t) / 0.7).clamp(0.0, 1.0),
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
        ),
      ),
    );
  }
}

class _SproutPainter extends CustomPainter {
  final Color color;
  const _SproutPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stem = Path()
      ..moveTo(size.width / 2, size.height - 8)
      ..cubicTo(
        size.width / 2,
        size.height * 0.6,
        size.width * 0.4,
        size.height * 0.42,
        size.width / 2,
        size.height * 0.26,
      );

    final leaf = Path()
      ..moveTo(size.width / 2, size.height * 0.26)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.20,
        size.width * 0.34,
        size.height * 0.04,
        size.width / 2,
        size.height * -0.02,
      )
      ..cubicTo(
        size.width * 0.66,
        size.height * 0.04,
        size.width * 0.66,
        size.height * 0.20,
        size.width / 2,
        size.height * 0.26,
      )
      ..close();

    canvas.drawPath(stem, Paint()
      ..color = color.withOpacity(0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round);
    canvas.drawPath(stem, Paint()
      ..color = color.withOpacity(0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    canvas.drawPath(leaf, Paint()
      ..color = color.withOpacity(0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7);
    canvas.drawPath(leaf, Paint()
      ..color = color.withOpacity(0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4);
  }

  @override
  bool shouldRepaint(covariant _SproutPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------
// Step 5 — collections interests, now a small constellation you touch
// awake rather than a checklist. Same CollectionsPrefsService underneath.
// ---------------------------------------------------------------------

class _InterestsStep extends StatefulWidget {
  final VoidCallback onNext;
  const _InterestsStep({required this.onNext});

  @override
  State<_InterestsStep> createState() => _InterestsStepState();
}

class _InterestsStepState extends State<_InterestsStep> {
  final _prefs = CollectionsPrefsService();
  final Set<String> _selected = {};
  bool _loaded = false;

  // Fractional (x, y) positions scattered across the available area —
  // enough spread that neighboring stars never overlap even at the
  // larger, selected size.
  static const _positions = [
    Offset(0.16, 0.10),
    Offset(0.64, 0.06),
    Offset(0.86, 0.42),
    Offset(0.58, 0.66),
    Offset(0.14, 0.52),
    Offset(0.34, 0.82),
  ];

  @override
  void initState() {
    super.initState();
    _prefs.loadInterests().then((saved) {
      if (!mounted) return;
      setState(() {
        _selected.addAll(saved);
        _loaded = true;
      });
    });
  }

  void _continue() {
    _prefs.saveInterests(_selected);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        children: [
          Text('touch what feels like you'.tr,
              textAlign: TextAlign.center, style: SeenlyText.serif(size: 16, color: SeenlyPalette.paper)),
          const SizedBox(height: 4),
          Text(
            'collections leads with these from day one — change this anytime from its header'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(0.42)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loaded
                ? LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        for (int i = 0; i < kInterests.length && i < _positions.length; i++)
                          Positioned(
                            left: constraints.maxWidth * _positions[i].dx,
                            top: constraints.maxHeight * _positions[i].dy,
                            child: _InterestStar(
                              interest: kInterests[i],
                              selected: _selected.contains(kInterests[i].value),
                              seed: i,
                              onTap: kInterests[i].soon
                                  ? null
                                  : () => setState(() {
                                        if (_selected.contains(kInterests[i].value)) {
                                          _selected.remove(kInterests[i].value);
                                        } else {
                                          _selected.add(kInterests[i].value);
                                        }
                                      }),
                            ),
                          ),
                      ],
                    ),
                  )
                : const Center(child: ThemedLoadingIndicator(size: 28)),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: _selected.isEmpty ? 'show me everything' : 'continue',
            onTap: _continue,
          ),
          if (_selected.isEmpty) ...[
            const SizedBox(height: 10),
            Center(
              child: Text('nothing picked yet is fine too — you can decide later'.tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 9, color: Colors.white.withOpacity(0.38))),
            ),
          ],
        ],
      ),
    );
  }
}

/// One point in the constellation — a plain glowing dot rather than a
/// category icon (icons here just read as a cramped, generic app-icon
/// grid; a dot is what actually makes it feel like a star), gently
/// bobbing in place so the whole sky reads as alive even before it's
/// touched. [seed] staggers each star's phase and period a little so
/// they never drift in lockstep.
class _InterestStar extends StatefulWidget {
  final Interest interest;
  final bool selected;
  final int seed;
  final VoidCallback? onTap;
  const _InterestStar({required this.interest, required this.selected, required this.seed, required this.onTap});

  @override
  State<_InterestStar> createState() => _InterestStarState();
}

class _InterestStarState extends State<_InterestStar> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 2600 + (widget.seed * 431) % 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.mediaColor(widget.interest.value);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final dx = ((widget.seed * 37) % 5 - 2) * 3.2; // -6.4..6.4, varies by star
        final dy = 6 + (widget.seed % 3) * 2; // 6..10
        return Transform.translate(offset: Offset(t * dx, -t * dy), child: child);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: widget.selected ? 54 : 36,
              height: widget.selected ? 54 : 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.selected ? color.withOpacity(0.92) : Colors.white.withOpacity(0.10),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: widget.selected ? 10 : 6,
                height: widget.selected ? 10 : 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.selected ? SeenlyPalette.accentOnAccent : Colors.white.withOpacity(0.7),
                ),
              ),
            ),
            const SizedBox(height: 5),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: SeenlyText.mono(
                size: widget.selected ? 10.5 : 9,
                color: widget.selected ? SeenlyPalette.paper : Colors.white54,
                weight: widget.selected ? FontWeight.w700 : FontWeight.w400,
              ),
              child: Text(widget.interest.label),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Step 6 — a few favorite films, same search-and-pick flow as before,
// restyled for the night rather than the paper.
// ---------------------------------------------------------------------

// Shown by default, before anyone's typed a single letter — so picking
// a favorite is a tap, not a chore that starts with "now think of a
// title and spell it correctly". Deliberately broad and internationally
// recognisable "comfort rewatch" titles rather than new releases, since
// that's exactly the pitch in the copy above the grid ("the classics,
// the comfort rewatches, whatever comes to mind first") — and picked to
// not repeat anything already shown earlier in this same flow (see the
// _kDeckPrimaryQueries family above), so the onboarding never feels like
// it's showing the same six posters twice.
const _kFavoriteSuggestionQueries = [
  'Parasite',
  'Spirited Away',
  'La La Land',
  'The Dark Knight',
  'Pulp Fiction',
  'Amélie',
  'Interstellar',
  'Whiplash',
  'The Grand Budapest Hotel',
  'In the Mood for Love',
];

/// Search a few films worth calling favorites and mark them as such —
/// the exact same POST /profile/favorites/toggle the heart button on a
/// title screen uses (see ProfileService.toggleFavorite), so these picks
/// land as real WatchlistEntry rows with genres attached. GET
/// /feed/for-you builds its seeds and genre weights from precisely that
/// data (see backend/app/routers/feed.py), so a handful of picks here is
/// enough for "for you" on Home to have something to work with before a
/// single evening's actually been logged. Entirely optional — skipping
/// just means "for you" waits for the first real log instead, same as it
/// always has.
class _FavoritesStep extends StatefulWidget {
  final VoidCallback onNext;
  // Reports the current pick list up to _OnboardingScreenState on every
  // toggle — see _favoritesPicked there — so the plan-reveal card a few
  // steps later can show real posters without this step needing to know
  // anything about that card existing.
  final ValueChanged<List<MediaItem>>? onPicked;
  const _FavoritesStep({required this.onNext, this.onPicked});

  @override
  State<_FavoritesStep> createState() => _FavoritesStepState();
}

class _FavoritesStepState extends State<_FavoritesStep> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _results = const [];
  bool _loading = false;
  bool _searched = false;
  // The default-state grid — populated from _kFavoriteSuggestionQueries
  // the instant this step mounts, same streaming-as-they-land pattern as
  // _PosterDeckLoader above, just scoped to this one step instead of
  // running for the whole flow. Stays visible (search box still sits
  // above it) until the person actually types something.
  final List<MediaItem> _suggestions = [];
  bool _suggestionsLoading = true;

  // "source:id" -> the picked item, so the strip above the grid can
  // render real posters without re-fetching anything.
  final Map<String, MediaItem> _picked = {};

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  // Capped at 4 concurrent requests, same spirit as _PosterDeckLoader's
  // own gate — the deck loader may still be finishing its own fetches in
  // the background this early in the flow (it starts the instant
  // onboarding opens, from step one), so this stays modest rather than
  // adding a second uncapped burst on top of it.
  final _suggestionsGate = _Semaphore(4);

  Future<void> _loadSuggestions() async {
    final media = context.read<AppState>().media;
    var completed = 0;
    for (final query in _kFavoriteSuggestionQueries) {
      unawaited(() async {
        await _suggestionsGate.acquire();
        try {
          final results = await media.search(
            query,
            includeGames: false,
            includeBooks: false,
            includeManga: false,
          );
          if (!mounted || results.isEmpty) return;
          setState(() => _suggestions.add(results.first));
        } catch (_) {
          // One missed suggestion just means a slightly shorter grid —
          // never worth surfacing as an error on a step this optional.
        } finally {
          _suggestionsGate.release();
          completed++;
          if (mounted && completed >= _kFavoriteSuggestionQueries.length) {
            setState(() => _suggestionsLoading = false);
          }
        }
      }());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () => _search(query));
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _searched = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await context.read<AppState>().media.search(
            q,
            includeGames: false,
            includeBooks: false,
            includeManga: false,
          );
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        _searched = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(MediaItem item) async {
    final key = '${item.source}:${item.id}';
    final wasPicked = _picked.containsKey(key);
    setState(() {
      if (wasPicked) {
        _picked.remove(key);
      } else {
        _picked[key] = item;
      }
    });
    widget.onPicked?.call(_picked.values.toList());
    try {
      await context.read<AppState>().profile.toggleFavorite(item, !wasPicked);
    } catch (_) {
      if (!mounted) return;
      // Best-effort — a failed request just un-does the optimistic tap
      // rather than leaving the UI out of sync with the server.
      setState(() {
        if (wasPicked) {
          _picked[key] = item;
        } else {
          _picked.remove(key);
        }
      });
      widget.onPicked?.call(_picked.values.toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('a few films you already love'.tr,
              textAlign: TextAlign.center, style: SeenlyText.serif(size: 18, color: SeenlyPalette.paper)),
          const SizedBox(height: 6),
          Text(
            'just a handful — not everything you\'ve ever watched, that part comes next when you import your history. Pick a few favorites here and "for you" on your home screen starts leaning toward them right away.'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 12, color: Colors.white.withOpacity(0.55)),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              style: SeenlyText.serif(size: 14, color: SeenlyPalette.paper),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'search for a film you\'d rewatch tonight'.tr,
                hintStyle: SeenlyText.serif(size: 13, color: Colors.white.withOpacity(0.35)),
                prefixIcon: Icon(Icons.search, size: 16, color: Colors.white.withOpacity(0.35)),
              ),
            ),
          ),
          if (_picked.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PickedStrip(items: _picked.values.toList(), onRemove: _toggle),
          ],
          const SizedBox(height: 12),
          Expanded(child: _buildResults()),
          const SizedBox(height: 14),
          PrimaryButton(
            label: _picked.isEmpty ? 'skip for now' : 'continue',
            onTap: widget.onNext,
          ),
          if (_picked.isEmpty) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'nothing picked yet is fine too — the heart on any title does the same thing later'.tr,
                textAlign: TextAlign.center,
                style: SeenlyText.mono(size: 9, color: Colors.white.withOpacity(0.38)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_loading && _results.isEmpty) {
      return const Center(child: ThemedLoadingIndicator(size: 34));
    }
    if (!_searched) {
      // Default state: real, tappable suggestions rather than an empty
      // placeholder asking someone to go think of a title first. Still
      // streams in one poster at a time as each search resolves (see
      // _loadSuggestions), same feel as the rest of this flow.
      if (_suggestions.isEmpty) {
        return _suggestionsLoading
            ? const Center(child: ThemedLoadingIndicator(size: 34))
            : Center(
                child: Text(
                  'the classics, the comfort rewatches, whatever comes to mind first'.tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(0.35)),
                ),
              );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'a few to start with — or search for your own above'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(0.35)),
          ),
          const SizedBox(height: 10),
          Expanded(child: _posterGrid(_suggestions)),
        ],
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('nothing turned up for that — try another title'.tr,
            style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(0.35))),
      );
    }
    return _posterGrid(_results);
  }

  Widget _posterGrid(List<MediaItem> items) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2 / 3,
      ),
      itemBuilder: (context, i) {
        final item = items[i];
        final picked = _picked.containsKey('${item.source}:${item.id}');
        return PosterTile(
          title: item.title.display,
          posterUrl: item.posterUrl,
          fallbackColor: SeenlyPalette.mediaColor(item.mediaType),
          onTap: () => _toggle(item),
          badge: picked
              ? Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: SeenlyPalette.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 10, color: SeenlyPalette.accentOnAccent),
                )
              : null,
        );
      },
    );
  }
}

/// A thin horizontal strip of what's been picked so far — tapping a
/// thumbnail here un-picks it the same way tapping it in the grid would.
class _PickedStrip extends StatelessWidget {
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onRemove;
  const _PickedStrip({required this.items, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          return SizedBox(
            width: 50,
            child: PosterTile(
              title: item.title.display,
              posterUrl: item.posterUrl,
              fallbackColor: SeenlyPalette.mediaColor(item.mediaType),
              showLabel: false,
              onTap: () => onRemove(item),
              badge: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: SeenlyPalette.accent, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 9, color: SeenlyPalette.accentOnAccent),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Step 7 — reassurance, closing on a line that settles rather than a
// character. The same "not a tracker dashboard, not a leaderboard"
// register as the opening screen, aimed at someone about to wonder
// whether they'll actually keep this up.
// ---------------------------------------------------------------------

class _MotivationStep extends StatefulWidget {
  final VoidCallback onNext;
  const _MotivationStep({required this.onNext});

  @override
  State<_MotivationStep> createState() => _MotivationStepState();
}

class _MotivationStepState extends State<_MotivationStep> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final lift = Curves.easeInOut.transform(_controller.value) * 5;
              return Transform.translate(
                offset: Offset(0, -lift),
                child: CustomPaint(
                  size: const Size(240, 70),
                  painter: const _CalmWavePainter(color: SeenlyPalette.mustard),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'one evening a week is already enough'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 20, weight: FontWeight.w600, color: SeenlyPalette.paper),
          ),
          const SizedBox(height: 12),
          Text(
            'no streaks to keep and nothing to fall behind on — log an evening whenever you actually have one, and teamira quietly fills in around it.'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 13, color: Colors.white.withOpacity(0.55)),
          ),
          const Spacer(),
          PrimaryButton(label: 'continue', onTap: widget.onNext),
        ],
      ),
    );
  }
}

/// A line that starts uneven on the left and settles into an almost flat
/// breath by the right edge — the visual equivalent of the line above it.
class _CalmWavePainter extends CustomPainter {
  final Color color;
  const _CalmWavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const cycles = 6;
    const steps = 70;
    final path = Path();
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      final amplitude = 22 - 19 * t;
      final y = size.height / 2 + math.sin(t * cycles * 2 * math.pi) * amplitude;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final glow = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final crisp = Paint()
      ..color = color.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, glow);
    canvas.drawPath(path, crisp);
  }

  @override
  bool shouldRepaint(covariant _CalmWavePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------
// Step 8 (new) — a one-line "plan", typed out letter by letter, that
// quietly recaps the two choices made a few steps ago (interests, the
// logging ritual) as a single sentence rather than a bulleted summary.
// Nothing here is stored — it only reads back what _InterestsStep and
// _RitualStep already saved (CollectionsPrefsService / LogThemeService)
// — so this step can't ever drift out of sync with what was actually
// picked, and skipping either earlier step just means a calmer, more
// general sentence instead of an error state.
// ---------------------------------------------------------------------

/// One run of the typed sentence — a chunk of text plus the colour it
/// should render in. Kept separate from plain string interpolation so
/// the interest and ritual callbacks can carry their own colour through
/// the reveal instead of the whole line going a single flat tone.
class _PlanSpan {
  final String text;
  final Color? color;
  const _PlanSpan(this.text, [this.color]);
}

/// Replaces a plain "continue" tap with something done by hand instead
/// of by finger-tap: drag the two halves of a small ticket stub apart
/// until it tears. Every other gesture in this flow either doesn't
/// finish anything (the orbit hero on Welcome springs right back the
/// instant you let go) or is a plain tap — this is the one place a drag
/// is allowed to actually complete something, which is exactly why it's
/// saved for the one moment that matters most: crossing from "still
/// deciding" into "using the app". Tinted with whichever ritual world's
/// colour _PlanRevealStep already carries, so even this brand-new bit
/// of UI reads as a continuation of a choice made a few steps back,
/// not a component with its own arbitrary colour.
///
/// You only have to pull it about 40% of the way — real paper doesn't
/// need a finger dragged all the way across it, it just needs to be
/// started. Past that point the ticket takes over: a spring carries the
/// tear the rest of the way with a bit of overshoot (the "crunch"),
/// and the whole thing shivers with resisting tension right up until
/// it gives.
class _TearTicketAction extends StatefulWidget {
  final Color accent;
  final VoidCallback onTorn;
  const _TearTicketAction({required this.accent, required this.onTorn});

  @override
  State<_TearTicketAction> createState() => _TearTicketActionState();
}

class _TearTicketActionState extends State<_TearTicketAction> with TickerProviderStateMixin {
  static const _leftWidth = 208.0;
  static const _rightWidth = 84.0;
  static const _height = 100.0;
  static const _maxGap = 46.0;
  static const _notchRadius = 8.0;
  // The drag only needs to cover this fraction before the paper takes
  // over — the point where real paper stops needing a finger and
  // starts tearing on its own.
  static const _completeThreshold = 0.42;
  // How much further the two halves sail apart (and fade) once the
  // crunch has landed, before onTorn actually fires. This is purely a
  // paint-time overflow (the Stack below is Clip.none) — it is NOT
  // reserved in the widget's layout size, so it never pushes the
  // ticket off-centre or off-screen while it's just sitting there.
  static const _flyDistance = 110.0;
  // Actual layout slack reserved on each side of the resting ticket —
  // just enough for the drag phase and the crunch's own overshoot, so
  // the widget stays a normal, screen-sized control at rest.
  static const _layoutMargin = 30.0;

  // 0.._completeThreshold while the finger is doing the work. Frozen
  // the instant it crosses the threshold — from there the spring owns
  // the motion. Released early (never having reached the threshold),
  // it settles back to 0 rather than staying half-torn.
  double _tear = 0;
  bool _autoCompleting = false; // spring has taken over from the finger
  bool _torn = false; // crunch has landed; now sailing apart and fading
  int _lastHapticStep = -1;
  double _tearAtSpringStart = 0;

  // Eases an uncommitted, released drag gently back to whole.
  late final AnimationController _springBack = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
    ..addListener(() {
      if (!mounted) return;
      setState(() => _tear = _tearAtSpringStart * (1 - Curves.easeOutCubic.transform(_springBack.value)));
    });

  // Carries the tear from the threshold to "fully given way" with a
  // real overshoot — an underdamped spring, so it snaps past 1.0 and
  // settles back rather than gliding to a linear stop. This is the
  // "hrust" (crunch): the moment the paper finishes the job itself.
  double _crunch = 0;
  late final AnimationController _crunchCtrl = AnimationController.unbounded(vsync: this)
    ..addListener(() {
      if (!mounted) return;
      setState(() => _crunch = _crunchCtrl.value);
    });

  // Once the crunch has landed, the two halves keep travelling apart
  // and fading out — the actual "gone" payoff — before onTorn fires.
  late final AnimationController _flyCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _fly = CurvedAnimation(parent: _flyCtrl, curve: Curves.easeInCubic);

  // A tight, continuous shiver representing the paper resisting the
  // pull — near-silent at the start of the drag, building toward a
  // visible tremor as the pull nears the point where it gives way.
  // Rebuilds only while it's actually doing something, so it doesn't
  // spend frames animating an invisible tremor at rest.
  late final AnimationController _jitterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 70))
    ..addListener(() {
      if (!mounted) return;
      if (_tear > 0 && !_autoCompleting && !_torn) setState(() {});
    });

  @override
  void dispose() {
    _springBack.dispose();
    _crunchCtrl.dispose();
    _flyCtrl.dispose();
    _jitterCtrl.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails d) {
    if (_torn || _autoCompleting) return;
    _springBack.stop();
    if (!_jitterCtrl.isAnimating) _jitterCtrl.repeat();
    HapticFeedback.selectionClick();
    _lastHapticStep = -1;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_torn || _autoCompleting) return;
    final dragSpeed = d.delta.dx.abs();
    setState(() => _tear = (_tear + dragSpeed / 150).clamp(0.0, _completeThreshold).toDouble());
    // Paper doesn't give smoothly — it catches in small stages, each
    // tick a touch sharper than the last as the pull nears the point
    // where the ticket takes over.
    final step = (_tear / _completeThreshold * 4).floor();
    if (step != _lastHapticStep && step > 0) {
      _lastHapticStep = step;
      HapticFeedback.lightImpact();
    }
    if (_tear >= _completeThreshold) {
      _beginAutoTear(dragSpeed);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_torn || _autoCompleting) return;
    _jitterCtrl.stop();
    _tearAtSpringStart = _tear;
    _springBack.forward(from: 0);
  }

  // Hands the tear off from the finger to a spring: the ticket finishes
  // ripping itself, overshooting past "fully apart" before settling —
  // the crunch — and only then sails off and fades.
  Future<void> _beginAutoTear(double lastDragSpeed) async {
    _autoCompleting = true;
    _jitterCtrl.stop();
    HapticFeedback.heavyImpact();
    final spring = SpringDescription(mass: 1, stiffness: 210, damping: 11);
    final sim = SpringSimulation(spring, _tear, 1.0, 5.5 + lastDragSpeed * 0.5);
    await _crunchCtrl.animateWith(sim);
    if (!mounted) return;
    HapticFeedback.mediumImpact(); // the crunch landing
    setState(() => _torn = true);
    await _flyCtrl.forward(from: 0);
    if (!mounted) return;
    widget.onTorn();
  }

  @override
  Widget build(BuildContext context) {
    // preT tracks how far the tear has actually progressed — the raw
    // drag before the handoff, the (briefly overshooting) spring value
    // after it. It only ever moves in one direction once auto-complete
    // begins.
    final preT = _autoCompleting ? _crunch : _tear;
    final flown = _fly.value * _flyDistance;
    final gap = preT * _maxGap + flown;
    final rot = preT.clamp(0.0, 1.35) * 0.13 + _fly.value * 0.22;
    final opacity = _torn ? (1 - _fly.value).clamp(0.0, 1.0).toDouble() : 1.0;

    // The resistance shiver: silent until a real pull starts, growing
    // sharply as the drag closes in on the handoff point, gone the
    // instant the spring takes over (its own overshoot reads as motion
    // enough on its own).
    final resistance = (!_autoCompleting && !_torn && _completeThreshold > 0)
        ? (_tear / _completeThreshold).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final shiver = math.sin(_jitterCtrl.value * 2 * math.pi) * resistance * resistance * 2.6;
    final shiverY = math.cos(_jitterCtrl.value * 2 * math.pi * 1.3) * resistance * resistance * 1.4;

    final accent = widget.accent;

    // Layout, done with explicit Positioned offsets rather than Stack's
    // own centering: the two halves are different widths (a wide label
    // stub and a narrow arrow stub), and Stack's alignment centers each
    // non-positioned child independently — which would sit the narrow
    // half concentrically on top of the middle of the wide one instead
    // of after it. Positioned everything by hand so the two halves sit
    // flush, side by side, at rest.
    const margin = _layoutMargin; // slack on each side for the halves to travel into
    final outerWidth = _leftWidth + _rightWidth + margin * 2;
    final outerHeight = _height + 30;
    final restLeft = margin; // left half's resting left edge
    final halvesTop = (outerHeight - _height) / 2;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: SizedBox(
        width: outerWidth,
        height: outerHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The dashed perforation — only visible before any pull
            // starts, the usual "this is where it gives" cue on a real
            // ticket. Fades out the instant a drag begins rather than
            // trying to track the growing gap itself. Sits right at the
            // resting seam between the two halves.
            Positioned(
              left: restLeft + _leftWidth - 1,
              top: (outerHeight - (_height - 10)) / 2,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _tear <= 0.01 ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: CustomPaint(
                    size: const Size(2, _height - 10),
                    painter: _PerforationPainter(color: accent.withOpacity(0.55)),
                  ),
                ),
              ),
            ),
            // A soft paper shadow under each half, drawn from the same
            // torn-and-notched silhouette so it actually follows the
            // ticket's shape instead of falling back to a plain
            // rectangle — this alone is most of what makes it read as
            // a physical object sitting above the sky rather than a
            // flat button painted on it.
            Positioned(
              left: restLeft,
              top: halvesTop,
              width: _leftWidth,
              height: _height,
              child: Transform.translate(
                offset: Offset(-gap + shiver, shiverY),
                child: Opacity(
                  opacity: opacity * 0.9,
                  child: Transform.rotate(
                    angle: -rot,
                    alignment: Alignment.centerRight,
                    child: CustomPaint(
                      size: Size(_leftWidth, _height),
                      painter: _TornHalfShadow(
                        edgeOnRight: true,
                        notchRadius: _notchRadius,
                        color: Colors.black.withOpacity(0.32),
                        blur: 5 + rot.abs() * 30,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: restLeft + _leftWidth - 2,
              top: halvesTop,
              width: _rightWidth,
              height: _height,
              child: Transform.translate(
                offset: Offset(gap - shiver, -shiverY),
                child: Opacity(
                  opacity: opacity * 0.9,
                  child: Transform.rotate(
                    angle: rot,
                    alignment: Alignment.centerLeft,
                    child: CustomPaint(
                      size: Size(_rightWidth, _height),
                      painter: _TornHalfShadow(
                        edgeOnRight: false,
                        notchRadius: _notchRadius,
                        color: Colors.black.withOpacity(0.32),
                        blur: 5 + rot.abs() * 30,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: restLeft,
              top: halvesTop,
              width: _leftWidth,
              height: _height,
              child: Transform.translate(
                offset: Offset(-gap + shiver, shiverY),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.rotate(
                    angle: -rot,
                    alignment: Alignment.centerRight,
                    child: ClipPath(
                      clipper: const _TornEdgeClipper(edgeOnRight: true, notchRadius: _notchRadius),
                      child: Container(
                        width: _leftWidth,
                        height: _height,
                        padding: const EdgeInsets.only(right: 14, left: 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(SeenlyPalette.paper, accent, 0.20)!.withOpacity(0.24),
                              accent.withOpacity(0.30),
                            ],
                          ),
                          border: Border.all(color: accent.withOpacity(0.6), width: 1.2),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.confirmation_number_outlined, size: 17, color: accent.withOpacity(0.85)),
                            const SizedBox(width: 9),
                            Flexible(
                              child: Text(
                                'tear to continue'.tr,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SeenlyText.mono(size: 14.5, color: SeenlyPalette.paper, weight: FontWeight.w700)
                                    .copyWith(letterSpacing: 0.2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: restLeft + _leftWidth - 2,
              top: halvesTop,
              width: _rightWidth,
              height: _height,
              child: Transform.translate(
                offset: Offset(gap - shiver, -shiverY),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.rotate(
                    angle: rot,
                    alignment: Alignment.centerLeft,
                    child: ClipPath(
                      clipper: const _TornEdgeClipper(edgeOnRight: false, notchRadius: _notchRadius),
                      child: Container(
                        width: _rightWidth,
                        height: _height,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withOpacity(0.30),
                              Color.lerp(SeenlyPalette.paper, accent, 0.20)!.withOpacity(0.24),
                            ],
                          ),
                          border: Border.all(color: accent.withOpacity(0.6), width: 1.2),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                        ),
                        child: Icon(Icons.arrow_forward_rounded, size: 24, color: SeenlyPalette.paper.withOpacity(0.9)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft, paper-shaped shadow cast by one half of the ticket — drawn
/// from the exact same torn-and-notched silhouette as
/// [_TornEdgeClipper], so it follows the ticket's actual outline
/// (teeth and punch-holes included) instead of falling back to a
/// generic rectangular drop shadow.
class _TornHalfShadow extends CustomPainter {
  final bool edgeOnRight;
  final double notchRadius;
  final Color color;
  final double blur;
  const _TornHalfShadow({
    required this.edgeOnRight,
    required this.notchRadius,
    required this.color,
    required this.blur,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final clipper = _TornEdgeClipper(edgeOnRight: edgeOnRight, notchRadius: notchRadius);
    canvas.drawShadow(clipper.getClip(size), color, blur, false);
  }

  @override
  bool shouldRepaint(covariant _TornHalfShadow oldDelegate) =>
      oldDelegate.blur != blur || oldDelegate.color != color || oldDelegate.edgeOnRight != edgeOnRight;
}

/// Bites a small zigzag out of one vertical edge of a rectangle, plus a
/// round punch-hole notch top and bottom right at the seam — the two
/// details that actually read as "ticket stub" rather than "rounded
/// button". `edgeOnRight` picks which side gets the teeth and which
/// corner the notches sit on; the ticket's left half bites its right
/// edge and the right half bites its left edge, so together the two
/// halves read as one ticket torn down the middle rather than two
/// separately-shaped chips, with the two half-notches lining up into
/// full circles when the halves sit flush.
class _TornEdgeClipper extends CustomClipper<Path> {
  final bool edgeOnRight;
  final double notchRadius;
  const _TornEdgeClipper({required this.edgeOnRight, this.notchRadius = 0});

  @override
  Path getClip(Size size) {
    const teeth = 10;
    const amplitude = 6.5;
    final toothH = size.height / teeth;
    final path = Path();
    if (edgeOnRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      for (var i = 0; i < teeth; i++) {
        final yMid = i * toothH + toothH / 2;
        final yEnd = (i + 1) * toothH;
        path.lineTo(size.width - (i.isEven ? amplitude : 0), yMid);
        path.lineTo(size.width, yEnd);
      }
      path.lineTo(0, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(0, 0);
      for (var i = 0; i < teeth; i++) {
        final yMid = i * toothH + toothH / 2;
        final yEnd = (i + 1) * toothH;
        path.lineTo(i.isEven ? amplitude : 0, yMid);
        path.lineTo(0, yEnd);
      }
      path.lineTo(size.width, size.height);
    }
    path.close();
    if (notchRadius <= 0) return path;
    final notchX = edgeOnRight ? size.width : 0.0;
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(notchX, 0), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(notchX, size.height), radius: notchRadius));
    return Path.combine(PathOperation.difference, path, notches);
  }

  @override
  bool shouldReclip(covariant _TornEdgeClipper oldClipper) =>
      oldClipper.edgeOnRight != edgeOnRight || oldClipper.notchRadius != notchRadius;
}

/// The plain dashed line hinting where the ticket above will give —
/// gone the instant a drag actually starts (see _TearTicketActionState).
class _PerforationPainter extends CustomPainter {
  final Color color;
  const _PerforationPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 4.0, gap = 4.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, math.min(y + dash, size.height)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _PerforationPainter oldDelegate) => oldDelegate.color != color;
}

class _PlanRevealStep extends StatefulWidget {
  final VoidCallback onNext;
  // Read once, when the card is actually opened for sharing — see
  // _favoritesPicked on _OnboardingScreenState. Never watched, so a
  // favorite picked a couple steps back doesn't cause this step to
  // rebuild for no visible reason.
  final ValueListenable<List<MediaItem>> favorites;
  const _PlanRevealStep({required this.onNext, required this.favorites});

  @override
  State<_PlanRevealStep> createState() => _PlanRevealStepState();
}

class _PlanRevealStepState extends State<_PlanRevealStep> with TickerProviderStateMixin {
  static const _msPerChar = 26;
  static const _minDuration = Duration(milliseconds: 1200);
  static const _maxDuration = Duration(milliseconds: 2600);
  // How many of the most-recently-revealed characters still render as
  // "settling" rather than fully solid — this is what turns a flat
  // per-character cut into something that reads as ink still catching,
  // not a progress bar.
  static const _settleChars = 5;

  // Caption fades in first, alone, so the sentence never starts typing
  // into an empty frame that just materialized.
  late final AnimationController _caption = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  // Undamped on purpose — a steady blink rather than a spring, since a
  // cursor is a metronome, not a gesture.
  late final AnimationController _cursor = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  )..repeat(reverse: true);
  // A single pass of light over the finished line — runs once, the
  // instant typing completes, then just sits idle at rest.
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  AnimationController? _type;

  List<_PlanSpan> _spans = const [];
  // Every character in _spans, flattened once when the sentence is built
  // (not recomputed every frame) — both the reveal and the comet's
  // current colour read off this same list.
  List<MapEntry<String, Color?>> _flatChars = const [];
  bool _ready = false;
  bool _typedOnce = false;
  // Kept alongside _spans purely so _PlanCard can be built later without
  // re-deriving anything — same ritual world and language the sentence
  // itself already read back.
  _RitualWorld _world = _kWorlds.first;
  bool _preferRussian = false;
  // Set true a beat after the sentence finishes — deliberately later
  // than the "continue" button below, so the card offer reads as a
  // second, quieter beat rather than competing with the main action for
  // attention the instant typing lands.
  bool _showCardAction = false;
  // Which _spans indices have already fired their "this word landed"
  // haptic — so a highlighted phrase ticks exactly once as its last
  // letter appears, never once per frame while it's mid-reveal.
  final Set<int> _spanTicked = {};

  @override
  void initState() {
    super.initState();
    _caption.forward();
    _loadAndBuild();
  }

  Future<void> _loadAndBuild() async {
    Set<String> interestValues = const {};
    try {
      interestValues = await CollectionsPrefsService().loadInterests();
    } catch (_) {
      // No saved interests yet (or the earlier step was skipped) — the
      // fallback phrase below covers this.
    }
    if (!mounted) return;

    final labels = [
      for (final v in interestValues)
        kInterests.firstWhere((i) => i.value == v, orElse: () => kInterests.first).label,
    ];

    late final _RitualWorld world;
    try {
      final theme = context.read<LogThemeService>().theme;
      world = _kWorlds.firstWhere((w) => w.theme == theme, orElse: () => _kWorlds.first);
    } catch (_) {
      world = _kWorlds.first;
    }
    bool preferRussian = false;
    try {
      preferRussian = context.read<LocaleService>().preferRussian;
    } catch (_) {
      // No LocaleService in scope for some reason — the card just falls
      // back to its default language chip.
    }

    final interestsPhrase = _joinNaturally(labels);
    final diary = world.diary; // e.g. "your diary becomes a jar, filling up with stubs"
    final diaryCapitalized = diary.isEmpty ? diary : diary[0].toUpperCase() + diary.substring(1);

    setState(() {
      _world = world;
      _preferRussian = preferRussian;
      _spans = [
        const _PlanSpan("so — you're here mostly for "),
        _PlanSpan(interestsPhrase, SeenlyPalette.mustard),
        const _PlanSpan(". "),
        _PlanSpan(diaryCapitalized, world.color),
        const _PlanSpan(
          " — logged whenever you actually have an evening, nothing to keep up with in between.",
        ),
      ];
      _flatChars = [
        for (final s in _spans) for (final ch in s.text.split('')) MapEntry(ch, s.color),
      ];
      _ready = true;
    });
    _startTyping();
  }

  String _joinNaturally(List<String> labels) {
    if (labels.isEmpty) return 'whatever you end up watching';
    if (labels.length == 1) return labels.first;
    if (labels.length == 2) return '${labels[0]} and ${labels[1]}';
    return '${labels.sublist(0, labels.length - 1).join(', ')}, and ${labels.last}';
  }

  void _startTyping() {
    final total = _spans.fold<int>(0, (sum, s) => sum + s.text.length);
    final ms = (total * _msPerChar).clamp(_minDuration.inMilliseconds, _maxDuration.inMilliseconds).toInt();
    final duration = Duration(milliseconds: ms);
    _type = AnimationController(vsync: this, duration: duration)
      ..addListener(_checkSpanMilestones)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted && !_typedOnce) {
          _typedOnce = true;
          HapticFeedback.lightImpact();
          _shimmer.forward(from: 0);
          setState(() {});
          Future.delayed(const Duration(milliseconds: 460), () {
            if (mounted) setState(() => _showCardAction = true);
          });
        }
      });
    // A short beat after the caption lands, not the instant it starts
    // fading in — the pause is what makes the first letter read as a
    // deliberate beginning rather than a continuation of the fade.
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _type?.forward();
    });
  }

  // Runs on every tick while typing — not in build(), since firing a
  // haptic is a side effect and build() has to stay pure. Each
  // highlighted span (the interests phrase, the ritual callback) gets
  // exactly one soft tick the moment its last character lands, so the
  // two things this step is actually reporting back feel like they
  // physically "click into place" rather than just fading in with
  // everything else.
  void _checkSpanMilestones() {
    final total = _spans.fold<int>(0, (sum, s) => sum + s.text.length);
    final revealed = ((_type?.value ?? 0) * total).round();
    var cursor = 0;
    for (var i = 0; i < _spans.length; i++) {
      final end = cursor + _spans[i].text.length;
      if (_spans[i].color != null && revealed >= end && _spanTicked.add(i)) {
        HapticFeedback.selectionClick();
      }
      cursor = end;
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _cursor.dispose();
    _shimmer.dispose();
    _type?.dispose();
    super.dispose();
  }

  /// Renders everything up to the reveal edge — merging same-colour runs
  /// into single TextSpans for the bulk of the line, but breaking the
  /// last [_settleChars] out individually with a graded opacity ramp,
  /// faintest right behind the comet and solid a few characters back.
  /// That trailing gradient is what makes each letter look like it's
  /// still catching rather than simply switching on.
  List<InlineSpan> _visibleSpans() {
    final progress = _type?.value ?? 0;
    final total = _flatChars.length;
    final revealed = (total * progress).round().clamp(0, total);
    final bulkEnd = (revealed - _settleChars).clamp(0, revealed);

    final out = <InlineSpan>[];
    var i = 0;
    while (i < bulkEnd) {
      final color = _flatChars[i].value;
      final buffer = StringBuffer();
      while (i < bulkEnd && _flatChars[i].value == color) {
        buffer.write(_flatChars[i].key);
        i++;
      }
      out.add(TextSpan(
        text: buffer.toString(),
        style: SeenlyText.serif(size: 21, weight: FontWeight.w600, color: color ?? SeenlyPalette.paper),
      ));
    }
    for (var j = bulkEnd; j < revealed; j++) {
      final settle = ((j - bulkEnd + 1) / _settleChars).clamp(0.0, 1.0);
      final base = _flatChars[j].value ?? SeenlyPalette.paper;
      out.add(TextSpan(
        text: _flatChars[j].key,
        style: SeenlyText.serif(
          size: 21,
          weight: FontWeight.w600,
          color: base.withOpacity(0.25 + 0.75 * settle),
        ),
      ));
    }
    return out;
  }

  /// Whatever colour the character right at the reveal edge carries —
  /// paper for plain text, mustard mid-word through the interests
  /// phrase, the ritual world's own colour mid-word through the diary
  /// line. This is what the comet's head reads its colour from, so it
  /// visibly changes hue exactly when it crosses into one of the two
  /// callbacks rather than staying one flat tone the whole line.
  Color _currentColor() {
    if (_flatChars.isEmpty) return SeenlyPalette.paper;
    final progress = _type?.value ?? 0;
    final idx = ((_flatChars.length * progress).round() - 1).clamp(0, _flatChars.length - 1);
    return _flatChars[idx].value ?? SeenlyPalette.paper;
  }

  // Opens the same reusable share-card sheet the rest of the app uses
  // (widgets/share_sheet.dart — Wrapped, trailer reels) rather than a
  // bespoke modal, so this gets the same capture-to-PNG plumbing and the
  // same "blurred backdrop, centered card" presentation for free. The
  // card itself (_PlanCard) is built from exactly the spans, world, and
  // language this step already has on hand — nothing re-derived, nothing
  // that can drift out of sync with the sentence just typed above it.
  void _openCard() {
    HapticFeedback.selectionClick();
    showShareCardSheet(
      context,
      card: _PlanCard(
        spans: _spans,
        world: _world,
        preferRussian: _preferRussian,
        favorites: widget.favorites.value,
      ),
      fileName: 'seenly-plan',
      shareText: 'quietly setting up my evenings on Seenly 🌙',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          FadeTransition(
            opacity: _caption,
            child: Text(
              'here\'s the shape of it'.tr,
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 11, color: Colors.white.withOpacity(0.42)),
            ),
          ),
          const SizedBox(height: 18),
          if (!_ready)
            const SizedBox(height: 28, width: 28, child: ThemedLoadingIndicator(size: 28))
          else
            AnimatedBuilder(
              animation: Listenable.merge([_type, _cursor, _shimmer]),
              builder: (context, _) {
                // Once the shimmer sweep has fully passed, the comet is
                // done — don't keep reserving inline space for an
                // invisible trailing element, or the centered line would
                // sit a hair off from where it settles right after.
                final showComet = !(_typedOnce && _shimmer.isCompleted);
                final sentence = RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: [
                      ..._visibleSpans(),
                      // A small comet — bright head, fading tail — rather
                      // than a blinking "|". This is the same shooting
                      // star that occasionally streaks the whole sky in
                      // this flow (see _ShootingStarBackdrop), just slowed
                      // down and put to work actually tracing the line
                      // instead of passing through decoratively. Its head
                      // takes _currentColor(), so it visibly shifts hue
                      // the moment it crosses into the interests phrase or
                      // the ritual callback, then fades out as the shimmer
                      // sweep passes over the finished sentence — its own
                      // spark becoming that one pass of light.
                      if (showComet)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Builder(builder: (context) {
                              final flicker = 0.7 + 0.3 * _cursor.value;
                              final fade = _typedOnce ? (1 - _shimmer.value).clamp(0.0, 1.0) : 1.0;
                              return SizedBox(
                                width: 22,
                                height: 14,
                                child: CustomPaint(
                                  painter: _CometCursorPainter(
                                    color: _currentColor(),
                                    intensity: flicker * fade,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                );
                if (!_typedOnce) return sentence;
                // One pass of a bright, narrow highlight sweeping left to
                // right over the finished line, timed to the comet's own
                // fade — a single-shot "shine", not a looping effect, so
                // it reads as the comet's spark trailing off across the
                // sentence rather than a decorative loading shimmer.
                return ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0),
                        Colors.white.withOpacity(0.55),
                        Colors.white.withOpacity(0),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      transform: _SlideGradientTransform(
                        (Curves.easeOut.transform(_shimmer.value) * 2.6 - 1) * bounds.width,
                      ),
                    ).createShader(bounds);
                  },
                  child: sentence,
                );
              },
            ),
          const Spacer(),
          // A small overshoot on the way in — the button doesn't just
          // fade, it settles into place a beat after the line finishes,
          // the same "played, not snapped" idea the page transitions use
          // via a real spring, just cheap enough here for a curve to
          // stand in for one.
          AnimatedScale(
            scale: _typedOnce ? 1 : 0.86,
            duration: const Duration(milliseconds: 480),
            curve: Curves.elasticOut,
            child: AnimatedOpacity(
              opacity: _typedOnce ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_typedOnce,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TearTicketAction(accent: _world.color, onTorn: widget.onNext),
                    const SizedBox(height: 8),
                    Text(
                      'drag to tear it — that\'s how you begin'.tr,
                      style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(0.35)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The quieter second beat: the same read-back, offered as
          // something to actually keep. Deliberately a plain ghost
          // pill, not a second PrimaryButton — "continue" stays the one
          // thing that looks like it needs pressing.
          AnimatedOpacity(
            opacity: _showCardAction ? 1 : 0,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOut,
            child: AnimatedSlide(
              offset: _showCardAction ? Offset.zero : const Offset(0, 0.3),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: !_showCardAction,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: GestureDetector(
                    onTap: _openCard,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 13, color: Colors.white.withOpacity(0.65)),
                          const SizedBox(width: 7),
                          Text(
                            'save this as a card'.tr,
                            style: SeenlyText.mono(size: 11, color: Colors.white.withOpacity(0.65)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The card itself — a small, static echo of the sentence above it: same
// spans (so "so — you're here mostly for [interests]" keeps its own
// mustard/world-colour highlighting), plus a short poster strip from
// _FavoritesStep and a quiet ritual/language footer. No animation here
// on purpose — this is the thing that gets frozen into a PNG, so it
// should look exactly as good sitting still as it does mid-reveal.
class _PlanCard extends StatelessWidget {
  final List<_PlanSpan> spans;
  final _RitualWorld world;
  final bool preferRussian;
  final List<MediaItem> favorites;

  const _PlanCard({
    required this.spans,
    required this.world,
    required this.preferRussian,
    required this.favorites,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: _OnboardingScreenState._nightColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: world.color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(color: world.color.withOpacity(0.22), blurRadius: 30, spreadRadius: -6),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // A handful of fixed, non-animated stars — the same idea as
          // _StarfieldBackdrop behind the whole flow, just frozen, since
          // this container gets rasterized to a still PNG.
          Positioned.fill(child: CustomPaint(painter: _StillStarsPainter(seed: 7))),
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(shape: BoxShape.circle, color: world.color.withOpacity(0.16)),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.nightlight_round, size: 13, color: world.color),
                  const SizedBox(width: 6),
                  Text('SEENLY'.tr, style: SeenlyText.mono(size: 11, color: Colors.white.withOpacity(0.55), weight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  children: [
                    for (final s in spans)
                      TextSpan(
                        text: s.text,
                        style: SeenlyText.serif(
                          size: 16,
                          weight: FontWeight.w600,
                          color: s.color ?? SeenlyPalette.paper,
                        ),
                      ),
                  ],
                ),
              ),
              if (favorites.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: favorites.length.clamp(0, 6),
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final item = favorites[i];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: SizedBox(
                          width: 44,
                          height: 64,
                          child: (item.posterUrl == null || item.posterUrl!.isEmpty)
                              ? Container(color: Colors.white.withOpacity(0.08))
                              : Image.network(
                                  item.posterUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(color: Colors.white.withOpacity(0.08)),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  _cardTag(world.label, world.color),
                  const SizedBox(width: 8),
                  _cardTag(preferRussian ? 'RU' : 'EN', Colors.white.withOpacity(0.5)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label, style: SeenlyText.mono(size: 9, color: color, weight: FontWeight.w700)),
    );
  }
}

/// A fixed (never animated) scatter of small stars — _StarfieldBackdrop's
/// look, without a ticker, since _PlanCard only ever needs to render one
/// still frame (either on screen or captured to PNG for sharing).
class _StillStarsPainter extends CustomPainter {
  final int seed;
  const _StillStarsPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < 34; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final r = 0.4 + rnd.nextDouble() * 1.1;
      paint.color = Colors.white.withOpacity(0.15 + rnd.nextDouble() * 0.35);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StillStarsPainter oldDelegate) => false;
}

/// Translates a gradient horizontally across whatever bounds it's asked
/// to shade in — the standard way to slide a [LinearGradient] across a
/// fixed shape over time, since [LinearGradient] itself has no notion of
/// animation.
class _SlideGradientTransform extends GradientTransform {
  final double dx;
  const _SlideGradientTransform(this.dx);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, 0, 0);
}

/// A tiny version of the shooting stars that occasionally streak the
/// whole sky elsewhere in this flow — a bright head with a soft fading
/// tail behind it, here doing double duty as the typewriter's cursor.
/// [intensity] folds together both the flicker (a fast little shimmer,
/// distinct from the slow blink a plain cursor would have) and the
/// fade-out once typing finishes, so the comet visibly burns out rather
/// than just disappearing.
class _CometCursorPainter extends CustomPainter {
  final Color color;
  final double intensity;
  const _CometCursorPainter({required this.color, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final head = Offset(size.width - 5, size.height / 2);
    final tailStart = Offset(2, size.height / 2);

    final tail = Paint()
      ..shader = LinearGradient(
        colors: [color.withOpacity(0), color.withOpacity(0.75 * intensity)],
      ).createShader(Rect.fromPoints(tailStart, head))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tailStart, head, tail);

    final glow = Paint()
      ..color = color.withOpacity(0.5 * intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(head, 4.5, glow);

    final core = Paint()..color = SeenlyPalette.paper.withOpacity(0.9 * intensity);
    canvas.drawCircle(head, 2, core);
  }

  @override
  bool shouldRepaint(covariant _CometCursorPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.intensity != intensity;
}

// ---------------------------------------------------------------------
// A shared confetti burst, fired from the outer flow (never from a step
// itself) at the handful of moments that earn one: the very first tap,
// choosing a ritual world, and arriving at the reassurance step. Built
// from the same palette as the rest of the app rather than random RGB —
// it should read as "more of this app's colour, all at once" rather than
// a generic party effect bolted on top of it.
// ---------------------------------------------------------------------

class _ConfettiPiece {
  final Offset origin; // fractional (0..1) position within the overlay
  final Offset velocity; // px/second
  final Color color;
  final double size;
  final double spin; // radians/second
  final bool round; // round dot vs small rectangle, for a bit of variety
  _ConfettiPiece({
    required this.origin,
    required this.velocity,
    required this.color,
    required this.size,
    required this.spin,
    required this.round,
  });
}

class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay({super.key});

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1500);
  static const _colors = [
    SeenlyPalette.coral,
    SeenlyPalette.mustard,
    SeenlyPalette.sage,
    SeenlyPalette.pink,
    SeenlyPalette.periwinkle,
    SeenlyPalette.paper,
  ];

  List<_ConfettiPiece> _pieces = const [];
  bool _showRing = true;
  late final AnimationController _controller = AnimationController(vsync: this, duration: _duration);

  /// Starts a fresh burst, replacing any still in flight. [origin] is
  /// fractional (0..1, 0..1) within this overlay — defaults to just
  /// above center, roughly where a step's headline sits. [count] and
  /// [speedScale] let a caller ask for something much smaller than the
  /// three big celebratory moments — see [sparkle] below.
  void burst({
    Offset origin = const Offset(0.5, 0.36),
    int count = 28,
    double speedScale = 1.0,
    bool withRing = true,
  }) {
    final rnd = math.Random();
    setState(() {
      _showRing = withRing;
      _pieces = List.generate(count, (_) {
        final angle = rnd.nextDouble() * 2 * math.pi;
        final speed = (70 + rnd.nextDouble() * 190) * speedScale;
        // Biased upward-and-outward like a real burst, not a uniform
        // circle — a plain circle of velocities reads as an explosion,
        // this reads as thrown.
        final vy = math.sin(angle) * speed - 90 * speedScale;
        return _ConfettiPiece(
          origin: origin,
          velocity: Offset(math.cos(angle) * speed, vy),
          color: _colors[rnd.nextInt(_colors.length)],
          size: (4.0 + rnd.nextDouble() * 5) * (0.55 + 0.45 * speedScale),
          spin: (rnd.nextDouble() - 0.5) * 12,
          round: rnd.nextBool(),
        );
      });
    });
    _controller.forward(from: 0);
  }

  /// A small, quiet cousin of [burst] — this is what fires when someone
  /// taps an empty patch of sky: just a handful of motes drifting apart
  /// with no shockwave, so it reads as "the sky noticed you" rather than
  /// competing with the three real celebratory moments in the flow.
  void sparkle(Offset origin) => burst(origin: origin, count: 9, speedScale: 0.32, withRing: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(pieces: _pieces, t: _controller.value, showRing: _showRing),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double t; // 0..1 over the burst's lifetime
  final bool showRing;

  const _ConfettiPainter({required this.pieces, required this.t, this.showRing = true});

  static const _gravity = 340.0; // px/s^2 — enough to arc back down within the burst's short life

  @override
  void paint(Canvas canvas, Size size) {
    if (pieces.isEmpty || t <= 0) return;
    final elapsed = t * 1.5; // seconds, matching the controller's duration
    // Pieces fade in the final third rather than vanishing at a hard
    // cutoff, so the burst settles instead of being cut off mid-fall.
    final opacity = t < 0.66 ? 1.0 : (1 - (t - 0.66) / 0.34).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    // A brief expanding ring of light right at the origin, gone within
    // the first third of the burst — this is what turns "particles
    // appear" into "something just went off here."
    final ringT = (t / 0.42).clamp(0.0, 1.0);
    if (showRing && ringT < 1.0 && pieces.isNotEmpty) {
      final origin = Offset(pieces.first.origin.dx * size.width, pieces.first.origin.dy * size.height);
      final ringRadius = Curves.easeOutCubic.transform(ringT) * 70;
      final ringOpacity = (1 - ringT) * 0.55;
      final ringPaint = Paint()
        ..color = SeenlyPalette.paper.withOpacity(ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 - ringT * 1.4;
      canvas.drawCircle(origin, ringRadius, ringPaint);
      final flashPaint = Paint()
        ..color = SeenlyPalette.paper.withOpacity(ringOpacity * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
      canvas.drawCircle(origin, ringRadius * 0.4, flashPaint);
    }

    for (final p in pieces) {
      final origin = Offset(p.origin.dx * size.width, p.origin.dy * size.height);
      final dx = p.velocity.dx * elapsed;
      final dy = p.velocity.dy * elapsed + 0.5 * _gravity * elapsed * elapsed;
      final pos = origin + Offset(dx, dy);
      final angle = p.spin * elapsed;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle);
      final paint = Paint()..color = p.color.withOpacity(opacity * 0.95);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size * 1.6, height: p.size * 0.7),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.pieces != pieces || oldDelegate.showRing != showRing;
}
