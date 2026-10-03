import '../services/locale_service.dart';
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

/// Mirrors `TimeBudgetOut` — what the ranker actually used as tonight's
/// time budget.
///
/// [source] matters for the copy: "chip" means the person tapped one of
/// the time chips and already knows, "text" means the backend read it out
/// of their sentence ("есть часа полтора"), which is worth saying back to
/// them so they can tell it was understood.
class AiTimeBudget {
  final int minutes;
  /// "chip" | "text"
  final String source;
  /// "episode" | "movie" | "either" — what that much time is most likely
  /// asking for. Drives the caption only; the actual ranking is done on
  /// real runtimes.
  final String shape;

  const AiTimeBudget({
    required this.minutes,
    this.source = 'chip',
    this.shape = 'either',
  });

  bool get cameFromText => source == 'text';

  /// "40 мин" / "1 ч 30 мин" (or "40 min" / "1 h 30 min" with the English
  /// interface) — the one place this is formatted, so every screen says
  /// it the same way.
  String get label {
    final ru = LocaleService.appIsRussian;
    final minWord = ru ? 'мин' : 'min';
    final hourWord = ru ? 'ч' : 'h';
    if (minutes < 60) return '$minutes $minWord';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h $hourWord' : '$h $hourWord $m $minWord';
  }

  factory AiTimeBudget.fromJson(Map<String, dynamic> json) => AiTimeBudget(
        minutes: json['minutes'] as int? ?? 0,
        source: json['source'] as String? ?? 'chip',
        shape: json['shape'] as String? ?? 'either',
      );
}

/// Mirrors `AiAskResponse` in backend/app/schemas.py — the response for
/// POST /ai/ask ("ask teamira" on Home): a free-text description in, a
/// ranked shortlist of real catalog titles out.
class AiAskResponse {
  final List<AiMatch> results;
  final bool isMock;
  /// Non-null whenever a time budget was in play.
  final AiTimeBudget? timeBudget;
  /// True when a budget was asked for but nothing near the top of the
  /// list actually fits it. The screen says so rather than quietly
  /// showing a three-hour film to someone who said they had forty
  /// minutes.
  final bool timeBudgetRelaxed;

  const AiAskResponse({
    required this.results,
    this.isMock = true,
    this.timeBudget,
    this.timeBudgetRelaxed = false,
  });

  factory AiAskResponse.fromJson(Map<String, dynamic> json) => AiAskResponse(
        results: (json['results'] as List? ?? const [])
            .map((e) => AiMatch.fromJson(e as Map<String, dynamic>))
            .toList(),
        isMock: json['is_mock'] as bool? ?? true,
        timeBudget: json['time_budget'] == null
            ? null
            : AiTimeBudget.fromJson(json['time_budget'] as Map<String, dynamic>),
        timeBudgetRelaxed: json['time_budget_relaxed'] as bool? ?? false,
      );
}
