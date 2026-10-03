import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart' show flashOpacity;
import '../services/app_translations.dart';
import '../services/locale_service.dart';
import '../theme/clay_kit.dart';

/// Plays right after an evening is saved in the shuttle theme — the
/// berth from [showShuttleBerth] has docked a sealed capsule, and
/// waits for *you* to pull the release: drag it apart (or just tap it
/// if you're not in the mood to drag), the shuttle's answer to tearing
/// a ticket or a boarding pass, or coaxing a bud open — same
/// drag-apart physicality, just recast as "ignition" instead of
/// "tearing" or "opening".
///
/// The instant it fires, a burst of tiny star sparks lifts free and a
/// warm glow blooms behind it — the same "moment sealed in light" beat
/// as the other three themes' tear/open, so all four read as one
/// ritual worn four ways.
///
/// Call [showLaunchDrop] rather than constructing this directly.
Future<void> showLaunchDrop(
  BuildContext context, {
  required String title,
  required String mediaType,
  required int? rating,
  required DateTime watchedAt,
  int? runtimeMinutes,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _LaunchDropOverlay(title: title, mediaType: mediaType, rating: rating, watchedAt: watchedAt),
      ),
    ),
  );
}

class _LaunchDropOverlay extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  const _LaunchDropOverlay({
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
  });

  @override
  State<_LaunchDropOverlay> createState() => _LaunchDropOverlayState();
}

class _LaunchDropOverlayState extends State<_LaunchDropOverlay> with TickerProviderStateMixin {
  late final AnimationController _appear; // one-shot: overlay settles in
  late final AnimationController _hintPulse; // loops: "pull to ignite" nudge
  late final AnimationController _snapBack; // one-shot: released too early
  late final AnimationController _ignite; // one-shot: after a committed ignition
  late final List<_SparkMote> _sparks; // this evening's burst, seeded once

  // How far ignited the capsule currently is, 0 (sealed) to 1 (fully
  // launched) — driven live by the drag itself while your finger's on
  // it, not a fixed timeline, so it genuinely tracks the gesture.
  double _dragIgnite = 0.0;
  double _dragIgniteAtRelease = 0.0;
  bool _committed = false;
  bool _dragging = false;
  bool _popped = false;

