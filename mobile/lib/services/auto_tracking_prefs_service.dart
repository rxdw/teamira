import 'package:flutter/foundation.dart';

import 'persisted_pref.dart';

/// Whether the "auto-tracking" teaser card on Home has been dismissed —
/// tapping the card's × hides it for good on this device. Same device-only
/// SharedPreferences pattern as [RitualPrefsService]'s own banner flag.
///
/// This only controls the Home teaser. Auto-tracking itself (Plex/
/// Jellyfin/Kodi/browser-extension) has no on/off switch here — someone
/// either has it wired up in Settings > auto-tracking or they don't;
/// dismissing this card just stops reminding them it exists.
class AutoTrackingPrefsService extends ChangeNotifier {
  final _bannerDismissed = PersistedPref.boolean('seenly_autotracking_home_banner_dismissed');

  bool get bannerDismissed => _bannerDismissed.value;

  Future<void> load() async {
    await _bannerDismissed.load();
    notifyListeners();
  }

  Future<void> dismissBanner() async {
    await _bannerDismissed.save(true, onChanged: notifyListeners);
  }
}
