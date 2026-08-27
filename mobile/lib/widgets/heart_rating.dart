import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';

/// One heart per point on the scale (now 1-10, up from the original 1-5) —
/// wraps rather than sitting in a single Row so ten hearts never overflow
/// a narrow row the way five always safely did. Filled hearts pick up
/// [SeenlyPalette.ratingColor] for the current value, so a 9/10 genuinely
/// looks warmer than a 3/10 rather than every rating being the same plum.
///
/// Every heart whose filled state just changed gives a small punch-out
/// pop rather than snapping instantly — the app's other "wow" moments
/// (achievement unlock, level-up, favoriting) are all occasional
/// set-pieces, but rating happens on essentially every log, so this is
/// deliberately the smallest, quietest version of that same idea: felt
/// more than seen. Landing on a perfect score gets one size up from
/// that — a brief warm glow behind the whole row — since a 10/10 is
/// rare enough to earn a beat of its own without turning into a
/// full-screen moment for something that isn't a milestone or a badge.
///
/// API is unchanged from the previous stateless version — every
/// existing call site (read-only rows in Diary, the flight-log board,
/// series episodes, watched-preview, and the interactive pickers in the
/// log flow and edit-review sheet) keeps working exactly as before.
class HeartRating extends StatefulWidget {
  final int value; // 0-10
  final int max;
  final double size;
  final ValueChanged<int>? onChanged; // null = read-only

  const HeartRating({
    super.key,
    required this.value,
    this.max = 10,
    this.size = 15,
    this.onChanged,
  });

  @override
  State<HeartRating> createState() => _HeartRatingState();
}

class _HeartRatingState extends State<HeartRating> with TickerProviderStateMixin {
  // One pop controller per heart position, created lazily and kept for
  // the widget's lifetime — idles at 0 (no visual effect) and plays a
  // single punch-out-and-settle whenever that heart's filled state
  // flips. Not disposed individually since [dispose] below tears down
  // every controller in the map at once.
  final Map<int, AnimationController> _pops = {};

  // Created lazily on the first perfect score this widget instance
  // sees; stays around (idling at its end value, which reads as "no
  // glow" — see build()) rather than being torn down and rebuilt on
  // every rating change, since most ratings never touch it again.
  AnimationController? _perfectCtrl;

  AnimationController _popFor(int i) {
    return _pops.putIfAbsent(
      i,
      () => AnimationController(vsync: this, duration: const Duration(milliseconds: 300)),
    );
  }

  @override
  void didUpdateWidget(covariant HeartRating oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;

    // Pop every heart whose filled state just flipped — a single tap
    // moves the boundary by one, but a drag or a big jump moves it by
    // several, and staggering those slightly makes a jump read as a
    // quick ripple across the changed hearts rather than everything
    // snapping in lockstep.
    final lo = math.min(oldWidget.value, widget.value);
    final hi = math.max(oldWidget.value, widget.value);
    var delayMs = 0;
    for (var i = lo + 1; i <= hi; i++) {
      final ctrl = _popFor(i);
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        ctrl.forward(from: 0);
      });
      delayMs += 16;
    }

    if (widget.max > 0 && widget.value == widget.max && oldWidget.value != widget.max) {
      _playPerfect();
    }
  }

  void _playPerfect() {
    final ctrl = _perfectCtrl ??=
        AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    HapticFeedback.mediumImpact();
    ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    for (final c in _pops.values) {
      c.dispose();
    }
    _perfectCtrl?.dispose();
    super.dispose();
  }

  /// A quick overshoot-then-settle scale curve: punches out past 1.0
  /// early, then eases back with a touch of bounce — plain interpolation
  /// (`t` mapped straight to scale) would just look like a fast zoom,
  /// not a heart popping.
  double _popScale(double t) {
    if (t <= 0 || t >= 1) return 1.0;
    if (t < 0.35) {
      return 1.0 + Curves.easeOut.transform(t / 0.35) * 0.4;
    }
    final settle = (t - 0.35) / 0.65;
    return 1.4 - Curves.easeOutBack.transform(settle) * 0.4;
  }

  @override
  Widget build(BuildContext context) {
    final filledColor = SeenlyPalette.ratingColor(widget.value > 0 ? widget.value : null);

    final row = Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (int i = 1; i <= widget.max; i++)
          GestureDetector(
            onTap: widget.onChanged == null ? null : () => widget.onChanged!(i),
            child: AnimatedBuilder(
              animation: _popFor(i),
              builder: (context, child) =>
                  Transform.scale(scale: _popScale(_popFor(i).value), child: child),
              child: Icon(
                i <= widget.value ? Icons.favorite : Icons.favorite_border,
                size: widget.size,
                color: i <= widget.value ? filledColor : SeenlyPalette.dashedBorder,
              ),
            ),
          ),
      ],
    );

    final perfectCtrl = _perfectCtrl;
    if (perfectCtrl == null) return row;

    return AnimatedBuilder(
      animation: perfectCtrl,
      builder: (context, child) {
        // A single rise-and-fall glow behind the whole row — sin(0)
        // and sin(pi) both land on 0, so this blooms in and fades back
        // out on its own without needing a separate reverse animation.
        final glow = math.sin(perfectCtrl.value.clamp(0.0, 1.0) * math.pi);
        if (glow < 0.01) return child!;
        return DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: SeenlyPalette.accent.withOpacity(0.4 * glow),
                blurRadius: 22 * glow,
                spreadRadius: 3 * glow,
              ),
            ],
          ),
          child: child,
        );
      },
      child: row,
    );
  }
}
