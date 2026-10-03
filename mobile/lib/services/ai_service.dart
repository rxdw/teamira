import '../models/ai_response.dart';
import 'api_client.dart';
import '../analytics/analytics.dart';

class AiService {
  final ApiClient _client;
  AiService(this._client);

  /// "ask teamira" on Home — a free-text description in, a ranked
  /// shortlist of real catalog titles out. Backend is local keyword/genre
  /// matching, not a model call (see backend/app/routers/ai.py); the
  /// contract is real so swapping in an actual model later doesn't touch
  /// this call site.
  /// [minutesAvailable] is the evening's time budget, from the time
  /// chips above the text field. Optional: when it's null the backend
  /// still scans the free text for a spoken budget ("есть часа полтора")
  /// before giving up on the idea, so typing it instead of tapping works
  /// too.
  ///
  /// The budget is a ranking signal, not a filter — see
  /// backend/app/routers/ai.py. Passing one never empties the list; it
  /// moves things that fit up and things that overrun down, and leaves
  /// titles with no known runtime exactly where they were.
  Future<AiAskResponse> ask(String query, {int? minutesAvailable}) async {
    final json = await _client.post('/ai/ask', body: {
      'query': query,
      if (minutesAvailable != null) 'minutes_available': minutesAvailable,
    }) as Map<String, dynamic>;
    Analytics.instance.track('ask_teamira', {
      'query_len': query.trim().length,
      'has_time_limit': minutesAvailable != null,
    });
    return AiAskResponse.fromJson(json);
  }
}
