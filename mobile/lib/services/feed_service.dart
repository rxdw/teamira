import '../models/collection.dart';
import '../models/media_item.dart';
import '../models/today_pick.dart';
import 'api_client.dart';
import 'locale_service.dart';

class FeedService {
  final ApiClient _client;
  FeedService(this._client);

  /// Named editorial shelves (real TMDB/IGDB/Open Library data) — powers the Collections tab.
  /// Sends the device's content-language preference (see
  /// services/locale_service.dart) so the shelves themselves come back
  /// with Russian titles/overviews already, instead of only after
  /// opening a title's own detail screen (that's a separate, richer
  /// per-title fetch — see MediaService.detail()).
  Future<List<SeenlyCollection>> collections() async {
    final json = await _client.get('/feed/collections', query: {
      if (LocaleService.contentPrefersRussian) 'lang': 'ru',
    }) as List;
    return json
        .map((e) => SeenlyCollection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Hand-curated shelves we build ourselves (franchises, "best of the
  /// year" picks, etc) — same shape as collections() above, different
  /// source (GET /feed/teamira). See backend/app/routers/teamira.py.
  Future<List<SeenlyCollection>> teamiraCollections() async {
    final json = await _client.get('/feed/teamira') as List;
    return json
        .map((e) => SeenlyCollection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Home's "today's pick" card — one franchise shelf picked for today,
  /// plus how far this account already is into it (GET /feed/today-pick).
  /// See widgets/today_pick_card.dart.
  /// [offset] asks the server to step past the shared daily franchise —
  /// used by the "today's pick" card's shuffle button (see
  /// TodayPickPrefsService.rerollCount) to get a different pick without
  /// touching the rotation everyone else sees today.
  Future<TodayPick> todayPick({int offset = 0}) async {
    final json = await _client.get(
      '/feed/today-pick',
      query: offset == 0 ? null : {'offset': '$offset'},
    ) as Map<String, dynamic>;
    return TodayPick.fromJson(json);
  }

  Future<List<MediaItem>> feed() async {
    final json = await _client.get('/feed') as List;
    return json
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Personal, content-based picks with a real trailer attached where one
  /// exists (GET /feed/for-you) — empty for a brand-new account with
  /// nothing logged yet; callers should just skip the section in that case
  /// rather than show it empty.
  Future<List<MediaItem>> forYou() async {
    final json = await _client.get('/feed/for-you') as List;
    return json
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// "like" -> watch_later, "watched" -> watched, "skip" -> no-op.
  Future<void> react(MediaItem item, String action) {
    return _client.post('/feed/react', body: {
      'item': item.toJson(),
      'action': action,
    });
  }
}
