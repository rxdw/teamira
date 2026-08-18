import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/achievement.dart';
import '../../services/log_theme_service.dart';
import '../../services/rabbit_mascot_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/log_theme_copy.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/achievement_badge.dart';
import '../../widgets/rabbit_mascot.dart';
import '../../widgets/scroll_reveal.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart' show Entrance, PressScale;
import '../../services/app_translations.dart';

const _kMaxPinned = 3;

/// The full badge showcase — everything on this screen is computed from
/// the person's own logged rows (see backend/app/routers/profile.py
/// ::get_achievements); there's nothing here that can be granted any
/// other way, which is the whole reason for the honesty note up top.
///
/// Filtered by rarity rather than grouped by category (milestone/craft/
/// genre/...) — four tabs, one per [BadgeRarity], the same underlined
/// tab-bar language Profile's own watched/plan-to-watch/watching-now
/// row uses (see _TabLabel in profile_screen.dart), just re-themed per
/// tab in that rarity's own color instead of always the accent.
class AchievementsScreen extends StatefulWidget {
  final AchievementsResponse? initial;
  const AchievementsScreen({super.key, this.initial});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late Future<AchievementsResponse> _future;
  // Mirrors the server's pinned_ids once a response has loaded — kept
  // separately so tapping a badge can update the showcase instantly
  // without re-fetching the whole achievements list.
  List<String> _pinnedIds = [];
  bool _pinning = false;
  BadgeRarity _activeRarity = BadgeRarity.habit;

  @override
  void initState() {
    super.initState();
    _future = widget.initial != null
        ? Future.value(widget.initial)
        : _load();
    if (widget.initial != null) _pinnedIds = widget.initial!.pinnedIds;
    _future.then((r) {
      if (mounted) setState(() => _pinnedIds = r.pinnedIds);
    });
  }

