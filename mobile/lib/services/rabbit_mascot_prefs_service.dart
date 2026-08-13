import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings > "rabbit companion": whether the little rabbit mascot shows
/// up around the app (onboarding, empty states, loading, achievements,
/// profile, co-viewing) or stays hidden and every screen looks exactly
/// as it does without it.
///
/// On by default — same device-only SharedPreferences pattern as the
/// other small look/feel toggles (see [SpoilerPrefsService],
/// [RitualPrefsService]).
class RabbitMascotPrefsService extends ChangeNotifier {
  static const _enabledKey = 'seenly_rabbit_mascot_enabled';

  bool _enabled = true;
  bool get enabled => _enabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }
}
