import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'title_share.dart';

/// The [Hero] tag shared between a poster thumbnail and the lightbox it
/// opens into, so the artwork visibly grows into place instead of just
/// appearing. Keyed by item id so several posters on the same screen
/// (e.g. a "similar titles" shelf) never collide.
String posterHeroTag(String itemId) => 'poster-lightbox-$itemId';

/// One Hero tag per *tapped card*, not per title — the same title can
/// legitimately show up in more than one shelf at once on a screen like
/// Home (say, both "watching now" and a collection), and Flutter throws
/// if two Heroes share a tag while mounted in the same route
/// simultaneously. [scope] keeps shelves/screens from colliding with each
/// other; [source]+[id] keeps titles within one shelf from colliding with
/// themselves. This is what lets a poster fly from wherever it was
/// tapped into TitleDetailScreen's header tile (via
/// [TitleDetailScreen.heroTag]) — or into another screen's own matching
/// Hero, like TrailerReelsScreen's cards — instead of a hard cut.
String scopedPosterHeroTag(String scope, String source, String id) =>
    'poster-hero-$scope-$source-$id';

/// Opens the poster large, over a softly blurred and dimmed version of
/// whatever screen was already showing — a quiet, gallery-like moment
/// rather than a hard navigation. Dismiss by tapping outside the poster,
/// the close button, or dragging the poster down.
Future<void> showPosterLightbox(
  BuildContext context, {
  required MediaItem item,
  required MediaRatings? ratings,
  // Lets a caller that already put this poster in a Hero of its own
  // (e.g. TitleDetailScreen's header, which may itself be flying in from
  // Home under a per-navigation tag) keep that exact tag flowing into the
  // lightbox, so the two Heroes describe one continuous flight instead of
  // the lightbox silently falling back to its own. Defaults to the
  // original item-id-keyed tag for any caller that doesn't care.
  String? heroTag,
}) {
  final tag = heroTag ?? posterHeroTag(item.id);
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _PosterLightbox(item: item, ratings: ratings, animation: animation, heroTag: tag);
      },
    ),
  );
}

class _PosterLightbox extends StatelessWidget {
  final MediaItem item;
  final MediaRatings? ratings;
  final Animation<double> animation;
  final String heroTag;

  const _PosterLightbox({
    required this.item,
    required this.ratings,
    required this.animation,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            // The rest of the app, softly blurred and dimmed behind the
            // poster — grows in with the same curve as everything else
            // so the whole thing reads as one gesture rather than a
            // backdrop that pops in a beat before the content does.
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22 * t, sigmaY: 22 * t),
                child: Container(color: SeenlyPalette.ink.withOpacity(0.62 * t)),
              ),
            ),
            child!,
          ],
        );
      },
      child: _LightboxContent(item: item, ratings: ratings, animation: curved, heroTag: heroTag),
    );
  }
}

class _LightboxContent extends StatefulWidget {
  final MediaItem item;
  final MediaRatings? ratings;
  final Animation<double> animation;
  final String heroTag;

  const _LightboxContent({
    required this.item,
    required this.ratings,
    required this.animation,
    required this.heroTag,
  });

  @override
  State<_LightboxContent> createState() => _LightboxContentState();
}

