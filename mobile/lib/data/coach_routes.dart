import 'dart:math' as math;

import '../services/geo_city_service.dart';
import 'world_cities.dart';

/// A single coach route: two real cities roughly this many minutes
/// apart by road — the raw material for "Evening Route"'s conceit that
/// tonight's runtime is also tonight's trip.
class CoachRoute {
  final String originCity;
  final String originCode; // 3-letter station code, boarding-pass style
  final String destCity;
  final String destCode;
  final int minutes;
  // Real coordinates, when known — lets the "watching now" progress
  // screen draw an actual OpenStreetMap between the two instead of a
  // decorative curve. Null for the curated list's rare unmatched name;
  // the progress screen falls back to the decorative curve in that case.
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;

  const CoachRoute({
    required this.originCity,
    required this.originCode,
    required this.destCity,
    required this.destCode,
    required this.minutes,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
  });

  bool get hasRealCoords => originLat != null && originLng != null && destLat != null && destLng != null;
}

/// A modest, real-world spread of coach routes from about 45 minutes to
/// a little over four hours — enough range to give almost any runtime a
/// plausible match without ever needing to invent a route out of thin
/// air. Durations are the kind of ballpark a coach timetable would
/// print, not guaranteed-exact — the point is a plausible evening
/// out-and-back, not a real booking.
const List<CoachRoute> _coachRoutes = [
  CoachRoute(originCity: 'Copenhagen', originCode: 'CPH', destCity: 'Malmö', destCode: 'MMA', minutes: 45),
  CoachRoute(originCity: 'Stockholm', originCode: 'STO', destCity: 'Uppsala', destCode: 'UPP', minutes: 50),
  CoachRoute(originCity: 'Frankfurt', originCode: 'FRA', destCity: 'Mannheim', destCode: 'MAN', minutes: 55),
  CoachRoute(originCity: 'Basel', originCode: 'BAS', destCity: 'Zürich', destCode: 'ZRH', minutes: 60),
  CoachRoute(originCity: 'Porto', originCode: 'OPO', destCity: 'Braga', destCode: 'BRG', minutes: 60),
  CoachRoute(originCity: 'Edinburgh', originCode: 'EDI', destCity: 'Glasgow', destCode: 'GLA', minutes: 65),
  CoachRoute(originCity: 'Florence', originCode: 'FLR', destCity: 'Bologna', destCode: 'BLQ', minutes: 65),
  CoachRoute(originCity: 'Rotterdam', originCode: 'RTM', destCity: 'Antwerp', destCode: 'ANR', minutes: 70),
  CoachRoute(originCity: 'Belgrade', originCode: 'BEG', destCity: 'Novi Sad', destCode: 'NVS', minutes: 70),
  CoachRoute(originCity: 'Vienna', originCode: 'VIE', destCity: 'Bratislava', destCode: 'BTS', minutes: 75),
  CoachRoute(originCity: 'Kraków', originCode: 'KRK', destCity: 'Katowice', destCode: 'KAT', minutes: 80),
  CoachRoute(originCity: 'Barcelona', originCode: 'BCN', destCity: 'Girona', destCode: 'GRO', minutes: 90),
  CoachRoute(originCity: 'Hamburg', originCode: 'HAM', destCity: 'Bremen', destCode: 'BRE', minutes: 95),
  CoachRoute(originCity: 'Turin', originCode: 'TRN', destCity: 'Genoa', destCode: 'GOA', minutes: 100),
  CoachRoute(originCity: 'Milan', originCode: 'MIL', destCity: 'Turin', destCode: 'TRN', minutes: 100),
  CoachRoute(originCity: 'Munich', originCode: 'MUC', destCity: 'Salzburg', destCode: 'SZG', minutes: 105),
  CoachRoute(originCity: 'Warsaw', originCode: 'WAW', destCity: 'Łódź', destCode: 'LDZ', minutes: 105),
  CoachRoute(originCity: 'Lyon', originCode: 'LYS', destCity: 'Geneva', destCode: 'GVA', minutes: 110),
  CoachRoute(originCity: 'Dublin', originCode: 'DUB', destCity: 'Belfast', destCode: 'BFS', minutes: 120),
  CoachRoute(originCity: 'Berlin', originCode: 'BER', destCity: 'Dresden', destCode: 'DRS', minutes: 130),
  CoachRoute(originCity: 'Sofia', originCode: 'SOF', destCity: 'Plovdiv', destCode: 'PDV', minutes: 130),
  CoachRoute(originCity: 'Bordeaux', originCode: 'BOD', destCity: 'Toulouse', destCode: 'TLS', minutes: 145),
  CoachRoute(originCity: 'Zagreb', originCode: 'ZAG', destCity: 'Ljubljana', destCode: 'LJU', minutes: 140),
  CoachRoute(originCity: 'Nice', originCode: 'NCE', destCity: 'Marseille', destCode: 'MRS', minutes: 150),
  CoachRoute(originCity: 'Prague', originCode: 'PRG', destCity: 'Brno', destCode: 'BRQ', minutes: 150),
  CoachRoute(originCity: 'Naples', originCode: 'NAP', destCity: 'Rome', destCode: 'ROM', minutes: 160),
  CoachRoute(originCity: 'Budapest', originCode: 'BUD', destCity: 'Vienna', destCode: 'VIE', minutes: 165),
  CoachRoute(originCity: 'Valencia', originCode: 'VLC', destCity: 'Alicante', destCode: 'ALC', minutes: 165),
  CoachRoute(originCity: 'Amsterdam', originCode: 'AMS', destCity: 'Brussels', destCode: 'BRU', minutes: 175),
  CoachRoute(originCity: 'Vilnius', originCode: 'VNO', destCity: 'Riga', destCode: 'RIX', minutes: 260),
];

