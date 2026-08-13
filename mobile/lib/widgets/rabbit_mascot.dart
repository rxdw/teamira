import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// The rabbit's "mood" — always the same drawing, never a different
/// face. Each mood is a different soft motion (and, for [sad] and
/// [celebrating], a couple of small separately-drawn accents) layered
/// on top of the one asset, so the character itself never looks
/// redrawn or inconsistent from screen to screen.
enum RabbitMood {
  /// Gentle idle bob. The default, used wherever the rabbit is just
  /// keeping company (onboarding, settings preview).
  content,

  /// Slower, smaller motion, tilted forward, with a single soft
  /// teardrop — for empty states.
  sad,

  /// A happy little bounce with a few soft sparkles — for finishing a
  /// ritual, unlocking an achievement, that kind of moment.
  celebrating,

  /// Same idle bob as [content], plus a small ticket-like card sliding
  /// in and out of the booklet in its paws — for loading states.
  loading,
}

/// The rabbit companion, reused everywhere — always the same popcorn
/// bunny drawing (assets/mascot/bunny_with_popcorn_level1.png). Only
/// [mood] (a soft animation, never a different drawing per se) and
/// [size] change per call site.
///
/// Screens should check `context.watch<RabbitMascotPrefsService>().enabled`
/// themselves and simply not place this widget (or fall back to their
/// normal look) when it's off, so a disabled mascot never leaves a gap.
class RabbitMascot extends StatefulWidget {
  final RabbitMood mood;
  final double size;

  const RabbitMascot({super.key, this.mood = RabbitMood.content, this.size = 96});

  @override
  State<RabbitMascot> createState() => _RabbitMascotState();
}

