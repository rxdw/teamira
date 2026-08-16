import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wow_motion.dart' show ScrollReveal;

/// A two-column Pinterest-style mosaic, standing in for a rigid NxN
/// grid. Every third tile (in [order]) is stretched taller, so the two
/// columns settle at different heights instead of lining up row by row.
///
/// Originally built for the collection full-screen grid
/// (screens/collections/collection_full_screen.dart) and pulled out
/// here so every other "shelf of posters" screen — Profile's watched/
/// plan-to-watch tabs, a category's full watched list, a friend's
/// shelf — gets the same treatment instead of three more copies of the
/// same layout math.
///
/// Deliberately agnostic about what a "tile" is: the caller hands back
/// the fully-built widget for a given slot via [tileBuilder], already
/// wrapped in whatever [TiltPosterTile]/[MosaicParallaxPoster] combination it
/// wants — this widget only owns the column-balancing and the
/// scroll-reveal stagger.
///
/// Built as one plain widget (not a Sliver) because every call site so
/// far is a small, fully-loaded list (not an infinite/paginated feed),
/// so there's no lazy-building benefit to lose by laying it all out at
/// once inside the enclosing SliverToBoxAdapter.
class MosaicPosterGrid extends StatelessWidget {
  final int itemCount;
  final List<int> order;
  final int revealGen;
  final double spacing;

  /// A stable identity for the tile at [originalIndex] — combined with
  /// [revealGen] to key each ScrollReveal, so a reshuffle (new
  /// [revealGen]) replays the settle-in instead of silently reordering.
  final Object Function(int originalIndex) keyOf;

  /// Builds the tile for [originalIndex] (its position in the
  /// unordered source list) at [gridIndex] (its position in [order]),
  /// given the [aspectRatio] this slot was assigned.
  final Widget Function(
    BuildContext context,
    int originalIndex,
    int gridIndex,
    double aspectRatio,
  ) tileBuilder;

  const MosaicPosterGrid({
    super.key,
    required this.itemCount,
    required this.order,
    required this.revealGen,
    required this.keyOf,
    required this.tileBuilder,
    this.spacing = 14,
  });

  // 2:3 (normal) for most tiles, a noticeably taller 2:3.75 for every
  // third slot — enough contrast to read as intentional, not a bug.
  static double aspectFor(int gridIndex) => gridIndex % 3 == 2 ? 2 / 3.75 : 2 / 3;

