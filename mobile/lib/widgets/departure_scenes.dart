import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart' show DustPainter, LightMote, flashOpacity, seededMotes;
import '../services/app_translations.dart';

/// The shared "moment locked in" beat: every scene holds its breath for
/// an instant right before the save lands — the camera creeps very
/// slightly closer, as if time itself is dragging — and then everything
/// eases outward on a gentle, rounded curve while a warm bloom of light
/// spreads outward from the center rather than a hard flash covering the
/// whole screen. This is what reads as "the moment locked in" rather
/// than just a fade; everything after this point is already on its way
/// out.
///
/// `_cinematicScale` drives a `Transform.scale` wrapped around each
/// scene's whole stage; `_cinematicGlow` drives a soft radial-gradient
/// bloom layered on top of it, warmer and gentler than a flat white
/// overlay. Both are pure functions of the same `t` (0..1) every
/// scene's one-shot controller already produces, so the three scenes
/// stay perfectly in sync with each other and with the save they're
/// covering.
double _cinematicScale(double t) {
  if (t < 0.58) return 1.0;
  if (t < 0.80) {
    // The slow creep-in — deliberately sluggish (easeInExpo barely
    // moves at first) so the last stretch before the snap feels like
    // it's dragging, the way the last second before a countdown does.
    final creepT = ((t - 0.58) / 0.22).clamp(0.0, 1.0).toDouble();
    return 1.0 + Curves.easeInExpo.transform(creepT) * 0.04;
  }
  // The release itself — a soft, rounded ease outward rather than a
  // hard overshooting punch, so the beat lands like a slow exhale
  // instead of a jolt.
  final releaseT = ((t - 0.80) / 0.20).clamp(0.0, 1.0).toDouble();
  return 1.04 + Curves.easeOutCubic.transform(releaseT) * 0.07;
}

double _cinematicGlow(double t) {
  final riseT = ((t - 0.76) / 0.10).clamp(0.0, 1.0).toDouble();
  final rise = Curves.easeOutCubic.transform(riseT);
  final fallT = ((t - 0.85) / 0.30).clamp(0.0, 1.0).toDouble();
  final fall = Curves.easeInCubic.transform(fallT);
  return (rise * (1 - fall)).clamp(0.0, 1.0).toDouble();
}

/// The burst's own progress — starts a beat after the glow begins
/// rising (so the rays read as blooming *out of* the light rather than
/// arriving alongside it) and lingers a little longer as it fades, for
/// a soft trailing sparkle rather than everything vanishing at once.
double _cinematicBurst(double t) {
  final riseT = ((t - 0.80) / 0.08).clamp(0.0, 1.0).toDouble();
  final rise = Curves.easeOutCubic.transform(riseT);
  final fallT = ((t - 0.88) / 0.34).clamp(0.0, 1.0).toDouble();
  final fall = Curves.easeInCubic.transform(fallT);
  return (rise * (1 - fall)).clamp(0.0, 1.0).toDouble();
}

