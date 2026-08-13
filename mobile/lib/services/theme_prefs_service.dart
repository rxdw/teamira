import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings > "appearance": follow the system, or force light/dark.
///
/// Same device-only SharedPreferences pattern as the other small
/// look/feel toggles (see [RabbitMascotPrefsService], [RitualPrefsService]).
///
/// For now [SeenlyAppTheme.dark] mirrors [SeenlyAppTheme.light] color for
/// color — the only thing that actually changes when dark mode is active
/// is which rabbit mascot artwork gets drawn (see widgets/rabbit_mascot.dart).
/// The rest of the app's real dark palette is coming later; this just
/// wires up the on/off switch and persistence ahead of that.
class ThemePrefsService extends ChangeNotifier {
  static const _modeKey = 'seenly_theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_modeKey);
    _mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}
