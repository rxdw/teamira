import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/series_route_state.dart';

/// On-device store for [SeriesRouteState] — same plain-[SharedPreferences]
/// pattern as JourneyPrefsService/CollectionsPrefsService, one JSON blob
/// per series under its own key so this survives an app restart (the
/// whole point of it: a "continue from Zürich?" prompt needs to still
/// work a week later, not just for the rest of this session).
class SeriesRoutePrefsService {
  static const _prefix = 'seenly_series_route_';

  String _key(String source, String mediaId) => '$_prefix${source}_$mediaId';

  Future<SeriesRouteState?> load(String source, String mediaId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(source, mediaId));
    if (raw == null) return null;
    try {
      return SeriesRouteState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Malformed/stale blob from an older app version — treat it as
      // "nothing saved" rather than crashing the continuation flow.
      return null;
    }
  }

  Future<void> save(String source, String mediaId, SeriesRouteState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(source, mediaId), jsonEncode(state.toJson()));
  }

  /// Called when someone explicitly picks "start new" over continuing —
  /// the old stop no longer applies once they've deliberately chosen a
  /// fresh route, so the next episode shouldn't offer to resume it.
  Future<void> clear(String source, String mediaId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(source, mediaId));
  }
}