class _RabbitMascotState extends State<RabbitMascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: switch (widget.mood) {
      RabbitMood.sad => const Duration(milliseconds: 4800),
      RabbitMood.celebrating => const Duration(milliseconds: 1700),
      RabbitMood.content || RabbitMood.loading => const Duration(milliseconds: 3400),
    },
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/mascot/bunnyDark_with_popcorn_level1.png'
        : 'assets/mascot/bunny_with_popcorn_level1.png';
    // The source art (742x1153) has a lot of transparent padding
    // around the drawing itself, so this crops in on it — the box
    // callers laid out against ([s] wide) is untouched, only the
    // bunny within it grows to fill more of that space.
    const artFillFraction = 0.94;
    const artContentHeightFrac = 903 / 1153;
    const cropScale = artFillFraction / artContentHeightFrac;
    final height = s / (742 / 1153);
    return SizedBox(
      width: s,
      height: height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          switch (widget.mood) {
            case RabbitMood.content:
              return _idleBob(t: t, s: s, child: child!);

            case RabbitMood.loading:
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  _idleBob(t: t, s: s, child: child!),
                  Positioned(
                    bottom: s * 0.14,
                    child: _TicketPeek(t: t, size: s),
                  ),
                ],
              );

            case RabbitMood.sad:
              // A slow, heavy sigh: settles low, tilts forward, shrinks
              // in on itself slightly — then eases back up. Eased with
              // a soft cosine rather than a linear droop so it lingers
              // at the bottom instead of ticking metronome-style.
              final settle = 0.5 - 0.5 * math.cos(t * 2 * math.pi); // 0..1..0, slow at both ends
              final droop = settle * s * 0.05;
              final tilt = -0.03 - settle * 0.05;
              final scale = 1 - settle * 0.035;
              return Transform.translate(
                offset: Offset(0, droop),
                child: Transform.rotate(
                  angle: tilt,
                  child: Transform.scale(
                    scale: scale,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        child!,
                        Positioned(
                          right: s * 0.30,
                          top: s * 0.32,
                          child: _FallingTear(t: t, size: s * 0.075),
                        ),
                      ],
                    ),
                  ),
                ),
              );

            case RabbitMood.celebrating:
              // A real hop rather than a sine wobble: height follows a
              // smooth cosine hump — fast off the ground, slow at the
              // peak, and easing to a standstill at ground contact
              // instead of reversing direction instantly, so the loop
              // doesn't feel like it snaps. The body still squashes on
              // contact and stretches at the top, the classic
              // hand-animation cue.
              final hop = (1 - math.cos(2 * math.pi * t)) / 2; // 0 at ground, 1 at peak, eased both ends
              final bounce = hop * s * 0.11;
              final squashY = 1 - 0.11 + 0.11 * hop; // 0.89 grounded -> 1.00 airborne
              final squashX = 1 + 0.09 - 0.09 * hop; // 1.09 grounded -> 1.00 airborne
              final tilt = (t - 0.5) * 0.06; // a gentler lean into the hop
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  for (final spark in _sparkleSpecs)
                    Positioned(
                      left: s * spark.dx,
                      top: s * spark.dy - bounce * 0.4,
                      child: Transform.scale(
                        scale: 0.7 + 0.3 * ((math.sin(t * 2 * math.pi + spark.phase) + 1) / 2),
                        child: Opacity(
                          opacity: (0.3 + 0.7 * ((math.sin(t * 2 * math.pi + spark.phase) + 1) / 2)),
                          child: _Sparkle(size: s * spark.scale),
                        ),
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(0, -bounce),
                    child: Transform.rotate(
                      angle: tilt,
                      child: Transform.scale(
                        scaleX: squashX,
                        scaleY: squashY,
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
          }
        },
        child: ClipRect(
          child: Transform.scale(
            scale: cropScale,
            child: Image.asset(
              asset,
              width: s,
              height: height,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  /// The shared idle motion for [RabbitMood.content] and
  /// [RabbitMood.loading]: a gentle up-down bob with a touch of
  /// squash-and-stretch and a whisper of a sway, so it reads as
  /// breathing rather than a robotic vertical slide.
  Widget _idleBob({required double t, required double s, required Widget child}) {
    final wave = math.sin(t * 2 * math.pi); // -1..1
    final bob = wave * s * 0.028;
    final stretch = wave * 0.02; // taller/thinner at the top of the bob
    final sway = wave * 0.018;
    return Transform.translate(
      offset: Offset(0, bob),
      child: Transform.rotate(
        angle: sway,
        child: Transform.scale(
          scaleX: 1 - stretch,
          scaleY: 1 + stretch,
          child: child,
        ),
      ),
    );
  }
}

class _SparkleSpec {
  final double dx, dy, scale, phase;
  const _SparkleSpec(this.dx, this.dy, this.scale, this.phase);
}

const _sparkleSpecs = [
  _SparkleSpec(0.04, 0.10, 0.11, 0),
  _SparkleSpec(0.80, 0.04, 0.09, 1.4),
  _SparkleSpec(0.86, 0.42, 0.08, 2.6),
  _SparkleSpec(-0.02, 0.46, 0.09, 3.6),
];

class _Sparkle extends StatelessWidget {
  final double size;
  const _Sparkle({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _SparklePainter());
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SeenlyPalette.mustard;
    final cx = size.width / 2, cy = size.height / 2;
    final path = Path()
      ..moveTo(cx, 0)
      ..lineTo(cx + size.width * 0.16, cy - size.height * 0.16)
      ..lineTo(size.width, cy)
      ..lineTo(cx + size.width * 0.16, cy + size.height * 0.16)
      ..lineTo(cx, size.height)
      ..lineTo(cx - size.width * 0.16, cy + size.height * 0.16)
      ..lineTo(0, cy)
      ..lineTo(cx - size.width * 0.16, cy - size.height * 0.16)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => false;
}

/// A single tear that wells up, falls, and fades — instead of a static
/// drop just flickering in place. Runs on the same clock as the sad
/// mood's sigh so the two feel like one gesture rather than two
/// independent loops.
class _FallingTear extends StatelessWidget {
  final double t;
  final double size;
  const _FallingTear({required this.t, required this.size});

  @override
  Widget build(BuildContext context) {
    // 0.00-0.15  well up (grow in, still)
    // 0.15-0.75  fall, fading out toward the end
    // 0.75-1.00  gone, waiting for the next well-up
    double opacity;
    double fall;
    double scale;
    if (t < 0.15) {
      final localT = t / 0.15;
      opacity = Curves.easeOut.transform(localT);
      scale = 0.6 + 0.4 * Curves.easeOut.transform(localT);
      fall = 0;
    } else if (t < 0.75) {
      final localT = (t - 0.15) / 0.60;
      opacity = 1 - Curves.easeIn.transform(localT) * 0.9;
      scale = 1;
      fall = Curves.easeIn.transform(localT);
    } else {
      opacity = 0;
      scale = 1;
      fall = 1;
    }
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, fall * size * 1.6),
        child: Transform.scale(
          scale: scale,
          child: CustomPaint(size: Size(size, size * 1.3), painter: _TeardropPainter()),
        ),
      ),
    );
  }
}

class _TeardropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SeenlyPalette.periwinkle.withOpacity(0.85);
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..quadraticBezierTo(size.width, size.height * 0.55, size.width / 2, size.height)
      ..quadraticBezierTo(0, size.height * 0.55, size.width / 2, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TeardropPainter oldDelegate) => false;
}

/// A small paper-coloured card that slides up out of the booklet in the
/// rabbit's paws and back down, like it's flipping through a page —
/// used only for [RabbitMood.loading]. Eased and given a brief pause at
/// the top (rather than a pure sine peek) so it reads as a deliberate
/// flip-and-check instead of a bobbing float.
class _TicketPeek extends StatelessWidget {
  final double t;
  final double size;
  const _TicketPeek({required this.t, required this.size});

  @override
  Widget build(BuildContext context) {
    // 0.00-0.35  rise
    // 0.35-0.55  hold at the top
    // 0.55-0.90  fall
    // 0.90-1.00  hold at the bottom
    double phase;
    if (t < 0.35) {
      phase = Curves.easeOutCubic.transform(t / 0.35);
    } else if (t < 0.55) {
      phase = 1;
    } else if (t < 0.90) {
      phase = 1 - Curves.easeInCubic.transform((t - 0.55) / 0.35);
    } else {
      phase = 0;
    }
    final rise = phase * size * 0.11;
    final tilt = (1 - phase) * 0.06;
    return Transform.translate(
      offset: Offset(0, -rise),
      child: Transform.rotate(
        angle: tilt,
        child: Container(
          width: size * 0.16,
          height: size * 0.10,
          decoration: BoxDecoration(
            color: const Color(0xFFF1E9D8),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: SeenlyPalette.ink, width: 1),
          ),
        ),
      ),
    );
  }
}
