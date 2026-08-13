import 'media_item.dart';

/// Mirrors `AiMatchOut` in backend/app/schemas.py — one shortlisted title
/// off POST /ai/ask, with a local 0-100 heuristic match score (no model
/// call behind it — see backend/app/routers/ai.py's module docstring).
class AiMatch {
  final MediaItem item;
  final int match; // 0-100
  final String? reasoning;

  const AiMatch({required this.item, required this.match, this.reasoning});

  factory AiMatch.fromJson(Map<String, dynamic> json) => AiMatch(
        item: MediaItem.fromJson(json['item'] as Map<String, dynamic>),
        match: json['match'] as int,
        reasoning: json['reasoning'] as String?,
      );
}

/// Mirrors `AiAskResponse` in backend/app/schemas.py — the response for
/// POST /ai/ask ("ask teamira" on Home): a free-text description in, a
/// ranked shortlist of real catalog titles out.
class AiAskResponse {
  final List<AiMatch> results;
  final bool isMock;

  const AiAskResponse({required this.results, this.isMock = true});

  factory AiAskResponse.fromJson(Map<String, dynamic> json) => AiAskResponse(
        results: (json['results'] as List? ?? const [])
            .map((e) => AiMatch.fromJson(e as Map<String, dynamic>))
            .toList(),
        isMock: json['is_mock'] as bool? ?? true,
      );
}