/// Wraps a scene's content with the shared push-in and returns it
/// alongside the glow and light-burst overlay, so every `build()`
/// below only needs one line instead of repeating the Stack/Transform
/// boilerplate.
Widget cinematicSnap(double t, Widget child) {
  final glow = _cinematicGlow(t);
  final burst = _cinematicBurst(t);
  return Stack(
    fit: StackFit.passthrough,
    children: [
      Transform.scale(scale: _cinematicScale(t), alignment: Alignment.center, child: child),
      if (burst > 0.001)
        IgnorePointer(
          child: Positioned.fill(
            child: CustomPaint(painter: _LightBurstPainter(t: burst)),
          ),
        ),
      IgnorePointer(
        child: Opacity(
          opacity: glow,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.1,
                colors: [
                  SeenlyPalette.paper.withOpacity(0.92),
                  SeenlyPalette.mustard.withOpacity(0.55),
                  SeenlyPalette.mustard.withOpacity(0.0),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// A soft burst of light rays and scattered sparkles radiating from
/// center — the little bit of sparkle that turns the glow from "a
/// light came on" into "something caught and shimmered." The ray
/// angles and sparkle positions come from a fixed seed so the pattern
/// is stable frame to frame (this paints every tick while `t` rises
/// and falls) rather than jittering.
class _LightBurstPainter extends CustomPainter {
  final double t; // 0..1, this beat's own progress
  const _LightBurstPainter({required this.t});

  static final List<double> _rayAngles = List.generate(
    12,
    (i) => (i / 12) * math.pi * 2 + (math.Random(7).nextDouble() - 0.5) * 0.18,
  );
  static final List<Offset> _sparkles = List.generate(
    16,
    (i) {
      final r = math.Random(101 + i);
      final angle = r.nextDouble() * math.pi * 2;
      final dist = 0.15 + r.nextDouble() * 0.85;
      return Offset(math.cos(angle) * dist, math.sin(angle) * dist);
    },
  );

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxLen = size.shortestSide * 0.6;
    final easedT = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));

    // Rays — thin, tapered streaks radiating outward, longest right at
    // the peak and never reaching all the way to the edges so they
    // read as light, not spokes on a wheel.
    for (final angle in _rayAngles) {
      final len = maxLen * (0.35 + 0.65 * easedT);
      final end = center + Offset(math.cos(angle), math.sin(angle)) * len;
      final rayPaint = Paint()
        ..shader = LinearGradient(
          colors: [SeenlyPalette.paper.withOpacity(0.55 * t), SeenlyPalette.paper.withOpacity(0)],
        ).createShader(Rect.fromPoints(center, end))
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, end, rayPaint);
    }

    // Sparkles — small points scattered outward from center, each
    // twinkling on its own phase so the field feels alive rather than
    // a static dusting.
    for (int i = 0; i < _sparkles.length; i++) {
      final dir = _sparkles[i];
      final travel = maxLen * 0.9 * easedT;
      final pos = center + Offset(dir.dx, dir.dy) * travel;
      final twinkle = (0.5 + 0.5 * math.sin(t * math.pi * 5 + i * 1.7)).clamp(0.0, 1.0);
      final opacity = (t * twinkle).clamp(0.0, 1.0).toDouble();
      if (opacity <= 0.02) continue;
      final r = 1.4 + 1.6 * twinkle;
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = SeenlyPalette.paper.withOpacity(opacity * 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LightBurstPainter oldDelegate) => oldDelegate.t != t;
}



/// The pre-confirm beat shared by all three logging rituals: the
/// instant "confirm boarding" / "confirm ticket" / "confirm planting"
/// is tapped, the screen doesn't just hard-cut to the result — it
/// plays one small, theme-true scene first (about 1.6s, timed to
/// roughly cover the save request itself), so the save always lands
/// on something that was already settling into place rather than a
/// blank wait. Each scene is a StatefulWidget with its own one-shot
/// controller — drop it straight in as a step's content, same as any
/// other `_buildXStep()` in the surrounding screen.
///
/// Each stage now fills essentially the whole remaining screen (via
/// `Expanded` + `LayoutBuilder`) rather than a small fixed-pixel box,
/// so it reads as a real scene the person is inside of, not a little
/// illustration floating on a plain background. A `scale` factor
/// derived from the available width keeps every glyph proportioned
/// on both small phones and big tablets. Every theme also carries one
/// extra "world" layer beyond its main glyph — a skyline for the
/// coach, a room full of seats for the cinema, a bloom and a swarm of
/// fireflies for the garden — so the three read as distinct places,
/// not the same shape recolored three times.

/// Coach theme: dusk sky overhead, a drifting skyline behind it, and
/// the train itself pulling out of the station past platform lamps and
/// a converging railway track.
class TrainDepartureScene extends StatefulWidget {
  final String routeLabel;
  const TrainDepartureScene({super.key, required this.routeLabel});

  @override
  State<TrainDepartureScene> createState() => _TrainDepartureSceneState();
}

class _TrainDepartureSceneState extends State<TrainDepartureScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<LightMote> _motes;
  late final List<double> _skyline;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
      ..forward();
    _motes = seededMotes(widget.routeLabel, 14, salt: 0x747261); // 'tra'
    final r = math.Random(widget.routeLabel.hashCode ^ 0x736B79); // 'sky'
    _skyline = List.generate(11, (_) => 0.16 + r.nextDouble() * 0.42);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final headlight = flashOpacity(t, riseEnd: 0.28);
        final driveT = Curves.easeInOutCubic.transform(((t - 0.22) / 0.78).clamp(0.0, 1.0).toDouble());
        final sceneFade = 1 - Curves.easeIn.transform(((t - 0.78) / 0.22).clamp(0.0, 1.0).toDouble());
        return cinematicSnap(
          t,
          SizedBox.expand(
          child: Column(
            key: const ValueKey('train-departure-scene'),
            children: [
              const SizedBox(height: 22),
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  final scale = (w / 300).clamp(1.0, 2.0).toDouble();
                  final dx = driveT * w * 0.42;
                  return ClipRect(
                    child: Opacity(
                      opacity: sceneFade.clamp(0.0, 1.0).toDouble(),
                      child: SizedBox.expand(
                        child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Dusk-to-night sky, full-bleed behind everything.
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  const Color(0xFF241C33).withOpacity(0.0),
                                  SeenlyPalette.mustard.withOpacity(0.10 + 0.06 * headlight),
                                ],
                              ),
                            ),
                          ),
                          // A drifting skyline behind the track, so the
                          // train reads as leaving a whole town, not a
                          // blank stage.
                          Positioned(
                            left: -driveT * w * 0.12,
                            right: -40,
                            bottom: h * 0.30,
                            height: h * 0.24,
                            child: CustomPaint(painter: _SkylinePainter(heights: _skyline)),
                          ),
                          // Warm halo breathing with the headlight.
                          Positioned(
                            left: w * 0.5 - 110 * scale + dx * 0.35,
                            top: h * 0.22,
                            child: Container(
                              width: 220 * scale,
                              height: 220 * scale,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    SeenlyPalette.mustard.withOpacity(0.18 + 0.14 * headlight),
                                    SeenlyPalette.mustard.withOpacity(0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Platform lamps repeating across the whole width,
                          // gliding past slower than the train for parallax
                          // depth.
                          for (int i = 0; i < 6; i++)
                            Positioned(
                              left: ((i * (w / 4)) - driveT * w * 0.3) % (w + 80) - 60,
                              bottom: h * 0.30,
                              child: Opacity(
                                opacity: 0.5,
                                child: _LampPost(lit: headlight, scale: scale * (0.85 + 0.3 * (i % 2))),
                              ),
                            ),
                          Positioned.fill(
                            child: CustomPaint(painter: DustPainter(t: t, motes: _motes)),
                          ),
                          // A converging railway track for real depth
                          // instead of a flat strip.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: h * 0.34,
                            child: CustomPaint(painter: _RailPainter(t: driveT)),
                          ),
                          // Faint speed streaks trailing the train.
                          for (int i = 1; i <= 4; i++)
                            Positioned(
                              left: w * 0.5 + dx - i * 30 * scale,
                              bottom: h * 0.30,
                              child: Opacity(
                                opacity: (0.18 - i * 0.04).clamp(0.0, 1.0).toDouble(),
                                child: Container(
                                  width: 38 * scale,
                                  height: 6 * scale,
                                  decoration: BoxDecoration(
                                    color: SeenlyPalette.paper.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: w * 0.5 - 76 * scale + dx,
                            bottom: h * 0.28,
                            // A small rumble riding on the rails — only
                            // once the train is actually moving, so it
                            // doesn't twitch while still standing at
                            // the platform.
                            child: Transform.translate(
                              offset: Offset(0, math.sin(t * math.pi * 18) * 1.6 * driveT),
                              child: _TrainGlyph(headlightGlow: headlight, scale: scale),
                            ),
                          ),
                        ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
            ],
          ),
          ),
        );
      },
    );
  }
}

class _SkylinePainter extends CustomPainter {
  final List<double> heights;
  const _SkylinePainter({required this.heights});

  @override
  void paint(Canvas canvas, Size size) {
    if (heights.isEmpty) return;
    final paint = Paint()..color = SeenlyPalette.ink.withOpacity(0.30);
    final buildingW = size.width / (heights.length - 2);
    for (int i = 0; i < heights.length; i++) {
      final bh = size.height * heights[i];
      final x = (i - 1) * buildingW;
      canvas.drawRect(Rect.fromLTWH(x, size.height - bh, buildingW * 0.82, bh), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SkylinePainter oldDelegate) => false;
}

class _LampPost extends StatelessWidget {
  final double lit;
  final double scale;
  const _LampPost({required this.lit, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: 20,
        height: 100,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 10,
              child: Container(width: 3, height: 90, color: SeenlyPalette.paper.withOpacity(0.26)),
            ),
            Positioned(
              top: 0,
              child: Opacity(
                opacity: (0.5 + lit * 0.5).clamp(0.0, 1.0).toDouble(),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFE9A8),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFFFE9A8).withOpacity(0.7), blurRadius: 16, spreadRadius: 4),
                    ],
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

/// A proper railway in perspective: a ballast bed narrowing toward the
/// horizon, sleepers (ties) crossing it that widen and space out as
/// they near the viewer, and two bright rails converging to a vanishing
/// point — reads as steel track at a glance, not a repainted road.
class _RailPainter extends CustomPainter {
  final double t;
  const _RailPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final bed = Paint()..color = SeenlyPalette.ink.withOpacity(0.22);
    final bedPath = Path()
      ..moveTo(size.width * 0.5 - size.width * 0.08, 0)
      ..lineTo(size.width * 0.5 + size.width * 0.08, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(bedPath, bed);

    // Sleepers — perpendicular bars crossing the bed, closer together
    // and thinner near the horizon, wider and thicker near the viewer,
    // scrolling forward on the same rhythm the old dashed centerline did.
    final tiePaint = Paint()..color = SeenlyPalette.ink.withOpacity(0.30);
    final shift = (t * 0.9) % 0.09;
    for (double frac = -shift; frac < 1.0; frac += 0.09) {
      if (frac < 0) continue;
      final eased = frac * frac; // bunches ties toward the horizon
      final y = size.height * eased;
      final halfW = size.width * (0.09 + 0.24 * eased);
      final tieH = 2.4 + 5.0 * eased;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(size.width * 0.5, y), width: halfW * 2, height: tieH),
        tiePaint,
      );
    }

    // The two rails themselves, bright steel lines converging to a
    // point at the horizon.
    final railPaint = Paint()
      ..color = SeenlyPalette.paper.withOpacity(0.5)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.5 - size.width * 0.026, 0),
      Offset(size.width * 0.09, size.height),
      railPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5 + size.width * 0.026, 0),
      Offset(size.width * 0.91, size.height),
      railPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RailPainter oldDelegate) => oldDelegate.t != t;
}

/// The train itself — a real curved nose instead of a boxy rectangle
/// (painted rather than built from stacked Containers, so the front can
/// taper the way an actual railcar's cab does), a pantograph reaching
/// up off the roof, a row of lit windows, and wheels tucked in close
/// together the way a train's bogies sit, rather than a bus's two
/// wide-set wheels.
class _TrainGlyph extends StatelessWidget {
  final double headlightGlow;
  final double scale;
  const _TrainGlyph({required this.headlightGlow, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      alignment: Alignment.bottomLeft,
      child: SizedBox(
        width: 172,
        height: 92,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: SizedBox(height: 54, child: CustomPaint(painter: _TrainBodyPainter())),
            ),
            // The pantograph — the one silhouette detail that reads
            // "train" at a glance rather than "bus".
            Positioned(
              left: 62,
              bottom: 14 + 54 - 5,
              child: CustomPaint(size: const Size(28, 20), painter: _PantographPainter()),
            ),
            Positioned(left: 18, top: 12, child: _windowGlow(intensity: 0.9)),
            Positioned(left: 50, top: 12, child: _windowGlow(intensity: 1.0)),
            Positioned(left: 82, top: 12, child: _windowGlow(intensity: 0.94)),
            // The nose's own small angled window, right where the roof
            // starts tapering into the point.
            Positioned(left: 122, top: 14, child: _windowGlow(width: 13, intensity: 0.8)),
            // Headlight — a soft outer bloom behind a small bright core,
            // rather than one flat circle with a blur shadow, so it
            // reads as a lit glass lamp instead of a glowing dot.
            Positioned(
              right: -8,
              top: 24,
              child: Opacity(
                opacity: (0.4 + headlightGlow * 0.6).clamp(0.0, 1.0).toDouble(),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFFFFE9A8).withOpacity(0.55),
                              const Color(0xFFFFE9A8).withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFFF6DD),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFFFFE9A8).withOpacity(0.9), blurRadius: 14, spreadRadius: 3),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -56,
              top: 35,
              child: Opacity(
                opacity: (headlightGlow * 0.55).clamp(0.0, 1.0).toDouble(),
                child: Container(
                  width: 60,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                      colors: [const Color(0xFFFFE9A8).withOpacity(0.55), const Color(0xFFFFE9A8).withOpacity(0.0)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(left: 24, bottom: 0, child: _bogie()),
            Positioned(right: 24, bottom: 0, child: _bogie()),
          ],
        ),
      ),
    );
  }

  Widget _windowGlow({double width = 24, double intensity = 1.0}) => Container(
        width: width,
        height: 20,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.5),
            colors: [
              const Color(0xFFFFFCF0).withOpacity(0.95 * intensity),
              const Color(0xFFFFE9C2).withOpacity(0.85 * intensity),
              const Color(0xFFF3CE8A).withOpacity(0.55 * intensity),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: SeenlyPalette.ink.withOpacity(0.16), width: 0.8),
          boxShadow: [
            BoxShadow(color: const Color(0xFFFFE9C2).withOpacity(0.45 * intensity), blurRadius: 10, spreadRadius: 1.5),
          ],
        ),
      );

  Widget _bogie() => SizedBox(
        width: 28,
        height: 18,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // A soft grounding shadow so the wheels read as touching
            // the rail rather than floating under the body.
            Positioned(
              left: 1,
              bottom: 0,
              child: Container(
                width: 26,
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: SeenlyPalette.ink.withOpacity(0.20),
                ),
              ),
            ),
            Positioned(left: 0, top: 0, child: _wheel()),
            Positioned(right: 0, top: 0, child: _wheel()),
          ],
        ),
      );

  Widget _wheel() => Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.35),
            colors: [SeenlyPalette.inkFaint.withOpacity(0.85), SeenlyPalette.ink.withOpacity(0.92)],
          ),
          border: Border.all(color: SeenlyPalette.paper.withOpacity(0.18), width: 0.8),
        ),
      );
}

