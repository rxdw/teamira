import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/challenge.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'challenge_card.dart' show challengeIcon;
import 'wow_effects.dart';
import '../services/app_translations.dart';
import '../services/locale_service.dart';

/// Shows the "just claimed" moment for a finished challenge — the same
/// spin/rays/sweep ceremony [showLevelUpCelebration] and
/// [showAchievementUnlockCelebration] give a level or a badge, reused
/// here so collecting a challenge's reward gets the same weight instead
/// of the quiet bottom sheet it used to be.
///
/// Deliberately its own full-screen route rather than a modal sheet —
/// see [showAchievementUnlockCelebration]'s own doc for why this beat in
/// particular is worth a pause rather than a toast. Tint is
/// [SeenlyPalette.mustard] throughout rather than the plum `accent` the
/// other two moments use — the same color [ChallengeCard] and the old
/// reward sheet already used for anything challenge-shaped, so this
/// still reads as unmistakably "a challenge", not a level or a badge,
/// even at a glance.
///
/// Call sites: wherever a claim succeeds (see
/// screens/profile/challenges_screen.dart's `_claim` and Home's
/// `_ChallengesHomeCard._claim`) — await this before reloading the
/// list, the same "celebrate first, refresh after" order every other
/// claim flow in the app already follows.
Future<void> showChallengeClaimCelebration(BuildContext context, ChallengeClaim claim) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'challenge claimed'.tr,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, __) => _ChallengeClaimMoment(claim: claim),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _ChallengeClaimMoment extends StatefulWidget {
  final ChallengeClaim claim;
  const _ChallengeClaimMoment({required this.claim});

  @override
  State<_ChallengeClaimMoment> createState() => _ChallengeClaimMomentState();
}

class _ChallengeClaimMomentState extends State<_ChallengeClaimMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  // Same one-shot-per-showing haptic guards as _LevelUpMomentState /
  // _AchievementMintMomentState — this widget is deliberately a close
  // cousin of those two rather than sharing a base class with them; see
  // _LevelUpMomentState's own comment on why forcing a shared base
  // would cost more in conditionals than it'd save.
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
    final claim = widget.claim;
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Same choreography as the level-up / achievement moments —
          // wound-up spin easing to a clean stop, an elastic entrance
          // scale, a ray burst that blooms and fades, a spotlight sweep,
          // text rising in last. See _AchievementMintMomentState.build's
          // own comments for why these are read here inside the builder
          // rather than once in build().
          final spinT = _interval(0.0, 0.62, curve: Curves.easeOutCubic);
          final spinAngle = -(1 - spinT) * 2 * math.pi * 3;

          final scaleT = _interval(0.0, 0.55, curve: Curves.elasticOut);
          final entranceOpacity = _interval(0.0, 0.22, curve: Curves.easeOut);

          final rayWindow = _interval(0.32, 0.95, curve: Curves.linear);
          final rayEnvelope = math.sin(rayWindow.clamp(0.0, 1.0) * math.pi);

          final sweepT = _interval(0.5, 0.92, curve: Curves.easeInOut);
          final textT = _interval(0.58, 0.95, curve: Curves.easeOutCubic);

          // The one beat this moment has that level-up/achievement
          // don't: a small "+points" pill that pops in just after the
          // medallion lands, rather than the number only living in the
          // body text below — the reward is the points first and foremost, so
          // it gets its own little entrance instead of waiting in line.
          final xpT = _interval(0.5, 0.78, curve: Curves.easeOutBack);

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
                              color: SeenlyPalette.mustard,
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
                                          color: SeenlyPalette.mustard.withOpacity(0.55),
                                          blurRadius: 34,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: _ChallengeMedallion(
                                      iconKey: claim.challenge.iconKey,
                                      diameter: 128,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // The +points pill, pinned just off the medallion's
                            // lower-right, the same corner a coin's shine
                            // would catch — pops in with a small overshoot
                            // (elastic-ish via easeOutBack) then just sits,
                            // no fade-out, so it's still readable once the
                            // rays have faded.
                            Positioned(
                              right: 6,
                              bottom: 14,
                              child: Transform.scale(
                                scale: xpT,
                                alignment: Alignment.center,
                                child: Opacity(
                                  opacity: xpT.clamp(0.0, 1.0),
                                  child: _PointsPill(points: claim.pointsAwarded),
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
                                'челлендж выполнен'.tr,
                                style: SeenlyText.mono(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: SeenlyPalette.mustard,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                claim.challenge.title,
                                textAlign: TextAlign.center,
                                style: SeenlyText.serif(
                                  size: 22,
                                  weight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                LocaleService.appIsRussian
                                    ? (claim.leveledUp
                                        ? 'и новый уровень — ${claim.level}'
                                        : 'уровень ${claim.level} · всего ${claim.totalPoints}')
                                    : (claim.leveledUp
                                        ? 'and a new level — ${claim.level}'
                                        : 'level ${claim.level} · ${claim.totalPoints} in total'),
                                style: SeenlyText.mono(size: 11, color: Colors.white60),
                              ),
                              const SizedBox(height: 26),
                              Text(
                                'нажми, чтобы продолжить'.tr,
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

/// The +points pill next to the medallion — small, solid mustard, dark
/// text for contrast (the one place this moment sits text *on* the
/// accent color rather than beside it, so it needs to stay legible on
/// its own rather than relying on the dark backdrop).
class _PointsPill extends StatelessWidget {
  final int points;
  const _PointsPill({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: SeenlyPalette.mustard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: SeenlyPalette.mustard.withOpacity(0.5),
            blurRadius: 12,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Text(
        '+$points',
        style: SeenlyText.mono(
          size: 12.5,
          weight: FontWeight.w800,
          color: const Color(0xFF2E2723), // dark-roast ink, not theme-adaptive —
          // see _AchievementMintMomentState's backdrop comment: this pill
          // sits on a flat mustard fill regardless of theme, so its text
          // needs a color that reliably reads dark-on-gold rather than
          // one that would flip light in dark mode and disappear.
        ),
      ),
    );
  }
}

/// The badge itself: same paper-disc-with-a-ring language as
/// [_LevelMedallion] in level_up_celebration.dart, just with the
/// challenge's own icon centered instead of a level number — keeps the
/// three celebration moments (badge, level, challenge) reading as one
/// family of medallions rather than three different shapes.
class _ChallengeMedallion extends StatelessWidget {
  final String iconKey;
  final double diameter;
  const _ChallengeMedallion({required this.iconKey, required this.diameter});

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
              border: Border.all(color: SeenlyPalette.mustard, width: strokeWidth),
            ),
          ),
          Container(
            width: innerSize,
            height: innerSize,
            // Theme-adaptive `paper`, not the fixed `paperOnDark` the
            // backdrop uses — same pairing _LevelMedallion and
            // RoundBadgeMedallion already rely on (paper + an
            // equally-adaptive ring color always contrast correctly
            // together, in either theme), even though this medallion
            // happens to sit on a fixed-dark scrim here.
            decoration: BoxDecoration(
              color: SeenlyPalette.paper,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              challengeIcon(iconKey),
              size: diameter * 0.4,
              color: SeenlyPalette.mustard,
            ),
          ),
        ],
      ),
    );
  }
}
