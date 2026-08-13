import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings > "today's pick" toggle, plus the card's own per-day dismiss
/// and "accepted" state.
///
/// The on/off toggle in Settings is a genuine device/UI preference —
/// same device-only [SharedPreferences] pattern as
/// [AutoTrackingPrefsService]'s banner flag — so it stays shared across
/// whoever's signed in on this device.
///
/// The dismiss/accepted/reroll state is different: it's tied to one
/// account's actual pick, the same "content, not a device preference"
/// distinction [EveningPlanService] draws for planned evenings. Without
/// scoping, dismissing today's pick on one account and then switching
/// to another account on the same device would show that second
/// account's pick as already dismissed too (or, the other way round,
/// hide the fact the first account ever dismissed it). So those three
/// keys are namespaced per signed-in account (see [_keyFor] /
/// [reloadForUser]) exactly like [EveningPlanService.reloadForUser] —
/// loaded once at app start under no particular account (app.dart's
/// `TodayPickPrefsService()..load()`), then re-scoped whenever the
/// signed-in account actually changes by app.dart's account-scope
/// widget, which watches `AppState.currentUser?.id`.
///
/// The card offers two ways to close it (see widgets/today_pick_card.dart):
/// "not now" (with a small "see you tomorrow" snackbar) and a plain "×"
/// (silent). Both end up calling [dismiss] here — they're the same
/// underlying state, "hide today's pick", just with a different amount of
/// ceremony on the way out. Either way the card comes back on its own once
/// the server hands back a new `pick_date` (see [TodayPick.pickDate]) —
/// there's nothing to "undo" here, it just naturally reappears tomorrow.
///
/// Tapping "I'm in" marks that day's pick [accept]ed — from then on the
/// card shows its progress readout (see [TodayPickCard]'s segmented bar)
/// even at 0 watched, instead of only appearing once something's actually
/// been watched, and the CTA switches from "I'm in" to "keep going".
class TodayPickPrefsService extends ChangeNotifier {
  static const _enabledKey = 'seenly_today_pick_enabled';
  static const _dismissedDateKey = 'seenly_today_pick_dismissed_date';
  static const _acceptedDateKey = 'seenly_today_pick_accepted_date';
  static const _rerollKey = 'seenly_today_pick_reroll';

  /// How many times [reroll] will actually bump the count for a single
  /// [pickDate] — past this, [reroll] is a no-op (returns the current
  /// count unchanged) and [hasRerollsLeft] goes false, so the card's
  /// shuffle button can disable itself instead of spending a network
  /// call to find out. Resets with everything else once the day's
  /// `pickDate` changes — "3 more tomorrow", not "3 ever".
  static const maxRerolls = 3;

  bool _enabled = true;
  bool get enabled => _enabled;

  String? _dismissedDate;
  String? _acceptedDate;

  // Stored as "pickDate:count" — a plain int alone can't tell "0 rerolls
  // today" from "never rerolled at all", and can't tell today's count
  // from a stale one left over from a previous day (see rerollCount).
  String? _rerollRaw;

  // Which account's dismiss/accepted/reroll state is currently loaded —
  // null means "no signed-in account yet" (the brief window before
  // AppState's own bootstrap resolves, or while actually signed out),
  // which reads from the same bare, unscoped keys these three always
  // used before per-account scoping existed.
  String? _scopeUserId;

  String _keyFor(String base, String? userId) => userId == null ? base : '${base}_$userId';

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;

    final dismissedKey = _keyFor(_dismissedDateKey, _scopeUserId);
    final acceptedKey = _keyFor(_acceptedDateKey, _scopeUserId);
    final rerollKey = _keyFor(_rerollKey, _scopeUserId);

    var dismissed = prefs.getString(dismissedKey);
    var accepted = prefs.getString(acceptedKey);
    var reroll = prefs.getString(rerollKey);

