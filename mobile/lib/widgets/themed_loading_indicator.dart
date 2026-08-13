import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/log_theme_service.dart';
import '../services/rabbit_mascot_prefs_service.dart';
import 'rabbit_mascot.dart';

/// The app's one loading spinner, dressed in whichever [LogTheme] is
/// active — a sprout growing two leaves, a ticket printing out of a
/// slot, or a coach window with the scenery sliding past outside.
/// Flat shapes in the app's own palette, not stock icons. Drop-in
/// replacement for `CircularProgressIndicator(...)`: same `size` and
/// `color` knobs, so swapping call sites is mechanical (`color` is
/// ignored here — each motif keeps its own two-tone palette so it
/// still reads correctly against any background).
class ThemedLoadingIndicator extends StatefulWidget {
  final double size;
  final Color? color;
  final double strokeWidth; // kept for call-site parity; unused visually

  const ThemedLoadingIndicator({
    super.key,
    this.size = 42,
    this.color,
    this.strokeWidth = 2,
  });

  @override
  State<ThemedLoadingIndicator> createState() => _ThemedLoadingIndicatorState();
}

class _ThemedLoadingIndicatorState extends State<ThemedLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;

    // Below ~56px the rabbit's detail gets muddy, so small inline
    // spinners (buttons, list rows) keep the themed motif regardless —
    // only spinners with room to breathe swap in the mascot.
    if (widget.size >= 56 && context.watch<RabbitMascotPrefsService>().enabled) {
      return RabbitMascot(mood: RabbitMood.loading, size: widget.size);
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final painter = switch (theme) {
            LogTheme.garden => SproutMotionPainter(t: _controller.value),
            LogTheme.coach => CoachWindowMotionPainter(t: _controller.value),
            LogTheme.ticket => TicketPrintMotionPainter(t: _controller.value),
          };
          return CustomPaint(size: Size(widget.size, widget.size), painter: painter);
        },
      ),
    );
  }
}

// These three painters are also reused as-is by [ThemedPullToRefresh]
// (see widgets/themed_pull_to_refresh.dart), which drives the same `t`
// off the pull gesture instead of a looping controller — one drawing,
// two different clocks feeding it.

// A stem rising from the soil line with two leaves unfurling on a
// slight offset from each other, then easing back — one breath of
// growth, looped.
class SproutMotionPainter extends CustomPainter {
  final double t; // 0..1
  const SproutMotionPainter({required this.t});

  static const _leaf = Color(0xFF8FA382); // SeenlyPalette.sage
  static const _leafDark = Color(0xFF6E8961);
  static const _soil = Color(0xFFB3A48F); // SeenlyPalette.placeholder

  double _growth(double phase) {
    final local = (t - phase) % 1.0;
    // eases up to full growth, holds briefly, eases back down
    if (local < 0.5) return Curves.easeOut.transform((local / 0.5).clamp(0.0, 1.0));
    return 1 - Curves.easeIn.transform(((local - 0.5) / 0.5).clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.scale(0.85);
    canvas.translate(-w / 2, -h / 2);

    final soilY = h * 0.79;
    final stemTopY = h * 0.33;

    canvas.drawLine(
      Offset(w * 0.25, soilY),
      Offset(w * 0.75, soilY),
      Paint()
        ..color = _soil
        ..strokeWidth = math.max(1.4, w * 0.045)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(w * 0.5, soilY),
      Offset(w * 0.5, stemTopY),
      Paint()
        ..color = _leaf
        ..strokeWidth = math.max(1.4, w * 0.055)
        ..strokeCap = StrokeCap.round,
    );

    final leftGrowth = _growth(0.0);
    final rightGrowth = _growth(0.16);
    final anchor = Offset(w * 0.5, h * 0.5);

    _drawLeaf(canvas, anchor, w, h, growth: leftGrowth, flip: false, color: _leaf);
    _drawLeaf(canvas, anchor, w, h, growth: rightGrowth, flip: true, color: _leafDark);
    canvas.restore();
  }

  void _drawLeaf(Canvas canvas, Offset anchor, double w, double h,
      {required double growth, required bool flip, required Color color}) {
    if (growth <= 0.02) return;
    final dir = flip ? 1.0 : -1.0;
    final reach = w * 0.30 * growth;
    final rise = h * 0.20 * growth;
    final base = anchor + Offset(0, flip ? h * 0.08 : 0);
    final tip = base + Offset(dir * reach, -rise);
    final ctrl = base + Offset(dir * reach * 0.75, -rise * 0.35);

    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(base.dx + dir * reach * 0.25, base.dy - rise * 0.55, base.dx, base.dy)
      ..close();

    canvas.drawPath(path, Paint()..color = color.withOpacity(0.55 + 0.45 * growth));
  }

  @override
  bool shouldRepaint(covariant SproutMotionPainter oldDelegate) => oldDelegate.t != t;
}

// A ticket sliding out of a slot like it's being printed, pausing,
// then drawing back in — clipped so it only ever shows below the slot.
class TicketPrintMotionPainter extends CustomPainter {
  final double t; // 0..1
  const TicketPrintMotionPainter({required this.t});

  static const _ticket = Color(0xFFC99A4C); // SeenlyPalette.mustard
  static const _slot = Color(0xFF8A7A68); // SeenlyPalette.inkMuted
  static const _notch = Color(0xFFF5EFE4); // SeenlyPalette.background

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.scale(0.85);
    canvas.translate(-w / 2, -h / 2);

    final slotY = h * 0.33;

