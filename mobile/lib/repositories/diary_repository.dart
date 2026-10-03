import '../models/diary_entry.dart';
import '../models/media_item.dart';
import '../services/diary_service.dart';
import '../services/local_json_cache.dart';
import '../utils/unset.dart';

/// Same shared sentinel DiaryService/DiaryEntry/DiaryStore use — see
/// utils/unset.dart for why this needs to be the literal same instance
/// everywhere rather than each file's own `const Object()`.
const Object _unset = unset;

/// Sits between [DiaryStore] and [DiaryService]. Doesn't decide *when*
/// to read from cache vs. network — that's the store's job (it's the
/// one with the "is this the first load or a forced refresh" context) —
/// this class just knows *how* to read/write the cache and talks to the
/// network. See Фаза 2.15.1 in the launch plan.
class DiaryRepository {
  final DiaryService _service;
  final LocalJsonCache _cache;
  static const _cacheKey = 'diary_entries';

  DiaryRepository(this._service, this._cache);

  /// The last cached list, or `null` if there isn't one yet (first ever
  /// launch, or the cache was cleared/corrupt).
  Future<List<DiaryEntry>?> readCache() async {
    final raw = await _cache.read(_cacheKey);
    if (raw is! List) return null;
    try {
      return raw
          .map((e) => DiaryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // The cached shape no longer matches DiaryEntry.fromJson (a field
      // was added/renamed since this was written) — treat it as no
      // cache at all rather than crashing; the network fetch below
      // will overwrite it with the current shape either way.
      return null;
    }
  }

  Future<void> writeCache(List<DiaryEntry> entries) =>
      _cache.write(_cacheKey, entries.map((e) => e.toJson()).toList());

  Future<List<DiaryEntry>> fetchAndCache() async {
    final entries = await _service.list();
    await writeCache(entries);
    return entries;
  }

  // Pass-through mutations — DiaryStore decides how (and whether) to
  // reflect these locally before/after the call actually resolves.
  Future<DiaryEntry> logEntry({
    required MediaItem item,
    int? rating,
    String? note,
    List<String>? moodTags,
    List<CastMember>? favoriteCast,
    DateTime? watchedAt,
    bool watchedWithPartner = false,
    bool isFavorite = false,
    int? season,
    int? episode,
    int? episodeCount,
  }) {
    return _service.logEntry(
      item: item,
      rating: rating,
      note: note,
      moodTags: moodTags,
      favoriteCast: favoriteCast,
      watchedAt: watchedAt,
      watchedWithPartner: watchedWithPartner,
      isFavorite: isFavorite,
      season: season,
      episode: episode,
      episodeCount: episodeCount,
    );
  }

  // NOTE on the plumbing below: `_unset` above is aliased to the one
  // shared sentinel in utils/unset.dart, specifically so it's
  // `identical()` to the one DiaryService.updateEntry checks against —
  // without that, simply forwarding `rating: rating` here would hand
  // the service a value it can't recognize as "left alone", and it'd
  // crash trying to cast it as `int?`. Building the call through
  // `Function.apply` instead — including only the named arguments this
  // repository's own check says were actually set — means an omitted
  // field reaches the service as genuinely absent from the call
  // either way, so this stays correct even if a future edit ever
  // swaps that shared sentinel back out for a file-local one.
  Future<DiaryEntry> updateEntry(
    String entryId, {
    Object? rating = _unset,
    Object? note = _unset,
    Object? moodTags = _unset,
    Object? watchedAt = _unset,
    Object? favoriteCast = _unset,
  }) {
    final namedArgs = <Symbol, dynamic>{};
    if (!identical(rating, _unset)) namedArgs[#rating] = rating;
    if (!identical(note, _unset)) namedArgs[#note] = note;
    if (!identical(moodTags, _unset)) namedArgs[#moodTags] = moodTags;
    if (!identical(watchedAt, _unset)) namedArgs[#watchedAt] = watchedAt;
    if (!identical(favoriteCast, _unset)) namedArgs[#favoriteCast] = favoriteCast;
    return Function.apply(_service.updateEntry, [entryId], namedArgs)
        as Future<DiaryEntry>;
  }

  Future<void> delete(String entryId) => _service.delete(entryId);
}
