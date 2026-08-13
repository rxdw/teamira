import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which content types the "random pick" card on Home should
/// draw from — same device-only [SharedPreferences] pattern as
/// [CollectionsPrefsService]; this is a display preference, not account
/// data. Deliberately its own stored set rather than reusing Collections'
/// interests: someone might want that shelf led by anime but tonight's
/// random pick to stick to just movies/series.
///
/// An empty stored set (including "never saved anything yet") means "no
/// filter chosen" — callers should treat that as "all types", not "show
/// nothing".
class RandomPickPrefsService {
  static const _typesKey = 'seenly_random_pick_types';

  Future<Set<String>> loadTypes() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_typesKey) ?? const []).toSet();
  }

  Future<void> saveTypes(Set<String> types) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_typesKey, types.toList());
  }
}
