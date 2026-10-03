/// Mirrors backend/app/schemas.py::RecommendationOut — one staked "I bet
/// you'll rate this N" between two friends (see
/// backend/app/routers/recommendations.py and app/sincerity.py's module
/// docstring for the full idea). `status` is the raw wire value from
/// models.RecommendationStatus: "pending", "hit", "missed" or "expired".
class Recommendation {
  final String id;
  final String stakerId;
  final String stakerUsername;
  final String recipientId;
  final String recipientUsername;
  final String source;
  final String mediaId;
  final String title;
  final int predictedRating;
  final int stakedAmount;
  final String status;
  final int? actualRating;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  /// True when the current person is the one who staked it — lets one
  /// card layout read as "ты поставил(а)…" or "…поставил(а) на тебя"
  /// without the screen needing to know whose id is whose.
  final bool isMine;

  const Recommendation({
    required this.id,
    required this.stakerId,
    required this.stakerUsername,
    required this.recipientId,
    required this.recipientUsername,
    required this.source,
    required this.mediaId,
    required this.title,
    required this.predictedRating,
    required this.stakedAmount,
    required this.status,
    this.actualRating,
    required this.createdAt,
    this.resolvedAt,
    required this.isMine,
  });

  bool get isPending => status == 'pending';

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      id: json['id'] as String,
      stakerId: json['staker_id'] as String,
      stakerUsername: json['staker_username'] as String,
      recipientId: json['recipient_id'] as String,
      recipientUsername: json['recipient_username'] as String,
      source: json['source'] as String,
      mediaId: json['media_id'] as String,
      title: json['title'] as String,
      predictedRating: json['predicted_rating'] as int,
      stakedAmount: json['staked_amount'] as int,
      status: json['status'] as String,
      actualRating: json['actual_rating'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at'] as String) : null,
      isMine: json['is_mine'] as bool,
    );
  }
}

/// Mirrors backend/app/schemas.py::RecommendationsOut — the full
/// response of GET /recommendations.
class RecommendationsResponse {
  final List<Recommendation> outgoing;
  final List<Recommendation> incoming;

  const RecommendationsResponse({required this.outgoing, required this.incoming});

  factory RecommendationsResponse.fromJson(Map<String, dynamic> json) {
    return RecommendationsResponse(
      outgoing: (json['outgoing'] as List<dynamic>)
          .map((e) => Recommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
      incoming: (json['incoming'] as List<dynamic>)
          .map((e) => Recommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
