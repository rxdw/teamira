import '../models/collection.dart';
import '../models/media_item.dart';
import '../models/today_pick.dart';
import 'api_client.dart';
import 'locale_service.dart';
import '../analytics/analytics.dart';

class FeedService {
  final ApiClient _client;
  FeedService(this._client);

  /// Named editorial shelves (real TMDB/IGDB/Open Library data) — powers the Collections tab.
  /// Sends the device's content-language preference (see
  /// services/locale_service.dart) so the shelves themselves come back
  /// with Russian titles/overviews already, instead of only after
  /// opening a title's own detail screen (that's a separate, richer
  /// per-title fetch — see MediaService.detail()).
  ///
  /// Longer timeout than the client default: on a cold cache (see
  /// COLLECTIONS_TTL in the backend) this endpoint fans out to ~19
  /// upstream shelf calls plus a per-title Russian-text supplement pass
  /// (app/routers/feed.py::_apply_ru_supplement) before it can answer at
  /// all — comfortably past the default 12s. Once cached (up to
  /// COLLECTIONS_TTL), the response is instant and this budget is unused.
  Future<List<SeenlyCollection>> collections() async {
    final json = await _client.get(
      '/feed/collections',
      query: {
        if (LocaleService.contentPrefersRussian) 'lang': 'ru',
      },
      timeout: const Duration(seconds: 60),
    ) as List;
    return json
        .map((e) => SeenlyCollection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Hand-curated shelves we build ourselves (franchises, "best of the
  /// year" picks, etc) — same shape as collections() above, different
  /// source (GET /feed/teamira). See backend/app/routers/teamira.py.
  /// Same cold-cache reasoning as collections() above applies here too.
  Future<List<SeenlyCollection>> teamiraCollections() async {
    final json = await _client.get(
      '/feed/teamira',
      timeout: const Duration(seconds: 60),
    ) as List;
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

  /// Whole-app pool — powers Home's "can't decide?" flow (random pick,
  /// roulette, swipe) via DecideFiltersScreen's default poolLoader. Same
  /// cold-cache reasoning as collections() above: GET /feed's own cache
  /// (see cache.py, "feed:discover", 24h TTL) fans out to TMDB + IGDB +
  /// Google Books + Shikimori on a miss, comfortably past the default 12s.
  Future<List<MediaItem>> feed() async {
    final json = await _client.get(
      '/feed',
      // Same as collections(): without it the pool's posters come back
      // English-only and only turn Russian once a title's own card is opened.
      query: {
        if (LocaleService.contentPrefersRussian) 'lang': 'ru',
      },
      timeout: const Duration(seconds: 60),
    ) as List;
    return json
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Personal, content-based picks with a real trailer attached where one
  /// exists (GET /feed/for-you) — empty for a brand-new account with
  /// nothing logged yet; callers should just skip the section in that case
  /// rather than show it empty. Same cold-cache reasoning as feed()/
  /// collections() above: up to a dozen extra per-title trailer lookups
  /// on a miss (see _FOR_YOU_TRAILER_LIMIT in feed.py).
  Future<List<MediaItem>> forYou() async {
    final json = await _client.get(
      '/feed/for-you',
      query: {
        if (LocaleService.contentPrefersRussian) 'lang': 'ru',
      },
      timeout: const Duration(seconds: 60),
    ) as List;
    return json
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// "like" -> watch_later, "watched" -> watched, "skip" -> no-op.
  Future<void> react(MediaItem item, String action) async {
    await _client.post('/feed/react', body: {
      'item': item.toJson(),
      'action': action,
    });
    Analytics.instance.track('title_reacted', {
      'action': action, // like / watched / skip
      'media_type': item.mediaType,
    });
  }
}
