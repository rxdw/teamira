import 'media_item.dart';

/// Mirrors `RatingsOut` — the community/critic layer (TMDB, plus
/// Kinopoisk and IMDb for Russian-language users — see
/// backend/app/adapters/poiskkino.py), not the user's own hearts.
/// tmdbRating/tmdbVotes can be null for a very obscure title TMDB has too
/// few votes on to mean much; the kp*/imdb* fields are null whenever the
/// backend wasn't asked for them (English users) or couldn't get them.
class MediaRatings {
  final double? tmdbRating;
  final int? tmdbVotes;
  final int? reviewsCount;
  final double? kpRating;
  final int? kpVotes;
  final double? imdbRating;
  final int? imdbVotes;

  /// Books only: Hardcover's community rating on its own 0–5 scale, how
  /// many people rated, and the book's page there (where its reviews live —
  /// their text isn't ours to show, see backend/app/adapters/hardcover.py).
  final double? hcRating;
  final int? hcVotes;
  final String? hcUrl;

  /// Games only: the share of positive Steam reviews (0–100, all languages)
  /// and how many reviews that is. Manga only: AniList's community mean on a
  /// 0–10 scale.
  final int? steamPct;
  final int? steamVotes;
  final double? alRating;

  const MediaRatings({
    this.tmdbRating,
    this.tmdbVotes,
    this.reviewsCount,
    this.kpRating,
    this.kpVotes,
    this.imdbRating,
    this.imdbVotes,
    this.hcRating,
    this.hcVotes,
    this.hcUrl,
    this.steamPct,
    this.steamVotes,
    this.alRating,
  });

  bool get isEmpty =>
      tmdbRating == null &&
      kpRating == null &&
      imdbRating == null &&
      hcRating == null &&
      steamPct == null &&
      alRating == null &&
      reviewsCount == null;

  factory MediaRatings.fromJson(Map<String, dynamic> json) => MediaRatings(
        tmdbRating: (json['tmdb_rating'] as num?)?.toDouble(),
        tmdbVotes: json['tmdb_votes'] as int?,
        reviewsCount: json['reviews_count'] as int?,
        kpRating: (json['kp_rating'] as num?)?.toDouble(),
        kpVotes: json['kp_votes'] as int?,
        imdbRating: (json['imdb_rating'] as num?)?.toDouble(),
        imdbVotes: json['imdb_votes'] as int?,
        hcRating: (json['hc_rating'] as num?)?.toDouble(),
        hcVotes: json['hc_votes'] as int?,
        hcUrl: json['hc_url'] as String?,
        steamPct: json['steam_pct'] as int?,
        steamVotes: json['steam_votes'] as int?,
        alRating: (json['al_rating'] as num?)?.toDouble(),
      );
}

/// Mirrors `TitleTrailer` — one YouTube-hosted video for this title's own
/// "trailers" shelf (distinct from `MediaItem.trailerYoutubeId`, which is
/// just the single best pick used elsewhere, e.g. Home's for-you feed).
class TitleTrailer {
  final String videoId;
  final String name;
  final String? thumbnailUrl;

  const TitleTrailer({
    required this.videoId,
    required this.name,
    this.thumbnailUrl,
  });

  factory TitleTrailer.fromJson(Map<String, dynamic> json) => TitleTrailer(
        videoId: json['video_id'] as String,
        name: json['name'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
      );
}

/// Mirrors `MediaDetailOut` — the response of GET /media/detail: the
/// enriched item, ratings (nullable), a short similar-titles shelf, and
/// this title's own trailers.
class MediaDetail {
  final MediaItem item;
  final MediaRatings? ratings;
  final List<MediaItem> similar;
  final List<TitleTrailer> trailers;
  // Required attribution text whenever item.cast/director, a ru
  // translation, or a ru poster came from TMDB — see backend
  // app/routers/media.py::_merge_tmdb_supplement. Null when nothing on
  // this item came from TMDB.
  final String? tmdbAttribution;

  const MediaDetail({
    required this.item,
    this.ratings,
    this.similar = const [],
    this.trailers = const [],
    this.tmdbAttribution,
  });

  factory MediaDetail.fromJson(Map<String, dynamic> json) => MediaDetail(
        item: MediaItem.fromJson(json['item'] as Map<String, dynamic>),
        ratings: json['ratings'] != null
            ? MediaRatings.fromJson(json['ratings'] as Map<String, dynamic>)
            : null,
        similar: (json['similar'] as List? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        trailers: (json['trailers'] as List? ?? const [])
            .map((e) => TitleTrailer.fromJson(e as Map<String, dynamic>))
            .toList(),
        tmdbAttribution: json['tmdb_attribution'] as String?,
      );
}
