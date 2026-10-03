import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_translations.dart';
import '../services/log_theme_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'themed_loading_indicator.dart';

/// The "tanè is thinking" state of Ask tanè — shown on the results screen
/// while the shortlist is being fetched.
///
/// Replaces a bare [ThemedLoadingIndicator] with the same motif (sprout /
/// ticket / coach window / rocket, whichever [LogTheme] is active) plus
/// three things around it:
///
///  * a soft halo that breathes behind the motif, and a few four-point
///    sparkles that twinkle around it (the same glyph as the sparkle icon
///    on the Ask card, so the two read as one feature);
///  * a line of words that changes as the wait goes on — a little story
///    (reading → thinking → *something in the voice of your theme* →
///    counting minutes, if a time budget was chosen → weighing → almost
///    there), not a random shuffle. After the story runs out it settles
///    into two "still looking" lines that trade places for as long as the
///    wait lasts, so a slow connection never replays the beginning;
///  * a slow sweep of the accent colour across the line, and three dots
///    that hop one after the other — the "typing" cue.
///
/// Every line is spoken in the first person, present tense, on purpose:
/// Russian has no gendered ending there, so the same lines work for tanè
/// in both languages without an "(а)" anywhere.
///
/// When the answer is in, set [finale] to true: the line changes to
/// "here you go", the sparkles fly in to the motif, a ring pings out of it,
/// and the whole thing fades away — [finaleDuration] in total. The results
/// then come in with [TaneArrivalBurst] on the top pick. [paceTaneThinking]
/// does the timing for both screens that show this widget, so they can't
/// drift apart.
///
/// Honours the system "reduce motion" setting: no sweep, no slide, no
/// halo pulse, no sparkles — lines still change, with a plain cross-fade.
class TaneThinking extends StatefulWidget {
  /// The loading state stays up at least this long. The matching itself is
  /// local keyword/genre scoring and usually answers in a few hundred
  /// milliseconds — faster than anyone can read one line of this, which
  /// would make the whole thing a one-frame flash. Two lines' worth.
  /// (Errors are never held back.) Duration.zero turns the pacing off.
  static const minimumVisible = Duration(milliseconds: 2200);

  /// How long the ending takes; also how long [paceTaneThinking] waits for
  /// it before handing over the results.
  static const finaleDuration = Duration(milliseconds: 620);

  /// True when the person tapped one of the time chips — adds the
  /// "counting the minutes" step. (A budget typed into the sentence is only
  /// known once the response is back, so it can't be used here.)
  final bool hasTimeBudget;

  /// Flip to true once the answer is in to play the ending.
  final bool finale;

  const TaneThinking({
    super.key,
    this.hasTimeBudget = false,
    this.finale = false,
  });

  @override
  State<TaneThinking> createState() => _TaneThinkingState();
}

/// Runs [work] and paces the result for the "thinking" screen: waits for it,
/// makes sure the loading state was on screen for at least
/// [TaneThinking.minimumVisible], calls [onFinale] (the screen flips
/// `TaneThinking.finale` to true), waits out [TaneThinking.finaleDuration],
/// and only then returns — which is when the screen swaps in the results.
///
/// If [work] throws, the error goes straight through with no waiting.
Future<T> paceTaneThinking<T>({
  required Future<T> Function() work,
  required bool Function() isMounted,
  required VoidCallback onFinale,
}) async {
  final started = DateTime.now();
  final result = await work();
  final left = TaneThinking.minimumVisible - DateTime.now().difference(started);
  if (left > Duration.zero) await Future<void>.delayed(left);
  if (!isMounted()) return result;
  onFinale();
  await Future<void>.delayed(TaneThinking.finaleDuration);
  return result;
}

