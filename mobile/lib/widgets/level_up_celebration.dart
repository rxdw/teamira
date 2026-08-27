import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/profile_stats.dart';
import '../services/log_theme_service.dart';
import '../theme/log_theme_copy.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';
import 'wow_effects.dart';

/// Shows the "just leveled up" moment — the same spin/rays/sweep
/// ceremony [showAchievementUnlockCelebration] gives a new badge,
/// reused here because a level-up currently just updates a cached
/// number in [AppState] and a small ring on Profile the next time
/// someone happens to look at it. That's the gap this fills: the exact
/// instant it happens, not just eventually reflected somewhere.
///
/// Call sites: right after a save, wherever [checkAndCelebrateNewAchievements]
/// already gets called — read [AppState.consumePendingLevelUp] first
/// and show this (if it returns non-null) before that achievement
/// check, so a level-up and a fresh badge from the same save play as
/// two beats in the same breath rather than competing.
Future<void> showLevelUpCelebration(BuildContext context, ProfileLevel level) {
  final theme = context.read<LogThemeService>().theme;
  return showGeneralDialog(
    context: context,
    barrierLabel: 'level up',
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, __) => _LevelUpMoment(level: level, theme: theme),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _LevelUpMoment extends StatefulWidget {
  final ProfileLevel level;
  final LogTheme theme;
  const _LevelUpMoment({required this.level, required this.theme});

  @override
  State<_LevelUpMoment> createState() => _LevelUpMomentState();
}

class _LevelUpMomentState extends State<_LevelUpMoment> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  // Same one-shot-per-showing haptic guards as _AchievementMintMomentState
  // in achievement_unlock_overlay.dart — this widget is deliberately a
  // close cousin of that one rather than sharing code with it: the two
  // moments differ enough (a level number instead of a badge medallion,
  // no queue, no rarity) that forcing a shared base would mean more
  // conditionals than it'd save.
  bool _spunHaptic = false;
  bool _landedHaptic = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.selectionClick();
    _c.addListener(_onTick);
    _c.forward();
  }

  void _onTick() {
    final t = _c.value;
    if (!_spunHaptic && t > 0.08) {
      _spunHaptic = true;
      HapticFeedback.lightImpact();
    }
    if (!_landedHaptic && t > 0.5) {
      _landedHaptic = true;
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  double _interval(double start, double end, {Curve curve = Curves.linear}) {
    final raw = ((_c.value - start) / (end - start)).clamp(0.0, 1.0);
    return curve.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Same choreography as the achievement mint moment — wound-up
          // spin easing to a clean stop, an elastic entrance scale, a
          // ray burst that blooms and fades, a spotlight sweep, text
          // rising in last. See _AchievementMintMomentState.build's own
          // comments for why these are read here inside the builder
          // rather than once in build().
          final spinT = _interval(0.0, 0.62, curve: Curves.easeOutCubic);
          final spinAngle = -(1 - spinT) * 2 * math.pi * 3;

          final scaleT = _interval(0.0, 0.55, curve: Curves.elasticOut);
          final entranceOpacity = _interval(0.0, 0.22, curve: Curves.easeOut);

          final rayWindow = _interval(0.32, 0.95, curve: Curves.linear);
          final rayEnvelope = math.sin(rayWindow.clamp(0.0, 1.0) * math.pi);

          final sweepT = _interval(0.5, 0.92, curve: Curves.easeInOut);
          final textT = _interval(0.58, 0.95, curve: Curves.easeOutCubic);

          return Stack(
            fit: StackFit.expand,
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: SeenlyPalette.darkColors.background.withOpacity(0.72 * entranceOpacity),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: entranceOpacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            GoldRayBurst(
                              t: rayEnvelope,
                              color: SeenlyPalette.accent,
                              size: 220,
                            ),
                            Transform.scale(
                              scale: scaleT,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.0018)
                                  ..rotateY(spinAngle),
                                child: SpotlightSweep(
                                  progress: sweepT,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: SeenlyPalette.accent.withOpacity(0.55),
                                          blurRadius: 34,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: _LevelMedallion(level: widget.level.level, diameter: 128),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Transform.translate(
                        offset: Offset(0, (1 - textT) * 14),
                        child: Opacity(
                          opacity: textT,
                          child: Column(
                            children: [
                              Text(
                                'level up'.tr,
                                style: SeenlyText.mono(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: SeenlyPalette.accent,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                LogThemeCopy.levelHeadline(widget.theme, widget.level.level),
                                textAlign: TextAlign.center,
                                style: SeenlyText.serif(
                                  size: 22,
                                  weight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 26),
                              Text(
                                'tap to continue'.tr,
                                style: SeenlyText.mono(size: 10, color: Colors.white38),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The badge itself: the same paper-disc-with-an-accent-ring language
/// as the small level ring on Profile (`_LevelRing`, private to that
/// screen) — a full ring rather than a partial-progress arc, since this
/// moment marks having just filled the old one, not showing where the
/// new one currently sits.
class _LevelMedallion extends StatelessWidget {
  final int level;
  final double diameter;
  const _LevelMedallion({required this.level, required this.diameter});

  @override
  Widget build(BuildContext context) {
    final strokeWidth = diameter * 0.055;
    final innerSize = diameter - strokeWidth * 2.6;
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SeenlyPalette.accent, width: strokeWidth),
            ),
          ),
          Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              color: SeenlyPalette.paper,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '$level',
                  style: SeenlyText.serif(
                    size: diameter * 0.4,
                    weight: FontWeight.w700,
                    color: SeenlyPalette.accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
