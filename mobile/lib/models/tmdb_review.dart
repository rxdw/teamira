import '../services/app_translations.dart';
/// Mirrors `TmdbReviewOut` in backend/app/schemas.py — a written review
/// from TMDB or Trakt (see backend/app/routers/reviews.py for why the two
/// are merged: TMDB alone is often nearly empty). IMDB still isn't an
/// option — no public API for review text.
class TmdbReview {
  final String author;
  final String? avatarUrl;
  final double? rating;
  final String content;
  final DateTime? createdAt;
  final String url;
  final String source; // "tmdb" | "trakt"

  const TmdbReview({
    required this.author,
    this.avatarUrl,
    this.rating,
    required this.content,
    this.createdAt,
    required this.url,
    this.source = 'tmdb',
  });

  factory TmdbReview.fromJson(Map<String, dynamic> json) => TmdbReview(
        author: json['author'] as String,
        avatarUrl: json['avatar_url'] as String?,
        rating: (json['rating'] as num?)?.toDouble(),
        content: json['content'] as String,
        createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
        url: json['url'] as String,
        source: json['source'] as String? ?? 'tmdb',
      );
}

/// Mirrors `TmdbReviewsOut` — an empty `reviews` list just means neither
/// source has written reviews for this title, not an error.
class TmdbReviewsResult {
  final List<TmdbReview> reviews;
  final String attribution;

  const TmdbReviewsResult({
    required this.reviews,
    this.attribution = 'Отзывы предоставлены TMDB и Trakt',
  });

  factory TmdbReviewsResult.fromJson(Map<String, dynamic> json) => TmdbReviewsResult(
        reviews: (json['reviews'] as List)
            .map((e) => TmdbReview.fromJson(e as Map<String, dynamic>))
            .toList(),
        attribution: json['attribution'] as String? ?? 'Отзывы предоставлены TMDB и Trakt'.tr,
      );
}
