import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'section_header.dart';
import 'themed_poster_tile.dart';
import 'wow_motion.dart';
import '../services/app_translations.dart';

/// A swipeable "stack of tickets" carousel — the centered card sits tall
/// and upright, its neighbours peek out from behind it a little smaller,
/// a little lower, tilted just a few degrees either way. Replaces a flat
/// single-poster banner with something that invites a swipe, while
/// staying inside the app's warm paper/plum palette instead of borrowing
/// a colder, glossier streaming-app look.
///
/// Built for the collections hero specifically: [items] is the small set
/// of titles to feature (a handful is plenty — this isn't a full shelf),
/// and the year/rating caption underneath re-labels itself as the person
/// swipes, the same way the poster stack itself settles into place.
class HeroStackCarousel extends StatefulWidget {
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;
  final String overline;

  const HeroStackCarousel({
    super.key,
    required this.items,
    required this.onTap,
    this.overline = 'collection of the week',
  });

  @override
  State<HeroStackCarousel> createState() => _HeroStackCarouselState();
}

class _HeroStackCarouselState extends State<HeroStackCarousel> {
  late final PageController _controller;
  late double _page;
  // The card that opens centered — fixed once at mount, not recomputed
  // as [_page] moves with a swipe. Same reasoning as ShelfStackCarousel:
  // drives which side each tile enters from below.
  late final int _centerIndex;

  @override
  void initState() {
    super.initState();
    // Starting on card 0 left the whole peek-space on its left empty —
    // there's nothing there to peek. Starting one card in means the
    // first card already sits in that left peek slot, so the hero opens
    // with something visible on both sides instead of a blank gap.
    final initialPage = widget.items.length > 1 ? 1 : 0;
    _page = initialPage.toDouble();
    _centerIndex = initialPage;
    _controller = PageController(viewportFraction: 0.62, initialPage: initialPage);
    _controller.addListener(() {
      // A page controller doesn't have a page until it's attached to a
      // live PageView with a laid-out viewport; on the very first frame
      // that isn't true yet.
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
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          child: SectionHeader(
            title: widget.overline,
            centerTitle: true,
          ),
        ),
        SizedBox(
          height: 272,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            padEnds: true,
            itemBuilder: (context, i) {
              final delta = (_page - i).clamp(-1.0, 1.0);
              // Center card: full size, upright, floating just above the
              // paper. Either neighbour: a touch smaller, tipped a few
              // degrees away from center, sunk slightly so the active
              // card visibly overlaps in front of it.
              final scale = 1 - (delta.abs() * 0.16);
              final tilt = delta * 0.16; // radians, ~9° at full offset
              final lift = delta.abs() * 20;
              final item = widget.items[i];
              // Fixed, exact 2:3 footprint (176x264) rather than letting
              // the card stretch to fill the page's own width — the page
              // itself is wider than the card (that's what leaves room
              // for the neighbour to peek through), so sizing off the
              // page would distort every poster.
              Widget tile = Center(
                child: Transform.translate(
                  offset: Offset(0, lift),
                  child: Transform.rotate(
                    angle: tilt,
                    child: Transform.scale(
                      scale: scale,
                      child: PressScale(
                        // Deliberately not the default 0.96 — this card is
                        // already being scaled by the carousel's own
                        // `scale` transform above, so a second, smaller
                        // press-scale reads as tactile without visibly
                        // fighting the carousel's own sizing.
                        scaleTo: 0.98,
                        onTap: () {
                          if (i == activeIndex) {
                            widget.onTap(item);
                          } else {
                            _controller.animateToPage(
                              i,
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                        child: Container(
                          width: 176,
                          height: 264,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: SeenlyPalette.ink
                                    .withOpacity(0.10 + (1 - delta.abs()) * 0.08),
                                blurRadius: 22,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
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
              // Same left/right/center entrance as ShelfStackCarousel —
              // see the comment there.
              if (i != _centerIndex) {
                tile = HorizontalReveal(
                  slideBy: i < _centerIndex ? -56 : 56,
                  child: tile,
                );
              }
              return tile;
            },
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.08), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            // Same "no title, just year + rating" caption as
            // ShelfStackCarousel — see the comment there.
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
