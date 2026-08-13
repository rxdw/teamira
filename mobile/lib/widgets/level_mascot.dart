import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/bunny.dart';

/// The bunny tied to a *specific* level tier — same real level/xp as
/// everywhere else (see ProfileService.level /
/// backend/app/routers/profile.py::get_level), reading its artwork from
/// the shared collection in models/bunny.dart. Used where the point is
/// to show progress for that exact level (the profile header, the level
/// list) rather than whichever bunny the person picked as their
/// favorite — for that, see widgets/rabbit_mascot.dart, which shows the
/// *selected* bunny (BunnyCollectionService) instead.
///
/// New tiers (level 10, 15, ...) only need an entry in
/// models/bunny.dart's `kBunnies` — see /BUNNY_SYSTEM.md — this widget
/// picks them up automatically. [hasArtFor] tells callers which levels
/// actually introduce a new drawing, so a screen listing upcoming
/// levels can say "coming soon" honestly instead of implying art that
/// isn't there yet.
class LevelMascot extends StatefulWidget {
  final int level;
  final double size;
  final bool animate;

  const LevelMascot({
    super.key,
    required this.level,
    this.size = 32,
    this.animate = true,
  });

  /// Levels that have their own unique artwork today — derived from
  /// models/bunny.dart's `kBunnies` so this never drifts out of sync
  /// with the actual collection.
  static List<int> get artTiers => bunnyArtLevels;

  static bool hasArtFor(int level) => artTiers.contains(level);

  /// Native size of every mascot tier's source art (742x1153) — used to
  /// keep callers' width/height math consistent without hardcoding the
  /// ratio in more than one place.
  static const double aspectRatio = 742 / 1153;

  /// The source art has a lot of transparent padding around the bunny
  /// itself — every tier's actual drawing only fills ~65% of the canvas
  /// width and ~78% of its height, centered — so at small sizes the
  /// mascot reads as tiny inside its own box. [_artFillFraction] is how
  /// much of the box height the crop below zooms in to fill; the box
  /// [aspectRatio]/size callers lay out against is untouched, so this
  /// only makes the bunny itself bigger within the space it already
  /// had — nothing else on screen shifts.
  static const double _artFillFraction = 0.94;
  static const double _artContentHeightFrac = 903 / 1153;
  static const double _cropScale = _artFillFraction / _artContentHeightFrac;

  static String assetFor(int level, bool isDark) =>
      currentTierBunny(level).assetFor(isDark);

  @override
  State<LevelMascot> createState() => _LevelMascotState();
}

class _LevelMascotState extends State<LevelMascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant LevelMascot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = LevelMascot.assetFor(widget.level, isDark);
    final s = widget.size;
    final height = s / LevelMascot.aspectRatio;

    // Content is dead-center in every tier's source art (see the class
    // doc), so scaling up about the center and clipping to the original
    // box crops off just the empty transparent margin — the bunny gets
    // bigger, the box callers laid out against does not.
    final image = ClipRect(
      child: Transform.scale(
        scale: LevelMascot._cropScale,
        child: Image.asset(asset, width: s, height: height, fit: BoxFit.contain),
      ),
    );

    if (!widget.animate) {
      return SizedBox(width: s, height: height, child: image);
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // A soft, slow breathing bob — gentler than the home-screen
        // rabbit's, so it doesn't compete for attention next to a
        // username or inside a list row.
        final wave = math.sin(_c.value * 2 * math.pi);
        final bob = wave * s * 0.035;
        final tilt = wave * 0.018;
        return Transform.translate(
          offset: Offset(0, bob),
          child: Transform.rotate(angle: tilt, child: child),
        );
      },
      child: SizedBox(width: s, height: height, child: image),
    );
  }
}