class _LightboxContentState extends State<_LightboxContent> {
  // How far the poster's been dragged down, and how far a downward
  // drag needs to travel before letting go counts as "dismiss" rather
  // than "snap back" — a swipe-to-close on top of the tap/button ones,
  // since that's the natural gesture once something's full-screen.
  double _dragDy = 0;
  static const double _dismissThreshold = 120;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _dragDy = (_dragDy + details.delta.dy).clamp(0, 400));
  }

  void _onDragEnd(DragEndDetails details) {
    final flungDown = details.velocity.pixelsPerSecond.dy > 600;
    if (_dragDy > _dismissThreshold || flungDown) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _dragDy = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ratings = widget.ratings;
    final media = MediaQuery.of(context);
    final posterWidth = (media.size.width * 0.66).clamp(0.0, 300.0);
    final posterHeight = posterWidth * 3 / 2;
    // The drag fades and shrinks the poster a touch as it travels, so
    // letting go mid-gesture feels continuous instead of the poster
    // snapping between two fixed states.
    final dragProgress = (_dragDy / (_dismissThreshold * 2)).clamp(0.0, 1.0);

    return SafeArea(
      child: AnimatedBuilder(
        animation: widget.animation,
        builder: (context, _) {
          final t = widget.animation.value;
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 24),
              child: Stack(
                children: [
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, _dragDy),
                      child: Opacity(
                        opacity: 1 - dragProgress * 0.5,
                        child: GestureDetector(
                          onVerticalDragUpdate: _onDragUpdate,
                          onVerticalDragEnd: _onDragEnd,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Hero(
                                tag: widget.heroTag,
                                child: Material(
                                  color: Colors.transparent,
                                  child: Container(
                                    width: posterWidth,
                                    height: posterHeight,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.35),
                                          blurRadius: 40,
                                          offset: const Offset(0, 18),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: item.posterUrl != null
                                          ? Image.network(
                                              item.posterUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                color: SeenlyPalette.mediaColor(item.mediaType),
                                              ),
                                            )
                                          : Container(color: SeenlyPalette.mediaColor(item.mediaType)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  item.title.display,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: SeenlyText.serif(
                                    size: 21,
                                    weight: FontWeight.w600,
                                    color: SeenlyPalette.paper,
                                  ),
                                ),
                              ),
                              if (item.year != null || item.runtimeMinutes != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  [
                                    if (item.year != null) '${item.year}',
                                    if (item.runtimeMinutes != null && item.mediaType != 'book')
                                      '${item.runtimeMinutes} мин',
                                  ].join('  ·  '),
                                  style: SeenlyText.mono(
                                    size: 13,
                                    color: SeenlyPalette.paper.withOpacity(0.7),
                                  ),
                                ),
                              ],
                              if (ratings?.tmdbRating != null) ...[
                                const SizedBox(height: 16),
                                _RatingPill(rating: ratings!.tmdbRating!, votes: ratings.tmdbVotes),
                              ],
                              // Sits below the whole poster block — title,
                              // meta, and rating all included — rather than
                              // as an icon crowding the close button up
                              // top, so it reads as the natural next step
                              // once you've taken the poster in.
                              const SizedBox(height: 22),
                              _ShareThisTitleButton(
                                onTap: () => shareTitle(
                                  context,
                                  item: item,
                                  fallbackColor: SeenlyPalette.mediaColor(item.mediaType),
                                  ratings: ratings,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 12,
                    child: _LightboxIconButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A soft, glowing little badge for the community rating — warmer and
/// more celebratory than a plain number, so it reads as "people loved
/// this" rather than just another stat.
class _RatingPill extends StatelessWidget {
  final double rating;
  final int? votes;
  const _RatingPill({required this.rating, this.votes});

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.ratingColor(rating.round());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.22),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            rating.toStringAsFixed(1),
            style: SeenlyText.serif(size: 15, weight: FontWeight.w700, color: SeenlyPalette.paper),
          ),
          if (votes != null) ...[
            const SizedBox(width: 6),
            Text(
              '· $votes',
              style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.65)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The soft "share this title" pill below the poster — glassy and quiet
/// like the rest of the lightbox's chrome, rather than a hard-edged icon
/// button, since sharing here is an invitation ("look what I found"),
/// not a utility action to get out of the way.
class _ShareThisTitleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ShareThisTitleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper.withOpacity(0.14),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: SeenlyPalette.paper.withOpacity(0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ios_share_rounded, size: 16, color: SeenlyPalette.paper),
            const SizedBox(width: 8),
            Text(
              'share this title',
              style: SeenlyText.mono(
                size: 13,
                color: SeenlyPalette.paper,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small glassy circle the close action uses.
class _LightboxIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _LightboxIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: SeenlyPalette.ink.withOpacity(0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}
