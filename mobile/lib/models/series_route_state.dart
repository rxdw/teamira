import '../services/log_theme_service.dart';

/// Snapshot of where a series' journey left off, written once an
/// episode's journey finishes (see JourneyProgressScreen._imBack) and
/// read the next time someone starts watching an episode of the same
/// series (see the continuation dialog in journey_select_screen.dart).
/// Persisted on-device via [SeriesRoutePrefsService] — same
/// on-device-only, no-backend-endpoint pattern as JourneyPrefsService,
/// since this is scratch continuity dressing, not account data worth a
/// sync round-trip.
///
/// What "where it left off" means is theme-specific:
/// - coach: the city the train just pulled into — the next episode's
///   journey departs *from* here rather than back from the person's own
///   home city (see coach_routes.dart's `closestRoutesFromCity`, reused
///   with this as the origin).
/// - ticket: the cinema itself — the next episode doesn't fly anywhere
///   new, it's a repeat showing in the same hall, so [matchKey] (the
///   cinema's own code) is all that actually matters here.
/// - garden: the garden itself, same idea as ticket — no new garden
///   gets chosen, just a fresh lap through it.
class SeriesRouteState {
  final LogTheme theme;
  final int season;
  final int episode; // the last episode actually finished
  final DateTime finishedAt;
  final String stopLabel; // human-readable: city / cinema / garden name
  // Theme-specific lookup key for reconstructing the exact same place:
  // coach → the city name itself (fed into closestRoutesFromCity as the
  // new origin); ticket → the cinema's own code; garden → the garden's
  // own name. Kept as a single loosely-typed field rather than three
  // separate ones since exactly one is ever relevant for a given theme.
  final String? matchKey;
  final double? lat;
  final double? lng;

  const SeriesRouteState({
    required this.theme,
    required this.season,
    required this.episode,
    required this.finishedAt,
    required this.stopLabel,
    this.matchKey,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'season': season,
        'episode': episode,
        'finished_at': finishedAt.toIso8601String(),
        'stop_label': stopLabel,
        'match_key': matchKey,
        'lat': lat,
        'lng': lng,
      };

  factory SeriesRouteState.fromJson(Map<String, dynamic> json) => SeriesRouteState(
        theme: LogTheme.values.firstWhere(
          (t) => t.name == json['theme'],
          orElse: () => LogTheme.coach,
        ),
        season: json['season'] as int,
        episode: json['episode'] as int,
        finishedAt: DateTime.parse(json['finished_at'] as String),
        stopLabel: json['stop_label'] as String,
        matchKey: json['match_key'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );
}
