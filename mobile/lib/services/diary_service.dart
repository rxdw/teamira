import '../models/diary_entry.dart';
import '../models/media_item.dart';
import 'api_client.dart';

/// Sentinel default for [DiaryService.updateEntry]'s optional fields, so
/// leaving an argument out ("don't touch this field") can be told apart
/// from passing it as `null` ("clear this field") — a plain `null`
/// default can't tell those two apart.
const Object _unset = Object();

class DiaryService {
  final ApiClient _client;
  DiaryService(this._client);

  /// Logs one evening. `rating` is 1-5 hearts, `watchedAt` defaults to now
  /// server-side when omitted. Also upserts the title's current
  /// watch-status snapshot and appends an activity event — see
  /// `routers/diary.py::log_entry` on the backend. `isFavorite` only ever
  /// turns the title's favorite flag ON (see DiaryEntryCreate.is_favorite's
  /// own docstring on the backend) — leaving the box unchecked on a
  /// rewatch never un-favorites something you favorited before.
  Future<DiaryEntry> logEntry({
    required MediaItem item,
    int? rating,
    String? note,
    List<String>? moodTags,
    // Up to 3 cast members picked as this evening's standouts — see the
    // themed log flows' "who did you love most tonight?" step. Omitted
    // (or empty) when that step was skipped.
    List<CastMember>? favoriteCast,
    DateTime? watchedAt,
    bool watchedWithPartner = false,
    bool isFavorite = false,
    // Set together to log this as one episode of a series (see
    // DiaryEntry's own doc comment) rather than a whole-title watch —
    // passed through from the themed log screens (coach/cinema/garden)
    // whenever they were opened for a specific season/episode. `season`
    // alone (episode null) instead logs one *completed season* — see
    // finishEpisode, the only place that builds a log screen this way.
    int? season,
    int? episode,
    // Only meaningful alongside a season-only log — how many episodes
    // that season has, so the one diary row it creates carries that many
    // episodes' worth of runtime rather than a single episode's (see
    // routers/diary.py::log_watched).
    int? episodeCount,
  }) async {
    final json = await _client.post('/diary', body: {
      'item': item.toJson(),
      'rating': rating,
      'note': note,
      'mood_tags': moodTags,
      'favorite_cast': favoriteCast?.map((c) => c.toJson()).toList(),
      'watched_at': watchedAt?.toIso8601String(),
      'watched_with_partner': watchedWithPartner,
      'is_favorite': isFavorite,
      'season': season,
      'episode': episode,
      'episode_count': episodeCount,
    }) as Map<String, dynamic>;
    return DiaryEntry.fromJson(json);
  }

  Future<List<DiaryEntry>> list() async {
    final json = await _client.get('/diary') as List;
    return json
        .map((e) => DiaryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Oldest-first history for one title — feeds the rewatch timeline on
  /// the title detail screen.
  Future<List<DiaryEntry>> mediaHistory(String mediaId, String source) async {
    final json = await _client.get('/diary/media/$mediaId', query: {
      'source': source,
    }) as List;
    return json
        .map((e) => DiaryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Edits an already-logged evening's review in place — the rating
  /// and/or note most of the time, occasionally the mood tags or the
  /// date. Only the arguments actually passed get sent, so a caller can
  /// fix just the note without touching the rating next to it (the
  /// sentinel objects below are how "not sent" gets told apart from
  /// "sent as null" — see the class-level docs on [_unset]). Mirrors
  /// `PATCH /diary/{entry_id}` on the backend, which keeps the
  /// watchlist snapshot in sync when this is the title's most recent
  /// logged evening — see `routers/diary.py::update_entry`.
  Future<DiaryEntry> updateEntry(
    String entryId, {
    Object? rating = _unset,
    Object? note = _unset,
    Object? moodTags = _unset,
    Object? watchedAt = _unset,
    Object? favoriteCast = _unset,
  }) async {
    final body = <String, dynamic>{};
    if (!identical(rating, _unset)) body['rating'] = rating as int?;
    if (!identical(note, _unset)) body['note'] = note as String?;
    if (!identical(moodTags, _unset)) body['mood_tags'] = moodTags as List<String>?;
    if (!identical(watchedAt, _unset)) {
      body['watched_at'] = (watchedAt as DateTime?)?.toIso8601String();
    }
    if (!identical(favoriteCast, _unset)) {
      body['favorite_cast'] = (favoriteCast as List<CastMember>?)?.map((c) => c.toJson()).toList();
    }
    final json = await _client.patch('/diary/$entryId', body: body) as Map<String, dynamic>;
    return DiaryEntry.fromJson(json);
  }

  Future<void> delete(String entryId) => _client.delete('/diary/$entryId');
}
