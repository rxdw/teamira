import 'package:flutter/foundation.dart';

import 'persisted_pref.dart';
import '../analytics/analytics.dart';

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
  final _theme = PersistedPref<LogTheme>(
    'seenly_log_theme',
    defaultValue: LogTheme.ticket,
    read: (prefs, key) => switch (prefs.getString(key)) {
      'coach' => LogTheme.coach,
      'garden' => LogTheme.garden,
      'shuttle' => LogTheme.shuttle,
      _ => LogTheme.ticket,
    },
    write: (prefs, key, value) => prefs.setString(key, switch (value) {
      LogTheme.coach => 'coach',
      LogTheme.ticket => 'ticket',
      LogTheme.garden => 'garden',
      LogTheme.shuttle => 'shuttle',
    }),
  );

  LogTheme get theme => _theme.value;

  Future<void> load() async {
    await _theme.load();
    notifyListeners();
  }

  Future<void> setTheme(LogTheme value) async {
    await _theme.save(value, onChanged: notifyListeners);
    Analytics.instance.track('setting_changed', {'setting': 'log_theme', 'value': value.name});
  }
}
