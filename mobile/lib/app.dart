import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'analytics/analytics_route_observer.dart';
import 'l10n/app_localizations.dart';
import 'navigation.dart' show rootNavigatorKey;
import 'repositories/diary_repository.dart';
import 'repositories/watchlist_repository.dart';
import 'services/local_json_cache.dart';
import 'state/diary_store.dart';
import 'widgets/app_video_background.dart';
import 'state/watchlist_store.dart';
import 'screens/legal/eula_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/greeting_splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/shell/root_shell.dart';
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
import 'state/app_state.dart';
import 'theme/app_scroll_behavior.dart';
import 'theme/app_theme.dart';
import 'theme/palette.dart';
import 'theme/text_styles.dart';
import 'services/app_translations.dart';

/// Shared across the app so any screen can subscribe as a [RouteAware]
/// and find out when a route pushed on top of it gets popped back —
/// most importantly, RootShell's own tab screens (Home/Diary/
/// Collections/Profile), which IndexedStack keeps alive forever rather
/// than recreating on every tab switch. Without this, a screen that
/// caches its data in a `Future` set once in `initState` (Profile's
/// watched/plan-to-watch/watching-now shelves, say) never finds out
/// that a title screen pushed on top of it just changed that data —
/// only a hot restart, which throws the whole cache away, would show
/// it. Subscribing to this and refetching in `didPopNext` fixes that
/// without changing how any of those screens load their data in the
/// first place.
///
/// Typed on [ModalRoute] rather than the narrower [PageRoute]:
/// `RouteObserver<R>.didPop` only notifies subscribers when *both* the
/// popped route and the one revealed underneath it are of type `R`, and
/// the series/episode logging flow (showSeriesEpisodesSheet — the one
/// reachable straight from Profile's own "watched" shelf, and from
/// Diary) opens over a `showGeneralDialog` (`RawDialogRoute`), which is
/// a `ModalRoute` but not a `PageRoute`. With `R = PageRoute`, popping
/// back out through that dialog silently breaks the didPopNext chain —
/// Profile never hears about the change, same "only a hot restart shows
/// it" symptom the paragraph above describes, just via a different
/// route type. `ModalRoute` is the common ancestor of `PageRoute`
/// (regular pushes) *and* dialog/bottom-sheet routes, so subscribing at
/// that level keeps didPopNext firing all the way through mixed
/// page+dialog navigation stacks.
final routeObserver = RouteObserver<ModalRoute<void>>();

/// Reports a `screen_view` for every pushed route (see
/// lib/analytics/analytics_route_observer.dart). A single shared instance,
/// like [routeObserver] above: it remembers what each route turned out to
/// be so popping back to it can be reported, and a new instance per build
/// of [SeenlyApp] would forget that.
final analyticsRouteObserver = AnalyticsRouteObserver();

class SeenlyApp extends StatelessWidget {
  const SeenlyApp({
    super.key,
    required this.localeService,
    required this.logThemeService,
    required this.ritualPrefsService,
    required this.autoTrackingPrefsService,
    required this.mapStyleService,
    required this.coViewPrefsService,
    required this.eveningPlanService,
    required this.sourcesDisplayPrefsService,
    required this.spoilerPrefsService,
    required this.themePrefsService,
    required this.todayPickPrefsService,
    required this.onThisDayPrefsService,
    required this.savedPeriodsService,
    required this.premiumService,
    required this.appSkinService,
    required this.homeWidgetService,
  });

