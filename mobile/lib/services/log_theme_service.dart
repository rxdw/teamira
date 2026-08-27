import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which set of visuals dresses the logging ritual, the diary
/// centerpiece, and the "log another evening" button — a little
/// private cinema with tickets, an evening coach route with a
/// boarding pass, a window-box garden that fills in with flowers, or
/// a shuttle cleared for launch into orbit.
/// Purely a look: the same diary entries either way, nothing about
/// what's saved changes with this.
enum LogTheme { ticket, coach, garden, shuttle }

/// Remembers which [LogTheme] this device is set to — same
/// device-only-preference pattern as `CollectionsPrefsService`: plain
/// [SharedPreferences], no backend endpoint, since this is a display
/// choice rather than account data.
class LogThemeService extends ChangeNotifier {
  static const _key = 'seenly_log_theme';

  LogTheme _theme = LogTheme.ticket;
  LogTheme get theme => _theme;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    _theme = switch (stored) {
      'coach' => LogTheme.coach,
      'garden' => LogTheme.garden,
      'shuttle' => LogTheme.shuttle,
      _ => LogTheme.ticket,
    };
    notifyListeners();
  }

  Future<void> setTheme(LogTheme value) async {
    if (_theme == value) return;
    _theme = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final stored = switch (value) {
      LogTheme.coach => 'coach',
      LogTheme.ticket => 'ticket',
      LogTheme.garden => 'garden',
      LogTheme.shuttle => 'shuttle',
    };
    await prefs.setString(_key, stored);
  }
}
