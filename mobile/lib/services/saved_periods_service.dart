import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_wrapped_period.dart';

/// Locally-saved "свой период" wrapped periods — a title and date range
/// the person named once and can revisit, rather than retyping it every
/// time (see CustomWrappedSetupScreen, which now only handles *creating*
/// a new one; SavedPeriodsScreen is the actual "свой период" landing
/// page). Entirely device-local, same reasoning as every other
/// `*_prefs_service.dart` in this app (see PremiumService's own
/// docstring) — there's no backend endpoint for a person's own named
/// periods any more than there was for the wrapped data itself (see
/// CustomWrappedService).
///
/// Account-scoped the same way as [OnThisDayPrefsService] — these
/// periods are built from one account's own diary, so signing into a
/// different account on the same device shouldn't show someone else's
/// saved periods. See app.dart's `_AccountScopedPrefsScope` for the
/// `reloadForUser` wiring.
class SavedPeriodsService extends ChangeNotifier {
  static const _key = 'seenly_saved_wrapped_periods';

  List<SavedWrappedPeriod> _periods = const [];
  String? _scopeUserId;
  bool _loaded = false;

  bool get loaded => _loaded;
  // Most recently saved first — a person's most recent trip or season
  // is the one they're most likely reaching for again.
  List<SavedWrappedPeriod> get periods => List.unmodifiable(_periods);

  String _keyFor(String? userId) => userId == null ? _key : '${_key}_$userId';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(_scopeUserId));
    _periods = _decode(raw);
    _loaded = true;
    notifyListeners();
  }

  /// Switches which account's saved periods this service is showing —
  /// see OnThisDayPrefsService.reloadForUser for the same shape. A
  /// no-op when [userId] is the account already loaded.
  Future<void> reloadForUser(String? userId) async {
    if (_loaded && _scopeUserId == userId) return;
    _scopeUserId = userId;
    _periods = const [];
    _loaded = false;
    notifyListeners();
    await load();
  }

  List<SavedWrappedPeriod> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      final parsed = list
          .map((e) => SavedWrappedPeriod.fromJson(e as Map<String, dynamic>))
          .toList();
      parsed.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return parsed;
    } catch (_) {
      // Malformed local data (a future app version changed the shape,
      // etc.) — better to show an empty list than crash the picker.
      return const [];
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyFor(_scopeUserId),
      jsonEncode(_periods.map((p) => p.toJson()).toList()),
    );
  }

  Future<SavedWrappedPeriod> add({required String title, required DateTimeRange range}) async {
    final period = SavedWrappedPeriod(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      start: range.start,
      end: range.end,
      savedAt: DateTime.now(),
    );
    _periods = [period, ..._periods];
    notifyListeners();
    await _persist();
    return period;
  }

  Future<void> remove(String id) async {
    _periods = _periods.where((p) => p.id != id).toList();
    notifyListeners();
    await _persist();
  }
}
