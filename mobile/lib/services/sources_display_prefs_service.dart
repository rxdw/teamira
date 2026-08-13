import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether "your sources" (YouTube/Twitch, see SourcesScreen) should also
/// show up inside the main Profile watched / watching / plan-to-watch
/// shelves, instead of staying confined to their own screen. Off by
/// default — this is what keeps a big playlist import from skewing the
/// "movies watched" stats in the first place (see SourcesScreen's own
/// doc comment), so merging them back in is an opt-in choice made once,
/// in Settings, same device-only SharedPreferences pattern as
/// [RitualPrefsService].
///
/// Turning this on only changes what ProfileScreen's shelves *include*
/// (see _ProfileScreenState._load in profile_screen.dart) — it doesn't
/// change how a tile behaves once it's there. A YouTube/Twitch entry
/// still has no catalog page behind it, so a tile that came from a
/// source still opens the original video externally rather than a title
/// page; mixed into a grid built for movie posters, that can look a
/// little off (aspect ratio, missing detail-screen behavior on tap).
/// That's the whole reason this needs an explicit warning in the UI
/// rather than just being on by default.
class SourcesDisplayPrefsService extends ChangeNotifier {
  static const _mergeKey = 'seenly_sources_merged_into_main_list';

  bool _mergeIntoMainList = false;
  bool get mergeIntoMainList => _mergeIntoMainList;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mergeIntoMainList = prefs.getBool(_mergeKey) ?? false;
    notifyListeners();
  }

  Future<void> setMergeIntoMainList(bool value) async {
    if (_mergeIntoMainList == value) return;
    _mergeIntoMainList = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mergeKey, value);
  }
}