/// The carriage's silhouette — a rounded back edge, a straight midsection,
/// and a snub, forward-leaning nose curve at the front (right side, the
/// direction of travel), plus a soft drop shadow and a darker roof band
/// for a bit of real livery detail instead of a flat block of color.
class _TrainBodyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Flat roofline, rounded shoulder at the back (left), tapering to a
    // pointed aerodynamic nose at the front (right) — the same profile
    // as the onboarding train card, instead of a symmetric loaf shape
    // that reads as a toy bus.
    final noseStart = w - h * 0.9;
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.18)
      ..quadraticBezierTo(0, 0, h * 0.32, 0)
      ..lineTo(noseStart, 0)
      ..cubicTo(
        noseStart + (w - noseStart) * 0.55,
        0,
        w,
        h * 0.3,
        w,
        h * 0.62,
      )
      ..quadraticBezierTo(w, h, w - h * 0.18, h)
      ..close();

    canvas.save();
    canvas.translate(0, 9);
    canvas.drawPath(
      path,
      Paint()
        ..color = SeenlyPalette.ink.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );
    canvas.restore();

    // A shaded metallic body — a warm highlight along the roofline
    // settling into the base mustard and deepening toward the
    // undercarriage, rather than one flat fill, so the livery reads
    // as painted steel catching evening light.
    final hsl = HSLColor.fromColor(SeenlyPalette.mustard);
    final topColor = hsl.withLightness((hsl.lightness + 0.20).clamp(0.0, 1.0)).toColor();
    final bottomColor = hsl.withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0)).toColor();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, SeenlyPalette.mustard, bottomColor],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.16), Paint()..color = SeenlyPalette.ink.withOpacity(0.14));
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.62, w, h * 0.1),
      Paint()..color = SeenlyPalette.ink.withOpacity(0.10),
    );

    // A diagonal specular sweep — the one bit of shine that sells
    // "lit, three-dimensional surface" rather than a flat cutout.
    final shinePath = Path()
      ..moveTo(w * 0.08, h)
      ..lineTo(w * 0.24, 0)
      ..lineTo(w * 0.36, 0)
      ..lineTo(w * 0.20, h)
      ..close();
    canvas.drawPath(
      shinePath,
      Paint()
        ..shader = LinearGradient(
          colors: [
            SeenlyPalette.paper.withOpacity(0.0),
            SeenlyPalette.paper.withOpacity(0.30),
            SeenlyPalette.paper.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // A cool tinted windshield right at the nose, so the tapered front
    // reads as glass rather than a plain wall of body color.
    canvas.drawRect(
      Rect.fromLTWH(
        noseStart + (w - noseStart) * 0.22,
        h * 0.08,
        (w - noseStart) * 0.62,
        h * 0.42,
      ),
      Paint()..color = SeenlyPalette.ink.withOpacity(0.20),
    );

    canvas.restore();

    // A thin, brighter contour along the top edge — the rim catching
    // the most light on a rounded metal surface.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = topColor.withOpacity(0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _TrainBodyPainter oldDelegate) => false;
}

/// A small diamond pantograph on the roof — two legs meeting a contact
/// bar, drawn as plain strokes so it stays a light silhouette rather
/// than competing with the body for attention.
class _PantographPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final legPaint = Paint()
      ..color = SeenlyPalette.ink.withOpacity(0.55)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final baseX = size.width * 0.5;
    final barY = size.height * 0.32;
    canvas.drawLine(Offset(baseX - 7, size.height), Offset(baseX - 1.5, barY), legPaint);
    canvas.drawLine(Offset(baseX + 7, size.height), Offset(baseX + 1.5, barY), legPaint);
    canvas.drawLine(
      Offset(baseX - 7, barY),
      Offset(baseX + 7, barY),
      legPaint..strokeWidth = 2.4,
    );
  }

  @override
  bool shouldRepaint(covariant _PantographPainter oldDelegate) => false;
}

