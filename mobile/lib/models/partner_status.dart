import '../utils/server_time.dart';
import 'taste_match.dart';

/// Mirrors `PartnerMemberOut` — one seat on the co-viewing circle,
/// including the caller's own (see `isYou`).
class PartnerMember {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final bool isYou;

  const PartnerMember({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.isYou = false,
  });

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory PartnerMember.fromJson(Map<String, dynamic> json) => PartnerMember(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        isYou: json['is_you'] as bool? ?? false,
      );
}

/// Mirrors `PartnerOut` in backend/app/schemas.py — the co-viewing card's
/// entire state in one shape: already linked (as a couple or, once a
/// third person's joined, a company), waiting on a code that was just
/// generated, or neither.
class PartnerStatus {
  final bool linked;
  final String? partnerUsername;
  final String? pendingCode;
  // Everyone in the circle, including the caller — a couple is always
  // exactly two entries; a company is three or more. Empty when
  // [linked] is false.
  final List<PartnerMember> members;
  final bool isCompany;

  const PartnerStatus({
    required this.linked,
    this.partnerUsername,
    this.pendingCode,
    this.members = const [],
    this.isCompany = false,
  });

  factory PartnerStatus.fromJson(Map<String, dynamic> json) => PartnerStatus(
        linked: json['linked'] as bool,
        partnerUsername: json['partner_username'] as String?,
        pendingCode: json['pending_code'] as String?,
        members: (json['members'] as List? ?? const [])
            .map((e) => PartnerMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        isCompany: json['is_company'] as bool? ?? false,
      );
}

/// Mirrors `PartnerInviteOut` — one pending (or just-answered) direct
/// invite to join a co-viewing circle, the alternative to sharing a
/// pairing code. `userId`/`username` are the *other* side of the invite
/// from the caller's point of view, whichever direction it's going.
class PartnerInvite {
  final String id;
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final String status; // "pending" | "accepted" | "declined"
  final DateTime? createdAt;

  const PartnerInvite({
    required this.id,
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    required this.status,
    this.createdAt,
  });

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory PartnerInvite.fromJson(Map<String, dynamic> json) => PartnerInvite(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        status: json['status'] as String,
        createdAt: tryParseServerUtc(json['created_at'] as String?),
      );
}

/// Mirrors `PartnerInvitesOut` — every pending invite touching this
/// account, split by direction.
class PartnerInvites {
  final List<PartnerInvite> incoming;
  final List<PartnerInvite> outgoing;

  const PartnerInvites({this.incoming = const [], this.outgoing = const []});

  factory PartnerInvites.fromJson(Map<String, dynamic> json) => PartnerInvites(
        incoming: (json['incoming'] as List? ?? const [])
            .map((e) => PartnerInvite.fromJson(e as Map<String, dynamic>))
            .toList(),
        outgoing: (json['outgoing'] as List? ?? const [])
            .map((e) => PartnerInvite.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Mirrors `CircleCompatibilityOut` — this account's taste match (see
/// models/taste_match.dart) against one other member of its co-viewing
/// circle. A couple gets exactly one of these back from
/// PartnerService.compatibility(), a company one per other seat. Powers
/// the "мы" tab's compatibility section.
class CircleCompatibility {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarPreset;
  final String? avatarUrl;
  final TasteMatch? tasteMatch;

  const CircleCompatibility({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarPreset,
    this.avatarUrl,
    this.tasteMatch,
  });

  String get nameForDisplay =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  factory CircleCompatibility.fromJson(Map<String, dynamic> json) => CircleCompatibility(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatarPreset: json['avatar_preset'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        tasteMatch: TasteMatch.tryParse(json['taste_match']),
      );
}
