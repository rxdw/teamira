import '../models/sincerity.dart';
import 'api_client.dart';

/// Talks to GET/PATCH /sincerity/* (backend/app/routers/sincerity.py).
/// Read-only from the client's point of view — every earn/spend event
/// itself happens server-side, as a side effect of the ordinary action
/// that triggered it (logging a title, revising a rating, ...); this
/// service only ever fetches the resulting balance/history or flips the
/// one privacy toggle.
class SincerityService {
  final ApiClient _client;
  SincerityService(this._client);

  Future<SincerityBalance> me({String? before}) async {
    final path = before == null ? '/sincerity/me' : '/sincerity/me?before=$before';
    final json = await _client.get(path) as Map<String, dynamic>;
    return SincerityBalance.fromJson(json);
  }

  Future<SincerityBalance> setVisibleToFriends(bool visible) async {
    final json = await _client.patch(
      '/sincerity/privacy',
      body: {'visible_to_friends': visible},
    ) as Map<String, dynamic>;
    return SincerityBalance.fromJson(json);
  }
}
