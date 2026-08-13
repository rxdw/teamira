import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether Home's "on this day" section has been closed by the person —
/// dismissed per calendar day, same "content, not a device preference"
/// idea as [TodayPickPrefsService], since which entries show up changes
/// with the date rather than staying fixed like a real device setting.
///
/// Scoped per signed-in account exactly like [TodayPickPrefsService]
/// (see that service's docstring for the full reasoning) — "on this
/// day" is read from one account's own diary, so dismissing it on one
/// account shouldn't hide it for another account signed in on the same
/// device. Loaded once at app start under no particular account
/// (app.dart's `OnThisDayPrefsService()..load()`), then re-scoped by
/// app.dart's account-scope widget whenever `AppState.currentUser?.id`
/// actually changes.
///
/// There's nothing to "undo": once the date rolls over, [isDismissed]
/// naturally reads false again for the new day.
class OnThisDayPrefsService extends ChangeNotifier {
  static const _dismissedDateKey = 'seenly_on_this_day_dismissed_date';

  String? _dismissedDate;
  String? _scopeUserId;

  String _keyFor(String base, String? userId) => userId == null ? base : '${base}_$userId';

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(_dismissedDateKey, _scopeUserId);
    var dismissed = prefs.getString(key);

    if (_scopeUserId != null && dismissed == null) {
      // Migrate any pre-account-scoping value the same way
      // TodayPickPrefsService does, so whoever's signed in right now
      // doesn't lose a dismissal they already made.
      final legacy = prefs.getString(_dismissedDateKey);
      if (legacy != null) {
        dismissed = legacy;
        await prefs.setString(key, legacy);
        await prefs.remove(_dismissedDateKey);
      }
    }

    _dismissedDate = dismissed;
    _loaded = true;
    notifyListeners();
  }

  /// Switches which account's dismiss state this service is showing —
  /// see [TodayPickPrefsService.reloadForUser]. A no-op when [userId]
  /// is the account already loaded.
  Future<void> reloadForUser(String? userId) async {
    if (_loaded && _scopeUserId == userId) return;
    _scopeUserId = userId;
    _dismissedDate = null;
    _loaded = false;
    notifyListeners();
    await load();
  }

  /// Whether the section should stay hidden for [dateKey] — a plain
  /// `yyyy-MM-dd` for "today" (see `_dateKey` in home_screen.dart).
  bool isDismissed(String dateKey) => _dismissedDate == dateKey;

  /// Hides the section for [dateKey]. Tomorrow's different `dateKey`
  /// naturally reads as "not dismissed" again — no reset needed.
  Future<void> dismiss(String dateKey) async {
    if (_dismissedDate == dateKey) return;
    _dismissedDate = dateKey;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(_dismissedDateKey, _scopeUserId), dateKey);
  }
}
