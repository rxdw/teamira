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
    // The video backdrop no longer forces the dark palette: it used to,
    // which made every light theme (light, cozy, clay, orange,
    // strawberry) unselectable while the video, on by default, was
    // playing. The theme now follows the chosen mode, and the video is
    // scrimmed toward the palette's own background instead (see
    // AppVideoBackground, and SeenlyPalette._forVideo for the text tones).
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

  static bool _videoBackdrop = false;

  /// True while the looping video backdrop is playing behind the app.
  /// [SeenlyPalette] reads this to strengthen its secondary text tones —
  /// the footage has both bright patches (~90% luminance) and dark ones,
  /// so text sitting directly on it, with no card behind it, needs more
  /// contrast than the same tones have on a flat page.
  static bool get videoBackdrop => _videoBackdrop;

  /// Kept in sync by AppBackgroundVideo (widgets/app_video_background.dart)
  /// — call before anything that depends on the palette rebuilds.
  static void setVideoBackdrop(bool on) {
    _videoBackdrop = on;
  }
}
