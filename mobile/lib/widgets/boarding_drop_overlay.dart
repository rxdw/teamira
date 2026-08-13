import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/coach_routes.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'boarding_pass.dart';
import 'light_bloom.dart' show flashOpacity;

/// The "Evening Route" theme's counterpart to `ticket_drop_overlay.dart`:
/// the pass waits for you to tear it at the gate — drag it apart (or
/// tap it) — then the trip plays out and you land on "we made it,"
/// standing in for "marked as watched." Same drag-and-tear physicality
/// as the cinema ticket; what's different is the destination this time
/// is a real place, not just a feeling.
///
/// The instant it tears, a scatter of tiny punched paper dots — the
/// conductor's hole-punch — flicks free, and a warm glow blooms behind
/// it, same "moment sealed in light" beat used by the other two themes.
///
/// Call [showBoardingDrop] rather than constructing this directly.
Future<void> showBoardingDrop(
  BuildContext context, {
  required String title,
  required String mediaType,
  required int? rating,
  required DateTime watchedAt,
  int? runtimeMinutes,
  CoachRoute? routeOverride,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _BoardingDropOverlay(
          title: title,
          mediaType: mediaType,
          rating: rating,
          watchedAt: watchedAt,
          runtimeMinutes: runtimeMinutes,
          routeOverride: routeOverride,
        ),
      ),
    ),
  );
}

class _BoardingDropOverlay extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  final int? runtimeMinutes;
  final CoachRoute? routeOverride;

  const _BoardingDropOverlay({
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
    required this.runtimeMinutes,
    this.routeOverride,
  });

  @override
  State<_BoardingDropOverlay> createState() => _BoardingDropOverlayState();
}

class _BoardingDropOverlayState extends State<_BoardingDropOverlay> with TickerProviderStateMixin {
  late final AnimationController _appear;
  late final AnimationController _hintPulse;
  late final AnimationController _snapBack;
  late final AnimationController _fall;
  late final AnimationController _idle; // loops: the night scene drifting behind the fog
  late final AnimationController _fogClear; // one-shot: the fog fading once wiped enough
  late final List<_PunchDot> _dots;

  double _dragTear = 0.0;
  double _dragTearAtRelease = 0.0;
  bool _committed = false;
  bool _dragging = false;
  bool _popped = false;

  Timer? _fallWatchdog;

  // The window starts fogged over — nothing to see, nothing to tear —
  // until a finger wipes it clear, the same small, cozy thing as
  // actually clearing a bus window with your sleeve to see where you
  // are. `_wipedPoints` accumulates a trail of cleared circles;
  // `_wipedDistance` is just their total length, so "enough" is a
  // couple of real strokes rather than one lucky tap.
  bool _foggy = true;
  final List<Offset> _wipedPoints = [];
  Offset? _lastWipePoint;
  double _wipedDistance = 0.0;
  static const double _wipeThreshold = 380.0;
  static const double _wipeRadius = 32.0;

  static const double _tearThreshold = 0.5;
  static const double _maxDragPx = 130;
  static const double _flingVelocity = 500;

