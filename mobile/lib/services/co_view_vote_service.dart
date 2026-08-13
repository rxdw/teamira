import '../models/co_view_vote_session.dart';
import '../models/media_item.dart';
import 'api_client.dart';

/// Which pool a round or a random draw pulls from — mirrors the
/// backend's `PoolSource` in co_view_vote.py. Kept as plain strings
/// (not an enum) since that's what the API already speaks.
class CoViewVotePoolSource {
  static const personal = 'personal'; // each side's own plan-to-watch shelf
  static const coview = 'coview'; // the shared "planned together" list itself
  static const both = 'both'; // union of the two above — still just what's queued or agreed between you
  static const catalog = 'catalog'; // the whole app catalog — not limited to either shelf
}

/// Talks to /partner/co-viewing/vote — deciding together which of the
/// titles either of you already means to watch is the one for tonight,
/// plus the plain combined pool the "pick for us" dice draws from. See
/// backend/app/routers/co_view_vote.py for the reasoning.
class CoViewVoteService {
  final ApiClient _client;
  CoViewVoteService(this._client);

  /// The pool for a given source — no round attached, used purely for a
  /// one-off random pick.
  Future<List<MediaItem>> deck({String source = CoViewVotePoolSource.personal}) async {
    final json = await _client.get('/partner/co-viewing/vote/deck', query: {'source': source}) as List;
    return json.map((e) => MediaItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Starts a round on the given pool, or hands back one already in
  /// progress (whichever pool it was started with) — whichever of you
  /// taps first, both phones end up looking at the same session.
  Future<CoViewVoteSession> start({String source = CoViewVotePoolSource.personal}) async {
    final json = await _client.post('/partner/co-viewing/vote?source=$source') as Map<String, dynamic>;
    return CoViewVoteSession.fromJson(json);
  }

  /// Polled on a timer while a round is open.
  Future<CoViewVoteSession> poll(String sessionId) async {
    final json = await _client.get('/partner/co-viewing/vote/$sessionId') as Map<String, dynamic>;
    return CoViewVoteSession.fromJson(json);
  }

  /// Puts a specific pick — teamira's suggestion, a reel spin, a random
  /// draw — in front of the whole circle instead of adding it straight
  /// to the shared list. Reuses the exact same round/poll/cast flow as
  /// [start]; a round already active for this link is just handed back,
  /// same "whichever of you gets there first" reasoning.
  Future<CoViewVoteSession> propose(List<MediaItem> items) async {
    final json = await _client.post('/partner/co-viewing/vote/propose', body: {
      'items': items.map((e) => e.toJson()).toList(),
    }) as Map<String, dynamic>;
    return CoViewVoteSession.fromJson(json);
  }

  Future<CoViewVoteSession> cast(
    String sessionId, {
    required String mediaId,
    required String source,
    required bool decision,
  }) async {
    final json = await _client.post('/partner/co-viewing/vote/$sessionId/cast', body: {
      'media_id': mediaId,
      'source': source,
      'decision': decision,
    }) as Map<String, dynamic>;
    return CoViewVoteSession.fromJson(json);
  }

  Future<void> end(String sessionId) =>
      _client.delete('/partner/co-viewing/vote/$sessionId');
}
