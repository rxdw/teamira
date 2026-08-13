import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/home/greeting_splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/shell/root_shell.dart';
import 'services/auto_tracking_prefs_service.dart';
import 'services/coview_prefs_service.dart';
import 'services/evening_plan_service.dart';
import 'services/locale_service.dart';
import 'services/log_theme_service.dart';
import 'services/map_style_service.dart';
import 'services/on_this_day_prefs_service.dart';
import 'services/rabbit_mascot_prefs_service.dart';
import 'services/ritual_prefs_service.dart';
import 'services/sources_display_prefs_service.dart';
import 'services/spoiler_prefs_service.dart';
import 'services/theme_prefs_service.dart';
import 'services/today_pick_prefs_service.dart';
import 'state/app_state.dart';
import 'theme/app_scroll_behavior.dart';
import 'theme/app_theme.dart';
import 'theme/palette.dart';
import 'theme/text_styles.dart';

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

class SeenlyApp extends StatelessWidget {
  const SeenlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..bootstrap()),
        // Whether logging shows tickets or coach boarding passes — a look,
        // not account data, so it loads from this device independently
        // of auth/bootstrap above.
        ChangeNotifierProvider(create: (_) => LogThemeService()..load()),
        // Whether titles/descriptions prefer Russian (when TMDB has a
        // translation) — same device-only loading, independent of auth.
        ChangeNotifierProvider(create: (_) => LocaleService()..load()),
        // Whether the seat/venue/ticket-tear ritual is skipped in favor
        // of an instant log — same device-only loading, independent of
        // auth. See WatchingChoiceScreen's quick-log banner and the
        // "skip the ritual" toggle in settings.
        ChangeNotifierProvider(create: (_) => RitualPrefsService()..load()),
        // Whether the Home "auto-tracking" teaser card has been dismissed
        // — same device-only loading, independent of auth. See
        // home_screen.dart's _AutoTrackingBanner and IntegrationsScreen.
        ChangeNotifierProvider(create: (_) => AutoTrackingPrefsService()..load()),
        // Which tile skin the route map (JourneyRealMap) draws — same
        // device-only loading, independent of auth. See the picker atop
        // the fullscreen route map and the "map style" row in Settings.
        ChangeNotifierProvider(create: (_) => MapStyleService()..load()),
        // Whether a Watch Together match also gets added to *your own*
        // personal "watch together" list (the shared co-viewing screen
        // always gets it regardless) — same device-only loading,
        // independent of auth. See together_screen.dart and the
        // "co-viewing" row in Settings.
        ChangeNotifierProvider(create: (_) => CoViewPrefsService()..load()),
        // The single planned-ahead evening ("get a ticket") someone might
        // be holding — device-local, same loading pattern as the prefs
        // services above. Read from Home, Profile, and CoViewingScreen
        // (see widgets/evening_plan_card.dart) so getting a ticket on one
        // updates the reminder on the other two immediately.
        ChangeNotifierProvider(create: (_) => EveningPlanService()..load()),
        // Whether "your sources" (YouTube/Twitch) should also appear in
        // the main watched/watching/plan-to-watch shelves on Profile —
        // same device-only loading, independent of auth. See the
        // ProfileScreen._load merge and the toggle in Settings.
        ChangeNotifierProvider(create: (_) => SourcesDisplayPrefsService()..load()),
        // Whether a title's synopsis and whether written reviews get a
        // soft blurred veil until tapped — same device-only loading,
        // independent of auth. See widgets/spoiler_veil.dart and the
        // "spoilers" row in Settings.
        ChangeNotifierProvider(create: (_) => SpoilerPrefsService()..load()),
        // Whether the rabbit mascot appears around the app (onboarding,
        // empty states, loading, achievements) — same device-only
        // loading, independent of auth, off by default. See
        // widgets/rabbit_mascot.dart and the "rabbit companion" row in
        // Settings.
        ChangeNotifierProvider(create: (_) => RabbitMascotPrefsService()..load()),
        // System / light / dark. Device-only, same loading pattern as
        // everything else above. Only the rabbit mascot actually reacts
        // to this today (see theme/app_theme.dart for why) — the rest
        // of the app's dark palette is coming later.
        ChangeNotifierProvider(create: (_) => ThemePrefsService()..load()),
        // Home's "today's pick" card: whether it's on at all (Settings)
        // and which day's pick has already been dismissed — same
        // device-only loading, independent of auth. See
        // widgets/today_pick_card.dart and the "today's pick" row in
        // Settings.
        ChangeNotifierProvider(create: (_) => TodayPickPrefsService()..load()),
        // Home's "on this day" section: which calendar day it's already
        // been closed for — account-scoped the same way as
        // TodayPickPrefsService above, since the entries it surfaces
        // come from one account's own diary. See home_screen.dart's
        // _OnThisDaySection and services/on_this_day_prefs_service.dart.
        ChangeNotifierProvider(create: (_) => OnThisDayPrefsService()..load()),
      ],
      child: Consumer<ThemePrefsService>(
        builder: (context, themePrefs, _) => MaterialApp(
          title: 'teamira',
          debugShowCheckedModeBanner: false,
          theme: SeenlyAppTheme.light,
          darkTheme: SeenlyAppTheme.dark,
          themeMode: themePrefs.mode,
          // One scroll feel everywhere — soft bounce on every platform,
          // no Android edge-glow — instead of each shelf inheriting
          // whatever the OS default happens to be. See app_scroll_behavior.dart.
          scrollBehavior: const SeenlyScrollBehavior(),
          navigatorObservers: [routeObserver],
          home: const _AccountScopedPrefsScope(child: _AuthGate()),
        ),
      ),
    );
  }
}

/// Keeps account-scoped local state in sync with whoever's actually
/// signed in — currently [EveningPlanService] (a held ticket),
/// [TodayPickPrefsService]'s dismiss/accepted/reroll state (today's
/// pick already closed/accepted), and [OnThisDayPrefsService]'s
/// dismiss state (which day the "on this day" section was closed
/// for) — see each service's own docstring for why that state has to
/// be scoped per account rather than shared device-wide, unlike the
/// plain device/UI preferences loaded above.
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
        child = const LoginScreen();
        break;
      case AuthStatus.signedIn:
        if (appState.justRegistered) {
          stateKey = 'onboarding';
          child = OnboardingScreen(onFinished: appState.finishOnboarding);
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
      return GreetingSplashScreen(onEnter: (t) => setState(() => _initialTab = t));
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
            const Icon(Icons.nights_stay_outlined,
                size: 30, color: SeenlyPalette.accent),
            const SizedBox(height: 10),
            Text('teamira', style: SeenlyText.serif(size: 22, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
