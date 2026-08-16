import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'building.dart';
import 'light_bloom.dart' show flashOpacity;
import '../services/app_translations.dart';

/// The city theme's counterpart to the ticket tear, the stamp press,
/// and the boarding-pass tear: the plot waits empty for you to raise
/// the building — drag it upward (or just tap it), the physical
/// opposite of a stamp's press, since this time something is going
/// *up* rather than coming down. Windows light in sequence as it
/// climbs; the moment it tops out, a scatter of warm sparks lifts off
/// and a soft glow blooms behind it — the same "moment sealed in
/// light" beat as the other three themes, tinted to how the evening
/// felt.
///
/// Call [showCityRise] rather than constructing this directly.
Future<void> showCityRise(
  BuildContext context, {
  required String title,
  required String mediaType,
  required int? rating,
  required DateTime watchedAt,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _CityRiseOverlay(title: title, mediaType: mediaType, rating: rating, watchedAt: watchedAt),
      ),
    ),
  );
}

class _CityRiseOverlay extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;

  const _CityRiseOverlay({
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
  });

  @override
  State<_CityRiseOverlay> createState() => _CityRiseOverlayState();
}

class _CityRiseOverlayState extends State<_CityRiseOverlay> with TickerProviderStateMixin {
  late final AnimationController _appear;
  late final AnimationController _hintPulse;
  late final AnimationController _snapBack;
  late final AnimationController _settle; // one-shot: commits the rise + sparks + camera pull-back
  late final List<_Spark> _sparks;
  late final List<_FireworkParticle> _fireworkParticles;

  double _dragRise = 0.0;
  double _dragRiseAtRelease = 0.0;
  bool _committed = false;
  bool _dragging = false;
  bool _popped = false;

  Timer? _settleWatchdog;

  static const double _riseThreshold = 0.55;
  static const double _maxDragPx = 120;
  static const double _flingVelocity = 420;

