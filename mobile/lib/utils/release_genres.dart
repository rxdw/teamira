import '../models/release_calendar_item.dart';

/// Genre filtering for the release calendar — the same idea as the
/// "can't decide?" flow's genre step (screens/decide/decide_filters_screen.dart):
/// the choices are whatever genres the current pool actually contains,
/// each with a count, and a release passes if it has *any* picked genre.

/// How many of [items] carry each genre.
Map<String, int> releaseGenreCounts(Iterable<ReleaseCalendarItem> items) {
  final counts = <String, int>{};
  for (final item in items) {
    for (final genre in item.allGenres) {
      counts[genre] = (counts[genre] ?? 0) + 1;
    }
  }
  return counts;
}

/// The picked genres that actually exist in [items]. A pick that the
/// current pool doesn't contain (say "Shooter" while looking at movies)
/// is inert rather than an empty screen.
Set<String> activeReleaseGenres(Iterable<ReleaseCalendarItem> items, Set<String> picked) {
  if (picked.isEmpty) return const {};
  final available = releaseGenreCounts(items).keys.toSet();
  return picked.intersection(available);
}

/// [items] narrowed to releases having any of [picked] (see
/// [activeReleaseGenres] for which picks count). No effective pick means
/// no filtering. Releases with no genres at all — e.g. an anime whose
/// genre lookup failed — are left out while a filter is on, the same way
/// the decide flow drops a title with no genres.
List<ReleaseCalendarItem> filterReleasesByGenres(
  List<ReleaseCalendarItem> items,
  Set<String> picked,
) {
  final active = activeReleaseGenres(items, picked);
  if (active.isEmpty) return items;
  return items.where((e) => e.allGenres.any(active.contains)).toList();
}
