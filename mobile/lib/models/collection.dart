import '../services/locale_service.dart';
import 'media_item.dart';

/// Mirrors `Collection` in backend/app/schemas.py — a named shelf of real
/// titles from TMDB/IGDB/Open Library, e.g. "Top Anime" or "Premieres this week".
class SeenlyCollection {
  final String title;
  // English shelf name — set only for franchise shelves (see
  // backend/app/curated_franchises.py). Null for /feed/collections and
  // hand-picked teamira shelves, same as description below; use
  // [displayTitle] rather than [title] directly so those fall back
  // correctly.
  final String? titleEn;
  final List<MediaItem> items;
  // True only for franchise shelves from GET /feed/teamira (Star Wars,
  // Marvel, ...) — rendered as a full-width banner instead of the usual
  // horizontal poster row. Always false elsewhere.
  final bool isFranchise;
  // Short synopsis of the franchise as a whole (TMDB's own collection
  // overview — see backend/app/adapters/tmdb.py::collection). Only ever
  // set for franchise shelves; null everywhere else, including when TMDB
  // has no overview for that collection. Russian text — see
  // [descriptionRu] for the English one and use [displayDescription]
  // rather than either field directly.
  final String? description;
  final String? descriptionRu;
  // Deeper "how this franchise was made" text, from the franchise's own
  // Wikipedia article (see backend/app/adapters/wikipedia.py). Always
  // paired with [historyUrl] — Wikipedia's content is CC BY-SA, so
  // wherever this text is shown it must attribute + link back via that url.
  final String? history;
  final String? historyUrl;

  const SeenlyCollection({
    required this.title,
    this.titleEn,
    required this.items,
    this.isFranchise = false,
    this.description,
    this.descriptionRu,
    this.history,
    this.historyUrl,
  });

  /// `title` is always Russian (hand-written in curated_franchises.py, or
  /// the shelf name an admin typed). `titleEn` is only ever set alongside
  /// it for franchise shelves. Same fallback convention as
  /// LocalizedText.display: show the language the toggle asks for, fall
  /// back to whichever exists when it doesn't.
  String get displayTitle {
    if (LocaleService.contentPrefersRussian) return title;
    return (titleEn?.trim().isNotEmpty ?? false) ? titleEn! : title;
  }

  /// Same fallback convention, mirrored for `description`/`descriptionRu`
  /// (TMDB's franchise overview, which — unlike `title`/`history` above —
  /// really does come back in both languages from TMDB itself).
  String? get displayDescription {
    final preferRu = LocaleService.contentPrefersRussian;
    final primary = preferRu ? description : descriptionRu;
    final fallback = preferRu ? descriptionRu : description;
    if (primary?.trim().isNotEmpty ?? false) return primary;
    if (fallback?.trim().isNotEmpty ?? false) return fallback;
    return null;
  }

  factory SeenlyCollection.fromJson(Map<String, dynamic> json) =>
      SeenlyCollection(
        title: json['title'] as String,
        titleEn: json['title_en'] as String?,
        items: (json['items'] as List? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        isFranchise: json['is_franchise'] as bool? ?? false,
        description: json['description'] as String?,
        descriptionRu: json['description_ru'] as String?,
        history: json['history'] as String?,
        historyUrl: json['history_url'] as String?,
      );
}
