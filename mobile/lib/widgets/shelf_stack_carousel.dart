import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'themed_poster_tile.dart';
import 'wow_motion.dart';
import '../services/app_translations.dart';

/// The same "peeking stack of tickets" feeling as [HeroStackCarousel], just
/// sized to live inline inside an ordinary collection shelf rather than sit
/// as a full-width hero. Every shelf on the Collections screen used to be a
/// flat [ListView] of same-size posters — this replaces that with a small
/// swipeable stack: the centered card sits a little taller and upright,
/// its neighbours peek out smaller, tipped a few degrees, tucked slightly
/// behind. A soft one-line caption underneath re-labels itself as the
/// centered card changes.
class ShelfStackCarousel extends StatefulWidget {
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;

  const ShelfStackCarousel({super.key, required this.items, required this.onTap});

  @override
  State<ShelfStackCarousel> createState() => _ShelfStackCarouselState();
}

class _ShelfStackCarouselState extends State<ShelfStackCarousel> {
  late final PageController _controller;
  late double _page;
  // The card that opens centered — fixed once at mount, not recomputed
  // as [_page] moves with a swipe. Drives which side each tile enters
  // from (see itemBuilder below): whatever started left of center
  // slides in from the left, whatever started right of it slides in
  // from the right, and center itself just sits there already in
  // place. Recomputing this off the live page would mean a tile's
  // entrance direction kept flip-flopping mid-swipe, which isn't the
  // point — it's about where the shelf *opened*, not where the person
  // has scrolled it to since.
  late final int _centerIndex;

  @override
  void initState() {
    super.initState();
    // Starting on card 0 left the whole peek-space on its left empty —
    // there's nothing there to peek. Starting one card in means the
    // first card already sits in that left peek slot, so the shelf opens
    // with something visible on both sides instead of a blank gap.
    final initialPage = widget.items.length > 1 ? 1 : 0;
    _page = initialPage.toDouble();
    _centerIndex = initialPage;
    _controller = PageController(viewportFraction: 0.34, initialPage: initialPage);
    _controller.addListener(() {
      // Same guard as HeroStackCarousel: no `.page` until the PageView
      // this controller is attached to has actually been laid out.
      if (!_controller.hasClients || _controller.page == null) return;
      setState(() => _page = _controller.page!);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final activeIndex = _page.round().clamp(0, widget.items.length - 1);
    final active = widget.items[activeIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 208,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            padEnds: true,
            itemBuilder: (context, i) {
              final delta = (_page - i).clamp(-1.0, 1.0);
              final scale = 1 - (delta.abs() * 0.15);
              final tilt = delta * 0.11; // radians — a gentle tip, not a spin
              final lift = delta.abs() * 13;
              final item = widget.items[i];
              Widget tile = Center(
                child: Transform.translate(
                  offset: Offset(0, lift),
                  child: Transform.rotate(
                    angle: tilt,
                    child: Transform.scale(
                      scale: scale,
                      child: PressScale(
                        // Same reasoning as HeroStackCarousel — a smaller
                        // press-scale on top of the carousel's own scale
                        // transform reads as tactile without fighting it.
                        scaleTo: 0.98,
                        onTap: () {
                          if (i == activeIndex) {
                            widget.onTap(item);
                          } else {
                            _controller.animateToPage(
                              i,
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                        child: Container(
                          width: 118,
                          height: 177,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: SeenlyPalette.ink
                                    .withOpacity(0.08 + (1 - delta.abs()) * 0.07),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: ThemedPosterTile(
                              title: item.title.display,
                              posterUrl: item.posterUrl,
                              mediaType: item.mediaType,
                              fallbackColor: SeenlyPalette.gridColorFor(i),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              // Peeking neighbours settle in from whichever side they
              // opened on — left peek slides in from the left, right
              // peek from the right — while the card that opened
              // centered is left completely alone, no animation at all.
              // Mirrors HorizontalReveal's own scroll-triggered rhythm
              // (via the ambient RevealPulse from the ScrollReveal this
              // whole shelf lives in), just direction-aware instead of
              // always from the right.
              if (i != _centerIndex) {
                tile = HorizontalReveal(
                  slideBy: i < _centerIndex ? -42 : 42,
                  child: tile,
                );
              }
              return tile;
            },
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            // Deliberately no title here — the poster already carries it,
            // and at the same weight/size as the shelf's own header
            // ("Thriller", "Romance", ...) it read as a second heading
            // stacked right underneath the first. Just year + rating,
            // centered under the focused card rather than spanning the
            // full shelf width, so it reads as that card's own caption.
            child: Row(
              key: ValueKey(active.id),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active.year != null)
                  Text('${active.year}',
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                if (active.year != null && active.rating != null) ...[
                  const SizedBox(width: 8),
                  Text('·'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                  const SizedBox(width: 8),
                ],
                if (active.rating != null) ...[
                  const Icon(Icons.star_rounded, size: 12, color: SeenlyPalette.mustard),
                  const SizedBox(width: 2),
                  Text(active.rating!.toStringAsFixed(1),
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
