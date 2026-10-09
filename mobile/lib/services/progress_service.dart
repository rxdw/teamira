import '../models/episode.dart';
import '../models/reading_progress.dart';
import 'api_client.dart';

class ProgressService {
  final ApiClient _client;
  ProgressService(this._client);

  /// The current user's bookmark on one book/manga (GET /progress/reading) —
  /// empty, never an error, for a title they haven't started.
  Future<ReadingBookmark> reading({
    required String mediaId,
    required String source,
  }) async {
    final json = await _client.get('/progress/reading', query: {
      'media_id': mediaId,
      'source': source,
    }) as Map<String, dynamic>;
    return ReadingBookmark.fromJson(json);
  }

  /// Replaces the bookmark (PUT /progress/reading). The whole state goes up
  /// every time, so a retry or a late duplicate lands on the same result; a
  /// bookmark with nothing in it clears it server-side.
  Future<ReadingBookmark> setReading({
    required String mediaId,
    required String source,
    required ReadingBookmark bookmark,
  }) async {
    final json = await _client.put('/progress/reading', body: {
      'media_id': mediaId,
      'source': source,
      'volume': bookmark.volume,
      'chapter': bookmark.chapter,
      'page': bookmark.page,
    }) as Map<String, dynamic>;
    return ReadingBookmark.fromJson(json);
  }

  Future<SeriesProgress> series({
    required String mediaId,
    required String source,
  }) async {
    final json = await _client.get('/progress/series', query: {
      'media_id': mediaId,
      'source': source,
    }) as Map<String, dynamic>;
    return SeriesProgress.fromJson(json);
  }

  /// Toggles one episode (a single tap) or a whole season at once ("mark
  /// season watched" sends every episode in it) — same endpoint either
  /// way. Returns the full updated watched-set so callers can just replace
  /// their local copy.
  Future<SeriesProgress> toggle({
    required String mediaId,
    required String source,
    required bool watched,
    required List<Episode> episodes,
  }) async {
    final json = await _client.post('/progress/toggle', body: {
      'media_id': mediaId,
      'source': source,
      'watched': watched,
      'episodes': [
        for (final e in episodes) {'season': e.season, 'episode': e.episode},
      ],
    }) as Map<String, dynamic>;
    return SeriesProgress.fromJson(json);
  }

  /// One episode's own lightweight rating/note, set right from the
  /// episode list (see routers/progress.py::rate_episode) — never
  /// creates a diary row by itself. Marks the episode watched if it
  /// wasn't already. Returns the full updated watched-set, same as
  /// [toggle], so the caller can just replace its local copy.
  Future<SeriesProgress> rateEpisode({
    required String mediaId,
    required String source,
    required int season,
    required int episode,
    int? rating,
    String? note,
  }) async {
    final json = await _client.post('/progress/episode-rating', body: {
      'media_id': mediaId,
      'source': source,
      'season': season,
      'episode': episode,
      'rating': rating,
      'note': note,
    }) as Map<String, dynamic>;
    return SeriesProgress.fromJson(json);
  }

  /// The explicit "every episode is watched now" transition — call once
  /// the client's own episode count says the series is fully watched
  /// (see [episode_log_followup.dart]). Never inferred from a single
  /// episode log; that only ever moves the title to "watching" server-side.
  Future<void> completeSeries({
    required String mediaId,
    required String source,
  }) async {
    await _client.post('/progress/complete', body: {
      'media_id': mediaId,
      'source': source,
    });
  }
}