  Future<AchievementsResponse> _load() => context.read<AppState>().profile.achievements();

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    final r = await next;
    if (mounted) setState(() => _pinnedIds = r.pinnedIds);
  }

  /// The whole reason for this screen to exist beyond a grid of shapes —
  /// tapping any badge (earned or not) opens a small cozy centered card
  /// with the same `caption` the backend already computes for every
  /// achievement (see profile.py::compute_achievements_for_user) but
  /// that the grid itself has no room to spell out. Shared with
  /// Profile's pinned-badges teaser row (see [showBadgeDetailCard]) so
  /// both places explain a given badge the exact same way.
  Future<void> _showBadgeDetail(Achievement a) => showBadgeDetailCard(
        context,
        achievement: a,
        pinned: _pinnedIds.contains(a.id),
        onTogglePin: () => _togglePin(a),
      );

  Future<void> _togglePin(Achievement a) async {
    if (_pinning) return;
    final next = List<String>.from(_pinnedIds);
    if (next.contains(a.id)) {
      next.remove(a.id);
    } else {
      if (next.length >= _kMaxPinned) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: SeenlyPalette.ink,
          behavior: SnackBarBehavior.floating,
          content: Text('${'you can showcase up to'.tr} $_kMaxPinned ${'badges — unpin one first'.tr}',
              style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper)),
        ));
        return;
      }
      next.add(a.id);
    }
    setState(() {
      _pinnedIds = next;
      _pinning = true;
    });
    try {
      final updated = await context.read<AppState>().profile.pinAchievements(next);
      if (mounted) setState(() => _pinnedIds = updated.pinnedIds);
    } catch (_) {
      // Best-effort — roll the optimistic update back on failure.
      if (mounted) setState(() => _pinnedIds = List<String>.from(_pinnedIds)..remove(a.id));
    } finally {
      if (mounted) setState(() => _pinning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Height is fixed to fit the celebration mascot fully — it used
            // to be positioned inside a Stack whose own height came only
            // from the header row (much shorter than the mascot), so the
            // mascot's bottom hung past the header and painted over the
            // list content underneath. Reserving its real height here
            // means nothing needs to overflow to fit.
            SizedBox(
              height: 76,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
                      child: Row(
                        children: [
                          PressScale(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('badges'.tr, style: SeenlyText.screenTitle),
                        ],
                      ),
                    ),
                  ),
                  FutureBuilder<AchievementsResponse>(
                    future: _future,
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      if (data == null || data.unlockedCount <= 0) return const SizedBox.shrink();
                      if (!context.watch<RabbitMascotPrefsService>().enabled) {
                        return const SizedBox.shrink();
                      }
                      return const Positioned(
                        top: 0,
                        right: 6,
                        child: RabbitMascot(mood: RabbitMood.celebrating, size: 76),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<AchievementsResponse>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return const Center(child: ThemedLoadingIndicator());
                  }
                  if (snapshot.hasError) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: SeenlyPalette.accent,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 60),
                        children: [
                          Entrance(
                            child: Text('couldn\'t load your badges'.tr,
                                textAlign: TextAlign.center,
                                style: SeenlyText.serif(italic: true, color: SeenlyPalette.inkMuted)),
                          ),
                          const SizedBox(height: 10),
                          Entrance(
                            delay: const Duration(milliseconds: 60),
                            child: PressScale(
                              onTap: _refresh,
                              child: Text('pull down, or tap here, to try again'.tr,
                                  textAlign: TextAlign.center,
                                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final data = snapshot.data!;
                  final byRarity = <BadgeRarity, List<Achievement>>{
                    for (final r in BadgeRarity.values) r: [],
                  };
                  for (final a in data.achievements) {
                    byRarity[badgeRarityFromKey(a.rarity)]!.add(a);
                  }
                  final shown = [...byRarity[_activeRarity]!]..sort((a, b) {
                      if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
                      return b.progressRatio.compareTo(a.progressRatio);
                    });
                  final shownUnlocked = shown.where((a) => a.unlocked).length;

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: SeenlyPalette.accent,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(21, 6, 21, 32),
                      children: [
                        Entrance(
                          child: Row(
                            children: [
                              const Icon(Icons.emoji_events, size: 17, color: SeenlyPalette.mustard),
                              const SizedBox(width: 7),
                              Text.rich(
                                TextSpan(
                                  style: SeenlyText.serif(size: 15, weight: FontWeight.w600),
                                  children: [
                                    TextSpan(text: '${data.unlockedCount}'),
                                    TextSpan(
                                      text: " ${'of'.tr} ${data.totalCount} ${'unlocked'.tr}",
                                      style: SeenlyText.serif(size: 15, color: SeenlyPalette.inkMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Entrance(
                          delay: const Duration(milliseconds: 60),
                          riseBy: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: SeenlyPalette.accent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.favorite_border, size: 15, color: SeenlyPalette.accent),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    LogThemeCopy.achievementsHonesty(theme),
                                    style: SeenlyText.serif(
                                        italic: true, size: 11.5, color: SeenlyPalette.accent),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Entrance(
                          delay: const Duration(milliseconds: 110),
                          child: Row(
                            children: [
                              for (final r in BadgeRarity.values)
                                _RarityTab(
                                  rarity: r,
                                  count: byRarity[r]!.where((a) => a.unlocked).length,
                                  active: _activeRarity == r,
                                  onTap: () => setState(() => _activeRarity = r),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            '$shownUnlocked ${'of'.tr} ${shown.length} ${_activeRarity.label} ${'badges earned'.tr}',
                            key: ValueKey(_activeRarity),
                            style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'tap any badge to see what it\'s for'.tr,
                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
                        ),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
                                  .animate(animation),
                              child: child,
                            ),
                          ),
                          child: shown.isEmpty
                              ? Padding(
                                  key: const ValueKey('empty'),
                                  padding: const EdgeInsets.symmetric(vertical: 30),
                                  child: Text(
                                    'nothing here yet'.tr,
                                    textAlign: TextAlign.center,
                                    style: SeenlyText.serif(italic: true, color: SeenlyPalette.placeholder),
                                  ),
                                )
                              : GridView.builder(
                                  key: ValueKey(_activeRarity),
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: shown.length,
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 22,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 0.74,
                                  ),
                                  itemBuilder: (context, i) {
                                    final a = shown[i];
                                    return ScrollRevealEntrance(
                                      index: i,
                                      child: _BadgeShowcaseTile(
                                        achievement: a,
                                        pinned: _pinnedIds.contains(a.id),
                                        onTap: () => _showBadgeDetail(a),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the four rarity filter tabs — same underlined-label language as
/// Profile's watched/plan-to-watch/watching-now row (_TabLabel), just
/// carrying its own rarity's color for the underline and count instead of
/// always the app accent, so the tab strip doubles as the legend the old
/// screen used to show separately.
class _RarityTab extends StatelessWidget {
  final BadgeRarity rarity;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _RarityTab({
    required this.rarity,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = rarity.color;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              bottom: BorderSide(color: active ? color : SeenlyPalette.border, width: 2),
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rarity.label,
                style: SeenlyText.serif(
                  italic: true,
                  size: 12.5,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? SeenlyPalette.ink : SeenlyPalette.placeholder,
                ),
              ),
              const SizedBox(height: 2),
              Text('$count', style: SeenlyText.mono(size: 9.5, color: active ? color : SeenlyPalette.placeholder)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The showcase grid's own tile — a round, pastel-filled medallion (the
/// reference showcase's circular badge-wall look, warmed up into
/// Seenly's own cork-and-cream palette instead of a bright game-y one)
/// with the title underneath and, for an unlocked badge, its rarity
/// named in that rarity's color where the reference shows its point
/// value — the closest honest equivalent, since nothing here carries a
/// numeric score (see the honesty banner above).
class _BadgeShowcaseTile extends StatelessWidget {
  final Achievement achievement;
  final bool pinned;
  final VoidCallback? onTap;
  const _BadgeShowcaseTile({required this.achievement, required this.pinned, this.onTap});

  @override
  Widget build(BuildContext context) {
    final unlocked = achievement.unlocked;
    final rarity = badgeRarityFromKey(achievement.rarity);
    final icon = achievementIcon(achievement.iconKey, achievement.title);
    final isLegend = unlocked && rarity == BadgeRarity.legend;
    const diameter = 68.0;

    Widget medallion = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: unlocked
            ? (isLegend
                ? rarity.gradient
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(SeenlyPalette.paper, rarity.color, 0.22)!,
                      Color.lerp(SeenlyPalette.paper, rarity.color, 0.34)!,
                    ],
                  ))
            : null,
        color: unlocked ? null : SeenlyPalette.paper,
        border: unlocked ? null : Border.all(color: SeenlyPalette.dashedBorder, width: 1.4),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: 27,
        color: unlocked ? (isLegend ? SeenlyPalette.paper : rarity.color) : SeenlyPalette.placeholder,
      ),
    );

    if (isLegend) {
      medallion = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          medallion,
          Positioned(
            top: 6,
            right: 10,
            child: Icon(Icons.auto_awesome, size: 11, color: SeenlyPalette.paper.withOpacity(0.9)),
          ),
        ],
      );
    }

    if (unlocked) {
      medallion = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: rarity.color.withOpacity(isLegend ? 0.42 : 0.3),
              blurRadius: isLegend ? 16 : 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: medallion,
      );
      medallion = Stack(
        clipBehavior: Clip.none,
        children: [
          medallion,
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 19,
              height: 19,
              decoration: const BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: pinned
                  ? Icon(Icons.push_pin, size: 11, color: SeenlyPalette.accent)
                  : Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: rarity.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: SeenlyPalette.paper, width: 1.4),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.check, size: 9, color: SeenlyPalette.paper),
                    ),
            ),
          ),
        ],
      );
    }

    final caption = unlocked
        ? Text(rarity.label,
            style: SeenlyText.mono(size: 9.5, weight: FontWeight.w700, color: rarity.color))
        : (achievement.progressCurrent > 0
            ? Text('${achievement.progressCurrent} / ${achievement.progressTarget}',
                style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder))
            : const SizedBox(height: 12));

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        medallion,
        const SizedBox(height: 9),
        Text(
          achievement.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: SeenlyText.serif(
            size: 11,
            weight: FontWeight.w600,
            color: unlocked ? SeenlyPalette.ink : SeenlyPalette.placeholder,
          ),
        ),
        const SizedBox(height: 3),
        caption,
      ],
    );

    if (onTap == null) return content;
    return PressScale(onTap: onTap, haptics: true, child: content);
  }
}

