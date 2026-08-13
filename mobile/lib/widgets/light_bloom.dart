import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Shared "warm light" pieces used by both logging rituals (a little
/// cinema's lamp, a coach's evening glow) and both "moment sealed"
/// flashes (the ticket tearing, the boarding pass tearing) — kept in
/// one place so the two themes read as variations on one visual idea
/// rather than two unrelated effects bolted on separately.

/// One drifting mote's fixed parameters — generated once per showing
/// (seeded on a title) so the beam doesn't reshuffle itself on rebuild.
class LightMote {
  final double x; // 0..1 horizontal position
  final double phase; // 0..1 start offset in its rise
  final double speed; // cycles per loop of the drift controller
  final double driftX; // px of side-to-side sway
  final double size;
  final double opacity;

  const LightMote({
    required this.x,
    required this.phase,
    required this.speed,
    required this.driftX,
    required this.size,
    required this.opacity,
  });
}

List<LightMote> seededMotes(String seed, int count, {int salt = 0}) {
  final r = math.Random(seed.hashCode ^ salt ^ 0x6D6F7465); // 'mote' salt
  return List.generate(count, (_) {
    return LightMote(
      x: r.nextDouble(),
      phase: r.nextDouble(),
      speed: 0.55 + r.nextDouble() * 0.45,
      driftX: 6 + r.nextDouble() * 16,
      size: 1.0 + r.nextDouble() * 1.7,
      opacity: 0.10 + r.nextDouble() * 0.16,
    );
  });
}

class DustPainter extends CustomPainter {
  final double t;
  final List<LightMote> motes;

  const DustPainter({required this.t, required this.motes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in motes) {
      final p = (t * m.speed + m.phase) % 1.0;
      final dx = m.x * size.width + math.sin(p * math.pi * 2) * m.driftX;
      final dy = size.height * (1 - p);
      final fade = math.sin(p * math.pi).clamp(0.0, 1.0);
      final paint = Paint()..color = SeenlyPalette.paper.withOpacity(m.opacity * fade);
      canvas.drawCircle(Offset(dx, dy), m.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DustPainter oldDelegate) => oldDelegate.t != t;
}

/// Clips away everything outside a growing circle — a lamp's iris.
/// Same "difference of two paths" trick used for a ticket's
/// perforation notches, just at the scale of a screen.
class IrisClipper extends CustomClipper<Path> {
  final double radius;
  final Offset center;

  const IrisClipper({required this.radius, required this.center});

  @override
  Path getClip(Size size) {
    final full = Path()..addRect(Offset.zero & size);
    if (radius <= 0) return full;
    final hole = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    return Path.combine(PathOperation.difference, full, hole);
  }

  @override
  bool shouldReclip(covariant IrisClipper oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.center != center;
}

/// The farthest-corner distance from [center] within [size] — enough
/// radius for an [IrisClipper] to fully clear the screen once open.
double irisMaxRadius(Size size, Offset center) {
  final dx = math.max(center.dx, size.width - center.dx);
  final dy = math.max(center.dy, size.height - center.dy);
  return math.sqrt(dx * dx + dy * dy);
}

/// A short bloom-then-fade curve for a one-shot "light just switched
/// on" flash — `flashOpacity(controller.value)`, 0 before/after, peaks
/// partway through the rise.
double flashOpacity(double t, {double riseEnd = 0.4}) {
  if (t <= 0) return 0.0;
  return t < riseEnd
      ? Curves.easeOut.transform((t / riseEnd).clamp(0.0, 1.0))
      : 1 - Curves.easeIn.transform(((t - riseEnd) / (1 - riseEnd)).clamp(0.0, 1.0));
}
