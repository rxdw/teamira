import '../utils/server_time.dart';

/// Mirrors `SharedDiaryPersonOut` in backend/app/schemas.py — one
/// person's side of a shared evening.
///
/// [note] being null stays deliberately ambiguous: either they didn't
/// leave one, or their own privacy settings hide it — the backend
/// refuses to tell these apart on purpose (see PartnerPrefs there).
/// [rating] used to work the same way, but no longer always does:
/// [ratingHidden] distinguishes "hidden because you haven't rated this
/// title yourself yet" (see app/sincerity.py's spoiler_unlock/
/// formed_own_opinion pair) from a plain "didn't rate it" or a
/// privacy-hidden one — only the first of those is worth a "открыть за
/// N очков" affordance in the UI.
class SharedDiaryPerson {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final int? rating;
  final bool ratingHidden;
  final String? note;
  final DateTime? watchedAt;
  final String entryId;
  final bool isMe;

  const SharedDiaryPerson({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.rating,
    this.ratingHidden = false,
    this.note,
    this.watchedAt,
    required this.entryId,
    this.isMe = false,
  });

  String get name => (displayName?.trim().isNotEmpty ?? false) ? displayName! : username;

  factory SharedDiaryPerson.fromJson(Map<String, dynamic> json) => SharedDiaryPerson(
        userId: json['user_id'] as String? ?? '',
        username: json['username'] as String? ?? '',
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        rating: json['rating'] as int?,
        ratingHidden: json['rating_hidden'] as bool? ?? false,
        note: json['note'] as String?,
        watchedAt: tryParseServerUtc(json['watched_at'] as String?),
        entryId: json['entry_id'] as String? ?? '',
        isMe: json['is_me'] as bool? ?? false,
      );
}

/// Mirrors `SharedDiaryItemOut` — one title on the shared diary, with
/// everyone's side merged into a single card. Two people who both logged
/// the same film are one entry here, not two, which is the whole reason
/// this screen exists rather than just showing each other's feeds.
class SharedDiaryItem {
  final String mediaId;
  final String source;
  final String mediaType;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  final String? backdropUrl;
  final int? year;
  final List<String> genres;
  final int? runtimeMinutes;
  final DateTime? watchedAt;
  final bool watchedTogether;
  final List<SharedDiaryPerson> people;
  /// Only set when everyone visible on this card left a rating — one
  /// person's score disagrees with nothing.
  final int? ratingGap;

  const SharedDiaryItem({
    required this.mediaId,
    required this.source,
    required this.mediaType,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.genres = const [],
    this.runtimeMinutes,
    this.watchedAt,
    this.watchedTogether = false,
    this.people = const [],
    this.ratingGap,
  });

  String title(bool ru) {
    final primary = ru ? titleRu : titleEn;
    return (primary?.trim().isNotEmpty ?? false)
        ? primary!
        : (titleEn ?? titleRu ?? '—');
  }

  SharedDiaryPerson? get me {
    for (final p in people) {
      if (p.isMe) return p;
    }
    return null;
  }

  List<SharedDiaryPerson> get others => people.where((p) => !p.isMe).toList();

  factory SharedDiaryItem.fromJson(Map<String, dynamic> json) => SharedDiaryItem(
        mediaId: json['media_id'] as String? ?? '',
        source: json['source'] as String? ?? '',
        mediaType: json['media_type'] as String? ?? 'movie',
        titleRu: json['title_ru'] as String?,
        titleEn: json['title_en'] as String?,
        posterUrl: json['poster_url'] as String?,
        backdropUrl: json['backdrop_url'] as String?,
        year: json['year'] as int?,
        genres: (json['genres'] as List? ?? const []).map((e) => e.toString()).toList(),
        runtimeMinutes: json['runtime_minutes'] as int?,
        watchedAt: tryParseServerUtc(json['watched_at'] as String?),
        watchedTogether: json['watched_together'] as bool? ?? false,
        people: (json['people'] as List? ?? const [])
            .map((e) => SharedDiaryPerson.fromJson(e as Map<String, dynamic>))
            .toList(),
        ratingGap: json['rating_gap'] as int?,
      );
}

/// Mirrors `SharedDiaryOut` — one cursor-paginated page.
class SharedDiaryPage {
  final List<SharedDiaryItem> items;
  /// Send back as `before` to fetch older evenings. Null means this is
  /// the last page.
  final String? nextBefore;
  final List<String> memberUsernames;