/// Cinema theme: a whole little theatre — rows of seats grounding the
/// foreground, curtains parting at either side, a spotlight sweeping
/// down, and the screen itself catching light and switching on.
class ScreenIgniteScene extends StatefulWidget {
  const ScreenIgniteScene({super.key});

  @override
  State<ScreenIgniteScene> createState() => _ScreenIgniteSceneState();
}

class _ScreenIgniteSceneState extends State<ScreenIgniteScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<LightMote> _motes;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
      ..forward();
    _motes = seededMotes('screen-ignite', 16, salt: 0x63696E65); // 'cine'
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final widthT = Curves.easeOutCubic.transform((t / 0.35).clamp(0.0, 1.0).toDouble());
        final heightT = Curves.easeOutCubic.transform(((t - 0.3) / 0.42).clamp(0.0, 1.0).toDouble());
        final glow = flashOpacity(t, riseEnd: 0.62);
        final curtainT = Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0).toDouble());
        final beamT = Curves.easeOut.transform((t / 0.5).clamp(0.0, 1.0).toDouble());
        final capT = Curves.easeOut.transform(((t - 0.55) / 0.28).clamp(0.0, 1.0).toDouble());
        final capFade = 1 - Curves.easeIn.transform(((t - 0.82) / 0.18).clamp(0.0, 1.0).toDouble());
        final captionOpacity = (capT * capFade).clamp(0.0, 1.0).toDouble();
        return cinematicSnap(
          t,
          SizedBox.expand(
          child: Column(
            key: const ValueKey('screen-ignite-scene'),
            children: [
              const SizedBox(height: 22),
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  final scale = (w / 300).clamp(1.0, 2.0).toDouble();
                  final screenW = (w * 0.62).clamp(180.0, 460.0);
                  final screenH = screenW * 0.56;
                  return SizedBox.expand(
                    child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // Dark theatre room, full-bleed.
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              SeenlyPalette.ink.withOpacity(0.0),
                              SeenlyPalette.ink.withOpacity(0.35),
                            ],
                          ),
                        ),
                      ),
                      // Spotlight sweeping down from the projector booth.
                      Positioned(
                        top: -20,
                        left: w * 0.5 - (screenW * 0.5) * beamT - 30,
                        child: Opacity(
                          opacity: (beamT * 0.5).clamp(0.0, 1.0).toDouble(),
                          child: ClipPath(
                            clipper: _BeamClipper(),
                            child: Container(
                              width: screenW + 60,
                              height: h * 0.42,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    SeenlyPalette.paper.withOpacity(0.22),
                                    SeenlyPalette.paper.withOpacity(0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Big soft halo behind the screen.
                      Container(
                        width: screenW * 1.5,
                        height: screenH * 2.6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              SeenlyPalette.paper.withOpacity(0.24 * glow),
                              SeenlyPalette.paper.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Opacity(
                          opacity: glow.clamp(0.0, 1.0).toDouble(),
                          child: CustomPaint(painter: DustPainter(t: t, motes: _motes)),
                        ),
                      ),
                      Center(
                        child: SizedBox(
                          width: screenW,
                          height: screenH,
                          child: FractionallySizedBox(
                            widthFactor: (0.04 + 0.96 * widthT).clamp(0.04, 1.0).toDouble(),
                            heightFactor: (0.012 + 0.988 * heightT).clamp(0.012, 1.0).toDouble(),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color.lerp(SeenlyPalette.paper, SeenlyPalette.mustard, 0.14 + 0.22 * glow)!,
                                    SeenlyPalette.paper,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: SeenlyPalette.paper.withOpacity(0.4 * glow),
                                    blurRadius: 60,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Curtains taller than the screen, parting at either
                      // side of the whole stage.
                      Positioned(
                        left: w * 0.5 - screenW * 0.5 - 26 - curtainT * 54 * scale,
                        top: -h * 0.08,
                        bottom: h * 0.18,
                        child: _Curtain(open: curtainT, height: h * 1.1),
                      ),
                      Positioned(
                        right: w * 0.5 - screenW * 0.5 - 26 - curtainT * 54 * scale,
                        top: -h * 0.08,
                        bottom: h * 0.18,
                        child: Transform.flip(flipX: true, child: _Curtain(open: curtainT, height: h * 1.1)),
                      ),
                      // A row of seat-backs grounding the foreground.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: h * 0.16,
                        child: CustomPaint(painter: _SeatRowPainter()),
                      ),
                    ],
                    ),
                  );
                }),
              ),
              const SizedBox(height: 18),
              Opacity(
                opacity: captionOpacity,
                child: Text('the screen comes alive'.tr,
                    style: SeenlyText.serif(italic: true, size: 21, color: SeenlyPalette.paper)),
              ),
              const SizedBox(height: 22),
            ],
          ),
          ),
        );
      },
    );
  }
}

