import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A handful of small, reusable "wow" light effects shared across the
/// logging rituals — kept in one place so a spotlight sweep or a foil
/// shimmer reads the same way wherever it shows up, the same spirit as
/// `light_bloom.dart`'s shared dust/iris/flash pieces.

/// A projector-style beam of light that switches on and slides once
/// across whatever it wraps — used on the cinema ticket as it settles
/// in, so the ticket itself feels lit rather than just faded in.
///
/// [progress] should run 0..1 once (an appear/entrance controller works
/// well) — the beam starts just off one edge and slides fully past the
/// other, brightest in the middle of its travel.
class SpotlightSweep extends StatelessWidget {
  final double progress;
  final Widget child;

  const SpotlightSweep({super.key, required this.progress, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    // Travels from just off the top-left to just off the bottom-right,
    // so the beam has clean run-up and run-off rather than snapping in.
    final center = -0.35 + t * 1.7;
    return ShaderMask(
      blendMode: BlendMode.plus,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: const Alignment(-1, -1),
          end: const Alignment(1, 1),
          colors: [
            Colors.transparent,
            Colors.transparent,
            Colors.white.withOpacity(0.65),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: [
            0.0,
            (center - 0.22).clamp(0.0, 1.0),
            center.clamp(0.0, 1.0),
            (center + 0.22).clamp(0.0, 1.0),
            1.0,
          ],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

/// A fan of golden light rays radiating outward — the "premiere-night"
/// beat that plays alongside a burst of confetti rather than instead of
/// it. [t] is a 0..1 envelope (bloom in, fade out) driving both the
/// rays' reach and their opacity; pass the same curve already used for
/// a scene's warm glow so the two stay in lockstep.
class GoldRayBurst extends StatelessWidget {
  final double t;
  final int rayCount;
  final Color color;
  final double size;

  const GoldRayBurst({
    super.key,
    required this.t,
    this.rayCount = 16,
    this.color = const Color(0xFFFFD873),
    this.size = 320,
  });

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: CustomPaint(
          size: Size.square(size),
          painter: _GoldRayPainter(rayCount: rayCount, color: color, reach: t),
        ),
      ),
    );
  }
}

class _GoldRayPainter extends CustomPainter {
  final int rayCount;
  final Color color;
  final double reach;

  const _GoldRayPainter({required this.rayCount, required this.color, required this.reach});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide * 0.5 * (0.45 + 0.55 * reach);
    final halfGap = (math.pi / rayCount) * 0.46;
    // A slow settle-spin, so the fan doesn't feel like a static sticker
    // even in a single short-lived burst.
    final spin = reach * 0.5;
    for (int i = 0; i < rayCount; i++) {
      final a = (i / rayCount) * 2 * math.pi + spin;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + math.cos(a - halfGap) * maxR, center.dy + math.sin(a - halfGap) * maxR)
        ..lineTo(center.dx + math.cos(a + halfGap) * maxR, center.dy + math.sin(a + halfGap) * maxR)
        ..close();
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withOpacity(0.55), color.withOpacity(0.0)],
        ).createShader(Rect.fromCircle(center: center, radius: maxR));
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoldRayPainter oldDelegate) =>
      oldDelegate.reach != reach || oldDelegate.color != color || oldDelegate.rayCount != rayCount;
}
