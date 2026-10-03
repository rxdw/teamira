import '../services/app_translations.dart';
import '../utils/server_time.dart';
class GenreCount {
  final String genre;
  final int count;
  const GenreCount({required this.genre, required this.count});

  factory GenreCount.fromJson(Map<String, dynamic> json) => GenreCount(
        genre: json['genre'] as String,
        count: json['count'] as int,
      );
}

/// Mirrors `ProfileYearStats` — powers the three stat tiles + activity grid
/// on the Profile tab.
class ProfileYearStats {
  final int movies;
  final int series;
  final int games;
  final int anime;
  final int books;
  final int manga;
  final int total;
  final List<GenreCount> topGenres;
  final int streakDays;

  const ProfileYearStats({
    required this.movies,
    required this.series,
    required this.games,
    this.anime = 0,
    this.books = 0,
    this.manga = 0,
    required this.total,
    required this.topGenres,
    required this.streakDays,
  });

  factory ProfileYearStats.fromJson(Map<String, dynamic> json) =>
      ProfileYearStats(
        movies: json['movies'] as int,
        series: json['series'] as int,
        games: json['games'] as int,
        anime: json['anime'] as int? ?? 0,
        books: json['books'] as int? ?? 0,
        manga: json['manga'] as int? ?? 0,
        total: json['total'] as int,
        topGenres: (json['top_genres'] as List? ?? const [])
            .map((e) => GenreCount.fromJson(e as Map<String, dynamic>))
            .toList(),
        streakDays: json['streak_days'] as int,
      );
}

/// Mirrors `WrappedBreakdown`.
class WrappedBreakdown {
  final int movies;
  final int series;
  final int anime;
  final int games;
  final int books;
  final int manga;

  const WrappedBreakdown({
    this.movies = 0,
    this.series = 0,
    this.anime = 0,
    this.games = 0,
    this.books = 0,
    this.manga = 0,
  });

  factory WrappedBreakdown.fromJson(Map<String, dynamic> json) =>
      WrappedBreakdown(
        movies: json['movies'] as int? ?? 0,
        series: json['series'] as int? ?? 0,
        anime: json['anime'] as int? ?? 0,
        games: json['games'] as int? ?? 0,
        books: json['books'] as int? ?? 0,
        manga: json['manga'] as int? ?? 0,
      );
}

/// Mirrors `WrappedStat` — powers the Wrapped screen (Profile → "your
/// wrapped"). One call per period; the client just switches `period` and
/// re-fetches when the person taps month/year.
class WrappedStat {
  final String period; // "month" | "year"
  final String periodLabel;
  final int totalLogged;
  final double hours;
  final WrappedBreakdown breakdown;
  final List<GenreCount> topGenres;
  final int longestStreak;
  final String? busiestDay;
  final String? favoriteTitle;
  final String? favoritePoster;
  final String? favoriteMediaType;
  final bool isPremium;
  final bool unlocked;

  const WrappedStat({
    required this.period,
    required this.periodLabel,
    required this.totalLogged,
    required this.hours,
    required this.breakdown,
    required this.topGenres,
    required this.longestStreak,
    this.busiestDay,
    this.favoriteTitle,
    this.favoritePoster,
    this.favoriteMediaType,
    this.isPremium = true,
    this.unlocked = true,
  });

  factory WrappedStat.fromJson(Map<String, dynamic> json) => WrappedStat(
        period: json['period'] as String,
        periodLabel: json['period_label'] as String,
        totalLogged: json['total_logged'] as int,
        hours: (json['hours'] as num).toDouble(),
        breakdown: WrappedBreakdown.fromJson(
            (json['breakdown'] as Map<String, dynamic>?) ?? const {}),
        topGenres: (json['top_genres'] as List? ?? const [])
            .map((e) => GenreCount.fromJson(e as Map<String, dynamic>))
            .toList(),
        longestStreak: json['longest_streak'] as int,
        busiestDay: json['busiest_day'] as String?,
        favoriteTitle: json['favorite_title'] as String?,
        favoritePoster: json['favorite_poster'] as String?,
        favoriteMediaType: json['favorite_media_type'] as String?,
        isPremium: json['is_premium'] as bool? ?? true,
        unlocked: json['unlocked'] as bool? ?? true,
      );
}

