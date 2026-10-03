import 'api_client.dart';

/// What POST /shares/card answered — see backend/app/routers/card_shares.py.
class CardShareResult {
  /// False when this card already paid out once, or today's cap was
  /// already used up. The share itself is fine either way.
  final bool counted;
  final int pointsAwarded;
  /// "already_counted" | "daily_limit" | null
  final String? reason;
  final int level;
  final bool leveledUp;

  const CardShareResult({
    required this.counted,
    this.pointsAwarded = 0,
    this.reason,
    this.level = 1,
    this.leveledUp = false,
  });

  factory CardShareResult.fromJson(Map<String, dynamic> json) => CardShareResult(
        counted: json['counted'] as bool? ?? false,
        pointsAwarded: json['points_awarded'] as int? ?? 0,
        reason: json['reason'] as String?,
        level: json['level'] as int? ?? 1,
        leveledUp: json['leveled_up'] as bool? ?? false,
      );
}

/// Tells the server a share card left the app so it can pay sincerity
/// points for it. The server dedupes per card and caps per day, so
/// calling this for every share is safe — a repeat just comes back with
/// counted: false.
class CardShareService {
  final ApiClient _client;
  CardShareService(this._client);

  Future<CardShareResult> record(String cardKey) async {
    final json = await _client.post(
      '/shares/card',
      body: {'card_key': cardKey},
    ) as Map<String, dynamic>;
    return CardShareResult.fromJson(json);
  }
}
