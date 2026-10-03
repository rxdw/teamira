import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'soft_motion.dart';
import 'tane_thinking.dart' show paintSparkle;
import 'wow_motion.dart' show PressScale;
import '../theme/clay_kit.dart';

/// What the two "leave it to chance" screens share — the spin-the-reel
/// screen (screens/decide/decide_roulette_screen.dart) and the plain random
/// pick (decide_random_screen.dart): a die for anything that rolls, a
/// secondary button whose waiting state isn't a spinner, and the frame the
/// reel lands in. Same rules as the rest of the motion kit: quiet, and a
/// plain still picture when the system asks for reduced motion.

// ---------------------------------------------------------------------------
// The die
// ---------------------------------------------------------------------------

/// A small die, drawn (not an icon) so it can actually tumble. Three
/// states:
///
///  * at rest — a face of five, still;
///  * [rolling] true — it tumbles end over end, hopping, its face
///    changing as it goes, for as long as it stays true; when [rolling]
///    turns false it finishes the turn it's on and settles;
///  * [rollTick] going up — one quick roll and settle, for a button that
///    re-draws something and isn't otherwise busy.
class DiceGlyph extends StatefulWidget {
  final double size;
  final Color color;
  final bool rolling;
  final int rollTick;

  const DiceGlyph({
    super.key,
    this.size = 20,
    required this.color,
    this.rolling = false,
    this.rollTick = 0,
  });

  @override
  State<DiceGlyph> createState() => _DiceGlyphState();
}

class _DiceGlyphState extends State<DiceGlyph> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  /// The faces it flashes through in one turn.
  static const _faces = [2, 5, 3, 6, 1, 4];

  @override
  void initState() {
    super.initState();
    if (widget.rolling) _c.repeat();
  }

  @override
  void didUpdateWidget(DiceGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rolling && !oldWidget.rolling) {
      _c.repeat();
    } else if (!widget.rolling && oldWidget.rolling) {
      _c.forward(); // finish the turn it's in, then rest
    } else if (widget.rollTick != oldWidget.rollTick && !widget.rolling) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = reduceMotion ? 0.0 : _c.value;
        final resting = t <= 0 || t >= 1;
        final face = resting ? 5 : _faces[(t * 6).floor() % 6];
        final angle = resting ? 0.0 : t * 2 * math.pi;
        // Three small hops per turn.
        final hop = resting ? 0.0 : -math.sin(((t * 3) % 1.0) * math.pi) * widget.size * 0.16;
        return Transform.translate(
          offset: Offset(0, hop),
          child: Transform.rotate(
            angle: angle,
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _DicePainter(face: face, color: widget.color),
            ),
          ),
        );
      },
    );
  }
}

class _DicePainter extends CustomPainter {
  final int face;
  final Color color;

  const _DicePainter({required this.face, required this.color});

  // (column, row) on a 3×3 grid, for each face.
  static const _pips = <int, List<(int, int)>>{
    1: [(1, 1)],
    2: [(0, 0), (2, 2)],
    3: [(0, 0), (1, 1), (2, 2)],
    4: [(0, 0), (2, 0), (0, 2), (2, 2)],
    5: [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
    6: [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.08, s * 0.08, s * 0.84, s * 0.84),
        Radius.circular(s * 0.24),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.09
        ..color = color,
    );
    final pip = Paint()..color = color;
    for (final (col, row) in _pips[face]!) {
      canvas.drawCircle(Offset(s * (0.30 + 0.2 * col), s * (0.30 + 0.2 * row)), s * 0.075, pip);
    }
  }

  @override
  bool shouldRepaint(covariant _DicePainter old) => old.face != face || old.color != color;
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

/// The big accent "spin" button. Looks like the app's primary button, but
/// while [rolling] its die tumbles and the label swaps to its "rolling…"
/// wording — instead of the label vanishing behind a spinner.
class DiceButton extends StatelessWidget {
  final String label;
  final bool rolling;
  final VoidCallback? onTap;

