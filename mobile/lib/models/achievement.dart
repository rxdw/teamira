/// Mirrors `AchievementOut` in backend/app/schemas.py — every figure behind
/// these (see app/routers/profile.py::get_achievements) is computed fresh
/// from the person's own logged rows, nothing stored separately that could
/// drift out of sync with what's actually been watched.
class Achievement {
  final String id;
  final String category; // "milestone" | "craft" | "genre" | "saga" | "devotion"
  final String iconKey;
  final String title;
  final String caption;
  final bool unlocked;
  final int progressCurrent;
  final int progressTarget;
  // "habit" | "devoted" | "obsession" | "legend" — see
  // profile.py::_rarity_for_target. Purely cosmetic (drives
  // AchievementBadge's material/glow), never affects unlock logic.
  final String rarity;

  const Achievement({
    required this.id,
    required this.category,
    required this.iconKey,
    required this.title,
    required this.caption,
    required this.unlocked,
    required this.progressCurrent,
    required this.progressTarget,
    required this.rarity,
  });

  double get progressRatio =>
      progressTarget <= 0 ? 0 : (progressCurrent / progressTarget).clamp(0, 1);

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
        id: json['id'] as String,
        category: json['category'] as String,
        iconKey: json['icon_key'] as String,
        title: json['title'] as String,
        caption: json['caption'] as String,
        unlocked: json['unlocked'] as bool,
        progressCurrent: json['progress_current'] as int,
        progressTarget: json['progress_target'] as int,
        rarity: json['rarity'] as String? ?? 'habit',
      );
}

/// Mirrors `AchievementsOut`.
class AchievementsResponse {
  final int unlockedCount;
  final int totalCount;
  final List<Achievement> achievements;
  final List<String> pinnedIds;
  // How many badges the showcase can hold right now (3 free + however
  // many bought — see backend/app/sincerity.py::spend_pin_slot) and how
  // many of those were bought. The client reads maxPinned instead of
  // hardcoding 3 so a purchase takes effect without an app update.
  final int maxPinned;
  final int bonusPinSlots;

  const AchievementsResponse({
    required this.unlockedCount,
    required this.totalCount,
    required this.achievements,
    this.pinnedIds = const [],
    this.maxPinned = 3,
    this.bonusPinSlots = 0,
  });

  factory AchievementsResponse.fromJson(Map<String, dynamic> json) =>
      AchievementsResponse(
        unlockedCount: json['unlocked_count'] as int,
        totalCount: json['total_count'] as int,
        achievements: (json['achievements'] as List? ?? const [])
            .map((e) => Achievement.fromJson(e as Map<String, dynamic>))
            .toList(),
        pinnedIds: (json['pinned_ids'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        maxPinned: json['max_pinned'] as int? ?? 3,
        bonusPinSlots: json['bonus_pin_slots'] as int? ?? 0,
      );
}
