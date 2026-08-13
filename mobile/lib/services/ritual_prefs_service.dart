import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets someone skip the whole logging ritual — seat/venue picks,
/// journey/coach/garden animations, the ticket tear — and just log an
/// evening (or an episode) instantly instead. Same device-only
/// SharedPreferences pattern as [LogThemeService].
///
/// Two separate flags on purpose: dismissing the inline banner (see
/// WatchingChoiceScreen's `_QuickLogBanner`) only hides that banner —
/// it doesn't quietly change behavior. Actually skipping the ritual for
/// good is a deliberate choice made once, in Settings.
class RitualPrefsService extends ChangeNotifier {
  static const _skipKey = 'seenly_skip_ritual';
  static const _bannerKey = 'seenly_ritual_banner_dismissed';

  bool _skipRitual = false;
  bool _bannerDismissed = false;
  bool get skipRitual => _skipRitual;
  bool get bannerDismissed => _bannerDismissed;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _skipRitual = prefs.getBool(_skipKey) ?? false;
    _bannerDismissed = prefs.getBool(_bannerKey) ?? false;
    notifyListeners();
  }

  Future<void> setSkipRitual(bool value) async {
    if (_skipRitual == value) return;
    _skipRitual = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skipKey, value);
  }

  Future<void> dismissBanner() async {
    if (_bannerDismissed) return;
    _bannerDismissed = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bannerKey, true);
  }
}
