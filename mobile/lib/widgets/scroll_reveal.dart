import 'package:flutter/material.dart';

/// Wraps a card with the same scroll-driven reveal the diary's log
/// already uses ([ScrapbookEntry] in log_timeline.dart): rather than a
/// fire-once "wait N ms then fade in" on first build, the card's
/// entrance is tied directly to the list's own [ScrollController] — it
/// eases up and drifts in from the side as its top crosses into the
/// viewport, catches up instantly if you flick fast, and — the part a
/// timed animation can never do — recedes again if you scroll back up
/// past it. That two-way link to the finger on the screen is what
/// reads as "alive" instead of "played once."
///
/// Deliberately generic (just a child, an index, and a couple of knobs)
/// so the programme, the route, and the garden bed can all share one
/// implementation instead of three copies of the same scroll-listener
/// bookkeeping — see _ScreeningCard, _StopTicketCard, _BloomCard.
class ScrollRevealEntrance extends StatefulWidget {
  final int index;
  final Widget child;

  /// How far the card drifts in sideways, alternating left/right by
  /// [index] parity. 0 disables the drift entirely (still fades/lifts).
  final double driftDistance;

  const ScrollRevealEntrance({
    super.key,
    required this.index,
    required this.child,
    this.driftDistance = 20,
  });

  @override
  State<ScrollRevealEntrance> createState() => _ScrollRevealEntranceState();
}

class _ScrollRevealEntranceState extends State<ScrollRevealEntrance> {
  // 0 = still below the fold, 1 = fully settled. Driven by scroll offset
  // rather than a ticker — see log_timeline.dart's ScrapbookEntry for
  // the fuller rationale, this is the same mechanic.
  double _t = 0;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    final newPosition = scrollable?.position;
    if (newPosition != _position) {
      _position?.removeListener(_onScroll);
      _position = newPosition;
      _position?.addListener(_onScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final scrollableBox = Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || scrollableBox == null || !scrollableBox.attached) return;
    final itemTop = box.localToGlobal(Offset.zero, ancestor: scrollableBox).dy;
    final viewportHeight = scrollableBox.size.height;
    const revealWindow = 190.0;
    final t = ((viewportHeight - itemTop) / revealWindow).clamp(0.0, 1.0);
    if ((t - _t).abs() > 0.004) {
      setState(() => _t = t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driftX = widget.driftDistance == 0
        ? 0.0
        : (widget.index.isEven ? -1 : 1) * widget.driftDistance * (1 - _t);

    return Opacity(
      opacity: _t,
      child: Transform.translate(
        offset: Offset(driftX, (1 - _t) * 26),
        child: Transform.scale(
          scale: 0.97 + 0.03 * _t,
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
