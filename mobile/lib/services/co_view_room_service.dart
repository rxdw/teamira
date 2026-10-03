import '../models/co_view_room.dart';
import '../models/media_item.dart';
import 'api_client.dart';
import 'realtime_socket.dart';

/// Thin client over `/partner/rooms/*` (backend/app/routers/co_view_room.py).
///
/// Every mutation answers with the whole fresh [RoomState], so a caller can
/// apply the reply immediately and let the socket's next push confirm it.
/// Nothing here is premium-gated: rooms, chat, voice and every player are
/// free (see the module docstring on the server).
class CoViewRoomService {
  CoViewRoomService(this._client);
  final ApiClient _client;

  Future<RoomState?> active() async {
    final json = await _client.get('/partner/rooms/active');
    if (json == null) return null;
    return RoomState.fromJson(json as Map<String, dynamic>);
  }

  /// Rooms friends have invited me into as a guest and that are still open.
  Future<List<GuestInvite>> myInvites() async {
    final json = await _client.get('/partner/rooms/invites') as List;
    return json.map((e) => GuestInvite.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Invite a friend into this room (circle members only; up to the room's
  /// free guest slots).
  Future<RoomState> inviteGuest(String roomId, String userId) => _mutate(
        () => _client.post('/partner/rooms/$roomId/guests', body: {'user_id': userId}),
      );

  /// Take an invitation back — or, as the guest, say no / leave for good.
  Future<void> removeGuest(String roomId, String userId) =>
      _client.delete('/partner/rooms/$roomId/guests/$userId');

  Future<RoomState> get(String id) async =>
      RoomState.fromJson(await _client.get('/partner/rooms/$id') as Map<String, dynamic>);

  /// Opens a room for the circle — or returns the one already open, so two
  /// people tapping "start" at once land in the same place.
  Future<RoomState> create({
    required String mediaId,
    required String mediaType,
    required String source,
    String? titleRu,
    String? titleEn,
    String? posterUrl,
    int? year,
    required PlayerKind playerKind,
    String? playerRef,
    int? durationMs,
    String? entryId,
    bool saveToShared = true,
  }) async {
    final json = await _client.post('/partner/rooms', body: {
      'media_id': mediaId,
      'media_type': mediaType,
      'source': source,
      'title_ru': titleRu,
      'title_en': titleEn,
      'poster_url': posterUrl,
      'year': year,
      'player_kind': playerKindToWire(playerKind),
      'player_ref': playerRef,
      'duration_ms': durationMs,
      'entry_id': entryId,
      'save_to_shared': saveToShared,
    }) as Map<String, dynamic>;
    return RoomState.fromJson(json);
  }

  /// Opens a room for *reading* (a book or a manga) — or returns the one
  /// already open. Nothing of the text is sent: [contentHash] is the SHA-256
  /// of the file this device opened (null for [ReadKind.parallel]) and
  /// [readUnits] its length in chapters/pages.
  Future<RoomState> createReading({
    required String mediaId,
    required String mediaType, // book | manga
    required String source,
    String? titleRu,
    String? titleEn,
    String? posterUrl,
    int? year,
    required ReadKind readKind,
    String? contentHash,
    int? readUnits,
    String readMode = 'own',
    String? entryId,
    bool saveToShared = true,
  }) async {
    final json = await _client.post('/partner/rooms', body: {
      'media_id': mediaId,
      'media_type': mediaType,
      'source': source,
      'title_ru': titleRu,
      'title_en': titleEn,
      'poster_url': posterUrl,
      'year': year,
      'activity': 'read',
      'read_kind': readKind.name,
      'content_hash': contentHash,
      'read_units': readUnits,
      'read_mode': readMode,
      'entry_id': entryId,
      'save_to_shared': saveToShared,
    }) as Map<String, dynamic>;
    return RoomState.fromJson(json);
  }

  /// Opens a room for *playing* a real game — or returns the one already open.
  /// Nothing of the game goes through the room: each person runs it on their
  /// own machine, and the room's clock is the session timer. [platform] is
  /// where this room plays it (pc | ps | xbox | switch | mobile | other).
  Future<RoomState> createPlay({
    required String mediaId,
    required String source,
    String? titleRu,
    String? titleEn,
    String? posterUrl,
    int? year,
    String? platform,
    String? entryId,
    bool saveToShared = true,
  }) async {
    final json = await _client.post('/partner/rooms', body: {
      'media_id': mediaId,
      'media_type': 'game',
      'source': source,
      'title_ru': titleRu,
      'title_en': titleEn,
      'poster_url': posterUrl,
      'year': year,
      'activity': 'play',
      'platform': platform,
      'entry_id': entryId,
      'save_to_shared': saveToShared,
    }) as Map<String, dynamic>;
    return RoomState.fromJson(json);
  }

  /// The ready check: "готов" on or off.
  Future<RoomState> setReady(String id, bool ready) =>
      _mutate(() => _client.post('/partner/rooms/$id/ready', body: {'ready': ready}));

  /// One finished round: win | loss | draw | checkpoint, stamped with the
  /// session time by the server.
  Future<RoomState> round(String id, String key) => _event(id, {'kind': 'round', 'key': key});

  /// "I'm here" — my place in a reading room (a locator, see
  /// `reading_locator.dart`), how far through it is (a permille, 0..1000),
  /// and the fingerprint of the file I opened.
  Future<RoomState> reportLocator(String id, String locator, int progress, {String? contentHash}) => _mutate(
        () => _client.post('/partner/rooms/$id/locator', body: {
          'locator': locator,
          'progress': progress,
          if (contentHash != null) 'content_hash': contentHash,
        }),
      );

  /// Turning the page for everyone ("together" mode; the circle only).
  Future<RoomState> lead(String id, String locator, int progress) => _mutate(
        () => _client.post('/partner/rooms/$id/lead', body: {'locator': locator, 'progress': progress}),
      );

  /// own | together. Switching on "together" starts everyone from the given
  /// place (or from where the person switching it on is).
  Future<RoomState> setReadMode(String id, String mode, {String? locator, int? progress}) => _mutate(
        () => _client.patch('/partner/rooms/$id', body: {
          'read_mode': mode,
          if (locator != null) 'locator': locator,
          if (progress != null) 'progress': progress,
        }),
      );

  Future<RoomState> setReadUnits(String id, int units) =>
      _mutate(() => _client.patch('/partner/rooms/$id', body: {'read_units': units}));

  /// A note in the margin, pinned to a place (with the line it refers to).
  Future<RoomState> margin(String id, String body, String locator, int progress, {String? quote}) => _event(id, {
        'kind': 'margin',
        'body': body,
        'locator': locator,
        'progress': progress,
        if (quote != null && quote.trim().isNotEmpty) 'quote': quote,
      });

  /// A highlight on a paragraph, switched [on] or off again. Each person has
  /// their own highlight on a paragraph, so switching yours off leaves the
  /// other's. [quote] is the line it's on (a line or two, never more).
  Future<RoomState> highlight(String id, String locator, bool on, int progress, {String? quote}) => _event(id, {
        'kind': 'highlight',
        'key': on ? 'on' : 'off',
        'locator': locator,
        'progress': progress,
        if (on && quote != null && quote.trim().isNotEmpty) 'quote': quote,
      });

  /// A feeling (zen) pinned to a place in the book.
  Future<RoomState> emotionAt(String id, String key, String locator, int progress) => _event(id, {
        'kind': 'emotion',
        'key': key,
        'locator': locator,
        'progress': progress,
      });

  /// Sets a paragraph aside for the pair album: it joins my sealed note for
  /// this book, which opens for both of you when you finish it. Throws the
  /// server's own words when there's no album (not a couple), no room in the
  /// note, or the free allowance of notes is spent (402).
  Future<AlbumQuoteResult> albumQuote(String id, String quote) async => AlbumQuoteResult.fromJson(
        await _client.post('/partner/rooms/$id/album-quote', body: {'quote': quote}) as Map<String, dynamic>,
      );

  /// A reaction pinned to a place in the book.
  Future<RoomState> reactAt(String id, String key, String locator, int progress) => _event(id, {
        'kind': 'reaction',
        'key': key,
        'locator': locator,
        'progress': progress,
      });

  /// Convenience for a catalog title (movie/series/anime): always the
  /// "parallel" player — each person plays it in their own streaming app.
  Future<RoomState> createForItem(
    MediaItem item, {
    String? entryId,
    bool saveToShared = true,
  }) =>
      create(
        mediaId: item.id,
        mediaType: item.mediaType,
        source: item.source,
        titleRu: item.title.ru,
        titleEn: item.title.en,
        posterUrl: item.posterUrl,
        year: item.year,
        playerKind: PlayerKind.parallel,
        entryId: entryId,
        saveToShared: saveToShared,
      );

  Future<RoomState> join(String id) => _mutate(() => _client.post('/partner/rooms/$id/join'));
  Future<RoomState> leave(String id) => _mutate(() => _client.post('/partner/rooms/$id/leave'));

  Future<RoomState> control(String id, String action, {int? positionMs}) => _mutate(
        () => _client.post('/partner/rooms/$id/control', body: {
          'action': action,
          if (positionMs != null) 'position_ms': positionMs,
        }),
      );

  Future<RoomState> chat(String id, String body) => _event(id, {'kind': 'chat', 'body': body});

  Future<RoomState> react(String id, String key, {int? positionMs}) =>
      _event(id, {'kind': 'reaction', 'key': key, if (positionMs != null) 'position_ms': positionMs});

  Future<RoomState> signal(String id, String key) => _event(id, {'kind': 'signal', 'key': key});

  Future<RoomState> emotion(String id, String key, {int? positionMs}) =>
      _event(id, {'kind': 'emotion', 'key': key, if (positionMs != null) 'position_ms': positionMs});

  Future<RoomState> setSaveToShared(String id, bool value) =>
      _mutate(() => _client.patch('/partner/rooms/$id', body: {'save_to_shared': value}));

  Future<RoomState> setDuration(String id, int durationMs) =>
      _mutate(() => _client.patch('/partner/rooms/$id', body: {'duration_ms': durationMs}));

  /// "Досмотрели" — ends the room for everyone and writes the evening when
  /// the save switch is on. Idempotent on the server.
  Future<RoomState> finish(String id, {int? positionMs}) => _mutate(
        () => _client.post('/partner/rooms/$id/finish', body: {
          if (positionMs != null) 'position_ms': positionMs,
        }),
      );

  Future<void> close(String id) => _client.delete('/partner/rooms/$id');

  Future<VoiceToken> voiceToken(String id) async =>
      VoiceToken.fromJson(await _client.post('/partner/rooms/$id/voice-token') as Map<String, dynamic>);

  Future<RoomState> voiceOff(String id) async => RoomState.fromJson(
      await _client.deleteAndDecode('/partner/rooms/$id/voice') as Map<String, dynamic>);

  Future<List<RoomEvent>> eventsAfter(String id, int after) async {
    final json = await _client.get('/partner/rooms/$id/events', query: {'after': '$after', 'limit': '300'});
    return (json as List).map((e) => RoomEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// The room's live feed: the whole room on connect and on every change.
  RealtimeSocket<RoomState> watch(String id) => RealtimeSocket<RoomState>(
        path: '/partner/rooms/$id/ws',
        fromJson: RoomState.fromJson,
        client: _client,
      );

  Future<RoomState> _event(String id, Map<String, dynamic> body) =>
      _mutate(() => _client.post('/partner/rooms/$id/events', body: body));

  Future<RoomState> _mutate(Future<dynamic> Function() call) async =>
      RoomState.fromJson(await call() as Map<String, dynamic>);
}
