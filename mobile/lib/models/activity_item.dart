/// Mirrors `ActivityItem` in backend/app/schemas.py. `who` is "You" for
/// this account's own events (see routers/activity.py) or a friend's
/// display name/username for anything pulled in from the friends graph.
class ActivityItem {
  final String who;
  final String text;
  final String? mediaType;
  final String createdAt;

  // Everything below rides along so the activity feed can show a real
  // poster and open the actual title, instead of just the plain text
  // line above — null on an old/self-only row that predates these
  // columns (see models.ActivityEvent), in which case the feed just
  // falls back to a text-only row for it.
  final String? userId;
  final String? username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final String? verb;
  final String? mediaTitle;
  final String? mediaId;
  final String? source;
  final String? posterUrl;
  final int? rating;

  const ActivityItem({
    required this.who,
    required this.text,
    this.mediaType,
    required this.createdAt,
    this.userId,
    this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.verb,
    this.mediaTitle,
    this.mediaId,
    this.source,
    this.posterUrl,
    this.rating,
  });

  bool get isMine => who == 'You';

  /// Whether this row has enough on it to open a poster card — an old
  /// pre-migration row (or one whose title/source never got a snapshot)
  /// just doesn't, and the feed falls back to a plain text line for it.
  bool get hasPoster => mediaId != null && source != null && mediaType != null;

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : (username ?? who);

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
        who: json['who'] as String,
        text: json['text'] as String,
        mediaType: json['media_type'] as String?,
        createdAt: json['created_at'] as String? ?? '',
        userId: json['user_id'] as String?,
        username: json['username'] as String?,
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        verb: json['verb'] as String?,
        mediaTitle: json['media_title'] as String?,
        mediaId: json['media_id'] as String?,
        source: json['source'] as String?,
        posterUrl: json['poster_url'] as String?,
        rating: json['rating'] as int?,
      );
}
