import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/achievement.dart';
import '../services/achievement_seen_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'achievement_badge.dart';
import 'wow_effects.dart';
import '../services/app_translations.dart';

/// Fetches this account's achievements fresh, diffs the unlocked ones
/// against what [AchievementSeenService] already knows it's shown, and
/// plays [showAchievementUnlockCelebration] for anything genuinely new
/// — the single place that check happens, called right after any
/// action that could plausibly unlock something (almost always logging
/// an evening; see the `_confirmAndSave`-style methods in
/// screens/add_entry/*) as well as from [AchievementsScreen] itself for
/// anyone who unlocks something some other way and only notices on
/// their next visit there.
///
/// Best-effort and silent on failure, the same spirit as
/// [AppState.refreshLevel] most call sites already sit next to — a
/// network hiccup here should never block or fail the flow (typically
/// a diary save) that triggered it.
Future<void> checkAndCelebrateNewAchievements(BuildContext context) async {
  try {
    final app = context.read<AppState>();
    final userId = app.currentUser?.id;
    final r = await app.profile.achievements();
    final unlockedNow = r.achievements.where((a) => a.unlocked).map((a) => a.id).toSet();

    if (await AchievementSeenService.isFirstEverCheck(userId)) {
      // Never checked before on this device/account — baseline every
      // already-unlocked badge as seen without celebrating any of them.
      // See AchievementSeenService.isFirstEverCheck's own doc for why.
      await AchievementSeenService.markSeen(userId, unlockedNow);
      return;
    }

    final seen = await AchievementSeenService.seenIds(userId);
    final freshlyUnlocked =
        r.achievements.where((a) => a.unlocked && !seen.contains(a.id)).toList();
    if (freshlyUnlocked.isEmpty) return;

    await AchievementSeenService.markSeen(userId, freshlyUnlocked.map((a) => a.id));
    if (!context.mounted) return;
    await showAchievementUnlockCelebration(context, freshlyUnlocked);
  } catch (e, st) {
    // Best-effort — see the doc comment above. Still logged (debug builds
    // only) rather than swallowed completely: this whole pipeline is a
    // silent no-op on ANY failure (a bad token on app.profile.achievements(),
    // a JSON shape mismatch in Achievement.fromJson, SharedPreferences not
    // being ready yet, ...), which from the outside looks identical to
    // "the celebration just doesn't exist" — exactly the bug report this
    // is here to help catch instead of hide.
    if (kDebugMode) {
      debugPrint('checkAndCelebrateNewAchievements failed silently: $e\n$st');
    }
  }
}

