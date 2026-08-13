import 'package:flutter/widgets.dart';
import 'package:flutter/physics.dart';

/// Snaps a horizontal shelf to the nearest card on release, instead of
/// letting a flick coast to a stop wherever the finger happened to let
/// go — a card left sitting half off-screen at the edge of the shelf.
///
/// [ShelfStackCarousel] and [HeroStackCarousel] already get a settle-
/// into-place feel for free because they're built on [PageView], which
/// snaps by construction. The plainer shelves — the "recent diary"
/// polaroid strip and "for you, with trailers" on Home — are ordinary
/// [ListView.separated]s with no such thing, so this gives them the
/// same behavior without switching them over to PageView (their cards
/// don't fill the viewport one at a time the way a PageView page does,
/// so PageView's own snapping unit — the full viewport — isn't the
/// right one here; this snaps to *card width*, not viewport width).
///
/// Chains onto whatever the ambient [ScrollBehavior] provides (see
/// [SeenlyScrollBehavior]) — normal bounce at the very first/last card,
/// snap to the nearest card everywhere in between.
class CardSnapScrollPhysics extends ScrollPhysics {
  /// Width of one card *including* the gap that follows it — the
  /// distance from one card's leading edge to the next one's.
  final double itemExtent;

  /// The shelf's own leading padding (its `EdgeInsets` before the first
  /// card), so card 0 snaps flush against it rather than a phantom
  /// card-width further in.
  final double leadingPadding;

  const CardSnapScrollPhysics({
    required this.itemExtent,
    this.leadingPadding = 0,
    super.parent,
  });

  @override
  CardSnapScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CardSnapScrollPhysics(
      itemExtent: itemExtent,
      leadingPadding: leadingPadding,
      parent: buildParent(ancestor),
    );
  }

  // A touch softer than PageView's own default settle — these are small
  // cards peeking at the shelf's edges, not full-bleed pages, so a
  // slightly gentler stop reads better.
  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100, ratio: 1.1);

  double _page(ScrollMetrics position) =>
      (position.pixels - leadingPadding) / itemExtent;

  double _pixelsForPage(ScrollMetrics position, double page) {
    final maxPage = ((position.maxScrollExtent - leadingPadding) / itemExtent)
        .clamp(0.0, double.infinity)
        .ceilToDouble();
    return page.clamp(0.0, maxPage) * itemExtent + leadingPadding;
  }

  double _targetPixels(
      ScrollMetrics position, Tolerance tolerance, double velocity) {
    var page = _page(position);
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    return _pixelsForPage(position, page.roundToDouble());
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // Past either end and still headed further out — that's the parent
    // (bounce) physics' job to rebound, snapping has nothing to add at
    // the boundary itself.
    final atLeadingEdge =
        velocity <= 0.0 && position.pixels <= position.minScrollExtent;
    final atTrailingEdge =
        velocity >= 0.0 && position.pixels >= position.maxScrollExtent;
    if (atLeadingEdge || atTrailingEdge) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    final target = _targetPixels(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(spring, position.pixels, target, velocity,
          tolerance: tolerance);
    }
    return null;
  }

  @override
  bool get allowImplicitScrolling => true;
}
