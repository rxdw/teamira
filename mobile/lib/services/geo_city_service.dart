import 'dart:convert';
import 'package:http/http.dart' as http;

/// A city resolved from OpenStreetMap — either typed in by the person
/// (Nominatim search) or found near another city (Overpass "nearby").
class GeoCity {
  final String name;
  final String? country;
  final double lat;
  final double lng;
  const GeoCity({required this.name, this.country, required this.lat, required this.lng});

  @override
  String toString() => name;
}

/// City search + "what's actually nearby" backed by OpenStreetMap's free,
/// keyless public APIs — real place data instead of a short hardcoded
/// list, so "from" genuinely covers any city in the world and "departing
/// soon" reflects what's actually close to it (a small town 40 minutes
/// from Moscow, say, rather than jumping straight to Saint Petersburg
/// because that's the only other place on file).
class GeoCityService {
  static const _nominatimBase = 'https://nominatim.openstreetmap.org';
  static const _overpassBase = 'https://overpass-api.de/api/interpreter';

  // Nominatim's usage policy requires a real, identifying User-Agent on
  // every request — this isn't optional, unrecognized/anonymous clients
  // get blocked.
  static const _headers = {'User-Agent': 'SeenlyApp/1.0 (evening diary app)'};

  /// Free-text place search for the "from" city picker — typing "Any
  /// city, anywhere" and getting real matches back, not a lookup
  /// against a fixed list.
  static Future<List<GeoCity>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final uri = Uri.parse('$_nominatimBase/search').replace(queryParameters: {
      'q': q,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '15',
    });
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      final seen = <String>{};
      final out = <GeoCity>[];
      for (final e in list) {
        final map = e as Map<String, dynamic>;
        final addr = map['address'] as Map<String, dynamic>? ?? const {};
        final placeClass = map['class']?.toString();
        // Keep this to actual settlements, not landmarks/streets/etc.
        if (placeClass != 'place' && placeClass != 'boundary') continue;
        final name = (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['municipality'] ?? map['name'])
            ?.toString();
        if (name == null || name.isEmpty) continue;
        final country = addr['country']?.toString();
        final key = '$name|$country';
        if (!seen.add(key)) continue;
        final lat = double.tryParse(map['lat']?.toString() ?? '');
        final lng = double.tryParse(map['lon']?.toString() ?? '');
        if (lat == null || lng == null) continue;
        out.add(GeoCity(name: name, country: country, lat: lat, lng: lng));
      }
      return out;
    } catch (_) {
      // Offline, DNS failure, Nominatim rate-limit, etc — caller falls
      // back to the bundled local city list.
      return [];
    }
  }

  /// Real towns/cities within [radiusKm] of a point, via Overpass —
  /// used to build the "departing soon" list around whatever "from" is
  /// currently set to.
  static Future<List<GeoCity>> nearby(double lat, double lng, {required double radiusKm, int limit = 80}) async {
    final radiusM = (radiusKm * 1000).round();
    final query = '[out:json][timeout:20];'
        'node(around:$radiusM,$lat,$lng)["place"~"^(city|town)\$"]["name"];'
        'out body $limit;';
    try {
      final res = await http
          .post(Uri.parse(_overpassBase), headers: _headers, body: {'data': query})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List?) ?? const [];
      final seen = <String>{};
      final out = <GeoCity>[];
      for (final e in elements) {
        final map = e as Map<String, dynamic>;
        final tags = map['tags'] as Map<String, dynamic>? ?? const {};
        final name = (tags['name:en'] ?? tags['name'])?.toString();
        final elLat = (map['lat'] as num?)?.toDouble();
        final elLng = (map['lon'] as num?)?.toDouble();
        if (name == null || name.isEmpty || elLat == null || elLng == null) continue;
        if (!seen.add(name)) continue;
        out.add(GeoCity(name: name, lat: elLat, lng: elLng));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// [nearby] with the search radius widened in steps until enough
  /// candidates turn up (or the radius gives up) — a city with a sparse
  /// immediate area (small hometown, remote region) still gets a real
  /// answer instead of an empty list.
  static Future<List<GeoCity>> nearbyExpanding(
    double lat,
    double lng, {
    List<double> stepsKm = const [60, 150, 300, 600, 1200, 2500],
    int minResults = 8,
    int limit = 80,
  }) async {
    List<GeoCity> best = const [];
    for (final radius in stepsKm) {
      final found = await nearby(lat, lng, radiusKm: radius, limit: limit);
      if (found.length >= minResults) return found;
      if (found.length > best.length) best = found;
    }
    return best;
  }
}
