import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'seenly_skin.dart';
import 'text_styles.dart';
import 'clay_kit.dart';

/// Real "this is a diary page" chrome for the Cozy Diary skin — every
/// piece here is either painted directly under real content (the ruled
/// page and its stitched binding sit behind the actual screen, at fixed
/// positions relative to the *page edge*, the way lines on real paper
/// don't move around) or wraps a specific real widget (the underline
/// sits under a specific title's own measured width, the tape pins a
/// specific card, the fold sits on a specific card's own corner).
/// Nothing here floats at a screen-relative coordinate independent of
/// what's actually on screen — that was the problem with the previous
/// global ink-layer overlay this file replaces.

/// Ruled-paper page background: faint horizontal rules, a red margin
/// line, and three binder holes threaded with a stitch — the literal
/// texture of a notebook page, sitting behind the real content rather
/// than drawn on top of it. Meant to go at the very back of a screen's
/// Stack (see RootShell), so scrolling content and cards paint over it
/// exactly like paper under photos and text.
class NotebookPageBackground extends StatelessWidget {
  const NotebookPageBackground({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RuledPagePainter(
            rule: SeenlyPalette.ink.withOpacity(0.05),
            margin: SeenlyPalette.coral.withOpacity(0.16),
            holeFill: SeenlyPalette.background,
            holeRing: SeenlyPalette.ink.withOpacity(0.10),
            thread: SeenlyPalette.tapeRose.withOpacity(0.45),
            ribbon: SeenlyPalette.pink.withOpacity(0.55),
            glow: SeenlyPalette.mustard,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _RuledPagePainter extends CustomPainter {
  final Color rule;
  final Color margin;
  final Color holeFill;
  final Color holeRing;
  final Color thread;
  final Color ribbon;
  final Color glow;
  _RuledPagePainter({
    required this.rule,
    required this.margin,
    required this.holeFill,
    required this.holeRing,
    required this.thread,
    required this.ribbon,
    required this.glow,
  });

  static const _lineGap = 30.0;
  static const _marginX = 34.0;
  static const _holeX = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    // A soft, warm glow in the upper page — like a reading lamp rather
    // than flat screen light — painted first so every other paper mark
    // sits on top of it. Kept very pale; this is ambiance, not a
    // visible shape.
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.6, -0.35),
        radius: 1.1,
        colors: [glow.withOpacity(0.05), Colors.transparent],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glowPaint);

    final rulePaint = Paint()
      ..color = rule
      ..strokeWidth = 1;
    for (var y = _lineGap; y < size.height; y += _lineGap) {
      canvas.drawLine(Offset(_marginX, y), Offset(size.width, y), rulePaint);
    }

    final marginPaint = Paint()
      ..color = margin
      ..strokeWidth = 1.1;
    canvas.drawLine(
        Offset(_marginX, 0), Offset(_marginX, size.height), marginPaint);

    // A loose running stitch threading the binder holes — drawn as one
    // continuous dashed path so it reads as a single piece of string,
    // not three unrelated dots.
    final stitchPaint = Paint()
      ..color = thread
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final holeYs = <double>[];
    for (var y = 96.0; y < size.height - 40; y += 168) {
      holeYs.add(y);
    }
    for (var i = 0; i < holeYs.length; i++) {
      final y = holeYs[i];
      final ringPaint = Paint()..color = holeFill;
      canvas.drawCircle(Offset(_holeX, y), 4.4, ringPaint);
      canvas.drawCircle(
          Offset(_holeX, y), 4.4, Paint()..color = holeRing..style = PaintingStyle.stroke..strokeWidth = 1);
      if (i > 0) {
        final prevY = holeYs[i - 1];
        final path = Path()..moveTo(_holeX, prevY + 5);
        final mid = (prevY + y) / 2;
        path.quadraticBezierTo(_holeX + 7, mid, _holeX, y - 5);
        canvas.drawPath(path, stitchPaint);
      }
    }

    _drawRibbonBookmark(canvas, size);
  }

  /// A fabric ribbon bookmark, sewn into the binding at a fixed point
  /// near the top-right and hanging down over the page a short way —
  /// a real bound-in book part, not a loose sticker, so it always sits
  /// at the same spot regardless of what's scrolling underneath it.
  /// Kept slim and tucked into the outer edge gutter (past where every
  /// screen's own header content stops) so it never overlaps a real
  /// button or title.
  void _drawRibbonBookmark(Canvas canvas, Size size) {
    const width = 11.0;
    const dropLength = 42.0;
    final x = size.width - 19;
    final paint = Paint()..color = ribbon;
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x + width, 0)
      ..lineTo(x + width, dropLength)
      ..lineTo(x + width / 2, dropLength - 9)
      ..lineTo(x, dropLength)
      ..close();
    canvas.drawPath(path, paint);
    // A thin fold shadow down the middle so it reads as cloth, not a flat chip.
    canvas.drawLine(
      Offset(x + width / 2, 0),
      Offset(x + width / 2, dropLength - 6),
      Paint()
        ..color = Colors.black.withOpacity(0.05)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _RuledPagePainter oldDelegate) => false;
}

/// A hand-drawn squiggle underline, sized to [child]'s own natural
/// width (via [IntrinsicWidth]) so it always sits directly under the
/// exact text/title it belongs to rather than a fixed, guessed width.
/// Cozy skin only — renders [child] alone otherwise.
class HandDrawnUnderline extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double thickness;
  final double gap;
  const HandDrawnUnderline({
    super.key,
    required this.child,
    this.color,
    this.thickness = 2.4,
    this.gap = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) return child;
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          SizedBox(height: gap),
          SizedBox(
            height: 8,
            child: HandDrawnLine(color: color ?? SeenlyPalette.accent, thickness: thickness),
          ),
        ],
      ),
    );
  }
}

