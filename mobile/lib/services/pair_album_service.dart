import '../models/media_item.dart';
import '../models/pair_album.dart';
import 'api_client.dart';

/// Thin client over `/partner/album/*` (backend/app/routers/pair_album.py).
///
/// Every write can answer 402 when the circle hasn't unlocked the album —
/// check [isPaywall] on whatever a call throws and answer it with the
/// upsell sheet instead of an error toast. Reads are never gated.
class PairAlbumService {
  PairAlbumService(this._client);
  final ApiClient _client;

  /// True for the "this circle has no premium" answer to a write.
  static bool isPaywall(Object error) => error is ApiException && error.statusCode == 402;

  Future<AlbumStatus> status() async {
    final json = await _client.get('/partner/album') as Map<String, dynamic>;
    return AlbumStatus.fromJson(json);
  }

  Future<AlbumStatus> setTogetherSince(DateTime? day) async {
    final json = await _client.put('/partner/album/together-since', body: {
      'together_since': day == null ? null : albumDayToWire(day),
    }) as Map<String, dynamic>;
    return AlbumStatus.fromJson(json);
  }

  // --- notes ----------------------------------------------------------

  /// Titles that carry a sealed note from either side. Never contains the
  /// partner's text — only that it exists (`partnerSealed`).
  Future<List<AlbumPage>> waitingNotes() async {
    final json = await _client.get('/partner/album/notes/waiting') as List;
    return json.map((e) => AlbumPage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Leaves — or rewrites — my note on [item] for the coming evening.
  Future<AlbumPage> putNote(MediaItem item, String body, {String? mood}) async {
    final json = await _client.put(
      '/partner/album/notes',
      body: albumNotePayload(item, body, mood),
    ) as Map<String, dynamic>;
    return AlbumPage.fromJson(json);
  }

  Future<void> deleteNote(String noteId) => _client.delete('/partner/album/notes/$noteId');

  Future<AlbumPages> pages({DateTime? before, int limit = 20}) async {
    final query = <String, String>{'limit': '$limit'};
    if (before != null) query['before'] = before.toUtc().toIso8601String();
    final json = await _client.get('/partner/album/pages', query: query) as Map<String, dynamic>;
    return AlbumPages.fromJson(json);
  }

  Future<void> markNoteOpened(String noteId) =>
      _client.post('/partner/album/notes/$noteId/opened');

  /// Pass null to clear the reply.
  Future<void> react(String noteId, String? emoji) =>
      _client.post('/partner/album/notes/$noteId/react', body: {'emoji': emoji});

  // --- capsules -------------------------------------------------------

  Future<List<Capsule>> capsules() async {
    final json = await _client.get('/partner/album/capsules') as Map<String, dynamic>;
    return ((json['items'] as List?) ?? const [])
        .map((e) => Capsule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Capsule> createCapsule({
    required DateTime opensOn,
    required String body,
    String? title,
  }) async {
    final json = await _client.post('/partner/album/capsules', body: {
      'opens_on': albumDayToWire(opensOn),
      'body': body,
      'title': (title == null || title.trim().isEmpty) ? null : title.trim(),
    }) as Map<String, dynamic>;
    return Capsule.fromJson(json);
  }

  Future<Capsule> addLetter(String capsuleId, String body) async {
    final json = await _client.post(
      '/partner/album/capsules/$capsuleId/letter',
      body: {'body': body},
    ) as Map<String, dynamic>;
    return Capsule.fromJson(json);
  }

  /// Marks the capsule opened for me and returns it with its letters.
  /// The server refuses (409) before the date, by its own clock.
  Future<Capsule> openCapsule(String capsuleId) async {
    final json = await _client.post('/partner/album/capsules/$capsuleId/open')
        as Map<String, dynamic>;
    return Capsule.fromJson(json);
  }

  Future<void> deleteCapsule(String capsuleId) =>
      _client.delete('/partner/album/capsules/$capsuleId');
}
