import 'package:flutter/foundation.dart';

import 'persisted_pref.dart';

/// Which tile set `JourneyRealMap` draws — a look, not data: the same
/// origin/destination/progress either way, just a different map skin
/// underneath. All four are free, keyless raster tile sources (same
/// "no key needed" stack the app already leans on for OSM/Nominatim —
/// see journey_real_map.dart's module docstring), so switching styles
/// never touches settings.tmdb_api_key-style configuration.
enum MapStyle { classic, paper, night, terrain }

/// Everything a [TileLayer] plus its required attribution line needs
/// for one [MapStyle] — kept together so adding a fifth style later is
/// a one-entry change in [MapStyleCatalog.all], not a scattered edit
/// across widget files.
class MapStyleInfo {
  final MapStyle style;
  final String label;
  final String urlTemplate;
  final List<String> subdomains;
  final String attribution;

  const MapStyleInfo({
    required this.style,
    required this.label,
    required this.urlTemplate,
    required this.subdomains,
    required this.attribution,
  });
}

/// Reference data for every style — tile URLs and required attribution
/// per each provider's own usage policy (CARTO and OpenTopoMap both
/// require their name credited alongside the base OSM credit, same as
/// journey_real_map.dart already does for plain OSM).
class MapStyleCatalog {
  const MapStyleCatalog._();

  static const List<MapStyleInfo> all = [
    MapStyleInfo(
      style: MapStyle.classic,
      label: 'classic',
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      subdomains: [],
      attribution: '© OpenStreetMap',
    ),
    MapStyleInfo(
      style: MapStyle.paper,
      label: 'paper',
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      attribution: '© OpenStreetMap © CARTO',
    ),
    MapStyleInfo(
      style: MapStyle.night,
      label: 'night',
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      attribution: '© OpenStreetMap © CARTO',
    ),
    MapStyleInfo(
      style: MapStyle.terrain,
      label: 'terrain',
      urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
      attribution: '© OpenStreetMap © OpenTopoMap',
    ),
  ];

  static MapStyleInfo infoFor(MapStyle style) =>
      all.firstWhere((info) => info.style == style, orElse: () => all.first);
}

/// Remembers which [MapStyle] this device is set to — same device-only-
/// preference pattern as [LogThemeService]/[LocaleService]: plain
/// [SharedPreferences], no backend endpoint. One shared setting rather
/// than a separate "for this trip only" choice — changing it from the
/// picker on the route map itself and changing it from Settings are the
/// exact same value, so either place always shows what the other last
/// picked.
class MapStyleService extends ChangeNotifier {
  final _style = PersistedPref<MapStyle>(
    'seenly_map_style',
    defaultValue: MapStyle.classic,
    read: (prefs, key) => MapStyle.values.firstWhere(
      (s) => s.name == prefs.getString(key),
      orElse: () => MapStyle.classic,
    ),
    write: (prefs, key, value) => prefs.setString(key, value.name),
  );

  MapStyle get style => _style.value;
  MapStyleInfo get info => MapStyleCatalog.infoFor(_style.value);

  Future<void> load() async {
    await _style.load();
    notifyListeners();
  }

  Future<void> setStyle(MapStyle value) async {
    await _style.save(value, onChanged: notifyListeners);
  }
}