class _TaneThinkingState extends State<TaneThinking>
    with TickerProviderStateMixin {
  /// How long each line of the story stays up.
  static const _step = Duration(milliseconds: 1100);

  /// Once the story reaches "almost there" and after that in the
  /// "still looking" lines — slower, because at this point the person is
  /// already waiting longer than expected and flicker would feel anxious.
  static const _tailStep = Duration(milliseconds: 2400);

  /// The one clock behind everything that moves here except the themed
  /// motif (which keeps its own). 2.4 s per lap: the sweep and the halo use
  /// the lap as is, the dots run two laps per lap.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  /// 0→1 over [TaneThinking.finaleDuration]; stays at 0 until the finale.
  late final AnimationController _finaleClock = AnimationController(
    vsync: this,
    duration: TaneThinking.finaleDuration,
  );

  /// The whole widget dissolves over the last fifth of the finale, so the
  /// results come in on an empty screen instead of on top of a spinner.
  late final Animation<double> _fadeOut = Tween<double>(begin: 1, end: 0).animate(
    CurvedAnimation(
      parent: _finaleClock,
      curve: const Interval(0.78, 1.0, curve: Curves.easeIn),
    ),
  );

  final _rng = math.Random();
  late final List<String> _lines;
  late final int _storyLength;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final theme = context.read<LogThemeService>().theme;
    final story = _story(theme);
    _storyLength = story.length;
    _lines = [
      ...story,
      'still looking'.tr,
      'good ones take a moment'.tr,
      'here you go'.tr, // the finale's line — never reached by the timer
    ];
    _scheduleNext();
  }

  /// Index of the last "still looking" line — where the slow loop ends.
  int get _tailEnd => _storyLength + 1;
  int get _finaleIndex => _storyLength + 2;

  @override
  void didUpdateWidget(TaneThinking oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.finale && !oldWidget.finale) _beginFinale();
  }

  void _beginFinale() {
    _timer?.cancel();
    _index = _finaleIndex; // read by the build that follows this update
    _finaleClock.forward(from: 0);
  }

  /// The story, already translated. Every line is a plain string literal
  /// with `.tr` right after it (not looked up from a table), so
  /// tools/l10n/check_missing_translations.py can see each one.
  List<String> _story(LogTheme theme) {
    String pick(List<String> options) => options[_rng.nextInt(options.length)];

    final themed = switch (theme) {
      LogTheme.garden => "looking for what's in bloom".tr,
      LogTheme.coach => 'checking the timetable'.tr,
      LogTheme.ticket => 'tearing off the right ticket'.tr,
      LogTheme.shuttle => 'scanning the orbit'.tr,
    };

    return [
      'reading what you wrote'.tr,
      pick([
        'catching the mood'.tr,
        'thinking it over'.tr,
        'hmm, let me think'.tr,
      ]),
      themed,
      if (widget.hasTimeBudget)
        pick([
          'counting the minutes'.tr,
          'checking runtimes'.tr,
        ]),
      'weighing the candidates'.tr,
      'picking the best few'.tr,
      'almost there'.tr,
    ];
  }

  void _scheduleNext() {
    final slowStretch = _index >= _storyLength - 1;
    _timer = Timer(slowStretch ? _tailStep : _step, () {
      if (!mounted || widget.finale) return;
      setState(() {
        // Past the story, only the two "still looking" lines take turns.
        _index = _index < _tailEnd ? _index + 1 : _storyLength;
      });
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.dispose();
    _finaleClock.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------

  static const _stageSize = Size(176, 128);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // A screen reader gets one steady label, not a new sentence every
    // second.
    return Semantics(
      label: 'tanè is thinking'.tr,
      liveRegion: true,
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: _fadeOut,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 350),
            builder: (context, appear, child) =>
                Opacity(opacity: appear, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stage(reduceMotion),
                const SizedBox(height: 8),
                _line(reduceMotion),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The motif with its halo and sparkles.
  Widget _stage(bool reduceMotion) {
    return SizedBox(
      width: _stageSize.width,
      height: _stageSize.height,
      child: AnimatedBuilder(
        animation: Listenable.merge([_clock, _finaleClock]),
        // The motif itself doesn't depend on our clocks (it runs its own),
        // so it's built once and handed through.
        child: const ThemedLoadingIndicator(size: 56),
        builder: (context, motif) {
          final e = _finaleClock.value; // 0 until the finale
          final pop = math.sin(e * math.pi); // 0→1→0 across it
          return Stack(
            alignment: Alignment.center,
            children: [
              if (!reduceMotion) _halo(e),
              if (!reduceMotion)
                CustomPaint(
                  size: _stageSize,
                  painter: _TwinklePainter(
                    t: _clock.value,
                    color: SeenlyPalette.accent,
                    finale: e,
                  ),
                ),
              // A small "pop" as the ping goes off.
              Transform.scale(
                scale: reduceMotion ? 1.0 : 1 + 0.14 * pop,
                child: motif!,
              ),
            ],
          );
        },
      ),
    );
  }

  /// A round glow that swells and settles once per lap — and flares once
  /// during the finale ([e] is the finale's 0..1 progress).
  Widget _halo(double e) {
    final pulse = 0.5 - 0.5 * math.cos(_clock.value * 2 * math.pi); // 0→1→0
    final pop = math.sin(e * math.pi);
    final size = 92.0 + 18.0 * pulse + 34.0 * e;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            SeenlyPalette.accent.withOpacity(0.11 + 0.06 * pulse + 0.16 * pop),
            SeenlyPalette.accent.withOpacity(0),
          ],
        ),
      ),
    );
  }

  /// The words. The whole line sits under a [ShaderMask] so the sweep of
  /// colour crosses text and dots alike; the text itself is drawn white and
  /// the mask decides what colour it actually ends up.
  Widget _line(bool reduceMotion) {
    final style = SeenlyText.serif(size: 15, color: Colors.white);

    return SizedBox(
      height: 30,
      child: AnimatedBuilder(
        animation: _clock,
        // The switcher only rebuilds on setState (a new line), not on every
        // tick of the clock — only the mask's gradient moves per frame.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            if (reduceMotion) {
              return FadeTransition(opacity: animation, child: child);
            }
            // New line rises in from below; the old one leaves upward.
            final incoming = child.key == ValueKey<int>(_index);
            final slide = Tween<Offset>(
              begin: Offset(0, incoming ? 0.45 : -0.45),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          // FittedBox: a long line on a narrow phone shrinks instead of
          // overflowing.
          child: FittedBox(
            key: ValueKey<int>(_index),
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_lines[_index], style: style),
                // "here you go" doesn't trail off.
                if (_index != _finaleIndex) ...[
                  const SizedBox(width: 5),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: _HoppingDots(clock: _clock, still: reduceMotion),
                  ),
                ],
              ],
            ),
          ),
        ),
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => _sweep(rect, reduceMotion),
          child: child,
        ),
      ),
    );
  }

  /// Muted ink with a band of accent colour travelling left to right — it
  /// starts and ends off the edge, so between laps the line rests in its
  /// plain colour.
  Shader _sweep(Rect rect, bool reduceMotion) {
    final base = SeenlyPalette.inkMuted;
    if (reduceMotion) {
      return LinearGradient(colors: [base, base]).createShader(rect);
    }
    double s(double v) => v.clamp(0.0, 1.0);
    final centre = _clock.value * 1.7 - 0.35;
    return LinearGradient(
      colors: [base, SeenlyPalette.accent, base],
      stops: [s(centre - 0.24), s(centre), s(centre + 0.24)],
    ).createShader(rect);
  }
}

