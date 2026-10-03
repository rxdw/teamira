import 'package:flutter/material.dart';

import '../theme/seenly_brightness.dart';
import '../theme/seenly_flavor.dart';
import 'persisted_pref.dart';
import '../analytics/analytics.dart';

/// Settings > "appearance": follow the system, force light/dark, or —
/// premium — one of the flavor moods ("апельсиновая"/"клубничная").
///
/// Brightness and flavor are two different ambient flags under the hood
/// ([SeenlyBrightness]/[SeenlyFlavor], each feeding [SeenlyPalette]
/// separately — see palette.dart), but they're deliberately ONE choice
/// here rather than a second settings row: a flavor is a fixed, always-
/// light mood (see seenly_flavor.dart for why), so "which flavor" and
/// "how bright" aren't actually independent questions the way skin
/// (classic/cozy, [AppSkinService]) and brightness are — a person picks
/// one appearance, not an appearance-brightness-flavor cross product.
/// [AppAppearance] is that single choice; [themeMode]/[flavor] below are
/// what it resolves to for the two ambient flags.
enum AppAppearance { system, light, dark, orange, strawberry }

extension AppAppearanceResolution on AppAppearance {
  /// What `MaterialApp.themeMode` should be for this appearance. Orange
  /// and strawberry both force light — see [AppFlavor]'s doc comment on
  /// why a flavor never has its own dark variant.
  ThemeMode get themeMode => switch (this) {
        AppAppearance.system => ThemeMode.system,
        AppAppearance.light => ThemeMode.light,
        AppAppearance.dark => ThemeMode.dark,
        AppAppearance.orange => ThemeMode.light,
        AppAppearance.strawberry => ThemeMode.light,
      };

  /// What [SeenlyFlavor] should hold for this appearance —
  /// [AppFlavor.none] for the three plain brightness choices.
  AppFlavor get flavor => switch (this) {
        AppAppearance.orange => AppFlavor.orange,
        AppAppearance.strawberry => AppFlavor.strawberry,
        AppAppearance.system || AppAppearance.light || AppAppearance.dark => AppFlavor.none,
      };

  bool get isFlavor => flavor != AppFlavor.none;
}

/// Same device-only SharedPreferences pattern as the other small
/// look/feel toggles (see [RitualPrefsService]).
///
/// Keeps [SeenlyBrightness] and [SeenlyFlavor] in sync with the chosen
/// appearance — those are the two flags [SeenlyPalette]'s colors
/// actually read, since most of the app reads them as bare static
/// getters rather than through `Theme.of(context)`. Always update both
/// before calling [notifyListeners] so that by the time dependents
/// rebuild, the palette is already resolving to the right one.
class ThemePrefsService extends ChangeNotifier {
  final _appearance = PersistedPref<AppAppearance>(
    'seenly_theme_mode',
    defaultValue: AppAppearance.system,
    read: (prefs, key) => switch (prefs.getString(key)) {
      'light' => AppAppearance.light,
      'dark' => AppAppearance.dark,
      'orange' => AppAppearance.orange,
      'strawberry' => AppAppearance.strawberry,
      _ => AppAppearance.system,
    },
    write: (prefs, key, value) => prefs.setString(key, switch (value) {
      AppAppearance.light => 'light',
      AppAppearance.dark => 'dark',
      AppAppearance.system => 'system',
      AppAppearance.orange => 'orange',
      AppAppearance.strawberry => 'strawberry',
    }),
  );

  AppAppearance get appearance => _appearance.value;

  /// Derived — kept so call sites that only ever cared about
  /// brightness (app.dart's `themeMode:`) don't need to know
  /// [AppAppearance] exists at all.
  ThemeMode get mode => _appearance.value.themeMode;

  Future<void> load() async {
    await _appearance.load();
    SeenlyBrightness.setMode(_appearance.value.themeMode);
    SeenlyFlavor.setFlavor(_appearance.value.flavor);
    notifyListeners();
  }

  Future<void> setAppearance(AppAppearance value) async {
    if (_appearance.value == value) return;
    SeenlyBrightness.setMode(value.themeMode);
    SeenlyFlavor.setFlavor(value.flavor);
    await _appearance.save(value, onChanged: notifyListeners);
    Analytics.instance.track('setting_changed', {'setting': 'theme_mode', 'value': value.name});
  }
}
