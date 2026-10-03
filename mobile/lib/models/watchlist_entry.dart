import 'media_item.dart' show CastMember;
import 'profile_stats.dart' show FavoritePick;

/// Mirrors `WatchlistEntryOut` in backend/app/schemas.py — one row per
/// title, current status only (no rewatch history; see [DiaryEntry] for
/// that). Powers the Profile "watched / plan to watch" toggle + grid.
class WatchlistEntry {
  final String id;
  final String mediaId;
  final String mediaType;
  final String source;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  // Horizontal backdrop image, same field MediaItem carries (see
  // MediaItem.backdropUrl) — used for wide banners (title screen's hero,
  // Profile's cover) instead of stretching the vertical poster. Null on
  // sources that never had one; callers fall back to posterUrl.
  final String? backdropUrl;
  final int? year;
  final List<String> genres;
  final double? rating; // source's score
  final int? userRating; // personal hearts, 1-5
  final String? note;
  // Mirrors of the most recently logged evening's DiaryEntry.moodTags /
  // favoriteCast (see DiaryEntry's own docstring) — so this shelf-level
  // snapshot can show the same "why did i like this" tags and standout
  // cast the diary itself would show for that evening, not just the
  // rating and note. Empty for a row logged before this shipped.
  final List<String> moodTags;
  final List<CastMember> favoriteCast;
  final DateTime? watchedAt;
  final String status; // "watch_later" | "watched" | "dropped"
  final bool isFavorite;

  const WatchlistEntry({
    required this.id,
    required this.mediaId,
    required this.mediaType,
    required this.source,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.genres = const [],
    this.rating,
    this.userRating,
    this.note,
    this.moodTags = const [],
    this.favoriteCast = const [],
    this.watchedAt,
    required this.status,
    this.isFavorite = false,
  });

  String get displayTitle =>
      (titleEn?.trim().isNotEmpty ?? false) ? titleEn! : (titleRu ?? '—');

  factory WatchlistEntry.fromJson(Map<String, dynamic> json) =>
      WatchlistEntry(
        id: json['id'] as String,
        mediaId: json['media_id'] as String,
        mediaType: json['media_type'] as String,
        source: json['source'] as String,
        titleRu: json['title_ru'] as String?,
        titleEn: json['title_en'] as String?,
        posterUrl: json['poster_url'] as String?,
        backdropUrl: json['backdrop_url'] as String?,
        year: json['year'] as int?,
        genres:
            (json['genres'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        rating: (json['rating'] as num?)?.toDouble(),
        userRating: json['user_rating'] as int?,
        note: json['note'] as String?,
        moodTags: (json['mood_tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        favoriteCast: (json['favorite_cast'] as List<dynamic>?)
                ?.map((e) => CastMember.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        watchedAt: json['watched_at'] != null
            ? DateTime.tryParse(json['watched_at'] as String)
            : null,
        status: json['status'] as String,
        isFavorite: json['is_favorite'] as bool? ?? false,
      );

  /// Mirrors [fromJson] — added for the on-device watchlist cache (see
  /// `services/local_json_cache.dart`), not for talking to the backend.
  Map<String, dynamic> toJson() => {
        'id': id,
        'media_id': mediaId,
        'media_type': mediaType,
        'source': source,
        'title_ru': titleRu,
        'title_en': titleEn,
        'poster_url': posterUrl,
        'backdrop_url': backdropUrl,
        'year': year,
        'genres': genres,
        'rating': rating,
        'user_rating': userRating,
        'note': note,
        'mood_tags': moodTags,
        'favorite_cast': favoriteCast.map((c) => c.toJson()).toList(),
        'watched_at': watchedAt?.toIso8601String(),
        'status': status,
        'is_favorite': isFavorite,
      };
}

/// Mirrors `FriendCollectionsOut` — same three shelves as
/// [ProfileCollections], but each one can also come back hidden (the
/// friend's own privacy setting for it is "nobody") rather than merely
/// empty — see [FriendProfile].
class FriendCollections {
  final List<WatchlistEntry> watchLater;
  final bool watchLaterVisible;
  final List<WatchlistEntry> watching;
  final bool watchingVisible;
  final List<WatchlistEntry> watched;
  final bool watchedVisible;
  // Favorite films (status-independent — see models.User.privacy_favorites
  // on the backend), gated by its own privacy setting independent of
  // `watched`'s. Same "visible=false means hidden, not empty" rule as
  // the three shelves above.
  final List<WatchlistEntry> favorites;
  final bool favoritesVisible;
  // The friend's own stories-deck picks among their favorites — see
  // ProfileMe.topFavoritePicks's own docstring.
  final List<FavoritePick> topFavoritePicks;

  const FriendCollections({
    this.watchLater = const [],
    this.watchLaterVisible = true,
    this.watching = const [],
    this.watchingVisible = true,
    this.watched = const [],
    this.watchedVisible = true,
    this.favorites = const [],
    this.favoritesVisible = true,
    this.topFavoritePicks = const [],
  });

  factory FriendCollections.fromJson(Map<String, dynamic> json) =>
      FriendCollections(
        watchLater: (json['watch_later'] as List? ?? const [])
            .map((e) => WatchlistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        watchLaterVisible: json['watch_later_visible'] as bool? ?? true,
        watching: (json['watching'] as List? ?? const [])
            .map((e) => WatchlistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        watchingVisible: json['watching_visible'] as bool? ?? true,
        watched: (json['watched'] as List? ?? const [])
            .map((e) => WatchlistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        watchedVisible: json['watched_visible'] as bool? ?? true,
        favorites: (json['favorites'] as List? ?? const [])
            .map((e) => WatchlistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        favoritesVisible: json['favorites_visible'] as bool? ?? true,
        topFavoritePicks: (json['top_favorite_picks'] as List? ?? const [])
            .map((e) => FavoritePick.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Same three shelves as [FriendCollections], but for the signed-in
/// account's own titles, always fully visible — the backend already splits
/// the same rows into: plan-to-watch, mid-series ("watching", at least
/// one episode logged but not completed), and fully watched.
class ProfileCollections {
  final List<WatchlistEntry> watchLater;
  final List<WatchlistEntry> watching;
  final List<WatchlistEntry> watched;

  const ProfileCollections({
    required this.watchLater,
    this.watching = const [],
    required this.watched,
  });

  factory ProfileCollections.fromJson(Map<String, dynamic> json) =>
      ProfileCollections(
        watchLater: (json['watch_later'] as List? ?? const [])
            .map((e) => WatchlistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        watching: (json['watching'] as List? ?? const [])
            .map((e) => WatchlistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        watched: (json['watched'] as List? ?? const [])
            .map((e) => WatchlistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Mirrors [fromJson] — added for the on-device watchlist cache (see
  /// `services/local_json_cache.dart`), not for talking to the backend.
  Map<String, dynamic> toJson() => {
        'watch_later': watchLater.map((e) => e.toJson()).toList(),
        'watching': watching.map((e) => e.toJson()).toList(),
        'watched': watched.map((e) => e.toJson()).toList(),
      };
}
