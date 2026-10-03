import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_translations.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart' show LightMote, seededMotes;
import 'themed_loading_indicator.dart';
import 'wow_motion.dart' show BreathingGlow, PressScale, RevealPulse;

/// The small kit behind the "your profile" screen (level_detail_screen.dart):
/// the avatar-in-a-level-ring hero, the glowing points bar, dust drifting through
/// the backdrop, and [RevealProgress] — the one helper that lets any piece of
/// a card (a bar, a counter, a rail) play *when its section scrolls into view*
/// instead of while it is still off-screen.
///
/// Same voice as wow_motion.dart: soft easing, small distances, one or two
/// things per screen that stay quietly alive, and everything collapses to a
/// still picture when the system asks to reduce motion.

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

// ---------------------------------------------------------------------------
// RevealProgress
// ---------------------------------------------------------------------------

/// Hands [builder] a value that runs 0 → 1 every time the nearest
/// [ScrollReveal] above it starts playing, and snaps back to 0 when that
/// section leaves the screen — so a bar that fills or a number that counts up
/// is actually seen doing it, each time the section comes into view. Rides the
/// ambient [RevealPulse] the same way HorizontalReveal does.
///
/// With no [ScrollReveal] above it, it plays once after [delay], like
/// [Entrance]. With "reduce motion" on, it just sits at 1.
///
/// [curve] is applied to the value handed to [builder]. Pass
/// [Curves.linear] (and shape the value with `Interval`s inside the builder)
/// when one timeline drives several moves. A curve that overshoots (easeOutBack)
/// can hand [builder] values above 1 — clamp before using one as an opacity.
class RevealProgress extends StatefulWidget {
  final Widget Function(BuildContext context, double t) builder;
  final Duration delay;
  final Duration duration;
  final Curve curve;

  const RevealProgress({
    super.key,
    required this.builder,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 900),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<RevealProgress> createState() => _RevealProgressState();
}

class _RevealProgressState extends State<RevealProgress> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curved = CurvedAnimation(parent: _c, curve: widget.curve);

  int? _seenPlay;
  int? _seenReset;
  Timer? _timer;

  void _play() {
    _timer?.cancel();
    _timer = Timer(widget.delay, () {
      if (mounted) _c.forward(from: 0);
    });
  }

  void _resetNow() {
    _timer?.cancel();
    _c.value = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _timer?.cancel();
      _c.value = 1;
      return;
    }
    final pulse = RevealPulse.of(context);
    if (pulse == null) {
      // Not inside a ScrollReveal — behave like Entrance: play once, right away.
      if (_seenPlay == null) {
        _seenPlay = -1;
        _play();
      }
      return;
    }
    if (_seenPlay == null) {
      _seenPlay = pulse.playGeneration;
      _seenReset = pulse.resetGeneration;
      // The section may already be mid-reveal by the time this mounts; a
      // generation of 0 means it hasn't started yet and its own first pulse
      // will reach us the normal way.
      if (pulse.playGeneration > 0) _play();
      return;
    }
    if (pulse.resetGeneration != _seenReset) {
      _seenReset = pulse.resetGeneration;
      _resetNow();
    }
    if (pulse.playGeneration != _seenPlay) {
      _seenPlay = pulse.playGeneration;
      _play();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, _) => widget.builder(context, _curved.value),
    );
  }
}

// ---------------------------------------------------------------------------
// DriftingMotes — dust in the light behind the avatar
// ---------------------------------------------------------------------------

/// A handful of soft specks rising slowly and swaying, seamlessly looping.
/// Meant to sit at the edge of noticing over the avatar backdrop; draws
/// nothing at all when motion is reduced.
class DriftingMotes extends StatefulWidget {
  final String seed;
  final int count;
  final Color color;

  const DriftingMotes({super.key, required this.seed, required this.color, this.count = 16});

  @override
  State<DriftingMotes> createState() => _DriftingMotesState();
}

class _DriftingMotesState extends State<DriftingMotes> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 34))..repeat();
  late final List<LightMote> _motes = seededMotes(widget.seed, widget.count);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _MotePainter(t: _c.value, motes: _motes, color: widget.color),
          ),
        ),
      ),
    );
  }
}

class _MotePainter extends CustomPainter {
  final double t;
  final List<LightMote> motes;
  final Color color;

