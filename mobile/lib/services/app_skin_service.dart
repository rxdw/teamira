import 'package:flutter/material.dart';

import '../theme/seenly_skin.dart';
import 'persisted_pref.dart';
import '../analytics/analytics.dart';

/// Settings > appearance > "visual style": standard, the cozy pastel
/// diary skin, or the claymorphism ("clay") skin. A separate axis from
/// [ThemePrefsService] (light/dark/system) on purpose — this picks the
/// *decoration* (paper, tape, scalloped cards vs. puffy pastel clay
/// cards, the warmer palette), brightness still picks how light or dark
/// that decoration renders, so all combinations (e.g. clay light, clay
/// dark) are valid.
/// Also unrelated to `LogThemeService` (services/log_theme_service.dart),
/// which only re-skins the logging ritual itself.
///
/// Same device-only SharedPreferences pattern as `ThemePrefsService`:
/// keeps [SeenlySkin] in sync with the chosen skin — that's the flag
/// [SeenlyPalette]'s colors actually read — always updating it before
/// [notifyListeners] so dependents rebuild against the right palette.
class AppSkinService extends ChangeNotifier {
  final _skin = PersistedPref<AppSkin>(
    'seenly_app_skin',
    defaultValue: AppSkin.classic,
    read: (prefs, key) => switch (prefs.getString(key)) {
      'cozy' => AppSkin.cozy,
      'clay' => AppSkin.clay,
      _ => AppSkin.classic,
    },
    write: (prefs, key, value) => prefs.setString(key, switch (value) {
      AppSkin.cozy => 'cozy',
      AppSkin.clay => 'clay',
      AppSkin.classic => 'classic',
    }),
  );

  AppSkin get skin => _skin.value;

  Future<void> load() async {
    await _skin.load();
    SeenlySkin.setSkin(_skin.value);
    notifyListeners();
  }

  Future<void> setSkin(AppSkin skin) async {
    if (_skin.value == skin) return;
    SeenlySkin.setSkin(skin);
    await _skin.save(skin, onChanged: notifyListeners);
    Analytics.instance.track('setting_changed', {'setting': 'skin', 'value': skin.name});
  }
}
