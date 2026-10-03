import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/analytics.dart';
import '../../services/evening_plan_service.dart';
import '../../services/home_widget_service.dart';
import '../../services/premium_service.dart';
import '../../state/app_state.dart';
import '../../theme/clay_kit.dart';
import '../../theme/notebook_paper.dart';
import '../../theme/palette.dart';
import '../../theme/seenly_skin.dart';
import '../../widgets/active_journey_badge.dart';
import '../../widgets/app_video_background.dart';
import '../../widgets/seenly_bottom_nav.dart';
import '../../widgets/wow_motion.dart';
import '../collections/collections_screen.dart';
import '../diary/diary_screen.dart';
import '../title/title_detail_screen.dart';
import '../premium/premium_screen.dart';
import 'home_mode_shell.dart';
import '../profile/profile_screen.dart';

class RootShell extends StatefulWidget {
  // Which tab to land on — defaults to Home, but the greeting splash's
  // CTA/quick-jumps (see screens/home/greeting_splash_screen.dart) send
  // people straight into Diary/Collections/Profile instead.
  final int initialIndex;
  const RootShell({super.key, this.initialIndex = 0});

  /// Tab indices, so callers elsewhere don't have to hardcode magic
  /// numbers to know which one is Diary/Collections/Profile.
  static const homeTab = 0;
  static const diaryTab = 1;
  static const collectionsTab = 2;
  static const profileTab = 3;

