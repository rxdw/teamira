import '../utils/server_time.dart';
import 'pair_album.dart' show parseAlbumDay;

/// Client mirrors of backend/app/routers/circle_review.py. What is sealed
/// from whom is decided by the server: a person who hasn't revealed yet
/// simply arrives with a null rating and an empty line.

class ReviewPerson {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final bool isYou;
  final bool done;
  final bool skipped;
  final int? rating;
  final List<String> tags;
  final String? line;

  const ReviewPerson({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    required this.isYou,
    required this.done,
    required this.skipped,
    this.rating,
    this.tags = const [],
    this.line,
  });

  String get name =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;
  String get letter => name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

  factory ReviewPerson.fromJson(Map<String, dynamic> j) => ReviewPerson(
        userId: j['user_id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String?,
        avatarPreset: j['avatar_preset'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        isYou: j['is_you'] == true,
        done: j['done'] == true,
        skipped: j['skipped'] == true,
        rating: (j['rating'] as num?)?.toInt(),
        tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
        line: j['line'] as String?,
      );
}

/// unison | close | split | solo
class ReviewSummary {
  final double? average;
  final int? spread;
  final String verdict;
  final int ratedCount;
  final List<String> sharedTags;

  const ReviewSummary({
    this.average,
    this.spread,
    required this.verdict,
    required this.ratedCount,
    this.sharedTags = const [],
  });

  factory ReviewSummary.fromJson(Map<String, dynamic> j) => ReviewSummary(
        average: (j['average'] as num?)?.toDouble(),
        spread: (j['spread'] as num?)?.toInt(),
        verdict: (j['verdict'] as String?) ?? 'solo',
        ratedCount: (j['rated_count'] as num?)?.toInt() ?? 0,
        sharedTags: ((j['shared_tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

class ReviewMoment {
  final int positionMs;
  final int people;
  final bool shared;
  final int count;
  final String top;

  /// A book's moments: the place ("c3:p12", "p42"), so the timeline can say
  /// which chapter or page it was. Null for a film.
  final String? locator;

  const ReviewMoment({
    required this.positionMs,
    required this.people,
    required this.shared,
    required this.count,
    required this.top,
    this.locator,
  });

  factory ReviewMoment.fromJson(Map<String, dynamic> j) => ReviewMoment(
        positionMs: (j['position_ms'] as num).toInt(),
        people: (j['people'] as num?)?.toInt() ?? 1,
        shared: j['shared'] == true,
        count: (j['count'] as num?)?.toInt() ?? 1,
        top: (j['top'] as String?) ?? '',
        locator: j['locator'] as String?,
      );
}

class CircleReview {
  final String id;
  final String origin; // room | logged
  final String? roomId;
  final String mediaId;
  final String mediaType;
  final String source;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  final int? year;
  final DateTime? watchedOn;
  final bool revealed;
  final DateTime expiresAt;
  final bool iAmDone;
  final List<ReviewPerson> people;
  final ReviewSummary? summary;
  final List<ReviewMoment>? moments;
  final bool momentsLocked;
  final DateTime createdAt;

  const CircleReview({
    required this.id,
    required this.origin,
    this.roomId,
    required this.mediaId,
    required this.mediaType,
    required this.source,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
    this.year,
    this.watchedOn,
    required this.revealed,
    required this.expiresAt,
    required this.iAmDone,
    required this.people,
    this.summary,
    this.moments,
    required this.momentsLocked,
    required this.createdAt,
  });

  String get title => (titleRu != null && titleRu!.trim().isNotEmpty) ? titleRu! : (titleEn ?? '');
  ReviewPerson? get me {
    for (final p in people) {
      if (p.isYou) return p;
    }
    return null;
  }

  int get doneCount => people.where((p) => p.done).length;
  List<ReviewPerson> get waitingOn => people.where((p) => !p.done).toList();

  factory CircleReview.fromJson(Map<String, dynamic> j) => CircleReview(
        id: j['id'] as String,
        origin: (j['origin'] as String?) ?? 'logged',
        roomId: j['room_id'] as String?,
        mediaId: j['media_id'] as String,
        mediaType: j['media_type'] as String,
        source: j['source'] as String,
        titleRu: j['title_ru'] as String?,
        titleEn: j['title_en'] as String?,
        posterUrl: j['poster_url'] as String?,
        year: (j['year'] as num?)?.toInt(),
        watchedOn: parseAlbumDay(j['watched_on']),
        revealed: j['revealed'] == true,
        expiresAt: tryParseServerUtc(j['expires_at'] as String?)?.toLocal() ?? DateTime.now(),
        iAmDone: j['i_am_done'] == true,
        people: ((j['people'] as List?) ?? const [])
            .map((e) => ReviewPerson.fromJson(e as Map<String, dynamic>))
            .toList(),
        summary: j['summary'] == null
            ? null
            : ReviewSummary.fromJson(j['summary'] as Map<String, dynamic>),
        moments: j['moments'] == null
            ? null
            : (j['moments'] as List)
                .map((e) => ReviewMoment.fromJson(e as Map<String, dynamic>))
                .toList(),
        momentsLocked: j['moments_locked'] == true,
        createdAt: tryParseServerUtc(j['created_at'] as String?)?.toLocal() ?? DateTime.now(),
      );
}
