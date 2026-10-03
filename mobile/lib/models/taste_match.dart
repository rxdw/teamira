/// Mirrors `SharedTasteTitleOut` in backend/app/schemas.py — one title
/// behind a TasteMatch's [TasteMatch.sharedTitles], carrying just enough
/// of its own snapshot (same title_ru/title_en/poster_url shape as
/// WatchlistEntry itself) to draw a little poster without a second fetch.
class SharedTasteTitle {
  final String mediaId;
  final String source;
  final String mediaType;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;

  const SharedTasteTitle({
    required this.mediaId,
    required this.source,
    required this.mediaType,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
  });

  // Same "prefer English, fall back to Russian" pick as
  // WatchlistEntry.displayTitle — kept consistent so a title never reads
  // differently here than it would on the shelf it came from.
  String get displayTitle =>
      (titleEn?.trim().isNotEmpty ?? false) ? titleEn! : (titleRu ?? '—');

  factory SharedTasteTitle.fromJson(Map<String, dynamic> json) => SharedTasteTitle(
        mediaId: json['media_id'] as String,
        source: json['source'] as String,
        mediaType: json['media_type'] as String,
        titleRu: json['title_ru'] as String?,
        titleEn: json['title_en'] as String?,
        posterUrl: json['poster_url'] as String?,
      );
}

/// Mirrors `TasteMatchOut` — the one similarity scale this app shows
/// anywhere two people's taste is compared (the friends screen, the
/// "people like you" onboarding step, the co-viewing circle's "мы" tab —
/// see backend/app/similarity.py for how it's built). Deliberately more
/// than a bare percentage: [headline] is the single best plain-language
/// reason for the match, [sharedTitles]/[sharedGenres] are the receipts
/// behind it, and [confidence] lets the UI soften its own presentation
/// for a very new account instead of showing a five-favorite guess with
/// the same certainty as a match built from years of diary history.
class TasteMatch {
  final int overall; // 0-100
  final String headline;
  final String basis;
  final String confidence; // "new" | "some" | "solid"
  final List<SharedTasteTitle> sharedTitles;
  final List<String> sharedGenres;

  const TasteMatch({
    required this.overall,
    required this.headline,
    required this.basis,
    required this.confidence,
    this.sharedTitles = const [],
    this.sharedGenres = const [],
  });

  bool get isNew => confidence == 'new';

  factory TasteMatch.fromJson(Map<String, dynamic> json) => TasteMatch(
        overall: json['overall'] as int? ?? 0,
        headline: json['headline'] as String? ?? '',
        basis: json['basis'] as String? ?? '',
        confidence: json['confidence'] as String? ?? 'some',
        sharedTitles: (json['shared_titles'] as List? ?? const [])
            .map((e) => SharedTasteTitle.fromJson(e as Map<String, dynamic>))
            .toList(),
        sharedGenres: (json['shared_genres'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
      );

  // A JSON-in, JSON-out-shaped nullable parse — every call site here
  // reads an *optional* taste_match field (a pair with no shelf data on
  // either side gets a null, not a fabricated 0% — see similarity.compare's
  // own docstring on the backend), so this is the one every fromJson
  // factory below actually calls.
  static TasteMatch? tryParse(dynamic json) =>
      json == null ? null : TasteMatch.fromJson(json as Map<String, dynamic>);
}