  const DiceButton({super.key, required this.label, required this.rolling, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: PressScale(
        onTap: rolling ? null : onTap,
        scaleTo: 0.97,
        haptics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 24),
          decoration: BoxDecoration(
            color: SeenlyPalette.accent,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DiceGlyph(size: 20, color: SeenlyPalette.accentOnAccent, rolling: rolling),
              const SizedBox(width: 10),
              SoftSwap(
                alignment: Alignment.center,
                child: Text(
                  label,
                  key: ValueKey<String>(label),
                  style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The paper-coloured button that sits beside the main one ("reroll",
/// "plan to watch", "spin again"). Its small states are soft:
///
///  * waiting (`loading`) shows three bouncing dots, not a spinner, and
///    the button keeps its height so nothing jumps;
///  * the label and icon swap with a quiet cross-fade, the new icon
///    popping in — "plan to watch" turning into "added" reads as a
///    change, not a repaint;
///  * pass [leading] instead of [icon] to put something else in front of
///    the label (the die).
class SecondaryActionButton extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool haptics;

  const SecondaryActionButton({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.haptics = false,
  }) : assert(icon != null || leading != null);

  @override
  Widget build(BuildContext context) {
    final face = loading
        ? const BouncingDots(key: ValueKey<String>('loading'))
        : Row(
            key: ValueKey<String>('$label/${icon?.codePoint}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              leading ?? _PoppingIcon(icon: icon!),
              const SizedBox(width: 7),
              Text(label, style: SeenlyText.mono(size: 12.5, color: SeenlyPalette.ink, weight: FontWeight.w600)),
            ],
          );
    return PressScale(
      onTap: onTap,
      scaleTo: 0.96,
      haptics: haptics,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: onTap == null && !loading ? 0.45 : 1,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: ClayBoxDecoration(
            boxShadow: SeenlyPalette.flatCardShadow,
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SeenlyPalette.border),
          ),
          alignment: Alignment.center,
          child: SoftSwap(alignment: Alignment.center, child: face),
        ),
      ),
    );
  }
}

/// An icon that pops in (from a bit smaller, with a little overshoot)
/// whenever it's a new one.
class _PoppingIcon extends StatelessWidget {
  final IconData icon;
  const _PoppingIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final still = Icon(icon, size: 17, color: SeenlyPalette.ink);
    if (MediaQuery.of(context).disableAnimations) return still;
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(icon.codePoint),
      tween: Tween<double>(begin: 0.5, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: still,
    );
  }
}

/// Three dots that hop one after another — a wait that isn't a spinner.
/// [color] defaults to the ink colour; [dotSize] scales the whole thing
/// (6 by default; 4 fits where a small spinner used to sit).
class BouncingDots extends StatefulWidget {
  final Color? color;
  final double dotSize;

  const BouncingDots({super.key, this.color, this.dotSize = 6});

  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final d = widget.dotSize;
    return SizedBox(
      height: d * 2.8,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: d * 0.85),
              _dot(reduceMotion ? 0.0 : _bump(_c.value, i)),
            ],
          ],
        ),
      ),
    );
  }

  /// 0→1→0 over the first 40 % of this dot's lap; each dot's lap starts a
  /// little after the previous one's.
  static double _bump(double t, int i) {
    final p = (t - i * 0.16) % 1.0;
    return p < 0.4 ? math.sin(p / 0.4 * math.pi) : 0.0;
  }

  Widget _dot(double bump) {
    final d = widget.dotSize;
    return Padding(
      padding: EdgeInsets.only(bottom: d / 3 + d * bump),
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: (widget.color ?? SeenlyPalette.ink).withOpacity(0.5 + 0.45 * bump),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The frame the reel lands in
// ---------------------------------------------------------------------------

/// The fixed accent frame the roulette reel spins past. When the reel
/// lands (or another poster is picked) — each time [landedTick] goes up —
/// the frame "locks on": it swells a little and its glow flares, a ring
/// spreads out from it and a few sparkles fly off its corners. Never
/// blocks touches (wrap it in an `IgnorePointer`).
class PointerFrame extends StatefulWidget {
  final double width;
  final double height;
  final int landedTick;

  const PointerFrame({
    super.key,
    required this.width,
    required this.height,
    required this.landedTick,
  });

  @override
  State<PointerFrame> createState() => _PointerFrameState();
}

class _PointerFrameState extends State<PointerFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  @override
  void didUpdateWidget(PointerFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.landedTick != oldWidget.landedTick && widget.landedTick > 0) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final size = Size(widget.width, widget.height);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = reduceMotion ? 0.0 : _c.value;
        // 0→1→0 across the first half: the swell.
        final pop = math.sin(math.min(t / 0.5, 1.0) * math.pi);
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (t > 0 && t < 1)
              CustomPaint(size: size, painter: _LockPainter(t: t)),
            Transform.scale(
              scale: 1 + 0.05 * pop,
              child: Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: SeenlyPalette.accent, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: SeenlyPalette.accent.withOpacity(0.22 + 0.3 * pop),
                      blurRadius: 26 + 16 * pop,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LockPainter extends CustomPainter {
  final double t; // 0..1

  const _LockPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final frame = Rect.fromCenter(center: centre, width: size.width, height: size.height);

    // A ring of the frame's own shape, spreading outward and fading.
    if (t > 0.08 && t < 0.9) {
      final p = Curves.easeOutCubic.transform(((t - 0.08) / 0.82).clamp(0.0, 1.0).toDouble());
      canvas.drawRRect(
        RRect.fromRectAndRadius(frame.inflate(4 + 34 * p), Radius.circular(24 + 34 * p)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * (1 - p) + 0.4
          ..color = SeenlyPalette.accent.withOpacity(0.5 * (1 - p)),
      );
    }

    // Sparkles flying off the corners and the middle of each side.
    final anchors = <Offset>[
      frame.topLeft, frame.topRight, frame.bottomLeft, frame.bottomRight,
      frame.topCenter, frame.bottomCenter, frame.centerLeft, frame.centerRight,
    ];
    for (int i = 0; i < anchors.length; i++) {
      final delay = 0.1 + ((i * 3) % 4) * 0.04;
      final local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0).toDouble();
      if (local <= 0) continue;
      final away = anchors[i] - centre;
      final dir = away / away.distance;
      final travel = 8 + Curves.easeOutCubic.transform(local) * (26 + 8 * (i % 3));
      final life = math.sin(math.pi * local);
      paintSparkle(
        canvas,
        anchors[i] + dir * travel,
        (3.4 + (i % 3) * 1.6) * (0.4 + 0.6 * life),
        Paint()..color = (i.isEven ? SeenlyPalette.accent : SeenlyPalette.mustard).withOpacity(0.9 * life),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LockPainter old) => old.t != t;
}
