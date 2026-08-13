import 'media_item.dart';

/// Mirrors `CoViewVoteSessionOut` in backend/app/schemas.py — one shared
/// voting round, built from every current member's own "plan to watch"
/// shelves. There's no code to join — an active partner link already
/// means everyone's a confirmed member, so every phone in the circle
/// polls this same session and each always sees itself as "me" via
/// [myDecided].
class CoViewVoteSession {
  final String id;
  final String status; // "active" | "done"
  final String poolSource; // "personal" | "coview" | "both"
  final List<MediaItem> deck;
  final List<String> myDecided; // "source:id" keys this account already voted on
  final int partnerDecidedCount;
  // Everyone currently in the circle, including this account — lets the
  // UI tell a couple (always 2) apart from a company (3+) so it can say
  // "them" vs "the others" and size partnerDecidedCount's denominator
  // correctly instead of assuming a single partner.
  final int memberCount;
  final MediaItem? winner;
  final DateTime createdAt;

  const CoViewVoteSession({
    required this.id,
    required this.status,
    required this.poolSource,
    required this.deck,
    this.myDecided = const [],
    this.partnerDecidedCount = 0,
    this.memberCount = 2,
    this.winner,
    required this.createdAt,
  });

  bool get isDone => status == 'done';
  bool get matched => winner != null;
  bool get isCompany => memberCount > 2;

  /// The next card neither side has swiped away yet, or null once this
  /// account has gone through the whole deck.
  MediaItem? get nextCard {
    for (final item in deck) {
      if (!myDecided.contains('${item.source}:${item.id}')) return item;
    }
    return null;
  }

  int get remaining => deck.length - myDecided.length;

  factory CoViewVoteSession.fromJson(Map<String, dynamic> json) => CoViewVoteSession(
        id: json['id'] as String,
        status: json['status'] as String,
        poolSource: json['pool_source'] as String? ?? 'personal',
        deck: (json['deck'] as List? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        myDecided: (json['my_decided'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        partnerDecidedCount: json['partner_decided_count'] as int? ?? 0,
        memberCount: json['member_count'] as int? ?? 2,
        winner: json['winner'] != null
            ? MediaItem.fromJson(json['winner'] as Map<String, dynamic>)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
