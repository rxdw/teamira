import '../data/cinema_showtimes.dart';
import '../data/coach_routes.dart';
import '../data/garden_tasks.dart';
import '../models/media_item.dart';
import '../models/series_route_state.dart';
import '../services/geo_city_service.dart';
import '../services/log_theme_service.dart';

String _fmtDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

const Map<String, int> _runtimeFallback = {
  'movie': 105, 'series': 45, 'anime': 24, 'game': 150, 'book': 240, 'manga': 30,
};

// A few decorative alley names for the garden theme's transfer, purely
// flavor text (see JourneyTransfer.garden below) — Seenly has no
// real multi-zone garden data, just one gate→inner-point walk per
// garden (see data/garden_tasks.dart), so "a different part of the
// grounds" is dressing on top of that same one walk, not a distinct
// real path.
const List<String> _gardenAlleys = [
  'the rose walk',
  'the shaded path',
  'the water garden',
  'the arboretum trail',
  'the sunken garden',
  'the old orchard row',
];

/// The next leg of a route, ready to hand straight to
/// [JourneyProgressScreen] — the whole point of a transfer is skipping
/// the picker, so this is already a finished decision, not options to
/// choose between.
class JourneyTransfer {
  final String routeLabel;
  final String routeDetail;
  final int routeMinutes;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  // Same meaning as SeriesRouteState.matchKey — what this leg's own
  // finish should be saved under as the *next* transfer's stop.
  final String destMatchKey;
  const JourneyTransfer({
    required this.routeLabel,
    required this.routeDetail,
    required this.routeMinutes,
    required this.destMatchKey,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
  });
}

int _effectiveMinutes(MediaItem item) => item.runtimeMinutes ?? _runtimeFallback[item.mediaType] ?? 100;

/// Builds the transfer leg for the next episode, given where the
/// previous one left off. Returns null only if the saved stop can no
/// longer be resolved (a cinema/garden that's since dropped out of the
/// curated list, say) — callers fall back to the full picker in that
/// case, same as if nothing had been saved at all.
Future<JourneyTransfer?> buildTransfer({
  required SeriesRouteState state,
  required MediaItem item,
}) async {
  switch (state.theme) {
    case LogTheme.coach:
      return _coachTransfer(state, item);
    case LogTheme.ticket:
      return _ticketTransfer(state, item);
    case LogTheme.garden:
      return _gardenTransfer(state, item);
  }
}

/// Train: the "next real station" reading of a transfer — the previous
/// leg's arrival city becomes this leg's departure city, and from
/// there it's the same closest-real-route matching the picker itself
/// uses (see journey_select_screen.dart), just auto-picking the single
/// closest match instead of presenting a list, since a transfer isn't
/// meant to be a fresh decision.
Future<JourneyTransfer?> _coachTransfer(SeriesRouteState state, MediaItem item) async {
  if (state.matchKey == null || state.lat == null || state.lng == null) return null;
  final origin = GeoCity(name: state.matchKey!, country: null, lat: state.lat!, lng: state.lng!);
  var routes = <CoachRoute>[];
  try {
    // Bounded to 6s regardless of how many of nearbyExpanding's own
    // radius steps are still pending — without this, a slow/overloaded
    // Overpass server can leave someone staring at an unresponsive
    // screen for as long as ~90s (nearbyExpanding tries up to 6 radii,
    // each with its own 15s timeout — see geo_city_service.dart) after
    // tapping "yes, continue", which reads as the button doing nothing.
    // The local dataset fallback right below is instant and always
    // available, so there's no reason a stalled live lookup should
    // hold up a continuation this long — a first-time route pick (via
    // JourneySelectScreen) can afford to wait longer for the real data
    // since that screen shows its own loading state either way.
    routes = await closestRoutesFromCityLive(
      origin: origin, runtimeMinutes: item.runtimeMinutes, mediaType: item.mediaType, count: 1,
    ).timeout(const Duration(seconds: 6));
  } catch (_) {
    routes = const [];
  }
  if (routes.isEmpty) {
    routes = closestRoutesFromCity(
      origin: origin, runtimeMinutes: item.runtimeMinutes, mediaType: item.mediaType, count: 1,
    );
  }
  if (routes.isEmpty) return null;
  final r = routes.first;
  return JourneyTransfer(
    routeLabel: '${origin.name} → ${r.destCity}',
    routeDetail: '${_fmtDuration(r.minutes)} on the rails · transfer at ${origin.name}',
    routeMinutes: r.minutes,
    destMatchKey: r.destCity,
    originLat: origin.lat,
    originLng: origin.lng,
    destLat: r.destLat,
    destLng: r.destLng,
  );
}

/// Plane/cinema: explicitly *not* a new flight — the whole season plays
/// out in the same hall (see the class-level spec this was built from),
/// so this just reuses the exact same [CinemaDestination] by its code,
/// framed as the next showing rather than a fresh trip.
JourneyTransfer? _ticketTransfer(SeriesRouteState state, MediaItem item) {
  CinemaDestination? cinema;
  for (final c in cinemaDestinations) {
    if (c.code == state.matchKey) {
      cinema = c;
      break;
    }
  }
  if (cinema == null) return null;
  return JourneyTransfer(
    routeLabel: '${cinema.name}, ${cinema.city}',
    routeDetail: 'next showing, same hall',
    routeMinutes: _effectiveMinutes(item),
    destMatchKey: cinema.code,
    destLat: cinema.lat,
    destLng: cinema.lng,
  );
}

/// Garden: same garden, not a new one — see [_gardenAlleys]'s own note
/// for why the "different alley" framing is flavor text rather than a
/// distinct real path (Seenly only has one gate→inner walk per garden).
JourneyTransfer? _gardenTransfer(SeriesRouteState state, MediaItem item) {
  GardenDestination? garden;
  for (final g in gardenDestinations) {
    if (g.name == state.matchKey) {
      garden = g;
      break;
    }
  }
  if (garden == null) return null;
  final alley = _gardenAlleys[state.episode % _gardenAlleys.length];
  return JourneyTransfer(
    routeLabel: '$alley, ${garden.name}',
    routeDetail: '${_fmtDuration(_effectiveMinutes(item))} walk · back through ${garden.city}',
    routeMinutes: _effectiveMinutes(item),
    destMatchKey: garden.name,
    originLat: garden.gateLat,
    originLng: garden.gateLng,
    destLat: garden.innerLat,
    destLng: garden.innerLng,
  );
}
