import '../models/achievement.dart';
import '../models/co_view_entry.dart';
import '../models/profile_stats.dart';
import '../models/shared_diary.dart';
import 'api_client.dart';

/// Talks to /partner/shared — the couple's (or company's) shared diary,
/// their planned evenings, and "наш год".
///
/// Worth knowing when reading the screens that use this: the shared diary
/// is a *view over personal diary entries*, not a separate store (see
/// backend/app/routers/shared_diary.py). So editing an evening through
/// the normal diary endpoints is what changes what a partner sees here —
/// there's no separate "update shared entry" call, and there shouldn't be.
class SharedDiaryService {
  final ApiClient _client;
  SharedDiaryService(this._client);

  /// One page of shared evenings, newest first. Pass the previous page's
  /// [SharedDiaryPage.nextBefore] as [before] for older ones.
  Future<SharedDiaryPage> diary({String? before}) async {
    final json = await _client.get(
      '/partner/shared/diary',
      query: before == null ? null : {'before': before},
    ) as Map<String, dynamic>;
    return SharedDiaryPage.fromJson(json);
  }

  /// Adds or removes one of *your own* evenings from the shared diary —
  /// the per-entry override of the auto-share setting.
  ///
  /// Returns the refreshed first page rather than a bare 204 so the
  /// screen updates in one round trip. Throws ApiException(400) when
  /// asked to un-share an evening that was watched together: the other
  /// person was there, so hiding it would make the shared diary wrong
  /// rather than private (delete the entry instead, if that's the
  /// intent).
  Future<SharedDiaryPage> setShared(String entryId, bool shared) async {
    final json = await _client.post(
      '/partner/shared/diary/$entryId/share',
      body: {'shared': shared},
    ) as Map<String, dynamic>;
    return SharedDiaryPage.fromJson(json);
  }

  /// The co-viewing queue plus the free-tier ceiling. The limit comes
  /// from the server rather than being hardcoded here, so the upsell copy
  /// can never disagree with what's actually enforced.
  Future<SharedPlanned> planned() async {
    final json = await _client.get('/partner/shared/planned') as Map<String, dynamic>;
    return SharedPlanned.fromJson(json);
  }

  /// Pays sincerity.NUDGE_COST to send every other circle-mate one push
  /// about [entryId] having gone stale in the shared plans — see
  /// co_view_hub_screen.dart's own staleness mirror
  /// (_CoViewHubScreenState._isNudgeable) for when the button even shows.
  /// Returns the refreshed queue, same round-trip shape as the rest of
  /// this service's write methods.
  Future<SharedPlanned> nudge(String entryId) async {
    final json = await _client.post('/partner/shared/planned/$entryId/nudge') as Map<String, dynamic>;
    return SharedPlanned.fromJson(json);
  }

  /// [period] is "year" or "all".
  Future<SharedStats> stats({String period = 'year'}) async {
    final json = await _client.get(
      '/partner/shared/stats',
      query: {'period': period},
    ) as Map<String, dynamic>;
    return SharedStats.fromJson(json);
  }

  /// The circle's own badge shelf ("наши вехи") — same shape as
  /// ProfileService.achievements(), just scored off the link instead of
  /// one account. Always all-time; there's no [period] here on purpose,
  /// see compute_couple_achievements_for_link's docstring server-side.
  Future<AchievementsResponse> achievements() async {
    final json = await _client.get('/partner/shared/achievements') as Map<String, dynamic>;
    return AchievementsResponse.fromJson(json);
  }

  Future<PartnerPrefs> prefs() async {
    final json = await _client.get('/partner/shared/prefs') as Map<String, dynamic>;
    return PartnerPrefs.fromJson(json);
  }

  Future<PartnerPrefs> updatePrefs({
    bool? autoShareLogs,
    bool? shareRatings,
    bool? shareNotes,
  }) async {
    final json = await _client.patch('/partner/shared/prefs', body: {
      if (autoShareLogs != null) 'auto_share_logs': autoShareLogs,
      if (shareRatings != null) 'share_ratings': shareRatings,
      if (shareNotes != null) 'share_notes': shareNotes,
    }) as Map<String, dynamic>;
    return PartnerPrefs.fromJson(json);
  }

  /// Pays sincerity.SPOILER_UNLOCK_COST to see one circle-mate's rating
  /// on [entryId] before rating that title yourself — the other half of
  /// [SharedDiaryPerson.ratingHidden]. Returns the refreshed first page,
  /// same shape as [setShared], so the card updates in one round trip.
  Future<SharedDiaryPage> revealRating(String entryId) async {
    final json = await _client.post('/partner/shared/diary/$entryId/reveal-rating') as Map<String, dynamic>;
    return SharedDiaryPage.fromJson(json);
  }

  /// The couple's own "наш враппед" — same shape and scopes
  /// (month/year/all) as [ProfileService.wrappedSummary], just built
  /// from the circle's shared diary rows instead of one person's. See
  /// wrapped_screen.dart's own doc comment for why WrappedScreen picks
  /// between the two services on `isCouple`.
  Future<WrappedSummary> wrappedSummary({
    String scope = 'year',
    int? year,
    int? month,
  }) async {
    final json = await _client.get('/partner/shared/wrapped/summary', query: {
      'scope': scope,
      if (year != null) 'year': '$year',
      if (month != null) 'month': '$month',
    }) as Map<String, dynamic>;
    return WrappedSummary.fromJson(json);
  }

  /// Mirrors [ProfileService.wrappedPeriods] — which years/months the
  /// circle actually has shared entries in, for the couple wrapped's own
  /// period picker.
  Future<WrappedPeriods> wrappedPeriods() async {
    final json = await _client.get('/partner/shared/wrapped/periods') as Map<String, dynamic>;
    return WrappedPeriods.fromJson(json);
  }
}

/// Mirrors `SharedPlannedOut` — the queue plus its ceiling.
class SharedPlanned {
  final List<CoViewEntry> planned;
  /// Null once premium — no ceiling at all.
  final int? limit;
  final int used;
  final bool isPremium;

  const SharedPlanned({
    this.planned = const [],
    this.limit,
    this.used = 0,
    this.isPremium = false,
  });

  bool get isFull => limit != null && used >= limit!;
  int get remaining => limit == null ? -1 : (limit! - used).clamp(0, limit!);

  factory SharedPlanned.fromJson(Map<String, dynamic> json) => SharedPlanned(
        planned: (json['planned'] as List? ?? const [])
            .map((e) => CoViewEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        limit: json['limit'] as int?,
        used: json['used'] as int? ?? 0,
        isPremium: json['is_premium'] as bool? ?? false,
      );
}
