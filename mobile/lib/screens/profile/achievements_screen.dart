import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/achievement.dart';
import '../../services/log_theme_service.dart';
import '../../state/app_state.dart';
import '../../theme/log_theme_copy.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/achievement_badge.dart';
import '../../widgets/achievement_unlock_overlay.dart';
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
      _checkForNewUnlocks(r);
    });
  }

  /// Delegates to [checkAndCelebrateNewAchievements] — the shared
  /// diff-and-celebrate check also called right after logging an
  /// evening (see screens/add_entry/*). Runs here too since this
  /// screen (or Profile's pinned-badges teaser row, which calls the
  /// same achievements() endpoint but never checks this) is also
  /// exactly the moment a newly-unlocked achievement would first
  /// become visible to someone who unlocked it some other way, or
  /// simply hasn't opened the app since.
  Future<void> _checkForNewUnlocks(AchievementsResponse r) =>
      checkAndCelebrateNewAchievements(context);

  Future<AchievementsResponse> _load() => context.read<AppState>().profile.achievements();

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    final r = await next;
    if (mounted) setState(() => _pinnedIds = r.pinnedIds);
    _checkForNewUnlocks(r);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
              child: Row(
                children: [
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('badges'.tr, style: SeenlyText.screenTitle),
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
                              Icon(Icons.emoji_events, size: 17, color: SeenlyPalette.mustard),
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
                        const SizedBox(height: 10),
                        // A thin overall-collection fill under the raw count —
                        // the same "count up, don't jump" fill-in Profile's own
                        // level ring uses (see _LevelRing), just flattened to a
                        // bar since there's no single "current tier" here to
                        // ring around, only a running total across every rarity.
                        Entrance(
                          delay: const Duration(milliseconds: 30),
                          child: _CollectionProgressBar(
                            ratio: data.totalCount == 0 ? 0 : data.unlockedCount / data.totalCount,
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
                        // The badge shelf itself sits in its own soft paper
                        // card rather than floating loose on the screen
                        // background — the same "cozy object on a surface"
                        // language the rest of the app uses (see palette's
                        // own doc comment on `paper`/`cork`), so a wall of
                        // circles reads as one grouped display case instead
                        // of scattered dots.
                        Entrance(
                          delay: const Duration(milliseconds: 140),
                          child: Container(
                            width: double.infinity,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: SeenlyPalette.paper,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: SeenlyPalette.border, width: 1),
                              boxShadow: SeenlyPalette.softShadow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // A slim accent strip in the active rarity's own
                                // color across the top of the case — echoes the
                                // tab that's currently selected, so the case
                                // below visibly "belongs" to whichever tab is
                                // lit rather than sitting neutral under all four.
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 260),
                                  height: 4,
                                  color: _activeRarity.color,
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 20, 14, 24),
                                  child: AnimatedSwitcher(
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
                                    padding: const EdgeInsets.symmetric(vertical: 26),
                                    child: Column(
                                      children: [
                                        Icon(Icons.emoji_events_outlined,
                                            size: 30, color: SeenlyPalette.dashedBorder),
                                        const SizedBox(height: 10),
                                        Text(
                                          'nothing here yet'.tr,
                                          textAlign: TextAlign.center,
                                          style: SeenlyText.serif(
                                              italic: true, color: SeenlyPalette.placeholder),
                                        ),
                                      ],
                                    ),
                                  )
                                  // A plain SliverGridDelegateWithFixedCrossAxisCount
                                  // always packs left-to-right, so a final row
                                  // short of a full 3 (2 left over, or 1) sits
                                  // stranded on the left. Wrap — sized so each
                                  // tile is exactly a third of the row, with
                                  // WrapAlignment.center — reproduces the same
                                  // tidy 3-across grid for every full row (a
                                  // full row has zero slack to center within,
                                  // so this is visually identical to the old
                                  // grid there) but centers the leftover tiles
                                  // instead of stranding them for the last,
                                  // partial one.
                                  : LayoutBuilder(
                                      key: ValueKey(_activeRarity),
                                      builder: (context, constraints) {
                                        const columns = 3;
                                        const spacing = 10.0;
                                        final tileWidth =
                                            (constraints.maxWidth - spacing * (columns - 1)) /
                                                columns;
                                        return Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: spacing,
                                          runSpacing: 24,
                                          children: [
                                            for (int i = 0; i < shown.length; i++)
                                              SizedBox(
                                                width: tileWidth,
                                                child: ScrollRevealEntrance(
                                                  index: i,
                                                  child: _BadgeShowcaseTile(
                                                    achievement: shown[i],
                                                    pinned: _pinnedIds.contains(shown[i].id),
                                                    onTap: () => _showBadgeDetail(shown[i]),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                          ),
                                ),
                              ],
                            ),
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
/// Profile's watched/plan-to-watch/watching-now row (_TabLabel), lifted a
/// touch further here: the active tab fills with that rarity's own
/// [BadgeRarityStyle.gradient] (the exact material its unlocked badges are
/// made of) rather than a flat tint, and carries a small glyph so the four
/// tabs read at a glance even before the label's been read — the same
/// count-as-legend idea the old screen's separate legend used to carry.
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

  IconData get _icon {
    switch (rarity) {
      case BadgeRarity.habit:
        return Icons.eco_outlined;
      case BadgeRarity.devoted:
        return Icons.favorite_outline;
      case BadgeRarity.obsession:
        return Icons.local_fire_department_outlined;
      case BadgeRarity.legend:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = rarity.color;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          scale: active ? 1.0 : 0.96,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color.withOpacity(0.22), color.withOpacity(0.10)],
                    )
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? color.withOpacity(0.55) : Colors.transparent,
                width: 1.2,
              ),
              boxShadow: active
                  ? [BoxShadow(color: color.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 3))]
                  : null,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon, size: 15, color: active ? color : SeenlyPalette.placeholder),
                const SizedBox(height: 4),
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
      ),
    );
  }
}

