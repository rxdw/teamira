import 'package:flutter/material.dart';

/// Draws a dashed rounded-rectangle outline around [child] — the
/// "stitched paper edge" look used by the cozy diary skin's cards
/// (Settings > appearance > visual style). Real dashes traced along a
/// [PathMetric] rather than a repeating-pattern border, so it follows
/// the rounded corners smoothly instead of gapping at them the way a
/// naive dash-per-side approach would.
///
/// [child] establishes the size (this just paints on top of it, inset
/// by [margin]) — wrap whatever card content the dashed line should
/// trace around.
class DashedRoundedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;
  final double strokeWidth;
  final EdgeInsets margin;

  const DashedRoundedBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = 18,
    this.dashWidth = 5,
    this.dashGap = 4,
    this.strokeWidth = 1.4,
    this.margin = const EdgeInsets.all(10),
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Padding(
            padding: margin,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DashedRRectPainter(
                  color: color,
                  radius: radius,
                  dashWidth: dashWidth,
                  dashGap: dashGap,
                  strokeWidth: strokeWidth,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;
  final double strokeWidth;

  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashGap,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashGap != dashGap ||
      oldDelegate.strokeWidth != strokeWidth;
}
