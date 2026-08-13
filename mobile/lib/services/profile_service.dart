import '../models/achievement.dart';
import '../models/media_item.dart';
import '../models/profile_stats.dart';
import '../models/watchlist_entry.dart';
import 'api_client.dart';

class ProfileService {
  final ApiClient _client;
  ProfileService(this._client);

  Future<ProfileCollections> collections() async {
    final json = await _client.get('/profile/collections') as Map<String, dynamic>;
    return ProfileCollections.fromJson(json);
  }

  Future<ProfileYearStats> yearStats() async {
    final json = await _client.get('/profile/stats/year') as Map<String, dynamic>;
    return ProfileYearStats.fromJson(json);
  }

  Future<WrappedStat> wrapped({String period = 'month'}) async {
    final json = await _client
        .get('/profile/wrapped', query: {'period': period}) as Map<String, dynamic>;
    return WrappedStat.fromJson(json);
  }

  Future<WrappedSummary> wrappedSummary({
    String scope = 'year',
    int? year,
    int? month,
  }) async {
    final json = await _client.get('/profile/wrapped/summary', query: {
      'scope': scope,
      if (year != null) 'year': '$year',
      if (month != null) 'month': '$month',
    }) as Map<String, dynamic>;
    return WrappedSummary.fromJson(json);
  }

  Future<WrappedPeriods> wrappedPeriods() async {
    final json = await _client.get('/profile/wrapped/periods') as Map<String, dynamic>;
    return WrappedPeriods.fromJson(json);
  }

  Future<AchievementsResponse> achievements() async {
    final json = await _client.get('/profile/achievements') as Map<String, dynamic>;
    return AchievementsResponse.fromJson(json);
  }

  /// Sets the badge showcase pinned to the profile header (and visible on
  /// the friend profile screen) — replaces the whole selection each call,
  /// same pattern as favoriteFilmPick above. Pass an empty list to clear it.
  Future<AchievementsResponse> pinAchievements(List<String> achievementIds) async {
    final json = await _client.post('/profile/achievements/pin', body: {
      'achievement_ids': achievementIds,
    }) as Map<String, dynamic>;
    return AchievementsResponse.fromJson(json);
  }

  Future<ProfileLevel> level() async {
    final json = await _client.get('/profile/level') as Map<String, dynamic>;
    return ProfileLevel.fromJson(json);
  }

  /// Current favorite-film status for one title — used by the title
  /// screen's heart button on load. Best-effort by design: callers treat
  /// a failure here the same as "not a favorite" rather than blocking the
  /// rest of the screen on it.
  Future<bool> favoriteStatus(String mediaId, String source) async {
    final json = await _client.get('/profile/favorites/status', query: {
      'media_id': mediaId,
      'source': source,
    }) as Map<String, dynamic>;
    return json['is_favorite'] as bool? ?? false;
  }

  /// Sets (or clears) a title's favorite flag — same flag the log form's
  /// heart toggle and Profile's real favorite films row read (see
  /// WatchlistEntry.is_favorite on the backend). Returns the flag's new
  /// value straight from the server, so callers can trust the response
  /// over their own optimistic guess.
  Future<bool> toggleFavorite(MediaItem item, bool isFavorite) async {
    final json = await _client.post('/profile/favorites/toggle', body: {
      'item': item.toJson(),
      'is_favorite': isFavorite,
    }) as Map<String, dynamic>;
    return json['is_favorite'] as bool? ?? isFavorite;
  }

  /// Sets the ordered stories deck that swipes across the Profile header
  /// banner — see ProfileMe.topFavoritePicks's own docstring. Every pick
  /// must already be one of this account's favorite movies; the backend
  /// rejects anything else. An empty list clears the banner back to its
  /// plain placeholder look.
  Future<ProfileMe> setTopFavorites(List<FavoritePick> picks) async {
    final json = await _client.post('/profile/favorites/pick', body: {
      'picks': picks.map((p) => p.toJson()).toList(),
    }) as Map<String, dynamic>;
    return ProfileMe.fromJson(json);
  }

  /// The editable identity block — name/avatar/status. Read by the edit
  /// screen on open; AppState.currentUser already carries the same
  /// fields from /auth/me for everywhere else, so this is only needed
  /// when the edit screen itself wants a fresh copy.
  Future<ProfileMe> me() async {
    final json = await _client.get('/profile/me') as Map<String, dynamic>;
    return ProfileMe.fromJson(json);
  }

  /// Updates whichever fields are non-null — mirrors the backend's
  /// `exclude_unset` PATCH (see routers/profile.py::update_me): pass
  /// only what changed. An empty string clears display_name/statusText
  /// back to "unset" (falls back to username / no status shown).
  Future<ProfileMe> updateMe({
    String? displayName,
    String? statusText,
    String? avatarPreset,
    String? privacyWatched,
    String? privacyWatching,
    String? privacyPlanned,
    String? privacyFavorites,
  }) async {
    final body = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (statusText != null) 'status_text': statusText,
      if (avatarPreset != null) 'avatar_preset': avatarPreset,
      if (privacyWatched != null) 'privacy_watched': privacyWatched,
      if (privacyWatching != null) 'privacy_watching': privacyWatching,
      if (privacyPlanned != null) 'privacy_planned': privacyPlanned,
      if (privacyFavorites != null) 'privacy_favorites': privacyFavorites,
    };
    final json = await _client.patch('/profile/me', body: body) as Map<String, dynamic>;
    return ProfileMe.fromJson(json);
  }

  /// Uploads a custom avatar photo — clears any chosen preset server-side
  /// (see routers/profile.py::upload_avatar). Returns the new avatar_url
  /// to render immediately without a second round trip.
  Future<String> uploadAvatar(List<int> bytes, {required String filename, String? contentType}) async {
    final json = await _client.postMultipart(
      '/profile/avatar',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    ) as Map<String, dynamic>;
    return json['avatar_url'] as String;
  }
}
