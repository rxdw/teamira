import '../utils/server_time.dart';
import 'media_item.dart';

/// Client mirrors of the pair album schemas in backend/app/schemas.py
/// (`Album*Out`, `Capsule*Out`). The rules — what is sealed from whom,
/// until when — are enforced server-side; these classes only carry what the
/// server chose to send, so a sealed note simply has an empty `body` here
/// rather than something the UI has to remember to hide.

/// A calendar day with no time and no timezone ("2026-09-29"). Kept as a
/// `DateTime` at local midnight so `difference`/`add` behave, but always
/// built from the y/m/d the server sent — never from an instant.
DateTime? parseAlbumDay(Object? raw) {
  if (raw is! String || raw.length < 10) return null;
  final y = int.tryParse(raw.substring(0, 4));
  final m = int.tryParse(raw.substring(5, 7));
  final d = int.tryParse(raw.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

String albumDayToWire(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Whole calendar days from [a] to [b], ignoring the time of day and DST
/// shifts (which a plain `Duration.inDays` gets wrong twice a year).
int albumDaysBetween(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

class AlbumPerson {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final bool isYou;

  const AlbumPerson({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    required this.isYou,
  });

  String get name =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  String get letter => name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

  factory AlbumPerson.fromJson(Map<String, dynamic> j) => AlbumPerson(
        userId: j['user_id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String?,
        avatarPreset: j['avatar_preset'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        isYou: j['is_you'] as bool? ?? false,
      );
}

class AlbumFirstEvening {
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  final DateTime? watchedAt;

  const AlbumFirstEvening({this.titleRu, this.titleEn, this.posterUrl, this.watchedAt});

  factory AlbumFirstEvening.fromJson(Map<String, dynamic> j) => AlbumFirstEvening(
        titleRu: j['title_ru'] as String?,
        titleEn: j['title_en'] as String?,
        posterUrl: j['poster_url'] as String?,
        watchedAt: j['watched_at'] == null ? null : parseServerUtc(j['watched_at'] as String),
      );
}

/// `GET /partner/album` — everything the hub card and the anniversary
/// screen need in one round trip.
class AlbumStatus {
  final bool isCouple;

  /// Whether either of the two has premium: no ceiling on notes and
  /// capsules, and the anniversary date. Reading is never gated, so
  /// everything below stays visible when this is false — and a free circle
  /// still has the small allowance described by the limits further down.
  final bool isPremium;

  /// The server's calendar day. Countdowns are drawn from this, never from
  /// the phone's own clock, so a shifted clock can't fake an opening.
  final DateTime serverToday;
  final DateTime? togetherSince;
  final String? togetherSetBy;
  final DateTime? linkedOn;
  final List<AlbumPerson> people;
  final int eveningsTogether;
  final AlbumFirstEvening? firstEvening;
  final int pagesCount;
  final int unreadPages;
  final int waitingMine;
  final int waitingPartner;
  final int capsulesSealed;
  final int capsulesReady;
  final bool hasContent;

  /// The free allowance, exactly as the server sent it (never hardcoded
  /// here). A null limit means no ceiling — premium. Notes are *mine*
  /// (counted per person), capsules are the couple's; both count what
  /// exists right now. See backend app/pair_album.py.
  final int? notesLimit;
  final int notesUsed;
  final int? capsulesLimit;
  final int capsulesUsed;

  const AlbumStatus({
    required this.isCouple,
    required this.isPremium,
    required this.serverToday,
    this.togetherSince,
    this.togetherSetBy,
    this.linkedOn,
    this.people = const [],
    this.eveningsTogether = 0,
    this.firstEvening,
    this.pagesCount = 0,
    this.unreadPages = 0,
    this.waitingMine = 0,
    this.waitingPartner = 0,
    this.capsulesSealed = 0,
    this.capsulesReady = 0,
    this.hasContent = false,
    this.notesLimit,
    this.notesUsed = 0,
    this.capsulesLimit,
    this.capsulesUsed = 0,
  });

  /// Free notes still unspent, or null when there is no ceiling.
  int? get notesLeft {
    final limit = notesLimit;
    if (limit == null) return null;
    final left = limit - notesUsed;
    return left < 0 ? 0 : left;
  }

  /// Free capsules still unspent, or null when there is no ceiling.
  int? get capsulesLeft {
    final limit = capsulesLimit;
    if (limit == null) return null;
    final left = limit - capsulesUsed;
    return left < 0 ? 0 : left;
  }

  /// A *new* note can be started. Rewriting a note I already left never
  /// needs this — it costs no slot.
  bool get canWriteNote => notesLeft == null || notesLeft! > 0;

  /// A new capsule can be sealed. Adding my letter to a capsule the partner
  /// sealed is never gated.
  bool get canCreateCapsule => capsulesLeft == null || capsulesLeft! > 0;

  AlbumPerson? get me {
    for (final p in people) {
      if (p.isYou) return p;
    }
    return null;
  }

  AlbumPerson? get partner {
    for (final p in people) {
      if (!p.isYou) return p;
    }
    return null;
  }

  /// Days together counting the first day as day 1 — "100 days" on the
  /// hundredth calendar day. Mirrors backend `days_together`.
  int? get daysTogether {
    final since = togetherSince;
    if (since == null) return null;
    return albumDaysBetween(since, serverToday) + 1;
  }

  /// Something worth drawing attention to on the hub card.
  bool get hasNews => unreadPages > 0 || capsulesReady > 0 || waitingPartner > 0;

  factory AlbumStatus.fromJson(Map<String, dynamic> j) => AlbumStatus(
        isCouple: j['is_couple'] as bool? ?? false,
        isPremium: j['is_premium'] as bool? ?? false,
        serverToday: parseAlbumDay(j['server_today']) ?? DateTime.now(),
        togetherSince: parseAlbumDay(j['together_since']),
        togetherSetBy: j['together_set_by'] as String?,
        linkedOn: parseAlbumDay(j['linked_on']),
        people: ((j['people'] as List?) ?? const [])
            .map((e) => AlbumPerson.fromJson(e as Map<String, dynamic>))
            .toList(),
        eveningsTogether: j['evenings_together'] as int? ?? 0,
        firstEvening: j['first_evening'] == null
            ? null
            : AlbumFirstEvening.fromJson(j['first_evening'] as Map<String, dynamic>),
        pagesCount: j['pages_count'] as int? ?? 0,
        unreadPages: j['unread_pages'] as int? ?? 0,
        waitingMine: j['waiting_mine'] as int? ?? 0,
        waitingPartner: j['waiting_partner'] as int? ?? 0,
        capsulesSealed: j['capsules_sealed'] as int? ?? 0,
        capsulesReady: j['capsules_ready'] as int? ?? 0,
        hasContent: j['has_content'] as bool? ?? false,
        notesLimit: j['notes_limit'] as int?,
        notesUsed: j['notes_used'] as int? ?? 0,
        capsulesLimit: j['capsules_limit'] as int?,
        capsulesUsed: j['capsules_used'] as int? ?? 0,
      );
}

class AlbumNote {
  final String id;
  final bool isMine;
  final String authorUsername;

  /// Empty for a note the server is still sealing from me.
  final String body;
  final String? mood;

  /// On my note: the partner's reply. On the partner's note: mine.
  final String? reaction;
  final bool opened;
  final DateTime createdAt;

  const AlbumNote({
    required this.id,
    required this.isMine,
    required this.authorUsername,
    required this.body,
    this.mood,
    this.reaction,
    this.opened = false,
    required this.createdAt,
  });

  factory AlbumNote.fromJson(Map<String, dynamic> j) => AlbumNote(
        id: j['id'] as String,
        isMine: j['is_mine'] as bool? ?? false,
        authorUsername: j['author_username'] as String? ?? '',
        body: j['body'] as String? ?? '',
        mood: j['mood'] as String?,
        reaction: j['reaction'] as String?,
        opened: j['opened'] as bool? ?? false,
        createdAt: parseServerUtc(j['created_at'] as String),
      );
}

/// One title's page in the shared book — my note and (once revealed) the
/// partner's, for a single viewing of the title.
class AlbumPage {
  final String source;
  final String mediaId;
  final String mediaType;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  final int? year;
  final int round;
  final bool revealed; // state == "revealed"
  final AlbumNote? mine;
  final AlbumNote? partner;

  /// The partner has left a note that is still sealed — a fact, never text.
  final bool partnerSealed;
  final String? entryId;
  final DateTime? eveningOn;
  final DateTime? revealedAt;
  final bool unread;

  const AlbumPage({
    required this.source,
    required this.mediaId,
    required this.mediaType,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
    this.year,
    required this.round,
    required this.revealed,
    this.mine,
    this.partner,
    this.partnerSealed = false,
    this.entryId,
    this.eveningOn,
    this.revealedAt,
    this.unread = false,
  });

  String title({required bool ru}) =>
      (ru ? (titleRu ?? titleEn) : (titleEn ?? titleRu)) ?? '';

  /// Stable across reloads — used to key animations and match a planned
  /// card to its note.
  String get key => '$source:$mediaId';

  /// A minimal [MediaItem] from the page's snapshot — enough to rewrite a
  /// note on this title (the server keys notes by source + id and refreshes
  /// its own snapshot from whatever the client sends).
  MediaItem toMediaItem() => MediaItem(
        id: mediaId,
        mediaType: mediaType,
        externalIds: const ExternalIds(),
        title: LocalizedText(ru: titleRu, en: titleEn),
        description: const LocalizedText(),
        posterUrl: posterUrl,
        year: year,
        source: source,
      );

  factory AlbumPage.fromJson(Map<String, dynamic> j) => AlbumPage(
        source: j['source'] as String,
        mediaId: j['media_id'] as String,
        mediaType: j['media_type'] as String? ?? 'movie',
        titleRu: j['title_ru'] as String?,
        titleEn: j['title_en'] as String?,
        posterUrl: j['poster_url'] as String?,
        year: j['year'] as int?,
        round: j['round'] as int? ?? 1,
        revealed: j['state'] == 'revealed',
        mine: j['mine'] == null ? null : AlbumNote.fromJson(j['mine'] as Map<String, dynamic>),
        partner:
            j['partner'] == null ? null : AlbumNote.fromJson(j['partner'] as Map<String, dynamic>),
        partnerSealed: j['partner_sealed'] as bool? ?? false,
        entryId: j['entry_id'] as String?,
        eveningOn: parseAlbumDay(j['evening_on']),
        revealedAt: j['revealed_at'] == null ? null : parseServerUtc(j['revealed_at'] as String),
        unread: j['unread'] as bool? ?? false,
      );
}

class AlbumPages {
  final List<AlbumPage> items;
  final DateTime? nextBefore;
  const AlbumPages({required this.items, this.nextBefore});

  factory AlbumPages.fromJson(Map<String, dynamic> j) => AlbumPages(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => AlbumPage.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextBefore: j['next_before'] == null ? null : parseServerUtc(j['next_before'] as String),
      );
}

class CapsuleLetter {
  final bool isMine;
  final String authorUsername;
  final String body;
  final DateTime sealedAt;

  const CapsuleLetter({
    required this.isMine,
    required this.authorUsername,
    required this.body,
    required this.sealedAt,
  });

  factory CapsuleLetter.fromJson(Map<String, dynamic> j) => CapsuleLetter(
        isMine: j['is_mine'] as bool? ?? false,
        authorUsername: j['author_username'] as String? ?? '',
        body: j['body'] as String? ?? '',
        sealedAt: parseServerUtc(j['sealed_at'] as String),
      );
}

class Capsule {
  final String id;
  final String? title;
  final DateTime opensOn;
  final DateTime createdAt;
  final String? createdByUsername;
  final bool createdByMe;
  final bool isOpen; // state == "open"
  final int daysLeft;
  final bool myLetterSealed;
  final bool partnerLetterSealed;

  /// Empty until the capsule is open — the server never sends sealed text.
  final List<CapsuleLetter> letters;
  final bool openedByMe;
  final bool canDelete;

  const Capsule({
    required this.id,
    this.title,
    required this.opensOn,
    required this.createdAt,
    this.createdByUsername,
    required this.createdByMe,
    required this.isOpen,
    required this.daysLeft,
    required this.myLetterSealed,
    required this.partnerLetterSealed,
    this.letters = const [],
    this.openedByMe = false,
    this.canDelete = false,
  });

  /// Open, and this person hasn't watched it open yet — the ceremony is
  /// still owed.
  bool get ready => isOpen && !openedByMe;

  factory Capsule.fromJson(Map<String, dynamic> j) => Capsule(
        id: j['id'] as String,
        title: j['title'] as String?,
        opensOn: parseAlbumDay(j['opens_on']) ?? DateTime.now(),
        createdAt: parseServerUtc(j['created_at'] as String),
        createdByUsername: j['created_by_username'] as String?,
        createdByMe: j['created_by_me'] as bool? ?? false,
        isOpen: j['state'] == 'open',
        daysLeft: j['days_left'] as int? ?? 0,
        myLetterSealed: j['my_letter_sealed'] as bool? ?? false,
        partnerLetterSealed: j['partner_letter_sealed'] as bool? ?? false,
        letters: ((j['letters'] as List?) ?? const [])
            .map((e) => CapsuleLetter.fromJson(e as Map<String, dynamic>))
            .toList(),
        openedByMe: j['opened_by_me'] as bool? ?? false,
        canDelete: j['can_delete'] as bool? ?? false,
      );
}

/// Decorative note tags and reply reactions. Closed sets on the server too
/// (`ALLOWED_MOODS` / `ALLOWED_REACTIONS` in backend/app/pair_album.py) —
/// keep the two lists in step.
const List<String> kAlbumMoods = ['💌', '😘', '🍿', '🥰', '😴', '🌙', '✨', '🤭'];
const List<String> kAlbumReactions = ['❤️', '😂', '🥹', '🔥', '👏'];

const int kAlbumNoteMaxChars = 400;
const int kAlbumLetterMaxChars = 4000;
const int kAlbumCapsuleTitleMaxChars = 60;
const int kAlbumCapsuleMinDays = 30;
const int kAlbumCapsuleMaxDays = 3650;

/// Builds the wire payload for a note from the client's own [MediaItem].
Map<String, dynamic> albumNotePayload(MediaItem item, String body, String? mood) => {
      'item': item.toJson(),
      'body': body,
      'mood': mood,
    };
