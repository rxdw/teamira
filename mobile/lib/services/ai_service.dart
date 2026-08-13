import '../models/ai_response.dart';
import 'api_client.dart';

class AiService {
  final ApiClient _client;
  AiService(this._client);

  /// "ask teamira" on Home — a free-text description in, a ranked
  /// shortlist of real catalog titles out. Backend is local keyword/genre
  /// matching, not a model call (see backend/app/routers/ai.py); the
  /// contract is real so swapping in an actual model later doesn't touch
  /// this call site.
  Future<AiAskResponse> ask(String query) async {
    final json = await _client
        .post('/ai/ask', body: {'query': query}) as Map<String, dynamic>;
    return AiAskResponse.fromJson(json);
  }
}
