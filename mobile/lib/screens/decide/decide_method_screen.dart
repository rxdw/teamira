import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/wow_motion.dart';
import 'decide_ask_teamira_screen.dart';
import 'decide_filters_screen.dart';
import 'decide_random_screen.dart';
import 'decide_roulette_screen.dart';
import 'decide_swipe_screen.dart';
import '../../services/app_translations.dart';
import '../../theme/clay_kit.dart';

/// Second step of the can't-decide flow — pick how you actually want the
/// filtered pool from [DecideFiltersScreen] narrowed down to one thing.
/// Four ways in, all reading the same [pool]; the pool itself never
/// changes here, only which screen does the narrowing.
///
/// Laid out as a 2×2 grid that fills the whole screen — the same big,
/// colorful-card language as the type/genre picker — rather than a
/// scrolling list of rows. Each tile gets a small "live" detail tuned to
/// what the method actually does: teamira's badge shimmers, random pick
/// breathes, the reel spins lazily on its own, and swipe sways side to
/// side like the gesture it's named for.
class DecideMethodScreen extends StatelessWidget {
  final List<MediaItem> pool;
  final DecideFilters filters;

  const DecideMethodScreen({super.key, required this.pool, required this.filters});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('how should we decide?'.tr, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${filters.summary} · ${pool.length} ${'to pick from'.tr}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text('edit'.tr, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.accent)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: HorizontalReveal(
                              slideBy: -28,
                              child: _MethodTile(
                                icon: Icons.auto_awesome_outlined,
                                color: SeenlyPalette.periwinkle,
                                title: 'ask tanè'.tr,
                                blurb: 'tell it what kind of evening you\'re after'.tr,
                                live: _LiveDetail.shimmer,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => DecideAskTeamiraScreen(filters: filters)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: HorizontalReveal(
                              slideBy: 28,
                              delay: const Duration(milliseconds: 70),
                              child: _MethodTile(
                                icon: Icons.casino_outlined,
                                color: SeenlyPalette.coral,
                                title: 'random pick'.tr,
                                blurb: 'one title, pulled from the pool above'.tr,
                                live: _LiveDetail.breathe,
                                onTap: pool.isEmpty
                                    ? null
                                    : () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => DecideRandomScreen(pool: pool)),
                                        ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: HorizontalReveal(
                              slideBy: -28,
                              delay: const Duration(milliseconds: 140),
                              child: _MethodTile(
                                icon: Icons.rotate_right_rounded,
                                color: SeenlyPalette.mustard,
                                title: 'spin the reel'.tr,
                                blurb: 'watch it roll and land on something'.tr,
                                live: _LiveDetail.spin,
                                onTap: pool.isEmpty
                                    ? null
                                    : () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => DecideRouletteScreen(pool: pool)),
                                        ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: HorizontalReveal(
                              slideBy: 28,
                              delay: const Duration(milliseconds: 210),
                              child: _MethodTile(
                                icon: Icons.swipe_outlined,
                                color: SeenlyPalette.sage,
                                title: 'swipe through'.tr,
                                blurb: 'left to skip, right for plan to watch'.tr,
                                live: _LiveDetail.sway,
                                onTap: pool.isEmpty
                                    ? null
                                    : () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => DecideSwipeScreen(pool: pool)),
                                        ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pool.isEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'nothing matched those filters — go back and loosen them up'.tr,
                        textAlign: TextAlign.center,
                        style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.placeholder),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which quiet, looping motion a tile's icon badge carries — chosen per
/// method to echo what tapping into it actually does, never more than
/// one motion per tile.
enum _LiveDetail { shimmer, breathe, spin, sway }

/// One big, colorful quarter-screen card — the 2×2 grid's unit. Same
/// paper-tinted-with-color surface as the type picker, just square and
/// roomy enough to carry an icon badge, a title, and a blurb without
/// feeling cramped.
class _MethodTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String blurb;
  final _LiveDetail live;
  final VoidCallback? onTap;

  const _MethodTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.blurb,
    required this.live,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.97,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: ClayBoxDecoration(
            color: Color.alphaBlend(color.withOpacity(0.09), SeenlyPalette.paper),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: SeenlyPalette.border),
            boxShadow: SeenlyPalette.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
              ),
              // The badge takes the whole middle of the card — centered
              // rather than pinned top-left — so the tile reads as one
              // balanced composition instead of a cramped header floating
              // over a lot of empty paper.
              Expanded(
                child: Center(
                  child: _LiveIconBadge(icon: icon, color: color, live: live),
                ),
              ),
              Text(title, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(
                blurb,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(italic: true, size: 13.5, color: SeenlyPalette.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 54px icon badge that carries each tile's one quiet motion.
class _LiveIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final _LiveDetail live;
  static const double _size = 64;

  const _LiveIconBadge({required this.icon, required this.color, required this.live});

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 27, color: color);

    switch (live) {
      case _LiveDetail.shimmer:
        // A shimmer sweep tinted to this tile's color instead of a flat
        // circle — the sparkle icon sits on top of its own light show,
        // fitting for the one method that's asking teamira to think.
        return SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(_size / 2),
                child: ShimmerBlock(
                  width: _size,
                  height: _size,
                  borderRadius: BorderRadius.circular(_size / 2),
                  baseColor: Color.alphaBlend(color.withOpacity(0.30), SeenlyPalette.paper),
                  highlightColor: SeenlyPalette.paper,
                ),
              ),
              iconWidget,
            ],
          ),
        );

      case _LiveDetail.breathe:
        // A soft glow breathing behind the badge — the one detail in
        // [wow_motion.dart] built exactly for "quietly alive, at rest".
        return BreathingGlow(
          color: color,
          size: _size,
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(color: color.withOpacity(0.16), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: iconWidget,
          ),
        );

      case _LiveDetail.spin:
        return Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(color: color.withOpacity(0.16), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: _LazySpin(child: iconWidget),
        );

      case _LiveDetail.sway:
        return Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(color: color.withOpacity(0.16), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: _SwipeSway(child: iconWidget),
        );
    }
  }
}

/// A slow, continuous, lazy roll — the reel icon spinning on its own
/// even before anyone's tapped it, at a pace that reads as idle rather
/// than urgent.
class _LazySpin extends StatefulWidget {
  final Widget child;
  const _LazySpin({required this.child});

  @override
  State<_LazySpin> createState() => _LazySpinState();
}

class _LazySpinState extends State<_LazySpin> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 9000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}

/// A gentle side-to-side sway with a hair of tilt — a quiet echo of the
/// left/right swipe gesture the method itself is named for, small enough
/// to read as idle rather than a nudge to act.
class _SwipeSway extends StatefulWidget {
  final Widget child;
  const _SwipeSway({required this.child});

  @override
  State<_SwipeSway> createState() => _SwipeSwayState();
}

class _SwipeSwayState extends State<_SwipeSway> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final wave = math.sin(_c.value * 2 * math.pi);
        return Transform.translate(
          offset: Offset(wave * 5, 0),
          child: Transform.rotate(angle: wave * 0.07, child: child),
        );
      },
    );
  }
}
