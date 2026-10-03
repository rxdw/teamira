import '../models/circle_review.dart';
import '../models/evenings_book.dart';
import 'api_client.dart';

/// Thin client over `/partner/reviews/*` (backend/app/routers/circle_review.py).
/// Reading a review is free for everyone, always. The one premium call is
/// [book] — the material for the PDF "book of your evenings".
class CircleReviewService {
  CircleReviewService(this._client);
  final ApiClient _client;

  CircleReview _one(dynamic json) => CircleReview.fromJson(json as Map<String, dynamic>);

  /// Reviews still waiting for *me* to write my part.
  Future<List<CircleReview>> pending() async {
    final json = await _client.get('/partner/reviews/pending') as List;
    return json.map(_one).toList();
  }

  Future<List<CircleReview>> list({int limit = 20, DateTime? before}) async {
    final json = await _client.get('/partner/reviews', query: {
      'limit': '$limit',
      if (before != null) 'before': before.toUtc().toIso8601String(),
    }) as List;
    return json.map(_one).toList();
  }

  Future<CircleReview> get(String id) async => _one(await _client.get('/partner/reviews/$id'));

  Future<CircleReview?> byRoom(String roomId) async {
    final json = await _client.get('/partner/reviews/by-room/$roomId');
    return json == null ? null : _one(json);
  }

  Future<CircleReview?> byTitle(String source, String mediaId) async {
    final json = await _client.get('/partner/reviews/by-title', query: {'source': source, 'media_id': mediaId});
    return json == null ? null : _one(json);
  }

  Future<CircleReview> putMine(String id, {int? rating, List<String>? tags, String? line}) async => _one(
        await _client.put('/partner/reviews/$id/mine', body: {
          'rating': rating,
          'tags': tags ?? const <String>[],
          'line': line,
        }),
      );

  Future<CircleReview> skip(String id) async => _one(await _client.post('/partner/reviews/$id/skip'));

  /// Everything the book is made of — the circle's opened reviews, oldest
  /// first, with their moments. Premium for the circle: without a plan the
  /// server answers 402, which surfaces here as an [ApiException] with
  /// `statusCode == 402` for the caller to turn into the upsell.
  Future<EveningsBook> book() async =>
      EveningsBook.fromJson(await _client.get('/partner/reviews/book') as Map<String, dynamic>);
}
