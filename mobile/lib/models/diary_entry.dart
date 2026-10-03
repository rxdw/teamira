import 'media_item.dart' show CastMember;
import 'sincerity.dart' show SincerityTransaction;
import '../utils/server_time.dart';
import '../utils/unset.dart';

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
  // Only ever non-null right after POST/PATCH /diary, on the exact
  // response that triggered it — see DiaryEntryOut.sincerity_awarded's
  // own docstring on the backend. Every other place a DiaryEntry gets
  // built from JSON (GET /diary, etc.) simply won't have this key.
  final List<SincerityTransaction> sincerityAwarded;

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
    this.sincerityAwarded = const [],
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
        createdAt: parseServerUtc(json['created_at'] as String),
        sincerityAwarded: (json['sincerity_awarded'] as List<dynamic>?)
                ?.map((e) => SincerityTransaction.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  /// Mirrors [fromJson] — added for the on-device diary cache (see
  /// `services/local_json_cache.dart`), not for talking to the backend.
  /// `sincerityAwarded` round-trips too even though it's normally only
  /// ever set right after a POST/PATCH response — harmless to keep
  /// around in the cache, and simpler than special-casing it here.
  Map<String, dynamic> toJson() => {
        'id': id,
        'media_id': mediaId,
        'media_type': mediaType,
        'source': source,
        'title_ru': titleRu,
        'title_en': titleEn,
        'poster_url': posterUrl,
        'backdrop_url': backdropUrl,
        'season': season,
        'episode': episode,
        'episodes_watched': episodesWatched,
        'rating': rating,
        'note': note,
        'mood_tags': moodTags,
        'favorite_cast': favoriteCast.map((c) => c.toJson()).toList(),
        'watched_with_username': watchedWithUsername,
        'is_rewatch': isRewatch,
        'watched_at': watchedAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'sincerity_awarded': sincerityAwarded.map((s) => s.toJson()).toList(),
      };

  /// Sentinel default, aliased to the one shared sentinel in
  /// utils/unset.dart — same trick and same reasoning as
  /// `DiaryService.updateEntry`'s own `_unset`, and needs to be
  /// `identical()` to it (and to DiaryRepository's and DiaryStore's) now
  /// that a caller's "leave this alone" has to survive being forwarded
  /// through those layers to reach this method. See that file's doc
  /// comment for why a fresh `const Object()` here wouldn't do that.
  static const Object _unset = unset;

  /// Applies the same set of fields [DiaryService.updateEntry] can send,
  /// locally and instantly — used by [DiaryStore.updateEntry] for the
  /// optimistic-update path (see Фаза 2.15.3 in the launch plan) so a
  /// screen can reflect an edited rating/note/etc. before the server has
  /// actually confirmed it, then swap in the server's own response (or
  /// roll back to the original) once the request settles.
  DiaryEntry copyWith({
    Object? rating = _unset,
    Object? note = _unset,
    Object? moodTags = _unset,
    Object? watchedAt = _unset,
    Object? favoriteCast = _unset,
  }) {
    return DiaryEntry(
      id: id,
      mediaId: mediaId,
      mediaType: mediaType,
      source: source,
      titleRu: titleRu,
      titleEn: titleEn,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      season: season,
      episode: episode,
      episodesWatched: episodesWatched,
      rating: identical(rating, _unset) ? this.rating : rating as int?,
      note: identical(note, _unset) ? this.note : note as String?,
      moodTags: identical(moodTags, _unset)
          ? this.moodTags
          : (moodTags as List<String>?) ?? const [],
      favoriteCast: identical(favoriteCast, _unset)
          ? this.favoriteCast
          : (favoriteCast as List<CastMember>?) ?? const [],
      watchedWithUsername: watchedWithUsername,
      isRewatch: isRewatch,
      // watchedAt is non-nullable on this model (unlike the wire format,
      // which allows clearing it) — an explicit null here falls back to
      // the existing value instead of a runtime crash.
      watchedAt: identical(watchedAt, _unset)
          ? this.watchedAt
          : (watchedAt as DateTime?) ?? this.watchedAt,
      createdAt: createdAt,
      sincerityAwarded: sincerityAwarded,
    );
  }
}
