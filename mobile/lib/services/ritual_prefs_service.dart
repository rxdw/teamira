import 'package:flutter/foundation.dart';

import 'persisted_pref.dart';
import '../analytics/analytics.dart';

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
  final _skipRitual = PersistedPref.boolean('seenly_skip_ritual');
  final _bannerDismissed = PersistedPref.boolean('seenly_ritual_banner_dismissed');

  bool get skipRitual => _skipRitual.value;
  bool get bannerDismissed => _bannerDismissed.value;

  Future<void> load() async {
    await _skipRitual.load();
    await _bannerDismissed.load();
    notifyListeners();
  }

  Future<void> setSkipRitual(bool value) async {
    await _skipRitual.save(value, onChanged: notifyListeners);
    Analytics.instance.track('setting_changed', {'setting': 'skip_ritual', 'value': value});
  }

  Future<void> dismissBanner() async {
    await _bannerDismissed.save(true, onChanged: notifyListeners);
  }
}
