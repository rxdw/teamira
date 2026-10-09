import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../analytics/analytics.dart';
import '../../models/partner_status.dart';
import '../../models/suggestion.dart';
import '../../services/api_client.dart';
import '../../services/partner_service.dart';
import '../../services/shared_diary_service.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/wow_motion.dart';
import '../home/home_screen.dart';
import '../partner/co_view_hub_screen.dart';
import '../partner/room/room_guest_banner.dart';
import '../../theme/clay_kit.dart';
import '../../services/app_translations.dart';
import '../../services/locale_service.dart';

/// Wraps the Home tab in a "вы / вместе" switch.
///
/// Why this sits here rather than inside HomeScreen: HomeScreen owns a
/// CustomScrollView whose first sliver is the greeting, and the switch has
/// to stay put while that scrolls. Pinning it *above* the scroll view
/// means neither screen has to know about the other, and the co-viewing
/// mode gets to be a genuinely full screen rather than a section wedged
/// into Home's existing sliver list.
///
/// The two modes are held in an [IndexedStack], not swapped — same
/// reasoning as RootShell's own tabs. Flipping to "вместе" to check
/// whether your partner voted and flipping back must not throw away
/// Home's scroll position or refetch its whole feed.
///
/// The switch only appears once there's actually a circle to switch into.
/// A solo user sees Home exactly as it was, with no extra chrome and no
/// tab teasing a feature they haven't set up — the co-viewing invite lives
/// on the Home card it always did.
class HomeModeShell extends StatefulWidget {
  const HomeModeShell({super.key});

  @override
  State<HomeModeShell> createState() => _HomeModeShellState();
}

class _HomeModeShellState extends State<HomeModeShell> {
  late final PartnerService _partner = PartnerService(ApiClient.instance);
  late final SharedDiaryService _shared = SharedDiaryService(ApiClient.instance);

  // How the "вы и .." half knows whether to show its dot — the last time
  // this account actually switched into that mode, in epoch millis.
  // Anything on the co-viewing side newer than this counts as unseen.
  static const _lastSeenKey = 'seenly_coview_last_seen_at';

  int _mode = 0;
  PartnerStatus? _status;
  bool _checked = false;
  bool _hasNews = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final status = await _partner.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _checked = true;
      });
      if (status.linked) _checkForNews(status);
    } catch (_) {
      // Offline, or the link check failed — fall back to plain Home
      // rather than blocking it. The switch reappears on the next
      // successful check; nothing about Home depends on this.
      if (!mounted) return;
      setState(() => _checked = true);
    }
  }

  /// A light early peek at whether the "вы и .." switch should carry a
  /// dot — a new suggestion waiting on you, or something the other side
  /// planned since you last actually opened that tab. Both come from
  /// endpoints CoViewHubScreen fetches anyway once you're there; this
  /// just checks them a beat sooner so the switch itself can carry the
  /// news instead of it being a surprise once you're already inside.
  Future<void> _checkForNews(PartnerStatus status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeen = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_lastSeenKey) ?? 0);
      final myUsername = status.members
          .firstWhere((m) => m.isYou, orElse: () => const PartnerMember(userId: '', username: ''))
          .username;
      final results = await Future.wait([
        _partner.suggestions(),
        _shared.planned(),
      ]);
      if (!mounted) return;
      final suggestions = results[0] as List<Suggestion>;
      final planned = results[1] as SharedPlanned;
      final hasNewSuggestion = suggestions.any((s) => s.createdAt.isAfter(lastSeen));
      // Only what the *other* side added — you already know about your
      // own additions, no notification needed for those.
      final hasNewPlanned = planned.planned.any((e) =>
          e.addedByUsername != null &&
          e.addedByUsername != myUsername &&
          e.createdAt.isAfter(lastSeen));
      setState(() => _hasNews = hasNewSuggestion || hasNewPlanned);
    } catch (_) {
      // Best-effort — a missed check just means the dot doesn't light up
      // until the next one; nothing about the switch depends on it.
    }
  }

  /// Called by the co-viewing side after someone links up, so the switch
  /// appears without needing an app restart.
  void refreshLink() => _check();

  Future<void> _markSeen() async {
    if (!_hasNews) return;
    setState(() => _hasNews = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeenKey, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final linked = _status?.linked ?? false;
    // Never render the switch before the first check finishes — a bar
    // that pops in half a second after the screen settles is worse than
    // one that was always there.
    final showSwitch = _checked && linked;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: showSwitch
              ? _ModeSwitch(
                  mode: _mode,
                  partnerName: _status?.partnerUsername,
                  showBadge: _hasNews,
                  onChanged: (i) {
                    setState(() => _mode = i);
                    if (i == 1) _markSeen();
                    // Same tab, different screen — see RootShell._tabScreenNames.
                    Analytics.instance.setRootScreen(i == 1 ? 'CoViewHubScreen' : 'HomeScreen', nav: 'tab');
                  },
                )
              : const SizedBox(width: double.infinity),
        ),
        // A friend inviting you into their watching room as a guest. Shown to
        // everybody, linked or not: a guest needn't be in any circle.
        const RoomGuestInviteBanner(),
        Expanded(
          child: IndexedStack(
            index: showSwitch ? _mode : 0,
            children: [
              const HomeScreen(),
              CoViewHubScreen(
                onUnlinked: () {
                  // Left the circle from inside the tab: back to plain
                  // Home, and re-check the link so the switch goes away.
                  setState(() => _mode = 0);
                  Analytics.instance.setRootScreen('HomeScreen', nav: 'tab');
                  _check();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A soft paper segmented control — two rounded halves with the active one
/// filled in the accent. Deliberately not Material's SegmentedButton: that
/// carries Material 3's own shape, ripple and borders, which read as a
/// system control dropped into a hand-made notebook.
class _ModeSwitch extends StatelessWidget {
  final int mode;
  final String? partnerName;
  final bool showBadge;
  final ValueChanged<int> onChanged;

  const _ModeSwitch({
    required this.mode,
    required this.onChanged,
    this.partnerName,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 2),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: _Half(
                label: 'вы'.tr,
                icon: Icons.nights_stay_outlined,
                active: mode == 0,
                color: SeenlyPalette.accent,
                onTap: () => onChanged(0),
              ),
            ),
            Expanded(
              child: _Half(
                // The partner's own name rather than a generic "вместе" —
                // it's the difference between a mode toggle and a person.
                label: partnerName == null || partnerName!.isEmpty
                    ? 'вместе'.tr
                    : (LocaleService.appIsRussian
                        ? 'вы и ${partnerName!.toLowerCase()}'
                        : 'you and ${partnerName!.toLowerCase()}'),
                icon: Icons.favorite_rounded,
                active: mode == 1,
                color: SeenlyPalette.pink,
                showBadge: showBadge,
                onTap: () => onChanged(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Half extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final bool showBadge;
  final VoidCallback onTap;

  const _Half({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) => PressScale(
        haptics: true,
        onTap: onTap,
        scaleTo: 0.96,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon,
                      size: 14,
                      color: active ? color : SeenlyPalette.inkFaint),
                  if (showBadge)
                    Positioned(
                      top: -3,
                      right: -4,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: SeenlyPalette.coral,
                          shape: BoxShape.circle,
                          border: Border.all(color: SeenlyPalette.paper, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 7),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 260),
                  style: SeenlyText.serif(
                    size: 13.5,
                    italic: true,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? color : SeenlyPalette.inkMuted,
                  ),
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
      );
}