/// A single reusable hand-drawn stroke — the same soft, wavering line
/// [HandDrawnUnderline] paints under a heading, but free-standing so any
/// other "there's a line here" spot (a tab's active indicator, a plain
/// divider) can use the identical pen stroke instead of each inventing
/// its own. Fills whatever box it's given (wrap it in a sized
/// parent — a fixed-height row, an AnimatedContainer, a Positioned).
/// Falls back to a plain straight line outside the cozy skin, so call
/// sites don't need to branch on [SeenlySkin] themselves.
///
/// Deliberately does *not* use [LayoutBuilder] to read its own size —
/// [LayoutBuilder] can't answer an intrinsic-dimension query, so a copy
/// that did broke the moment it ended up under an [IntrinsicWidth]
/// ancestor (as it does inside [HandDrawnUnderline]) with a confusing
/// "Assertion failed" deep in Flutter's box.dart. A plain empty
/// [SizedBox] as the [CustomPaint] child sizes correctly either way:
/// it reports zero for an intrinsic query (harmless — a sibling like
/// the heading text supplies the real width) and still stretches to
/// fill whatever concrete box it's given once real layout happens.
class HandDrawnLine extends StatelessWidget {
  final Color color;
  final double thickness;
  const HandDrawnLine({super.key, required this.color, this.thickness = 2.4});

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) {
      return DecoratedBox(decoration: BoxDecoration(color: color));
    }
    return CustomPaint(
      painter: SquigglePainter(color: color, thickness: thickness),
      child: const SizedBox(),
    );
  }
}

