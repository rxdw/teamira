import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/log_theme_service.dart';
import '../theme/log_theme_copy.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';
import 'wow_effects.dart';

/// Shows the "you just finished every episode of this" moment — same
/// spin/rays/sweep ceremony as [showLevelUpCelebration] and the
/// achievement unlock, for a threshold neither of those cover: a
/// specific season (or, with [wholeSeries], a whole series) actually
/// watched to the end.
///
/// Before this existed, `maybeLogCompletedSeason` (episode_log_followup.dart)
/// quietly wrote the season's diary row and, for a finished series,
/// quietly promoted it on the shelf — genuinely one of the bigger
/// feel-good moments watching something offers, happening with zero
/// visual acknowledgement. Call this from the same spot, right after
/// that diary row lands.
Future<void> showWatchCompleteCelebration(
  BuildContext context, {
  required bool wholeSeries,
}) {
  final theme = context.read<LogThemeService>().theme;
  return showGeneralDialog(
    context: context,
    barrierLabel: 'watch complete',
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, __) =>
        _WatchCompleteMoment(theme: theme, wholeSeries: wholeSeries),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _WatchCompleteMoment extends StatefulWidget {
  final LogTheme theme;
  final bool wholeSeries;
  const _WatchCompleteMoment({required this.theme, required this.wholeSeries});

  @override
  State<_WatchCompleteMoment> createState() => _WatchCompleteMomentState();
}

class _WatchCompleteMomentState extends State<_WatchCompleteMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  // Same one-shot-per-showing haptic guards as the level-up and
  // achievement moments this one is styled after — see their own
  // State classes for why this stays a close cousin rather than a
  // shared base (see level_up_celebration.dart's doc comment).
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
                                    child: _WatchCompleteMedallion(
                                      icon: LogThemeCopy.navIcon(widget.theme, active: true),
                                      wholeSeries: widget.wholeSeries,
                                      diameter: 128,
                                    ),
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
                                (widget.wholeSeries ? 'series complete' : 'season complete').tr,
                                style: SeenlyText.mono(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: SeenlyPalette.accent,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                LogThemeCopy.seasonCompleteHeadline(
                                  widget.theme,
                                  wholeSeries: widget.wholeSeries,
                                ),
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

/// The badge itself: same paper-disc-with-an-accent-ring language as
/// [_LevelMedallion] in level_up_celebration.dart, but centered on a
/// checkmark (season) or the theme's own nav icon (whole series) rather
/// than a number — there's no count to show here, just "done".
class _WatchCompleteMedallion extends StatelessWidget {
  final IconData icon;
  final bool wholeSeries;
  final double diameter;
  const _WatchCompleteMedallion({
    required this.icon,
    required this.wholeSeries,
    required this.diameter,
  });

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
            child: Icon(
              wholeSeries ? icon : Icons.check_rounded,
              size: diameter * 0.42,
              color: SeenlyPalette.accent,
            ),
          ),
        ],
      ),
    );
  }
}