class _BeamClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.42, 0)
      ..lineTo(size.width * 0.58, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _SeatRowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SeenlyPalette.ink.withOpacity(0.4);
    final seatW = size.width / 9;
    for (int i = 0; i < 9; i++) {
      final x = i * seatW;
      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x + seatW * 0.12, size.height * 0.15, seatW * 0.76, size.height * 0.85),
        topLeft: const Radius.circular(7),
        topRight: const Radius.circular(7),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SeatRowPainter oldDelegate) => false;
}

class _Curtain extends StatelessWidget {
  final double open;
  final double height;
  const _Curtain({required this.open, required this.height});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: (0.9 - open * 0.3).clamp(0.0, 1.0).toDouble(),
      child: Container(
        width: 44,
        height: height,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [SeenlyPalette.accent.withOpacity(0.92), SeenlyPalette.accent.withOpacity(0.55)],
          ),
          boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.3), blurRadius: 18, offset: const Offset(5, 0))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(9, (_) => Container(width: 2.5, color: SeenlyPalette.ink.withOpacity(0.1))),
        ),
      ),
    );
  }
}

/// Garden theme: the whole sky eases from dusk into night, a vine
/// climbs and blooms in real time, and a small swarm of fireflies
/// drifts down to settle over the bed.
class GardenDuskScene extends StatefulWidget {
  final String spotLabel;
  const GardenDuskScene({super.key, required this.spotLabel});

