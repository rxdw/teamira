import 'media_item.dart';
import '../utils/server_time.dart';

/// Mirrors TogetherSessionOut in backend/app/schemas.py — one snapshot of
/// a network watch-together session, from the point of view of whichever
/// account just asked for it (owner or guest — see [myRole]).
class TogetherSession {
  final String id;
  final String code;
  final String status; // "waiting" | "active" | "done"
  final String typeFilter;
  final List<String> genresFilter;
  final List<MediaItem> deck;
  final String ownerUsername;
  final String? guestUsername;
  final String myRole; // "owner" | "guest"
  final int mySwiped;
  final int partnerSwiped;
  final List<MediaItem> matches;
  final DateTime createdAt;

  const TogetherSession({
    required this.id,
    required this.code,
    required this.status,
    required this.typeFilter,
    this.genresFilter = const [],
    required this.deck,
    required this.ownerUsername,
    this.guestUsername,
    required this.myRole,
    required this.mySwiped,
    required this.partnerSwiped,
    required this.matches,
    required this.createdAt,
  });

  bool get partnerJoined => guestUsername != null;
  String? get partnerUsername => myRole == 'owner' ? guestUsername : ownerUsername;

  factory TogetherSession.fromJson(Map<String, dynamic> json) => TogetherSession(
        id: json['id'] as String,
        code: json['code'] as String,
        status: json['status'] as String,
        typeFilter: json['type_filter'] as String,
        genresFilter: (json['genres_filter'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        deck: (json['deck'] as List? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        ownerUsername: json['owner_username'] as String,
        guestUsername: json['guest_username'] as String?,
        myRole: json['my_role'] as String,
        mySwiped: json['my_swiped'] as int,
        partnerSwiped: json['partner_swiped'] as int,
        matches: (json['matches'] as List? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: parseServerUtc(json['created_at'] as String),
      );
}
