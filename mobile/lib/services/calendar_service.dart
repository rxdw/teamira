import '../models/release_calendar_item.dart';
import 'api_client.dart';

/// Backs the Home screen's two release-calendar blocks — see
/// backend/app/routers/calendar.py for both endpoints' own docstrings.
/// Same convention as FeedService: lets a failure throw rather than
/// swallowing it here — home_screen.dart's own _load() is what decides
/// per-block "best-effort, ignored on failure" the way it already does
/// for collections()/forYou()/profile.collections().
class CalendarService {
  final ApiClient _client;

  CalendarService(this._client);

  /// GET /calendar/releases — the Steam-style discovery grid: anime
  /// (Shikimori), games (IGDB) and movies (TMDB), merged and sorted by
  /// date server-side. Not personalized — same shelf for everyone,
  /// cached for a few hours on the backend.
  Future<List<ReleaseCalendarItem>> releases() async {
    final json = await _client.get('/calendar/releases') as List;
    return json
        .map((e) => ReleaseCalendarItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /calendar/watching — this user's own "new episode"/"it's out"
  /// strip, checked against whatever's actually on their watching/
  /// watch-later shelves.
  Future<List<WatchingReleaseItem>> watching() async {
    final json = await _client.get('/calendar/watching') as List;
    return json
        .map((e) => WatchingReleaseItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
