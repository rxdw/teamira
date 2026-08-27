import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/seenly_brightness.dart';

/// Settings > "appearance": follow the system, or force light/dark.
///
/// Same device-only SharedPreferences pattern as the other small
/// look/feel toggles (see [RitualPrefsService]).
///
/// Keeps [SeenlyBrightness] in sync with the chosen mode — that's the
/// flag [SeenlyPalette]'s colors actually read, since most of the app
/// reads them as bare static getters rather than through
/// `Theme.of(context)`. Always update it before calling
/// [notifyListeners] so that by the time dependents rebuild, the palette
/// is already resolving to the right brightness.
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
    SeenlyBrightness.setMode(_mode);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    SeenlyBrightness.setMode(_mode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}
