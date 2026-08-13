import 'media_item.dart' show CastMember;

/// Mirrors `DiaryEntryOut` in backend/app/schemas.py — one row per logged
/// evening for movies/games/books/etc, including rewatches. A series is
/// the one exception: it only ever has a single row, created on its first
/// log and updated in place after that (see the backend model's own doc
/// comment) — so `season`/`episode` are the *latest* point reached, not
/// "the episode this row represents". Backs the Diary tab (grouped by
/// date) and the "your evenings with this film" timeline on the title
/// screen.
class DiaryEntry {
  final String id;
  final String mediaId;
  final String mediaType;
  final String source;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  // Wide still/fanart image, same field WatchlistEntry carries (see
  // WatchlistEntry.backdropUrl) — used for the Home "on this day" card's
  // wide banner instead of stretching the vertical poster. Null on rows
  // logged before this shipped, or from a source with no backdrop on
  // file; callers fall back to posterUrl.
  final String? backdropUrl;
  // Set only on a series' single row — see the class doc comment. Both
  // null for movies/games/books/etc.
  final int? season;
  final int? episode;
  // Running count of watched episodes — only set alongside season/episode,
  // for showing "N episodes watched" without a second fetch.
  final int? episodesWatched;
  final int? rating; // hearts, 1-10
  final String? note;
  final List<String> moodTags; // free-form vibe tags, e.g. "cozy night in", "background noise"
  // Up to 3 cast members picked as this evening's standouts — see the
  // themed log flows' "who did you love most tonight?" step. Empty when
  // that step was skipped (or predates this feature).
  final List<CastMember> favoriteCast;
  final String? watchedWithUsername; // set when logged as watched with the linked partner
  final bool isRewatch;
  final DateTime watchedAt;
  final DateTime createdAt;

  const DiaryEntry({
    required this.id,
    required this.mediaId,
    required this.mediaType,
    required this.source,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
    this.backdropUrl,
    this.season,
    this.episode,
    this.episodesWatched,
    this.rating,
    this.note,
    this.moodTags = const [],
    this.favoriteCast = const [],
    this.watchedWithUsername,
    required this.isRewatch,
    required this.watchedAt,
    required this.createdAt,
  });

  /// True when this row is one episode of a series rather than a whole
  /// title — see the class doc comment.
  bool get isEpisodeEntry => season != null && episode != null;

  String get displayTitle =>
      (titleEn?.trim().isNotEmpty ?? false) ? titleEn! : (titleRu ?? '—');

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
        id: json['id'] as String,
        mediaId: json['media_id'] as String,
        mediaType: json['media_type'] as String,
        source: json['source'] as String,
        titleRu: json['title_ru'] as String?,
        titleEn: json['title_en'] as String?,
        posterUrl: json['poster_url'] as String?,
        backdropUrl: json['backdrop_url'] as String?,
        season: json['season'] as int?,
        episode: json['episode'] as int?,
        episodesWatched: json['episodes_watched'] as int?,
        rating: json['rating'] as int?,
        note: json['note'] as String?,
        moodTags: (json['mood_tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        favoriteCast: (json['favorite_cast'] as List<dynamic>?)
                ?.map((e) => CastMember.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        watchedWithUsername: json['watched_with_username'] as String?,
        isRewatch: json['is_rewatch'] as bool? ?? false,
        watchedAt: DateTime.parse(json['watched_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
