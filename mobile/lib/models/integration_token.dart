import '../utils/server_time.dart';

/// Mirrors `IntegrationTokenOut` in backend/app/schemas.py — everything
/// the Integrations screen needs to render: the raw token (for anything
/// these ready-made URLs don't cover) plus a URL already built per source.
class IntegrationToken {
  final String token;
  final String plexWebhookUrl;
  final String jellyfinWebhookUrl;
  final String kodiUrl;
  final String extensionIngestUrl;

  const IntegrationToken({
    required this.token,
    required this.plexWebhookUrl,
    required this.jellyfinWebhookUrl,
    required this.kodiUrl,
    required this.extensionIngestUrl,
  });

  factory IntegrationToken.fromJson(Map<String, dynamic> json) => IntegrationToken(
        token: json['token'] as String,
        plexWebhookUrl: json['plex_webhook_url'] as String,
        jellyfinWebhookUrl: json['jellyfin_webhook_url'] as String,
        kodiUrl: json['kodi_url'] as String,
        extensionIngestUrl: json['extension_ingest_url'] as String,
      );
}

/// Mirrors `ScrobbleEventOut` — one incoming automatic-tracking event,
/// matched or not. Shown on the Integrations screen as a lightweight
/// activity log, mainly so "why didn't my Netflix watch show up" has
/// somewhere to look instead of being a total mystery.
class ScrobbleEvent {
  final String id;
  final String integration;
  final String? rawTitle;
  final String? matchedMediaId;
  final String? matchedSource;
  final String action; // "logged" | "ignored" | "unmatched"
  final String? detail;
  final DateTime createdAt;

  const ScrobbleEvent({
    required this.id,
    required this.integration,
    this.rawTitle,
    this.matchedMediaId,
    this.matchedSource,
    required this.action,
    this.detail,
    required this.createdAt,
  });

  bool get logged => action == 'logged';

  factory ScrobbleEvent.fromJson(Map<String, dynamic> json) => ScrobbleEvent(
        id: json['id'] as String,
        integration: json['integration'] as String,
        rawTitle: json['raw_title'] as String?,
        matchedMediaId: json['matched_media_id'] as String?,
        matchedSource: json['matched_source'] as String?,
        action: json['action'] as String,
        detail: json['detail'] as String?,
        createdAt: parseServerUtc(json['created_at'] as String),
      );
}