  /// Switches to another RootShell tab from a screen living *inside*
  /// one of its tabs (Home, Profile, ...) — e.g. Home's "fresh in your
  /// diary — all" link, or Profile's "diary ›" link. Used instead of
  /// pushing a fresh screen (`Navigator.push(DiaryScreen())`) so the
  /// bottom nav bar and Scaffold stay exactly the ones RootShell
  /// already owns, rather than a second, nav-less screen stacking on
  /// top of it. No-ops if there's no RootShell above [context] (there
  /// always should be, for any tab screen).
  static void switchTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_RootShellState>()?._switchTab(index);
  }

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  late int _index = widget.initialIndex.clamp(0, _screens.length - 1).toInt();

  // Whichever AppState this State is currently subscribed to, purely so
  // [dispose] can remove the exact listener [didChangeDependencies]
  // added — Provider's own lookup isn't safe to repeat inside dispose()
  // (the widget tree above this one may already be gone by then).
  AppState? _appState;

  // Same idea for the premium service the trial-ending nudge listens to.
  PremiumService? _premium;
  bool _trialNudgeBusy = false;
  bool _winbackNudgeBusy = false;

  // What each tab is called in analytics — the same names the screen
  // registry (mobile/tools/analytics/list_screens.py) lists, since the tabs
  // are IndexedStack children and never go through the route observer.
  static const _tabScreenNames = [
    'HomeScreen',
    'DiaryScreen',
    'CollectionsScreen',
    'ProfileScreen',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Analytics.instance.setRootScreen(_tabScreenNames[_index], nav: 'tab');
    // Covers the case where AppState.pendingTitleLink was already set
    // by the time this widget's very first build happens — either a
    // pending link just applied by login()/register()/bootstrap()
    // right before _GreetingGateState built this, or (less commonly) a
    // live link that arrived in the gap between that and now. The
    // listener registered below in didChangeDependencies covers every
    // later arrival while this stays mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingTitleLink());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboardingPaywall());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPartnerLinkedPaywall());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTrialNudge());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWinbackNudge());
  }

  /// Coming back to the app is when "the free period ended while you
  /// were away" becomes true for the person, so re-read the account's
  /// premium state; the listener registered in [didChangeDependencies]
  /// then decides whether a nudge is due.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final userId = context.read<AppState>().currentUser?.id;
    context.read<PremiumService>().reloadForUser(userId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final premium = context.read<PremiumService>();
    if (_premium != premium) {
      _premium?.removeListener(_maybeShowTrialNudge);
      _premium?.removeListener(_maybeShowWinbackNudge);
      _premium = premium;
      premium.addListener(_maybeShowTrialNudge);
      premium.addListener(_maybeShowWinbackNudge);
    }
    final app = context.read<AppState>();
    if (_appState != app) {
      _appState?.removeListener(_openPendingTitleLink);
      _appState?.removeListener(_maybeShowPartnerLinkedPaywall);
      _appState = app;
      // AppState.notifyListeners() fires for plenty of things unrelated
      // to a title link (journeys, level, ...) — harmless here, since
      // consumePendingTitleLink() is a no-op returning null on every
      // one of those, same as ProfileScreen's own
      // consumePendingProfileTab() being checked on every build whether
      // or not a tab switch is actually pending.
      app.addListener(_openPendingTitleLink);
      // Same live-listener shape as _openPendingTitleLink just above —
      // unlike the onboarding paywall (always queued before RootShell's
      // first frame), partner linking can happen at any point while
      // this shell is already mounted underneath a pushed screen (a
      // friend's profile, the plan-evening sheet), so a one-shot
      // postFrameCallback at mount time alone wouldn't catch it.
      app.addListener(_maybeShowPartnerLinkedPaywall);
      // Same "first mount or account actually changed" moment covers
      // the home-widget's initial push too — attach() only refreshes
      // when it sees a new AppState, so this is a no-op on every other
      // rebuild that lands here for an unrelated dependency change.
      context.read<HomeWidgetService>().attach(
            app,
            context.read<EveningPlanService>(),
            context.read<PremiumService>(),
          );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _premium?.removeListener(_maybeShowTrialNudge);
    _premium?.removeListener(_maybeShowWinbackNudge);
    _appState?.removeListener(_openPendingTitleLink);
    _appState?.removeListener(_maybeShowPartnerLinkedPaywall);
    super.dispose();
  }

  /// Opens whatever title a shared-title deep link (seenly://title?...,
  /// see services/title_link_service.dart) asked for — either tapped
  /// live while already signed in and this shell already on screen, or
  /// waiting from before sign-in and just applied by
  /// AppState._applyPendingTitleLink(). Consumes it immediately so a
  /// later, unrelated notifyListeners() (a journey update, a level-up,
  /// ...) can never re-open the same title a second time.
  void _openPendingTitleLink() {
    if (!mounted) return;
    final link = context.read<AppState>().consumePendingTitleLink();
    if (link == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TitleDetailScreen(
        mediaId: link.mediaId,
        source: link.source,
        mediaType: link.mediaType,
        seedTitle: link.title.isNotEmpty ? link.title : link.mediaId,
      ),
    ));
  }

  /// The one soft, automatic paywall trigger in the app (every other
  /// one — AI-ask limit, favorites limit, ... — only ever fires from an
  /// actual tap on something premium; see widgets/premium_upsell_sheet.dart
  /// and its many call sites). Consumed once, right here, the same
  /// one-shot shape as [_openPendingTitleLink] just above — except there's
  /// no listener re-check needed, since AppState.finishOnboarding() (the
  /// only place that ever sets the flag) has already run and settled by
  /// the time this RootShell's first frame exists at all.
  ///
  /// Delayed rather than instant so it doesn't feel like onboarding just
  /// kept going under a different name — Home gets a moment to actually
  /// be seen first, then the offer arrives as its own, skippable thing.
  Future<void> _maybeShowOnboardingPaywall() async {
    if (!mounted) return;
    final pending = context.read<AppState>().consumePendingOnboardingPaywall();
    if (!pending) return;
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const PremiumScreen(triggerSource: 'onboarding'),
      fullscreenDialog: true,
    ));
  }

  /// The second soft, automatic paywall trigger (see
  /// [_maybeShowOnboardingPaywall]'s own doc comment on the first) —
  /// fires once, right after two accounts freshly link into a co-
  /// viewing couple (see AppState.notePartnerJustLinked and its three
  /// call sites). Registered as both a postFrameCallback (covers the
  /// flag already being set by the time this shell's first frame
  /// exists — e.g. linking happened on a screen that then popped back
  /// to RootShell before this ever ran) and a live AppState listener
  /// (covers linking happening later, from a screen pushed on top of
  /// an already-mounted RootShell) — same double-registration shape as
  /// [_openPendingTitleLink] just above, for the same reason.
  ///
  /// Delayed, but far less than onboarding's 1.4s: the person just saw
  /// their own "linked!" confirmation UI, so this doesn't need to wait
  /// out a whole screen transition the way the onboarding one does —
  /// just long enough that the offer reads as a follow-up thought, not
  /// something that cuts the linking moment itself off.
  Future<void> _maybeShowPartnerLinkedPaywall() async {
    if (!mounted) return;
    final pending = context.read<AppState>().consumePendingPartnerLinkedPaywall();
    if (!pending) return;
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const PremiumScreen(triggerSource: 'partner_linked'),
      fullscreenDialog: true,
    ));
  }

  /// The in-app half of the "your free period is ending" series (the
  /// server sends the pushes — backend app/trial.py): opens the paywall
  /// once per stage — ends soon, last hours, ended — and never twice for
  /// the same one (PremiumService.takeTrialNudge does the bookkeeping).
  ///
  /// Only ever fires while this shell is the screen the person is
  /// actually looking at: if something is pushed on top (another
  /// paywall, a title, a dialog) it stays quiet *without* consuming the
  /// stage, so it's simply offered the next time the shell is in front
  /// (the listener fires on every premium refresh, i.e. every resume).
  Future<void> _maybeShowTrialNudge() async {
    if (!mounted || _trialNudgeBusy) return;
    final premium = context.read<PremiumService>();
    if (premium.trialNudgeStage == 0) return;
    _trialNudgeBusy = true;
    try {
      // Let Home be seen first, like the onboarding paywall does.
      await Future.delayed(const Duration(milliseconds: 1600));
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      final stage = await premium.takeTrialNudge();
      if (stage == null || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PremiumScreen(
          triggerSource: stage == 3 ? 'trial_ended' : 'trial_ending',
        ),
        fullscreenDialog: true,
      ));
    } finally {
      _trialNudgeBusy = false;
    }
  }

  /// The comeback offer's one-time paywall, the win-back twin of
  /// [_maybeShowTrialNudge] with the same rules: only while this shell is
  /// what the person is looking at, and it is recorded as shown only at
  /// the moment it is really shown (PremiumService.takeWinbackNudge), so
  /// an offer that had to wait behind another screen is offered later.
  Future<void> _maybeShowWinbackNudge() async {
    if (!mounted || _winbackNudgeBusy) return;
    final premium = context.read<PremiumService>();
    if (!premium.winbackActive) return;
    _winbackNudgeBusy = true;
    try {
      await Future.delayed(const Duration(milliseconds: 1600));
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      if (!await premium.takeWinbackNudge() || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const PremiumScreen(triggerSource: 'winback'),
        fullscreenDialog: true,
      ));
    } finally {
      _winbackNudgeBusy = false;
    }
  }

  static const _screens = [
    // The Home tab is wrapped in the "вы / вместе" switch (see
    // HomeModeShell) rather than being HomeScreen directly. The switch
    // renders as nothing at all for anyone without a co-viewing circle,
    // so a solo account's Home tab is byte-for-byte what it always was.
    HomeModeShell(),
    DiaryScreen(),
    CollectionsScreen(),
    ProfileScreen(),
  ];

  // One "generation" counter per tab, bumped each time that tab becomes
  // the active one — see [TabActivation] in widgets/wow_motion.dart.
  // [IndexedStack] keeps every tab mounted and laid out at all times
  // (that's the point of it — state/scroll position survive a switch),
  // so a tab's own cards never naturally re-mount or move on switch for
  // their [ScrollReveal]s to replay against on their own; each one
  // reads this counter instead and replays its settle whenever it
  // ticks while that tab is the one showing.
  final _generations = List<int>.filled(_screens.length, 0);

  void _switchTab(int index) {
    final clamped = index.clamp(0, _screens.length - 1);
    if (!mounted || clamped == _index) return;
    setState(() {
      _index = clamped;
      _generations[clamped]++;
    });
    Analytics.instance.setRootScreen(_tabScreenNames[clamped], nav: 'tab');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The looping video backdrop lives inside the SafeArea below, so it
      // never reaches the status-bar / system insets. A transparent
      // Scaffold left those uncovered and the native window colour
      // (black on Android via Theme.Black in styles.xml) showed through —
      // on light themes that read as a dark screen, most visibly with the
      // video turned off. A flat palette fill underneath fixes that; the
      // video/tint layer in the Stack still paints on top of it.
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Stack(
          children: [
            // The looping onboarding backdrop, now the app's own
            // background rather than an onboarding-only moment — see
            // widgets/app_video_background.dart. Painted first so
            // everything else in this Stack sits on top of it exactly
            // as it used to sit on the flat SeenlyPalette.background
            // fill this Scaffold painted before.
            // Clay skin has its own pastel world (milky gradient, colour
            // clouds, drifting hearts/sparkles — see ClayBackdrop in
            // theme/clay_kit.dart) that shows while the video is turned
            // off; with the video on (Home's video button) it gets the
            // same looping backdrop as every other skin, so the button
            // works in clay too.
            if (SeenlySkin.isClay)
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                  valueListenable: AppBackgroundVideo.instance.enabled,
                  builder: (context, videoOn, _) =>
                      videoOn ? const AppVideoBackground() : const ClayBackdrop(),
                ),
              )
            else
              const Positioned.fill(child: AppVideoBackground()),
            // The literal paper this diary is written on — ruled lines,
            // a red margin, a stitched binding — sitting behind every
            // tab's real content instead of drawn as loose ornaments on
            // top of it. No-ops entirely outside the cozy skin.
            const Positioned.fill(child: NotebookPageBackground()),
            _TabFade(
              index: _index,
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < _screens.length; i++)
                    TabActivation(
                      active: _index == i,
                      generation: _generations[i],
                      child: _screens[i],
                    ),
                ],
              ),
            ),
            // Visible no matter which tab is open — the whole point
            // is that a journey stays reachable even after backing
            // out of it by accident.
            const ActiveJourneyBadge(),
          ],
        ),
      ),
      bottomNavigationBar: SeenlyBottomNav(
        currentIndex: _index,
        onTap: _switchTab,
      ),
    );
  }
}

/// Wraps [child] (the tab [IndexedStack]) with a quick settle-in fade
/// whenever [index] changes — otherwise switching tabs is an instant
/// hard cut, out of step with how gently everything else in the app
/// arrives. Doesn't touch [IndexedStack] itself, so every tab keeps its
/// own scroll position and state exactly as before; this only fades the
/// *result* of the swap in, the same "settle" read as [Entrance] just
/// fast enough to feel like a nav response rather than a page loading.
class _TabFade extends StatefulWidget {
  final int index;
  final Widget child;
  const _TabFade({required this.index, required this.child});

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..value = 1;
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void didUpdateWidget(covariant _TabFade old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _c
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: widget.child);
  }
}