  // Every one of these is already loaded (its own SharedPreferences read
  // finished) before runApp — see main.dart's own comment. Used to be
  // `ChangeNotifierProvider(create: (_) => XService()..load())` per
  // service below: built with its default value, then a second
  // `notifyListeners()` a beat later once the async read actually
  // resolved. That's an invisible-in-testing, real-in-practice bit of
  // state inconsistency — a screen's very first frame(s) show the
  // default (system theme, spoilers unblurred, ritual not skipped...)
  // and then jump to whatever was actually saved, easy to mistake for a
  // glitch ("my setting didn't stick") rather than what it is (a timing
  // gap). SharedPreferences reads are fast and entirely on-device, so
  // main() now awaits all of them up front instead — costs a handful of
  // milliseconds before the first frame, not a visible extra splash,
  // and removes the jump entirely. AppState (auth/session — the one
  // provider below still built with `create: (_) => AppState()
  // ..bootstrap()`) is deliberately NOT part of this: bootstrap() makes
  // a real network call, and blocking runApp on that would trade one
  // glitch for a much worse one (nothing rendering at all until the
  // network answers) — it already has its own loading state
  // (_SplashScreen, see _AuthGate below) for exactly that reason.
  final LocaleService localeService;
  final LogThemeService logThemeService;
  final RitualPrefsService ritualPrefsService;
  final AutoTrackingPrefsService autoTrackingPrefsService;
  final MapStyleService mapStyleService;
  final CoViewPrefsService coViewPrefsService;
  final EveningPlanService eveningPlanService;
  final SourcesDisplayPrefsService sourcesDisplayPrefsService;
  final SpoilerPrefsService spoilerPrefsService;
  final ThemePrefsService themePrefsService;
  final TodayPickPrefsService todayPickPrefsService;
  final OnThisDayPrefsService onThisDayPrefsService;
  final SavedPeriodsService savedPeriodsService;
  final PremiumService premiumService;
  final AppSkinService appSkinService;
  final HomeWidgetService homeWidgetService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..bootstrap()),
        // Shared, cache-backed diary/watchlist state — see Фаза 2.15 in
        // the launch plan. Built from AppState's own services (context
        // can `read` anything earlier in this list), so there's exactly
        // one DiaryService/ProfileService instance underneath either
        // way. Deliberately NOT chained with `..bootstrap()`/`..load()`
        // like the note above explains for AppState — the very first
        // screen that actually needs this data calls `ensureLoaded()`
        // itself (see diary_screen.dart, profile_screen.dart), same as
        // every screen already did before these existed. That also
        // means a signed-out session never fires a doomed-to-401
        // network call just because the provider tree was built.
        ChangeNotifierProvider(
          create: (context) => DiaryStore(
            DiaryRepository(context.read<AppState>().diary, LocalJsonCache()),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => WatchlistStore(
            WatchlistRepository(context.read<AppState>().profile, LocalJsonCache()),
          ),
        ),
        // Whether logging shows tickets or coach boarding passes — a look,
        // not account data, so it loads from this device independently
        // of auth/bootstrap above.
        ChangeNotifierProvider.value(value: logThemeService),
        // Whether titles/descriptions prefer Russian (when TMDB has a
        // translation) — loaded in main() before runApp.
        ChangeNotifierProvider.value(value: localeService),
        // Whether the seat/venue/ticket-tear ritual is skipped in favor
        // of an instant log — same device-only loading, independent of
        // auth. See WatchingChoiceScreen's quick-log banner and the
        // "skip the ritual" toggle in settings.
        ChangeNotifierProvider.value(value: ritualPrefsService),
        // Whether the Home "auto-tracking" teaser card has been dismissed
        // — same device-only loading, independent of auth. See
        // home_screen.dart's _AutoTrackingBanner and IntegrationsScreen.
        ChangeNotifierProvider.value(value: autoTrackingPrefsService),
        // Which tile skin the route map (JourneyRealMap) draws — same
        // device-only loading, independent of auth. See the picker atop
        // the fullscreen route map and the "map style" row in Settings.
        ChangeNotifierProvider.value(value: mapStyleService),
        // Whether a Watch Together match also gets added to *your own*
        // personal "watch together" list (the shared co-viewing screen
        // always gets it regardless) — same device-only loading,
        // independent of auth. See together_screen.dart and the
        // "co-viewing" row in Settings.
        ChangeNotifierProvider.value(value: coViewPrefsService),
        // The single planned-ahead evening ("get a ticket") someone might
        // be holding — device-local, same loading pattern as the prefs
        // services above. Read from Home, Profile, and CoViewingScreen
        // (see widgets/evening_plan_card.dart) so getting a ticket on one
        // updates the reminder on the other two immediately.
        ChangeNotifierProvider.value(value: eveningPlanService),
        // Whether "your sources" (YouTube/Twitch) should also appear in
        // the main watched/watching/plan-to-watch shelves on Profile —
        // same device-only loading, independent of auth. See the
        // ProfileScreen._load merge and the toggle in Settings.
        ChangeNotifierProvider.value(value: sourcesDisplayPrefsService),
        // Whether a title's synopsis and whether written reviews get a
        // soft blurred veil until tapped — same device-only loading,
        // independent of auth. See widgets/spoiler_veil.dart and the
        // "spoilers" row in Settings.
        ChangeNotifierProvider.value(value: spoilerPrefsService),
        // System / light / dark. Device-only, same loading pattern as
        // everything else above. Drives SeenlyPalette's real dark
        // ("evening lamp") colors app-wide — see theme/palette.dart and
        // theme/seenly_brightness.dart.
        ChangeNotifierProvider.value(value: themePrefsService),
        // Home's "today's pick" card: whether it's on at all (Settings)
        // and which day's pick has already been dismissed — same
        // device-only loading, independent of auth. See
        // widgets/today_pick_card.dart and the "today's pick" row in
        // Settings.
        ChangeNotifierProvider.value(value: todayPickPrefsService),
        // Home's "on this day" section: which calendar day it's already
        // been closed for — account-scoped the same way as
        // TodayPickPrefsService above, since the entries it surfaces
        // come from one account's own diary. See home_screen.dart's
        // _OnThisDaySection and services/on_this_day_prefs_service.dart.
        ChangeNotifierProvider.value(value: onThisDayPrefsService),
        // "Свой период" wrapped periods the person has named and saved
        // — account-scoped the same way as OnThisDayPrefsService above,
        // since these are built from one account's own diary. See
        // services/saved_periods_service.dart and
        // screens/premium/saved_periods_screen.dart.
        ChangeNotifierProvider.value(value: savedPeriodsService),
        // Premium subscription state — same device-only loading as
        // everything above (see services/premium_service.dart's own
        // docstring for how it also now syncs against the account's
        // server-side state once signed in). Independent of auth since
        // it's read from Settings, Profile, and every free-tier upsell
        // sheet before/without navigating anywhere account-specific.
        ChangeNotifierProvider.value(value: premiumService),
        // Standard vs the cozy pastel diary skin — a separate axis from
        // ThemePrefsService above (that one is brightness, this one is
        // decoration; see the "visual style" row in Settings, right
        // under "appearance"). Same device-only loading as everything
        // above. Drives SeenlyPalette's cozy color sets app-wide — see
        // theme/palette.dart and theme/seenly_skin.dart.
        ChangeNotifierProvider.value(value: appSkinService),
        // Premium home-widget data pusher — not a ChangeNotifier (see
        // its own doc comment: write-only, nothing reads its state
        // back), so a plain Provider rather than ChangeNotifierProvider.
        Provider<HomeWidgetService>.value(value: homeWidgetService),
      ],
      // Video backdrop on/off rebuilds the app so the palette's video
      // text tones (SeenlyPalette._forVideo) apply — see
      // SeenlyBrightness.setVideoBackdrop. It does not change the theme.
      child: ValueListenableBuilder<bool>(
        valueListenable: AppBackgroundVideo.instance.enabled,
        builder: (context, videoOn, _) => Consumer3<ThemePrefsService, AppSkinService, LocaleService>(
        builder: (context, themePrefs, skinPrefs, localeSvc, _) => MaterialApp(
          // Most of the app reads its colors from SeenlyPalette's static
          // getters rather than through Theme.of(context) (see
          // theme/palette.dart), so a screen that's already on the
          // Navigator stack won't spontaneously repaint itself just
          // because ThemePrefsService or AppSkinService changed —
          // nothing told it to rebuild. Keying the whole app on all
          // three (theme, skin, and now interface language) forces
          // Flutter to tear down and rebuild everything below here
          // fresh whenever any of them change, so every screen picks up
          // the new palette — or the new language — immediately.
          //
          // The language toggle used to be the odd one out here: it
          // only reached already-open screens on their next natural
          // rebuild (see LocaleService.appIsRussian's own docstring on
          // that older behavior). Including it in this key now makes
          // "russian interface" behave exactly like "appearance" and
          // "visual style" already did — a small, deliberate consistency
          // fix that came out of wiring `locale:` below, which needs
          // MaterialApp to actually rebuild for
          // AppLocalizations.of(context) to hand new screens the right
          // language immediately rather than eventually.
          //
          // The cost is the same one already accepted for theme/skin:
          // toggling drops back to the home route rather than staying
          // put mid-navigation. Acceptable for a settings-screen toggle.
          //
          // Keyed on `appearance` rather than `mode` deliberately: the
          // two premium flavors both resolve to ThemeMode.light (see
          // ThemePrefsService/AppAppearance), so switching between them
          // wouldn't change `mode` at all — the wider 5-value enum is
          // what actually distinguishes "light" from "апельсиновая"
          // from "клубничная".
          key: ValueKey((themePrefs.appearance, skinPrefs.skin, localeSvc.preferRussian, videoOn)),
          title: 'tanè',
          debugShowCheckedModeBanner: false,
          theme: SeenlyAppTheme.light,
          darkTheme: SeenlyAppTheme.dark,
          themeMode: themePrefs.mode,
          // Explicit, driven by the in-app "russian interface" toggle —
          // deliberately NOT the device's system locale. Someone whose
          // phone is set to English but who wants a Russian interface
          // (or the reverse) gets what the toggle says, not what iOS/
          // Android guesses; that's the whole point of this being a
          // setting rather than automatic. This is also now the single
          // place that decides the app's language — AppLocalizations.of
          // (context) downstream and TrString.tr (app_translations.dart)
          // both ultimately answer to the same LocaleService preference,
          // just through two different call-site conventions (typed
          // getters for new code, `.tr` for the ~1800 existing call
          // sites — see app_translations.dart's own docstring).
          locale: Locale(localeSvc.preferRussian ? 'ru' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ru')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // One scroll feel everywhere — soft bounce on every platform,
          // no Android edge-glow — instead of each shelf inheriting
          // whatever the OS default happens to be. See app_scroll_behavior.dart.
          scrollBehavior: const SeenlyScrollBehavior(),
          navigatorKey: rootNavigatorKey,
          navigatorObservers: [routeObserver, analyticsRouteObserver],
          builder: (context, child) => child ?? const SizedBox.shrink(),
          home: const _AccountScopedPrefsScope(child: _AuthGate()),
        ),
        ),
      ),
    );
  }
}

