import '../utils/server_time.dart';
import 'achievement.dart';
import 'activity_item.dart';
import 'taste_match.dart';
import 'watchlist_entry.dart';

/// Mirrors `FriendOut` in backend/app/schemas.py — one accepted friend,
/// with their live level so the friends list can show it without a
/// second per-person fetch.
class Friend {
  final String userId;
  final String username;
  final int level;
  final DateTime? friendsSince;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final String? statusText;
  // The single most recent thing this friend logged that they've
  // allowed a friend to see (privacy — see PrivacySettings below) —
  // null if they've hidden every shelf, or simply have nothing yet.
  final ActivityItem? recentActivity;
  // Null when there isn't enough shelf data on either side yet to say
  // anything (see similarity.compare on the backend) — the UI shows
  // nothing rather than a fabricated "0% match" in that case.
  final TasteMatch? tasteMatch;

  const Friend({
    required this.userId,
    required this.username,
    required this.level,
    this.friendsSince,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.statusText,
    this.recentActivity,
    this.tasteMatch,
  });

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        level: json['level'] as int? ?? 1,
        friendsSince: tryParseServerUtc(json['friends_since'] as String?),
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        statusText: json['status_text'] as String?,
        recentActivity: json['recent_activity'] != null
            ? ActivityItem.fromJson(json['recent_activity'] as Map<String, dynamic>)
            : null,
        tasteMatch: TasteMatch.tryParse(json['taste_match']),
      );
}

/// Mirrors `FriendRequestOut` — a pending request, either one this
/// account sent or one it received (the friends screen tells the two
/// apart by which list it came from, see FriendsData below).
class FriendRequestItem {
  final String id;
  final String userId;
  final String username;
  final DateTime? createdAt;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;

