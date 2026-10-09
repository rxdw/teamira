import '../services/app_translations.dart';
/// Mirrors `TmdbReviewOut` in backend/app/schemas.py — a written review
/// from TMDB, Trakt, or (Russian-language users only) Kinopoisk for films
/// and series; Steam for games; AniList for manga — see
/// backend/app/routers/reviews.py for why they're merged: TMDB alone is
/// often nearly empty. IMDB still isn't an option — no public API for
/// review text.
class TmdbReview {
  final String author;
  final String? avatarUrl;
  final double? rating;
  final String content;
  final DateTime? createdAt;
  final String url;
  final String source; // "tmdb" | "trakt" | "kinopoisk" | "steam" | "anilist"

  /// Kinopoisk / Steam / AniList (null for TMDB and Trakt): a headline where
  /// the source has one, a tone ("positive" | "negative" | "neutral" —
  /// Kinopoisk reviewers pick one, Steam's is recommend / don't recommend,
  /// AniList's is derived from the reviewer's score), and how many readers
  /// found it useful.
  final String? title;
  final String? tone;
  final int? likes;

  /// Steam only: hours the reviewer had played when they wrote it.
  final double? playtimeHours;

  const TmdbReview({
    required this.author,
    this.avatarUrl,
    this.rating,
    required this.content,
    this.createdAt,
    required this.url,
    this.source = 'tmdb',
    this.title,
    this.tone,
    this.likes,
    this.playtimeHours,
  });

  factory TmdbReview.fromJson(Map<String, dynamic> json) => TmdbReview(
        author: json['author'] as String,
        avatarUrl: json['avatar_url'] as String?,
        rating: (json['rating'] as num?)?.toDouble(),
        content: json['content'] as String,
        createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
        url: json['url'] as String,
        source: json['source'] as String? ?? 'tmdb',
        title: json['title'] as String?,
        tone: json['tone'] as String?,
        likes: json['likes'] as int?,
        playtimeHours: (json['playtime_hours'] as num?)?.toDouble(),
      );
}

/// Mirrors `TmdbReviewsOut` — an empty `reviews` list just means no
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