class WrappedTitleMoment {
  final String title;
  final String dateLabel;
  final String? posterUrl;
  const WrappedTitleMoment({required this.title, required this.dateLabel, this.posterUrl});
  factory WrappedTitleMoment.fromJson(Map<String, dynamic> json) =>
      WrappedTitleMoment(
        title: json['title'] as String,
        dateLabel: json['date_label'] as String,
        posterUrl: json['poster_url'] as String?,
      );
}

class WrappedDirectorCount {
  final String name;
  final int count;
  const WrappedDirectorCount({required this.name, required this.count});
  factory WrappedDirectorCount.fromJson(Map<String, dynamic> json) =>
      WrappedDirectorCount(name: json['name'] as String, count: json['count'] as int);
}

class WrappedDecadeBucket {
  final String label;
  final int count;
  final double percent;
  const WrappedDecadeBucket({required this.label, required this.count, required this.percent});
  factory WrappedDecadeBucket.fromJson(Map<String, dynamic> json) => WrappedDecadeBucket(
        label: json['label'] as String,
        count: json['count'] as int,
        percent: (json['percent'] as num).toDouble(),
      );
}

class WrappedTimelineBucket {
  final String label; // day-of-month ("1".."31") for a month summary, month abbrev ("янв".tr) otherwise
  final int count;
  const WrappedTimelineBucket({required this.label, required this.count});
  factory WrappedTimelineBucket.fromJson(Map<String, dynamic> json) =>
      WrappedTimelineBucket(label: json['label'] as String, count: json['count'] as int);
}

class WrappedWeekdayCount {
  final int weekday; // 0=Mon..6=Sun
  final int count;
  const WrappedWeekdayCount({required this.weekday, required this.count});
  factory WrappedWeekdayCount.fromJson(Map<String, dynamic> json) =>
      WrappedWeekdayCount(weekday: json['weekday'] as int, count: json['count'] as int);
}

class WrappedGenreShare {
  final String genre;
  final int count;
  final double percent;
  const WrappedGenreShare({required this.genre, required this.count, required this.percent});
  factory WrappedGenreShare.fromJson(Map<String, dynamic> json) => WrappedGenreShare(
        genre: json['genre'] as String,
        count: json['count'] as int,
        percent: (json['percent'] as num).toDouble(),
      );
}

class WrappedReviewItem {
  final String title;
  final int? rating;
  final String? note;
  final String? dateLabel;
  final String? posterUrl;
  const WrappedReviewItem({required this.title, this.rating, this.note, this.dateLabel, this.posterUrl});
  factory WrappedReviewItem.fromJson(Map<String, dynamic> json) => WrappedReviewItem(
        title: json['title'] as String,
        rating: json['rating'] as int?,
        note: json['note'] as String?,
        dateLabel: json['date_label'] as String?,
        posterUrl: json['poster_url'] as String?,
      );
}

class WrappedReceiptItem {
  final String title;
  final int count;
  const WrappedReceiptItem({required this.title, required this.count});
  factory WrappedReceiptItem.fromJson(Map<String, dynamic> json) =>
      WrappedReceiptItem(title: json['title'] as String, count: json['count'] as int);
}

/// One (year) or (year, month) that the account actually has diary
/// entries in — mirrors `WrappedMonthPeriod` inside `WrappedPeriods`.
class WrappedMonthPeriod {
  final int year;
  final int month;
  const WrappedMonthPeriod({required this.year, required this.month});
  factory WrappedMonthPeriod.fromJson(Map<String, dynamic> json) =>
      WrappedMonthPeriod(year: json['year'] as int, month: json['month'] as int);
}

/// Mirrors `WrappedPeriodsOut` — powers the period picker: only ever
/// offers a year or month the account actually has something logged in.
class WrappedPeriods {
  final List<int> years;
  final List<WrappedMonthPeriod> months;
  final bool hasAny;
  const WrappedPeriods({this.years = const [], this.months = const [], this.hasAny = false});