/// Shows the "just unlocked" moment for one or more achievements, one
/// after another — the celebratory counterpart to [showBadgeDetailCard]
/// (which is the calm, read-only explanation of a badge; this is the
/// one time a badge gets to make an entrance). Call sites don't need to
/// know or care whether [achievements] has one item or five — the
/// overlay handles the queue itself, advancing on every tap until it's
/// through the list, then dismissing.
///
/// Deliberately its own full-screen route (barrier-blocking,
/// non-dismissible by tapping outside) rather than a snackbar/toast:
/// this is meant to be a beat the person actually pauses for, the same
/// weight [showBadgeDetailCard]'s centered card already carries, just
/// with real ceremony this time instead of quiet information.
Future<void> showAchievementUnlockCelebration(
  BuildContext context,
  List<Achievement> achievements,
) {
  if (achievements.isEmpty) return Future.value();
  return showGeneralDialog(
    context: context,
    barrierLabel: 'achievement unlocked',
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, __) => _MintQueue(achievements: achievements),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _MintQueue extends StatefulWidget {
  final List<Achievement> achievements;
  const _MintQueue({required this.achievements});

  @override
  State<_MintQueue> createState() => _MintQueueState();
}

class _MintQueueState extends State<_MintQueue> {
  int _index = 0;

  void _advance() {
    if (_index >= widget.achievements.length - 1) {
      Navigator.of(context).pop();
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.achievements[_index];
    return _AchievementMintMoment(
      // Re-keying per achievement restarts the whole entrance —
      // spin, rays, sweep, text — from zero for each one in the queue
      // rather than the second badge inheriting the first's
      // already-finished animation state.
      key: ValueKey(a.id),
      achievement: a,
      queueLabel: widget.achievements.length > 1
          ? '${_index + 1} / ${widget.achievements.length}'
          : null,
      onDismiss: _advance,
    );
  }
}

class _AchievementMintMoment extends StatefulWidget {
  final Achievement achievement;
  final String? queueLabel;
  final VoidCallback onDismiss;

  const _AchievementMintMoment({
    super.key,
    required this.achievement,
    required this.queueLabel,
    required this.onDismiss,
  });

  @override
  State<_AchievementMintMoment> createState() => _AchievementMintMomentState();
}

class _AchievementMintMomentState extends State<_AchievementMintMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  // One-shot flags so the mid-flight haptic and the "landed" haptic
  // each fire exactly once per showing rather than re-firing on every
  // rebuild the controller's own animation causes.
  bool _spunHaptic = false;
  bool _landedHaptic = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.selectionClick(); // the instant it appears
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
      HapticFeedback.heavyImpact(); // the coin "lands"
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  double _interval(double start, double end, {Curve curve = Curves.linear}) {
    // A hand-rolled Interval+curve read instead of constructing a
    // throwaway CurvedAnimation every call: this runs inside
    // AnimatedBuilder's builder, once per animation tick, so a fresh
    // CurvedAnimation object (which attaches itself as a listener to
    // _c on construction) every single frame would leak a listener
    // per tick for the life of the controller instead of computing a
    // plain number.
    final t = _c.value;
    if (end <= start) return t >= end ? 1.0 : 0.0;
    final normalized = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return curve.transform(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.achievement;
    final rarity = badgeRarityFromKey(a.rarity);

    return GestureDetector(
      onTap: widget.onDismiss,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Deliberately computed here, inside the builder, and not up
          // in the outer build() method: build() only runs once (right
          // after initState kicks _c.forward() off, with _c.value still
          // ~0), while this builder re-runs every tick because it's
          // wired to _c via `animation: _c` above. Reading _c.value up
          // in build() would freeze every one of these at whatever it
          // happened to be on that single call — which is exactly the
          // bug this replaced: the backdrop blur (unconditional, below)
          // would show immediately, but the badge, rays, and text would
          // stay locked at their t≈0 values forever since nothing was
          // ever re-reading _c as it actually advanced.

          // Spin: several full turns easing to a clean stop at angle 0
          // (not some odd multiple), so it always finishes facing
          // forward rather than occasionally landing mirrored. Wound up
          // before entrance rather than winding up live — the badge
          // appears already mid-spin and unwinds to a stop, which reads
          // as "arriving already in motion" rather than a visible
          // wind-up beat nobody asked for.
          final spinT = _interval(0.0, 0.62, curve: Curves.easeOutCubic);
          final spinAngle = -(1 - spinT) * 2 * math.pi * 3;

          // Entrance scale: a single elastic settle covers both "flies
          // in" and "coin drops with a little bounce" in one curve.
          final scaleT = _interval(0.0, 0.55, curve: Curves.elasticOut);
          final entranceOpacity = _interval(0.0, 0.22, curve: Curves.easeOut);

          // Rays bloom in, hold, then fade — a bell envelope over one
          // stretch of the timeline rather than GoldRayBurst's own
          // straight 0..1 ramp, since this needs it to also fade back
          // out.
          final rayWindow = _interval(0.32, 0.95, curve: Curves.linear);
          final rayEnvelope = math.sin(rayWindow.clamp(0.0, 1.0) * math.pi);

          final sweepT = _interval(0.5, 0.92, curve: Curves.easeInOut);
          final textT = _interval(0.58, 0.95, curve: Curves.easeOutCubic);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Backdrop — same blurred, dimmed treatment as
              // showBadgeDetailCard, just dimmer, since this moment
              // needs the rest of the screen to fully recede.
              //
              // Deliberately a fixed dark tone (the app's own "evening
              // lamp" dark-mode background, always, not the ambient
              // SeenlyPalette.ink) rather than the theme-adaptive ink
              // color showBadgeDetailCard/poster_lightbox use for the
              // same blur: those two only ever sit an *opaque* card or
              // photo on top, so the scrim's own color never has to
              // carry contrast by itself. This moment sits plain white
              // text with no card behind it, so the scrim has to
              // reliably read as dark no matter which theme is active —
              // SeenlyPalette.ink flips to a light cream in dark mode
              // (it's a *text* color, correctly light-on-dark there),
              // which would otherwise leave white text sitting on a
              // pale backdrop.
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: SeenlyPalette.darkColors.background
                      .withOpacity(0.72 * entranceOpacity),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: entranceOpacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.queueLabel != null) ...[
                        Text(widget.queueLabel!,
                            style: SeenlyText.mono(size: 11, color: Colors.white54)),
                        const SizedBox(height: 18),
                      ],
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            GoldRayBurst(
                              t: rayEnvelope,
                              color: rarity.color,
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
                                    // Extra glow specifically for the
                                    // unlock beat — bigger and warmer
                                    // than the badge's own resting
                                    // shadow (see AchievementBadge),
                                    // since this version needs to read
                                    // as "actively catching light" for
                                    // a couple of seconds, not sit
                                    // quietly in a grid.
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: rarity.color.withOpacity(0.55),
                                          blurRadius: 34,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: RoundBadgeMedallion(
                                      iconKey: a.iconKey,
                                      title: a.title,
                                      rarity: a.rarity,
                                      unlocked: true,
                                      diameter: 128,
                                      showLabel: false,
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
                                'achievement unlocked'.tr,
                                style: SeenlyText.mono(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: rarity.color,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                a.title,
                                textAlign: TextAlign.center,
                                style: SeenlyText.serif(
                                  size: 22,
                                  weight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                rarity.label,
                                style: SeenlyText.mono(size: 11, color: Colors.white60),
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