    // 0-60%: slides out; 60-85%: holds; 85-100%: slides back in
    double progress;
    if (t < 0.6) {
      progress = Curves.easeOut.transform(t / 0.6);
    } else if (t < 0.85) {
      progress = 1.0;
    } else {
      progress = 1 - Curves.easeIn.transform((t - 0.85) / 0.15);
    }

    final ticketW = w * 0.5;
    final ticketH = h * 0.58;
    final restY = slotY + h * 0.08;
    final hiddenY = slotY - ticketH * 0.55;
    final top = hiddenY + (restY - hiddenY) * progress;

    final rect = Rect.fromLTWH((w - ticketW) / 2, top, ticketW, ticketH);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.045));
    final notchR = ticketW * 0.13;

    final body = Path()..addRRect(rrect);
    final notchL =
        Path()..addOval(Rect.fromCircle(center: Offset(rect.left, rect.top + rect.height / 2), radius: notchR));
    final notchR2 =
        Path()..addOval(Rect.fromCircle(center: Offset(rect.right, rect.top + rect.height / 2), radius: notchR));
    final cut = Path.combine(
      PathOperation.difference,
      Path.combine(PathOperation.difference, body, notchL),
      notchR2,
    );

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, slotY, w, h - slotY));
    canvas.drawPath(cut, Paint()..color = _ticket);
    canvas.drawLine(
      Offset(rect.left, rect.top + rect.height / 2),
      Offset(rect.right, rect.top + rect.height / 2),
      Paint()
        ..color = _notch
        ..strokeWidth = math.max(1.0, w * 0.02)
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    canvas.drawLine(
      Offset(w * 0.2, slotY),
      Offset(w * 0.8, slotY),
      Paint()
        ..color = _slot
        ..strokeWidth = math.max(1.6, w * 0.06)
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TicketPrintMotionPainter oldDelegate) => oldDelegate.t != t;
}

// A little window: a rounded frame, with hills sliding continuously
// past behind the glass, like the view riding shotgun on the coach.
class CoachWindowMotionPainter extends CustomPainter {
  final double t; // 0..1
  const CoachWindowMotionPainter({required this.t});

  static const _frame = Color(0xFFB6704A); // SeenlyPalette.clay
  static const _glass = Color(0xFFEAF0E4);
  static const _hill = Color(0xFF8FA382); // SeenlyPalette.sage
  static const _hillDark = Color(0xFF7D9270);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.scale(0.85);
    canvas.translate(-w / 2, -h / 2);

    final frameRect = Rect.fromLTWH(w * 0.07, h * 0.14, w * 0.86, h * 0.66);
    final frameRRect = RRect.fromRectAndRadius(frameRect, Radius.circular(w * 0.18));

    // A short pantograph tick above the frame — the one silhouette
    // detail that reads "train" rather than leaving the window to
    // read as a vehicle body of its own (which is what the wheels
    // used to do).
    final pantoX = frameRect.left + frameRect.width * 0.68;
    final pantoPaint = Paint()
      ..color = _frame.withOpacity(0.8)
      ..strokeWidth = w * 0.018
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(pantoX - w * 0.05, frameRect.top),
      Offset(pantoX, frameRect.top - h * 0.09),
      pantoPaint,
    );
    canvas.drawLine(
      Offset(pantoX, frameRect.top - h * 0.09),
      Offset(pantoX + w * 0.05, frameRect.top),
      pantoPaint,
    );

    canvas.drawRRect(frameRRect, Paint()..color = _frame);

    final glassInset = w * 0.05;
    final glassRect = frameRect.deflate(glassInset);
    final glassRRect = RRect.fromRectAndRadius(glassRect, Radius.circular(w * 0.08));
    canvas.drawRRect(glassRRect, Paint()..color = _glass);

    canvas.save();
    canvas.clipRRect(glassRRect);

    final tileW = glassRect.width * 1.3;
    final shift = (t * tileW) % tileW;
    final baseY = glassRect.bottom - glassRect.height * 0.28;

    canvas.drawRect(
      Rect.fromLTWH(glassRect.left, baseY, glassRect.width * 3, glassRect.height * 0.3),
      Paint()..color = const Color(0xFFC9BFA0),
    );

    void hill(double cx, double peakH, Color color) {
      final path = Path()
        ..moveTo(cx - peakH * 0.7, baseY)
        ..lineTo(cx, baseY - peakH)
        ..lineTo(cx + peakH * 0.7, baseY)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    for (int rep = -1; rep < 3; rep++) {
      final offset = rep * tileW - shift;
      hill(glassRect.left + offset + tileW * 0.15, glassRect.height * 0.42, _hill);
      hill(glassRect.left + offset + tileW * 0.45, glassRect.height * 0.30, _hill);
      hill(glassRect.left + offset + tileW * 0.70, glassRect.height * 0.55, _hillDark);
      hill(glassRect.left + offset + tileW * 0.95, glassRect.height * 0.34, _hill);
    }
    canvas.restore();

    // Trailing motion streaks under the frame stand in for the old
    // wheels as the "this is moving" cue, without drawing a vehicle
    // body underneath the window.
    final streakY = frameRect.bottom + h * 0.05;
    for (int i = 0; i < 3; i++) {
      final streakShift = (t * w * 1.4 + i * w * 0.22) % (w * 0.9);
      canvas.drawLine(
        Offset(frameRect.right - streakShift, streakY),
        Offset(frameRect.right - streakShift - w * 0.1, streakY),
        Paint()
          ..color = _frame.withOpacity(0.35 - i * 0.08)
          ..strokeWidth = w * 0.02
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CoachWindowMotionPainter oldDelegate) => oldDelegate.t != t;
}
