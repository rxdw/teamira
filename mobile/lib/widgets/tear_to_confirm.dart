import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// The torn-paper edge shared by both halves of [TearToConfirm] — a
/// gentle, irregular zigzag rather than a perfectly even sawtooth, so
/// it reads as paper giving way rather than a printed pattern. Both
/// halves are built from the same [seed], so the teeth on one side
/// always line up with the notches on the other, the way a real torn
/// edge still fits itself back together.
Path _tornPath(Size size, {required bool edgeOnRight, required int seed}) {
  const teeth = 9;
  const amplitude = 5.0;
  final rnd = math.Random(seed);
  final offsets = List<double>.generate(teeth + 1, (i) {
    if (i == 0 || i == teeth) return 0.0; // corners stay flush with the pill shape
    return (rnd.nextDouble() * 2 - 1) * amplitude;
  });
  final stepH = size.height / teeth;

  final zigzag = Path();
  if (edgeOnRight) {
    zigzag.moveTo(0, -6);
    zigzag.lineTo(size.width, -6);
    for (var i = 0; i <= teeth; i++) {
      zigzag.lineTo(size.width + offsets[i], i * stepH);
    }
    zigzag.lineTo(0, size.height + 6);
    zigzag.close();
  } else {
    zigzag.moveTo(size.width, -6);
    for (var i = 0; i <= teeth; i++) {
      zigzag.lineTo(offsets[i], i * stepH);
    }
    zigzag.lineTo(size.width, size.height + 6);
    zigzag.close();
  }

  final shortSide = math.min(size.width, size.height);
  final rounded = Path()
    ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(shortSide / 2)));
  return Path.combine(PathOperation.intersect, rounded, zigzag);
}

class _TornEdgeClipper extends CustomClipper<Path> {
  final bool edgeOnRight;
  final int seed;
  const _TornEdgeClipper({required this.edgeOnRight, required this.seed});

  @override
  Path getClip(Size size) => _tornPath(size, edgeOnRight: edgeOnRight, seed: seed);

  @override
  bool shouldReclip(covariant _TornEdgeClipper oldDelegate) =>
      oldDelegate.edgeOnRight != edgeOnRight || oldDelegate.seed != seed;
}

/// A soft, paper-shaped drop shadow under each torn half — drawn from
/// the exact same path as the clip above, so the shadow's silhouette
/// follows the jagged edge instead of falling back to a plain
/// rectangle underneath it.
class _TornShadowPainter extends CustomPainter {
  final bool edgeOnRight;
  final int seed;
  final Color color;
  const _TornShadowPainter({required this.edgeOnRight, required this.seed, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final path = _tornPath(size, edgeOnRight: edgeOnRight, seed: seed);
    canvas.drawShadow(path, color, 5, false);
  }

  @override
  bool shouldRepaint(covariant _TornShadowPainter oldDelegate) => true;
}

/// A "tear to confirm" control — the drag-and-rip cousin of
/// `SlideToConfirm`. Where the logging flow's ticket only tears open
/// partway (`TicketWidget.tearProgress`, capped mid-tear for the jar
/// and scatter views), dragging this one past the threshold tears
/// clean through: the paper strip splits along a jagged seam and the
/// torn-away piece keeps drifting and fading outward instead of
/// snapping back — no partial reveal, no going back to whole. Letting
/// go early just lets both halves ease back together, unharmed.
///
/// Meant for ending something that's still quietly running (a
/// companion journey) — the one gesture on this screen that should
/// feel as final and physical as the action it triggers.
class TearToConfirm extends StatefulWidget {
  final String label;
  final String confirmedLabel;
  final Color accent;
  final Color trackColor;
  final Color labelColor;
  final VoidCallback onConfirmed;

  const TearToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.confirmedLabel = 'torn',
    this.accent = SeenlyPalette.coral,
    this.trackColor = SeenlyPalette.background,
    this.labelColor = SeenlyPalette.inkMuted,
  });

  @override
  State<TearToConfirm> createState() => _TearToConfirmState();
}

class _TearToConfirmState extends State<TearToConfirm> with TickerProviderStateMixin {
  // Drag-linked spring-back, exactly like SlideToConfirm's own snap.
  late final AnimationController _snapCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addListener(() {
      if (_snap != null) setState(() => _dragX = _snap!.value);
    });
  Animation<double>? _snap;

  // A separate, slower flourish for the moment the tear actually goes
  // through — the torn piece sailing the rest of the way off and
  // fading, distinct from the drag itself.
  late final AnimationController _finishCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  late final Animation<double> _finish = CurvedAnimation(parent: _finishCtrl, curve: Curves.easeInCubic);
  late final Animation<double> _labelIn = CurvedAnimation(
    parent: _finishCtrl,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
  );

