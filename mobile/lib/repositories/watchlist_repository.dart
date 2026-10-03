import '../models/watchlist_entry.dart';
import '../services/local_json_cache.dart';
import '../services/profile_service.dart';

/// "Watchlist" here means the three shelves — plan to watch / watching /
/// watched — that `ProfileService.collections()` already returns as a
/// [ProfileCollections]. There's no separate fetch on `WatchlistService`
/// (that one only has the "honest drop" action) — this repository just
/// gives that existing call the same cache-then-network treatment
/// [DiaryRepository] gives `DiaryService.list()`. See Фаза 2.15.1 in the
/// launch plan.
class WatchlistRepository {
  final ProfileService _service;
  final LocalJsonCache _cache;
  static const _cacheKey = 'watchlist_collections';

  WatchlistRepository(this._service, this._cache);

  Future<ProfileCollections?> readCache() async {
    final raw = await _cache.read(_cacheKey);
    if (raw is! Map) return null;
    try {
      return ProfileCollections.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      // Same reasoning as DiaryRepository.readCache — a shape mismatch
      // just means "no usable cache yet", not a crash.
      return null;
    }
  }

  Future<void> writeCache(ProfileCollections collections) =>
      _cache.write(_cacheKey, collections.toJson());

  Future<ProfileCollections> fetchAndCache() async {
    final collections = await _service.collections();
    await writeCache(collections);
    return collections;
  }
}