  @override
  State<GardenDuskScene> createState() => _GardenDuskSceneState();
}

class _GardenDuskSceneState extends State<GardenDuskScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<Offset> _stars;
  late final List<double> _twinklePhase;
  late final List<double> _fireflyPhase;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
      ..forward();
    final r = math.Random(widget.spotLabel.hashCode ^ 0x64757368); // 'dush'
    _stars = List.generate(22, (_) => Offset(r.nextDouble(), r.nextDouble() * 0.55));
    _twinklePhase = List.generate(22, (_) => r.nextDouble() * math.pi * 2);
    _fireflyPhase = List.generate(3, (_) => r.nextDouble());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final moonT = Curves.easeOutCubic.transform((t / 0.5).clamp(0.0, 1.0).toDouble());
        final starT = Curves.easeOut.transform(((t - 0.15) / 0.55).clamp(0.0, 1.0).toDouble());
        final skyT = Curves.easeInOut.transform(t);
        final growT = Curves.easeOutCubic.transform(((t - 0.08) / 0.55).clamp(0.0, 1.0).toDouble());
        final bloomT = Curves.easeOutBack.transform(((t - 0.55) / 0.4).clamp(0.0, 1.0).toDouble());
        final capT = Curves.easeOut.transform((t / 0.3).clamp(0.0, 1.0).toDouble());
        final capFade = 1 - Curves.easeIn.transform(((t - 0.72) / 0.28).clamp(0.0, 1.0).toDouble());
        final captionOpacity = (capT * capFade).clamp(0.0, 1.0).toDouble();
        final skyTop = Color.lerp(const Color(0xFFD98B5C), const Color(0xFF241C33), skyT)!;
        final skyBottom = Color.lerp(const Color(0xFF7D5A6B), const Color(0xFF1B1526), skyT)!;
        return cinematicSnap(
          t,
          SizedBox.expand(
          child: Column(
            key: const ValueKey('garden-dusk-scene'),
            children: [
              const SizedBox(height: 22),
              Opacity(
                opacity: captionOpacity,
                child: Text('the bed settles for the night'.tr,
                    style: SeenlyText.serif(italic: true, size: 21, color: SeenlyPalette.paper)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return SizedBox.expand(
                    child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Dusk easing into night, full-bleed.
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [skyTop.withOpacity(0.30), skyBottom.withOpacity(0.14)],
                          ),
                        ),
                      ),
                      for (int i = 0; i < _stars.length; i++)
                        Positioned(
                          left: _stars[i].dx * w,
                          top: _stars[i].dy * h * 0.7,
                          child: Opacity(
                            opacity: (starT *
                                    (0.35 + 0.65 * ((i % 3) / 2)) *
                                    (0.6 + 0.4 * math.sin(t * math.pi * 3 + _twinklePhase[i])))
                                .clamp(0.0, 1.0)
                                .toDouble(),
                            child: Container(
                              width: 2.8,
                              height: 2.8,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.paper),
                            ),
                          ),
                        ),
                      Positioned(
                        right: w * 0.12,
                        top: h * 0.05 + (1 - moonT) * 40,
                        child: Opacity(
                          opacity: moonT.clamp(0.0, 1.0).toDouble(),
                          child: const _MoonGlyph(),
                        ),
                      ),
                      // A vine climbing up from the bed, blooming once it's
                      // reached its height — so the beat lands on the plant
                      // itself, not just an abstract dusk.
                      Positioned(
                        left: w * 0.12,
                        bottom: 0,
                        width: w * 0.5,
                        height: h * 0.86,
                        child: CustomPaint(painter: _VinePainter(growT: growT, bloomT: bloomT.clamp(0.0, 1.2))),
                      ),
                      // A small swarm of fireflies drifting down to settle
                      // over the bed, each with its own soft trailing glow.
                      for (int f = 0; f < _fireflyPhase.length; f++)
                        ..._fireflyDots(f, t, w, h),
                    ],
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
            ],
          ),
          ),
        );
      },
    );
  }

  List<Widget> _fireflyDots(int index, double t, double w, double h) {
    final phase = _fireflyPhase[index];
    final start = 0.36 + phase * 0.12;
    final fireflyT = Curves.easeInOut.transform(((t - start) / 0.5).clamp(0.0, 1.0).toDouble());
    final fireflyFade = fireflyT <= 0 ? 0.0 : (fireflyT > 0.9 ? (1 - (fireflyT - 0.9) / 0.1) : 1.0);
    final baseX = w * (0.15 + phase * 0.55);
    final baseTop = h * (0.62 - phase * 0.14);
    return [
      for (final trail in [0.1, 0.05, 0.0])
        Builder(builder: (context) {
          final ft = (fireflyT - trail).clamp(0.0, 1.0).toDouble();
          final fade = trail == 0.0
              ? fireflyFade.clamp(0.0, 1.0).toDouble()
              : fireflyFade.clamp(0.0, 1.0).toDouble() * (0.5 - trail * 3.2).clamp(0.0, 0.5);
          return Positioned(
            left: baseX + ft * w * 0.5,
            top: baseTop - ft * h * 0.36 + math.sin(ft * math.pi * 3 + phase * 6) * 8,
            child: Opacity(
              opacity: fade,
              child: Container(
                width: trail == 0.0 ? 7.0 : 4.0,
                height: trail == 0.0 ? 7.0 : 4.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEFE08A),
                  boxShadow: trail == 0.0
                      ? [BoxShadow(color: const Color(0xFFEFE08A).withOpacity(0.9), blurRadius: 14, spreadRadius: 4)]
                      : null,
                ),
              ),
            ),
          );
        }),
    ];
  }
}

