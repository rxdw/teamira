import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'seenly_skin.dart';

/// The Cozy Diary skin is a quiet paper world, not a foreground decoration
/// layer.  The painter deliberately keeps the centre of the screen clean:
/// cards, posters and controls own their space; the illustration only lives
/// in the empty paper margins and adds a barely-visible paper grain.
class CozyDiaryAtmosphere extends StatelessWidget {
  final Widget child;

  const CozyDiaryAtmosphere({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!SeenlySkin.isCozy) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(painter: _CozyDiaryPainter()),
          ),
        ),
      ],
    );
  }
}

class _CozyDiaryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final ink = SeenlyPalette.ink;
    final accent = SeenlyPalette.accent;

    // The grain is intentionally almost imperceptible. It makes a flat
    // Flutter background feel like the warm paper in the reference without
    // putting visual noise over posters or text.
    _drawPaperFibers(canvas, size, ink);

    // Hand-drawn details live in the outer paper margins only. There is no
    // awning, no row of circles and no decoration crossing the content area.
    _drawTopMarks(canvas, size, accent);
    _drawBottomBotanicals(canvas, size, ink);
  }

  void _drawPaperFibers(Canvas canvas, Size size, Color color) {
    final p = Paint()
      ..color = color.withOpacity(0.018)
      ..strokeWidth = 0.55
      ..style = PaintingStyle.stroke;

    var seed = 9173;
    double next() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    for (var i = 0; i < 70; i++) {
      final x = next() * size.width;
      final y = next() * size.height;
      final len = 3 + next() * 7;
      final dx = (next() - 0.5) * len;
      final dy = (next() - 0.5) * 1.0;
      canvas.drawLine(Offset(x, y), Offset(x + dx, y + dy), p);
    }
  }

  void _drawTopMarks(Canvas canvas, Size size, Color color) {
    final p = Paint()
      ..color = color.withOpacity(0.16)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Small pencil-like flourishes in the top corners. These replace the
    // previous scalloped strip/dots, which made the theme look pasted on.
    canvas.drawLine(const Offset(24, 42), const Offset(36, 49), p);
    canvas.drawLine(const Offset(21, 58), const Offset(31, 57), p);
    canvas.drawLine(Offset(size.width - 36, 49), Offset(size.width - 24, 42), p);
    canvas.drawLine(Offset(size.width - 31, 57), Offset(size.width - 21, 58), p);

    _drawSparkle(canvas, Offset(18, math.min(116, size.height * .14)), 4.5,
        SeenlyPalette.mustard.withOpacity(0.30));
    _drawHeart(canvas, Offset(size.width - 24, math.min(122, size.height * .15)),
        6.5, SeenlyPalette.pink.withOpacity(0.25));
  }

  void _drawBottomBotanicals(Canvas canvas, Size size, Color color) {
    final y = size.height - 14;
    _drawBotanical(canvas, Offset(14, y), 1, color);
    _drawBotanical(canvas, Offset(size.width - 14, y), -1, color);
  }

  void _drawBotanical(Canvas canvas, Offset origin, double direction, Color color) {
    final p = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final stem = Path()
      ..moveTo(origin.dx, origin.dy)
      ..cubicTo(
        origin.dx + direction * 7,
        origin.dy - 18,
        origin.dx + direction * 4,
        origin.dy - 34,
        origin.dx + direction * 13,
        origin.dy - 54,
      );
    canvas.drawPath(stem, p);

    const leafOffsets = [
      Offset(5, -15),
      Offset(3, -28),
      Offset(7, -40),
    ];
    for (var i = 0; i < leafOffsets.length; i++) {
      final o = leafOffsets[i] + origin;
      final side = i.isEven ? -direction : direction;
      final leaf = Path()
        ..moveTo(o.dx, o.dy)
        ..quadraticBezierTo(
          o.dx + side * 10,
          o.dy - 7,
          o.dx + side * 7,
          o.dy - 14,
        )
        ..quadraticBezierTo(
          o.dx - side * 2,
          o.dy - 10,
          o.dx,
          o.dy,
        );
      canvas.drawPath(leaf, p);
    }
  }

  void _drawHeart(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()..color = color;
    final path = Path()..moveTo(c.dx, c.dy + r * .82);
    path
      ..cubicTo(c.dx - r * 1.35, c.dy - r * .05, c.dx - r * .72,
          c.dy - r, c.dx, c.dy - r * .38)
      ..cubicTo(c.dx + r * .72, c.dy - r, c.dx + r * 1.35,
          c.dy - r * .05, c.dx, c.dy + r * .82)
      ..close();
    canvas.drawPath(path, p);
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
  }

  @override
  bool shouldRepaint(covariant _CozyDiaryPainter oldDelegate) => false;
}
