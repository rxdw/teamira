import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Clips a rect to a torn/deckled top edge and a normal rounded bottom
/// — the "ripped off a notepad" paper look the cozy diary skin's cards
/// use instead of a plain rounded rectangle. The jag pattern is a fixed
/// list rather than [math.Random], so it stays put across rebuilds
/// instead of re-jittering every frame.
///
/// Deliberately only the clip shape, no shadow: [BoxShadow] is painted
/// from a widget's own rect, so a Container with a shadow wrapped
/// directly in this clipper would have most of that shadow clipped away
/// wherever the torn path pulls in from the rect it was computed for.
/// Pair this with a plain (un-clipped) rounded rect behind it for the
/// shadow — see `_CozyPaperFrame` in cinema_log_screen.dart for the
/// pattern.
class TornTopClipper extends CustomClipper<Path> {
  final double jag;
  final double bottomRadius;

  const TornTopClipper({this.jag = 7, this.bottomRadius = 26});

  static const _jitter = [
    0.15, 0.85, 0.30, 1.00, 0.10, 0.70, 0.40, 0.95,
    0.20, 0.80, 0.35, 0.90, 0.05, 0.75, 0.45, 0.60,
  ];

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return Path()..addRect(Offset.zero & size);

    const teeth = 16;
    final seg = w / teeth;
    final path = Path()..moveTo(0, jag * _jitter[0]);
    for (var i = 1; i <= teeth; i++) {
      final x = (i * seg).clamp(0.0, w);
      final y = jag * _jitter[i % _jitter.length];
      path.lineTo(x, y);
    }
    final r = bottomRadius.clamp(0.0, h / 2);
    path
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant TornTopClipper oldClipper) =>
      oldClipper.jag != jag || oldClipper.bottomRadius != bottomRadius;
}

/// A single small four-point sparkle, dropped as a `Positioned` accent
/// near a card's corner — the cozy diary skin's stand-in for the little
/// hand-drawn ✦ marks scattered around the pastel mockups. Wrapped in
/// [IgnorePointer] since it's purely decorative and often sits slightly
/// outside its card's own bounds.
class SparkleAccent extends StatelessWidget {
  final double size;
  final Color? color;
  final double opacity;

  const SparkleAccent({super.key, this.size = 14, this.color, this.opacity = 0.65});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Icon(Icons.auto_awesome, size: size, color: (color ?? SeenlyPalette.accent).withOpacity(opacity)),
    );
  }
}
