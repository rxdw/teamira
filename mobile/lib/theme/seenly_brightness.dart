import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Tracks which brightness [SeenlyPalette] should currently resolve to.
///
/// Most of the app reads colors as bare `SeenlyPalette.ink` /
/// `SeenlyPalette.accent` static getters rather than through
/// `Theme.of(context)` — including from places with no `BuildContext` at
/// all (`CustomPainter`s, default parameter resolution, static helpers).
/// That's why this is a plain static flag instead of an InheritedWidget:
/// it's the one piece of ambient state [SeenlyPalette]'s getters can
/// check without needing a context threaded everywhere.
///
/// Kept in sync with [ThemePrefsService] (see theme_prefs_service.dart) —
/// call [setMode] whenever that service's mode changes, before the
/// dependent tree rebuilds.
class SeenlyBrightness {
  SeenlyBrightness._();

  static ThemeMode _mode = ThemeMode.system;

  static void setMode(ThemeMode mode) {
    _mode = mode;
  }

  /// Whether [SeenlyPalette]'s ambient getters should currently hand back
  /// the dark variant.
  static bool get isDark {
    switch (_mode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return SchedulerBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }
}
