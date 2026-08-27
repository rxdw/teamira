import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/collection.dart';
import '../models/media_item.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../screens/trailers/trailer_reels_screen.dart';
import '../services/app_translations.dart';
import '../services/locale_service.dart';

/// "about this franchise / how it was made" — opened from a small pill on
/// [CollectionFullScreen] for franchise shelves only.
///
/// Everything here comes straight off the same [SeenlyCollection] the
/// grid already has, no extra fetch:
/// - `displayDescription` is TMDB's own synopsis for the collection (see
///   backend/app/adapters/tmdb.py::collection) — nothing hand-written,
///   and already follows the language toggle (English/Russian, whichever
///   TMDB actually had a translation for).
/// - `history` is hand-written production/creation text from
///   backend/app/curated_franchises.py — not fetched from anywhere
///   (used to come from Wikipedia; dropped that). `historyUrl` is
///   always null now, so the "читать полностью" link just doesn't
///   render — see the `historyUrl != null` check below.
/// - the trailer pill opens [TrailerReelsScreen] on just the movies in
///   this franchise that actually have one, same YouTube lookup (per
///   movie) and same external-open behaviour as the rest of the app
///   already uses for trailers.
/// (There used to also be a numbered "watch order" list of every item in
/// the collection here; removed on request — the shelf grid itself
/// already shows the same items.)
Future<void> showFranchiseInfoSheet(BuildContext context, SeenlyCollection collection) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _FranchiseInfoSheet(collection: collection),
  );
}

class _FranchiseInfoSheet extends StatelessWidget {
  final SeenlyCollection collection;
  const _FranchiseInfoSheet({required this.collection});

  List<MediaItem> get _itemsWithTrailers => collection.items
      .where((item) => (item.trailerYoutubeId ?? '').isNotEmpty)
      .toList();

  void _openTrailers(BuildContext context, {required int aroundItemIndex}) {
    final withTrailers = _itemsWithTrailers;
    if (withTrailers.isEmpty) return;
    final target = collection.items[aroundItemIndex];
    final startIndex = withTrailers.indexWhere((i) => i.id == target.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrailerReelsScreen(
          items: withTrailers,
          initialIndex: startIndex < 0 ? 0 : startIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final description = collection.displayDescription?.trim();
    final history = collection.history?.trim();
    final trailerCount = _itemsWithTrailers.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.dashedBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(collection.displayTitle, style: SeenlyText.serif(italic: true, size: 19)),
              const SizedBox(height: 2),
              Text('о франшизе и как она создавалась'.tr,
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
              const SizedBox(height: 18),

              if (description != null && description.isNotEmpty) ...[
                Text(description,
                    style: SeenlyText.serif(size: 13.5).copyWith(height: 1.5)),
                const SizedBox(height: 22),
              ],

              if (trailerCount > 0) ...[
                GestureDetector(
                  onTap: () => _openTrailers(context, aroundItemIndex: 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.play_circle_fill, size: 20, color: SeenlyPalette.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            trailerCount == 1
                                ? 'смотреть трейлер'.tr
                                : (LocaleService.appIsRussian
                                    ? 'смотреть трейлеры ($trailerCount)'
                                    : 'watch trailers ($trailerCount)'),
                            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.accent),
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 16, color: SeenlyPalette.accent),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
              ],

              if (history != null && history.isNotEmpty) ...[
                Text('как создавалась франшиза'.tr, style: SeenlyText.sectionTitle),
                const SizedBox(height: 10),
                Text(history, style: SeenlyText.serif(size: 13.5).copyWith(height: 1.5)),
                const SizedBox(height: 8),
                if (collection.historyUrl != null)
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse(collection.historyUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text('читать полностью на Wikipedia →'.tr,
                        style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
                  ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        );
      },
    );
  }
}
