import '../models/recommendation.dart';
import 'api_client.dart';
import '../analytics/analytics.dart';

/// Talks to POST/GET /recommendations (backend/app/routers/recommendations.py)
/// — staking sincerity points on a friend liking something you
/// recommend. Resolution itself happens server-side, from
/// routers/diary.py::log_watched the moment the friend rates the same
/// title, so this service only ever creates a stake or reads the
/// current list — never resolves one directly.
class RecommendationService {
  final ApiClient _client;
  RecommendationService(this._client);

  Future<Recommendation> create({
    required String friendId,
    required String source,
    required String mediaId,
    required String title,
    required int predictedRating,
    required int stake,
  }) async {
    final json = await _client.post('/recommendations', body: {
      'friend_id': friendId,
      'source': source,
      'media_id': mediaId,
      'title': title,
      'predicted_rating': predictedRating,
      'stake': stake,
    }) as Map<String, dynamic>;
    Analytics.instance.track('recommendation_staked', {'stake': stake});
    return Recommendation.fromJson(json);
  }

  Future<RecommendationsResponse> list() async {
    final json = await _client.get('/recommendations') as Map<String, dynamic>;
    return RecommendationsResponse.fromJson(json);
  }
}
