import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// A calm, poster-backed preview card for Home's "for you" trailer shelf.
///
/// Deliberately *not* an autoplaying video here — several of these sit
/// side by side in a horizontal row, and starting several muted players at
/// once the moment Home loads is exactly the "reels feed" feel the rest of
/// this screen is trying to avoid (see the design discussion this shelf
/// came out of: cozy paper aesthetic, not TikTok). Tapping this card opens
/// [TrailerReelScreen] at this item, which is where the real, single,
/// sound-on playback happens — one video at a time, only once someone has
/// actually asked to watch.
class TrailerPreviewCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final double width;
  // Lets the caller (Home) hand this card a Hero tag that the destination
  // screen's matching card uses too, so the poster visibly flies into the
  // trailer feed instead of the two screens hard-cutting. Null keeps this
  // a plain image, for any caller that doesn't set one up.
  final String? heroTag;

  const TrailerPreviewCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 132,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrailer = (item.trailerYoutubeId ?? '').isNotEmpty;
    final tag = heroTag;
    final posterImage = item.posterUrl != null
        ? Image.network(item.posterUrl!, fit: BoxFit.cover)
        : null;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: SeenlyPalette.mediaColor(item.mediaType),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: SeenlyPalette.softShadow,
                ),
                child: Stack(
                  children: [
                    if (posterImage != null)
                      Positioned.fill(
                        child: tag == null ? posterImage : Hero(tag: tag, child: posterImage),
                      ),
                    // A soft warm veil, just enough to keep the play chip
                    // and title readable over any poster.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.5, 1],
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.55),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (hasTrailer)
                      Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: SeenlyPalette.paper.withOpacity(0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              size: 22, color: SeenlyPalette.accent),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 9,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title.display,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.serif(
                                italic: true, size: 12.5, color: SeenlyPalette.paper),
                          ),
                          if (item.year != null || item.genres.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (item.year != null) '${item.year}',
                                if (item.genres.isNotEmpty) item.genres.first,
                              ].join(' · '),
                              style: SeenlyText.mono(
                                  size: 8.5, color: SeenlyPalette.paper.withOpacity(0.8)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