  @override
  void initState() {
    super.initState();
    _sparks = _makeSparks(title: widget.title, watchedAt: widget.watchedAt, rating: widget.rating, mediaType: widget.mediaType);
    _fireworkParticles = _makeFireworkParticles(
        title: widget.title, watchedAt: widget.watchedAt, rating: widget.rating, mediaType: widget.mediaType);
    _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..addListener(() => setState(() {}))
      ..forward();
    _hintPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..addListener(() => setState(() {}))
      ..repeat(reverse: true);
    _snapBack = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _dragRise = 0;
      });
    _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _popOnce();
      });
  }

  @override
  void dispose() {
    _settleWatchdog?.cancel();
    _appear.dispose();
    _hintPulse.dispose();
    _snapBack.dispose();
    _settle.dispose();
    super.dispose();
  }

  static List<_Spark> _makeSparks({
    required String title,
    required DateTime watchedAt,
    required int? rating,
    required String mediaType,
  }) {
    final r = math.Random(Object.hash(title, watchedAt, rating, mediaType, 'spark'));
    final color = SeenlyPalette.mediaColor(mediaType);
    return List.generate(12, (i) {
      return _Spark(
        x: (r.nextDouble() - 0.5) * 70,
        rise: 40 + r.nextDouble() * 70,
        sway: (r.nextDouble() - 0.5) * 24,
        size: 2 + r.nextDouble() * 2.4,
        delay: r.nextDouble() * 0.3,
        color: color,
      );
    });
  }

  static List<_FireworkParticle> _makeFireworkParticles({
    required String title,
    required DateTime watchedAt,
    required int? rating,
    required String mediaType,
  }) {
    final r = math.Random(Object.hash(title, watchedAt, rating, mediaType, 'firework'));
    final colors = [
      SeenlyPalette.ratingColor(rating),
      SeenlyPalette.mediaColor(mediaType),
      SeenlyPalette.mustard,
      SeenlyPalette.paper,
    ];
    return List.generate(18, (i) {
      final angle = (i / 18) * 2 * math.pi + (r.nextDouble() - 0.5) * 0.3;
      return _FireworkParticle(
        angle: angle,
        distance: 34 + r.nextDouble() * 40,
        size: 2 + r.nextDouble() * 2.6,
        color: colors[r.nextInt(colors.length)],
      );
    });
  }

  void _popOnce() {
    if (_popped || !mounted) return;
    _popped = true;
    _settleWatchdog?.cancel();
    Navigator.of(context).pop();
  }

  void _onDragStart(DragStartDetails _) {
    if (_committed) return;
    final currentVisual = _dragRise * (1 - Curves.easeOut.transform(_snapBack.value));
    _snapBack.stop();
    setState(() {
      _dragRise = currentVisual;
      _dragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_committed) return;
    final wasPastThreshold = _dragRise >= _riseThreshold;
    setState(() {
      // Dragging upward means a negative dy — that's what grows the
      // building, same physical logic as actually lifting something.
      _dragRise = (_dragRise - d.delta.dy / _maxDragPx).clamp(0.0, 1.0).toDouble();
    });
    if (!wasPastThreshold && _dragRise >= _riseThreshold) {
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_committed) return;
    setState(() => _dragging = false);
    final flung = -d.velocity.pixelsPerSecond.dy > _flingVelocity;
    if (_dragRise >= _riseThreshold || flung) {
      _commitRise();
    } else {
      _dragRiseAtRelease = _dragRise;
      _snapBack.forward(from: 0);
    }
  }

  void _onTap() {
    if (!_committed) _commitRise();
  }

  void _commitRise() {
    HapticFeedback.mediumImpact();
    _dragRiseAtRelease = _dragRise;
    setState(() => _committed = true);
    _settle.forward(from: 0);
    _settleWatchdog?.cancel();
    _settleWatchdog = Timer(_settle.duration! * 2, _popOnce);
  }

  void _skip() => _popOnce();

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOutBack.transform(_appear.value);

    final liveRise = _dragging ? _dragRise : _dragRise * (1 - Curves.easeOut.transform(_snapBack.value));
    final settleV = _settle.value;
    final rise = _committed ? _riseAtCommitBlend(settleV) : liveRise;

    final hintVisible = !_dragging && !_committed && _dragRise < 0.05;
    final hintPulse = 0.5 + 0.5 * _hintPulse.value;

    final captionT = _committed ? Curves.easeOut.transform((settleV / 0.55).clamp(0.0, 1.0).toDouble()) : 0.0;

    final flashA = flashOpacity(_committed ? settleV : 0.0, riseEnd: 0.35);
    final glowColor = SeenlyPalette.ratingColor(widget.rating);

    final sparkT = _committed ? Curves.easeOut.transform(((settleV - 0.25) / 0.5).clamp(0.0, 1.0).toDouble()) : 0.0;
    final sparkFade = 1 - Curves.easeIn.transform(((settleV - 0.65) / 0.35).clamp(0.0, 1.0).toDouble());

    // The firework itself catches right after the sparks lift off — a
    // short, bright "arrival" beat on the rooftop rather than the
    // sparks' longer drift.
    final fireworkT = _committed ? Curves.easeOut.transform(((settleV - 0.42) / 0.3).clamp(0.0, 1.0).toDouble()) : 0.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: SeenlyPalette.ink.withOpacity(0.32),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: captionT,
                    child: Transform.translate(
                      offset: Offset(0, (1 - captionT) * 8),
                      child: Text('raised for tonight'.tr,
                          style: SeenlyText.serif(italic: true, size: 15, color: SeenlyPalette.paper)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 220,
                    height: 260,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      clipBehavior: Clip.none,
                      children: [
                        // The ground the building stands on.
                        Positioned(
                          bottom: 0,
                          child: Container(
                            width: 150,
                            height: 4,
                            decoration: BoxDecoration(
                              color: SeenlyPalette.paper.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Warm glow, blooming the instant it tops out.
                        Positioned(
                          bottom: 20,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: (flashA * 0.5).clamp(0.0, 1.0),
                              child: Container(
                                width: 240,
                                height: 240,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [glowColor.withOpacity(0.75), glowColor.withOpacity(0.0)],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: _SparkBurst(t: sparkT, fade: sparkFade.clamp(0.0, 1.0), sparks: _sparks),
                        ),
                        // A short, bright firework over the roofline —
                        // the building's own little arrival celebration,
                        // rather than just sparks drifting off it. Rides
                        // the same rise-driven anchor as the sparks so it
                        // always sits right at the current roofline.
                        IgnorePointer(
                          child: _RoofFirework(t: fireworkT, rise: rise, particles: _fireworkParticles),
                        ),
                        Opacity(
                          opacity: appear.clamp(0.0, 1.0).toDouble(),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _onTap,
                            onVerticalDragStart: _onDragStart,
                            onVerticalDragUpdate: _onDragUpdate,
                            onVerticalDragEnd: _onDragEnd,
                            child: SizedBox(
                              width: 220,
                              height: 200,
                              child: BuildingWidget(
                                title: widget.title,
                                mediaType: widget.mediaType,
                                rating: widget.rating,
                                watchedAt: widget.watchedAt,
                                width: 74,
                                height: 200,
                                rise: rise,
                                showLabel: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Opacity(
                    opacity: hintVisible ? (appear * hintPulse).clamp(0.0, 1.0).toDouble() : 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_upward, size: 13, color: SeenlyPalette.paper.withOpacity(0.75)),
                        const SizedBox(width: 6),
                        Text('raise it — or just tap'.tr,
                            style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper.withOpacity(0.75))),
                      ],
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

  double _riseAtCommitBlend(double settleV) {
    final finish = Curves.easeOut.transform((settleV / 0.25).clamp(0.0, 1.0).toDouble());
    return _dragRiseAtRelease + (1 - _dragRiseAtRelease) * finish;
  }
}

class _Spark {
  final double x;
  final double rise;
  final double sway;
  final double size;
  final double delay;
  final Color color;

  const _Spark({
    required this.x,
    required this.rise,
    required this.sway,
    required this.size,
    required this.delay,
    required this.color,
  });
}

/// The lift of warm sparks off the roofline the instant the building
/// tops out — small, upward, and twinkling, unlike the other three
/// themes' bursts, since this is a "lighting up" rather than a
/// "flying/falling apart."
class _SparkBurst extends StatelessWidget {
  final double t;
  final double fade;
  final List<_Spark> sparks;

  const _SparkBurst({required this.t, required this.fade, required this.sparks});

  @override
  Widget build(BuildContext context) {
    if (t <= 0 || fade <= 0) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: sparks.map((s) {
        final local = ((t - s.delay) / (1 - s.delay)).clamp(0.0, 1.0);
        final eased = Curves.easeOut.transform(local);
        final dy = -s.rise * eased;
        final dx = s.x + math.sin(eased * math.pi) * s.sway;
        final twinkle = (math.sin(eased * math.pi * 3) + 1) / 2;
        return Transform.translate(
          offset: Offset(dx, dy - 80),
          child: Opacity(
            opacity: (fade * (0.4 + 0.6 * twinkle)).clamp(0.0, 1.0),
            child: Container(
              width: s.size,
              height: s.size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: s.color),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FireworkParticle {
  final double angle;
  final double distance;
  final double size;
  final Color color;

  const _FireworkParticle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
  });
}

/// A short, bright burst over the roofline — an actual firework's
/// expand-then-fade shape (as opposed to the sparks' longer upward
/// drift), timed to catch right as the building tops out.
class _RoofFirework extends StatelessWidget {
  final double t; // 0..1, own timing window (already offset from settle)
  final double rise; // 0..1, tracks the building's current height
  final List<_FireworkParticle> particles;

  const _RoofFirework({required this.t, required this.rise, required this.particles});

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final burstT = Curves.easeOut.transform(t.clamp(0.0, 1.0));
    final fade = 1 - Curves.easeIn.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0).toDouble());
    if (fade <= 0) return const SizedBox.shrink();
    // Tracks the same roofline the sparks launch from, a touch higher
    // so the burst reads as happening just above it.
    final roofY = -80 - rise.clamp(0.0, 1.0) * 60;
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: particles.map((p) {
        final dist = p.distance * burstT;
        final dx = math.cos(p.angle) * dist;
        // A slight extra lift so the burst arcs upward rather than
        // expanding as a flat disc.
        final dy = math.sin(p.angle) * dist - burstT * 14;
        return Transform.translate(
          offset: Offset(dx, roofY + dy),
          child: Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Container(
              width: p.size,
              height: p.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.color,
                boxShadow: [BoxShadow(color: p.color.withOpacity(0.7), blurRadius: 5, spreadRadius: 1)],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
