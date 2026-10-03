import 'package:flutter/material.dart';

/// Small, calm building blocks for changing what's on screen without a
/// hard cut. They sit next to the older kit in wow_motion.dart (Entrance,
/// PressScale, Breathe …) and follow the same rule: quiet on purpose — a
/// few pixels of travel, a soft fade, never a bounce that competes with
/// the content. Every one of them falls back to a plain cross-fade when
/// the system asks for reduced motion.

/// Swaps between the screens of a step-by-step flow with a little sideways
/// travel that follows the direction the person is going: forward, the new
/// step glides in from the right while the old one drifts off to the left;
/// back, the other way round.
///
/// Give it the current [step] number and the widget for that step — it
/// tells forward from back itself by comparing with the previous number,
/// so the caller doesn't have to track a direction.
///
/// With [expand] the outgoing and incoming steps are both forced to fill
/// the space they're given (right for a step that's a `Column` with
/// `Expanded` children); without it they take their natural size (right
/// for something like a calendar grid, whose height differs between
/// pages).
class StepSwitcher extends StatefulWidget {
  final int step;
  final Widget child;
  final bool expand;
  final Duration duration;

  /// How far the steps travel, as a fraction of their own width.
  final double shift;

  const StepSwitcher({
    super.key,
    required this.step,
    required this.child,
    this.expand = false,
    this.duration = const Duration(milliseconds: 360),
    this.shift = 0.07,
  });

  @override
  State<StepSwitcher> createState() => _StepSwitcherState();
}

class _StepSwitcherState extends State<StepSwitcher> {
  int _direction = 1;

  @override
  void didUpdateWidget(StepSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step != oldWidget.step) {
      _direction = widget.step > oldWidget.step ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final currentKey = ValueKey<int>(widget.step);

    return AnimatedSwitcher(
      duration: widget.duration,
      reverseDuration: widget.duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        fit: widget.expand ? StackFit.expand : StackFit.loose,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        if (reduceMotion) {
          return FadeTransition(opacity: animation, child: child);
        }
        // The incoming step starts on the side it's coming from; the
        // outgoing one (its animation runs 1→0) ends on the opposite side.
        final incoming = child.key == currentKey;
        final dx = widget.shift * (incoming ? _direction : -_direction);
        final slide = Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
            .animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(key: currentKey, child: widget.child),
    );
  }
}

/// Cross-fades a small piece of UI (a heading, a line of text, an icon, a
/// button label) into its replacement with a slight rise — the new one
/// comes up from just below, the old one leaves upward.
///
/// Whatever is passed as [child] must carry a `key` that changes when its
/// content should count as "different" (same idea as `AnimatedSwitcher`,
/// which this wraps): `SoftSwap(child: Text(label, key: ValueKey(label)))`.
///
/// [rise] is the travel as a fraction of the child's own height, so it
/// stays proportionate whether it's swapping a caption or a big number.
/// [pop] adds a soft scale-up on the way in — for icons, not text.
/// With [expand] the outgoing and incoming pictures are both stretched to
/// fill the space (for swapping whole screen bodies, like [StepSwitcher]).
class SoftSwap extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final double rise;
  final bool pop;
  final bool expand;
  final AlignmentGeometry alignment;

  const SoftSwap({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 260),
    this.rise = 0.22,
    this.pop = false,
    this.expand = false,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final currentKey = child.key;

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        fit: expand ? StackFit.expand : StackFit.loose,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        if (reduceMotion) {
          return FadeTransition(opacity: animation, child: child);
        }
        // The incoming one climbs from just below to rest; the outgoing
        // one (its animation runs 1→0) ends just above, so it leaves
        // upward.
        final incoming = child.key == currentKey;
        final slide = Tween<Offset>(
          begin: Offset(0, incoming ? rise : -rise),
          end: Offset.zero,
        ).animate(animation);
        Widget out = SlideTransition(position: slide, child: child);
        if (pop) {
          out = ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: out,
          );
        }
        return FadeTransition(opacity: animation, child: out);
      },
      child: child,
    );
  }
}
