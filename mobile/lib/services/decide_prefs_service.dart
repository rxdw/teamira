import 'persisted_pref.dart';

/// Remembers the filters someone last used in the "can't decide?" flow
/// (Home → DecideFiltersScreen) — same device-only [SharedPreferences]
/// pattern as the old RandomPickPrefsService this replaces. Three
/// independent sets/values, saved together once someone taps through to
/// a decision method, so reopening the flow tomorrow starts from
/// wherever they left off instead of resetting to "everything".
///
/// Empty/null stored values all mean "no filter chosen" — callers should
/// treat that as "don't narrow on this axis", not "show nothing".
class DecidePrefsService {
  final _types = PersistedPref.stringSet('seenly_decide_types');
  final _genres = PersistedPref.stringSet('seenly_decide_genres');
  final _decade = PersistedPref.nullableInt('seenly_decide_decade');

  Future<Set<String>> loadTypes() async {
    await _types.load();
    return _types.value;
  }

  Future<Set<String>> loadGenres() async {
    await _genres.load();
    return _genres.value;
  }

  Future<int?> loadDecade() async {
    await _decade.load();
    return _decade.value;
  }

  Future<void> save({
    required Set<String> types,
    required Set<String> genres,
    required int? decade,
  }) async {
    await _types.save(types);
    await _genres.save(genres);
    await _decade.save(decade);
  }
}
