import '../models/integration_token.dart';
import 'api_client.dart';

/// Talks to backend/app/routers/integrations.py — the token that unlocks
/// Plex/Jellyfin/Kodi/browser-extension auto-tracking, plus a recent
/// activity log for debugging a scrobble that didn't show up.
class IntegrationsService {
  final ApiClient _client;
  IntegrationsService(this._client);

  Future<IntegrationToken> getToken() async {
    final json = await _client.get('/integrations/token') as Map<String, dynamic>;
    return IntegrationToken.fromJson(json);
  }

  /// Invalidates every previously configured Plex/Jellyfin/Kodi/browser
  /// URL at once — everything needs re-pasting the new one afterward.
  Future<IntegrationToken> rotateToken() async {
    final json = await _client.post('/integrations/token/rotate') as Map<String, dynamic>;
    return IntegrationToken.fromJson(json);
  }

  Future<List<ScrobbleEvent>> recentEvents() async {
    final json = await _client.get('/integrations/events') as List;
    return json.map((e) => ScrobbleEvent.fromJson(e as Map<String, dynamic>)).toList();
  }
}
