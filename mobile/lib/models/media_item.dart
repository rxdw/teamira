import '../services/locale_service.dart';
import 'watchlist_entry.dart';

/// Mirrors `ExternalIds` in backend/app/schemas.py.
class ExternalIds {
  final String? tmdb;
  final String? imdb;

  const ExternalIds({this.tmdb, this.imdb});

  factory ExternalIds.fromJson(Map<String, dynamic> json) => ExternalIds(
        tmdb: json['tmdb'] as String?,
        imdb: json['imdb'] as String?,
      );

  Map<String, dynamic> toJson() => {'tmdb': tmdb, 'imdb': imdb};
}

/// Mirrors `LocalizedText` in backend/app/schemas.py.
class LocalizedText {
  final String? ru;
  final String? en;

  const LocalizedText({this.ru, this.en});

  /// The UI never shows an empty string — it always falls back to
  /// whichever language actually has content. Which one is tried first
  /// follows the device's content-language setting (see
  /// services/locale_service.dart) — English by default, Russian if the
  /// person turned it on in Settings and TMDB actually had a translation
  /// for this title.
  String get display {
    final preferRu = LocaleService.contentPrefersRussian;
    final primary = preferRu ? ru : en;
    final fallback = preferRu ? en : ru;
    if (primary?.trim().isNotEmpty ?? false) return primary!;
    if (fallback?.trim().isNotEmpty ?? false) return fallback!;
    return '—';
  }

  factory LocalizedText.fromJson(Map<String, dynamic> json) => LocalizedText(
        ru: json['ru'] as String?,
        en: json['en'] as String?,
      );

  Map<String, dynamic> toJson() => {'ru': ru, 'en': en};
}

/// Mirrors `CastMember` in backend/app/schemas.py — sourced from TMDB, see
/// app/adapters/tmdb.py::full_detail.
class CastMember {
  // TMDB's own person id — powers tapping this cast member to open their
  // filmography (see MediaService.fetchPerson / PersonDetailScreen). Null
  // only for a row cached before this field existed.
  final String? personId;
  final String name;
  // Unlike `name` above, TMDB translates the role a person played per
  // request language ("Tony Stark" vs "Тони Старк") — so this follows
  // the same LocalizedText().display convention as title/description,
  // not a plain string.
  final LocalizedText? character;
  final String? photoUrl;

  const CastMember({this.personId, required this.name, this.character, this.photoUrl});

  factory CastMember.fromJson(Map<String, dynamic> json) => CastMember(
        personId: json['person_id'] as String?,
        name: json['name'] as String,
        character: json['character'] == null
            ? null
            : LocalizedText.fromJson(json['character'] as Map<String, dynamic>),
        photoUrl: json['photo_url'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'person_id': personId, 'name': name, 'character': character?.toJson(), 'photo_url': photoUrl};
}

/// Mirrors `MediaItem` in backend/app/schemas.py — the shared shape every
/// adapter (TMDB, IGDB, mock games) returns, and the shape the client sends
/// back when logging a diary entry or reacting to the feed.
class MediaItem {
  final String id;
  final String mediaType; // "movie" | "series" | "game" | "book"
  final ExternalIds externalIds;
  final LocalizedText title;
  final LocalizedText description;
  final String? _posterUrlBase; // the source's own poster (English/international)
  // TMDB's Russian-localized poster, when TMDB actually has one for this
  // title (see backend app/adapters/tmdb.py::full_detail) — populated
  // only by GET /media/detail, same as cast/director below. Most titles
  // won't have one; that's ordinary, not an error.
  final String? posterUrlRu;
  final String? backdropUrl;
  final int? year;
  final List<String> genres;
  final double? rating; // source's score (TMDB/IMDb-style)
  final String source; // "tmdb" | "igdb"

  // Populated only by MediaService.detail() (GET /media/detail) — every
  // search/feed/collections-sourced MediaItem leaves these null.
  final String? tagline;
  final int? runtimeMinutes;
  final String? certification;
  final String? releaseDate;
  final String? status;
  final String? country;
  final bool? hasTrailer;

  // Populated only by FeedService.forYou() (GET /feed/for-you) — a YouTube
  // video id for this title's trailer. Null everywhere else, and even
  // within for-you whenever TMDB has nothing for this title.
  final String? trailerYoutubeId;

  // Populated only by MediaService.detail() (GET /media/detail), from
  // TMDB — see backend app/adapters/tmdb.py::title_supplement. Empty/null
  // whenever there's no tmdb id or TMDB has nothing, same as everything
  // else TMDB-sourced on this model.
  final List<CastMember> cast;
  final String? director;
  // TMDB person id of the first credited director — lets the director's
  // name in _CastSection (title_detail_screen.dart) open PersonDetailScreen
  // the same way a cast member's does (see CastMember.personId above).
  // Null whenever [director] itself is null, or on the rarer case of a
  // director TMDB has no person id for.
  final String? directorId;

