import 'media_item.dart';
import '../services/log_theme_service.dart';

/// A "watching now" companion journey that's still running.
///
/// [JourneyProgressScreen] used to keep its start time as purely local
/// widget state — the instant someone backed out of that screen (even
/// by accident, tapping the collapse arrow), the whole thing vanished
/// with no way back to it and nothing anywhere in the app to say it
/// was still going. This is that state lifted up to [AppState] instead,
/// so it survives the screen closing: as long as this is set, the
/// journey is still "in progress" and [ActiveJourneyBadge] can surface
/// it from anywhere in the app. Pause/resume lives here too, for the
/// same reason: a pause started on this screen needs to still be a
/// pause when the badge — or later, a "watched now" screen — reads
/// this same object.
class ActiveJourney {
  final MediaItem item;
  final LogTheme theme;
  final String routeLabel;
  final String routeDetail;
  final int routeMinutes;
  // Real coordinates for the coach theme's map — see JourneyRealMap.
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  final DateTime startedAt;
  // When the journey is currently paused, the moment that pause began —
  // null means it's running right now. `pausedDuration` is the total
  // time spent paused *before* this current pause (zero stretches
  // already folded in), so elapsedAt() below only ever needs to add in
  // the one still-open pause, if any, on top of it.
  final DateTime? pausedAt;
  final Duration pausedDuration;
  // Set together only for a series watched at episode granularity — see
  // DiaryEntry's own doc comment on the backend for why this mirrors
  // that same convention. Both null means "this journey is for the
  // title as a whole" (a movie, or a series watched the old way).
  final int? season;
  final int? episode;

  const ActiveJourney({
    required this.item,
    required this.theme,
    required this.routeLabel,
    required this.routeDetail,
    required this.routeMinutes,
    required this.startedAt,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    this.pausedAt,
    this.pausedDuration = Duration.zero,
    this.season,
    this.episode,
  });

  bool get isPaused => pausedAt != null;
  bool get isEpisodeJourney => season != null && episode != null;

  /// Real elapsed time since the journey started, with every paused
  /// stretch subtracted out — the one place this math happens, so
  /// [JourneyProgressScreen], [ActiveJourneyBadge], and the "watching
  /// now" screen all agree on the same number instead of each computing
  /// their own version of "how long has this actually been going".
  /// While currently paused, this stays frozen no matter how much
  /// wall-clock time passes, since the still-open pause grows exactly
  /// as fast as `now - startedAt` does.
  Duration elapsedAt(DateTime now) {
    final pausedSoFar =
        pausedAt == null ? pausedDuration : pausedDuration + now.difference(pausedAt!);
    return now.difference(startedAt) - pausedSoFar;
  }

  ActiveJourney copyWith({
    DateTime? pausedAt,
    bool clearPausedAt = false,
    Duration? pausedDuration,
  }) {
    return ActiveJourney(
      item: item,
      theme: theme,
      routeLabel: routeLabel,
      routeDetail: routeDetail,
      routeMinutes: routeMinutes,
      startedAt: startedAt,
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
      pausedDuration: pausedDuration ?? this.pausedDuration,
      season: season,
      episode: episode,
    );
  }
}
