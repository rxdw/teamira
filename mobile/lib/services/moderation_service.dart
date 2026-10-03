import 'api_client.dart';
import '../analytics/analytics.dart';

/// Blocking and reporting — the client half of the backend's
/// `/moderation` router.
///
/// Two separate actions on purpose, offered together in the UI but never
/// merged: "I don't want to see this person" and "someone should look at
/// what this person is doing" are different asks. Merging them means
/// either people block when they should report (and nothing gets looked
/// at) or the report queue fills with "I just didn't like them".
class ModerationService {
  final ApiClient _client;
  ModerationService(this._client);

  Future<List<BlockedUser>> blocks() async {
    final json = await _client.get('/moderation/blocks') as List<dynamic>;
    return json.map((e) => BlockedUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Takes effect immediately and needs no review. The server also tears
  /// down the friendship and any pending requests between the two — see
  /// the backend's block_user.
  Future<void> block(String userId) async {
    await _client.post('/moderation/blocks', body: {'user_id': userId});
    Analytics.instance.track('user_blocked');
  }

  /// Restores visibility, not the friendship. That has to be asked for
  /// again, deliberately: quietly re-friending people on unblock would
  /// undo a decision nobody made twice.
  Future<void> unblock(String userId) => _client.delete('/moderation/blocks/$userId');

  Future<void> report({
    required ReportTarget target,
    required String reportedUserId,
    String? targetId,
    required ReportReason reason,
    String? details,
  }) async {
    await _client.post('/moderation/reports', body: {
      'target_type': target.wire,
      'reported_user_id': reportedUserId,
      if (targetId != null) 'target_id': targetId,
      'reason': reason.wire,
      if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
    });
    Analytics.instance.track('report_filed', {
      'target': target.wire,
      'reason': reason.wire,
    });
  }

  /// What this person reported and what came of it. Closing the loop
  /// matters more than it looks — a report flow that never says anything
  /// back teaches people to stop using it.
  Future<List<MyReport>> myReports() async {
    final json = await _client.get('/moderation/reports') as List<dynamic>;
    return json.map((e) => MyReport.fromJson(e as Map<String, dynamic>)).toList();
  }
}

enum ReportTarget {
  user('user'),
  diaryEntry('diary_entry'),
  activityEvent('activity_event'),
  list('list'),
  review('review');

  final String wire;
  const ReportTarget(this.wire);
}

/// Kept short and concrete on purpose. A long taxonomy makes people pick
/// "other" and write the real reason in free text, which is slower to
/// triage rather than faster.
enum ReportReason {
  harassment('harassment', 'harassment or bullying'),
  hate('hate', 'hate speech'),
  sexualContent('sexual_content', 'sexual content'),
  violence('violence', 'violence or cruelty'),
  spam('spam', 'spam or advertising'),
  impersonation('impersonation', 'pretending to be someone else'),
  selfHarm('self_harm', 'self-harm'),
  childSafety('child_safety', 'child safety'),
  other('other', 'something else');

  final String wire;
  final String label;
  const ReportReason(this.wire, this.label);
}

class BlockedUser {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final DateTime? blockedAt;

  BlockedUser({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.blockedAt,
  });

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        blockedAt: json['blocked_at'] == null
            ? null
            : DateTime.tryParse(json['blocked_at'] as String),
      );
}

class MyReport {
  final String id;
  final String status;
  final String reason;
  final String? reportedUsername;
  final DateTime? createdAt;
  final String? actionTaken;

  MyReport({
    required this.id,
    required this.status,
    required this.reason,
    this.reportedUsername,
    this.createdAt,
    this.actionTaken,
  });

  factory MyReport.fromJson(Map<String, dynamic> json) => MyReport(
        id: json['id'] as String,
        status: json['status'] as String,
        reason: json['reason'] as String,
        reportedUsername: json['reported_username'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
        actionTaken: json['action_taken'] as String?,
      );
}
