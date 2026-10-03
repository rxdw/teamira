import 'persisted_pref.dart';

/// Remembers which title types (movie/series/anime/game/book/manga — see
/// widgets/interest_picker.dart's `kInterests`, the same list Collections
/// uses) the Home screen's release calendar should show — same
/// on-device-only preference pattern as [CollectionsPrefsService]. This is
/// a display filter, not account data, so it's fine for it to live only on
/// this device.
///
/// Empty means "no filter" — every type the calendar can show is shown,
/// same "nothing picked yet is fine too" default the interests picker
/// itself already uses for Collections.
class CalendarFiltersPrefsService {
  final _selected = PersistedPref.stringSet('seenly_calendar_type_filter');
  // Genre labels (same English vocabulary as MediaItem.genres) picked in
  // the full-screen calendar. Empty means no genre filter. Kept across
  // sessions like the type filter, and read by Home too so the strip and
  // the full screen never disagree about what's being shown.
  final _genres = PersistedPref.stringSet('seenly_calendar_genre_filter');

  Future<Set<String>> loadSelected() async {
    await _selected.load();
    return _selected.value;
  }

  Future<void> saveSelected(Set<String> selected) async {
    await _selected.save(selected);
  }

  Future<Set<String>> loadGenres() async {
    await _genres.load();
    return _genres.value;
  }

  Future<void> saveGenres(Set<String> genres) async {
    await _genres.save(genres);
  }
}
