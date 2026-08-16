import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart' show flashOpacity;
import 'ticket.dart';
import 'wow_effects.dart';
import '../services/app_translations.dart';

/// Plays right after an evening is saved: the ticket settles in whole,
/// then waits for *you* to tear it — drag it apart (or just tap it if
/// you're not in the mood to drag), same motion as tearing a stub at the
/// door, just softened and put in your hands instead of on a timer.
///
/// The moment it tears open, a handful of paper scraps — tiny torn-off
/// [MiniTicketChip]s in the evening's own colors — burst outward and
/// fall away, and a soft, rating-tinted glow blooms behind the ticket:
/// the same "moment sealed in light" beat as the lamp in
/// `seat_picker_overlay.dart`, so the two scenes read as one ritual.
///
/// Call [showTicketDrop] rather than constructing this directly — it
/// handles pushing the transparent route and popping itself when done.
Future<void> showTicketDrop(
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
        child: _TicketDropOverlay(
          title: title,
          mediaType: mediaType,
          rating: rating,
          watchedAt: watchedAt,
        ),
      ),
    ),
  );
}

class _TicketDropOverlay extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;

  const _TicketDropOverlay({
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
  });

  @override
  State<_TicketDropOverlay> createState() => _TicketDropOverlayState();
}

class _TicketDropOverlayState extends State<_TicketDropOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _appear; // one-shot: ticket settles in
  late final AnimationController _hintPulse; // loops: "drag to tear" nudge
  late final AnimationController _snapBack; // one-shot: released too early
  late final AnimationController _fall; // one-shot: after a committed tear
  late final List<_Scrap> _scraps; // this evening's confetti, seeded once

  // How far torn apart the ticket currently is, 0 (whole) to 1 (fully
  // torn) — driven live by the drag itself, not a fixed timeline, so it
  // genuinely tracks your finger rather than just approving a gesture.
  double _dragTear = 0.0;
  double _dragTearAtRelease = 0.0;
  bool _committed = false;
  bool _dragging = false;
  bool _popped = false;

  // Watchdog: if the fall animation never reports "completed" (dropped
  // frame, controller somehow stuck, whatever), this makes sure the
  // overlay still gets out of the way instead of trapping the user on
  // a screen with no way forward besides "skip".
  Timer? _fallWatchdog;

  static const double _tearThreshold = 0.5;
  static const double _maxDragPx = 130;
  static const double _flingVelocity = 500;

  @override
  void initState() {
    super.initState();
    _scraps = _makeScraps(
      title: widget.title,
      watchedAt: widget.watchedAt,
      rating: widget.rating,
      mediaType: widget.mediaType,
    );
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
  }

  @override
  void dispose() {
    _fallWatchdog?.cancel();
    _appear.dispose();
    _hintPulse.dispose();
    _snapBack.dispose();
    _fall.dispose();
    super.dispose();
  }

  static List<_Scrap> _makeScraps({
    required String title,
    required DateTime watchedAt,
    required int? rating,
    required String mediaType,
  }) {
    final r = math.Random(Object.hash(title, watchedAt, rating, mediaType));
    final colors = [
      SeenlyPalette.ratingColor(rating),
      SeenlyPalette.mediaColor(mediaType),
      SeenlyPalette.paper,
    ];
    return List.generate(12, (i) {
      // Spread mostly upward and outward from the tear point, like
      // real torn paper catching a little air rather than just
      // dropping straight down.
      final angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.4;
      return _Scrap(
        angle: angle,
        distance: 30 + r.nextDouble() * 68,
        gravity: 60 + r.nextDouble() * 90,
        rotationBase: r.nextDouble() * math.pi * 2,
        rotationSpeed: (r.nextBool() ? 1 : -1) * (2 + r.nextDouble() * 3),
        width: 7 + r.nextDouble() * 5,
        height: 11 + r.nextDouble() * 7,
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
      HapticFeedback.selectionClick(); // a little tick right at the point of no return
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
    _dragTearAtRelease = _dragTear; // wherever the drag (or tap, still 0) left off
    setState(() => _committed = true);
    _fall.forward(from: 0);
    // Give the animation generous headroom over its own duration, then
    // force the pop if it still hasn't happened — better a slightly late
    // dismissal than an overlay that never goes away.
    _fallWatchdog?.cancel();
    _fallWatchdog = Timer(_fall.duration! * 2, _popOnce);
  }

  void _skip() {
    _popOnce();
  }

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOutBack.transform(_appear.value);

    // While the person is dragging (or it's springing back from an
    // aborted pull), the tear tracks that directly. Once committed, the
    // first slice of the fall animation finishes off whatever tear was
    // left, then the rest of the fall handles the actual falling/fading.
    final liveTear = _dragging
        ? _dragTear
        : _dragTear * (1 - Curves.easeOut.transform(_snapBack.value));

    final fallV = _fall.value;
    final tear = _committed
        ? _dragTearAtCommitBlend(fallV)
        : liveTear;

    final fallProgress = _committed
        ? Curves.easeIn.transform(((fallV - 0.18) / 0.82).clamp(0.0, 1.0).toDouble())
        : 0.0;
    final fall = fallProgress * 340;
    final fade = _committed
        ? 1.0 - Curves.easeIn.transform(((fallV - 0.72) / 0.28).clamp(0.0, 1.0).toDouble())
        : 1.0;

    // The hint (and its little pulse) only makes sense before anything's
    // happened — fades out the moment a drag starts or it's torn.
    final hintVisible = !_dragging && !_committed && _dragTear < 0.05;
    final hintPulse = 0.5 + 0.5 * _hintPulse.value;

    // Caption shows once the tear has properly committed, drifting up and
    // fading as the ticket falls away beneath it.
    final captionT = _committed
        ? Curves.easeOut.transform((fallV / 0.5).clamp(0.0, 1.0).toDouble())
        : 0.0;
    final captionFade = _committed
        ? 1.0 - Curves.easeIn.transform(((fallV - 0.7) / 0.3).clamp(0.0, 1.0).toDouble())
        : 0.0;

    // The flash blooms right as the tear commits and fades out over the
    // first chunk of the fall — the same "sealed in light" beat used in
    // the seat picker's lamp, tinted to how the evening felt.
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
                      child: Text('skip'.tr,
                          style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.7))),
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
                          child: Text(
                            'tucked away for tonight'.tr,
                            style: SeenlyText.serif(
                                italic: true, size: 15, color: SeenlyPalette.paper),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 320,
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            // Warm glow, blooming from behind the ticket
                            // the instant the tear commits.
                            IgnorePointer(
                              child: Opacity(
                                opacity: (flashA * 0.5).clamp(0.0, 1.0),
                                child: Container(
                                  width: 260,
                                  height: 260,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        glowColor.withOpacity(0.8),
                                        glowColor.withOpacity(0.0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // A fan of gold light — premiere-night rays,
                            // not just a spark — blooming behind the tear
                            // in the same beat as the glow and confetti.
                            GoldRayBurst(t: flashA),
                            // The scraps that fly free the moment it tears.
                            IgnorePointer(
                              child: _ConfettiBurst(t: _committed ? fallV : 0.0, scraps: _scraps),
                            ),
                            Transform.translate(
                              offset: Offset(0, fall),
                              child: Opacity(
                                opacity: (appear * fade).clamp(0.0, 1.0).toDouble(),
                                child: Transform.scale(
                                  scale: 0.85 + appear * 0.15,
                                  child: SpotlightSweep(
                                    // Plays once as the ticket settles in —
                                    // a beam of light switching on and
                                    // sliding across it, projector-style.
                                    progress: _appear.value,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _onTap,
                                      onHorizontalDragStart: _onDragStart,
                                      onHorizontalDragUpdate: _onDragUpdate,
                                      onHorizontalDragEnd: _onDragEnd,
                                      child: TicketWidget(
                                        title: widget.title,
                                        mediaType: widget.mediaType,
                                        rating: widget.rating,
                                        watchedAt: widget.watchedAt,
                                        width: 250,
                                        height: 112,
                                        tearProgress: tear,
                                      ),
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
                        opacity: hintVisible ? (appear * hintPulse).clamp(0.0, 1.0).toDouble() : 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swipe, size: 13, color: SeenlyPalette.paper.withOpacity(0.75)),
                            const SizedBox(width: 6),
                            Text('tug it apart — or just tap'.tr,
                                style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper.withOpacity(0.75))),
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

  /// Once committed, blends from wherever the drag left the tear (could
  /// be anywhere from the threshold up to 1.0) the rest of the way to a
  /// fully torn ticket over the fall's first ~18%, so a threshold-only
  /// tear and a full drag-to-the-end tear both arrive at "torn" smoothly
  /// rather than snapping.
  double _dragTearAtCommitBlend(double fallV) {
    final finish = Curves.easeOut.transform((fallV / 0.18).clamp(0.0, 1.0).toDouble());
    return _dragTearAtRelease + (1 - _dragTearAtRelease) * finish;
  }
}

/// One paper scrap's fixed flight parameters — seeded once per evening
/// so a rebuild doesn't reshuffle the burst mid-flight.
class _Scrap {
  final double angle;
  final double distance;
  final double gravity;
  final double rotationBase;
  final double rotationSpeed;
  final double width;
  final double height;
  final Color color;

  const _Scrap({
    required this.angle,
    required this.distance,
    required this.gravity,
    required this.rotationBase,
    required this.rotationSpeed,
    required this.width,
    required this.height,
    required this.color,
  });
}

/// The burst of torn-off [MiniTicketChip]s that flies free the instant
/// the tear commits — a quick outward scatter, then gravity takes over
/// and they fall away and fade, same beat as the ticket itself falling.
class _ConfettiBurst extends StatelessWidget {
  final double t; // 0 (nothing yet) .. 1 (matches _fall's timeline)
  final List<_Scrap> scraps;

  const _ConfettiBurst({required this.t, required this.scraps});

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
      children: scraps.map((s) {
        final dx = math.cos(s.angle) * s.distance * burstT;
        final dy = math.sin(s.angle) * s.distance * burstT + fallT * s.gravity;
        final rotation = s.rotationBase + t * s.rotationSpeed;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: rotation,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: MiniTicketChip(color: s.color, width: s.width, height: s.height),
            ),
          ),
        );
      }).toList(),
    );
  }
}
