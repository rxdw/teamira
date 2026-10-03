import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import 'room_strings.dart';

/// One person's heart in the finale: who, and what they gave.
class FinaleHeart {
  final String name;
  final int rating;
  final bool isYou;
  const FinaleHeart({required this.name, required this.rating, required this.isYou});
}

/// The moment the joint rating appears.
///
/// Everyone's own heart — each with the number they gave — drifts together,
/// and as they touch they melt into one big heart that counts up to the
/// shared number. How it feels follows how you agreed:
///  * **unison** — a warm cloud of hearts rises (you felt the same thing);
///  * **close**  — a handful of soft sparkles;
///  * **split**  — the hearts first lean apart and wobble, then still meet in
///    the middle, with only a couple of small hearts at the end. No one is
///    wrong; it's just a livelier evening.
/// After it plays, the same widget rests as the big heart and a row of who
/// gave what. With "reduce motion" on it simply starts at that resting state.
///
/// [animate] says "this is the first time you see it"; the animation then
/// waits for [active] (the parent decides when it is on screen) and plays once.
class TogetherFinale extends StatefulWidget {
  final List<FinaleHeart> hearts;
  final double? average;
  final String verdict; // unison | close | split | solo
  final List<String> sharedTags;
  final bool animate;
  final bool active;

  const TogetherFinale({
    super.key,
    required this.hearts,
    required this.average,
    required this.verdict,
    this.sharedTags = const [],
    this.animate = true,
    this.active = true,
  });

  @override
  State<TogetherFinale> createState() => _TogetherFinaleState();
}

