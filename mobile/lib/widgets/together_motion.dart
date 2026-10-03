import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'soft_motion.dart';
import 'wow_motion.dart' show PressScale;
import '../theme/clay_kit.dart';

/// The animated pieces the two "decide with your person" screens share —
/// Watch Together (screens/together/together_screen.dart) and the circle's
/// vote (screens/partner/co_view_vote_screen.dart). Both are the same
/// thing at heart: a deck of cards, a yes or a no for each, and another
/// person somewhere on the other end. These moments are the emotional core
/// of the app, so the motion here is warm and a little playful — hearts,
/// a card that leans into your thumb, a number that fills as they catch up
/// — while keeping to the rule of the rest of the kit: nothing loud, and
/// everything settles back to still (and to a plain fade when the system
/// asks for reduced motion).

// ---------------------------------------------------------------------------
// The deck
// ---------------------------------------------------------------------------

/// The stack of cards: the one you're holding on top, two more fanned out
/// behind it. When the top one is decided, the next glides forward into its
/// place and a new one slides in at the back, instead of the whole stack
/// snapping to new positions.
///
/// It only lays the cards out — what a card looks like is up to
/// [topBuilder] (the live, draggable one) and [backBuilder] (the plain
/// faces behind it). [keyOf] must give every card a stable identity, which
/// is how a card is recognised as "the same one, one step closer".
class DeckStack extends StatelessWidget {
  /// Position of the top card in the deck.
  final int index;

  /// Total cards in the deck.
  final int count;
  final String Function(int i) keyOf;
  final Widget Function(int i) topBuilder;
  final Widget Function(int i) backBuilder;

  const DeckStack({
    super.key,
    required this.index,
    required this.count,
    required this.keyOf,
    required this.topBuilder,
    required this.backBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final last = math.min(index + 2, count - 1);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Deepest first, so the top card is painted last.
        for (var i = last; i >= index; i--)
          _DeckLayer(
            key: ValueKey<String>('layer:${keyOf(i)}'),
            depth: i - index,
            // Alternating by the card's own place in the deck (not by how
            // deep it is right now), so a card keeps leaning the same way
            // as it moves forward.
            sign: i.isEven ? 1 : -1,
            child: i == index ? topBuilder(i) : backBuilder(i),
          ),
      ],
    );
  }
}

class _DeckLayer extends StatelessWidget {
  final int depth;
  final int sign;
  final Widget child;