  Timer? _igniteWatchdog;

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];
  // Short Russian month abbreviations for the same date line — kept as
  // its own array rather than routed through the generic .tr table,
  // matching the pattern in garden_drop_overlay.dart.
  static const _monthsRu = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  static const double _igniteThreshold = 0.5;
  static const double _maxDragPx = 130;
  static const double _flingVelocity = 500;

  @override
  void initState() {
    super.initState();
    _sparks = _makeSparks(title: widget.title, watchedAt: widget.watchedAt, rating: widget.rating);
    _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..addListener(() => setState(() {}))
      ..forward();
    _hintPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..addListener(() => setState(() {}))
      ..repeat(reverse: true);
    _snapBack = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _dragIgnite = 0;
      });
    _ignite = AnimationController(vsync: this, duration: const Duration(milliseconds: 950))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          Future.delayed(const Duration(milliseconds: 450), _popOnce);
        }
      });
  }

  @override
  void dispose() {
    _igniteWatchdog?.cancel();
    _appear.dispose();
    _hintPulse.dispose();
    _snapBack.dispose();
    _ignite.dispose();
    super.dispose();
  }

  static List<_SparkMote> _makeSparks({
    required String title,
    required DateTime watchedAt,
    required int? rating,
  }) {
    final r = math.Random(Object.hash(title, watchedAt, rating, 'spark'));
    return List.generate(10, (i) {
      final angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.3;
      return _SparkMote(
        angle: angle,
        distance: 24 + r.nextDouble() * 56,
        lift: 40 + r.nextDouble() * 70,
        size: 2.6 + r.nextDouble() * 2.6,
      );
    });
  }

  void _popOnce() {
    if (_popped || !mounted) return;
    _popped = true;
    _igniteWatchdog?.cancel();
    Navigator.of(context).pop();
  }

  void _onDragStart(DragStartDetails _) {
    if (_committed) return;
    final currentVisual = _dragIgnite * (1 - Curves.easeOut.transform(_snapBack.value));
    _snapBack.stop();
    setState(() {
      _dragIgnite = currentVisual;
      _dragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_committed) return;
    final wasPastThreshold = _dragIgnite >= _igniteThreshold;
    setState(() {
      _dragIgnite = (_dragIgnite + d.delta.dx.abs() / _maxDragPx).clamp(0.0, 1.0).toDouble();
    });
    if (!wasPastThreshold && _dragIgnite >= _igniteThreshold) {
      HapticFeedback.selectionClick(); // a little tick right at the point it takes
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_committed) return;
    setState(() => _dragging = false);
    final flung = d.velocity.pixelsPerSecond.dx.abs() > _flingVelocity;
    if (_dragIgnite >= _igniteThreshold || flung) {
      _commitIgnite();
    } else {
      _dragIgniteAtRelease = _dragIgnite;
      _snapBack.forward(from: 0);
    }
  }

  void _onTap() {
    if (!_committed) _commitIgnite();
  }

  void _commitIgnite() {
    HapticFeedback.mediumImpact();
    _dragIgniteAtRelease = _dragIgnite;
    setState(() => _committed = true);
    _ignite.forward(from: 0);
    _igniteWatchdog?.cancel();
    _igniteWatchdog = Timer(_ignite.duration! * 3, _popOnce);
  }

  void _skip() => _popOnce();

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOutBack.transform(_appear.value);

    final liveIgnite = _dragging
        ? _dragIgnite
        : _dragIgnite * (1 - Curves.easeOut.transform(_snapBack.value));
    final igniteV = _ignite.value;
    final thrust = _committed ? _dragIgniteAtCommitBlend(igniteV) : liveIgnite;

    final hintVisible = !_dragging && !_committed && _dragIgnite < 0.05;
    final hintPulse = 0.5 + 0.5 * _hintPulse.value;

    final cardT = _committed
        ? Curves.easeOutCubic.transform(((igniteV - 0.35) / 0.45).clamp(0.0, 1.0).toDouble())
        : 0.0;

    final flashA = flashOpacity(_committed ? igniteV : 0.0, riseEnd: 0.3);
    final sparkT = _committed ? igniteV : 0.0;
    final glowColor = SeenlyPalette.ratingColor(widget.rating);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: const Color(0xFF171A2E).withOpacity(0.55),
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
                      child: Text('skip'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.7))),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 260,
                        height: 190,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            IgnorePointer(
                              child: Opacity(
                                opacity: (flashA * 0.55).clamp(0.0, 1.0).toDouble(),
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
                            IgnorePointer(child: _SparkBurst(t: sparkT, motes: _sparks, color: glowColor)),
                            Opacity(
                              opacity: appear.clamp(0.0, 1.0).toDouble(),
                              child: Transform.scale(
                                scale: 0.88 + appear * 0.12,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _onTap,
                                  onHorizontalDragStart: _onDragStart,
                                  onHorizontalDragUpdate: _onDragUpdate,
                                  onHorizontalDragEnd: _onDragEnd,
                                  child: _IgnitingPod(
                                    thrust: thrust.clamp(0.0, 1.15).toDouble(),
                                    color: glowColor,
                                    mediaType: widget.mediaType,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Opacity(
                        opacity: hintVisible ? (appear * hintPulse).clamp(0.0, 1.0).toDouble() : 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swipe, size: 13, color: SeenlyPalette.paper.withOpacity(0.75)),
                            const SizedBox(width: 6),
                            Text('pull the release — or just tap'.tr,
                                style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper.withOpacity(0.75))),
                          ],
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, (1 - cardT) * 16),
                        child: Opacity(
                          opacity: cardT.clamp(0.0, 1.0).toDouble(),
                          child: Container(
                            width: 240,
                            margin: const EdgeInsets.only(top: 14),
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                            decoration: ClayBoxDecoration(
                              color: SeenlyPalette.paper,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: SeenlyPalette.softShadow,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: SeenlyText.serif(italic: true, size: 15.5, weight: FontWeight.w600),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${widget.watchedAt.day} ${(LocaleService.appIsRussian ? _monthsRu : _months)[widget.watchedAt.month - 1]} ${'· launched into orbit'.tr}',
                                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                                ),
                              ],
                            ),
                          ),
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

  /// Once committed, blends from wherever the drag left the ignition
  /// (could be anywhere from the threshold up to 1.0) the rest of the
  /// way to a full launch over the first half of [_ignite], with a
  /// little elastic overshoot for a satisfying "kick" — then holds at
  /// full thrust while the card slides in.
  double _dragIgniteAtCommitBlend(double igniteV) {
    final finish = Curves.elasticOut.transform((igniteV / 0.5).clamp(0.0, 1.0).toDouble());
    return _dragIgniteAtRelease + (1 - _dragIgniteAtRelease) * finish;
  }
}

