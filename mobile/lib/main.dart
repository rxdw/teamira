import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'analytics/analytics.dart';
import 'app.dart';
import 'services/app_skin_service.dart';
import 'services/home_widget_service.dart';
import 'services/auto_tracking_prefs_service.dart';
import 'services/coview_prefs_service.dart';
import 'services/evening_plan_service.dart';
import 'services/locale_service.dart';
import 'services/log_theme_service.dart';
import 'services/map_style_service.dart';
import 'services/on_this_day_prefs_service.dart';
import 'services/premium_service.dart';
import 'services/ritual_prefs_service.dart';
import 'services/saved_periods_service.dart';
import 'services/sources_display_prefs_service.dart';
import 'services/spoiler_prefs_service.dart';
import 'services/theme_prefs_service.dart';
import 'services/today_pick_prefs_service.dart';

// Crash reporting — see pubspec.yaml's own comment on sentry_flutter for
// the "why Sentry, why unconditional" story; this is just the wiring.
// Both are compile-time constants, not read from backend/.env the way
// the server reads SENTRY_DSN — a release build has no .env file, so
// these come from --dart-define instead, e.g.:
//
//   flutter build ios --dart-define=SENTRY_DSN=https://...@.../... \
//                      --dart-define=SENTRY_ENVIRONMENT=production
//
// Left blank (the default for every local/debug run), SentryFlutter.init
// below is a documented no-op: nothing is sent anywhere, and appRunner
// still runs the app exactly as it would without this whole block.
const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const String _sentryEnvironment =
    String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: 'development');

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.environment = _sentryEnvironment;
      // Error capture happens regardless of this value — same split as
      // the backend's SENTRY_TRACES_SAMPLE_RATE, which also defaults to
      // 0.0 and only affects *performance* tracing, never error
      // reporting. Left at 0 here too until there's an actual reason to
      // pay for trace volume.
      options.tracesSampleRate = 0.0;
      // Diary entries, watch history, and co-viewing partners are
      // exactly the kind of personal detail that shouldn't ride along
      // on a crash report by default — this only ever affects what
      // Sentry's own native layer might otherwise attach (device
      // user/IP), not anything this app explicitly reports itself.
      options.sendDefaultPii = false;
    },
    appRunner: () => _runApp(),
  );
}

Future<void> _runApp() async {
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

  // Every device-only prefs service the app has, constructed up front
  // and awaited *before* runApp — previously only LocaleService got
  // this treatment (see the old comment here, kept in spirit below);
  // every other one was handed to app.dart as
  // `ChangeNotifierProvider(create: (_) => XService()..load())`, which
  // builds the service with its in-memory defaults, renders with that,
  // and only rebuilds once the async SharedPreferences read resolves a
  // beat later. That's not a crash, but it *is* real state
  // inconsistency: a toggle that's actually "on" can render "off" for
  // a frame or two and then flip, which reads exactly like a bug
  // report ("my setting didn't stick") rather than what it is — a
  // startup race nobody was waiting on.
  //
  // SharedPreferences reads are local-disk, not network, so awaiting
  // all of them together costs single-digit milliseconds before the
  // first frame — not a visible extra splash screen — and removes the
  // jump entirely. AppState (auth/session) deliberately stays out of
  // this list: its own bootstrap() call is a real network request, and
  // blocking runApp on that would trade a small, harmless jump for a
  // much worse one (a blank screen for however long the network takes)
  // — it already renders its own loading state (_SplashScreen, see
  // app.dart's _AuthGate) for exactly that reason, so it keeps using
  // `create: (_) => AppState()..bootstrap()` unchanged.
  final localeService = LocaleService();
  final logThemeService = LogThemeService();
  final ritualPrefsService = RitualPrefsService();
  final autoTrackingPrefsService = AutoTrackingPrefsService();
  final mapStyleService = MapStyleService();
  final coViewPrefsService = CoViewPrefsService();
  final eveningPlanService = EveningPlanService();
  final sourcesDisplayPrefsService = SourcesDisplayPrefsService();
  final spoilerPrefsService = SpoilerPrefsService();
  final themePrefsService = ThemePrefsService();
  final todayPickPrefsService = TodayPickPrefsService();
  final onThisDayPrefsService = OnThisDayPrefsService();
  final savedPeriodsService = SavedPeriodsService();
  final premiumService = PremiumService();
  final appSkinService = AppSkinService();
  final homeWidgetService = HomeWidgetService();

  await Future.wait([
    localeService.load(),
    logThemeService.load(),
    ritualPrefsService.load(),
    autoTrackingPrefsService.load(),
    mapStyleService.load(),
    coViewPrefsService.load(),
    eveningPlanService.load(),
    sourcesDisplayPrefsService.load(),
    spoilerPrefsService.load(),
    themePrefsService.load(),
    todayPickPrefsService.load(),
    onThisDayPrefsService.load(),
    savedPeriodsService.load(),
    premiumService.load(),
    appSkinService.load(),
    homeWidgetService.init(),
    // Product analytics (see lib/analytics/analytics.dart): reads the
    // opt-out flag, the per-install id and any events left over from the
    // last run. Local disk only — no network — so it's safe to await here.
    Analytics.instance.init(),
  ]);

  runApp(SeenlyApp(
    localeService: localeService,
    logThemeService: logThemeService,
    ritualPrefsService: ritualPrefsService,
    autoTrackingPrefsService: autoTrackingPrefsService,
    mapStyleService: mapStyleService,
    coViewPrefsService: coViewPrefsService,
    eveningPlanService: eveningPlanService,
    sourcesDisplayPrefsService: sourcesDisplayPrefsService,
    spoilerPrefsService: spoilerPrefsService,
    themePrefsService: themePrefsService,
    todayPickPrefsService: todayPickPrefsService,
    onThisDayPrefsService: onThisDayPrefsService,
    savedPeriodsService: savedPeriodsService,
    premiumService: premiumService,
    appSkinService: appSkinService,
    homeWidgetService: homeWidgetService,
  ));
}
