import 'dart:math' as math;

import '../services/geo_city_service.dart';

/// A single real, culturally iconic cinema somewhere in the world — the
/// ticket theme's answer to the coach theme's real city-to-city routes
/// (see data/coach_routes.dart), except the "route" here is a flight to
/// go and actually see something there. Coordinates aim at the venue
/// itself; for a few of these that's necessarily a close approximation
/// rather than a surveyed address, same honesty caveat coach_routes.dart
/// already carries for its own durations.
class CinemaDestination {
  final String name;
  final String city;
  final String country;
  final String code; // 3-letter airport-style code, boarding-pass style
  final double lat;
  final double lng;
  const CinemaDestination({
    required this.name,
    required this.city,
    required this.country,
    required this.code,
    required this.lat,
    required this.lng,
  });
}

/// A curated, real spread of culturally iconic cinemas across every
/// inhabited continent — the kind of place worth actually flying to see
/// something at.
const List<CinemaDestination> cinemaDestinations = [
  CinemaDestination(name: 'TCL Chinese Theatre', city: 'Los Angeles', country: 'United States', code: 'LAX', lat: 34.1022, lng: -118.3406),
  CinemaDestination(name: 'Radio City Music Hall', city: 'New York', country: 'United States', code: 'NYC', lat: 40.7600, lng: -73.9800),
  CinemaDestination(name: 'Odeon Leicester Square', city: 'London', country: 'United Kingdom', code: 'LON', lat: 51.5108, lng: -0.1305),
  CinemaDestination(name: 'Le Grand Rex', city: 'Paris', country: 'France', code: 'PAR', lat: 48.8706, lng: 2.3487),
  CinemaDestination(name: 'Zoo Palast', city: 'Berlin', country: 'Germany', code: 'BER', lat: 52.5049, lng: 13.3325),
  CinemaDestination(name: 'Cinema Barberini', city: 'Rome', country: 'Italy', code: 'ROM', lat: 41.9038, lng: 12.4880),
  CinemaDestination(name: 'TOHO Cinemas Shinjuku', city: 'Tokyo', country: 'Japan', code: 'TYO', lat: 35.6952, lng: 139.7016),
  CinemaDestination(name: 'Busan Cinema Center', city: 'Busan', country: 'South Korea', code: 'PUS', lat: 35.1685, lng: 129.1298),
  CinemaDestination(name: 'Raj Mandir Cinema', city: 'Jaipur', country: 'India', code: 'JAI', lat: 26.9147, lng: 75.7873),
  CinemaDestination(name: 'The Projector', city: 'Singapore', country: 'Singapore', code: 'SIN', lat: 1.3006, lng: 103.8631),
  CinemaDestination(name: 'State Theatre', city: 'Sydney', country: 'Australia', code: 'SYD', lat: -33.8698, lng: 151.2082),
  CinemaDestination(name: 'The Astor Theatre', city: 'Melbourne', country: 'Australia', code: 'MEL', lat: -37.8590, lng: 144.9910),
  CinemaDestination(name: 'Cineteca Nacional', city: 'Mexico City', country: 'Mexico', code: 'MEX', lat: 19.3559, lng: -99.1633),
  CinemaDestination(name: 'Gran Rex', city: 'Buenos Aires', country: 'Argentina', code: 'BUE', lat: -34.6034, lng: -58.3781),
  CinemaDestination(name: 'Elgin and Winter Garden Theatre', city: 'Toronto', country: 'Canada', code: 'YTO', lat: 43.6534, lng: -79.3789),
  CinemaDestination(name: 'The Labia Theatre', city: 'Cape Town', country: 'South Africa', code: 'CPT', lat: -33.9280, lng: 18.4130),
];

/// One real flight, priced out in minutes rather than money: a curated
/// cinema, paired with the flight time to get there from wherever
/// "from" is currently set to.
class CinemaOption {
  final CinemaDestination cinema;
  final int minutes;
  const CinemaOption({required this.cinema, required this.minutes});
}

/// Reasonable session lengths for titles with no runtime on file — same
/// numbers as coach_routes.dart's own fallback table, kept in sync.
const Map<String, int> _cinemaFallbackMinutes = {
  'movie': 105,
  'series': 45,
  'anime': 24,
  'game': 150,
  'book': 240,
  'manga': 30,
};

double _distanceKmRaw(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = (lat2 - lat1) * (math.pi / 180);
  final dLng = (lng2 - lng1) * (math.pi / 180);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(lat1 * (math.pi / 180)) * math.cos(lat2 * (math.pi / 180));
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

/// A plausible real-world flight duration for a distance — average
/// commercial cruise speed, plus fixed overhead for check-in, security,
/// boarding, taxi, and climb/descent that a real trip would carry even
/// on a short hop. Ballpark, not a booking — same honesty caveat
/// world_cities.dart's own coach-speed estimate carries.
int estimateFlightMinutes(double km) {
  const cruiseSpeedKmh = 800.0;
  const groundOverheadMinutes = 105;
  final minutes = (km / cruiseSpeedKmh * 60).round() + groundOverheadMinutes;
  return minutes < 70 ? 70 : minutes;
}

/// Closest flights to tonight's runtime, closest first — same
/// closeness-sort as coach_routes.dart::closestRoutes, just measured in
/// flight time from [origin] instead of a fixed table.
List<CinemaOption> closestCinemas({
  required GeoCity origin,
  required int? runtimeMinutes,
  required String mediaType,
  int count = 6,
}) {
  final effective = runtimeMinutes ?? _cinemaFallbackMinutes[mediaType] ?? 100;
  final options = cinemaDestinations
      .where((c) => c.city.toLowerCase() != origin.name.toLowerCase())
      .map((c) => CinemaOption(
            cinema: c,
            minutes: estimateFlightMinutes(_distanceKmRaw(origin.lat, origin.lng, c.lat, c.lng)),
          ))
      .toList()
    ..sort((a, b) => (a.minutes - effective).abs().compareTo((b.minutes - effective).abs()));
  return options.take(count).toList();
}