class SquigglePainter extends CustomPainter {
  final Color color;
  final double thickness;
  SquigglePainter({required this.color, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(0, size.height * 0.6);
    const waveWidth = 16.0;
    var x = 0.0;
    var up = true;
    while (x < size.width) {
      final nextX = math.min(x + waveWidth, size.width);
      final controlY = up ? 0.0 : size.height;
      path.quadraticBezierTo(
        (x + nextX) / 2,
        controlY,
        nextX,
        size.height * 0.6,
      );
      x = nextX;
      up = !up;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SquigglePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.thickness != thickness;
}

/// Circles [child] the way you'd circle a number in a real notebook —
/// a single wobbly loop of pen line drawn around the child's own actual
/// size (via [CustomPaint]'s foreground painter, so it always tracks
/// whatever it's wrapping rather than a fixed-size decoration guessed
/// from outside). Meant for a standalone number worth calling out (a
/// rating stat), not for running text. Cozy skin only — renders
/// [child] alone otherwise.
class HandDrawnCircle extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double thickness;
  final EdgeInsets padding;
  const HandDrawnCircle({
    super.key,
    required this.child,
    this.color,
    this.thickness = 2,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  });

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) return child;
    return CustomPaint(
      foregroundPainter:
          _CircleScribblePainter(color: color ?? SeenlyPalette.accent, thickness: thickness),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _CircleScribblePainter extends CustomPainter {
  final Color color;
  final double thickness;
  _CircleScribblePainter({required this.color, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width / 2;
    final ry = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    var seed = 7;
    double jitter() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return (seed / 0x7fffffff - 0.5) * 3.0;
    }

    // One main loop just outside the number, plus a short second pass
    // over the first quarter-turn — the little overlap flourish people
    // draw without thinking when they circle something they mean.
    const steps = 28;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final t = (i / steps) * 2 * math.pi - math.pi / 2;
      final x = cx + (rx + jitter()) * math.cos(t);
      final y = cy + (ry + jitter()) * math.sin(t);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    final flourish = Path();
    for (var i = 0; i <= steps ~/ 4; i++) {
      final t = (i / steps) * 2 * math.pi - math.pi / 2;
      final x = cx + (rx + 2.4 + jitter()) * math.cos(t);
      final y = cy + (ry + 2.4 + jitter()) * math.sin(t);
      if (i == 0) {
        flourish.moveTo(x, y);
      } else {
        flourish.lineTo(x, y);
      }
    }
    canvas.drawPath(flourish, paint);
  }

  @override
  bool shouldRepaint(covariant _CircleScribblePainter oldDelegate) => false;
}

/// Frames [child] as a real polaroid/instant photo — a white paper mat,
/// thin on three sides and thick at the bottom for a handwritten
/// [caption], a small deterministic tilt (from [tiltSeed], so the same
/// poster always leans the same way rather than jittering between
/// rebuilds), and a soft worn darkening in the corners like an old,
/// handled print. Sized to fill whatever box it's given — the box
/// itself doesn't grow, so this drops into an existing 2:3 poster slot
/// without changing any grid's cell size.
/// Cozy skin only — renders [child] alone otherwise.
class PolaroidFrame extends StatelessWidget {
  final Widget child;
  final String? caption;
  final int tiltSeed;
  const PolaroidFrame({
    super.key,
    required this.child,
    this.caption,
    this.tiltSeed = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) return child;
    // A small, deterministic lean — same poster always tilts the same
    // way, rather than reshuffling every rebuild — so a grid of these
    // reads as "a pile of photos", not a shimmering mess.
    final step = (tiltSeed.abs() % 5) - 2; // -2..2
    final angle = step * 0.017; // ~1° per step, ±~2° at the extremes
    // Fixed logical-pixel margins rather than a percentage of the box's
    // own measured size: reading that size would need a LayoutBuilder,
    // and LayoutBuilder can't answer an intrinsic-dimension query. This
    // widget sits inside an AspectRatio that itself sits inside
    // LogDayGroup's IntrinsicHeight (the diary's dashed thread needs to
    // measure each day's row), so anything here has to stay
    // intrinsic-safe — plain Container padding and a Column/Expanded
    // are, a LayoutBuilder isn't.
    return Transform.rotate(
      angle: angle,
      child: CustomPaint(
        foregroundPainter: _WornCornersPainter(color: SeenlyPalette.ink.withOpacity(0.16)),
        child: Container(
          decoration: ClayBoxDecoration(
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(5),
            boxShadow: SeenlyPalette.softShadow,
          ),
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 3),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: child,
                ),
              ),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: SeenlyText.handwrittenNote(size: 11, color: SeenlyPalette.ink),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WornCornersPainter extends CustomPainter {
  final Color color;
  _WornCornersPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // A soft radial smudge tucked into each corner — the way a print
    // that's been handled a lot gets a little worn and grubby right
    // where fingers pinch it, not a hard mark, just a hint of age.
    final r = size.shortestSide * 0.32;
    for (final corner in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withOpacity(0)],
        ).createShader(Rect.fromCircle(center: corner, radius: r));
      canvas.drawCircle(corner, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WornCornersPainter oldDelegate) => false;
}

/// Drop-in replacement for [Divider] — a straight line outside the cozy
/// skin, a dashed "perforated tear line" inside it, the way notebook
/// pages are actually scored to tear along. Same constructor shape as
/// [Divider] (height/thickness/color/indent/endIndent), so any existing
/// call site can swap the widget name and nothing else.
class CozyDivider extends StatelessWidget {
  final double height;
  final double thickness;
  final Color? color;
  final double indent;
  final double endIndent;
  const CozyDivider({
    super.key,
    this.height = 16,
    this.thickness = 0.8,
    this.color,
    this.indent = 0,
    this.endIndent = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) {
      return Divider(
          height: height, thickness: thickness, color: color, indent: indent, endIndent: endIndent);
    }
    final strokeWidth = thickness < 1.3 ? 1.3 : thickness;
    // No LayoutBuilder here — see HandDrawnLine's note above; a plain
    // empty SizedBox as CustomPaint's child gets the same "safe under
    // an intrinsic query, still stretches to the real width at real
    // layout" behavior without it.
    return SizedBox(
      height: height,
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: endIndent),
          child: CustomPaint(
            painter: _DashPainter(
              color: color ?? SeenlyPalette.dashedBorder,
              strokeWidth: strokeWidth,
            ),
            child: SizedBox(height: strokeWidth),
          ),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  _DashPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    const dash = 5.0;
    const gap = 4.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = math.min(x + dash, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Clips [child] the way a real paperclip holds a little stack of pages
/// together — sat right on [child]'s own top edge (not floating
/// somewhere else on screen), a bit off from dead-center the way an
/// actual paperclip usually is. Meant for a card that's genuinely
/// standing in for a group of things (a season's worth of episodes),
/// not decoration for its own sake. Cozy skin only — renders [child]
/// alone otherwise.
class PaperclipCard extends StatelessWidget {
  final Widget child;
  final double dx;
  const PaperclipCard({super.key, required this.child, this.dx = 22});

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -15,
          left: dx,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: -0.2,
              child: Icon(Icons.attach_file_rounded,
                  size: 32, color: SeenlyPalette.inkFaint.withOpacity(0.6)),
            ),
          ),
        ),
      ],
    );
  }
}

/// A passport/rubber-stamp look for a short status callout ("top",
/// "new", "watched") — a rotated, slightly uneven double ring of ink
/// drawn around whatever [child] actually is (a number, a word, an
/// icon-plus-label row), sized to that content rather than a fixed
/// shape guessed from outside. Reads as *pressed onto* the page, not
/// printed as a flat UI chip. Cozy skin only — renders [child] alone
/// otherwise, so a call site can keep its existing pill/badge for the
/// standard skin and only add this for cozy.
class StampBadge extends StatelessWidget {
  final Widget child;
  final Color color;
  final double angle;
  final EdgeInsets padding;
  const StampBadge({
    super.key,
    required this.child,
    required this.color,
    this.angle = -0.16,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  });

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) return child;
    return Transform.rotate(
      angle: angle,
      child: CustomPaint(
        foregroundPainter: _StampRingPainter(color: color),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _StampRingPainter extends CustomPainter {
  final Color color;
  _StampRingPainter({required this.color});

  Path _wobblyOval(Rect rect, int seedStart, double wobble) {
    final path = Path();
    var seed = seedStart;
    double jitter() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return (seed / 0x7fffffff - 0.5) * wobble;
    }

    const steps = 28;
    for (var i = 0; i <= steps; i++) {
      final t = (i / steps) * 2 * math.pi;
      final rx = rect.width / 2 + jitter();
      final ry = rect.height / 2 + jitter();
      final x = rect.center.dx + rx * math.cos(t);
      final y = rect.center.dy + ry * math.sin(t);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final outer = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    canvas.drawPath(_wobblyOval(outer, 11, 1.4), paint);
    final inner = outer.deflate(3.2);
    if (inner.width > 4 && inner.height > 4) {
      canvas.drawPath(_wobblyOval(inner, 53, 1.0), paint..strokeWidth = 1.1);
    }
  }

  @override
  bool shouldRepaint(covariant _StampRingPainter oldDelegate) => oldDelegate.color != color;
}

/// Drop-in replacement for a `Container(width:, height:, decoration:
/// BoxDecoration(shape: BoxShape.circle))` icon button — same box size,
/// but the circle itself is a single wobbly hand-drawn stroke instead
/// of Flutter's perfectly geometric one. For real icon buttons (filter,
/// refresh, share) — not for anything clipping an actual photo (avatar,
/// cast headshot), which should stay a true circle. Cozy skin only —
/// renders the plain geometric circle otherwise.
class WobblyCircle extends StatelessWidget {
  final double size;
  final Color color;
  final Widget child;
  final EdgeInsets margin;
  final List<BoxShadow>? boxShadow;
  const WobblyCircle({
    super.key,
    required this.size,
    required this.color,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) {
      return Container(
        width: size,
        height: size,
        margin: margin,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: boxShadow),
        alignment: Alignment.center,
        child: child,
      );
    }
    return Container(
      width: size,
      height: size,
      margin: margin,
      decoration: boxShadow == null
          ? null
          : BoxDecoration(shape: BoxShape.circle, boxShadow: boxShadow),
      child: CustomPaint(
        painter: _WobblyCirclePainter(color: color),
        child: Center(child: child),
      ),
    );
  }
}

class _WobblyCirclePainter extends CustomPainter {
  final Color color;
  _WobblyCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 1;
    var seed = 19;
    double jitter() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return (seed / 0x7fffffff - 0.5) * size.width * 0.035;
    }

    const steps = 22;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final t = (i / steps) * 2 * math.pi;
      final rr = r + jitter();
      final x = cx + rr * math.cos(t);
      final y = cy + rr * math.sin(t);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WobblyCirclePainter oldDelegate) => oldDelegate.color != color;
}

