import '../models/friend.dart';
import '../models/taste_match.dart';
import 'api_client.dart';
import '../analytics/analytics.dart';

/// Talks to /friends — friend requests, the accepted friends list, a
/// username search to start a request, and the standing invite code with
/// its bonus tally. See backend/app/routers/friends.py for the reasoning
/// (an accepted FriendRequest row *is* the friendship, same shape
/// PartnerService's one linked row already uses for co-viewing pairs).
class FriendsService {
  final ApiClient _client;
  FriendsService(this._client);

  Future<FriendsData> list() async {
    final json = await _client.get('/friends') as Map<String, dynamic>;
    return FriendsData.fromJson(json);
  }

  Future<List<FriendSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final json = await _client.get('/friends/search', query: {'q': trimmed}) as List;
    return json.map((e) => FriendSearchResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FriendRequestItem> sendRequest(String username) async {
    final json = await _client.post('/friends/request', body: {
      'username': username.trim(),
    }) as Map<String, dynamic>;
    Analytics.instance.track('friend_request_sent');
    return FriendRequestItem.fromJson(json);
  }

  Future<Friend> acceptRequest(String requestId) async {
    final json = await _client.post('/friends/requests/$requestId/accept') as Map<String, dynamic>;
    Analytics.instance.track('friend_request_accepted');
    return Friend.fromJson(json);
  }

  Future<void> declineRequest(String requestId) =>
      _client.post('/friends/requests/$requestId/decline');

  /// Withdraws a request *this* account sent, before it's been answered.
  Future<void> cancelRequest(String requestId) =>
      _client.delete('/friends/requests/$requestId');

  Future<void> removeFriend(String friendUserId) =>
      _client.delete('/friends/$friendUserId');

  /// The friend-profile screen: header + the three privacy-filtered
  /// shelves (see backend/app/routers/friends.py::get_friend_profile).
  /// Only ever valid for an accepted friend — a 404 means the request
  /// went stale (unfriended, etc) between screens.
  Future<FriendProfile> friendProfile(String userId) async {
    final json = await _client.get('/friends/$userId/profile') as Map<String, dynamic>;
    return FriendProfile.fromJson(json);
  }

  /// "People you may know" — anyone not already a friend and with no
  /// pending request either way, each with a small public-activity
  /// preview (see backend/app/routers/friends.py::get_suggested_friends).
  Future<List<SuggestedFriend>> suggested() async {
    final json = await _client.get('/friends/suggested') as List;
    return json.map((e) => SuggestedFriend.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// The detailed one-pair taste breakdown behind the compact
  /// `tasteMatch` field already inlined on Friend/SuggestedFriend/
  /// FriendProfile — for a card that wants the full picture (e.g. an
  /// expanded "why you match" sheet) without refetching the whole list.
  /// Returns null exactly when the pair has nothing to compare yet (see
  /// backend/app/routers/friends.py::get_taste_match's own docstring) —
  /// not an exception to handle, just no card to show.
  Future<TasteMatch?> tasteMatch(String userId) async {
    try {
      final json = await _client.get('/friends/$userId/taste-match') as Map<String, dynamic>;
      return TasteMatch.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// This account's own standing code plus its running invite tally —
  /// generated lazily server-side on first call.
  Future<InviteInfo> invite() async {
    final json = await _client.get('/friends/invite') as Map<String, dynamic>;
    return InviteInfo.fromJson(json);
  }

  /// The no-external-service half of the referral link (see
  /// backend/app/routers/linking.py's module docstring) — applies a
  /// code picked up from a `seenly://invite?code=...` open, an Android
  /// Play Install Referrer read, or an iOS clipboard check, without the
  /// person having typed anything on the registration screen. Silent
  /// no-op server-side if the code's stale/unknown/already claimed, so
  /// callers can fire this on every cold start that has a pending code
  /// without worrying about double-applying it.
  Future<void> claimInvite(String code) =>
      _client.post('/friends/invite/claim', body: {'code': code});
}
