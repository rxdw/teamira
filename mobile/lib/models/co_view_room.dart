import '../utils/server_time.dart';

/// Client mirrors of backend/app/routers/co_view_room.py (`RoomOut` and
/// friends). Everything the server decides — who is present, where the
/// clock stands, what the save switch says — arrives here already decided;
/// the room screen only draws it and sends intents back.

/// How the picture reaches each person.
enum PlayerKind { youtube, twitch, direct, parallel }

PlayerKind playerKindFromWire(String? s) => switch (s) {
      'youtube' => PlayerKind.youtube,
      'twitch' => PlayerKind.twitch,
      'direct' => PlayerKind.direct,
      _ => PlayerKind.parallel,
    };

String playerKindToWire(PlayerKind k) => k.name;

/// What a room is about: a film's clock, a place in a book, or a real game
/// each person plays on their own machine (the room is the evening around it).
enum RoomActivity { watch, read, play }

RoomActivity roomActivityFromWire(String? s) => switch (s) {
      'read' => RoomActivity.read,
      'play' => RoomActivity.play,
      _ => RoomActivity.watch,
    };

/// How the text of a reading room reaches each person (backend
/// app/co_reading.py): their own EPUB, their own comic archive, or read
/// somewhere else (an official site, paper) with only the room in common.
enum ReadKind { epub, cbz, parallel }

ReadKind? readKindFromWire(String? s) => switch (s) {
      'epub' => ReadKind.epub,
      'cbz' => ReadKind.cbz,
      'parallel' => ReadKind.parallel,
      _ => null,
    };

class RoomParticipant {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final bool isYou;
  final bool isHost;

  /// A friend invited into this one room (not in the circle), and who asked them.
  final bool isGuest;
  final String? invitedBy;
  final bool joined;
  final bool present;
  final bool voiceOn;

  /// Reading rooms: where this person is (a locator string, see
  /// `reading_locator.dart`), how far through that is (a permille), and
  /// whether the file they opened is the room's edition (null = unknown).
  final String? locator;
  final int progress;
  final bool? sameEdition;

  /// Game rooms: has tapped "готов".
  final bool ready;

  const RoomParticipant({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    required this.isYou,
    required this.isHost,
    this.isGuest = false,
    this.invitedBy,
    required this.joined,
    required this.present,
    required this.voiceOn,
    this.locator,
    this.progress = 0,
    this.sameEdition,
    this.ready = false,
  });

  String get name =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  String get letter => name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

