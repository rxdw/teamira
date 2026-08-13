/// A single real botanical garden or park somewhere in the world — the
/// garden theme's answer to the coach theme's real city-to-city routes
/// (see data/coach_routes.dart), except the whole "route" happens
/// inside the grounds of one real place: a walk from the main gate to
/// somewhere worth reaching inside it. [minutes] is a curated,
/// real-world estimate of that walk — sized to how big the actual
/// grounds are, the same kind of ballpark a walking-tour leaflet would
/// print, not a live pedestrian-routing calculation (Seenly has no
/// routing engine — see journey_real_map.dart's own honesty note).
class GardenDestination {
  final String name;
  final String city;
  final String country;
  final double gateLat;
  final double gateLng;
  final double innerLat;
  final double innerLng;
  final int minutes;
  const GardenDestination({
    required this.name,
    required this.city,
    required this.country,
    required this.gateLat,
    required this.gateLng,
    required this.innerLat,
    required this.innerLng,
    required this.minutes,
  });
}

/// A curated, real spread of botanical gardens and gardened parks
/// across every inhabited continent — from a rock garden you can sit
/// with in twenty minutes to grounds too large to see in one visit.
const List<GardenDestination> gardenDestinations = [
  GardenDestination(
    name: 'Kew Gardens', city: 'London', country: 'United Kingdom',
    gateLat: 51.4787, gateLng: -0.2957, innerLat: 51.4816, innerLng: -0.2879, minutes: 105,
  ),
  GardenDestination(
    name: 'Gardens of Versailles', city: 'Versailles', country: 'France',
    gateLat: 48.8048, gateLng: 2.1203, innerLat: 48.8090, innerLng: 2.1064, minutes: 140,
  ),
  GardenDestination(
    name: 'Ryōan-ji Rock Garden', city: 'Kyoto', country: 'Japan',
    gateLat: 35.0341, gateLng: 135.7183, innerLat: 35.0345, innerLng: 135.7188, minutes: 25,
  ),
  GardenDestination(
    name: 'Boboli Gardens', city: 'Florence', country: 'Italy',
    gateLat: 43.7649, gateLng: 11.2500, innerLat: 43.7615, innerLng: 11.2530, minutes: 75,
  ),
  GardenDestination(
    name: 'Butchart Gardens', city: 'Victoria', country: 'Canada',
    gateLat: 48.5628, gateLng: -123.4680, innerLat: 48.5645, innerLng: -123.4715, minutes: 60,
  ),
  GardenDestination(
    name: 'Keukenhof', city: 'Lisse', country: 'Netherlands',
    gateLat: 52.2696, gateLng: 4.5473, innerLat: 52.2735, innerLng: 4.5510, minutes: 90,
  ),
  GardenDestination(
    name: 'Singapore Botanic Gardens', city: 'Singapore', country: 'Singapore',
    gateLat: 1.3138, gateLng: 103.8159, innerLat: 1.3225, innerLng: 103.8158, minutes: 100,
  ),
  GardenDestination(
    name: 'Nong Nooch Tropical Garden', city: 'Pattaya', country: 'Thailand',
    gateLat: 12.7333, gateLng: 100.9333, innerLat: 12.7280, innerLng: 100.9390, minutes: 110,
  ),
  GardenDestination(
    name: "Claude Monet's Garden", city: 'Giverny', country: 'France',
    gateLat: 49.0755, gateLng: 1.5346, innerLat: 49.0748, innerLng: 1.5325, minutes: 45,
  ),
  GardenDestination(
    name: "Villa d'Este Gardens", city: 'Tivoli', country: 'Italy',
    gateLat: 41.9629, gateLng: 12.7955, innerLat: 41.9615, innerLng: 12.7935, minutes: 60,
  ),
  GardenDestination(
    name: 'Golden Gate Park Conservatory', city: 'San Francisco', country: 'United States',
    gateLat: 37.7715, gateLng: -122.4605, innerLat: 37.7690, innerLng: -122.4530, minutes: 80,
  ),
  GardenDestination(
    name: 'Jardins de Marqueyssac', city: 'Vézac', country: 'France',
    gateLat: 44.8395, gateLng: 1.1875, innerLat: 44.8410, innerLng: 1.1830, minutes: 55,
  ),
  GardenDestination(
    name: 'Ninfa Garden', city: 'Cisterna di Latina', country: 'Italy',
    gateLat: 41.5450, gateLng: 12.9685, innerLat: 41.5470, innerLng: 12.9650, minutes: 70,
  ),
  GardenDestination(
    name: 'Shalimar Bagh', city: 'Srinagar', country: 'India',
    gateLat: 34.1264, gateLng: 74.8797, innerLat: 34.1290, innerLng: 74.8815, minutes: 40,
  ),
];

/// Reasonable session lengths for titles with no runtime on file — same
/// numbers as coach_routes.dart's own fallback table, kept in sync.
const Map<String, int> _gardenFallbackMinutes = {
  'movie': 105,
  'series': 45,
  'anime': 24,
  'game': 150,
  'book': 240,
  'manga': 30,
};

/// Closest gardens to tonight's runtime, closest first — same
/// closeness-sort as coach_routes.dart::closestRoutes.
List<GardenDestination> closestGardens({required int? runtimeMinutes, required String mediaType, int count = 6}) {
  final effective = runtimeMinutes ?? _gardenFallbackMinutes[mediaType] ?? 100;
  final byCloseness = [...gardenDestinations]
    ..sort((a, b) => (a.minutes - effective).abs().compareTo((b.minutes - effective).abs()));
  return byCloseness.take(count).toList();
}
