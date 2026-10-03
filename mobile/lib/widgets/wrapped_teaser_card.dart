import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/profile_stats.dart';
import '../services/app_translations.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'wow_motion.dart';

/// Profile's "your wrapped" entry point.
///
/// Dressed like the Wrapped screen it opens (same night-sky colour, twinkling
/// stars, a soft warm glow) rather than the flat accent bar it used to be, so
/// the teaser already feels like the thing behind it: this month's favorite
/// poster pinned like a photo, the three numbers that matter (hours, logged,
/// streak), the top genre, and an "open" button.
///
/// Deliberately fixed night colours in every theme — the Wrapped screen
/// itself is always night, and a dark card on a light page is the point.
class WrappedTeaserCard extends StatefulWidget {
  final WrappedStat wrapped;
  final VoidCallback onTap;
  const WrappedTeaserCard({super.key, required this.wrapped, required this.onTap});

  @override
  State<WrappedTeaserCard> createState() => _WrappedTeaserCardState();
}

class _WrappedTeaserCardState extends State<WrappedTeaserCard>
    with SingleTickerProviderStateMixin {
  static const _night = Color(0xFF241A22);
  static const _nightLift = Color(0xFF33232F);
  static const _cream = Color(0xFFF5EBDD);
  static const _gold = Color(0xFFF0C878);

  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wrapped;
    final hours = w.hours;
    final hoursLabel = hours >= 10 ? hours.round().toString() : hours.toStringAsFixed(1);
    final hasData = w.totalLogged > 0;
    final topGenre = w.topGenres.isNotEmpty ? w.topGenres.first.genre : null;
    final poster = w.favoritePoster;

    return PressScale(
      onTap: widget.onTap,
      scaleTo: 0.97,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_nightLift, _night],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF241A22).withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 10),
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // Warm glow behind the poster, cool one bottom-right.
              Positioned(
                left: -30,
                top: -30,
                child: _Glow(color: _gold.withOpacity(0.20), size: 170),
              ),
              Positioned(
                right: -40,
                bottom: -50,
                child: _Glow(color: SeenlyPalette.periwinkle.withOpacity(0.22), size: 190),
              ),
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _StarsPainter(_twinkle)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _PosterPin(posterUrl: poster),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                w.periodLabel.toLowerCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SeenlyText.mono(size: 9, color: _gold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'your wrapped'.tr,
                                style: SeenlyText.serif(
                                  italic: true,
                                  size: 22,
                                  weight: FontWeight.w600,
                                  color: _cream,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (hasData)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _Stat(value: hoursLabel, label: 'hrs'.tr),
                                    _StatDivider(),
                                    _Stat(value: '${w.totalLogged}', label: 'logged'.tr),
                                    _StatDivider(),
                                    _Stat(value: '${w.longestStreak}', label: 'streak'.tr),
                                  ],
                                )
                              else
                                Text(
                                  'nothing logged yet this month'.tr,
                                  style: SeenlyText.serif(
                                    italic: true,
                                    size: 12.5,
                                    color: _cream.withOpacity(0.7),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Perforation, like a ticket stub.
                    SizedBox(
                      height: 1,
                      child: CustomPaint(
                        size: const Size(double.infinity, 1),
                        painter: _DashPainter(color: _cream.withOpacity(0.22)),
                      ),
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        if (topGenre != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: _cream.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _cream.withOpacity(0.16)),
                            ),
                            child: Text(
                              topGenre.toLowerCase(),
                              style: SeenlyText.mono(size: 9, color: _cream.withOpacity(0.85)),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            'your year, at a glance'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.serif(
                              italic: true,
                              size: 11.5,
                              color: _cream.withOpacity(0.6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                          child: const Icon(Icons.arrow_forward_rounded, size: 17, color: _night),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
          ),
        ),
      );
}

/// The month's favorite poster, pinned like a photo with a strip of tape.
/// Falls back to a glowing film icon when there's no poster to show.
class _PosterPin extends StatelessWidget {
  final String? posterUrl;
  const _PosterPin({required this.posterUrl});

  static const double _w = 64;
  static const double _h = 92;

  @override
  Widget build(BuildContext context) {
    final hasPoster = posterUrl != null && posterUrl!.isNotEmpty;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SeenlyPalette.accent.withOpacity(0.85),
            SeenlyPalette.periwinkle.withOpacity(0.7),
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.local_movies_outlined, size: 24, color: Color(0xFFF5EBDD)),
      ),
    );

    return Transform.rotate(
      angle: -0.06,
      child: SizedBox(
        width: _w + 14,
        height: _h + 14,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: _w + 10,
              padding: const EdgeInsets.fromLTRB(5, 5, 5, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFDF9F2),
                boxShadow: [
                  BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 6)),
                ],
              ),
              child: SizedBox(
                width: _w,
                height: _h - 12,
                child: hasPoster
                    ? Image.network(
                        posterUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => fallback,
                      )
                    : fallback,
              ),
            ),
            Positioned(
              top: -3,
              child: Transform.rotate(
                angle: 0.08,
                child: Container(
                  width: 34,
                  height: 12,
                  color: const Color(0xFFF0C878).withOpacity(0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: SeenlyText.serif(
            size: 21,
            weight: FontWeight.w600,
            color: const Color(0xFFF5EBDD),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: SeenlyText.mono(size: 8.5, color: const Color(0xFFF5EBDD).withOpacity(0.55)),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: const Color(0xFFF5EBDD).withOpacity(0.18),
      );
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 5.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + dash, size.width), 0.5), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// A fixed sprinkle of stars, each twinkling on its own phase.
class _StarsPainter extends CustomPainter {
  final Animation<double> t;
  _StarsPainter(this.t) : super(repaint: t);

  // x, y (0..1), radius, phase (0..1)
  static const _stars = <(double, double, double, double)>[
    (0.06, 0.12, 1.3, 0.0),
    (0.22, 0.06, 0.9, 0.3),
    (0.41, 0.15, 1.1, 0.6),
    (0.58, 0.07, 1.4, 0.15),
    (0.74, 0.18, 0.9, 0.85),
    (0.90, 0.09, 1.3, 0.45),
    (0.96, 0.34, 0.9, 0.7),
    (0.83, 0.52, 1.1, 0.2),
    (0.94, 0.78, 1.4, 0.55),
    (0.62, 0.86, 0.9, 0.9),
    (0.35, 0.92, 1.2, 0.35),
    (0.12, 0.84, 0.9, 0.75),
    (0.50, 0.50, 0.8, 0.05),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final (x, y, r, phase) in _stars) {
      final v = (math.sin((t.value + phase) * math.pi * 2) + 1) / 2; // 0..1
      paint.color = const Color(0xFFF5EBDD).withOpacity(0.15 + 0.55 * v);
      canvas.drawCircle(Offset(x * size.width, y * size.height), r, paint);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => false;
}