/// The thin "collection so far" fill under the raw unlocked/total count —
/// animates from empty on first build (same "grows in" spirit as
/// Profile's own level ring) rather than snapping straight to its target.
class _CollectionProgressBar extends StatelessWidget {
  final double ratio;
  const _CollectionProgressBar({required this.ratio});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 6,
        color: SeenlyPalette.border,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => FractionallySizedBox(
            widthFactor: value,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [SeenlyPalette.mustard, SeenlyPalette.accent],
                ),
              ),
            ),
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
              decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
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
                      child: Icon(Icons.check, size: 9, color: SeenlyPalette.paper),
                    ),
            ),
          ),
        ],
      );
    }

    // A thin outer gauge instead of the old dashed border sitting right
    // on the medallion's own edge — locked badges get an honest "how
    // close am I" ring (empty track when nothing's logged toward it
    // yet, filled to [Achievement.progressRatio] once something has),
    // unlocked ones just get the plain glow above. Wrapping every tile
    // in the same [ringSize] box regardless of state (rather than only
    // the locked ones) keeps every medallion — locked or unlocked —
    // sitting at the same visual size in the grid instead of the ring
    // silently making locked tiles a few pixels wider than unlocked
    // ones next to them.
    const ringSize = diameter + 16;
    medallion = SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (!unlocked)
            CustomPaint(
              size: const Size(ringSize, ringSize),
              painter: _BadgeProgressRingPainter(
                progress: achievement.progressRatio,
                trackColor: SeenlyPalette.dashedBorder,
                progressColor: rarity.color,
              ),
            ),
          medallion,
        ],
      ),
    );

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

/// The locked-badge progress gauge — a rounded-stroke arc over a neutral
/// track, same drawing approach as Profile's own `_RingArcPainter` for
/// the level ring, just sized for a small grid tile instead of a header
/// avatar. Kept local to this file rather than shared: the two draw the
/// same shape but never need to change in lockstep.
class _BadgeProgressRingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color trackColor;
  final Color progressColor;
  const _BadgeProgressRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.0;
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final center = rect.center;
    final radius = rect.width / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = progressColor;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress.clamp(0.0, 1.0), false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BadgeProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}

