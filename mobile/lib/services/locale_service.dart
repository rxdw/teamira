import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which language catalog content (titles, descriptions) prefers on this
/// device. A `ru` value only exists on a MediaItem when TMDB actually had
/// a translation for that specific title (see backend
/// app/adapters/tmdb.py::full_detail) — LocalizedText.display still falls
/// back to whichever language actually has content.
///
/// This same toggle now also drives the app's own UI copy (see
/// [appIsRussian] and services/app_translations.dart's `TrString.tr`),
/// so "prefer Russian wherever TMDB happened to have one" *and*
/// "translate the interface itself" are one single setting from the
/// person's point of view — "russian interface" in Settings.
///
/// Same device-only-preference pattern as LogThemeService: plain
/// SharedPreferences, no backend endpoint, since this is a display choice
/// rather than account data.
class LocaleService extends ChangeNotifier {
  static const _key = 'seenly_content_language';

  bool _preferRussian = false;
  bool get preferRussian => _preferRussian;

  /// A static mirror of [_preferRussian], read by LocalizedText.display
  /// (models/media_item.dart) without plumbing this service through every
  /// one of the ~11 screens that already call `.display` directly. The
  /// tradeoff: a screen already built before the toggle changes won't
  /// re-render mid-session just because this flipped — it'll pick up the
  /// new language next time it rebuilds (navigating back in, pull-to-
  /// refresh, or app restart), same as e.g. LogTheme does for already-open
  /// screens. Screens that watch `LocaleService` directly (this settings
  /// screen) still update instantly.
  static bool contentPrefersRussian = false;

  /// Same underlying preference as [contentPrefersRussian], read by
  /// `TrString.tr` (services/app_translations.dart) to decide whether
  /// hardcoded UI copy renders in Russian or English. Kept as a distinct
  /// named getter — rather than having every call site read
  /// [contentPrefersRussian] directly — so it's clear at each use site
  /// *why* it's being read (interface language, not just title language),
  /// even though today they're the same single toggle.
  static bool get appIsRussian => contentPrefersRussian;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _preferRussian = prefs.getBool(_key) ?? false;
    contentPrefersRussian = _preferRussian;
    _region = prefs.getString(_regionKey);
    notifyListeners();
  }

  Future<void> setPreferRussian(bool value) async {
    if (_preferRussian == value) return;
    _preferRussian = value;
    contentPrefersRussian = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  // ---------------------------------------------------------------------
  // Watch-provider region — which country's streaming availability shows
  // in "where to watch" (title_detail_screen.dart's _WhereToWatchSection).
  // Separate from [preferRussian] above: that's about which language a
  // title's own name/synopsis show in, this is about which country's
  // Kinopoisk/Netflix/etc. listings TMDB returns. `null` means "auto" —
  // guess from the device's own locale (see title_detail_screen.dart's
  // _watchRegion), same as before this existed. Set explicitly whenever
  // the device locale guess doesn't match where someone actually
  // streams from (e.g. an en-US phone but a Russian JustWatch catalog).
  static const _regionKey = 'seenly_watch_region';

  String? _region;
  String? get region => _region;

  Future<void> setRegion(String? code) async {
    if (_region == code) return;
    _region = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_regionKey);
    } else {
      await prefs.setString(_regionKey, code);
    }
  }
}
