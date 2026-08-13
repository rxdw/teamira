import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the "auto-tracking" teaser card on Home has been dismissed —
/// tapping the card's × hides it for good on this device. Same device-only
/// SharedPreferences pattern as [RitualPrefsService]'s own banner flag.
///
/// This only controls the Home teaser. Auto-tracking itself (Plex/
/// Jellyfin/Kodi/browser-extension) has no on/off switch here — someone
/// either has it wired up in Settings > auto-tracking or they don't;
/// dismissing this card just stops reminding them it exists.
class AutoTrackingPrefsService extends ChangeNotifier {
  static const _bannerKey = 'seenly_autotracking_home_banner_dismissed';

  bool _bannerDismissed = false;
  bool get bannerDismissed => _bannerDismissed;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _bannerDismissed = prefs.getBool(_bannerKey) ?? false;
    notifyListeners();
  }

  Future<void> dismissBanner() async {
    if (_bannerDismissed) return;
    _bannerDismissed = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bannerKey, true);
  }
}
