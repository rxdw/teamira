import 'package:flutter/material.dart';

import '../../models/watchlist_entry.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/series_episodes_sheet.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/watched_preview_sheet.dart';

/// Everything the person has marked watched in one category (movies,
/// series, anime, ...) — a plain 2-column poster grid, nothing fancier.
/// Opened by tapping a row in the Profile stats card (see
/// `_CategoryRow.onTap` in profile_screen.dart), so the list handed in
/// here is always the same `ProfileCollections.watched` slice already
/// loaded for that screen — no separate fetch.
class CategoryWatchedScreen extends StatelessWidget {
  final String label; // plural display label, e.g. "movies"
  final List<WatchlistEntry> entries;
  const CategoryWatchedScreen({super.key, required this.label, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Text(label, style: SeenlyText.screenTitle),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 0, 21, 6),
              child: Text('${entries.length} title${entries.length == 1 ? '' : 's'}',
                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text('nothing here yet',
                          style: SeenlyText.serif(italic: true, color: SeenlyPalette.placeholder)),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(21, 4, 21, 28),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 2 / 3,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final isSeries = e.mediaType == 'series' || e.mediaType == 'anime';
                        return ThemedPosterTile(
                          title: e.displayTitle,
                          posterUrl: e.posterUrl,
                          mediaType: e.mediaType,
                          fallbackColor: SeenlyPalette.gridColorFor(i),
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
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