/// Three dots that hop one after another: the "still working" ellipsis.
class _HoppingDots extends StatelessWidget {
  final Animation<double> clock;
  final bool still;

  const _HoppingDots({required this.clock, required this.still});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final t = (clock.value * 2) % 1.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              _dot(still ? 0.0 : _bump(t, i)),
            ],
          ],
        );
      },
    );
  }

  /// 0→1→0 over the first 45 % of this dot's lap, then flat; each dot's lap
  /// starts a little after the previous one's.
  static double _bump(double t, int i) {
    final p = (t - i * 0.14) % 1.0;
    return p < 0.45 ? math.sin(p / 0.45 * math.pi) : 0.0;
  }

  Widget _dot(double bump) {
    return Transform.translate(
      offset: Offset(0, -3.5 * bump),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5 + 0.5 * bump),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Three four-point sparkles around the motif, each twinkling once per
/// lap, a third of a lap apart.
///
/// During the finale ([finale], 0..1) they stop drifting around: all three
/// light up and fly in to the centre (first 70 %), vanish, and a thin ring
/// pings outward from where they met (from 55 % on).
class _TwinklePainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  final double finale; // 0..1, 0 = not in the finale

  const _TwinklePainter({
    required this.t,
    required this.color,
    this.finale = 0,
  });

  // (x, y as fractions of half the stage from its centre, phase 0..1,
  // full radius in logical pixels)
  static const _spots = <(double, double, double, double)>[
    (-0.64, -0.52, 0.00, 6.0),
    (0.68, -0.18, 0.34, 4.5),
    (0.42, 0.62, 0.67, 3.5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final gather = Curves.easeInCubic.transform((finale / 0.7).clamp(0.0, 1.0));
    final vanish = 1 - ((finale - 0.7) / 0.3).clamp(0.0, 1.0);

    for (final (fx, fy, phase, radius) in _spots) {
      final local = (t - phase) % 1.0;
      final k = math.sin(local * math.pi); // 0→1→0 across the lap
      final lit = math.max(k * k, gather);
      if (lit * vanish < 0.03) continue;
      final home = centre + Offset(fx * size.width / 2, fy * size.height / 2);
      _paintStar(
        canvas,
        Offset.lerp(home, centre, gather)!,
        radius * (0.35 + 0.65 * lit) * (1 + 0.5 * gather),
        Paint()..color = color.withOpacity((0.2 + 0.6 * lit) * vanish),
      );
    }

    if (finale > 0.55) {
      final p = Curves.easeOutCubic.transform(((finale - 0.55) / 0.45).clamp(0.0, 1.0));
      canvas.drawCircle(
        centre,
        size.shortestSide * (0.16 + 0.30 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.4 + 1.8 * (1 - p)
          ..color = color.withOpacity(0.45 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TwinklePainter old) =>
      old.t != t || old.color != color || old.finale != finale;
}

/// The four-point sparkle (✦), for other screens that want the same glyph
/// in a burst of their own. [radius] is the distance from the middle to
/// each tip.
void paintSparkle(Canvas canvas, Offset centre, double radius, Paint paint) =>
    _paintStar(canvas, centre, radius, paint);

/// A concave four-point star — the shape of the ✦ / auto-awesome glyph.
void _paintStar(Canvas canvas, Offset c, double r, Paint paint) {
  final path = Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
    ..close();
  canvas.drawPath(path, paint);
}

/// One-shot burst of sparkles for the moment the answer lands: drop it as
/// the last child of the top pick's card (it fills its parent and ignores
/// touches). Nine ✦ fly out from the middle of the card and fade, once —
/// the "arrival" half of the hand-off that [TaneThinking]'s finale starts.
/// Does nothing when the system asks for reduced motion.
class TaneArrivalBurst extends StatefulWidget {
  /// Waits this long before going off, so it lines up with the card
  /// finishing its own fade-in.
  final Duration delay;

  const TaneArrivalBurst({
    super.key,
    this.delay = const Duration(milliseconds: 140),
  });

  @override
  State<TaneArrivalBurst> createState() => _TaneArrivalBurstState();
}

class _TaneArrivalBurstState extends State<TaneArrivalBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _delay = Timer(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _BurstPainter(
            t: _c.value,
            light: SeenlyPalette.paper,
            warm: SeenlyPalette.mustard,
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double t; // 0..1
  final Color light;
  final Color warm;

  const _BurstPainter({required this.t, required this.light, required this.warm});

  static const _count = 9;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final centre = Offset(size.width * 0.5, size.height * 0.46);
    final reach = size.width * 0.44;
    final life = math.sin(math.pi * math.pow(t, 0.75)); // 0→1→0

    for (int i = 0; i < _count; i++) {
      final angle = i / _count * 2 * math.pi + 0.35;
      // Each sparkle flies at its own speed (0.6..1.0 of full reach), so
      // the ring doesn't look stamped out.
      final speed = 0.6 + 0.4 * (((i * 7) % 5) / 4);
      final travel = Curves.easeOutCubic.transform(t) * reach * speed;
      // The card is wide, not tall — squash the burst to match.
      final pos = centre +
          Offset(math.cos(angle) * travel, math.sin(angle) * travel * 0.55);
      final radius = (3.0 + (i % 3) * 1.6) * (0.4 + 0.6 * life);
      _paintStar(
        canvas,
        pos,
        radius,
        Paint()..color = (i.isEven ? light : warm).withOpacity(0.85 * life),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}
