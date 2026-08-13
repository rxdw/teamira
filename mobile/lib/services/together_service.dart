import '../models/together_session.dart';
import 'api_client.dart';

class TogetherService {
  final ApiClient _client;
  TogetherService(this._client);

  /// Starts a new session and returns it with a fresh 6-character code to
  /// share with the other person. [genres] narrows the deck to titles
  /// sharing at least one of the given genre names ([] = no narrowing).
  /// [syncToOwnList] is this device's own Settings > co-viewing choice —
  /// whether a match should also land on this account's personal "watch
  /// together" list.
  Future<TogetherSession> create({
    required String typeFilter,
    List<String> genres = const [],
    bool syncToOwnList = true,
  }) async {
    final json = await _client.post('/together', body: {
      'type_filter': typeFilter,
      'genres': genres,
      'sync_to_own_list': syncToOwnList,
    }) as Map<String, dynamic>;
    return TogetherSession.fromJson(json);
  }

  /// Joins an existing session by its code (case-insensitive).
  Future<TogetherSession> join(String code, {bool syncToOwnList = true}) async {
    final json = await _client.post('/together/join', body: {
      'code': code.trim().toUpperCase(),
      'sync_to_own_list': syncToOwnList,
    }) as Map<String, dynamic>;
    return TogetherSession.fromJson(json);
  }

  /// Polled on a timer while a session is open — carries partner-joined
  /// state, swipe progress, and matches so far.
  Future<TogetherSession> poll(String sessionId) async {
    final json = await _client.get('/together/$sessionId') as Map<String, dynamic>;
    return TogetherSession.fromJson(json);
  }

  Future<TogetherSession> swipe(
    String sessionId, {
    required String mediaId,
    required String source,
    required bool decision,
  }) async {
    final json = await _client.post('/together/$sessionId/swipe', body: {
      'media_id': mediaId,
      'source': source,
      'decision': decision,
    }) as Map<String, dynamic>;
    return TogetherSession.fromJson(json);
  }

  Future<void> end(String sessionId) => _client.delete('/together/$sessionId');
}
