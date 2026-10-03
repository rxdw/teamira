import 'media_item.dart';

/// Mirrors `ReleaseCalendarItem` in backend/app/schemas.py — one dated
/// card on the Home screen's discovery calendar grid (GET
/// /calendar/releases). Not tied to anything the current user has
/// logged — see CalendarService.releases.
class ReleaseCalendarItem {
  final String source; // "tmdb" | "igdb" | "shikimori"
  final String mediaType; // "movie" | "game" | "anime"
  // ISO date (tmdb/igdb) or ISO datetime with an offset (shikimori,
  // which carries a real air *time* — see backend schema's own
  // docstring). Use [releaseDateTime] rather than parsing this
  // yourself; DateTime.tryParse already handles either shape.
  final String releaseDate;
  final LocalizedText title;
  final String? posterUrl;
  final int? year;
  // Shikimori rows only — which episode number airs on releaseDate.
  final int? episode;
  // Populated for source == "tmdb"/"igdb" — everything needed to open
  // TitleDetailScreen the same way any other poster grid in this app
  // does. Null for source == "shikimori": this app has no id in common
  // with Shikimori's own catalog (see ShikimoriAdapter.calendar's own
  // docstring), so there's no in-app detail screen behind that card —
  // [externalUrl] is what a shikimori-sourced card opens instead.
  final MediaItem? item;
  final String? externalUrl;
  // Genre labels straight from the server row (`genres`). For tmdb/igdb
  // it duplicates `item.genres`; for shikimori it is the only place
  // they exist, since those rows have no MediaItem. Read [allGenres]
  // rather than this — it doesn't care which source filled what.
  final List<String> genres;

  const ReleaseCalendarItem({
    required this.source,
    required this.mediaType,
    required this.releaseDate,
    required this.title,
    this.posterUrl,
    this.year,
    this.episode,
    this.item,
    this.externalUrl,
    this.genres = const [],
  });

  /// Every genre this release is filed under, whichever of [genres] /
  /// `item.genres` carries them — what the calendar's genre filter
  /// (utils/release_genres.dart) reads.
  List<String> get allGenres {
    final fromItem = item?.genres ?? const <String>[];
    if (fromItem.isEmpty) return genres;
    if (genres.isEmpty) return fromItem;
    return {...fromItem, ...genres}.toList();
  }

  DateTime? get releaseDateTime => DateTime.tryParse(releaseDate);

  /// The calendar day this release lands on, in the *device's own*
  /// timezone, at local midnight — what the full-screen calendar groups
  /// by (see utils/release_day_groups.dart) and what the Home tile's date
  /// badge shows. A plain ISO date (tmdb/igdb) has no clock time, so it
  /// reads as itself; a Shikimori air time carries an offset and is
  /// converted first, so an episode that airs at 23:30 in Tokyo lands on
  /// the day it actually reaches *this* device rather than the day it
  /// happens to be in UTC or Japan.
  DateTime? get releaseDay {
    final parsed = releaseDateTime;
    if (parsed == null) return null;
    final local = parsed.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  factory ReleaseCalendarItem.fromJson(Map<String, dynamic> json) =>
      ReleaseCalendarItem(
        source: json['source'] as String,
        mediaType: json['media_type'] as String,
        releaseDate: json['release_date'] as String,
        title: LocalizedText.fromJson(
            (json['title'] as Map<String, dynamic>?) ?? const {}),
        posterUrl: json['poster_url'] as String?,
        year: json['year'] as int?,
        episode: json['episode'] as int?,
        item: json['item'] == null
            ? null
            : MediaItem.fromJson(json['item'] as Map<String, dynamic>),
        externalUrl: json['external_url'] as String?,
        genres: (json['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

/// Mirrors `WatchingReleaseItem` in backend/app/schemas.py — one row on
/// the Home screen's "new episodes" strip (GET /calendar/watching).
/// Always about a title already on this user's own watching/watch-later
/// shelf — see CalendarService.watching.
class WatchingReleaseItem {
  final String mediaId;
  final String source; // "tmdb" | "igdb"
  final String mediaType; // "series" | "anime" | "game"
  final LocalizedText title;
  final String? posterUrl;
  final String releaseDate;
  // True: this episode/release already aired/shipped and the user
  // hasn't logged it yet — "new, go watch/play it". False: still
  // upcoming — "coming up".
  final bool isOut;
  // Series/anime only — null for games.
  final int? season;
  final int? episode;
  final String? episodeName;

  const WatchingReleaseItem({
    required this.mediaId,
    required this.source,
    required this.mediaType,
    required this.title,
    this.posterUrl,
    required this.releaseDate,
    required this.isOut,
    this.season,
    this.episode,
    this.episodeName,
  });

  DateTime? get releaseDateTime => DateTime.tryParse(releaseDate);

  bool get isGame => mediaType == 'game';

  factory WatchingReleaseItem.fromJson(Map<String, dynamic> json) =>
      WatchingReleaseItem(
        mediaId: json['media_id'] as String,
        source: json['source'] as String,
        mediaType: json['media_type'] as String,
        title: LocalizedText.fromJson(
            (json['title'] as Map<String, dynamic>?) ?? const {}),
        posterUrl: json['poster_url'] as String?,
        releaseDate: json['release_date'] as String,
        isOut: json['is_out'] as bool,
        season: json['season'] as int?,
        episode: json['episode'] as int?,
        episodeName: json['episode_name'] as String?,
      );
}