  const _MotePainter({required this.t, required this.motes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    for (final m in motes) {
      // Whole cycles per loop, so the last frame of the loop meets the first.
      final cycles = m.speed > 0.8 ? 2 : 1;
      final p = (t * cycles + m.phase) % 1.0;
      final dx = m.x * size.width + math.sin(p * math.pi * 2) * m.driftX;
      final dy = size.height * (1 - p);
      final fade = math.sin(p * math.pi).clamp(0.0, 1.0).toDouble();
      final a = (m.opacity * 2.2 * fade).clamp(0.0, 1.0).toDouble();
      canvas.drawCircle(Offset(dx, dy), m.size * 2.6, Paint()..color = color.withOpacity(a * 0.20));
      canvas.drawCircle(Offset(dx, dy), m.size * 1.1, Paint()..color = color.withOpacity(a));
    }
  }

  @override
  bool shouldRepaint(covariant _MotePainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// LevelRingAvatar
// ---------------------------------------------------------------------------

/// The hero of the screen: the person's avatar sitting on a paper mat inside
/// a dial-like level ring. On arrival the avatar settles in, the ring's tick
/// marks fade up, the progress arc sweeps round to where the level actually is
/// (lighting the ticks it passes, a small bead riding its tip), and the level
/// pill lands last with its number counting up. A soft glow breathes behind
/// it all. Tapping the pill replays the sweep; tapping the avatar calls
/// [onAvatarTap] (the parent opens its picker).
///
/// [avatar] should carry a `key` that changes when the picture does — the old
/// and new pictures then cross-fade instead of cutting.
class LevelRingAvatar extends StatefulWidget {
  final Widget avatar;
  final int level;

  /// 0..1 — how far through the current level.
  final double progress;
  final double avatarSize;

  /// Shows a small loader over the avatar while a new picture uploads.
  final bool busy;
  final VoidCallback? onAvatarTap;

  const LevelRingAvatar({
    super.key,
    required this.avatar,
    required this.level,
    required this.progress,
    this.avatarSize = 132,
    this.busy = false,
    this.onAvatarTap,
  });

  @override
  State<LevelRingAvatar> createState() => _LevelRingAvatarState();
}

class _LevelRingAvatarState extends State<LevelRingAvatar> with TickerProviderStateMixin {
  static const double _matPad = 5;
  static const double _gap = 9;
  static const double _stroke = 7;
  static const double _tickGap = 8;
  static const double _tickLen = 6;
  static const double _pillOverhang = 16;

  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _arc =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  double _from = 0;
  double _to = 0;
  Timer? _arcTimer;

  double get _ringRadius => widget.avatarSize / 2 + _matPad + _gap + _stroke / 2;
  double get _dial => 2 * (_ringRadius + _stroke / 2 + _tickGap + _tickLen + 4);
  double get _shown => _from + (_to - _from) * Curves.easeOutCubic.transform(_arc.value);

  double get _target => widget.progress.clamp(0.0, 1.0).toDouble();

  @override
  void initState() {
    super.initState();
    _to = _target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reduceMotion(context)) {
        _intro.value = 1;
        _arc.value = 1;
        return;
      }
      _intro.forward();
      // The sweep is its own beat, a moment after the avatar has settled.
      _arcTimer = Timer(const Duration(milliseconds: 380), () {
        if (mounted) _arc.forward(from: 0);
      });
    });
  }

