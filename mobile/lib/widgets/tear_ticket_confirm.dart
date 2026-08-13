import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// The jagged seam shared by both halves of [TearTicketConfirm] — a soft,
/// irregular zigzag (paper giving way, not a printed pattern) running the
/// full height of the ticket. Both halves are cut from the same [seed],
/// so the teeth on one side always sit in the notches of the other —
/// the two pieces would still fit back together if you held them up to
/// the light.
Path _raggedSeam(Size size, {required bool edgeOnRight, required int seed}) {
  const teeth = 12;
  const amplitude = 6.5;
  final rnd = math.Random(seed);
  final offsets = List<double>.generate(teeth + 1, (i) {
    if (i == 0 || i == teeth) return 0.0; // corners stay flush with the card
    return (rnd.nextDouble() * 2 - 1) * amplitude;
  });
  final stepH = size.height / teeth;

  final zigzag = Path();
  if (edgeOnRight) {
    zigzag.moveTo(0, -10);
    zigzag.lineTo(size.width, -10);
    for (var i = 0; i <= teeth; i++) {
      zigzag.lineTo(size.width + offsets[i], i * stepH);
    }
    zigzag.lineTo(0, size.height + 10);
    zigzag.close();
  } else {
    zigzag.moveTo(size.width, -10);
    for (var i = 0; i <= teeth; i++) {
      zigzag.lineTo(offsets[i], i * stepH);
    }
    zigzag.lineTo(size.width, size.height + 10);
    zigzag.close();
  }
  return zigzag;
}

/// One half of the ticket: rounded on its outer corners, a small punched
/// notch top and bottom at the seam (the same perforation language as
/// [TicketWidget]), and the ragged tear running down its inner edge.
class _TicketHalfClipper extends CustomClipper<Path> {
  final bool isLeft;
  final int seed;
  final double notchRadius;
  const _TicketHalfClipper({required this.isLeft, required this.seed, required this.notchRadius});

  @override
  Path getClip(Size size) {
    final rrect = isLeft
        ? RRect.fromRectAndCorners(
            Offset.zero & size,
            topLeft: const Radius.circular(18),
            bottomLeft: const Radius.circular(18),
            topRight: const Radius.circular(3),
            bottomRight: const Radius.circular(3),
          )
        : RRect.fromRectAndCorners(
            Offset.zero & size,
            topRight: const Radius.circular(18),
            bottomRight: const Radius.circular(18),
            topLeft: const Radius.circular(3),
            bottomLeft: const Radius.circular(3),
          );
    var base = Path()..addRRect(rrect);
    final notchX = isLeft ? size.width : 0.0;
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(notchX, 0), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(notchX, size.height), radius: notchRadius));
    base = Path.combine(PathOperation.difference, base, notches);
    final ragged = _raggedSeam(size, edgeOnRight: isLeft, seed: seed);
    return Path.combine(PathOperation.intersect, base, ragged);
  }

  @override
  bool shouldReclip(covariant _TicketHalfClipper oldDelegate) => true;
}

/// A soft, paper-shaped shadow under each half, drawn from the same
/// clipped silhouette so it follows the torn edge instead of falling
/// back to a plain rectangle.
class _TicketHalfShadow extends CustomPainter {
  final bool isLeft;
  final int seed;
  final double notchRadius;
  final Color color;
  final double blur;
  const _TicketHalfShadow({
    required this.isLeft,
    required this.seed,
    required this.notchRadius,
    required this.color,
    required this.blur,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final clipper = _TicketHalfClipper(isLeft: isLeft, seed: seed, notchRadius: notchRadius);
    canvas.drawShadow(clipper.getClip(size), color, blur, false);
  }

  @override
  bool shouldRepaint(covariant _TicketHalfShadow oldDelegate) =>
      oldDelegate.blur != blur || oldDelegate.color != color;
}

/// A full ticket, pulled apart with a drag instead of slid across a
/// track — the confirm control for anything final enough to deserve an
/// actual rip rather than a swipe. Drag either half outward (or just
/// drag anywhere on it) and the two pieces peel apart along a jagged
/// seam, twisting slightly the way paper does under real tension;
/// release early and they settle gently back together, unharmed. Pull
/// far enough and the tear goes all the way through — both halves sail
/// the rest of the way apart and fade, and [onConfirmed] fires once
/// they're gone.
///
/// Distinct from `TearToConfirm` (the drag-a-tab-along-a-strip control
/// used elsewhere): this one has no track and no tab. The whole card is
/// the thing coming apart.
class TearTicketConfirm extends StatefulWidget {
  final String label;
  final String confirmedLabel;
  final Color accent;
  final VoidCallback onConfirmed;
  final double height;

  const TearTicketConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.confirmedLabel = 'torn',
    this.accent = SeenlyPalette.coral,
    this.height = 96,
  });

  @override
  State<TearTicketConfirm> createState() => _TearTicketConfirmState();
}

class _TearTicketConfirmState extends State<TearTicketConfirm> with TickerProviderStateMixin {
  // Eases a released, uncommitted drag gently back to whole — a soft
  // settle rather than a hard snap, like paper relaxing once you stop
  // pulling on it.
  late final AnimationController _settleCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..addListener(() {
      if (_settle != null) setState(() => _pull = _settle!.value);
    });
  Animation<double>? _settle;

  // The moment the tear goes all the way through: both halves keep
  // travelling apart and fading, well past where the finger let go.
  late final AnimationController _flyCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final Animation<double> _fly = CurvedAnimation(parent: _flyCtrl, curve: Curves.easeInCubic);
  late final Animation<double> _labelIn = CurvedAnimation(
    parent: _flyCtrl,
    curve: const Interval(0.15, 0.7, curve: Curves.easeOut),
  );

