/// Mirrors backend/app/schemas.py::ReferredUserOut — one invited person
/// in "Мои приглашения", with live progress against the three
/// real-person conditions when still pending (see routers/referrals.py
/// for what those three conditions are and why).
class ReferredUser {
  final String referredUserId;
  final String? displayName;
  final String username;
  final String status; // "pending" | "verified" | "rewarded" | "rejected"
  final DateTime createdAt;
  final DateTime? verifiedAt;

  final int entriesCount;
  final int entriesRequired;
  final int streakDays;
  final int streakDaysRequired;
  final int daysSinceSignup;
  final int daysSinceSignupRequired;
  final DateTime eligibleNotBefore;

  const ReferredUser({
    required this.referredUserId,
    this.displayName,
    required this.username,
    required this.status,
    required this.createdAt,
    this.verifiedAt,
    required this.entriesCount,
    required this.entriesRequired,
    required this.streakDays,
    required this.streakDaysRequired,
    required this.daysSinceSignup,
    required this.daysSinceSignupRequired,
    required this.eligibleNotBefore,
  });

  /// Display name, falling back to username — same pattern used
  /// everywhere else a person's name is shown (see models.User.
  /// display_name's own backend comment).
  String get name => (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : username;

  bool get isPending => status == 'pending';
  bool get isRewarded => status == 'rewarded';
  bool get isVerified => status == 'verified' || status == 'rewarded';
  bool get isRejected => status == 'rejected';

  factory ReferredUser.fromJson(Map<String, dynamic> json) => ReferredUser(
        referredUserId: json['referred_user_id'] as String,
        displayName: json['display_name'] as String?,
        username: json['username'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        createdAt: DateTime.parse(json['created_at'] as String),
        verifiedAt: json['verified_at'] != null ? DateTime.tryParse(json['verified_at'] as String) : null,
        entriesCount: json['entries_count'] as int? ?? 0,
        entriesRequired: json['entries_required'] as int? ?? 3,
        streakDays: json['streak_days'] as int? ?? 0,
        streakDaysRequired: json['streak_days_required'] as int? ?? 5,
        daysSinceSignup: json['days_since_signup'] as int? ?? 0,
        daysSinceSignupRequired: json['days_since_signup_required'] as int? ?? 7,
        eligibleNotBefore: DateTime.parse(json['eligible_not_before'] as String),
      );
}

/// Mirrors backend/app/schemas.py::ReferralStatusOut — everything
/// "Пригласи друга" / "Мои приглашения" need in one call. See
/// backend/app/routers/referrals.py's module docstring for why this is
/// also the call that quietly recomputes/verifies pending invitees —
/// there's no separate "refresh" action, loading this screen IS the
/// refresh.
class ReferralStatus {
  final int verifiedCount;
  final int pendingCount;
  final int? nextMilestoneAt;
  final int? nextMilestoneDays;
  final List<ReferredUser> referred;
  final String? promoCode;
  final int promoDiscountPercent;
  final int referredWelcomeDays;

  const ReferralStatus({
    required this.verifiedCount,
    required this.pendingCount,
    this.nextMilestoneAt,
    this.nextMilestoneDays,
    required this.referred,
    this.promoCode,
    required this.promoDiscountPercent,
    required this.referredWelcomeDays,
  });

  factory ReferralStatus.fromJson(Map<String, dynamic> json) => ReferralStatus(
        verifiedCount: json['verified_count'] as int? ?? 0,
        pendingCount: json['pending_count'] as int? ?? 0,
        nextMilestoneAt: json['next_milestone_at'] as int?,
        nextMilestoneDays: json['next_milestone_days'] as int?,
        referred: (json['referred'] as List? ?? [])
            .map((e) => ReferredUser.fromJson(e as Map<String, dynamic>))
            .toList(),
        promoCode: json['promo_code'] as String?,
        promoDiscountPercent: json['promo_discount_percent'] as int? ?? 15,
        referredWelcomeDays: json['referred_welcome_days'] as int? ?? 3,
      );
}