  /// The poster every screen actually renders. Prefers [posterUrlRu] when
  /// the device is set to Russian (services/locale_service.dart) and TMDB
  /// actually had a Russian poster for this title; falls back to the base
  /// poster otherwise. A getter rather than a stored field on purpose — the
  /// ~25 call sites across the app that already read `.posterUrl` pick this
  /// up automatically, no plumbing needed (same reasoning as
  /// LocalizedText.display above).
  String? get posterUrl =>
      (LocaleService.contentPrefersRussian && (posterUrlRu?.trim().isNotEmpty ?? false))
          ? posterUrlRu
          : _posterUrlBase;

  /// The non-Russian poster, even when [posterUrl] above is currently
  /// showing the Russian one — used as a load-failure fallback (see
  /// _ResilientPoster in title_detail_screen.dart) so a broken/expired
  /// TMDB image URL degrades to the poster that was already working
  /// instead of a blank tile.
  String? get posterUrlFallback => _posterUrlBase;

  const MediaItem({
    required this.id,
    required this.mediaType,
    required this.externalIds,
    required this.title,
    required this.description,
    String? posterUrl,
    this.posterUrlRu,
    this.backdropUrl,
    this.year,
    this.genres = const [],
    this.rating,
    required this.source,
    this.tagline,
    this.runtimeMinutes,
    this.certification,
    this.releaseDate,
    this.status,
    this.country,
    this.hasTrailer,
    this.trailerYoutubeId,
    this.cast = const [],
    this.director,
    this.directorId,
  }) : _posterUrlBase = posterUrl;

  /// Builds just enough of a MediaItem to round-trip through
  /// POST /profile/favorites/toggle for a title that's already on one of
  /// this account's shelves (see ProfileService.toggleFavorite and the
  /// "add favorites" picker in screens/profile/favorite_add_screen.dart).
  /// The backend only reads these fields when it has to *create* a fresh
  /// WatchlistEntry — for a title that's already on a shelf (always true
  /// here, since it came from one) it only flips `is_favorite` on the
  /// existing row, so external_ids/description are safe to leave empty.
  factory MediaItem.fromWatchlistEntry(WatchlistEntry e) => MediaItem(
        id: e.mediaId,
        mediaType: e.mediaType,
        externalIds: const ExternalIds(),
        title: LocalizedText(ru: e.titleRu, en: e.titleEn),
        description: const LocalizedText(),
        posterUrl: e.posterUrl,
        year: e.year,
        genres: e.genres,
        rating: e.rating,
        source: e.source,
      );

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'] as String,
        mediaType: json['media_type'] as String,
        externalIds: ExternalIds.fromJson(
            (json['external_ids'] as Map<String, dynamic>?) ?? const {}),
        title: LocalizedText.fromJson(
            (json['title'] as Map<String, dynamic>?) ?? const {}),
        description: LocalizedText.fromJson(
            (json['description'] as Map<String, dynamic>?) ?? const {}),
        posterUrl: json['poster_url'] as String?,
        posterUrlRu: json['poster_url_ru'] as String?,
        backdropUrl: json['backdrop_url'] as String?,
        year: json['year'] as int?,
        genres: (json['genres'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        rating: (json['rating'] as num?)?.toDouble(),
        source: json['source'] as String,
        tagline: json['tagline'] as String?,
        runtimeMinutes: json['runtime_minutes'] as int?,
        certification: json['certification'] as String?,
        releaseDate: json['release_date'] as String?,
        status: json['status'] as String?,
        country: json['country'] as String?,
        hasTrailer: json['has_trailer'] as bool?,
        trailerYoutubeId: json['trailer_youtube_id'] as String?,
        cast: (json['cast'] as List? ?? const [])
            .map((e) => CastMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        director: json['director'] as String?,
        directorId: json['director_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'media_type': mediaType,
        'external_ids': externalIds.toJson(),
        'title': title.toJson(),
        'description': description.toJson(),
        'poster_url': _posterUrlBase,
        'backdrop_url': backdropUrl,
        'year': year,
        'genres': genres,
        'rating': rating,
        'source': source,
        // Everything else on this model only ever gets *read* off a
        // server response (detail/search/etc.) — omitted here the same
        // way it always has been. runtime_minutes is the one exception:
        // "your sources" (SourcesService/ImportService) sets it straight
        // from the YouTube/Twitch adapter at preview time, and it needs
        // to survive the round trip back to POST /import/commit so a
        // video/VOD's real length reaches WatchlistEntry.runtime_minutes
        // (see backend/app/routers/imports.py::commit_import) instead of
        // silently dropping out and undercounting Wrapped's hour totals.
        'runtime_minutes': runtimeMinutes,
      };
}
