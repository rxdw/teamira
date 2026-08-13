import '../models/activity_item.dart';
import 'api_client.dart';

/// Talks to /activity — this account's own recent events plus everything
/// its accepted friends have done, already combined server-side (see
/// backend/app/routers/activity.py). `ActivityItem.isMine` tells the two
/// apart client-side.
class ActivityService {
  final ApiClient _client;
  ActivityService(this._client);

  Future<List<ActivityItem>> feed() async {
    final json = await _client.get('/activity') as List;
    return json.map((e) => ActivityItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}
