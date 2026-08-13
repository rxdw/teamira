import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../widgets/active_journey_badge.dart';
import '../../widgets/seenly_bottom_nav.dart';
import '../../widgets/wow_motion.dart';
import '../collections/collections_screen.dart';
import '../diary/diary_screen.dart';
import '../home/home_screen.dart';
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

class _RootShellState extends State<RootShell> {
  late int _index = widget.initialIndex.clamp(0, _screens.length - 1).toInt();

  static const _screens = [
    HomeScreen(),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Stack(
          children: [
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