  @override
  void initState() {
    super.initState();
    _dots = _makeDots(title: widget.title, watchedAt: widget.watchedAt, rating: widget.rating, mediaType: widget.mediaType);
    _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..addListener(() => setState(() {}))
      ..forward();
    _hintPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..addListener(() => setState(() {}))
      ..repeat(reverse: true);
    _snapBack = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _dragTear = 0;
      });
    _fall = AnimationController(vsync: this, duration: const Duration(milliseconds: 950))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _popOnce();
      });
    _idle = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addListener(() => setState(() {}))
      ..repeat();
    _fogClear = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _fallWatchdog?.cancel();
    _appear.dispose();
    _hintPulse.dispose();
    _snapBack.dispose();
    _fall.dispose();
    _idle.dispose();
    _fogClear.dispose();
    super.dispose();
  }

  static List<_PunchDot> _makeDots({
    required String title,
    required DateTime watchedAt,
    required int? rating,
    required String mediaType,
  }) {
    final r = math.Random(Object.hash(title, watchedAt, rating, mediaType, 'punch'));
    final colors = [SeenlyPalette.ratingColor(rating), SeenlyPalette.mediaColor(mediaType), SeenlyPalette.paper];
    return List.generate(11, (i) {
      final angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.5;
      return _PunchDot(
        angle: angle,
        distance: 26 + r.nextDouble() * 62,
        gravity: 55 + r.nextDouble() * 85,
        rotationSpeed: (r.nextBool() ? 1 : -1) * (2 + r.nextDouble() * 3),
        size: 5 + r.nextDouble() * 3.5,
        color: colors[r.nextInt(colors.length)],
      );
    });
  }

  void _popOnce() {
    if (_popped || !mounted) return;
    _popped = true;
    _fallWatchdog?.cancel();
    Navigator.of(context).pop();
  }

  void _onDragStart(DragStartDetails _) {
    if (_committed) return;
    final currentVisual = _dragTear * (1 - Curves.easeOut.transform(_snapBack.value));
    _snapBack.stop();
    setState(() {
      _dragTear = currentVisual;
      _dragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_committed) return;
    final wasPastThreshold = _dragTear >= _tearThreshold;
    setState(() {
      _dragTear = (_dragTear + d.delta.dx.abs() / _maxDragPx).clamp(0.0, 1.0).toDouble();
    });
    if (!wasPastThreshold && _dragTear >= _tearThreshold) {
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_committed) return;
    setState(() => _dragging = false);
    final flung = d.velocity.pixelsPerSecond.dx.abs() > _flingVelocity;
    if (_dragTear >= _tearThreshold || flung) {
      _commitTear();
    } else {
      _dragTearAtRelease = _dragTear;
      _snapBack.forward(from: 0);
    }
  }

  void _onTap() {
    if (!_committed) _commitTear();
  }

  void _commitTear() {
    HapticFeedback.mediumImpact();
    _dragTearAtRelease = _dragTear;
    setState(() => _committed = true);
    _fall.forward(from: 0);
    _fallWatchdog?.cancel();
    _fallWatchdog = Timer(_fall.duration! * 2, _popOnce);
  }

  void _skip() => _popOnce();

  void _onFogPanStart(DragStartDetails d) {
    if (!_foggy) return;
    _lastWipePoint = d.localPosition;
    setState(() => _wipedPoints.add(d.localPosition));
  }

  void _onFogPanUpdate(DragUpdateDetails d) {
    if (!_foggy) return;
    final p = d.localPosition;
    final last = _lastWipePoint;
    if (last != null) {
      final segLen = (p - last).distance;
      _wipedDistance += segLen;
      // A few extra points along the stroke so a fast swipe still
      // clears a continuous streak rather than a dotted line.
      final steps = (segLen / 8).ceil().clamp(1, 12);
      for (int i = 1; i <= steps; i++) {
        _wipedPoints.add(Offset.lerp(last, p, i / steps)!);
      }
    } else {
      _wipedPoints.add(p);
    }
    _lastWipePoint = p;
    setState(() {});
    if (_wipedDistance >= _wipeThreshold) {
      _foggy = false;
      HapticFeedback.lightImpact();
      _fogClear.forward();
    }
  }

  void _onFogPanEnd(DragEndDetails d) {
    _lastWipePoint = null;
  }

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOutBack.transform(_appear.value);

    final liveTear = _dragging ? _dragTear : _dragTear * (1 - Curves.easeOut.transform(_snapBack.value));
    final fallV = _fall.value;
    final tear = _committed ? _dragTearAtCommitBlend(fallV) : liveTear;

    final fallProgress = _committed ? Curves.easeIn.transform(((fallV - 0.18) / 0.82).clamp(0.0, 1.0).toDouble()) : 0.0;
    final fall = fallProgress * 340;
    final fade = _committed ? 1.0 - Curves.easeIn.transform(((fallV - 0.72) / 0.28).clamp(0.0, 1.0).toDouble()) : 1.0;

    final hintVisible = !_dragging && !_committed && _dragTear < 0.05;
    final hintPulse = 0.5 + 0.5 * _hintPulse.value;

    // How clear the glass currently is, and how much of the pass that
    // earns — the pass doesn't just appear, it becomes visible exactly
    // as far as the window's actually been wiped clear.
    final fogT = Curves.easeIn.transform(_fogClear.value);
    final passReveal = _foggy ? 0.0 : fogT;
    final fogShowing = _foggy || _fogClear.value < 1.0;

    final captionT = _committed ? Curves.easeOut.transform((fallV / 0.5).clamp(0.0, 1.0).toDouble()) : 0.0;
    final captionFade = _committed ? 1.0 - Curves.easeIn.transform(((fallV - 0.7) / 0.3).clamp(0.0, 1.0).toDouble()) : 0.0;

    final flashA = flashOpacity(_committed ? fallV : 0.0, riseEnd: 0.3);
    final glowColor = SeenlyPalette.ratingColor(widget.rating);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: SeenlyPalette.ink.withOpacity(0.32),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: _skip,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('skip', style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.7))),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: captionT * captionFade,
                        child: Transform.translate(
                          offset: Offset(0, (1 - captionT) * 8),
                          child: Text('добрались',
                              style: SeenlyText.serif(italic: true, size: 15, color: SeenlyPalette.paper)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 330,
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            // The night going by, drawn first so wiping
                            // the fog above reveals it rather than a
                            // blank void.
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: _DuskWindowBackdrop(loop: _idle.value),
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: Opacity(
                                opacity: (flashA * 0.5).clamp(0.0, 1.0),
                                child: Container(
                                  width: 260,
                                  height: 260,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [glowColor.withOpacity(0.8), glowColor.withOpacity(0.0)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Streaks of warm streetlight blurring past,
                            // like riding a dusk route past lamp after
                            // lamp — motion, not just a static flash.
                            IgnorePointer(
                              child: _WindowLightStreaks(t: _committed ? fallV : 0.0),
                            ),
                            IgnorePointer(
                              child: _PunchBurst(t: _committed ? fallV : 0.0, dots: _dots),
                            ),
                            Transform.translate(
                              offset: Offset(0, fall),
                              child: Opacity(
                                opacity: (appear * fade * passReveal).clamp(0.0, 1.0).toDouble(),
                                child: Transform.scale(
                                  scale: 0.85 + appear * 0.15,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _onTap,
                                    onHorizontalDragStart: _onDragStart,
                                    onHorizontalDragUpdate: _onDragUpdate,
                                    onHorizontalDragEnd: _onDragEnd,
                                    child: BoardingPassWidget(
                                      title: widget.title,
                                      mediaType: widget.mediaType,
                                      rating: widget.rating,
                                      watchedAt: widget.watchedAt,
                                      runtimeMinutes: widget.runtimeMinutes,
                                      routeOverride: widget.routeOverride,
                                      width: 250,
                                      height: 112,
                                      tearProgress: tear,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // The fogged glass itself — wipe it to clear
                            // a trail through to the window (and, once
                            // enough of it's cleared, to the pass).
                            if (fogShowing)
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanStart: _onFogPanStart,
                                    onPanUpdate: _onFogPanUpdate,
                                    onPanEnd: _onFogPanEnd,
                                    child: CustomPaint(
                                      painter: _FogPainter(
                                        points: _wipedPoints,
                                        radius: _wipeRadius,
                                        opacity: 0.88 * (1 - fogT),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Opacity(
                        opacity: (_foggy
                                ? (appear * hintPulse)
                                : (hintVisible ? (appear * hintPulse) : 0))
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_foggy ? Icons.water_drop_outlined : Icons.swipe,
                                size: 13, color: SeenlyPalette.paper.withOpacity(0.75)),
                            const SizedBox(width: 6),
                            Text(
                              _foggy ? 'wipe the window to see' : 'tear it at the gate — or just tap',
                              style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper.withOpacity(0.75)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _dragTearAtCommitBlend(double fallV) {
    final finish = Curves.easeOut.transform((fallV / 0.18).clamp(0.0, 1.0).toDouble());
    return _dragTearAtRelease + (1 - _dragTearAtRelease) * finish;
  }
}

/// A handful of blurred, warm-toned streaks racing past behind the
/// pass as it tears — standing in for streetlights streaming by a bus
/// window at dusk. Each streak's own lane and speed are fixed per
/// evening (seeded), but their position is driven live by [t], so they
/// genuinely read as motion rather than a fixed decorative pattern.
class _WindowLightStreaks extends StatelessWidget {
  final double t; // 0..1, matches the tear/fall timeline
  const _WindowLightStreaks({required this.t});

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final fade = 1 - Curves.easeIn.transform(((t - 0.6) / 0.4).clamp(0.0, 1.0).toDouble());
    if (fade <= 0) return const SizedBox.shrink();
    return Opacity(
      opacity: fade.clamp(0.0, 1.0),
      child: CustomPaint(
        size: const Size(330, 220),
        painter: _StreakPainter(t: Curves.easeOut.transform(t.clamp(0.0, 1.0))),
      ),
    );
  }
}

class _StreakPainter extends CustomPainter {
  final double t;
  const _StreakPainter({required this.t});

  static const _lampColors = [Color(0xFFFFC978), Color(0xFFFF9E5E), Color(0xFFFFE0A3)];

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(0x6C616D70); // 'lamp' — fixed lanes every time
    for (int i = 0; i < 8; i++) {
      final y = r.nextDouble() * size.height;
      final len = 46 + r.nextDouble() * 100;
      final speed = 0.7 + r.nextDouble() * 0.9;
      final laneT = (t * speed).clamp(0.0, 1.0);
      final x = size.width * 1.15 - laneT * size.width * 1.45;
      final color = _lampColors[i % _lampColors.length];
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [color.withOpacity(0.0), color.withOpacity(0.6), color.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(x, y, len, 2))
        ..strokeWidth = 1.6 + r.nextDouble() * 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, y), Offset(x + len, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StreakPainter oldDelegate) => oldDelegate.t != t;
}

/// The quiet night scene sitting behind the fogged glass — a dusk
/// gradient with a handful of lamp-streaks drifting continuously
/// (looping, unlike the tear's one-shot streaks), so there's always
/// something worth wiping the window clear to see.
class _DuskWindowBackdrop extends StatelessWidget {
  final double loop; // 0..1, repeating
  const _DuskWindowBackdrop({required this.loop});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SeenlyPalette.ink, Color.lerp(SeenlyPalette.ink, SeenlyPalette.mustard, 0.16)!],
        ),
      ),
      child: CustomPaint(painter: _IdleStreakPainter(loop: loop), size: Size.infinite),
    );
  }
}

class _IdleStreakPainter extends CustomPainter {
  final double loop;
  const _IdleStreakPainter({required this.loop});

  static const _lampColors = [Color(0xFFFFC978), Color(0xFFFF9E5E), Color(0xFFFFE0A3)];

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(0x4E4947); // fixed lanes — a calm, familiar route
    for (int i = 0; i < 6; i++) {
      final y = r.nextDouble() * size.height;
      final len = 36 + r.nextDouble() * 60;
      final speed = 0.45 + r.nextDouble() * 0.6;
      final laneT = (loop * speed) % 1.0;
      final x = size.width * (1 - laneT);
      final color = _lampColors[i % _lampColors.length];
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [color.withOpacity(0.0), color.withOpacity(0.5), color.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(x, y, len, 1.6))
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, y), Offset(x + len, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _IdleStreakPainter oldDelegate) => oldDelegate.loop != loop;
}

/// The condensation on the glass — a flat wash of "paper" fog with a
/// trail of circles punched clear wherever a finger's actually wiped,
/// using a clear-blend so what's underneath shows through cleanly
/// rather than just fading — the same technique behind any real
/// scratch-off reveal.
class _FogPainter extends CustomPainter {
  final List<Offset> points;
  final double radius;
  final double opacity;

  const _FogPainter({required this.points, required this.radius, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = SeenlyPalette.paper.withOpacity(opacity.clamp(0.0, 1.0)));
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final p in points) {
      canvas.drawCircle(p, radius, clear);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FogPainter oldDelegate) =>
      oldDelegate.points.length != points.length || oldDelegate.opacity != opacity;
}

class _PunchDot {
  final double angle;
  final double distance;
  final double gravity;
  final double rotationSpeed;
  final double size;
  final Color color;

  const _PunchDot({
    required this.angle,
    required this.distance,
    required this.gravity,
    required this.rotationSpeed,
    required this.size,
    required this.color,
  });
}

/// The scatter of tiny punched-paper dots that flicks free the instant
/// the pass tears — round, small, and quick, the conductor's hole-punch
/// confetti rather than the ticket theme's tumbling paper scraps.
class _PunchBurst extends StatelessWidget {
  final double t;
  final List<_PunchDot> dots;

  const _PunchBurst({required this.t, required this.dots});

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final burstT = Curves.easeOut.transform((t / 0.35).clamp(0.0, 1.0));
    final fallT = Curves.easeIn.transform(((t - 0.1) / 0.9).clamp(0.0, 1.0));
    final opacity = 1 - Curves.easeIn.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0));
    if (opacity <= 0) return const SizedBox.shrink();

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: dots.map((d) {
        final dx = math.cos(d.angle) * d.distance * burstT;
        final dy = math.sin(d.angle) * d.distance * burstT + fallT * d.gravity;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              width: d.size,
              height: d.size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: d.color),
            ),
          ),
        );
      }).toList(),
    );
  }
}
