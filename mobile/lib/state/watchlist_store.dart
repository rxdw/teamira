import 'package:flutter/foundation.dart';

import '../models/watchlist_entry.dart';
import '../repositories/watchlist_repository.dart';

/// Same shape and same reasoning as [DiaryStore] (see that class's own
/// doc comment and Фаза 2.15 in the launch plan), for the plan-to-watch
/// / watching / watched shelves instead of the diary log.
///
/// No optimistic mutation methods here yet — unlike the diary's rating
/// edit, none of the actions that change these shelves (marking
/// something watched, dropping it, favoriting it) go through this store
/// today; they still call their own services directly (see
/// title_detail_screen.dart and friends). [refresh] is what those
/// screens should call once they're migrated, so the change shows up
/// here too instead of only on the screen that made it.
class WatchlistStore extends ChangeNotifier {
  WatchlistStore(this._repo);
  final WatchlistRepository _repo;

  ProfileCollections collections = const ProfileCollections(watchLater: [], watched: []);
  bool isLoading = false;
  Object? error;

  bool _everLoaded = false;
  Future<ProfileCollections>? _inFlight;

  Future<ProfileCollections> ensureLoaded({bool forceRefresh = false}) {
    if (_everLoaded && !forceRefresh) return Future.value(collections);
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<ProfileCollections> refresh() => ensureLoaded(forceRefresh: true);

  Future<ProfileCollections> _load() async {
    if (!_everLoaded) {
      final cached = await _repo.readCache();
      if (cached != null) {
        collections = cached;
        notifyListeners();
      }
    }
    isLoading = true;
    notifyListeners();
    try {
      collections = await _repo.fetchAndCache();
      error = null;
    } catch (e) {
      error = e;
      // Same "keep showing the cache on a failed refresh" reasoning as
      // DiaryStore._load — an empty-and-never-loaded store still
      // surfaces the error so the caller can show something.
      if (collections.watchLater.isEmpty &&
          collections.watching.isEmpty &&
          collections.watched.isEmpty) {
        rethrow;
      }
    } finally {
      isLoading = false;
      _everLoaded = true;
      notifyListeners();
    }
    return collections;
  }
}
