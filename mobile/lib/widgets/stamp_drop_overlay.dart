import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart' show flashOpacity;
import 'stamp.dart';
import 'wow_effects.dart';
import '../services/app_translations.dart';

/// The passport theme's counterpart to `ticket_drop_overlay.dart`: the
/// stamp hovers just above the page, waiting for you to press it down
/// — drag it downward (or just tap it), the same physical motion as
/// actually stamping something, just softened and put in your hands.
///
/// The instant it lands, a scatter of tiny ink droplets flicks outward
/// and a soft glow blooms behind the page — the same "moment sealed in
/// light" beat as the ticket tear, tinted to how the evening felt, so
/// the two themes' rituals feel like one idea worn two ways.
///
/// Call [showStampDrop] rather than constructing this directly.
Future<void> showStampDrop(
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
        child: _StampDropOverlay(
          title: title,
          mediaType: mediaType,
          rating: rating,
          watchedAt: watchedAt,
        ),
      ),
    ),
  );
}

class _StampDropOverlay extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;

  const _StampDropOverlay({
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
  });

  @override
  State<_StampDropOverlay> createState() => _StampDropOverlayState();
}

class _StampDropOverlayState extends State<_StampDropOverlay> with TickerProviderStateMixin {
  late final AnimationController _appear; // one-shot: the stamp settles in, hovering
  late final AnimationController _hintPulse; // loops: "press it down" nudge
  late final AnimationController _snapBack; // one-shot: released too early, springs back up
  late final AnimationController _land; // one-shot: the committed press + settle
  late final List<_Droplet> _droplets; // this evening's ink burst, seeded once

  // How far pressed down the stamp currently is, 0 (hovering) to 1
  // (fully landed) — tracks the drag live rather than a fixed timeline.
  double _dragPress = 0.0;
  double _dragPressAtRelease = 0.0;
  bool _committed = false;
  bool _dragging = false;
  bool _popped = false;

  Timer? _landWatchdog;

  static const double _pressThreshold = 0.5;
  static const double _maxDragPx = 90;
  static const double _flingVelocity = 450;

