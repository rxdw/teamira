/// Mirrors backend/app/schemas.py: EpisodeOut, SeasonOut, EpisodesOut.

class Episode {
  final int season;
  final int episode;
  final String? title;

  const Episode({required this.season, required this.episode, this.title});

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        season: json['season'] as int,
        episode: json['episode'] as int,
        title: json['title'] as String?,
      );

  String get key => '$season:$episode';
}

class Season {
  final int season;
  final List<Episode> episodes;
  // From TMDB, best-effort — see backend/app/adapters/tmdb.py::season_posters.
  // Null when TMDB has no id match or no poster for this particular season.
  final String? posterUrl;

  const Season({required this.season, required this.episodes, this.posterUrl});

  factory Season.fromJson(Map<String, dynamic> json) => Season(
        season: json['season'] as int,
        episodes: (json['episodes'] as List)
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
        posterUrl: json['poster_url'] as String?,
      );
}

class SeriesEpisodes {
  final List<Season> seasons;
  const SeriesEpisodes({required this.seasons});

  factory SeriesEpisodes.fromJson(Map<String, dynamic> json) =>
      SeriesEpisodes(
        seasons: (json['seasons'] as List? ?? const [])
            .map((e) => Season.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  int get totalEpisodes =>
      seasons.fold(0, (sum, s) => sum + s.episodes.length);
}

/// Mirrors SeriesProgressOut — one user's watched-episode set for one
/// series, each with when it was marked. Kept as a Map<String, DateTime>
/// keyed by "season:episode" client-side for O(1) "is this watched?" /
/// "when?" lookups while rendering the grid. `watchedKeys` stays around
/// for callers (like [SeasonTracker]'s optimistic toggle) that only ever
/// needed the set of keys.
///
/// `ratings`/`notes` are each episode's own lightweight rating (see
/// routers/progress.py::rate_episode) — set from the episode list, not
/// the full log ritual. Only populated for episodes the person has
/// actually rated; most watched episodes have no entry here.
class SeriesProgress {
  final Map<String, DateTime> watchedAt;
  final Map<String, int> ratings;
  final Map<String, String> notes;
  const SeriesProgress(this.watchedAt, {this.ratings = const {}, this.notes = const {}});

  Set<String> get watchedKeys => watchedAt.keys.toSet();

  factory SeriesProgress.fromJson(Map<String, dynamic> json) {
    final list = json['watched'] as List? ?? const [];
    final ratings = <String, int>{};
    final notes = <String, String>{};
    for (final e in list) {
      final key = '${e['season']}:${e['episode']}';
      final rating = e['rating'] as int?;
      final note = e['note'] as String?;
      if (rating != null) ratings[key] = rating;
      if (note != null && note.isNotEmpty) notes[key] = note;
    }
    return SeriesProgress(
      {
        for (final e in list)
          '${e['season']}:${e['episode']}':
              DateTime.tryParse(e['watched_at'] as String? ?? '') ?? DateTime.now(),
      },
      ratings: ratings,
      notes: notes,
    );
  }

  bool isWatched(int season, int episode) =>
      watchedAt.containsKey('$season:$episode');

  DateTime? watchedAtFor(int season, int episode) => watchedAt['$season:$episode'];

  int? ratingFor(int season, int episode) => ratings['$season:$episode'];

  String? noteFor(int season, int episode) => notes['$season:$episode'];

  /// A copy with one episode removed from the watched set — used for the
  /// episode list's optimistic "remove from watched" tap (see
  /// series_episodes_sheet.dart::_unmarkWatched) so the UI updates the
  /// instant it's tapped rather than waiting on the round-trip.
  SeriesProgress without(int season, int episode) {
    final key = '$season:$episode';
    return SeriesProgress(
      {...watchedAt}..remove(key),
      ratings: {...ratings}..remove(key),
      notes: {...notes}..remove(key),
    );
  }
}
