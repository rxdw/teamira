import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/diary_entry.dart';
import '../models/media_item.dart';
import '../repositories/diary_repository.dart';
import '../utils/unset.dart';

/// Sentinel default, aliased to the one shared sentinel in
/// utils/unset.dart — needs to be `identical()` to DiaryEntry's and
/// DiaryRepository's, since a caller's "leave this alone" here has to
/// survive being forwarded down through both of those. See that file's
/// doc comment.
const Object _unset = unset;

/// The one shared, in-memory copy of the signed-in account's diary,
/// backed by an on-device cache (see `DiaryRepository` /
/// `LocalJsonCache`) — see Фаза 2.15 in the launch plan for the problem
/// this replaces (every screen calling `DiaryService` and holding its
/// own `Future`, kept loosely in sync via `RouteObserver`/`didPopNext`).
///
/// Registered once in `app.dart`'s `MultiProvider`, same as any other
/// service — screens read it with `context.watch<DiaryStore>()` for
/// [entries]/[isLoading]/[error], and call [ensureLoaded] once (from
/// `initState` is fine — it's idempotent) to make sure something has
/// actually triggered a load.
class DiaryStore extends ChangeNotifier {
  DiaryStore(this._repo);
  final DiaryRepository _repo;

  List<DiaryEntry> entries = [];
  bool isLoading = false;
  Object? error;

  bool _everLoaded = false;
  Future<List<DiaryEntry>>? _inFlight;

  /// Cache-then-network fetch. Safe to call from every screen that
  /// shows diary entries without worrying about duplicate network
  /// calls: the first caller does the work, everyone else (including a
  /// caller that arrives while it's still in flight) shares the same
  /// result. Once a load has completed at least once this session,
  /// later calls resolve instantly with whatever's already in [entries]
  /// unless [forceRefresh] is set (pull-to-refresh, or an explicit
  /// "I know something changed elsewhere" refresh).
  Future<List<DiaryEntry>> ensureLoaded({bool forceRefresh = false}) {
    if (_everLoaded && !forceRefresh) return Future.value(entries);
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> refresh() => ensureLoaded(forceRefresh: true);

  Future<List<DiaryEntry>> _load() async {
    if (!_everLoaded) {
      final cached = await _repo.readCache();
      if (cached != null) {
        entries = cached;
        notifyListeners();
      }
    }
    isLoading = true;
    notifyListeners();
    try {
      entries = await _repo.fetchAndCache();
      error = null;
    } catch (e) {
      error = e;
      // Offline, or the request just failed — if a cached copy is
      // already showing (just above, or from an earlier successful
      // load this session), that's what stays on screen. Only a
      // genuinely empty store surfaces the error to whoever's watching,
      // instead of silently looking like an empty diary.
      if (entries.isEmpty) rethrow;
    } finally {
      isLoading = false;
      _everLoaded = true;
      notifyListeners();
    }
    return entries;
  }

  /// Logs a new evening. Not optimistic on purpose, unlike [updateEntry]
  /// below — there's no existing local row to show early here (the
  /// server assigns the id and works out the sincerity/level-up side
  /// effects), so callers keep their current "await, then show a
  /// result" flow. What this *does* give every caller: the new entry
  /// lands in the one shared [entries] list, so any other screen
  /// watching this store sees it immediately, instead of only the
  /// screen that logged it.
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
  }) async {
    final entry = await _repo.logEntry(
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
    entries = [entry, ...entries]; // newest-first, matching DiaryService.list's own order
    unawaited(_repo.writeCache(entries));
    notifyListeners();
    return entry;
  }

  /// Optimistic — see Фаза 2.15.3 in the launch plan. [entries] (and so
  /// every screen watching this store) reflects the change the instant
  /// this is called, before the network round trip finishes; rolls the
  /// affected row back to what it was if the request fails. Same
  /// "leave a field alone vs. set it to null" sentinel convention as
  /// `DiaryService.updateEntry` and `DiaryEntry.copyWith`.
  Future<DiaryEntry> updateEntry(
    String entryId, {
    Object? rating = _unset,
    Object? note = _unset,
    Object? moodTags = _unset,
    Object? watchedAt = _unset,
    Object? favoriteCast = _unset,
  }) async {
    final index = entries.indexWhere((e) => e.id == entryId);
    final previous = index == -1 ? null : entries[index];
    if (previous != null) {
      entries = [...entries];
      entries[index] = previous.copyWith(
        rating: rating,
        note: note,
        moodTags: moodTags,
        watchedAt: watchedAt,
        favoriteCast: favoriteCast,
      );
      notifyListeners();
    }
    try {
      // Same reasoning as DiaryRepository.updateEntry's own comment:
      // this store's `_unset` isn't the repository's `_unset`, so
      // building the call through Function.apply (rather than
      // forwarding `rating: rating` etc. directly) makes sure an
      // omitted field here reaches the repository as genuinely omitted
      // — letting *its* own sentinel check (which then does the same
      // thing one hop further down, into the service) work correctly,
      // without this store needing to know or care how that's
      // implemented underneath it.
      final namedArgs = <Symbol, dynamic>{};
      if (!identical(rating, _unset)) namedArgs[#rating] = rating;
      if (!identical(note, _unset)) namedArgs[#note] = note;
      if (!identical(moodTags, _unset)) namedArgs[#moodTags] = moodTags;
      if (!identical(watchedAt, _unset)) namedArgs[#watchedAt] = watchedAt;
      if (!identical(favoriteCast, _unset)) namedArgs[#favoriteCast] = favoriteCast;
      final updated = await (Function.apply(_repo.updateEntry, [entryId], namedArgs)
          as Future<DiaryEntry>);
      final i = entries.indexWhere((e) => e.id == entryId);
      if (i != -1) {
        entries = [...entries];
        entries[i] = updated;
      }
      return updated;
    } catch (e) {
      if (previous != null) {
        final i = entries.indexWhere((e) => e.id == entryId);
        if (i != -1) {
          entries = [...entries];
          entries[i] = previous;
        }
      }
      // The caller (the edit sheet, today) still needs to know this
      // failed, so it can show its own "couldn't save" message — same
      // as before this store existed.
      rethrow;
    } finally {
      unawaited(_repo.writeCache(entries));
      notifyListeners();
    }
  }

  /// Optimistic removal — same reasoning as [updateEntry].
  Future<void> delete(String entryId) async {
    final index = entries.indexWhere((e) => e.id == entryId);
    final removed = index == -1 ? null : entries[index];
    if (index != -1) {
      entries = [...entries]..removeAt(index);
      notifyListeners();
    }
    try {
      await _repo.delete(entryId);
    } catch (e) {
      if (removed != null && index != -1) {
        entries = [...entries]..insert(index, removed);
        notifyListeners();
      }
      rethrow;
    } finally {
      unawaited(_repo.writeCache(entries));
    }
  }
}