  factory WrappedPeriods.fromJson(Map<String, dynamic> json) => WrappedPeriods(
        years: (json['years'] as List? ?? const []).map((e) => e as int).toList(),
        months: (json['months'] as List? ?? const [])
            .map((e) => WrappedMonthPeriod.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasAny: json['has_any'] as bool? ?? false,
      );
}

class WrappedRatingBucket {
  final int rating; // 1-10
  final int count;
  const WrappedRatingBucket({required this.rating, required this.count});
  factory WrappedRatingBucket.fromJson(Map<String, dynamic> json) =>
      WrappedRatingBucket(rating: json['rating'] as int, count: json['count'] as int);
}

/// Mirrors `WrappedSummary` — powers the full "envelope -> cards ->
/// letter -> receipt" Wrapped flow (Profile → "твой год"/"твой месяц"/
/// "за всё время"). One call per period; every card on screen reads off
/// this same object, nothing fetched separately. `scope` is "month" |
/// "year" | "all" — see ProfileService.wrappedSummary.
class WrappedSummary {
  final String scope;
  final int year;
  final int? month;
  final String periodLabel;
  final String rangeLabel;

  final int totalLogged;
  final double totalHours;

  final WrappedTitleMoment? first;
  final WrappedTitleMoment? last;
  final int daysSpan;

  final List<WrappedDirectorCount> topDirectors;
  final List<WrappedDecadeBucket> decades;

  final int newCount;
  final int rewatchCount;

  final List<WrappedTimelineBucket> timeline;
  final String? busiestTimelineLabel;
  final int longestStreakDays;

  final List<WrappedWeekdayCount> weekdays;
  final double weekendPercent;

  final int soloCount;
  final int companyCount;
  final double soloPercent;

  final int? peakHour;
  final double peakHourPercent;
  final String archetypeLabel;

  final List<WrappedGenreShare> genreMix;
  final String? topGenre;

  final int reviewCount;
  final double averageRating;
  final int fullMarksCount;
  final List<WrappedReviewItem> topReviews;
  final WrappedReviewItem? favoriteReview;
  final List<WrappedRatingBucket> ratingHistogram;

  final int? hoursPercentile;
  final List<WrappedReceiptItem> receiptItems;
  final List<String> posterUrls;

  final bool isPremium;
  final bool unlocked;

  const WrappedSummary({
    required this.scope,
    required this.year,
    this.month,
    required this.periodLabel,
    required this.rangeLabel,
    required this.totalLogged,
    required this.totalHours,
    this.first,
    this.last,
    this.daysSpan = 0,
    this.topDirectors = const [],
    this.decades = const [],
    this.newCount = 0,
    this.rewatchCount = 0,
    this.timeline = const [],
    this.busiestTimelineLabel,
    this.longestStreakDays = 0,
    this.weekdays = const [],
    this.weekendPercent = 0,
    this.soloCount = 0,
    this.companyCount = 0,
    this.soloPercent = 0,
    this.peakHour,
    this.peakHourPercent = 0,
    this.archetypeLabel = '',
    this.genreMix = const [],
    this.topGenre,
    this.reviewCount = 0,
    this.averageRating = 0,
    this.fullMarksCount = 0,
    this.topReviews = const [],
    this.favoriteReview,
    this.ratingHistogram = const [],
    this.hoursPercentile,
    this.receiptItems = const [],
    this.posterUrls = const [],
    this.isPremium = true,
    this.unlocked = true,
  });