  const SharedDiaryPage({
    this.items = const [],
    this.nextBefore,
    this.memberUsernames = const [],
  });

  bool get hasMore => nextBefore != null;

  factory SharedDiaryPage.fromJson(Map<String, dynamic> json) => SharedDiaryPage(
        items: (json['items'] as List? ?? const [])
            .map((e) => SharedDiaryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextBefore: json['next_before'] as String?,
        memberUsernames:
            (json['member_usernames'] as List? ?? const []).map((e) => e.toString()).toList(),
      );
}

/// Mirrors `SharedStatsOut` — "наш год", the couple's own recap.
class SharedStats {
  final String period;
  final String periodLabel;
  final int eveningsTogether;
  final int eveningsSharedTotal;
  final double hoursTogether;
  final List<String> topGenres;
  /// username -> their average rating across shared entries.
  final Map<String, double> averageRatings;
  final SharedDiaryItem? biggestDisagreement;
  final SharedDiaryItem? bestSharedPick;
  final int longestStreakDays;
  final DateTime? firstEveningAt;
  final int plannedCount;
  /// username -> how many co-view entries (planned or watched) they
  /// added, same window as the rest of this object. Not derived from
  /// the shared diary rows like everything else here — see the
  /// backend's own comment on `added_by_counts`.
  final Map<String, int> addedByCounts;

  const SharedStats({
    this.period = 'year',
    this.periodLabel = '',
    this.eveningsTogether = 0,
    this.eveningsSharedTotal = 0,
    this.hoursTogether = 0,
    this.topGenres = const [],
    this.averageRatings = const {},
    this.biggestDisagreement,
    this.bestSharedPick,
    this.longestStreakDays = 0,
    this.firstEveningAt,
    this.plannedCount = 0,
    this.addedByCounts = const {},
  });

  bool get isEmpty => eveningsSharedTotal == 0;

  factory SharedStats.fromJson(Map<String, dynamic> json) => SharedStats(
        period: json['period'] as String? ?? 'year',
        periodLabel: json['period_label'] as String? ?? '',
        eveningsTogether: json['evenings_together'] as int? ?? 0,
        eveningsSharedTotal: json['evenings_shared_total'] as int? ?? 0,
        hoursTogether: (json['hours_together'] as num?)?.toDouble() ?? 0,
        topGenres: (json['top_genres'] as List? ?? const []).map((e) => e.toString()).toList(),
        averageRatings: (json['average_ratings'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ) ??
            const {},
        biggestDisagreement: json['biggest_disagreement'] == null
            ? null
            : SharedDiaryItem.fromJson(json['biggest_disagreement'] as Map<String, dynamic>),
        bestSharedPick: json['best_shared_pick'] == null
            ? null
            : SharedDiaryItem.fromJson(json['best_shared_pick'] as Map<String, dynamic>),
        longestStreakDays: json['longest_streak_days'] as int? ?? 0,
        firstEveningAt: tryParseServerUtc(json['first_evening_at'] as String?),
        plannedCount: json['planned_count'] as int? ?? 0,
        addedByCounts: (json['added_by_counts'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const {},
      );
}

/// Mirrors `PartnerPrefsOut` — this person's own sharing settings for
/// this circle. Note these are per-person: turning [autoShareLogs] off
/// hides *your* evenings from the shared diary, never your partner's.
class PartnerPrefs {
  final bool autoShareLogs;
  final bool shareRatings;
  final bool shareNotes;

  const PartnerPrefs({
    this.autoShareLogs = true,
    this.shareRatings = true,
    this.shareNotes = false,
  });

  PartnerPrefs copyWith({bool? autoShareLogs, bool? shareRatings, bool? shareNotes}) =>
      PartnerPrefs(
        autoShareLogs: autoShareLogs ?? this.autoShareLogs,
        shareRatings: shareRatings ?? this.shareRatings,
        shareNotes: shareNotes ?? this.shareNotes,
      );

  factory PartnerPrefs.fromJson(Map<String, dynamic> json) => PartnerPrefs(
        autoShareLogs: json['auto_share_logs'] as bool? ?? true,
        shareRatings: json['share_ratings'] as bool? ?? true,
        shareNotes: json['share_notes'] as bool? ?? false,
      );
}
