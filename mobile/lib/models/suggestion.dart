import 'media_item.dart';
import '../utils/server_time.dart';

/// Mirrors `SuggestionOut` in backend/app/schemas.py — one title the
/// linked partner sent over with a single tap ("I'm suggesting this for
/// tonight"). Only carries the snapshot fields a card needs to render;
/// tapping through to the full title screen re-fetches the rest.
class Suggestion {
  final String id;
  final String mediaId;
  final String mediaType;
  final String source;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  final int? year;
  final String senderUsername;
  final DateTime createdAt;

  const Suggestion({
    required this.id,
    required this.mediaId,
    required this.mediaType,
    required this.source,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
    this.year,
    required this.senderUsername,
    required this.createdAt,
  });

  String get displayTitle => (titleEn?.trim().isNotEmpty ?? false)
      ? titleEn!
      : (titleRu?.trim().isNotEmpty ?? false)
          ? titleRu!
          : '—';

  /// A minimal [MediaItem] built from the snapshot — enough to open the
  /// title screen, which backfills the rest itself.
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

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
        id: json['id'] as String,
        mediaId: json['media_id'] as String,
        mediaType: json['media_type'] as String,
        source: json['source'] as String,
        titleRu: json['title_ru'] as String?,
        titleEn: json['title_en'] as String?,
        posterUrl: json['poster_url'] as String?,
        year: json['year'] as int?,
        senderUsername: json['sender_username'] as String,
        createdAt: parseServerUtc(json['created_at'] as String),
      );
}