class _TogetherFinaleState extends State<TogetherFinale> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
  bool _started = false;
  bool _buzzed = false;
  late final List<_Particle> _particles = _makeParticles();

  List<_Particle> _makeParticles() {
    final rng = math.Random(widget.hearts.fold<int>(7, (a, h) => a * 31 + h.rating));
    final n = switch (widget.verdict) {
      'unison' => 24,
      'close' => 12,
      'split' => 5,
      _ => 0,
    };
    final sparkle = widget.verdict == 'close';
    return [
      for (var i = 0; i < n; i++)
        _Particle(
          x: 0.1 + rng.nextDouble() * 0.8,
          speed: 0.55 + rng.nextDouble() * 0.5,
          size: 7 + rng.nextDouble() * (sparkle ? 7 : 11),
          sway: rng.nextDouble() * 2 * math.pi,
          delay: rng.nextDouble() * 0.35,
          sparkle: sparkle,
          pink: rng.nextBool(),
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_buzzed && _c.value >= 0.47) {
        _buzzed = true;
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant TogetherFinale old) {
    super.didUpdateWidget(old);
    _maybeStart();
  }

  void _maybeStart() {
    if (_started) return;
    final reduce = MediaQuery.of(context).disableAnimations;
    if (!widget.animate || reduce || widget.hearts.length < 2) {
      _started = true;
      _buzzed = true;
      _c.value = 1;
      return;
    }
    if (widget.active) {
      _started = true;
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final hearts = widget.hearts;
    final avg = widget.average;
    if (hearts.isEmpty || avg == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final gather = _seg(0.05, 0.44, Curves.easeInOutCubic);
        final melt = _seg(0.42, 0.56, Curves.easeIn);
        final pop = _seg(0.44, 0.72, Curves.easeOutBack);
        final count = _seg(0.5, 0.86, Curves.easeOutCubic);
        final rest = _seg(0.8, 1.0, Curves.easeOut);
        final wobble = widget.verdict == 'split' ? math.sin(_c.value * 22) * (1 - gather) * 7 : 0.0;
        final single = hearts.length < 2;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 190,
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  final cy = 92.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _ParticlePainter(particles: _particles, t: _c.value)),
                      ),
                      // halo behind the merged heart
                      Positioned(
                        left: w / 2 - 80,
                        top: cy - 80,
                        child: Opacity(
                          opacity: (pop * 0.9).clamp(0.0, 1.0),
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [
                                SeenlyPalette.pink.withOpacity(0.32),
                                SeenlyPalette.pink.withOpacity(0.0),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      // the individual hearts, drifting together
                      if (!single)
                        for (var i = 0; i < hearts.length; i++) ...[
                          Builder(builder: (_) {
                            final n = hearts.length;
                            final spread = math.min(w * 0.36, 120.0);
                            final startX = (i - (n - 1) / 2) * (spread * 2 / math.max(n - 1, 1)) * (n == 2 ? 1 : 0.8);
                            final x = startX * (1 - gather);
                            final y = wobble * (i.isEven ? 1 : -1);
                            final fade = (1 - melt).clamp(0.0, 1.0);
                            final appear = _seg(0.0, 0.14, Curves.easeOut);
                            return Positioned(
                              left: w / 2 - 34 + x,
                              top: cy - 34 + y,
                              child: Opacity(
                                opacity: (fade * appear).clamp(0.0, 1.0),
                                child: Transform.scale(
                                  scale: 0.85 + 0.15 * appear - 0.25 * melt,
                                  child: _NumberHeart(size: 68, number: '${hearts[i].rating}', color: SeenlyPalette.pink),
                                ),
                              ),
                            );
                          }),
                        ],
                      // the one big heart
                      Positioned(
                        left: w / 2 - 56,
                        top: cy - 56,
                        child: Opacity(
                          opacity: single ? 1 : pop.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: single ? 1 : (0.4 + 0.6 * pop),
                            child: _NumberHeart(
                              size: 112,
                              number: single
                                  ? '${hearts.first.rating}'
                                  : (avg * count).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), ''),
                              color: SeenlyPalette.accent,
                              big: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Opacity(
              opacity: rest,
              child: Column(
                children: [
                  if (!single)
                    Text(at('общая оценка', 'together'),
                        style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkFaint)),
                  const SizedBox(height: 4),
                  Text(
                    verdictLine(widget.verdict),
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(size: 16.5, italic: true, color: SeenlyPalette.ink),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final h in hearts)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.pink.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '${h.isYou ? at('вы', 'you') : h.name.toLowerCase()} · ${h.rating}',
                            style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.pink),
                          ),
                        ),
                    ],
                  ),
                  if (widget.sharedTags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(at('вам обоим', 'you both picked'),
                        style: SeenlyText.serif(size: 12, italic: true, color: SeenlyPalette.inkFaint)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final t in widget.sharedTags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: SeenlyPalette.sage.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(t, style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.sage)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A heart with a number in it.
class _NumberHeart extends StatelessWidget {
  final double size;
  final String number;
  final Color color;
  final bool big;
  const _NumberHeart({required this.size, required this.number, required this.color, this.big = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.favorite_rounded, size: size, color: color.withOpacity(big ? 1 : 0.9)),
          Padding(
            padding: EdgeInsets.only(bottom: size * 0.05),
            child: Text(
              number,
              style: SeenlyText.serif(
                size: big ? 36 : 22,
                weight: FontWeight.w700,
                color: SeenlyPalette.accentOnAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Particle {
  final double x;
  final double speed;
  final double size;
  final double sway;
  final double delay;
  final bool sparkle;
  final bool pink;
  const _Particle({
    required this.x,
    required this.speed,
    required this.size,
    required this.sway,
    required this.delay,
    required this.sparkle,
    required this.pink,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  _ParticlePainter({required this.particles, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty || t < 0.6 || t >= 1) return;
    final base = (t - 0.6) / 0.4;
    for (final p in particles) {
      final q = ((base - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (q <= 0) continue;
      final y = size.height * 0.62 - q * size.height * 0.85 * p.speed;
      final x = size.width * p.x + math.sin(p.sway + q * 5) * 12;
      final opacity = math.sin(q * math.pi).clamp(0.0, 1.0);
      final color = (p.pink ? SeenlyPalette.pink : SeenlyPalette.accent).withOpacity(0.75 * opacity);
      final paint = Paint()..color = color;
      if (p.sparkle) {
        _star(canvas, Offset(x, y), p.size * (0.6 + 0.4 * opacity), paint);
      } else {
        _heart(canvas, Offset(x, y), p.size * (0.7 + 0.3 * opacity), paint);
      }
    }
  }

  void _heart(Canvas canvas, Offset c, double s, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy + s * 0.35)
      ..cubicTo(c.dx - s * 0.9, c.dy - s * 0.15, c.dx - s * 0.45, c.dy - s * 0.85, c.dx, c.dy - s * 0.3)
      ..cubicTo(c.dx + s * 0.45, c.dy - s * 0.85, c.dx + s * 0.9, c.dy - s * 0.15, c.dx, c.dy + s * 0.35)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _star(Canvas canvas, Offset c, double s, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - s)
      ..quadraticBezierTo(c.dx + s * 0.12, c.dy - s * 0.12, c.dx + s, c.dy)
      ..quadraticBezierTo(c.dx + s * 0.12, c.dy + s * 0.12, c.dx, c.dy + s)
      ..quadraticBezierTo(c.dx - s * 0.12, c.dy + s * 0.12, c.dx - s, c.dy)
      ..quadraticBezierTo(c.dx - s * 0.12, c.dy - s * 0.12, c.dx, c.dy - s)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}
