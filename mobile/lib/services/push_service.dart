import 'api_client.dart';

/// One category of push this app sends — mirrors app/push.py's
/// PushCategory on the backend exactly (same string values, so this
/// enum's `.name` round-trips through the API with no translation
/// table to keep in sync). See [PushPreference] for the label/
/// description that comes back from the server for each.
enum PushCategory {
  friendActivity('friend_activity'),
  partnerActivity('partner_activity'),
  matches('matches'),
  levelUps('level_ups'),
  streakReminders('streak_reminders'),
  memories('memories'),
  newEpisodes('new_episodes'),
  subscription('subscription'),
  pairAlbum('pair_album'),
  coViewRooms('co_view_rooms');

  final String apiValue;
  const PushCategory(this.apiValue);

  static PushCategory? fromApiValue(String value) {
    for (final c in PushCategory.values) {
      if (c.apiValue == value) return c;
    }
    return null;
  }
}

/// One row of GET /push/preferences — label/description are server-
/// authored copy (app/push.py's CATEGORY_COPY), not hardcoded here, so
/// adding a new category later is a backend-only change; this screen
/// just renders whatever comes back.
class PushPreference {
  final PushCategory? category; // null for a category this build doesn't recognize yet
  final String rawCategory;
  final String label;
  final String description;
  final bool enabled;

  PushPreference({
    required this.category,
    required this.rawCategory,
    required this.label,
    required this.description,
    required this.enabled,
  });

  factory PushPreference.fromJson(Map<String, dynamic> json) {
    final raw = json['category'] as String;
    return PushPreference(
      category: PushCategory.fromApiValue(raw),
      rawCategory: raw,
      label: json['label'] as String,
      description: json['description'] as String,
      enabled: json['enabled'] as bool,
    );
  }
}

/// Thin wrapper over the four push-related backend endpoints — see
/// services/push_notification_manager.dart for the Firebase/permission
/// side of things that actually calls these. Kept separate the same way
/// e.g. AuthService (API) and SecureTokenStore (device-local storage)
/// are separate: this class only ever talks to the backend, never to
/// firebase_messaging directly, so it stays trivially reusable if the
/// underlying push provider ever changed without this file caring.
class PushService {
  final ApiClient _client;
  PushService(this._client);

  Future<void> registerToken({
    required String token,
    required String platform,
    String? timezone,
    // "ru" / "en" — the language the app shows, so the server words pushes to
    // match it (backend/app/bi.py). Old servers ignore the field.
    String? locale,
  }) async {
    await _client.post('/push/tokens', body: {
      'token': token,
      'platform': platform,
      if (timezone != null) 'timezone': timezone,
      if (locale != null) 'locale': locale,
    });
  }

  Future<void> unregisterToken(String token) async {
    await _client.delete('/push/tokens/$token');
  }

  Future<List<PushPreference>> getPreferences() async {
    final json = await _client.get('/push/preferences') as Map<String, dynamic>;
    final rows = json['categories'] as List<dynamic>;
    return rows.map((r) => PushPreference.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<PushPreference>> updatePreferences(Map<PushCategory, bool> changes) async {
    final json = await _client.patch('/push/preferences', body: {
      'categories': {for (final e in changes.entries) e.key.apiValue: e.value},
    }) as Map<String, dynamic>;
    final rows = json['categories'] as List<dynamic>;
    return rows.map((r) => PushPreference.fromJson(r as Map<String, dynamic>)).toList();
  }
}
