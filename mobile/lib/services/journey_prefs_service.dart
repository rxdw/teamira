import 'package:shared_preferences/shared_preferences.dart';

import 'geo_city_service.dart';

/// Remembers two small "where did we leave off" facts for the
/// watching-now journey picker (see screens/add_entry/journey_select_screen.dart)
/// — same on-device-only preference pattern as `CollectionsPrefsService`
/// / `LogThemeService`: plain [SharedPreferences], no backend endpoint,
/// since neither of these is account data.
///
/// - The ticket theme's last flight-departure city, so "flying from"
///   defaults to wherever the person actually set off from last time
///   instead of resetting to a fixed city every session — the same
///   spirit as the coach theme's own changeable "from", just
///   remembered instead of hardcoded.
/// - The garden theme's last-visited garden name, purely for the
///   "still just past the gates of ___" note atop today's list — the
///   garden options themselves don't depend on it, this is just
///   continuity dressing.
class JourneyPrefsService {
  static const _originNameKey = 'seenly_journey_origin_name';
  static const _originCountryKey = 'seenly_journey_origin_country';
  static const _originLatKey = 'seenly_journey_origin_lat';
  static const _originLngKey = 'seenly_journey_origin_lng';
  static const _lastGardenKey = 'seenly_journey_last_garden';

  Future<GeoCity?> loadLastOrigin() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_originNameKey);
    final lat = prefs.getDouble(_originLatKey);
    final lng = prefs.getDouble(_originLngKey);
    if (name == null || lat == null || lng == null) return null;
    return GeoCity(name: name, country: prefs.getString(_originCountryKey), lat: lat, lng: lng);
  }

  Future<void> saveLastOrigin(GeoCity city) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_originNameKey, city.name);
    if (city.country != null) {
      await prefs.setString(_originCountryKey, city.country!);
    }
    await prefs.setDouble(_originLatKey, city.lat);
    await prefs.setDouble(_originLngKey, city.lng);
  }

  Future<String?> loadLastGarden() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastGardenKey);
  }

  Future<void> saveLastGarden(String gardenName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastGardenKey, gardenName);
  }
}