/// The capsule itself — sealed and slender at [thrust] 0, flaring into
/// a full ring of exhaust plumes around the media icon as [thrust]
/// approaches 1, tracking the drag directly rather than playing on a
/// fixed timeline.
class _IgnitingPod extends StatelessWidget {
  final double thrust; // 0 (sealed capsule) .. ~1.15 (a touch of overshoot)
  final Color color;
  final String mediaType;
  const _IgnitingPod({required this.thrust, required this.color, required this.mediaType});

  @override
  Widget build(BuildContext context) {
    final s = thrust.clamp(0.0, 1.15).toDouble();
    return SizedBox(
      width: 120,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (int p = 0; p < 8; p++)
            Transform.rotate(
              angle: p * (math.pi * 2 / 8),
              child: Transform.translate(
                offset: Offset(0, -30 * s),
                child: Opacity(
                  opacity: s.clamp(0.0, 1.0).toDouble(),
                  child: Container(
                    width: 14 + 8 * s,
                    height: 26 + 20 * s,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color.lerp(color, Colors.white, 0.35)!, color],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
          // The capsule's sealed hatch, showing while still mostly
          // closed and fading out as the exhaust plumes take over.
          Opacity(
            opacity: (1 - s * 1.6).clamp(0.0, 1.0).toDouble(),
            child: Container(
              width: 26,
              height: 40,
              decoration: BoxDecoration(
                color: SeenlyPalette.periwinkle,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          Transform.scale(
            scale: 0.7 + 0.3 * s.clamp(0.0, 1.0).toDouble(),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(color: Color(0xFFEAEAF6), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(_mediaIcon(mediaType), size: 15, color: SeenlyPalette.ink.withOpacity(0.65)),
            ),
          ),
        ],
      ),
    );
  }

  IconData _mediaIcon(String mediaType) {
    switch (mediaType) {
      case 'movie':
        return Icons.local_movies_outlined;
      case 'series':
      case 'anime':
        return Icons.live_tv_outlined;
      case 'game':
        return Icons.sports_esports_outlined;
      case 'book':
      case 'manga':
        return Icons.menu_book_outlined;
      default:
        return Icons.movie_creation_outlined;
    }
  }
}

class _SparkMote {
  final double angle;
  final double distance;
  final double lift;
  final double size;
  const _SparkMote({required this.angle, required this.distance, required this.lift, required this.size});
}

/// The little burst of star sparks that lifts free the instant the
/// capsule ignites — rising and fading rather than falling, this
/// theme's answer to the ticket's paper confetti, the boarding pass's
/// hole-punch dots, and the garden's pollen drift.
class _SparkBurst extends StatelessWidget {
  final double t; // 0..1, matches the ignite animation's timeline
  final List<_SparkMote> motes;
  final Color color;
  const _SparkBurst({required this.t, required this.motes, required this.color});

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final burstT = Curves.easeOut.transform((t / 0.4).clamp(0.0, 1.0).toDouble());
    final riseT = Curves.easeOut.transform(((t - 0.1) / 0.9).clamp(0.0, 1.0).toDouble());
    final opacity = 1 - Curves.easeIn.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0).toDouble());
    if (opacity <= 0) return const SizedBox.shrink();

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: motes.map((m) {
        final dx = math.cos(m.angle) * m.distance * burstT;
        final dy = math.sin(m.angle) * m.distance * burstT - riseT * m.lift;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0).toDouble(),
            child: Container(
              width: m.size,
              height: m.size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Color.lerp(color, const Color(0xFFEAEAF6), 0.6)!),
            ),
          ),
        );
      }).toList(),
    );
  }
}
