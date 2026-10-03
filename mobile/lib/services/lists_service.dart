import '../models/media_item.dart';
import '../models/user_list.dart';
import 'api_client.dart';
import '../analytics/analytics.dart';

class ListsService {
  final ApiClient _client;
  ListsService(this._client);

  Future<List<UserList>> all() async {
    final json = await _client.get('/lists') as List;
    return json
        .map((e) => UserList.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserList> create({required String name, String? description}) async {
    final json = await _client.post('/lists', body: {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
    }) as Map<String, dynamic>;
    Analytics.instance.track('list_created');
    return UserList.fromJson(json);
  }

  Future<UserList> rename(String listId, {String? name, String? description}) async {
    final json = await _client.patch('/lists/$listId', body: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
    }) as Map<String, dynamic>;
    return UserList.fromJson(json);
  }

  Future<void> delete(String listId) => _client.delete('/lists/$listId');

  Future<UserListDetail> detail(String listId) async {
    final json = await _client.get('/lists/$listId') as Map<String, dynamic>;
    return UserListDetail.fromJson(json);
  }

  /// The IDs of the user's lists that already contain this title — used to
  /// pre-check the boxes in the "add to list" sheet.
  Future<Set<String>> membership({
    required String mediaId,
    required String source,
  }) async {
    final json = await _client.get('/lists/membership', query: {
      'media_id': mediaId,
      'source': source,
    }) as List;
    return json.map((e) => e as String).toSet();
  }

  Future<UserListDetail> addItem(String listId, MediaItem item) async {
    final json = await _client.post('/lists/$listId/items',
        body: item.toAddListItemBody()) as Map<String, dynamic>;
    Analytics.instance.track('list_item_added', {'media_type': item.mediaType});
    return UserListDetail.fromJson(json);
  }

  Future<UserListDetail> removeItem(String listId, String itemId) async {
    final json = await _client
        .deleteAndDecode('/lists/$listId/items/$itemId') as Map<String, dynamic>;
    return UserListDetail.fromJson(json);
  }
}