  double _dragX = 0;
  double _maxDrag = 1;
  bool _torn = false;

  static const double _tabWidth = 58;
  static const double _trackPad = 4;
  static const int _seed = 4271;

  @override
  void dispose() {
    _snapCtrl.dispose();
    _finishCtrl.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_torn) return;
    setState(() => _dragX = (_dragX + details.delta.dx).clamp(0, _maxDrag));
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_torn) return;
    final completed = _maxDrag > 0 && _dragX >= _maxDrag * 0.7;
    if (completed) {
      setState(() => _torn = true);
      await _snapTo(_maxDrag);
      await _finishCtrl.forward(from: 0);
      widget.onConfirmed();
    } else {
      await _snapTo(0);
    }
  }

  Future<void> _snapTo(double target) {
    _snap = Tween<double>(begin: _dragX, end: target)
        .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic));
    return _snapCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      _maxDrag = (width - _tabWidth - _trackPad * 2).clamp(0, double.infinity);
      final t = _maxDrag == 0 ? 0.0 : (_dragX / _maxDrag).clamp(0, 1).toDouble();
      final height = _tabWidth + _trackPad * 2;

      return AnimatedBuilder(
        animation: _finishCtrl,
        builder: (context, _) {
          final f = _finish.value;
          final bodyLeft = _trackPad + _tabWidth + _dragX;
          final bodyWidth = (width - _trackPad - bodyLeft).clamp(0.0, double.infinity);
          final tabFly = f * 44;
          final tabAngle = f * 0.4;
          final tabFade = 1 - f;
          final restLabelOpacity = (1 - t * 1.7).clamp(0, 1).toDouble();

          return GestureDetector(
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The seam track underneath — a steady pill shape and
                  // border that stays put through the whole gesture, so
                  // the gap left behind by a torn-away piece still reads
                  // as part of one control rather than a hole in the layout.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.trackColor,
                        borderRadius: BorderRadius.circular(height / 2),
                        border: Border.all(color: widget.accent.withOpacity(0.20)),
                      ),
                    ),
                  ),
                  // The remaining body — the part of the strip not yet
                  // torn away. Shrinks from the left as the tab drags
                  // across it, its cut edge always the jagged seam.
                  if (bodyWidth > 0.5)
                    Positioned(
                      left: bodyLeft,
                      top: _trackPad,
                      bottom: _trackPad,
                      width: bodyWidth,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _TornShadowPainter(
                                edgeOnRight: false,
                                seed: _seed,
                                color: SeenlyPalette.ink.withOpacity(0.16),
                              ),
                            ),
                          ),
                          ClipPath(
                            clipper: const _TornEdgeClipper(edgeOnRight: false, seed: _seed),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Color.lerp(widget.trackColor, SeenlyPalette.paper, 0.6)!,
                                    SeenlyPalette.paper,
                                  ],
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // The tab — what the hand actually drags. Carries the
                  // icon, then keeps sailing outward and fading once the
                  // tear goes through, well past where the drag itself
                  // left off.
                  Positioned(
                    left: _trackPad + _dragX + tabFly,
                    top: _trackPad,
                    bottom: _trackPad,
                    width: _tabWidth,
                    child: Opacity(
                      opacity: _torn ? tabFade.clamp(0, 1).toDouble() : 1,
                      child: Transform.rotate(
                        angle: tabAngle,
                        alignment: Alignment.center,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _TornShadowPainter(
                                  edgeOnRight: true,
                                  seed: _seed,
                                  color: SeenlyPalette.ink.withOpacity(0.2),
                                ),
                              ),
                            ),
                            ClipPath(
                              clipper: const _TornEdgeClipper(edgeOnRight: true, seed: _seed),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      widget.accent,
                                      Color.lerp(widget.accent, SeenlyPalette.ink, 0.18)!,
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    _torn ? Icons.check_rounded : Icons.chevron_right_rounded,
                                    color: SeenlyPalette.paper,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Centered label — the initial prompt, fading as the
                  // drag begins, replaced by the confirmed label easing
                  // in once the tear is under way.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: _torn ? 0 : restLabelOpacity,
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SeenlyText.mono(size: 11, color: widget.labelColor, weight: FontWeight.w600)
                                    .copyWith(letterSpacing: 0.6),
                              ),
                            ),
                            if (_torn)
                              Opacity(
                                opacity: _labelIn.value,
                                child: Text(
                                  widget.confirmedLabel,
                                  style: SeenlyText.mono(size: 11, color: widget.labelColor, weight: FontWeight.w600)
                                      .copyWith(letterSpacing: 0.6),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}
