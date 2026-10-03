import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/planned_evening.dart';

/// Owns every evening someone's holding a ticket for — see
/// [PlannedEvening]'s own docstring for why that can be more than one.
/// Same device-only SharedPreferences pattern as
/// [CoViewPrefsService]/[RitualPrefsService] in *how* it's stored, but
/// unlike those (which are genuine device/UI preferences, fine to
/// carry across whoever's signed in), a planned evening is actual
/// content tied to one account — including, for a co-viewing evening,
/// a specific linked partner (see [PlannedEvening.partnerUsername]).
/// So the storage key itself is scoped per signed-in account (see
/// [reloadForUser]) rather than shared device-wide: switching accounts
/// on the same device must not hand the new account a ticket — or
/// worse, a co-viewing ticket for a partner it isn't even linked to —
/// that actually belonged to whoever was signed in before.
///
/// Loaded once at app start under no particular account (see app.dart's
/// `EveningPlanService()..load()`), then re-scoped every time the
/// signed-in account actually changes by app.dart's
/// `_AccountScopedPrefsScope`, which watches `AppState.currentUser?.id`
/// and calls [reloadForUser]. Read from three places (Home, Profile,
/// CoViewingScreen) via `context.watch<EveningPlanService>()`, so
/// getting a ticket on one screen updates the reminder on the other two
/// immediately.
class EveningPlanService extends ChangeNotifier {
  static const _key = 'seenly_planned_evening';

  List<PlannedEvening> _plans = const [];

  // Which account's tickets are currently loaded — null means "no
  // signed-in account yet" (the brief window before AppState's own
  // bootstrap resolves, or while actually signed out), which reads
  // from the same bare, unscoped key this service always used before
  // per-account scoping existed.
  String? _scopeUserId;

  String _keyFor(String? userId) => userId == null ? _key : '${_key}_$userId';

  /// All planned evenings, soonest first. Past ones sort to the end (by
  /// how long ago they were), same "still here until you deal with it"
  /// idea the single-plan version had.
  List<PlannedEvening> get plans {
    final sorted = [..._plans];
    sorted.sort((a, b) => a.date.compareTo(b.date));
    return List.unmodifiable(sorted);
  }

  bool get hasPlans => _plans.isNotEmpty;

  /// The one ticket to show where the app only has room for one: the
  /// soonest evening that hasn't happened yet, or — if everything
  /// planned is already in the past — the most recent of those, so a
  /// forgotten plan still surfaces as "did you watch it?" instead of
  /// just vanishing.
  PlannedEvening? get plan {
    if (_plans.isEmpty) return null;
    final upcoming = _plans.where((p) => !p.isPast).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (upcoming.isNotEmpty) return upcoming.first;
    final past = [..._plans]..sort((a, b) => b.date.compareTo(a.date));
    return past.first;
  }

  /// Same "soonest upcoming, else latest past" pick as [plan], but only
  /// among plans matching [test] — for a screen that only cares about
  /// one kind of evening. The co-viewing hub's own ticket card uses this
  /// (matching `p.coViewing`) so a solo evening planned from Home/Profile
  /// doesn't show up there as if it were a shared one, just because it
  /// happens to be the soonest thing on the calendar overall.
  PlannedEvening? planMatching(bool Function(PlannedEvening) test) {
    final matching = _plans.where(test).toList();
    if (matching.isEmpty) return null;
    final upcoming = matching.where((p) => !p.isPast).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (upcoming.isNotEmpty) return upcoming.first;
    final past = [...matching]..sort((a, b) => b.date.compareTo(a.date));
    return past.first;
  }

  /// How many *other* evenings are planned besides the one [plan] is
  /// already showing — what a "+2 more" affordance counts against.
  int get otherPlansCount => _plans.isEmpty ? 0 : _plans.length - 1;

  /// Same idea as [otherPlansCount], scoped to [test] — pairs with
  /// [planMatching].
  int otherCountMatching(bool Function(PlannedEvening) test) {
    final matching = _plans.where(test).length;
    return matching == 0 ? 0 : matching - 1;
  }

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _keyFor(_scopeUserId);
    var raw = prefs.getString(scopedKey);
    if (raw == null && _scopeUserId != null) {
      // This account's own key has never been written to — before
      // per-account scoping existed, every account on this device
      // shared the one bare key above. Migrate whatever's sitting
      // there into this account's own key (so whoever's actually
      // signed in right now doesn't lose tickets they already had)
      // and clear the shared key so it can't also leak into the next
      // account that signs in on this device.
      final legacy = prefs.getString(_key);
      if (legacy != null) {
        raw = legacy;
        await prefs.setString(scopedKey, legacy);
        await prefs.remove(_key);
      }
    }
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _plans = decoded
              .map((e) => PlannedEvening.fromJson(e as Map<String, dynamic>))
              .toList();
        } else if (decoded is Map<String, dynamic>) {
          // Migrating a save from before multiple evenings were
          // supported — one bare object instead of a list.
          _plans = [PlannedEvening.fromJson(decoded)];
        }
      } catch (_) {
        _plans = const [];
      }
    } else {
      _plans = const [];
    }
    _loaded = true;
    notifyListeners();
  }

  /// Switches which account's tickets this service is showing — called
  /// by app.dart's `_AccountScopedPrefsScope` whenever
  /// `AppState.currentUser?.id` actually changes (sign-in, sign-out, or
  /// switching to a different account on the same device). A no-op
  /// when [userId] is the account already loaded, so it's safe to call
  /// this on every rebuild rather than only on a confirmed edge.
  Future<void> reloadForUser(String? userId) async {
    if (_loaded && _scopeUserId == userId) return;
    _scopeUserId = userId;
    // Clears what's showing immediately, before the new account's own
    // tickets (or lack of them) finish loading — so there's never a
    // frame where the previous account's ticket is still on screen
    // under the new account.
    _plans = const [];
    _loaded = false;
    notifyListeners();
    await load();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(_scopeUserId), jsonEncode(_plans.map((p) => p.toJson()).toList()));
  }

  /// Gets a ticket for a new evening — adds it alongside whatever's
  /// already planned rather than replacing it (see the model's own
  /// docstring: several evenings can be queued up at once).
  Future<void> planEvening(PlannedEvening evening) async {
    _plans = [..._plans, evening];
    notifyListeners();
    await _persist();
  }

  /// Lets go of one planned evening — used both for an explicit
  /// "cancel" and for quietly clearing a past evening once it's been
  /// dealt with (marked watched, or just waved off). [id] targets the
  /// specific ticket; the rest of the plans are untouched.
  Future<void> clear(String id) async {
    if (!_plans.any((p) => p.id == id)) return;
    _plans = _plans.where((p) => p.id != id).toList();
    notifyListeners();
    await _persist();
  }

  /// Lets go of every planned evening at once.
  Future<void> clearAll() async {
    if (_plans.isEmpty) return;
    _plans = const [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(_scopeUserId));
  }
}