/// [_coachRoutes], but each pair stamped with the real coordinates of
/// both cities (looked up from [worldCities], which every curated name
/// above matches) — computed once, not on every call, since the
/// underlying list never changes at runtime.
final List<CoachRoute> _coachRoutesWithCoords = _coachRoutes.map((r) {
  final origin = findCityByName(r.originCity);
  final dest = findCityByName(r.destCity);
  return CoachRoute(
    originCity: r.originCity,
    originCode: r.originCode,
    destCity: r.destCity,
    destCode: r.destCode,
    minutes: r.minutes,
    originLat: origin.lat,
    originLng: origin.lng,
    destLat: dest.lat,
    destLng: dest.lng,
  );
}).toList();

/// Reasonable session lengths to fall back on when a title has no
/// runtime on file (common for series, games, books) — just enough to
/// still hand the route-matcher something plausible to work with.
const Map<String, int> _fallbackMinutes = {
  'movie': 105,
  'series': 45,
  'anime': 24,
  'game': 150,
  'book': 240,
  'manga': 30,
};

/// Picks a real coach route whose duration lands close to tonight's
/// runtime — the three closest matches, then one of those three chosen
/// by a seed (the title), so the same runtime doesn't always hand back
/// the exact same city pair.
CoachRoute routeForRuntime({required int? runtimeMinutes, required String mediaType, required Object seed}) {
  final effective = runtimeMinutes ?? _fallbackMinutes[mediaType] ?? 100;
  final byCloseness = [..._coachRoutesWithCoords]
    ..sort((a, b) => (a.minutes - effective).abs().compareTo((b.minutes - effective).abs()));
  final pool = byCloseness.take(3).toList();
  final r = math.Random(seed.hashCode);
  return pool[r.nextInt(pool.length)];
}

/// Same real dataset, but for the "watching now" route picker (see
/// screens/add_entry/journey_select_screen.dart) rather than the
/// post-log reveal above — that one hands back a single surprise pick,
/// this one hands back a short list so the person can actually choose
/// which route to ride while the film plays. Sorted by closeness to
/// tonight's runtime, closest first.
List<CoachRoute> closestRoutes({required int? runtimeMinutes, required String mediaType, int count = 6}) {
  final effective = runtimeMinutes ?? _fallbackMinutes[mediaType] ?? 100;
  final byCloseness = [..._coachRoutesWithCoords]
    ..sort((a, b) => (a.minutes - effective).abs().compareTo((b.minutes - effective).abs()));
  return byCloseness.take(count).toList();
}

