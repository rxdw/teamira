import 'package:flutter/foundation.dart';

import 'persisted_pref.dart';
import '../analytics/analytics.dart';

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
  final _preferRussian = PersistedPref.boolean('seenly_content_language');

  bool get preferRussian => _preferRussian.value;

  /// A static mirror of [preferRussian], read by LocalizedText.display
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

  /// The sentence for the current language, for copy that splices names or
  /// numbers into the middle of a phrase. `.tr` can't help there: it looks the
  /// finished string up whole, and a string with a username in it never
  /// matches anything. Write both versions out instead (word order and
  /// plural forms differ between the two languages anyway).
  static String pick(String ru, String en) => appIsRussian ? ru : en;

  Future<void> load() async {
    await _preferRussian.load();
    contentPrefersRussian = _preferRussian.value;
    await _region.load();
    notifyListeners();
  }

  Future<void> setPreferRussian(bool value) async {
    contentPrefersRussian = value;
    await _preferRussian.save(value, onChanged: notifyListeners);
    Analytics.instance.track('setting_changed', {'setting': 'content_language', 'value': value ? 'ru' : 'en'});
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
  final _region = PersistedPref.nullableString('seenly_watch_region');

  String? get region => _region.value;

  Future<void> setRegion(String? code) async {
    await _region.save(code, onChanged: notifyListeners);
  }
}
