import '../models/episode.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/person_detail.dart';
import '../models/tmdb_review.dart';
import '../models/watch_provider.dart';
import 'api_client.dart';
import 'locale_service.dart';

class MediaService {
  final ApiClient _client;
  MediaService(this._client);

  /// `lang` tells the backend which content-language setting is active
  /// (see services/locale_service.dart) — it defaults to
  /// `LocaleService.contentPrefersRussian`, the same static mirror
  /// LocalizedText.display already reads, so callers don't have to thread
  /// a Provider lookup through every call site just to search. This
  /// doesn't change *how the results are cached* (nothing here is
  /// cached — see backend app/routers/media.py::search_media's
  /// docstring) — it only affects whether the backend also tries a
  /// Russian-language TMDB search. A query typed
  /// in Cyrillic gets that same treatment server-side regardless of this
  /// flag, so leaving it at the default is never a reason a Russian
  /// query fails to find anything.
  Future<List<MediaItem>> search(
    String query, {
    bool includeGames = true,
    bool includeBooks = true,
    bool includeManga = true,
    String? lang,
  }) async {
    if (query.trim().isEmpty) return [];
    final json = await _client.get('/media/search', query: {
      'q': query,
      'include_games': includeGames.toString(),
      'include_books': includeBooks.toString(),
      'include_manga': includeManga.toString(),
      'lang': lang ?? (LocaleService.contentPrefersRussian ? 'ru' : 'en'),
    }) as List;
    return json
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Runtime/certification/status, ratings, and similar titles for a TMDB
  /// title — or the IGDB/Open Library equivalent (genres/description/
  /// cover) for a game/book/manga, with ratings/similar simply empty
  /// there. Returns null if the source doesn't support extended detail at
  /// all, or resolution failed — callers should fall back to whatever thin
  /// MediaItem they already had rather than treating this as fatal.
  Future<MediaDetail?> detail({
    required String mediaId,
    required String mediaType,
    required String source,
  }) async {
    const supported = {'tmdb', 'igdb', 'open_library', 'shikimori_manga'};
    if (!supported.contains(source)) return null;
    try {
      final json = await _client.get('/media/detail', query: {
        'media_id': mediaId,
        'media_type': mediaType,
        'source': source,
      }) as Map<String, dynamic>;
      return MediaDetail.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// A tapped cast member / director's bio + photo + filmography, opened
  /// from the title screen's cast row (see CastMember.personId /
  /// MediaItem.directorId). Null on a 404 (bad/stale id) rather than
  /// throwing, same degrade-quietly convention as detail() above.
  Future<PersonDetail?> person({required String personId}) async {
    try {
      final json = await _client.get('/media/person', query: {
        'person_id': personId,
      }) as Map<String, dynamic>;
      return PersonDetail.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// A series' season/episode list, for the season tracker on the title
  /// screen. Always returns something (an empty list rather than throwing)
  /// for movies/games/unresolved titles — see GET /media/episodes.
  Future<SeriesEpisodes> episodes({
    required String mediaId,
    required String source,
  }) async {
    final json = await _client.get('/media/episodes', query: {
      'media_id': mediaId,
      'source': source,
    }) as Map<String, dynamic>;
    return SeriesEpisodes.fromJson(json);
  }

  /// "Where to watch" — Netflix/Disney+/etc availability for a movie or
  /// series, plus a click-through link that always goes through our own
  /// backend first (see backend/app/routers/watch.py). Empty `providers`
  /// just means nothing's known for this title/country — not an error;
  /// callers should hide the section rather than showing a failure.
  Future<WatchProvidersResult> watchProviders({
    required String mediaId,
    required String source,
    required String mediaType,
    required String title,
    String? tmdbId,
    String country = 'US',
  }) async {
    final json = await _client.get('/media/watch-providers', query: {
      'media_id': mediaId,
      'source': source,
      'media_type': mediaType,
      'title': title,
      if (tmdbId != null) 'tmdb_id': tmdbId,
      'country': country,
    }) as Map<String, dynamic>;
    return WatchProvidersResult.fromJson(json);
  }

  /// Written reviews for a movie/series, merged from TMDB and Trakt (see
  /// backend/app/routers/reviews.py). Empty list just means neither
  /// source has anything for this title, or there's no tmdb_id to look
  /// up at all (a game/book/manga).
  Future<TmdbReviewsResult> reviews({
    required String mediaType,
    String? tmdbId,
  }) async {
    if (tmdbId == null) return const TmdbReviewsResult(reviews: []);
    final json = await _client.get('/media/reviews', query: {
      'media_type': mediaType,
      'tmdb_id': tmdbId,
    }) as Map<String, dynamic>;
    return TmdbReviewsResult.fromJson(json);
  }
}