/// Same idea as [closestRoutes], but "from" is any city rather than a
/// fixed list of curated pairs. This is the **offline fallback** —
/// destinations come from the small bundled [worldCities] list, used
/// only when [closestRoutesFromCityLive]'s live OpenStreetMap lookup
/// comes back empty (no network, API hiccup, etc). Duration is
/// estimated from great-circle distance (see world_cities.dart) rather
/// than looked up, so it's a ballpark, same as the curated dataset
/// above.
List<CoachRoute> closestRoutesFromCity({
  required GeoCity origin,
  required int? runtimeMinutes,
  required String mediaType,
  int count = 6,
}) {
  final effective = runtimeMinutes ?? _fallbackMinutes[mediaType] ?? 100;
  final candidates = worldCities.where((c) => c.name != origin.name).map((c) {
    final km = _distanceKmRaw(origin.lat, origin.lng, c.lat, c.lng);
    final minutes = estimateMinutesForDistance(km);
    return CoachRoute(
      originCity: origin.name,
      originCode: origin.name.length >= 3 ? origin.name.substring(0, 3).toUpperCase() : origin.name.toUpperCase(),
      destCity: c.name,
      destCode: c.name.length >= 3 ? c.name.substring(0, 3).toUpperCase() : c.name.toUpperCase(),
      minutes: minutes,
      originLat: origin.lat,
      originLng: origin.lng,
      destLat: c.lat,
      destLng: c.lng,
    );
  }).toList()
    ..sort((a, b) => (a.minutes - effective).abs().compareTo((b.minutes - effective).abs()));
  return candidates.take(count).toList();
}

/// The real, API-backed version: pulls actual nearby towns/cities from
/// OpenStreetMap around [origin] (widening the search radius until
/// there's a reasonable spread of candidates — see
/// [GeoCityService.nearbyExpanding]) and picks the ones whose estimated
/// travel time is closest to tonight's runtime. This is why a origin
/// with few big neighbours (Moscow, say) still gets a dense set of
/// genuinely nearby options instead of jumping straight to a city
/// hours away — it isn't limited to whatever happens to be in the
/// bundled dataset. Falls back to [closestRoutesFromCity] (the small
/// local dataset) if the live lookup fails or the device is offline.
Future<List<CoachRoute>> closestRoutesFromCityLive({
  required GeoCity origin,
  required int? runtimeMinutes,
  required String mediaType,
  int count = 6,
}) async {
  final effective = runtimeMinutes ?? _fallbackMinutes[mediaType] ?? 100;
  final nearby = await GeoCityService.nearbyExpanding(origin.lat, origin.lng);
  final realCandidates = nearby.where((c) => c.name.toLowerCase() != origin.name.toLowerCase()).toList();

  if (realCandidates.isEmpty) {
    return closestRoutesFromCity(origin: origin, runtimeMinutes: runtimeMinutes, mediaType: mediaType, count: count);
  }

  final routes = realCandidates.map((c) {
    final km = _distanceKmRaw(origin.lat, origin.lng, c.lat, c.lng);
    final minutes = estimateMinutesForDistance(km);
    return CoachRoute(
      originCity: origin.name,
      originCode: origin.name.length >= 3 ? origin.name.substring(0, 3).toUpperCase() : origin.name.toUpperCase(),
      destCity: c.name,
      destCode: c.name.length >= 3 ? c.name.substring(0, 3).toUpperCase() : c.name.toUpperCase(),
      minutes: minutes,
      originLat: origin.lat,
      originLng: origin.lng,
      destLat: c.lat,
      destLng: c.lng,
    );
  }).toList()
    ..sort((a, b) => (a.minutes - effective).abs().compareTo((b.minutes - effective).abs()));

  // A handful of real nearby places can repeat similar durations —
  // dedupe by rounded minutes isn't worth it here, closeness sort
  // already surfaces the best spread within `count`.
  return routes.take(count).toList();
}

double _distanceKmRaw(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = (lat2 - lat1) * (math.pi / 180);
  final dLng = (lng2 - lng1) * (math.pi / 180);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(lat1 * (math.pi / 180)) * math.cos(lat2 * (math.pi / 180));
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}