/// Keeps account-scoped local state in sync with whoever's actually
/// signed in — currently [EveningPlanService] (a held ticket),
/// [TodayPickPrefsService]'s dismiss/accepted/reroll state (today's
/// pick already closed/accepted), [OnThisDayPrefsService]'s dismiss
/// state (which day the "on this day" section was closed for),
/// [SavedPeriodsService]'s saved "свой период" wrapped periods, and
/// [PremiumService]'s sync against the account's server-side
/// subscription state — see each service's own docstring for why that
/// state has to be scoped per account rather than shared device-wide,
/// unlike the plain device/UI preferences loaded above.
/// Watches only `AppState.currentUser?.id` (not the whole user object,
/// so an avatar or display-name edit doesn't re-trigger this), and
/// calls each service's own `reloadForUser` whenever that id actually
/// changes: on first resolving who's signed in, on logging into a
/// different account, and on signing out.
class _AccountScopedPrefsScope extends StatefulWidget {
  final Widget child;
  const _AccountScopedPrefsScope({required this.child});

  @override
  State<_AccountScopedPrefsScope> createState() => _AccountScopedPrefsScopeState();
}

class _AccountScopedPrefsScopeState extends State<_AccountScopedPrefsScope> {
  // Not-yet-observed sentinel, distinct from "signed out" (which is a
  // real null userId) — so the very first build, before AppState's own
  // bootstrap has resolved anything, doesn't get skipped as "unchanged".
  Object? _lastUserId = _unset;
  static const _unset = Object();