class _VinePainter extends CustomPainter {
  final double growT;
  final double bloomT;
  const _VinePainter({required this.growT, required this.bloomT});

  @override
  void paint(Canvas canvas, Size size) {
    if (growT <= 0) return;
    final stemPaint = Paint()
      ..color = SeenlyPalette.sage.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(size.width * 0.5, size.height);
    final topY = size.height - growT * size.height * 0.92;
    path.cubicTo(
      size.width * 0.2, size.height * 0.65,
      size.width * 0.85, size.height * 0.35,
      size.width * 0.5, topY,
    );
    final metric = path.computeMetrics().first;
    final grown = metric.extractPath(0, metric.length * growT.clamp(0.0, 1.0));
    canvas.drawPath(grown, stemPaint);

    if (growT > 0.3) {
      _leaf(canvas, Offset(size.width * 0.28, size.height * 0.68), ((growT - 0.3) / 0.2).clamp(0.0, 1.0), -0.5);
    }
    if (growT > 0.5) {
      _leaf(canvas, Offset(size.width * 0.72, size.height * 0.44), ((growT - 0.5) / 0.2).clamp(0.0, 1.0), 0.6);
    }
    if (growT > 0.7) {
      _leaf(canvas, Offset(size.width * 0.34, size.height * 0.3), ((growT - 0.7) / 0.2).clamp(0.0, 1.0), -0.3);
    }
    if (bloomT > 0 && growT >= 0.98) {
      _bloom(canvas, Offset(size.width * 0.5, topY), bloomT.clamp(0.0, 1.2));
    }
  }

