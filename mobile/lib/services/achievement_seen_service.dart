import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which achievement unlocks this account has already been
/// shown the mint/celebration moment for — purely a local, per-device
/// bookkeeping detail (like [TodayPickPrefsService]'s dismiss state),
/// nothing the backend needs to know about, since `Achievement.unlocked`
/// itself is always computed fresh from the person's own logged rows
/// (see the model's own doc comment) and never goes back to locked.
///
/// Deliberately a plain static-method helper rather than a
/// [ChangeNotifier] service loaded once at app start: nothing here
/// drives UI reactively (no widget needs to rebuild when the seen-set
/// changes), it's read-and-diffed at exactly one moment — right after
/// an achievements fetch resolves — so there's nothing to gain from the
/// heavier load()/reloadForUser() machinery [TodayPickPrefsService]
/// needs for state that *does* drive UI continuously.
class AchievementSeenService {
  static const _keyPrefix = 'seenly_achv_seen_';

  static String _key(String? userId) => '$_keyPrefix${userId ?? 'anon'}';

  /// The full set of achievement ids this account has ever been shown
  /// the unlock celebration for.
  static Future<Set<String>> seenIds(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(userId)) ?? const []).toSet();
  }

  /// Adds [ids] to the seen set (idempotent — already-seen ids are a
  /// no-op) and persists it.
  static Future<void> markSeen(String? userId, Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_key(userId)) ?? const []).toSet();
    current.addAll(ids);
    await prefs.setStringList(_key(userId), current.toList());
  }

  /// True the very first time this account's achievements are ever
  /// checked (the key has never been written) — the signal
  /// [AchievementsScreen] uses to silently baseline every
  /// already-unlocked badge as "seen" instead of celebrating a whole
  /// wall of them at once the first time someone (say, after importing
  /// a watch history) opens the screen with a dozen already earned.
  static Future<bool> isFirstEverCheck(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    return !prefs.containsKey(_key(userId));
  }
}