  const FriendRequestItem({
    required this.id,
    required this.userId,
    required this.username,
    this.createdAt,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
  });

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory FriendRequestItem.fromJson(Map<String, dynamic> json) => FriendRequestItem(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        username: json['username'] as String,
        createdAt: tryParseServerUtc(json['created_at'] as String?),
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// Mirrors `FriendsOut` — the friends screen's (and the profile block's)
/// entire state in one call.
class FriendsData {
  final List<Friend> friends;
  final List<FriendRequestItem> incomingRequests;
  final List<FriendRequestItem> outgoingRequests;

  const FriendsData({
    this.friends = const [],
    this.incomingRequests = const [],
    this.outgoingRequests = const [],
  });

  factory FriendsData.fromJson(Map<String, dynamic> json) => FriendsData(
        friends: (json['friends'] as List? ?? [])
            .map((e) => Friend.fromJson(e as Map<String, dynamic>))
            .toList(),
        incomingRequests: (json['incoming_requests'] as List? ?? [])
            .map((e) => FriendRequestItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        outgoingRequests: (json['outgoing_requests'] as List? ?? [])
            .map((e) => FriendRequestItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Mirrors `FriendSearchResultOut` — one username-search hit, tagged with
/// this account's relationship to it so the row can show "add",
/// "requested", "respond", or nothing.
class FriendSearchResult {
  final String userId;
  final String username;
  final String status; // "none" | "friends" | "pending_outgoing" | "pending_incoming"
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;

  const FriendSearchResult({
    required this.userId,
    required this.username,
    required this.status,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
  });

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory FriendSearchResult.fromJson(Map<String, dynamic> json) => FriendSearchResult(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        status: json['status'] as String? ?? 'none',
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// Mirrors `InviteOut` — this account's own standing invite code, plus
/// how many friends have joined through it and the sincerity points
/// that's earned (see backend/app/sincerity.py::earn_friend_invited).
class InviteInfo {
  final String code;
  final String shareText;
  final int invitedCount;
  final int sincerityBonus;
  final int sincerityPerFriend;

  const InviteInfo({
    required this.code,
    required this.shareText,
    required this.invitedCount,
    required this.sincerityBonus,
    required this.sincerityPerFriend,
  });

  factory InviteInfo.fromJson(Map<String, dynamic> json) => InviteInfo(
        code: json['code'] as String,
        shareText: json['share_text'] as String,
        invitedCount: json['invited_count'] as int? ?? 0,
        sincerityBonus: json['sincerity_bonus'] as int? ?? 0,
        sincerityPerFriend: json['sincerity_per_friend'] as int? ?? 0,
      );
}

/// Mirrors `FriendProfileOut` — any account's profile screen state in
/// one call: header + the three (privacy-filtered) shelves + recent
/// activity. Fetched both for an accepted friend and for a stranger —
/// see FriendsService.friendProfile.
class FriendProfile {
  final String userId;
  final String username;
  final int level;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final String? statusText;
  final FriendCollections collections;
  // This account's pinned badge showcase — always visible, not gated by
  // privacy like the shelves above. Empty if they haven't pinned anything.
  final List<Achievement> pinnedAchievements;
  // This account's recent activity, privacy-gated the same way the
  // shelves above are — empty if they've hidden everything, or simply
  // have nothing loggable yet.
  final List<ActivityItem> recentActivity;

  // "none" | "friends" | "pending_outgoing" | "pending_incoming" — same
  // vocabulary FriendSearchResult.status already uses, powering the
  // "add friend" button on this screen (see friend_profile_screen.dart's
  // _ActionRow). friendRequestId is the row behind a pending/accepted
  // status, for accepting/cancelling it directly.
  final String friendshipStatus;
  final String? friendRequestId;

  // Same shape, for "are we in the same co-viewing circle" — "none" |
  // "same_circle" | "pending_outgoing" | "pending_incoming" — powers the
  // "invite to co-viewing" button on this screen.
  final String coviewStatus;
  final String? coviewInviteId;

  // Same taste scale as Friend.tasteMatch/SuggestedFriend.tasteMatch —
  // shown here too so opening someone's profile (friend or stranger)
  // gets the full breakdown, not just a compact card version.
  final TasteMatch? tasteMatch;

  const FriendProfile({
    required this.userId,
    required this.username,
    required this.level,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.statusText,
    required this.collections,
    this.pinnedAchievements = const [],
    this.recentActivity = const [],
    this.friendshipStatus = 'none',
    this.friendRequestId,
    this.coviewStatus = 'none',
    this.coviewInviteId,
    this.tasteMatch,
  });

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory FriendProfile.fromJson(Map<String, dynamic> json) => FriendProfile(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        level: json['level'] as int? ?? 1,
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        statusText: json['status_text'] as String?,
        collections: FriendCollections.fromJson(json['collections'] as Map<String, dynamic>? ?? const {}),
        pinnedAchievements: (json['pinned_achievements'] as List? ?? const [])
            .map((e) => Achievement.fromJson(e as Map<String, dynamic>))
            .toList(),
        recentActivity: (json['recent_activity'] as List? ?? const [])
            .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        friendshipStatus: json['friendship_status'] as String? ?? 'none',
        friendRequestId: json['friend_request_id'] as String?,
        coviewStatus: json['coview_status'] as String? ?? 'none',
        coviewInviteId: json['coview_invite_id'] as String?,
        tasteMatch: TasteMatch.tryParse(json['taste_match']),
      );
}

/// Mirrors `SuggestedFriendOut` — one row in the friends screen's
/// "people you may know" section, with a small preview of their most
/// recent *public* activity (see FriendsService.suggested).
class SuggestedFriend {
  final String userId;
  final String username;
  final int level;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final String? statusText;
  final List<ActivityItem> recentActivity;
  // Same taste scale as Friend.tasteMatch — this is what lets "people
  // you may know" be ranked (and shown) by actual taste overlap instead
  // of just "who signed up most recently."
  final TasteMatch? tasteMatch;

  const SuggestedFriend({
    required this.userId,
    required this.username,
    required this.level,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.statusText,
    this.recentActivity = const [],
    this.tasteMatch,
  });

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory SuggestedFriend.fromJson(Map<String, dynamic> json) => SuggestedFriend(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        level: json['level'] as int? ?? 1,
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        statusText: json['status_text'] as String?,
        recentActivity: (json['recent_activity'] as List? ?? const [])
            .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        tasteMatch: TasteMatch.tryParse(json['taste_match']),
      );
}