  const _DeckLayer({
    super.key,
    required this.depth,
    required this.sign,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return _place(depth.toDouble(), child);
    }
    // The tween's `begin` only matters when the layer first appears: a new
    // card slides in from one step further back. After that, each change of
    // depth animates from wherever the card currently is to its new place.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: depth + 1.0, end: depth.toDouble()),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, d, child) => _place(d, child!),
    );
  }

  /// [d] is a card's depth as a continuous number: 0 = the top card,
  /// 1 and 2 = the ones behind it, 3 = just about to appear.
  Widget _place(double d, Widget child) {
    final appear = (1 - (d - 2).clamp(0.0, 1.0)).toDouble();
    return Opacity(
      opacity: appear,
      child: Transform.translate(
        offset: Offset(d * 9 * sign, d * 9),
        child: Transform.scale(
          scale: 1 - d * 0.045,
          child: Transform.rotate(
            angle: 0.035 * sign * d.clamp(0.0, 1.0).toDouble(),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One side of a swipe: what's revealed behind the card as it's dragged
/// that way.
class SwipeSide {
  final IconData icon;
  final String label;
  final Color color;

  const SwipeSide({required this.icon, required this.label, required this.color});
}

/// The draggable top card. Swiping right is a yes ([yes]), left a no
/// ([no]) — releasing far enough commits it through [onDecide], exactly
/// like tapping the matching button.
///
/// While the card is being dragged it leans the way it's going (pivoting
/// from its bottom edge, like something held in a hand), the icon behind it
/// swells and brightens, and a light tick fires once when the drag passes
/// the point of no return.
///
/// Needs a stable [key]: it doubles as the `Dismissible`'s key, so each
/// card is dismissed as its own thing.
class SwipeableCard extends StatefulWidget {
  final Widget child;
  final SwipeSide yes;
  final SwipeSide no;
  final ValueChanged<bool> onDecide;

  const SwipeableCard({
    required Key key,
    required this.child,
    required this.yes,
    required this.no,
    required this.onDecide,
  }) : super(key: key);

  @override
  State<SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<SwipeableCard> {
  /// −1..1: how far the card is dragged, positive toward "yes".
  final ValueNotifier<double> _drag = ValueNotifier<double>(0);

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _onUpdate(DismissUpdateDetails details) {
    final toward = details.direction == DismissDirection.startToEnd ? 1.0 : -1.0;
    _drag.value = toward * details.progress;
    if (details.reached && !details.previousReached) {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Dismissible(
      key: widget.key!,
      direction: DismissDirection.horizontal,
      onUpdate: _onUpdate,
      onDismissed: (direction) => widget.onDecide(direction == DismissDirection.startToEnd),
      background: _SwipeHint(
        side: widget.yes,
        alignment: Alignment.centerLeft,
        drag: _drag,
        toward: 1,
      ),
      secondaryBackground: _SwipeHint(
        side: widget.no,
        alignment: Alignment.centerRight,
        drag: _drag,
        toward: -1,
      ),
      child: reduceMotion
          ? widget.child
          : ValueListenableBuilder<double>(
              valueListenable: _drag,
              child: widget.child,
              builder: (context, drag, child) => Transform.rotate(
                angle: drag * 0.12,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  final SwipeSide side;
  final Alignment alignment;
  final ValueListenable<double> drag;
  final double toward;

  const _SwipeHint({
    required this.side,
    required this.alignment,
    required this.drag,
    required this.toward,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: drag,
      builder: (context, value, _) {
        final eased = Curves.easeOut.transform((value * toward).clamp(0.0, 1.0).toDouble());
        return Container(
          decoration: BoxDecoration(
            color: side.color,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: SeenlyPalette.ink.withOpacity(0.14),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: alignment,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.8 + 0.5 * eased,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14 + 0.22 * eased),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(side.icon, color: SeenlyPalette.paper, size: 22),
                ),
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: 0.55 + 0.45 * eased,
                child: Text(
                  side.label,
                  style: SeenlyText.mono(
                    size: 10,
                    color: SeenlyPalette.paper,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Pills, buttons, counters
// ---------------------------------------------------------------------------

/// The small status pill above a deck ("12 left", "anna: 5 of 20"). The
/// words swap softly when they change, and with [progress] the pill fills
/// from the left like a little tide coming in — so somebody else's
/// progress is something you can watch creep along, not just a number that
/// occasionally changes.
class DeckPill extends StatelessWidget {
  final String label;

  /// 0..1; null for a plain pill.
  final double? progress;

  const DeckPill(this.label, {super.key, this.progress});

  @override
  Widget build(BuildContext context) {
    final fill = progress;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: Stack(
          children: [
            if (fill != null)
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: fill.clamp(0.0, 1.0).toDouble()),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: ColoredBox(color: SeenlyPalette.accent.withOpacity(0.14)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              child: SoftSwap(
                alignment: Alignment.center,
                rise: 0.4,
                duration: const Duration(milliseconds: 220),
                child: Text(
                  label,
                  key: ValueKey<String>(label),
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two round buttons under a deck: a soft circle that dips under
/// the finger. The big [large] one (the "yes") also gives a light tick.
class DecisionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color background;
  final bool large;
  final bool bordered;
  final VoidCallback onTap;

  const DecisionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.background,
    required this.onTap,
    this.large = false,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 52.0;
    return PressScale(
      onTap: onTap,
      scaleTo: 0.9,
      haptics: large,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: bordered ? Border.all(color: SeenlyPalette.border) : null,
              boxShadow: [
                BoxShadow(
                  color: SeenlyPalette.ink.withOpacity(large ? 0.16 : 0.08),
                  blurRadius: large ? 18 : 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: large ? 26 : 20, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(label, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
        ],
      ),
    );
  }
}

/// The little "♥ 3" in a header: the heart gives a beat and the number
/// pops each time [count] goes up, and the whole thing eases in and out
/// with [visible] instead of appearing and vanishing.
class MatchCounter extends StatefulWidget {
  final int count;
  final bool visible;

  const MatchCounter({super.key, required this.count, required this.visible});

  @override
  State<MatchCounter> createState() => _MatchCounterState();
}

class _MatchCounterState extends State<MatchCounter> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didUpdateWidget(MatchCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > oldWidget.count) _beat.forward(from: 0);
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerRight,
      child: !widget.visible
          ? const SizedBox(height: 1)
          : Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _beat,
                    builder: (context, child) => Transform.scale(
                      scale: 1 + 0.5 * math.sin(_beat.value * math.pi),
                      child: child,
                    ),
                    child: Icon(Icons.favorite, size: 13, color: SeenlyPalette.accent),
                  ),
                  const SizedBox(width: 4),
                  SoftSwap(
                    pop: true,
                    alignment: Alignment.center,
                    child: Text(
                      '${widget.count}',
                      key: ValueKey<int>(widget.count),
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hearts
// ---------------------------------------------------------------------------

void _paintHeart(Canvas canvas, Offset c, double s, Paint paint) {
  final path = Path()
    ..moveTo(c.dx, c.dy + s * 0.9)
    ..cubicTo(c.dx - s * 1.5, c.dy - s * 0.2, c.dx - s * 0.7, c.dy - s * 1.2, c.dx, c.dy - s * 0.4)
    ..cubicTo(c.dx + s * 0.7, c.dy - s * 1.2, c.dx + s * 1.5, c.dy - s * 0.2, c.dx, c.dy + s * 0.9)
    ..close();
  canvas.drawPath(path, paint);
}

/// Nine little hearts that fan out upward from the middle, drift, and fade —
/// [t] is 0..1 across the whole burst. Shared by [MatchBeat] and
/// [HeartsBurst].
class _HeartsPainter extends CustomPainter {
  final double t;
  final double reach;

  const _HeartsPainter({required this.t, this.reach = 1});

  static const _count = 9;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final centre = Offset(size.width / 2, size.height / 2 - 6);
    for (int i = 0; i < _count; i++) {
      // Fanned across the upper half, each with its own delay and reach.
      final angle = -math.pi / 2 + (i - (_count - 1) / 2) * 0.42;
      final delay = ((i * 37) % 10) / 10 * 0.25;
      final local = ((t - 0.1 - delay) / (0.9 - delay)).clamp(0.0, 1.0).toDouble();
      if (local <= 0) continue;
      final travel = Curves.easeOutCubic.transform(local) * (70 + 30 * (i % 3)) * reach;
      final pos = centre +
          Offset(math.cos(angle) * travel, math.sin(angle) * travel - 26 * local);
      final life = math.sin(math.pi * local);
      final color = i.isEven ? SeenlyPalette.accent : SeenlyPalette.pink;
      _paintHeart(
        canvas,
        pos,
        (4.5 + (i % 3) * 2.2) * (0.5 + 0.5 * life),
        Paint()..color = color.withOpacity(0.85 * life),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeartsPainter old) => old.t != t || old.reach != reach;
}

/// A short "that's a match" moment laid over a deck: a small paper card
/// pops in with a heart, a few hearts float up from it, then it fades —
/// under a second and a half, and it never asks anything.
///
/// Plays each time [tick] goes up (and only then). [headline] is the line
/// on the card; [subtitle], when there is one, sits under it (the title
/// that matched, say). Wrap it in an `IgnorePointer` so it can't catch
/// touches meant for the deck underneath.
class MatchBeat extends StatefulWidget {
  final int tick;
  final String headline;
  final String? subtitle;

  const MatchBeat({
    super.key,
    required this.tick,
    required this.headline,
    this.subtitle,
  });

  @override
  State<MatchBeat> createState() => _MatchBeatState();
}

class _MatchBeatState extends State<MatchBeat> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.72, end: 1.08).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 34,
    ),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 34),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95), weight: 20),
  ]).animate(_c);
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
  ]).animate(_c);

  @override
  void didUpdateWidget(covariant MatchBeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tick != oldWidget.tick && widget.tick > 0) _c.forward(from: 0);
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
        if (_c.isDismissed || _c.isCompleted) return const SizedBox.shrink();
        return SizedBox(
          width: 300,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (!reduceMotion)
                Positioned.fill(child: CustomPaint(painter: _HeartsPainter(t: _c.value))),
              Opacity(
                opacity: _opacity.value,
                child: Transform.scale(
                  scale: reduceMotion ? 1.0 : _scale.value,
                  child: _card(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card() {
    final subtitle = widget.subtitle;
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: SeenlyPalette.ink.withOpacity(0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite, size: 22, color: SeenlyPalette.accent),
          const SizedBox(height: 6),
          Text(
            widget.headline,
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent, weight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Plays the same float-up hearts once as soon as it appears, around
/// whatever [child] is — for a celebration screen that should open with a
/// little shower of them rather than nothing.
class HeartsBurst extends StatefulWidget {
  final Widget child;
  final Duration delay;

  /// How far the hearts travel, 1 = as far as on a [MatchBeat]. Smaller
  /// where there's little room above the child.
  final double reach;

  const HeartsBurst({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 250),
    this.reach = 1.0,
  });

  @override
  State<HeartsBurst> createState() => _HeartsBurstState();
}

class _HeartsBurstState extends State<HeartsBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _delay = Timer(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _HeartsPainter(t: _c.value, reach: widget.reach),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A heart (or any icon) with a resting heartbeat: a double thump, then a
/// pause, with a thin ring spreading out from it on the first thump.
/// [ring] turns the ring off (for tight spaces).
class HeartbeatIcon extends StatefulWidget {
  final double size;
  final Color? color;
  final IconData icon;
  final bool ring;

  const HeartbeatIcon({
    super.key,
    this.size = 26,
    this.color,
    this.icon = Icons.favorite,
    this.ring = true,
  });

  @override
  State<HeartbeatIcon> createState() => _HeartbeatIconState();
}

class _HeartbeatIconState extends State<HeartbeatIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _bump(double t, double from, double to) =>
      (t <= from || t >= to) ? 0.0 : math.sin((t - from) / (to - from) * math.pi);

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? SeenlyPalette.accent;
    if (MediaQuery.of(context).disableAnimations) {
      return Icon(widget.icon, size: widget.size, color: color);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final beat = _bump(t, 0.0, 0.14) + 0.65 * _bump(t, 0.18, 0.32);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (widget.ring && t < 0.6)
                CustomPaint(
                  size: Size.square(widget.size),
                  painter: _RingPainter(
                    p: t / 0.6,
                    color: color,
                    minRadius: widget.size * 0.5,
                    maxRadius: widget.size * 1.5,
                  ),
                ),
              Transform.scale(
                scale: 1 + 0.2 * beat,
                child: Icon(widget.icon, size: widget.size, color: color),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double p; // 0..1
  final Color color;
  final double minRadius;
  final double maxRadius;

  const _RingPainter({
    required this.p,
    required this.color,
    required this.minRadius,
    required this.maxRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOutCubic.transform(p.clamp(0.0, 1.0).toDouble());
    canvas.drawCircle(
      size.center(Offset.zero),
      minRadius + (maxRadius - minRadius) * eased,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * (1 - eased) + 0.4
        ..color = color.withOpacity(0.3 * (1 - eased)),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.p != p || old.color != color;
}

// ---------------------------------------------------------------------------
// Waiting, loading, feedback
// ---------------------------------------------------------------------------

/// "Waiting for them": a heart in the middle with rings spreading out
/// from it one after another, the way a signal goes out and waits to be
/// answered. Calm and endless — it's meant to be sat with.
class WaitingRipples extends StatefulWidget {
  final double size;

  const WaitingRipples({super.key, this.size = 120});

  @override
  State<WaitingRipples> createState() => _WaitingRipplesState();
}

class _WaitingRipplesState extends State<WaitingRipples> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduceMotion)
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                size: Size.square(widget.size),
                painter: _RipplesPainter(t: _c.value, color: SeenlyPalette.accent),
              ),
            ),
          Container(
            width: widget.size * 0.36,
            height: widget.size * 0.36,
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: HeartbeatIcon(size: widget.size * 0.17, ring: false),
          ),
        ],
      ),
    );
  }
}

class _RipplesPainter extends CustomPainter {
  final double t;
  final Color color;

  const _RipplesPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final inner = size.shortestSide * 0.19;
    final outer = size.shortestSide * 0.5;
    for (int i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final eased = Curves.easeOut.transform(p);
      canvas.drawCircle(
        centre,
        inner + (outer - inner) * eased,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withOpacity(0.32 * (1 - p) * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RipplesPainter old) => old.t != t || old.color != color;
}

/// While a deck is being put together: three cards riffle open into a fan
/// and close again, over a line of text. Stands in for a spinner on the
/// screens whose whole subject is a deck of cards.
class CardShuffleLoader extends StatefulWidget {
  final String caption;

  const CardShuffleLoader({super.key, required this.caption});

  @override
  State<CardShuffleLoader> createState() => _CardShuffleLoaderState();
}

class _CardShuffleLoaderState extends State<CardShuffleLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _card({required bool front}) => Container(
        width: 50,
        height: 72,
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SeenlyPalette.border),
          boxShadow: [
            BoxShadow(
              color: SeenlyPalette.ink.withOpacity(0.10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: front
            ? Icon(Icons.favorite, size: 16, color: SeenlyPalette.accent.withOpacity(0.7))
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 130,
            height: 100,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                // 0 = squared up, 1 = fully fanned; eases in and out.
                final open = reduceMotion
                    ? 0.5
                    : 0.5 - 0.5 * math.cos(_c.value * 2 * math.pi);
                Widget fanned(int side) => Transform.translate(
                      offset: Offset(side * 30.0 * open, -4.0 * open),
                      child: Transform.rotate(
                        angle: side * 0.38 * open,
                        alignment: Alignment.bottomCenter,
                        child: _card(front: false),
                      ),
                    );
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    fanned(-1),
                    fanned(1),
                    Transform.translate(
                      offset: Offset(0, -6.0 * open),
                      child: _card(front: true),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          SoftSwap(
            alignment: Alignment.center,
            child: Text(
              widget.caption,
              key: ValueKey<String>(widget.caption),
              style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

/// A short code (the pairing / session code) shown as a row of tiles that
/// pop in one after another, left to right, as if stamped onto a ticket.
class CodeTiles extends StatefulWidget {
  final String code;
  final double tileWidth;
  final double tileHeight;
  final double fontSize;

  const CodeTiles({
    super.key,
    required this.code,
    this.tileWidth = 38,
    this.tileHeight = 52,
    this.fontSize = 24,
  });

  @override
  State<CodeTiles> createState() => _CodeTilesState();
}

class _CodeTilesState extends State<CodeTiles> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..forward();

  late final List<Animation<double>> _grow = _intervals(Curves.easeOutBack);
  late final List<Animation<double>> _fade = _intervals(Curves.easeOut);

  List<Animation<double>> _intervals(Curve curve) {
    final n = widget.code.length;
    return List.generate(n, (i) {
      final start = n <= 1 ? 0.0 : (i / n) * 0.55;
      final end = (start + 0.45).clamp(0.0, 1.0).toDouble();
      return CurvedAnimation(parent: _c, curve: Interval(start, end, curve: curve));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _tile(int i, String char, bool reduceMotion) {
    final tile = Container(
      width: widget.tileWidth,
      height: widget.tileHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: SeenlyPalette.border),
        boxShadow: [
          BoxShadow(
            color: SeenlyPalette.ink.withOpacity(0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        char,
        style: SeenlyText.mono(
          size: widget.fontSize,
          weight: FontWeight.w700,
          color: SeenlyPalette.ink,
        ),
      ),
    );
    if (reduceMotion) return tile;
    return FadeTransition(
      opacity: _fade[i],
      child: ScaleTransition(scale: _grow[i], child: tile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final chars = widget.code.split('');
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < chars.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _tile(i, chars[i], reduceMotion),
          ],
        ],
      ),
    );
  }
}

/// Shakes its child sideways a few times whenever [trigger] changes to a
/// new non-null value — a wrong code, a rejected input. Quick and small:
/// a "no" that doesn't scold.
class ShakeOnChange extends StatefulWidget {
  final Object? trigger;
  final Widget child;

  const ShakeOnChange({super.key, required this.trigger, required this.child});

  @override
  State<ShakeOnChange> createState() => _ShakeOnChangeState();
}

class _ShakeOnChangeState extends State<ShakeOnChange> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(ShakeOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != null && widget.trigger != oldWidget.trigger) {
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
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final dx = math.sin(t * math.pi * 5) * 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// A poster (or any keepsake) arriving on a celebration screen: rises from
/// a touch smaller and slightly tilted, and sits upright — as if set down
/// on a table. Plays once. [duration] shortens it for things that arrive
/// often (a re-rolled pick); [fade] false skips the fade-in for a child
/// that's already fading in some other way.
class SettleIn extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final bool fade;

  const SettleIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 720),
    this.fade = true,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) {
        final placed = Transform.rotate(
          angle: (1 - t) * 0.05,
          child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
        );
        return fade ? Opacity(opacity: t, child: placed) : placed;
      },
    );
  }
}
