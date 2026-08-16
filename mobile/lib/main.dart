import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/locale_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge: without this, Android reserves the status bar as its
  // own opaque strip instead of letting app content (e.g. the poster
  // collage behind Collections' full-screen header) draw underneath it,
  // which is what shows up as a bare cream sliver at the very top of
  // screens with a hero image header. Individual screens still control
  // their own icon color via AnnotatedRegion<SystemUiOverlayStyle>.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  // Awaited *before* runApp — unlike every other device-only prefs
  // service in app.dart (LogThemeService, RitualPrefsService, ...),
  // whose own screens read them through Provider/context.watch and so
  // just rebuild whenever `..load()` finishes in the background,
  // LocaleService.contentPrefersRussian is also read as a bare static
  // field by code that isn't listening for a rebuild at all — most
  // importantly, whatever a screen's own initState fires off as its
  // first API fetch (`lang: LocaleService.contentPrefersRussian ? 'ru'
  // : null` — see feed_service.dart). If that fetch goes out before
  // SharedPreferences has actually been read, it goes out in English,
  // gets cached in that screen's own state, and nothing ever tells it
  // to redo the fetch once the flag flips a moment later — only an
  // explicit Settings toggle (which re-fetches itself) fixes it, which
  // is exactly the "have to switch it off and on again" symptom this
  // avoids. Loading it here removes the race instead of chasing every
  // read site.
  final localeService = LocaleService();
  await localeService.load();
  runApp(SeenlyApp(localeService: localeService));
}