  @override
  Widget build(BuildContext context) {
    final userId = context.select<AppState, String?>((s) => s.currentUser?.id);
    if (userId != _lastUserId) {
      _lastUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<EveningPlanService>().reloadForUser(userId);
        context.read<TodayPickPrefsService>().reloadForUser(userId);
        context.read<OnThisDayPrefsService>().reloadForUser(userId);
        context.read<SavedPeriodsService>().reloadForUser(userId);
        context.read<PremiumService>().reloadForUser(userId);
      });
    }
    return widget.child;
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String stateKey;
    Widget child;
    switch (appState.status) {
      case AuthStatus.unknown:
        stateKey = 'splash';
        child = const _SplashScreen();
        break;
      case AuthStatus.signedOut:
        stateKey = 'login';
        child = const ScreenViewTracker(name: 'LoginScreen', child: LoginScreen());
        break;
      case AuthStatus.signedIn:
        // Accounts that predate the terms, or that accepted an older
        // version, see them before anything else. App Store guideline
        // 1.2 wants an agreement acknowledging there's no tolerance for
        // objectionable content, and an agreement nobody ever saw isn't
        // one. New accounts never land here — registration records
        // acceptance server-side (routers/auth.py::register) — so in
        // practice this is a one-time screen for existing installs.
        //
        // Placed inside the gate rather than pushed as a route on top of
        // Home on purpose: a route can be dismissed by a back gesture,
        // and this is the one screen in the app that must not be.
        if (appState.currentUser?.eulaCurrent == false) {
          stateKey = 'eula';
          child = ScreenViewTracker(
            name: 'EulaScreen',
            child: EulaScreen(
              requireAcceptance: true,
              onAccepted: appState.markEulaAccepted,
            ),
          );
        } else if (appState.justRegistered) {
          stateKey = 'onboarding';
          child = ScreenViewTracker(
            name: 'OnboardingScreen',
            child: OnboardingScreen(onFinished: appState.finishOnboarding),
          );
        } else {
          stateKey = 'home';
          child = const _GreetingGate();
        }
        break;
    }
    // Without this, swapping one of these four screens for another was a
    // hard cut — same frame, entirely different widget tree. The one
    // hand-off that actually matters, onboarding finishing into the real
    // app, already floods the screen with warm light on its own side
    // right before this swap happens (see OnboardingScreen's _finale) —
    // this cross-fade is what picks that up on the other end, so Home
    // eases in through the same light rather than just appearing once
    // the flood clears. Applied to every pair here, not only that one,
    // so the whole gate feels like one consistent surface instead of
    // onboarding being the only hand-off that got special treatment.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (widgetChild, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(animation),
          child: widgetChild,
        ),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}

/// Holds which tab to land on once the greeting splash is dismissed —
/// null while it's still showing. Lives above [RootShell] rather than
/// inside it so the splash only ever appears once per cold launch: this
/// widget (and its state) is only ever built fresh when `_AuthGate`
/// itself first reaches [AuthStatus.signedIn], not on every app resume.
class _GreetingGate extends StatefulWidget {
  const _GreetingGate();

  @override
  State<_GreetingGate> createState() => _GreetingGateState();
}

class _GreetingGateState extends State<_GreetingGate> {
  int? _initialTab;

  @override
  Widget build(BuildContext context) {
    final tab = _initialTab;
    if (tab == null) {
      return ScreenViewTracker(
        name: 'GreetingSplashScreen',
        child: GreetingSplashScreen(onEnter: (t) => setState(() => _initialTab = t)),
      );
    }
    return RootShell(initialIndex: tab);
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nights_stay_outlined,
                size: 30, color: SeenlyPalette.accent),
            const SizedBox(height: 10),
            Text('tanè'.tr, style: SeenlyText.serif(size: 22, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
