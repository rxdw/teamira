import '../utils/server_time.dart';

/// Mirrors `ChallengeOut` in backend/app/schemas.py.
///
/// A challenge is deliberately *not* an achievement: it starts, it ends,
/// and an unfinished one quietly goes away and is replaced. See
/// backend/app/challenges.py for why the app has both and what each is
/// for. That difference is what the UI has to carry — a challenge card
/// shows time remaining, an achievement badge never does.
class Challenge {
  final String id;
  /// "weekly" | "yearly"
  final String cadence;
  /// Small fixed vocabulary mapped to icons on this side — same
  /// convention as AchievementIcon. Unknown keys fall back to a neutral
  /// icon rather than throwing, so the backend can add one without
  /// shipping an app update.
  final String iconKey;
  final String title;
  final String caption;
  final String rule;
  final int current;
  final int target;
  final double progress;
  final bool completed;
  final bool claimed;
  final int points;
  final int? daysLeft;
  final String periodKey;
  final DateTime? completedAt;

  const Challenge({
    required this.id,
    required this.cadence,
    required this.iconKey,
    required this.title,
    required this.caption,
    this.rule = '',
    this.current = 0,
    this.target = 1,
    this.progress = 0,
    this.completed = false,
    this.claimed = false,
    this.points = 0,
    this.daysLeft,
    this.periodKey = '',
    this.completedAt,
  });

  bool get isWeekly => cadence == 'weekly';
  /// Finished, reward not collected — the one state worth a badge.
  bool get claimable => completed && !claimed;
  int get remaining => (target - current).clamp(0, target);

  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
        id: json['id'] as String? ?? '',
        cadence: json['cadence'] as String? ?? 'weekly',
        iconKey: json['icon_key'] as String? ?? 'star',
        // Lowercased on arrival, whatever the backend sends — the app
        // writes all its copy lowercase, and this keeps a server that
        // hasn't been redeployed yet from showing "Три вечера".
        title: (json['title'] as String? ?? '').toLowerCase(),
        caption: (json['caption'] as String? ?? '').toLowerCase(),
        rule: (json['rule'] as String? ?? '').toLowerCase(),
        current: json['current'] as int? ?? 0,
        target: json['target'] as int? ?? 1,
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        completed: json['completed'] as bool? ?? false,
        claimed: json['claimed'] as bool? ?? false,
        points: json['points'] as int? ?? 0,
        daysLeft: json['days_left'] as int?,
        periodKey: json['period_key'] as String? ?? '',
        completedAt: tryParseServerUtc(json['completed_at'] as String?),
      );
}

/// Mirrors `ChallengesOut`.
class Challenges {
  final List<Challenge> weekly;
  final List<Challenge> yearly;
  /// Finished but not yet acknowledged — what Home announces once and
  /// then stops announcing (see ChallengesService.markSeen).
  final List<Challenge> toAnnounce;
  final int claimableCount;
  final DateTime? weekEndsAt;

  const Challenges({
    this.weekly = const [],
    this.yearly = const [],
    this.toAnnounce = const [],
    this.claimableCount = 0,
    this.weekEndsAt,
  });

  bool get isEmpty => weekly.isEmpty && yearly.isEmpty;

  /// The single most worth-showing one for Home's compact card: anything
  /// collectable first, then whatever is closest to done, then the first
  /// weekly. Never a completed-and-collected one — there's nothing left
  /// to do with it.
  Challenge? get spotlight {
    final pool = [...weekly, ...yearly];
    if (pool.isEmpty) return null;
    final claimable = pool.where((c) => c.claimable).toList();
    if (claimable.isNotEmpty) return claimable.first;
    final open = pool.where((c) => !c.completed).toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    return open.isNotEmpty ? open.first : null;
  }

  factory Challenges.fromJson(Map<String, dynamic> json) {
    List<Challenge> parse(String key) => (json[key] as List? ?? const [])
        .map((e) => Challenge.fromJson(e as Map<String, dynamic>))
        .toList();
    return Challenges(
      weekly: parse('weekly'),
      yearly: parse('yearly'),
      toAnnounce: parse('to_announce'),
      claimableCount: json['claimable_count'] as int? ?? 0,
      weekEndsAt: tryParseServerUtc(json['week_ends_at'] as String?),
    );
  }
}

/// Mirrors `ChallengeClaimOut` — everything the reward animation needs,
/// including the post-claim level, so the ring can move without a second
/// round trip to /sincerity/me.
class ChallengeClaim {
  final Challenge challenge;
  final int pointsAwarded;
  final int totalPoints;
  final int level;
  final bool leveledUp;

  const ChallengeClaim({
    required this.challenge,
    required this.pointsAwarded,
    required this.totalPoints,
    required this.level,
    this.leveledUp = false,
  });

  factory ChallengeClaim.fromJson(Map<String, dynamic> json) => ChallengeClaim(
        challenge: Challenge.fromJson(json['challenge'] as Map<String, dynamic>),
        pointsAwarded: json['points_awarded'] as int? ?? 0,
        totalPoints: json['total_points'] as int? ?? 0,
        level: json['level'] as int? ?? 1,
        leveledUp: json['leveled_up'] as bool? ?? false,
      );
}
