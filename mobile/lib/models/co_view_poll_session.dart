import '../utils/server_time.dart';
import 'media_item.dart';

/// Mirrors `CoViewPollSessionOut` in backend/app/schemas.py — one shared
/// head-to-head poll round: a small shortlist everyone in the circle
/// votes on, on a clock, rather than each person swiping the whole deck
/// alone. `candidates`/`voteCounts` are index-aligned. A tie for the
/// lead doesn't end it — the backend narrows this same round down to
/// just the tied leaders and bumps [roundNumber], so polling again just
/// shows a smaller shortlist and a fresh [deadline] rather than a whole
/// new session.
class CoViewPollSession {
  final String id;
  final String status; // "active" | "done"
  final String poolSource; // "personal" | "coview" | "both"
  final int roundNumber;
  final DateTime deadline;
  final List<MediaItem> candidates;
  final List<int> voteCounts; // index-aligned with candidates
  final int? myVote; // index into candidates, or null if not voted yet
  final int votedCount;
  // Everyone currently in the circle, including this account — same
  // "tell a couple apart from a company" reasoning as CoViewVoteSession.
  final int memberCount;
  final MediaItem? winner;
  final DateTime createdAt;

  const CoViewPollSession({
    required this.id,
    required this.status,
    required this.poolSource,
    required this.roundNumber,
    required this.deadline,
    required this.candidates,
    this.voteCounts = const [],
    this.myVote,
    this.votedCount = 0,
    this.memberCount = 2,
    this.winner,
    required this.createdAt,
  });

  bool get isDone => status == 'done';
  bool get isCompany => memberCount > 2;
  bool get hasVoted => myVote != null;

  int votesFor(int index) => index < voteCounts.length ? voteCounts[index] : 0;

  int get totalVotes => voteCounts.fold(0, (a, b) => a + b);

  Duration get timeLeft {
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  factory CoViewPollSession.fromJson(Map<String, dynamic> json) => CoViewPollSession(
        id: json['id'] as String,
        status: json['status'] as String,
        poolSource: json['pool_source'] as String? ?? 'personal',
        roundNumber: json['round_number'] as int? ?? 1,
        deadline: parseServerUtc(json['deadline'] as String),
        candidates: (json['candidates'] as List? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        voteCounts: (json['vote_counts'] as List? ?? const [])
            .map((e) => e as int)
            .toList(),
        myVote: json['my_vote'] as int?,
        votedCount: json['voted_count'] as int? ?? 0,
        memberCount: json['member_count'] as int? ?? 2,
        winner: json['winner'] != null
            ? MediaItem.fromJson(json['winner'] as Map<String, dynamic>)
            : null,
        createdAt: parseServerUtc(json['created_at'] as String),
      );
}