    if (_scopeUserId != null && dismissed == null && accepted == null && reroll == null) {
      // This account's own keys have never been written to — before
      // per-account scoping existed, every account on this device
      // shared the bare keys above. Migrate whatever's sitting there
      // into this account's own keys (so whoever's actually signed in
      // right now doesn't lose state they already had) and clear the
      // shared keys so they can't also leak into the next account that
      // signs in on this device.
      final legacyDismissed = prefs.getString(_dismissedDateKey);
      final legacyAccepted = prefs.getString(_acceptedDateKey);
      final legacyReroll = prefs.getString(_rerollKey);
      if (legacyDismissed != null || legacyAccepted != null || legacyReroll != null) {
        dismissed = legacyDismissed;
        accepted = legacyAccepted;
        reroll = legacyReroll;
        if (legacyDismissed != null) await prefs.setString(dismissedKey, legacyDismissed);
        if (legacyAccepted != null) await prefs.setString(acceptedKey, legacyAccepted);
        if (legacyReroll != null) await prefs.setString(rerollKey, legacyReroll);
        await prefs.remove(_dismissedDateKey);
        await prefs.remove(_acceptedDateKey);
        await prefs.remove(_rerollKey);
      }
    }

    _dismissedDate = dismissed;
    _acceptedDate = accepted;
    _rerollRaw = reroll;
    _loaded = true;
    notifyListeners();
  }

  /// Switches which account's dismiss/accepted/reroll state this
  /// service is showing — called by app.dart's account-scope widget
  /// whenever `AppState.currentUser?.id` actually changes (sign-in,
  /// sign-out, or switching to a different account on the same
  /// device). A no-op when [userId] is the account already loaded, so
  /// it's safe to call this on every rebuild rather than only on a
  /// confirmed edge.
  Future<void> reloadForUser(String? userId) async {
    if (_loaded && _scopeUserId == userId) return;
    _scopeUserId = userId;
    // Clears what's showing immediately, before the new account's own
    // state (or lack of it) finishes loading — so there's never a
    // frame where the previous account's dismissed/accepted pick is
    // still reflected under the new account.
    _dismissedDate = null;
    _acceptedDate = null;
    _rerollRaw = null;
    _loaded = false;
    notifyListeners();
    await load();
  }

  /// Whether the card for [pickDate] (the server's `TodayPick.pickDate`)
  /// should be hidden — either the person turned the whole feature off in
  /// Settings, or already dismissed this exact day's pick.
  bool isDismissed(String pickDate) => !_enabled || _dismissedDate == pickDate;

  /// Whether [pickDate]'s pick was accepted ("I'm in") — kept per
  /// `pick_date` the same way [isDismissed] is, so it naturally clears
  /// itself once the server rotates to a new day/franchise rather than
  /// needing an explicit reset.
  bool isAccepted(String pickDate) => _acceptedDate == pickDate;

  /// Marks [pickDate] as accepted — "I'm in" tapped.
  Future<void> accept(String pickDate) async {
    if (_acceptedDate == pickDate) return;
    _acceptedDate = pickDate;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(_acceptedDateKey, _scopeUserId), pickDate);
  }

  /// Hides the card for [pickDate] — called by both the "not now" button
  /// and the "×". A new `pick_date` from the server (tomorrow, or today's
  /// next unfinished franchise) naturally reads as "not dismissed" again,
  /// no separate reset needed.
  Future<void> dismiss(String pickDate) async {
    if (_dismissedDate == pickDate) return;
    _dismissedDate = pickDate;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(_dismissedDateKey, _scopeUserId), pickDate);
  }

  /// How many times the shuffle button has been tapped for [pickDate] —
  /// 0 for a day that's never been rerolled, and also 0 once [pickDate]
  /// moves on to a new day (a leftover count from yesterday shouldn't
  /// carry over). This is purely a local nudge for GET /feed/today-pick's
  /// `offset` param, not synced anywhere — a fresh install or a second
  /// device just starts from the shared daily pick again.
  int rerollCount(String pickDate) {
    final raw = _rerollRaw;
    if (raw == null) return 0;
    final parts = raw.split(':');
    if (parts.length != 2 || parts[0] != pickDate) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  /// Whether [pickDate] still has a shuffle left — see [maxRerolls].
  bool hasRerollsLeft(String pickDate) => rerollCount(pickDate) < maxRerolls;

  /// Bumps the reroll count for [pickDate] by one and returns the new
  /// value, so the caller can immediately refetch with that as `offset`.
  /// Once [maxRerolls] is already reached this is a no-op that just
  /// returns the unchanged current count — callers should check
  /// [hasRerollsLeft] first rather than rely on this to enforce the cap.
  Future<int> reroll(String pickDate) async {
    final current = rerollCount(pickDate);
    if (current >= maxRerolls) return current;
    final next = current + 1;
    _rerollRaw = '$pickDate:$next';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(_rerollKey, _scopeUserId), _rerollRaw!);
    return next;
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }
}