  double _pull = 0; // signed drag distance, px
  double _maxPull = 100;
  bool _torn = false;
  bool _midHapticFired = false;

  static const int _seed = 6301;
  static const double _threshold = 0.6;

  @override
  void dispose() {
    _settleCtrl.dispose();
    _flyCtrl.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails _) {
    if (_torn) return;
    _settleCtrl.stop();
    _midHapticFired = false;
    HapticFeedback.selectionClick();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_torn) return;
    setState(() => _pull = (_pull + details.delta.dx).clamp(-_maxPull * 1.2, _maxPull * 1.2).toDouble());
    final t = (_pull.abs() / _maxPull).clamp(0.0, 1.0);
    if (t >= 0.5 && !_midHapticFired) {
      _midHapticFired = true;
      HapticFeedback.lightImpact();
    } else if (t < 0.5) {
      _midHapticFired = false;
    }
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_torn) return;
    final t = (_pull.abs() / _maxPull).clamp(0.0, 1.0);
    if (t >= _threshold) {
      HapticFeedback.mediumImpact();
      setState(() => _torn = true);
      await _flyCtrl.forward(from: 0);
      widget.onConfirmed();
    } else {
      _settle = Tween<double>(begin: _pull, end: 0)
          .animate(CurvedAnimation(parent: _settleCtrl, curve: Curves.easeOutCubic));
      await _settleCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      _maxPull = (width * 0.24).clamp(64.0, 118.0).toDouble();
      final halfWidth = (width - 2) / 2;
      final t = (_pull.abs() / _maxPull).clamp(0.0, 1.0).toDouble();
      final sign = _pull == 0 ? 1.0 : _pull.sign;

      return AnimatedBuilder(
        animation: _flyCtrl,
        builder: (context, _) {
          final f = _fly.value;
          // While dragging: a modest, legible separation. Once torn:
          // the same motion keeps going, several times further, so the
          // two halves clearly sail apart rather than just stopping.
          final drag = t * 30;
          final flown = f * 190;
          final gap = drag + flown;
          final wobble = math.sin(t * math.pi) * 3 * (1 - f);
          final leftAngle = -(t * 0.10 + f * 0.5) * sign;
          final rightAngle = (t * 0.10 + f * 0.5) * sign;
          final opacity = _torn ? (1 - f).clamp(0.0, 1.0).toDouble() : 1.0;
          final restLabelOpacity = (1 - t * 2.2).clamp(0.0, 1.0).toDouble();
          final notchRadius = widget.height * 0.05;

          return SizedBox(
            width: width,
            height: widget.height + 28,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Hint text and confirmed label, floating above the
                // ticket rather than printed on it, so nothing needs to
                // visually split mid-word as the paper does.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
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
                              style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted, weight: FontWeight.w600)
                                  .copyWith(letterSpacing: 0.5),
                            ),
                          ),
                          if (_torn)
                            Opacity(
                              opacity: _labelIn.value,
                              child: Text(
                                widget.confirmedLabel,
                                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted, weight: FontWeight.w600)
                                    .copyWith(letterSpacing: 0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 22,
                  left: 0,
                  right: 0,
                  height: widget.height,
                  child: GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Left half.
                        Positioned(
                          left: 0,
                          top: 0,
                          width: halfWidth,
                          height: widget.height,
                          child: Transform.translate(
                            offset: Offset(-gap, wobble),
                            child: Opacity(
                              opacity: opacity,
                              child: Transform.rotate(
                                angle: leftAngle,
                                alignment: Alignment.centerRight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _TicketHalfShadow(
                                          isLeft: true,
                                          seed: _seed,
                                          notchRadius: notchRadius,
                                          color: SeenlyPalette.ink.withOpacity(0.18),
                                          blur: 6 + t * 6 + f * 4,
                                        ),
                                      ),
                                    ),
                                    ClipPath(
                                      clipper: _TicketHalfClipper(isLeft: true, seed: _seed, notchRadius: notchRadius),
                                      child: Container(
                                        width: halfWidth,
                                        height: widget.height,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              SeenlyPalette.paper,
                                              Color.lerp(SeenlyPalette.paper, widget.accent, 0.10)!,
                                            ],
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          Icons.local_activity_outlined,
                                          size: widget.height * 0.30,
                                          color: widget.accent.withOpacity(0.55),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Right half.
                        Positioned(
                          left: halfWidth + 2,
                          top: 0,
                          width: halfWidth,
                          height: widget.height,
                          child: Transform.translate(
                            offset: Offset(gap, -wobble),
                            child: Opacity(
                              opacity: opacity,
                              child: Transform.rotate(
                                angle: rightAngle,
                                alignment: Alignment.centerLeft,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _TicketHalfShadow(
                                          isLeft: false,
                                          seed: _seed,
                                          notchRadius: notchRadius,
                                          color: SeenlyPalette.ink.withOpacity(0.18),
                                          blur: 6 + t * 6 + f * 4,
                                        ),
                                      ),
                                    ),
                                    ClipPath(
                                      clipper: _TicketHalfClipper(isLeft: false, seed: _seed, notchRadius: notchRadius),
                                      child: Container(
                                        width: halfWidth,
                                        height: widget.height,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color.lerp(SeenlyPalette.paper, widget.accent, 0.10)!,
                                              SeenlyPalette.paper,
                                            ],
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          _torn ? Icons.check_rounded : Icons.content_cut_rounded,
                                          size: widget.height * 0.26,
                                          color: widget.accent.withOpacity(0.7),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}
