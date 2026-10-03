import 'package:shared_preferences/shared_preferences.dart';

/// [AchievementSeenService]'s own counterpart for the "наши вехи" badges
/// on the co-viewing hub's "мы" tab — same purely-local, per-device
/// bookkeeping, nothing the backend needs to know about, since
/// `Achievement.unlocked` here is also always computed fresh (see
/// compute_couple_achievements_for_link's doc comment server-side) and
/// never goes back to locked.
///
/// Keyed by this account's own [userId] alone, not by link id — there's
/// no link id exposed to the client at all (see PartnerStatus), and it
/// turns out not to matter: unlinking and relinking to anyone, even the
/// same partner, means a brand-new `PartnerLink` row server-side, and
/// every couple achievement is scored off that link's own rows (see
/// `_shared_rows(db, link)` there), so a fresh link genuinely starts
/// every couple badge back at zero progress rather than silently
/// inheriting old unlocks. Nothing here needs to distinguish "seen for
/// circle A" from "seen for circle B" as a result.
class CoupleAchievementSeenService {
  static const _keyPrefix = 'seenly_couple_achv_seen_';

  static String _key(String? userId) => '$_keyPrefix${userId ?? 'anon'}';

  /// The full set of couple-achievement ids this account has ever been
  /// shown the unlock celebration for.
  static Future<Set<String>> seenIds(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(userId)) ?? const []).toSet();
  }

  /// Adds [ids] to the seen set (idempotent) and persists it.
  static Future<void> markSeen(String? userId, Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_key(userId)) ?? const []).toSet();
    current.addAll(ids);
    await prefs.setStringList(_key(userId), current.toList());
  }

  /// True the very first time this account's couple achievements are
  /// ever checked — same "baseline silently, don't celebrate a whole
  /// wall at once" signal as [AchievementSeenService.isFirstEverCheck],
  /// for whoever links up with a partner who already has a long shared
  /// history to import/backfill.
  static Future<bool> isFirstEverCheck(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    return !prefs.containsKey(_key(userId));
  }
}