/// Drop-in replacement for [Switch] — same `value`/`onChanged`/
/// `activeColor` shape, but the thumb carries an actual hand-drawn
/// checkmark or cross that swaps as it toggles, rather than being a
/// bare circle the way Material's switch is. Cozy skin only — renders
/// the plain [Switch] otherwise.
class CozySwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  const CozySwitch({super.key, required this.value, required this.onChanged, this.activeColor});

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? SeenlyPalette.accent;
    if (!SeenlySkin.isCozy) {
      return Switch(value: value, onChanged: onChanged, activeColor: color);
    }
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 46,
        height: 27,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: value ? color.withOpacity(0.18) : SeenlyPalette.border.withOpacity(0.4),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: value ? color : SeenlyPalette.inkFaint.withOpacity(0.7), width: 1.3),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: ClayBoxDecoration(
              color: value ? color : SeenlyPalette.paper,
              shape: BoxShape.circle,
              boxShadow: SeenlyPalette.softShadow,
            ),
            child: CustomPaint(
              painter: _MarkPainter(
                isCheck: value,
                color: value ? SeenlyPalette.paper : SeenlyPalette.inkFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final bool isCheck;
  final Color color;
  _MarkPainter({required this.isCheck, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    if (isCheck) {
      final path = Path()
        ..moveTo(cx - 4.5, cy + 0.3)
        ..lineTo(cx - 1, cy + 3.6)
        ..lineTo(cx + 5, cy - 4);
      canvas.drawPath(path, paint);
    } else {
      canvas.drawLine(Offset(cx - 3.8, cy - 3.8), Offset(cx + 3.8, cy + 3.8), paint);
      canvas.drawLine(Offset(cx + 3.8, cy - 3.8), Offset(cx - 3.8, cy + 3.8), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.isCheck != isCheck || oldDelegate.color != color;
}

/// Drop-in replacement for [LinearProgressIndicator] — same
/// `value`/`minHeight`/`backgroundColor`/`valueColor` shape, but the
/// track is marked off like a hand-ruled scale (small tick marks every
/// tenth) instead of being a bare filled bar. Cozy skin only — renders
/// the plain [LinearProgressIndicator] otherwise.
class RuledProgressBar extends StatelessWidget {
  // Nullable on purpose: null means "indeterminate" (an animated,
  // looping bar with no known fraction yet) — the same contract
  // Flutter's own LinearProgressIndicator.value already has, and the
  // one _PosterProgressBar (profile_screen.dart) needs for its "still
  // fetching a runtime, no progress % yet" dash. Was non-nullable
  // before, which meant that null case had nowhere to go and didn't
  // compile.
  final double? value;
  final double minHeight;
  final Color backgroundColor;
  final Color valueColor;
  const RuledProgressBar({
    super.key,
    required this.value,
    this.minHeight = 6,
    required this.backgroundColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value?.clamp(0.0, 1.0);
    if (!SeenlySkin.isCozy) {
      return LinearProgressIndicator(
        value: clamped,
        minHeight: minHeight,
        backgroundColor: backgroundColor,
        valueColor: AlwaysStoppedAnimation(valueColor),
      );
    }
    if (clamped == null) {
      // The hand-drawn ruled painter below needs an actual fraction to
      // fill (it's a static paint, not an animation controller) — there's
      // no "cozy" indeterminate look yet, so this borrows the standard
      // Material indeterminate bar rather than silently rendering an
      // empty/zero track that would misreport "no progress" as if it
      // were a real 0%.
      return ClipRRect(
        borderRadius: BorderRadius.circular(minHeight / 2),
        child: LinearProgressIndicator(
          minHeight: minHeight,
          backgroundColor: backgroundColor,
          valueColor: AlwaysStoppedAnimation(valueColor),
        ),
      );
    }
    // No LayoutBuilder — this can sit inside an IntrinsicHeight (a
    // stats row measuring itself against its siblings), and
    // LayoutBuilder can't answer an intrinsic-dimension query. A plain
    // empty SizedBox fixing only the height, as CustomPaint's child, is
    // safe there and still stretches to the real width once real
    // layout happens.
    return ClipRRect(
      borderRadius: BorderRadius.circular(minHeight / 2),
      child: CustomPaint(
        painter: _RuledProgressPainter(value: clamped, track: backgroundColor, fill: valueColor),
        child: SizedBox(height: minHeight),
      ),
    );
  }
}

class _RuledProgressPainter extends CustomPainter {
  final double value;
  final Color track;
  final Color fill;
  _RuledProgressPainter({required this.value, required this.track, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    final fillWidth = size.width * value;
    if (fillWidth > 0) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, radius));
      canvas.drawRect(Rect.fromLTWH(0, 0, fillWidth, size.height), Paint()..color = fill);
      canvas.restore();
    }
    // Ruler gradations across the whole track — a scale someone marked
    // off by hand, not just a plain filled bar.
    const divisions = 10;
    final tickPaint = Paint()..strokeWidth = 1;
    for (var i = 1; i < divisions; i++) {
      final x = size.width * i / divisions;
      final onFill = x <= fillWidth;
      tickPaint.color = (onFill ? Colors.white : track).withOpacity(0.5);
      canvas.drawLine(Offset(x, size.height * 0.18), Offset(x, size.height * 0.82), tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RuledProgressPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.track != track || oldDelegate.fill != fill;
}

/// A real strip of washi tape "pinning" [child] to the page — a
/// slightly rotated, torn-edged rectangle overlapping [child]'s own
/// corner, built from [child]'s actual size (via Stack/Positioned), not
/// a screen-relative decoration independent of what it's taped to.
/// Cozy skin only — renders [child] alone otherwise.
class WashiTapedCard extends StatelessWidget {
  final Widget child;
  final Color? tapeColor;
  final Alignment corner;
  final double angle;
  const WashiTapedCard({
    super.key,
    required this.child,
    this.tapeColor,
    this.corner = Alignment.topRight,
    this.angle = 0.12,
  });

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) return child;
    // Only the two top corners are used anywhere in the app so far —
    // picks which side of the Stack the tape hugs.
    final onLeft = corner.x <= 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -10,
          left: onLeft ? 8 : null,
          right: onLeft ? null : 8,
          child: Transform.rotate(
            angle: angle,
            child: CustomPaint(
              painter: _TapePainter(color: tapeColor ?? SeenlyPalette.tapeRose),
              child: const SizedBox(width: 46, height: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _TapePainter extends CustomPainter {
  final Color color;
  _TapePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.82);
    // A torn edge on both short sides instead of a clean rectangle —
    // a handful of small random-ish notches, deterministic per call so
    // the tape doesn't shimmer on rebuild.
    final path = Path();
    var seed = 42;
    double jag() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return (seed / 0x7fffffff - 0.5) * 3.2;
    }

    path.moveTo(0, jag().abs());
    const notches = 4;
    for (var i = 0; i <= notches; i++) {
      final x = size.width * i / notches;
      path.lineTo(x, jag());
    }
    for (var i = notches; i >= 0; i--) {
      final x = size.width * i / notches;
      path.lineTo(x, size.height + jag());
    }
    path.close();
    canvas.drawPath(path, paint);

    final sheen = Paint()..color = Colors.white.withOpacity(0.14);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.4), sheen);
  }

  @override
  bool shouldRepaint(covariant _TapePainter oldDelegate) => false;
}

/// A folded-down page corner (dog-ear) anchored to [child]'s own
/// top-right — reads as "this specific page/card got folded", not a
/// decoration floating elsewhere on screen. Cozy skin only.
class DogEarCorner extends StatelessWidget {
  final Widget child;
  final double size;
  const DogEarCorner({super.key, required this.child, this.size = 22});

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: IgnorePointer(
            child: CustomPaint(
              size: Size(size, size),
              painter: _DogEarPainter(
                fold: SeenlyPalette.paper,
                shadow: SeenlyPalette.ink.withOpacity(0.14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DogEarPainter extends CustomPainter {
  final Color fold;
  final Color shadow;
  _DogEarPainter({required this.fold, required this.shadow});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = shadow);
    final fp = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width * 0.18, 0)
      ..lineTo(size.width, size.height * 0.82)
      ..close();
    canvas.drawPath(fp, Paint()..color = fold);
  }

  @override
  bool shouldRepaint(covariant _DogEarPainter oldDelegate) => false;
}