  void _leaf(Canvas canvas, Offset at, double opacity, double angle) {
    if (opacity <= 0) return;
    final paint = Paint()..color = SeenlyPalette.sage.withOpacity(0.75 * opacity);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    canvas.scale(opacity.clamp(0.2, 1.0));
    final leaf = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(13, -8, 26, 0)
      ..quadraticBezierTo(13, 8, 0, 0)
      ..close();
    canvas.drawPath(leaf, paint);
    canvas.restore();
  }

  void _bloom(Canvas canvas, Offset at, double t) {
    final scale = t.clamp(0.0, 1.2);
    final petalPaint = Paint()..color = SeenlyPalette.pink.withOpacity(0.85 * (scale.clamp(0.0, 1.0)));
    final centerPaint = Paint()..color = SeenlyPalette.mustard.withOpacity(0.9 * (scale.clamp(0.0, 1.0)));
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(scale);
    for (int i = 0; i < 5; i++) {
      final angle = (i / 5) * math.pi * 2;
      canvas.save();
      canvas.rotate(angle);
      canvas.drawOval(const Rect.fromLTWH(-5, -14, 10, 14), petalPaint);
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, 5, centerPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VinePainter oldDelegate) =>
      oldDelegate.growT != growT || oldDelegate.bloomT != bloomT;
}

class _MoonGlyph extends StatelessWidget {
  const _MoonGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF0DFA0),
              boxShadow: [BoxShadow(color: const Color(0xFFF0DFA0).withOpacity(0.55), blurRadius: 28, spreadRadius: 4)],
            ),
          ),
          Positioned(
            left: 16,
            top: -4,
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.ink),
            ),
          ),
        ],
      ),
    );
  }
}
