import 'media_item.dart';

/// Mirrors UserListOut — the lists screen's overview card: no items, just
/// a count and a few posters for a collage preview.
class UserList {
  final String id;
  final String name;
  final String? description;
  final int itemCount;
  final List<String> previewPosters;
  final DateTime createdAt;

  const UserList({
    required this.id,
    required this.name,
    this.description,
    required this.itemCount,
    required this.previewPosters,
    required this.createdAt,
  });

  factory UserList.fromJson(Map<String, dynamic> json) => UserList(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        itemCount: json['item_count'] as int,
        previewPosters: (json['preview_posters'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Mirrors UserListItemOut.
class UserListItem {
  final String id;
  final String mediaId;
  final String mediaType;
  final String source;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  final int? year;
  final List<String> genres;
  final double? rating;
  final DateTime addedAt;

  const UserListItem({
    required this.id,
    required this.mediaId,
    required this.mediaType,
    required this.source,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
    this.year,
    required this.genres,
    this.rating,
    required this.addedAt,
  });

  String get displayTitle => titleEn ?? titleRu ?? '—';

  factory UserListItem.fromJson(Map<String, dynamic> json) => UserListItem(
        id: json['id'] as String,
        mediaId: json['media_id'] as String,
        mediaType: json['media_type'] as String,
        source: json['source'] as String,
        titleRu: json['title_ru'] as String?,
        titleEn: json['title_en'] as String?,
        posterUrl: json['poster_url'] as String?,
        year: json['year'] as int?,
        genres: (json['genres'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        rating: (json['rating'] as num?)?.toDouble(),
        addedAt: DateTime.parse(json['added_at'] as String),
      );
}

/// Mirrors UserListDetailOut — one list with its full items.
class UserListDetail {
  final String id;
  final String name;
  final String? description;
  final List<UserListItem> items;
  final DateTime createdAt;

  const UserListDetail({
    required this.id,
    required this.name,
    this.description,
    required this.items,
    required this.createdAt,
  });

  factory UserListDetail.fromJson(Map<String, dynamic> json) =>
      UserListDetail(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        items: (json['items'] as List? ?? const [])
            .map((e) => UserListItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Helper for MediaItem -> the shape POST /lists/{id}/items expects.
extension MediaItemToListPayload on MediaItem {
  Map<String, dynamic> toAddListItemBody() => {'item': toJson()};
}
