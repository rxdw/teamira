import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// A soft circular "% match" badge — used on Ask Teamira's results list.
/// Reuses [SeenlyPalette.ratingColor] (the same warm coral -> mustard ->
/// sage -> plum gradient the diary's heart ratings use) so a strong match
/// reads as visually consistent with "loved it" elsewhere in the app,
/// rather than inventing a new red/yellow/green scale just for this.
///
/// With [animateIn] the ring fills and the number counts up from 0 to the
/// match once, on first build — used for the top pick, where the number is
/// the payoff of the whole "thinking" moment. It waits a beat first so the
/// card has finished fading in, and stays put when the system asks for
/// reduced motion. The colour is the final one from the start (a 94 doesn't
/// pass through coral on the way).
class MatchRing extends StatelessWidget {
  final int match; // 0-100
  final double size;
  final bool animateIn;
  // Ambient by default (SeenlyPalette.border) — fine for every normal
  // surface, which already sits on the ambient paper/background this
  // resolves against. The one place that isn't true is onboarding's
  // fixed dark "night" canvas (see onboarding_screen.dart's own header
  // comment on this exact class of bug): in dark app-mode, the ambient
  // border color is itself a dark brown and nearly vanishes against
  // onboarding's always-dark backdrop. Passing an explicit [trackColor]
  // there (e.g. a low-opacity white) sidesteps it the same way that
  // file's own _onboardingPaper alias does for text.
  final Color? trackColor;

  const MatchRing({
    super.key,
    required this.match,
    this.size = 46,
    this.animateIn = false,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = match.clamp(0, 100);
    if (animateIn && !MediaQuery.of(context).disableAnimations) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: clamped.toDouble()),
        duration: const Duration(milliseconds: 1300),
        // First quarter idle, then an ease-out count.
        curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
        builder: (context, shown, _) => _ring(clamped, shown),
      );
    }
    return _ring(clamped, clamped.toDouble());
  }

  /// [target] is the real match (decides the colour); [shown] is what the
  /// ring and the number display right now.
  Widget _ring(int target, double shown) {
    // 0-100 -> 1-10 so this can borrow the diary's existing rating gradient
    // instead of a second color scale.
    final color = SeenlyPalette.ratingColor((target / 10).ceil().clamp(1, 10));
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: shown / 100,
              strokeWidth: 3.5,
              backgroundColor: trackColor ?? SeenlyPalette.border,
              valueColor: AlwaysStoppedAnimation(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '${shown.round()}',
            style: SeenlyText.mono(size: size * 0.32, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