  factory RoomParticipant.fromJson(Map<String, dynamic> j) => RoomParticipant(
        userId: j['user_id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String?,
        avatarPreset: j['avatar_preset'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        isYou: j['is_you'] == true,
        isHost: j['is_host'] == true,
        isGuest: j['is_guest'] == true,
        invitedBy: j['invited_by'] as String?,
        joined: j['joined'] == true,
        present: j['present'] == true,
        voiceOn: j['voice_on'] == true,
        locator: j['locator'] as String?,
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        sameEdition: j['same_edition'] as bool?,
        ready: j['ready'] == true,
      );
}

/// chat | reaction | signal | emotion | margin | control | join | leave | system
class RoomEvent {
  final int seq;
  final String kind;
  final String? userId;
  final String? username;
  final String? body;
  final String? key; // the emoji / signal / emotion key (`emoji` on the wire)
  final int? positionMs;

  /// Reading rooms: the place a reaction or margin note is pinned to, and the
  /// short passage it refers to.
  final String? locator;
  final String? quote;
  final DateTime createdAt;

  const RoomEvent({
    required this.seq,
    required this.kind,
    this.userId,
    this.username,
    this.body,
    this.key,
    this.positionMs,
    this.locator,
    this.quote,
    required this.createdAt,
  });

  bool get isMargin => kind == 'margin';
  bool get isChat => kind == 'chat';
  bool get isReaction => kind == 'reaction';
  bool get isSignal => kind == 'signal';
  bool get isEmotion => kind == 'emotion';

  factory RoomEvent.fromJson(Map<String, dynamic> j) => RoomEvent(
        seq: (j['seq'] as num).toInt(),
        kind: j['kind'] as String,
        userId: j['user_id'] as String?,
        username: j['username'] as String?,
        body: j['body'] as String?,
        key: j['emoji'] as String?,
        positionMs: (j['position_ms'] as num?)?.toInt(),
        locator: j['locator'] as String?,
        quote: j['quote'] as String?,
        createdAt: tryParseServerUtc(j['created_at'] as String?)?.toLocal() ?? DateTime.now(),
      );
}

/// Something written on the pages of a reading room right now: a note in the
/// margin, or somebody's highlight on a paragraph. The server reduces the
/// room's event ledger to these (the pushed event tail only holds the last few
/// events), so a book read over days still shows all of its margins.
class RoomMark {
  final int seq;
  final String? userId;
  final String kind; // margin | highlight
  final String locator;
  final String? body;
  final String? quote;

  /// How far through the book, scaled by 1000 (see backend co_reading.py).
  final int? positionMs;

  const RoomMark({
    required this.seq,
    required this.userId,
    required this.kind,
    required this.locator,
    this.body,
    this.quote,
    this.positionMs,
  });

  bool get isMargin => kind == 'margin';
  bool get isHighlight => kind == 'highlight';

  factory RoomMark.fromJson(Map<String, dynamic> j) => RoomMark(
        seq: (j['seq'] as num).toInt(),
        userId: j['user_id'] as String?,
        kind: (j['kind'] as String?) ?? 'margin',
        locator: (j['locator'] as String?) ?? '',
        body: j['body'] as String?,
        quote: j['quote'] as String?,
        positionMs: (j['position_ms'] as num?)?.toInt(),
      );
}

/// What setting a quote aside for the pair album came to.
class AlbumQuoteResult {
  /// The person's sealed note for this title was just started.
  final bool created;

  /// False when this very quote was already in the note.
  final bool added;
  final int charsLeft;
  const AlbumQuoteResult({required this.created, required this.added, required this.charsLeft});

  factory AlbumQuoteResult.fromJson(Map<String, dynamic> j) => AlbumQuoteResult(
        created: j['created'] == true,
        added: j['added'] != false,
        charsLeft: (j['chars_left'] as num?)?.toInt() ?? 0,
      );
}

class RoomState {
  final String id;
  final String status; // lobby | live | ended
  final String mediaId;
  final String mediaType;
  final String source;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  final int? year;
  final PlayerKind playerKind;
  final String? playerRef;
  final int? durationMs;
  final bool isPlaying;

  /// Already advanced to [serverNow] on the server.
  final int positionMs;
  final DateTime serverNow;
  final int controlSeq;
  final bool saveToShared;
  final String? entryId;
  final String? savedEntryId;
  final String? myDiaryEntryId;
  final String? reviewId;
  final String? hostUserId;
  final List<RoomParticipant> participants;
  final List<RoomEvent> events;
  final int lastSeq;
  final bool voiceAvailable;

  /// Zen mode is open for this circle: any member's subscription covers
  /// everyone (the server decides — it also refuses emotion taps otherwise).
  final bool zenAvailable;

  /// I'm in this room as a guest: I can watch, chat, react and talk, but the
  /// playback, the save switch and ending the room belong to the circle.
  final bool meIsGuest;
  final int guestSlotsLeft;

  /// Reading together: what the room keeps in sync, how the text reaches
  /// people, its length in chapters/pages (when known), whether everybody
  /// reads at their own pace or follows one shared place, that shared place,
  /// who turned it last, and the fingerprint of the file the room is about.
  final RoomActivity activity;
  final ReadKind? readKind;
  final int? readUnits;
  final String readMode; // own | together | aloud
  final String? leadLocator;
  final String? leadUserId;
  final String? contentHash;

  /// Notes in the margin and highlights, as they stand now (reading rooms).
  final List<RoomMark> marks;

  /// Game rooms: rounds played this session by kind (win | loss | draw |
  /// checkpoint — all four always present), and whether everybody who is here
  /// has said they're ready.
  final Map<String, int> rounds;
  final bool allReady;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// When this snapshot reached the device — lets the player extrapolate the
  /// clock forward without trusting the phone's wall clock for anything
  /// except "how long ago did this arrive".
  final int receivedAtMicros;

  RoomState({
    required this.id,
    required this.status,
    required this.mediaId,
    required this.mediaType,
    required this.source,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
    this.year,
    required this.playerKind,
    this.playerRef,
    this.durationMs,
    required this.isPlaying,
    required this.positionMs,
    required this.serverNow,
    required this.controlSeq,
    required this.saveToShared,
    this.entryId,
    this.savedEntryId,
    this.myDiaryEntryId,
    this.reviewId,
    this.hostUserId,
    required this.participants,
    required this.events,
    required this.lastSeq,
    required this.voiceAvailable,
    this.zenAvailable = false,
    this.meIsGuest = false,
    this.guestSlotsLeft = 0,
    this.activity = RoomActivity.watch,
    this.readKind,
    this.readUnits,
    this.readMode = 'own',
    this.leadLocator,
    this.leadUserId,
    this.contentHash,
    this.marks = const [],
    this.rounds = const {},
    this.allReady = false,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    int? receivedAtMicros,
  }) : receivedAtMicros = receivedAtMicros ?? DateTime.now().microsecondsSinceEpoch;

  bool get isReading => activity == RoomActivity.read;

  /// A real game played on everybody's own machine; the room's clock is the
  /// session timer and [platform] says where it is played (pc | ps | xbox |
  /// switch | mobile | other), if anyone said.
  bool get isGame => activity == RoomActivity.play;
  String? get platform => isGame ? playerRef : null;

  /// Rounds of one kind played so far.
  int roundsOf(String key) => rounds[key] ?? 0;
  int get roundsTotal => rounds.values.fold(0, (a, b) => a + b);
  bool get isTogether => isReading && readMode == 'together';

  /// One person reads out loud over the room's voice and everyone else follows
  /// the highlighted paragraph; only that person (the reader) moves it.
  bool get isAloud => isReading && readMode == 'aloud';

  /// Whether the room keeps one place everybody follows.
  bool get hasSharedPlace => isTogether || isAloud;

  /// The shared place's progress, 0..1 (a reading room's `positionMs` is a
  /// permille scaled by 1000, see backend app/co_reading.py).
  double get leadProgress => (positionMs / 1000000).clamp(0.0, 1.0);

  bool get isLobby => status == 'lobby';
  bool get isLive => status == 'live';
  bool get isEnded => status == 'ended';
  bool get isOpen => !isEnded;

  String get title => (titleRu != null && titleRu!.trim().isNotEmpty)
      ? titleRu!
      : (titleEn ?? '');

  RoomParticipant? get me {
    for (final p in participants) {
      if (p.isYou) return p;
    }
    return null;
  }

  List<RoomParticipant> get others => participants.where((p) => !p.isYou).toList();
  List<RoomParticipant> get guests => participants.where((p) => p.isGuest).toList();

  /// Only the circle steers and can invite; guests ride along.
  bool get canSteer => !meIsGuest;
  List<RoomParticipant> get present => participants.where((p) => p.present).toList();
  int get presentCount => present.length;

  /// Where the room's clock stands *now*, extrapolated from this snapshot
  /// with the device's monotonic-ish elapsed time since it arrived.
  int positionNowMs() {
    if (!isPlaying) return positionMs;
    final elapsed =
        (DateTime.now().microsecondsSinceEpoch - receivedAtMicros) ~/ 1000;
    final v = positionMs + (elapsed < 0 ? 0 : elapsed);
    final d = durationMs;
    return (d != null && d > 0 && v > d) ? d : v;
  }

  double get progress {
    final d = durationMs;
    if (d == null || d <= 0) return 0;
    return (positionNowMs() / d).clamp(0.0, 1.0);
  }

  factory RoomState.fromJson(Map<String, dynamic> j) {
    final serverNow = tryParseServerUtc(j['server_now'] as String?) ?? DateTime.now().toUtc();
    return RoomState(
      id: j['id'] as String,
      status: j['status'] as String,
      mediaId: j['media_id'] as String,
      mediaType: j['media_type'] as String,
      source: j['source'] as String,
      titleRu: j['title_ru'] as String?,
      titleEn: j['title_en'] as String?,
      posterUrl: j['poster_url'] as String?,
      year: (j['year'] as num?)?.toInt(),
      playerKind: playerKindFromWire(j['player_kind'] as String?),
      playerRef: j['player_ref'] as String?,
      durationMs: (j['duration_ms'] as num?)?.toInt(),
      isPlaying: j['is_playing'] == true,
      positionMs: (j['position_ms'] as num?)?.toInt() ?? 0,
      serverNow: serverNow,
      controlSeq: (j['control_seq'] as num?)?.toInt() ?? 0,
      saveToShared: j['save_to_shared'] != false,
      entryId: j['entry_id'] as String?,
      savedEntryId: j['saved_entry_id'] as String?,
      myDiaryEntryId: j['my_diary_entry_id'] as String?,
      reviewId: j['review_id'] as String?,
      hostUserId: j['host_user_id'] as String?,
      participants: ((j['participants'] as List?) ?? const [])
          .map((e) => RoomParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      events: ((j['events'] as List?) ?? const [])
          .map((e) => RoomEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastSeq: (j['last_seq'] as num?)?.toInt() ?? 0,
      voiceAvailable: j['voice_available'] == true,
      zenAvailable: j['zen_available'] == true,
      meIsGuest: j['me_is_guest'] == true,
      guestSlotsLeft: (j['guest_slots_left'] as num?)?.toInt() ?? 0,
      activity: roomActivityFromWire(j['activity'] as String?),
      readKind: readKindFromWire(j['read_kind'] as String?),
      readUnits: (j['read_units'] as num?)?.toInt(),
      readMode: (j['read_mode'] as String?) ?? 'own',
      leadLocator: j['lead_locator'] as String?,
      leadUserId: j['lead_user_id'] as String?,
      contentHash: j['content_hash'] as String?,
      marks: [
        for (final m in (j['marks'] as List? ?? const []))
          RoomMark.fromJson(m as Map<String, dynamic>),
      ],
      rounds: {
        for (final e in ((j['rounds'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt(),
      },
      allReady: j['all_ready'] == true,
      createdAt: tryParseServerUtc(j['created_at'] as String?)?.toLocal() ?? DateTime.now(),
      startedAt: tryParseServerUtc(j['started_at'] as String?)?.toLocal(),
      endedAt: tryParseServerUtc(j['ended_at'] as String?)?.toLocal(),
    );
  }
}

class VoiceToken {
  final String url;
  final String token;
  final String roomName;
  final String identity;
  const VoiceToken({required this.url, required this.token, required this.roomName, required this.identity});

  factory VoiceToken.fromJson(Map<String, dynamic> j) => VoiceToken(
        url: j['url'] as String,
        token: j['token'] as String,
        roomName: j['room_name'] as String,
        identity: j['identity'] as String,
      );
}

/// The allow-lists the server enforces (backend/app/co_view_room.py) —
/// kept in one place so the pickers and the server can't quietly disagree.
class RoomKeys {
  static const reactions = ['❤️', '😂', '😱', '🥹', '😮', '👏', '😭', '🔥', '🫶', '😴'];
  static const signals = ['pause', 'rewind', 'pulse', 'hold'];
  static const emotions = ['warm', 'funny', 'tense', 'touching', 'beautiful', 'sad', 'wow', 'bored'];

  /// What players say mid-session (a film's `signals` are about a picture).
  static const gameSignals = ['ready', 'brb', 'help', 'gg', 'again'];

  /// One tap per finished round.
  static const rounds = ['win', 'loss', 'draw', 'checkpoint'];

  /// Where a game room is played.
  static const platforms = ['pc', 'ps', 'xbox', 'switch', 'mobile', 'other'];
}


/// A room a friend invited me into as a guest (`GET /partner/rooms/invites`).
class GuestInvite {
  final String roomId;
  final String title;
  final String? posterUrl;
  final String inviterName;
  final String inviterUsername;
  final String roomStatus; // lobby | live
  final DateTime createdAt;

  /// watch | read — what the room is about.
  final String activity;

  const GuestInvite({
    required this.roomId,
    required this.title,
    this.posterUrl,
    required this.inviterName,
    required this.inviterUsername,
    required this.roomStatus,
    required this.createdAt,
    this.activity = 'watch',
  });

  bool get isLive => roomStatus == 'live';
  bool get isReading => activity == 'read';
  bool get isGame => activity == 'play';

  factory GuestInvite.fromJson(Map<String, dynamic> j) => GuestInvite(
        roomId: j['room_id'] as String,
        title: (j['title'] as String?) ?? '',
        posterUrl: j['poster_url'] as String?,
        inviterName: (j['inviter_name'] as String?) ?? '',
        inviterUsername: (j['inviter_username'] as String?) ?? '',
        roomStatus: (j['room_status'] as String?) ?? 'lobby',
        createdAt: tryParseServerUtc(j['created_at'] as String?)?.toLocal() ?? DateTime.now(),
        activity: (j['activity'] as String?) ?? 'watch',
      );
}