  @override
  Widget build(BuildContext context) {
    final columns = <List<Widget>>[[], []];
    // Running height-per-unit-width for each column (both columns share
    // the same width, so 1/aspectRatio is directly comparable) — each
    // new tile goes to whichever column is currently shorter, which is
    // what actually produces the staggered look rather than a fixed
    // left/right alternation.
    final columnHeights = <double>[0, 0];

    for (var gridIndex = 0; gridIndex < order.length; gridIndex++) {
      final originalIndex = order[gridIndex];
      final aspect = aspectFor(gridIndex);
      final columnIndex = columnHeights[0] <= columnHeights[1] ? 0 : 1;
      columnHeights[columnIndex] += 1 / aspect;

      columns[columnIndex].add(
        Padding(
          padding: EdgeInsets.only(bottom: spacing),
          child: ScrollReveal(
            key: ValueKey('${keyOf(originalIndex)}-$revealGen'),
            // Capped rather than growing with gridIndex — only the
            // handful of tiles entering the viewport together in one
            // scroll pass should stagger against each other.
            delay: Duration(milliseconds: 35 * (gridIndex % 6)),
            child: tileBuilder(context, originalIndex, gridIndex, aspect),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: columns[0])),
        SizedBox(width: spacing),
        Expanded(child: Column(children: columns[1])),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Tap/long-press interactivity for mosaic tiles
// ---------------------------------------------------------------------

/// Wraps a poster tile with two layers of response: a live 3D tilt that
/// follows the finger while it's down (like the poster is a physical
/// card pivoting under your thumb), plus an optional long-press for a
/// secondary action (e.g. a quick-actions sheet) instead of only ever
/// reaching it through the title detail screen.
///
/// Tracking is done via a raw [Listener] (pointer down/move/up/cancel)
/// running *alongside* a [GestureDetector] for the semantic tap/long-press
/// gestures, rather than trying to do both through one recognizer set —
/// Listener doesn't enter the gesture arena, so it can freely watch every
/// pointer movement without ever competing with (or stealing) the tap/
/// long-press recognizers living on the GestureDetector next to it.
class TiltPosterTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const TiltPosterTile({super.key, required this.child, this.onTap, this.onLongPress});

  @override
  State<TiltPosterTile> createState() => _TiltPosterTileState();
}

class _TiltPosterTileState extends State<TiltPosterTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 340),
  );
  // Normalized -1..1 offset of the finger from the tile's center —
  // (-1,-1) is the top-left corner, (1,1) the bottom-right.
  Offset _touch = Offset.zero;
  Size _size = Size.zero;
  bool _firedLongPress = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _updateTouch(Offset local) {
    if (_size.isEmpty) return;
    final dx = ((local.dx / _size.width) * 2 - 1).clamp(-1.0, 1.0);
    final dy = ((local.dy / _size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() => _touch = Offset(dx, dy));
  }

  void _pressStart(Offset local) {
    _firedLongPress = false;
    _updateTouch(local);
    _c.forward();
  }

  void _pressEnd() {
    _c.reverse();
    setState(() => _touch = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return Listener(
          onPointerDown: (e) => _pressStart(e.localPosition),
          onPointerMove: (e) => _updateTouch(e.localPosition),
          onPointerUp: (_) => _pressEnd(),
          onPointerCancel: (_) => _pressEnd(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress == null
                ? null
                : () {
                    _firedLongPress = true;
                    HapticFeedback.mediumImpact();
                    widget.onLongPress!();
                  },
            // A completed long-press already released the finger inside
            // this widget, which would otherwise also fire onTap right
            // after — the flag swallows that duplicate open.
            onTapUp: _firedLongPress ? (_) {} : null,
            child: AnimatedBuilder(
              animation: _c,
              child: widget.child,
              builder: (context, child) {
                final t = _c.value;
                final rotX = -_touch.dy * 0.14 * t;
                final rotY = _touch.dx * 0.14 * t;
                final scale = 1.0 - 0.045 * t;
                final matrix = Matrix4.identity()
                  ..setEntry(3, 2, 0.0022)
                  ..rotateX(rotX)
                  ..rotateY(rotY)
                  ..scale(scale);
                return Transform(
                  alignment: Alignment.center,
                  transform: matrix,
                  child: child,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Drives ThemedPosterTile's `parallax` param from scroll position: the
/// poster art drifts a few px inside its frame as the tile moves through
/// the viewport, giving the grid a sense of depth instead of every image
/// just being glued to its card.
///
/// The shift is bounded by *where this tile currently sits in the
/// viewport* (measured via its own RenderBox on every scroll tick) —
/// not by raw scroll distance. A naive shift = factor * scrollOffset
/// keeps growing the further down the list you go, which would
/// eventually fling a far-down tile's artwork clean out of frame; this
/// version always stays within the same small range, however far you've
/// scrolled.
class MosaicParallaxPoster extends StatefulWidget {
  final Widget Function(double parallax) builder;
  const MosaicParallaxPoster({super.key, required this.builder});

  @override
  State<MosaicParallaxPoster> createState() => _MosaicParallaxPosterState();
}

class _MosaicParallaxPosterState extends State<MosaicParallaxPoster> {
  static const double _maxShiftPx = 15;
  final GlobalKey _key = GlobalKey();
  ScrollPosition? _scrollPosition;
  double _shift = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.of(context).position;
    if (!identical(position, _scrollPosition)) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = position;
      _scrollPosition!.addListener(_onScroll);
      // First measurement has to wait for this frame's layout to land.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final viewportHeight = MediaQuery.of(context).size.height;
    final centerY = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
    // -1 at the very top of the screen, 0 dead center, +1 at the bottom.
    final normalized = ((centerY / viewportHeight) * 2 - 1).clamp(-1.0, 1.0);
    final newShift = normalized * _maxShiftPx;
    // Skip the rebuild for sub-pixel jitter — scroll listeners fire on
    // every frame while scrolling, and most of those deltas are too
    // small to ever paint differently.
    if ((newShift - _shift).abs() > 0.15) {
      setState(() => _shift = newShift);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.builder(_shift));
  }
}