  @override
  void didUpdateWidget(covariant LevelRingAvatar old) {
    super.didUpdateWidget(old);
    final next = _target;
    if ((next - _to).abs() > 0.0005) {
      _arcTimer?.cancel();
      // Continue from wherever the arc currently sits rather than snapping.
      _from = _shown;
      _to = next;
      _arc.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _arcTimer?.cancel();
    _intro.dispose();
    _arc.dispose();
    super.dispose();
  }

  void _replay() {
    if (_reduceMotion(context)) return;
    HapticFeedback.lightImpact();
    _arcTimer?.cancel();
    _from = 0;
    _to = _target;
    _arc.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final dial = _dial;
    final accent = SeenlyPalette.accent;
    final center = dial / 2;
    // The edit badge sits on the avatar's lower-right rim.
    final badgeR = widget.avatarSize / 2 - 2;
    final badgeOffset = badgeR * math.sqrt1_2;

    return SizedBox(
      width: dial,
      height: dial + _pillOverhang,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            width: dial,
            height: dial,
            child: BreathingGlow(
              color: accent,
              size: dial * 1.08,
              maxOpacity: 0.30,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            width: dial,
            height: dial,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_intro, _arc]),
                builder: (context, _) {
                  final reveal = const Interval(0.1, 0.7, curve: Curves.easeOut).transform(_intro.value);
                  return CustomPaint(
                    size: Size(dial, dial),
                    painter: _LevelRingPainter(
                      sweep: _shown,
                      reveal: reveal,
                      stroke: _stroke,
                      ringRadius: _ringRadius,
                      tickGap: _tickGap,
                      accent: accent,
                      track: SeenlyPalette.border,
                      idleTick: SeenlyPalette.inkFaint,
                      paper: SeenlyPalette.paper,
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            width: dial,
            height: dial,
            child: Center(
              child: AnimatedBuilder(
                animation: _intro,
                child: _avatarDisc(),
                builder: (context, child) {
                  final t = const Interval(0.0, 0.55, curve: Curves.easeOutCubic).transform(_intro.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: center + badgeOffset - 16,
            top: center + badgeOffset - 16,
            child: AnimatedBuilder(
              animation: _intro,
              builder: (context, child) {
                final pop = const Interval(0.5, 0.9, curve: Curves.easeOutBack).transform(_intro.value);
                final fade = const Interval(0.5, 0.75).transform(_intro.value);
                return Opacity(opacity: fade, child: Transform.scale(scale: pop, child: child));
              },
              child: IgnorePointer(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: SeenlyPalette.paper, width: 2.5),
                    boxShadow: [
                      BoxShadow(color: accent.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Icon(Icons.camera_alt_outlined, size: 15, color: SeenlyPalette.accentOnAccent),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: dial - 20,
            child: Center(
              child: AnimatedBuilder(
                animation: _intro,
                builder: (context, _) {
                  final pop = const Interval(0.55, 1.0, curve: Curves.easeOutBack).transform(_intro.value);
                  final fade = const Interval(0.55, 0.85).transform(_intro.value);
                  final count = const Interval(0.5, 1.0, curve: Curves.easeOutCubic).transform(_intro.value);
                  return Opacity(
                    opacity: fade,
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * pop,
                      child: PressScale(
                        onTap: _replay,
                        scaleTo: 0.94,
                        child: _LevelPill(level: (widget.level * count).round()),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarDisc() {
    final size = widget.avatarSize;
    return PressScale(
      onTap: widget.busy ? null : widget.onAvatarTap,
      scaleTo: 0.965,
      haptics: true,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size + _matPad * 2,
            height: size + _matPad * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SeenlyPalette.paper,
              boxShadow: [
                BoxShadow(color: SeenlyPalette.ink.withOpacity(0.20), blurRadius: 22, offset: const Offset(0, 8)),
              ],
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              child: widget.avatar,
            ),
          ),
          if (widget.busy)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.paper.withOpacity(0.7)),
              alignment: Alignment.center,
              child: const ThemedLoadingIndicator(size: 26),
            ),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  final int level;
  const _LevelPill({required this.level});

  @override
  Widget build(BuildContext context) {
    final accent = SeenlyPalette.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.5), width: 1.2),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 13, color: accent),
          const SizedBox(width: 6),
          Text(
            'level'.tr,
            style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted, weight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text('$level', style: SeenlyText.serif(size: 16, weight: FontWeight.w700, color: accent)),
        ],
      ),
    );
  }
}

class _LevelRingPainter extends CustomPainter {
  final double sweep; // 0..1 of the circle currently drawn
  final double reveal; // 0..1 track + ticks fading in
  final double stroke;
  final double ringRadius;
  final double tickGap;
  final Color accent;
  final Color track;
  final Color idleTick;
  final Color paper;

  static const int _ticks = 60;

  const _LevelRingPainter({
    required this.sweep,
    required this.reveal,
    required this.stroke,
    required this.ringRadius,
    required this.tickGap,
    required this.accent,
    required this.track,
    required this.idleTick,
    required this.paper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);

    // Track.
    canvas.drawCircle(
      c,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track.withOpacity(0.9 * reveal),
    );

    // Dial ticks, lighting up as the arc passes them.
    final tickStart = ringRadius + stroke / 2 + tickGap;
    for (var i = 0; i < _ticks; i++) {
      final a = -math.pi / 2 + i / _ticks * 2 * math.pi;
      final major = i % 5 == 0;
      final len = major ? 6.0 : 3.5;
      final lit = ((sweep - i / _ticks) * _ticks / 3).clamp(0.0, 1.0).toDouble();
      final base = Color.lerp(idleTick, accent, lit) ?? accent;
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = major ? 1.8 : 1.3
        ..color = base.withOpacity((0.26 + 0.6 * lit) * reveal);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * tickStart, c + dir * (tickStart + len), paint);
    }

    if (sweep <= 0.002) return;

    final rect = Rect.fromCircle(center: c, radius: ringRadius);
    final sweepAngle = 2 * math.pi * sweep;

    // Soft halo under the arc.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke + 3
        ..color = accent.withOpacity(0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // The arc itself, fading in from a pale tail up to the bead.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.max(sweepAngle, 0.05),
          colors: [accent.withOpacity(0.42), accent],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );

    // Bead riding the tip.
    final tipAngle = -math.pi / 2 + sweepAngle;
    final tip = c + Offset(math.cos(tipAngle), math.sin(tipAngle)) * ringRadius;
    canvas.drawCircle(
      tip,
      stroke * 1.5,
      Paint()
        ..color = accent.withOpacity(0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(tip, stroke * 0.62, Paint()..color = paper);
  }

  @override
  bool shouldRepaint(covariant _LevelRingPainter old) =>
      old.sweep != sweep ||
      old.reveal != reveal ||
      old.accent != accent ||
      old.track != track ||
      old.idleTick != idleTick ||
      old.paper != paper ||
      old.ringRadius != ringRadius;
}

// ---------------------------------------------------------------------------
// PointsProgressBar
// ---------------------------------------------------------------------------

/// The points bar: a ruled track that fills with a soft gradient when its card
/// scrolls into view, a pale sheen crossing the fill once it lands, and a
/// small bead at the leading edge. [value] is the final 0..1 fill.
class PointsProgressBar extends StatelessWidget {
  final double value;
  final Duration delay;

  const PointsProgressBar({super.key, required this.value, this.delay = Duration.zero});

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0).toDouble();
    return RevealProgress(
      delay: delay,
      duration: const Duration(milliseconds: 1600),
      curve: Curves.linear,
      builder: (context, t) {
        final fill = target * const Interval(0.0, 0.72, curve: Curves.easeOutCubic).transform(t);
        final sheen = const Interval(0.62, 1.0, curve: Curves.easeInOut).transform(t);
        return SizedBox(
          height: 28,
          width: double.infinity,
          child: CustomPaint(
            painter: _PointsBarPainter(
              fill: fill,
              sheen: sheen,
              accent: SeenlyPalette.accent,
              track: SeenlyPalette.border,
              tick: SeenlyPalette.paper,
              paper: SeenlyPalette.paper,
            ),
          ),
        );
      },
    );
  }
}

class _PointsBarPainter extends CustomPainter {
  final double fill;
  final double sheen;
  final Color accent;
  final Color track;
  final Color tick;
  final Color paper;

  const _PointsBarPainter({
    required this.fill,
    required this.sheen,
    required this.accent,
    required this.track,
    required this.tick,
    required this.paper,
  });

  static const double _h = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final top = cy - _h / 2;
    final radius = const Radius.circular(_h / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, top, size.width, _h), radius),
      Paint()..color = track,
    );
    final tickPaint = Paint()
      ..color = tick.withOpacity(0.7)
      ..strokeWidth = 1;
    for (var i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, top + 2.5), Offset(x, top + _h - 2.5), tickPaint);
    }

    if (fill <= 0.001) return;

    final w = math.max(size.width * fill, _h);
    final fillRRect = RRect.fromRectAndRadius(Rect.fromLTWH(0, top, w, _h), radius);

    canvas.save();
    canvas.clipRRect(fillRRect);
    canvas.drawRect(
      fillRRect.outerRect,
      Paint()
        ..shader = LinearGradient(
          colors: [accent.withOpacity(0.72), accent],
        ).createShader(fillRRect.outerRect),
    );
    // A thin highlight along the top edge — the glossy-ink look.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(3, top + 1.5, math.max(w - 6, 0), 2), const Radius.circular(1)),
      Paint()..color = Colors.white.withOpacity(0.22),
    );
    if (sheen > 0 && sheen < 1) {
      const bandW = 54.0;
      final x = -bandW + (w + bandW * 2) * sheen;
      final band = Rect.fromLTWH(x, top, bandW, _h);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withOpacity(0),
              Colors.white.withOpacity(0.42),
              Colors.white.withOpacity(0),
            ],
          ).createShader(band),
      );
    }
    canvas.restore();

    // Bead at the leading edge.
    final knob = Offset(w - _h / 2, cy);
    canvas.drawCircle(
      knob,
      11,
      Paint()
        ..color = accent.withOpacity(0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(knob, 7.5, Paint()..color = paper);
    canvas.drawCircle(knob, 4, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _PointsBarPainter old) =>
      old.fill != fill ||
      old.sheen != sheen ||
      old.accent != accent ||
      old.track != track ||
      old.tick != tick ||
      old.paper != paper;
}
