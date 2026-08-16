import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart' show flashOpacity;
import '../services/app_translations.dart';

/// Plays right after an evening is saved in the garden theme — the
/// seed from [showGardenPlant] has taken root as a closed bud, and
/// waits for *you* to coax it open: drag its petals apart (or just tap
/// it if you're not in the mood to drag), the garden's answer to
/// tearing a ticket or a boarding pass — same drag-apart physicality,
/// just softened into "opening" instead of "tearing".
///
/// The instant it opens, a little drift of golden pollen lifts free and
/// a warm glow blooms behind it — the same "moment sealed in light"
/// beat as the other two themes' tear, so all three read as one ritual
/// worn three ways.
///
/// Call [showBloomDrop] rather than constructing this directly.
Future<void> showBloomDrop(
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
        child: _BloomDropOverlay(title: title, mediaType: mediaType, rating: rating, watchedAt: watchedAt),
      ),
    ),
  );
}

class _BloomDropOverlay extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  const _BloomDropOverlay({
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
  });

  @override
  State<_BloomDropOverlay> createState() => _BloomDropOverlayState();
}

class _BloomDropOverlayState extends State<_BloomDropOverlay> with TickerProviderStateMixin {
  late final AnimationController _appear; // one-shot: overlay settles in
  late final AnimationController _hintPulse; // loops: "drag to open" nudge
  late final AnimationController _snapBack; // one-shot: released too early
  late final AnimationController _open; // one-shot: after a committed open
  late final List<_PollenMote> _pollen; // this evening's drift, seeded once

  // How far open the bud currently is, 0 (closed) to 1 (fully bloomed) —
  // driven live by the drag itself while your finger's on it, not a
  // fixed timeline, so it genuinely tracks the gesture.
  double _dragOpen = 0.0;
  double _dragOpenAtRelease = 0.0;
  bool _committed = false;
  bool _dragging = false;
  bool _popped = false;

  Timer? _openWatchdog;

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  static const double _openThreshold = 0.5;
  static const double _maxDragPx = 130;
  static const double _flingVelocity = 500;

