import 'package:shared_preferences/shared_preferences.dart';

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
  static const _typesKey = 'seenly_decide_types';
  static const _genresKey = 'seenly_decide_genres';
  static const _decadeKey = 'seenly_decide_decade';

  Future<Set<String>> loadTypes() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_typesKey) ?? const []).toSet();
  }

  Future<Set<String>> loadGenres() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_genresKey) ?? const []).toSet();
  }

  Future<int?> loadDecade() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_decadeKey);
  }

  Future<void> save({
    required Set<String> types,
    required Set<String> genres,
    required int? decade,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_typesKey, types.toList());
    await prefs.setStringList(_genresKey, genres.toList());
    if (decade == null) {
      await prefs.remove(_decadeKey);
    } else {
      await prefs.setInt(_decadeKey, decade);
    }
  }
}