  @override
  void initState() {
    super.initState();
    _droplets = _makeDroplets(
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
        if (status == AnimationStatus.completed) _dragPress = 0;
      });
    _land = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _popOnce();
      });
  }

  @override
  void dispose() {
    _landWatchdog?.cancel();
    _appear.dispose();
    _hintPulse.dispose();
    _snapBack.dispose();
    _land.dispose();
    super.dispose();
  }

  static List<_Droplet> _makeDroplets({
    required String title,
    required DateTime watchedAt,
    required int? rating,
    required String mediaType,
  }) {
    final r = math.Random(Object.hash(title, watchedAt, rating, mediaType, 'ink'));
    final ink = SeenlyPalette.ratingColor(rating);
    return List.generate(10, (i) {
      final angle = r.nextDouble() * math.pi * 2;
      return _Droplet(
        angle: angle,
        distance: 20 + r.nextDouble() * 46,
        size: 2 + r.nextDouble() * 3.2,
        delay: r.nextDouble() * 0.12,
        color: ink,
      );
    });
  }

  void _popOnce() {
    if (_popped || !mounted) return;
    _popped = true;
    _landWatchdog?.cancel();
    Navigator.of(context).pop();
  }

  void _onDragStart(DragStartDetails _) {
    if (_committed) return;
    final currentVisual = _dragPress * (1 - Curves.easeOut.transform(_snapBack.value));
    _snapBack.stop();
    setState(() {
      _dragPress = currentVisual;
      _dragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_committed) return;
    final wasPastThreshold = _dragPress >= _pressThreshold;
    setState(() {
      _dragPress = (_dragPress + d.delta.dy.abs() / _maxDragPx).clamp(0.0, 1.0).toDouble();
    });
    if (!wasPastThreshold && _dragPress >= _pressThreshold) {
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_committed) return;
    setState(() => _dragging = false);
    final flung = d.velocity.pixelsPerSecond.dy.abs() > _flingVelocity;
    if (_dragPress >= _pressThreshold || flung) {
      _commitPress();
    } else {
      _dragPressAtRelease = _dragPress;
      _snapBack.forward(from: 0);
    }
  }

  void _onTap() {
    if (!_committed) _commitPress();
  }

  void _commitPress() {
    HapticFeedback.mediumImpact();
    _dragPressAtRelease = _dragPress;
    setState(() => _committed = true);
    _land.forward(from: 0);
    _landWatchdog?.cancel();
    _landWatchdog = Timer(_land.duration! * 2, _popOnce);
  }

  void _skip() => _popOnce();

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOutBack.transform(_appear.value);

    final livePress =
        _dragging ? _dragPress : _dragPress * (1 - Curves.easeOut.transform(_snapBack.value));

    final landV = _land.value;
    final press = _committed ? _pressAtCommitBlend(landV) : livePress;

    // A quick squash right around the moment of impact — the "thunk" —
    // rather than a smooth glide all the way through.
    final squash = _committed ? 1 - 0.16 * math.sin(landV.clamp(0.0, 0.3) / 0.3 * math.pi) : 1.0;
    final hover = -16 * (1 - press);

    final hintVisible = !_dragging && !_committed && _dragPress < 0.05;
    final hintPulse = 0.5 + 0.5 * _hintPulse.value;

    final captionT = _committed ? Curves.easeOut.transform((landV / 0.45).clamp(0.0, 1.0).toDouble()) : 0.0;
    final overlayFade = _committed
        ? 1.0 - Curves.easeIn.transform(((landV - 0.78) / 0.22).clamp(0.0, 1.0).toDouble())
        : 1.0;

    final flashA = flashOpacity(_committed ? landV : 0.0, riseEnd: 0.28);
    final glowColor = SeenlyPalette.ratingColor(widget.rating);

    final dropletT = _committed
        ? Curves.easeOut.transform(((landV - 0.18) / 0.4).clamp(0.0, 1.0).toDouble())
        : 0.0;
    final dropletFade = 1 - Curves.easeIn.transform(((landV - 0.55) / 0.45).clamp(0.0, 1.0).toDouble());

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: SeenlyPalette.ink.withOpacity(0.32),
          child: SafeArea(
            child: Opacity(
              opacity: overlayFade.clamp(0.0, 1.0),
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
                            style: SeenlyText.mono(
                                size: 11, color: SeenlyPalette.paper.withOpacity(0.7))),
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: captionT,
                          child: Transform.translate(
                            offset: Offset(0, (1 - captionT) * 8),
                            child: Text('sealed for tonight'.tr,
                                style: SeenlyText.serif(
                                    italic: true, size: 15, color: SeenlyPalette.paper)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 260,
                          height: 220,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              // The passport page itself, sitting still,
                              // waiting for the stamp.
                              IgnorePointer(
                                child: Container(
                                  width: 180,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    color: SeenlyPalette.paper.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: SeenlyPalette.paper.withOpacity(0.22)),
                                  ),
                                ),
                              ),
                              // Warm glow, blooming the instant it lands.
                              IgnorePointer(
                                child: Opacity(
                                  opacity: (flashA * 0.5).clamp(0.0, 1.0),
                                  child: Container(
                                    width: 240,
                                    height: 240,
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
                              // The scatter of ink that flicks free on impact.
                              IgnorePointer(
                                child: _InkBurst(
                                  t: dropletT,
                                  fade: dropletFade.clamp(0.0, 1.0),
                                  droplets: _droplets,
                                ),
                              ),
                              Transform.translate(
                                offset: Offset(0, hover),
                                child: Transform.scale(
                                  scaleY: squash,
                                  scaleX: 2 - squash,
                                  child: Opacity(
                                    opacity: appear.clamp(0.0, 1.0).toDouble(),
                                    child: FoilRingShimmer(
                                      // A ring of foil-bright shine spins
                                      // once around the stamp right as it
                                      // presses down — the same "moment
                                      // sealed in light" beat, but as a
                                      // glint rather than a plain glow.
                                      t: _committed ? flashA : 0.0,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _onTap,
                                        onVerticalDragStart: _onDragStart,
                                        onVerticalDragUpdate: _onDragUpdate,
                                        onVerticalDragEnd: _onDragEnd,
                                        child: StampWidget(
                                          title: widget.title,
                                          mediaType: widget.mediaType,
                                          rating: widget.rating,
                                          watchedAt: widget.watchedAt,
                                          size: 132,
                                          press: press,
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
                          opacity:
                              hintVisible ? (appear * hintPulse).clamp(0.0, 1.0).toDouble() : 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_downward,
                                  size: 13, color: SeenlyPalette.paper.withOpacity(0.75)),
                              const SizedBox(width: 6),
                              Text('press it down — or just tap'.tr,
                                  style: SeenlyText.mono(
                                      size: 10, color: SeenlyPalette.paper.withOpacity(0.75))),
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
      ),
    );
  }

  /// Once committed, blends from wherever the drag left the press
  /// (threshold up to 1.0) the rest of the way to fully landed over
  /// the land animation's first ~20%, so a threshold-only press and a
  /// full drag both arrive smoothly rather than snapping.
  double _pressAtCommitBlend(double landV) {
    final finish = Curves.easeOut.transform((landV / 0.2).clamp(0.0, 1.0).toDouble());
    return _dragPressAtRelease + (1 - _dragPressAtRelease) * finish;
  }
}

/// One ink droplet's fixed flight parameters — seeded once per evening.
class _Droplet {
  final double angle;
  final double distance;
  final double size;
  final double delay;
  final Color color;

  const _Droplet({
    required this.angle,
    required this.distance,
    required this.size,
    required this.delay,
    required this.color,
  });
}

/// The quick scatter of ink that flicks outward the instant the stamp
/// lands — small, sharp, and short-lived, unlike the ticket theme's
/// tumbling paper scraps, since ink flicks rather than falls.
class _InkBurst extends StatelessWidget {
  final double t; // 0..1, own eased progress (already computed by caller)
  final double fade; // 0..1, already computed by caller
  final List<_Droplet> droplets;

  const _InkBurst({required this.t, required this.fade, required this.droplets});

  @override
  Widget build(BuildContext context) {
    if (t <= 0 || fade <= 0) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: droplets.map((d) {
        final local = ((t - d.delay) / (1 - d.delay)).clamp(0.0, 1.0);
        final eased = Curves.easeOut.transform(local);
        final dx = math.cos(d.angle) * d.distance * eased;
        final dy = math.sin(d.angle) * d.distance * eased;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: fade,
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