  @override
  void initState() {
    super.initState();
    _pollen = _makePollen(title: widget.title, watchedAt: widget.watchedAt, rating: widget.rating);
    _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..addListener(() => setState(() {}))
      ..forward();
    _hintPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..addListener(() => setState(() {}))
      ..repeat(reverse: true);
    _snapBack = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _dragOpen = 0;
      });
    _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 950))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          Future.delayed(const Duration(milliseconds: 450), _popOnce);
        }
      });
  }

  @override
  void dispose() {
    _openWatchdog?.cancel();
    _appear.dispose();
    _hintPulse.dispose();
    _snapBack.dispose();
    _open.dispose();
    super.dispose();
  }

  static List<_PollenMote> _makePollen({
    required String title,
    required DateTime watchedAt,
    required int? rating,
  }) {
    final r = math.Random(Object.hash(title, watchedAt, rating, 'pollen'));
    return List.generate(10, (i) {
      final angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.3;
      return _PollenMote(
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
    _openWatchdog?.cancel();
    Navigator.of(context).pop();
  }

  void _onDragStart(DragStartDetails _) {
    if (_committed) return;
    final currentVisual = _dragOpen * (1 - Curves.easeOut.transform(_snapBack.value));
    _snapBack.stop();
    setState(() {
      _dragOpen = currentVisual;
      _dragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_committed) return;
    final wasPastThreshold = _dragOpen >= _openThreshold;
    setState(() {
      _dragOpen = (_dragOpen + d.delta.dx.abs() / _maxDragPx).clamp(0.0, 1.0).toDouble();
    });
    if (!wasPastThreshold && _dragOpen >= _openThreshold) {
      HapticFeedback.selectionClick(); // a little tick right at the point it takes
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_committed) return;
    setState(() => _dragging = false);
    final flung = d.velocity.pixelsPerSecond.dx.abs() > _flingVelocity;
    if (_dragOpen >= _openThreshold || flung) {
      _commitOpen();
    } else {
      _dragOpenAtRelease = _dragOpen;
      _snapBack.forward(from: 0);
    }
  }

  void _onTap() {
    if (!_committed) _commitOpen();
  }

  void _commitOpen() {
    HapticFeedback.mediumImpact();
    _dragOpenAtRelease = _dragOpen;
    setState(() => _committed = true);
    _open.forward(from: 0);
    _openWatchdog?.cancel();
    _openWatchdog = Timer(_open.duration! * 3, _popOnce);
  }

  void _skip() => _popOnce();

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOutBack.transform(_appear.value);

    final liveOpen = _dragging
        ? _dragOpen
        : _dragOpen * (1 - Curves.easeOut.transform(_snapBack.value));
    final openV = _open.value;
    final spread = _committed ? _dragOpenAtCommitBlend(openV) : liveOpen;

    final hintVisible = !_dragging && !_committed && _dragOpen < 0.05;
    final hintPulse = 0.5 + 0.5 * _hintPulse.value;

    final cardT = _committed
        ? Curves.easeOutCubic.transform(((openV - 0.35) / 0.45).clamp(0.0, 1.0).toDouble())
        : 0.0;

    final flashA = flashOpacity(_committed ? openV : 0.0, riseEnd: 0.3);
    final pollenT = _committed ? openV : 0.0;
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
                            IgnorePointer(child: _PollenBurst(t: pollenT, motes: _pollen, color: glowColor)),
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
                                  child: _OpeningBud(
                                    spread: spread.clamp(0.0, 1.15).toDouble(),
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
                            Text('coax the petals apart — or just tap'.tr,
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
                            decoration: BoxDecoration(
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
                                  '${widget.watchedAt.day} ${_months[widget.watchedAt.month - 1]} · bloomed in the bed',
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

  /// Once committed, blends from wherever the drag left the opening
  /// (could be anywhere from the threshold up to 1.0) the rest of the
  /// way to a fully open bloom over the first half of [_open], with a
  /// little elastic overshoot for a satisfying "pop" — then holds at
  /// full bloom while the card slides in.
  double _dragOpenAtCommitBlend(double openV) {
    final finish = Curves.elasticOut.transform((openV / 0.5).clamp(0.0, 1.0).toDouble());
    return _dragOpenAtRelease + (1 - _dragOpenAtRelease) * finish;
  }
}

/// The bud itself — closed and slender at [spread] 0, opening into a
/// full ring of petals around the media icon as [spread] approaches 1,
/// tracking the drag directly rather than playing on a fixed timeline.
class _OpeningBud extends StatelessWidget {
  final double spread; // 0 (closed bud) .. ~1.15 (a touch of overshoot)
  final Color color;
  final String mediaType;
  const _OpeningBud({required this.spread, required this.color, required this.mediaType});

  @override
  Widget build(BuildContext context) {
    final s = spread.clamp(0.0, 1.15).toDouble();
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
                    width: 18 + 12 * s,
                    height: 22 + 16 * s,
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
          // The closed bud's sepal, showing while still mostly shut and
          // fading out as the real petals take over.
          Opacity(
            opacity: (1 - s * 1.6).clamp(0.0, 1.0).toDouble(),
            child: Container(
              width: 26,
              height: 40,
              decoration: BoxDecoration(
                color: SeenlyPalette.sage,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          Transform.scale(
            scale: 0.7 + 0.3 * s.clamp(0.0, 1.0).toDouble(),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(color: Color(0xFFF0DFA0), shape: BoxShape.circle),
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

class _PollenMote {
  final double angle;
  final double distance;
  final double lift;
  final double size;
  const _PollenMote({required this.angle, required this.distance, required this.lift, required this.size});
}

/// The little drift of golden pollen that lifts free the instant the
/// bud opens — rising and fading rather than falling, the garden
/// theme's answer to the ticket's paper confetti and the boarding
/// pass's hole-punch dots.
class _PollenBurst extends StatelessWidget {
  final double t; // 0..1, matches the open animation's timeline
  final List<_PollenMote> motes;
  final Color color;
  const _PollenBurst({required this.t, required this.motes, required this.color});

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
              decoration: BoxDecoration(shape: BoxShape.circle, color: Color.lerp(color, const Color(0xFFF0DFA0), 0.6)!),
            ),
          ),
        );
      }).toList(),
    );
  }
}
