/// A single real spaceport somewhere in the world — the shuttle
/// theme's answer to the garden theme's real botanical gardens (see
/// data/garden_tasks.dart) and the coach theme's real city-to-city
/// routes (see data/coach_routes.dart): the whole "journey" happens
/// within the grounds of one real site, a short walk from the public
/// gate out to the viewing area nearest the pad. [minutes] is a
/// curated, real-world estimate of that walk — sized to how big the
/// actual grounds are, not a live pedestrian-routing calculation
/// (Seenly has no routing engine — see journey_real_map.dart's own
/// honesty note).
class LaunchSite {
  final String name;
  final String city;
  final String country;
  final double gateLat;
  final double gateLng;
  final double padLat;
  final double padLng;
  final int minutes;
  const LaunchSite({
    required this.name,
    required this.city,
    required this.country,
    required this.gateLat,
    required this.gateLng,
    required this.padLat,
    required this.padLng,
    required this.minutes,
  });
}

/// A curated, real spread of active spaceports across every continent
/// that launches from one — from a short walk to a nearby viewing
/// mound to grounds too large to see in one visit.
const List<LaunchSite> launchSites = [
  LaunchSite(
    name: 'Kennedy Space Center', city: 'Merritt Island', country: 'United States',
    gateLat: 28.5230, gateLng: -80.6820, padLat: 28.6084, padLng: -80.6043, minutes: 120,
  ),
  LaunchSite(
    name: 'Baikonur Cosmodrome', city: 'Baikonur', country: 'Kazakhstan',
    gateLat: 45.9650, gateLng: 63.3050, padLat: 45.9200, padLng: 63.3422, minutes: 90,
  ),
  LaunchSite(
    name: 'Guiana Space Centre', city: 'Kourou', country: 'French Guiana',
    gateLat: 5.2360, gateLng: -52.7680, padLat: 5.2360, padLng: -52.7756, minutes: 45,
  ),
  LaunchSite(
    name: 'Vandenberg Space Force Base', city: 'Lompoc', country: 'United States',
    gateLat: 34.7420, gateLng: -120.5724, padLat: 34.6321, padLng: -120.6106, minutes: 75,
  ),
  LaunchSite(
    name: 'Tanegashima Space Center', city: 'Minamitane', country: 'Japan',
    gateLat: 30.3913, gateLng: 130.9691, padLat: 30.4008, padLng: 130.9756, minutes: 40,
  ),
  LaunchSite(
    name: 'Jiuquan Satellite Launch Center', city: 'Jiuquan', country: 'China',
    gateLat: 40.9583, gateLng: 100.2913, padLat: 40.9608, padLng: 100.2914, minutes: 60,
  ),
  LaunchSite(
    name: 'Vostochny Cosmodrome', city: 'Tsiolkovsky', country: 'Russia',
    gateLat: 51.8840, gateLng: 128.3330, padLat: 51.8845, padLng: 128.3345, minutes: 30,
  ),
  LaunchSite(
    name: 'Rocket Lab Launch Complex 1', city: 'Māhia', country: 'New Zealand',
    gateLat: -39.2600, gateLng: 177.8600, padLat: -39.2620, padLng: 177.8650, minutes: 25,
  ),
  LaunchSite(
    name: 'Satish Dhawan Space Centre', city: 'Sriharikota', country: 'India',
    gateLat: 13.7199, gateLng: 80.2304, padLat: 13.7330, padLng: 80.2350, minutes: 55,
  ),
  LaunchSite(
    name: 'Alcântara Space Center', city: 'Alcântara', country: 'Brazil',
    gateLat: -2.3730, gateLng: -44.3960, padLat: -2.3750, padLng: -44.4030, minutes: 35,
  ),
];

/// Reasonable session lengths for titles with no runtime on file — same
/// numbers as garden_tasks.dart's own fallback table, kept in sync.
const Map<String, int> _launchFallbackMinutes = {
  'movie': 105,
  'series': 45,
  'anime': 24,
  'game': 150,
  'book': 240,
  'manga': 30,
};

/// Closest spaceports to tonight's runtime, closest first — same
/// closeness-sort as garden_tasks.dart::closestGardens.
List<LaunchSite> closestLaunchSites({required int? runtimeMinutes, required String mediaType, int count = 6}) {
  final effective = runtimeMinutes ?? _launchFallbackMinutes[mediaType] ?? 100;
  final byCloseness = [...launchSites]
    ..sort((a, b) => (a.minutes - effective).abs().compareTo((b.minutes - effective).abs()));
  return byCloseness.take(count).toList();
}