  factory WrappedSummary.fromJson(Map<String, dynamic> json) => WrappedSummary(
        scope: json['scope'] as String? ?? 'year',
        year: json['year'] as int,
        month: json['month'] as int?,
        periodLabel: json['period_label'] as String? ?? '',
        rangeLabel: json['range_label'] as String? ?? '',
        totalLogged: json['total_logged'] as int,
        totalHours: (json['total_hours'] as num).toDouble(),
        first: json['first'] != null
            ? WrappedTitleMoment.fromJson(json['first'] as Map<String, dynamic>)
            : null,
        last: json['last'] != null
            ? WrappedTitleMoment.fromJson(json['last'] as Map<String, dynamic>)
            : null,
        daysSpan: json['days_span'] as int? ?? 0,
        topDirectors: (json['top_directors'] as List? ?? const [])
            .map((e) => WrappedDirectorCount.fromJson(e as Map<String, dynamic>))
            .toList(),
        decades: (json['decades'] as List? ?? const [])
            .map((e) => WrappedDecadeBucket.fromJson(e as Map<String, dynamic>))
            .toList(),
        newCount: json['new_count'] as int? ?? 0,
        rewatchCount: json['rewatch_count'] as int? ?? 0,
        timeline: (json['timeline'] as List? ?? const [])
            .map((e) => WrappedTimelineBucket.fromJson(e as Map<String, dynamic>))
            .toList(),
        busiestTimelineLabel: json['busiest_timeline_label'] as String?,
        longestStreakDays: json['longest_streak_days'] as int? ?? 0,
        weekdays: (json['weekdays'] as List? ?? const [])
            .map((e) => WrappedWeekdayCount.fromJson(e as Map<String, dynamic>))
            .toList(),
        weekendPercent: (json['weekend_percent'] as num?)?.toDouble() ?? 0,
        soloCount: json['solo_count'] as int? ?? 0,
        companyCount: json['company_count'] as int? ?? 0,
        soloPercent: (json['solo_percent'] as num?)?.toDouble() ?? 0,
        peakHour: json['peak_hour'] as int?,
        peakHourPercent: (json['peak_hour_percent'] as num?)?.toDouble() ?? 0,
        archetypeLabel: json['archetype_label'] as String? ?? '',
        genreMix: (json['genre_mix'] as List? ?? const [])
            .map((e) => WrappedGenreShare.fromJson(e as Map<String, dynamic>))
            .toList(),
        topGenre: json['top_genre'] as String?,
        reviewCount: json['review_count'] as int? ?? 0,
        averageRating: (json['average_rating'] as num?)?.toDouble() ?? 0,
        fullMarksCount: json['full_marks_count'] as int? ?? 0,
        topReviews: (json['top_reviews'] as List? ?? const [])
            .map((e) => WrappedReviewItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        favoriteReview: json['favorite_review'] != null
            ? WrappedReviewItem.fromJson(json['favorite_review'] as Map<String, dynamic>)
            : null,
        ratingHistogram: (json['rating_histogram'] as List? ?? const [])
            .map((e) => WrappedRatingBucket.fromJson(e as Map<String, dynamic>))
            .toList(),
        hoursPercentile: json['hours_percentile'] as int?,
        receiptItems: (json['receipt_items'] as List? ?? const [])
            .map((e) => WrappedReceiptItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        posterUrls: (json['poster_urls'] as List? ?? const []).map((e) => e as String).toList(),
        isPremium: json['is_premium'] as bool? ?? true,
        unlocked: json['unlocked'] as bool? ?? true,
      );
}

/// Mirrors `LevelOut` — powers the merged Sincerity screen's level ring.
/// Level and its progress come straight off the account's lifetime
/// sincerity total (see backend/app/sincerity.py::compute_level — that
/// module's docstring covers the old, separate XP system this merged
/// into), so `points` only ever goes up, even when the spendable
/// sincerity balance shown alongside it (see SincerityBalance) gets
/// spent down.
///
/// Everything below `progress` is informational stats for the
/// level-detail screen (how many titles, how many with a note, and so
/// on) — not a per-source breakdown of `points`. For the honest,
/// itemized "where did my points actually come from", see
/// SincerityBalance.history instead.
class ProfileLevel {
  final int level;
  final int points;
  final int pointsIntoLevel;
  final int pointsForNextLevel;
  final double progress;

  final int watchedCount;
  final int reviewsCount;
  final int rewatchCount;
  final int genresCount;
  final int longestStreakEver;
  final int invitesCount;
  final int challengesClaimed;
  final int watchedTogetherCount;
  final int cardSharesCount;

  const ProfileLevel({
    required this.level,
    required this.points,
    required this.pointsIntoLevel,
    required this.pointsForNextLevel,
    required this.progress,
    this.watchedCount = 0,
    this.reviewsCount = 0,
    this.rewatchCount = 0,
    this.genresCount = 0,
    this.longestStreakEver = 0,
    this.invitesCount = 0,
    this.challengesClaimed = 0,
    this.watchedTogetherCount = 0,
    this.cardSharesCount = 0,
  });

  factory ProfileLevel.fromJson(Map<String, dynamic> json) => ProfileLevel(
        level: json['level'] as int,
        points: json['points'] as int,
        pointsIntoLevel: json['points_into_level'] as int,
        pointsForNextLevel: json['points_for_next_level'] as int,
        progress: (json['progress'] as num).toDouble(),
        watchedCount: json['watched_count'] as int? ?? 0,
        reviewsCount: json['reviews_count'] as int? ?? 0,
        rewatchCount: json['rewatch_count'] as int? ?? 0,
        genresCount: json['genres_count'] as int? ?? 0,
        longestStreakEver: json['longest_streak_ever'] as int? ?? 0,
        invitesCount: json['invites_count'] as int? ?? 0,
        challengesClaimed: json['challenges_claimed'] as int? ?? 0,
        watchedTogetherCount: json['watched_together_count'] as int? ?? 0,
        cardSharesCount: json['card_shares_count'] as int? ?? 0,
      );
}

/// Mirrors `ActivityItem` — used for Home's "fresh in your diary" strip as
/// a fallback when a lighter read than the full /diary list is enough.
class ActivityItem {
  final String who;
  final String text;
  final String? mediaType;
  final String createdAt;

  const ActivityItem({
    required this.who,
    required this.text,
    this.mediaType,
    required this.createdAt,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
        who: json['who'] as String,
        text: json['text'] as String,
        mediaType: json['media_type'] as String?,
        createdAt: json['created_at'] as String,
      );
}

/// Mirrors `UserOut`.
class SeenlyUser {
  final String id;
  final String username;
  final DateTime? createdAt;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final String? statusText;

  /// Recovery address, and whether it has been confirmed. Both drive the
  /// Account screen's nudge: an account with no address at all loses its
  /// whole diary to a forgotten password, and an unconfirmed one can't be
  /// used for reset at all (the backend refuses — an unconfirmed address
  /// only proves somebody typed it).
  final String? email;
  final bool emailVerified;

  /// False when this account has never accepted the terms, or accepted a
  /// version older than the current one — the app shows the agreement
  /// sheet on next launch. Accounts created before the EULA existed land
  /// here rather than being locked out.
  final bool eulaCurrent;

  final bool isAdmin;

  const SeenlyUser({
    required this.id,
    required this.username,
    this.createdAt,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.statusText,
    this.email,
    this.emailVerified = false,
    this.eulaCurrent = true,
    this.isAdmin = false,
  });

  /// True when there is no usable way back into this account if the
  /// password is forgotten. Drives the one nudge the Account screen shows.
  bool get needsRecoveryEmail => email == null || !emailVerified;

  /// What the header/friend rows should actually show — the edited
  /// display name if one was ever set, otherwise the login username.
  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory SeenlyUser.fromJson(Map<String, dynamic> json) => SeenlyUser(
        id: json['id'] as String,
        username: json['username'] as String,
        createdAt: tryParseServerUtc(json['created_at'] as String?),
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        statusText: json['status_text'] as String?,
        email: json['email'] as String?,
        emailVerified: json['email_verified'] as bool? ?? false,
        eulaCurrent: json['eula_current'] as bool? ?? true,
        isAdmin: json['is_admin'] as bool? ?? false,
      );
}

/// Mirrors `ProfileMeOut` — the editable identity block returned by
/// GET/PATCH /profile/me. Kept as its own small type (rather than
/// reusing SeenlyUser) since the edit screen only ever talks to that
/// endpoint, not /auth/me.
class ProfileMe {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final String? statusText;
  // "everyone" | "friends" | "nobody" each — see PrivacyLevel below.
  final String privacyWatched;
  final String privacyWatching;
  final String privacyPlanned;
  // Same, for the "favorite" shelf on Profile — see PrivacyShelf.favorites
  // below.
  final String privacyFavorites;

  /// "people can find me by my username" — the opt-out for friend
  /// search. Separate from the four shelf settings above: those decide
  /// what a viewer sees once they're already looking at this profile,
  /// this decides whether a stranger can reach it at all.
  final bool discoverable;
  // Up to 5 favorites shown as a swipeable stories deck on the Profile
  // header banner, in the order the person arranged them — see
  // models.User.top_favorite_picks on the backend. Empty until picked
  // on the favorite-films screen.
  final List<FavoritePick> topFavoritePicks;

  const ProfileMe({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.statusText,
    this.privacyWatched = 'everyone',
    this.privacyWatching = 'everyone',
    this.privacyPlanned = 'everyone',
    this.privacyFavorites = 'everyone',
    this.discoverable = true,
    this.topFavoritePicks = const [],
  });

  factory ProfileMe.fromJson(Map<String, dynamic> json) => ProfileMe(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        statusText: json['status_text'] as String?,
        privacyWatched: json['privacy_watched'] as String? ?? 'everyone',
        privacyWatching: json['privacy_watching'] as String? ?? 'everyone',
        privacyPlanned: json['privacy_planned'] as String? ?? 'everyone',
        privacyFavorites: json['privacy_favorites'] as String? ?? 'everyone',
        discoverable: json['discoverable'] as bool? ?? true,
        topFavoritePicks: (json['top_favorite_picks'] as List? ?? const [])
            .map((e) => FavoritePick.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One slide of the Profile header's stories-style banner — mirrors the
/// backend's `TopFavoritePick` (media_id + source), just enough to match
/// it back up against a full [WatchlistEntry] for its poster/backdrop.
class FavoritePick {
  final String mediaId;
  final String source;
  const FavoritePick({required this.mediaId, required this.source});

  factory FavoritePick.fromJson(Map<String, dynamic> json) => FavoritePick(
        mediaId: json['media_id'] as String,
        source: json['source'] as String,
      );

  Map<String, dynamic> toJson() => {'media_id': mediaId, 'source': source};

  String get key => '$source:$mediaId';
}

/// The shelves a privacy level can be set on — mirrors
/// ProfileUpdateIn.privacy_watched/privacy_watching/privacy_planned/
/// privacy_favorites.
enum PrivacyShelf { watched, watching, planned, favorites }

/// One of the three visibility levels a shelf can be set to. Order here
/// is deliberately most-open-first, matching the settings screen's own
/// top-to-bottom layout.
enum PrivacyLevel { everyone, friends, nobody }

extension PrivacyLevelWire on PrivacyLevel {
  String get wireValue => switch (this) {
        PrivacyLevel.everyone => 'everyone',
        PrivacyLevel.friends => 'friends',
        PrivacyLevel.nobody => 'nobody',
      };

  String get label => switch (this) {
        PrivacyLevel.everyone => 'everyone',
        PrivacyLevel.friends => 'friends only',
        PrivacyLevel.nobody => 'nobody',
      };

  static PrivacyLevel fromWire(String? value) => switch (value) {
        'friends' => PrivacyLevel.friends,
        'nobody' => PrivacyLevel.nobody,
        _ => PrivacyLevel.everyone,
      };
}

/// The fixed set of bundled-in-app avatar choices — ids must match
/// backend/app/routers/profile.py::AVATAR_PRESETS exactly, since the
/// server rejects anything else PATCH /profile/me tries to set.
class AvatarPresetOption {
  final String id;
  final String assetPath;
  const AvatarPresetOption(this.id, this.assetPath);
}

const List<AvatarPresetOption> kAvatarPresets = [
  AvatarPresetOption('bunnies_coviewing', 'assets/mascot/bunnies_coViewing.png'),
];

/// A handful of ready-made status lines the edit screen offers as quick
/// chips — tapping one just fills the free-text field with it, the
/// server sees one plain `status_text` either way (see
/// routers/profile.py::update_me).
final List<String> kStatusPresets = [
  'смотрю сериал 🍿'.tr,
  'в поиске совместного просмотра'.tr,
  'не беспокоить'.tr,
  'на паузе'.tr,
  'открыт(а) для рекомендаций'.tr,
];
