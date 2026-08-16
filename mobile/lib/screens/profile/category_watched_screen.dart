import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/watchlist_entry.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/mosaic_poster_grid.dart';
import '../../widgets/series_episodes_sheet.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/watched_preview_sheet.dart';
import '../../widgets/wow_motion.dart' show BannerReveal;
import '../../services/app_translations.dart';

/// Everything the person has marked watched in one category (movies,
/// series, anime, ...) — opened by tapping a row in the Profile stats
/// card (see `_CategoryRow.onTap` in profile_screen.dart), so the list
/// handed in here is always the same `ProfileCollections.watched` slice
/// already loaded for that screen — no separate fetch.
///
/// Same mosaic/tilt/parallax treatment as a collection's own full-shelf
/// screen (see collection_full_screen.dart's _MosaicGrid / TiltPosterTile
/// / ParallaxPoster, shared via widgets/mosaic_poster_grid.dart), plus a
/// large hero-style title up top — this screen is otherwise the closest
/// thing Profile has to that same "one shelf, in full" moment. No
/// shuffle button here though: unlike an editorial collection, this
/// list's order already means something (however it was handed in), so
/// there's nothing to reshuffle for the sake of it.
class CategoryWatchedScreen extends StatelessWidget {
  final String label; // plural display label, e.g. "movies"
  final List<WatchlistEntry> entries;
  const CategoryWatchedScreen({super.key, required this.label, required this.entries});

  @override
  Widget build(BuildContext context) {
    final order = List.generate(entries.length, (i) => i);
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 20, 0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(21, 4, 21, 18),
              sliver: SliverToBoxAdapter(
                child: BannerReveal(
                  from: -12,
                  duration: const Duration(milliseconds: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: SeenlyText.serif(size: 34, weight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('${entries.length} title${entries.length == 1 ? '' : 's'}',
                          style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
                    ],
                  ),
                ),
              ),
            ),
            if (entries.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('nothing here yet'.tr,
                        style: SeenlyText.serif(italic: true, color: SeenlyPalette.placeholder)),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 0, 21, 28),
                sliver: SliverToBoxAdapter(
                  child: MosaicPosterGrid(
                    itemCount: entries.length,
                    order: order,
                    revealGen: 0,
                    keyOf: (i) => entries[i].id,
                    tileBuilder: (context, i, gridIndex, aspect) {
                      final e = entries[i];
                      final isSeries = e.mediaType == 'series' || e.mediaType == 'anime';
                      return TiltPosterTile(
                        onTap: () => isSeries
                            ? showSeriesEpisodesSheet(
                                context,
                                mediaId: e.mediaId,
                                source: e.source,
                                title: e.displayTitle,
                                mediaType: e.mediaType,
                                posterUrl: e.posterUrl,
                              )
                            : showWatchedPreview(context, WatchedPreviewData.fromWatchlistEntry(e)),
                        onLongPress: () => _shareEntry(e),
                        child: MosaicParallaxPoster(
                          builder: (parallax) => ThemedPosterTile(
                            title: e.displayTitle,
                            posterUrl: e.posterUrl,
                            mediaType: e.mediaType,
                            fallbackColor: SeenlyPalette.gridColorFor(i),
                            aspectRatio: aspect,
                            parallax: parallax,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Long-press action for a shelf tile built from a [WatchlistEntry]
/// rather than a full MediaItem (see collection_full_screen.dart's own
/// `_shareMediaItem`, which links out to IMDb/TMDB) — no external ids on
/// this shape, so this is title + year only, the same fallback that
/// screen itself uses when a title has neither id to link to.
void _shareEntry(WatchlistEntry e) {
  final bits = [
    e.displayTitle,
    if (e.year != null) '(${e.year})',
  ].join(' ');
  Share.share(bits);
}
