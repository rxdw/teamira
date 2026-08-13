import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// A soft circular "% match" badge — used on Ask Teamira's results list.
/// Reuses [SeenlyPalette.ratingColor] (the same warm coral -> mustard ->
/// sage -> plum gradient the diary's heart ratings use) so a strong match
/// reads as visually consistent with "loved it" elsewhere in the app,
/// rather than inventing a new red/yellow/green scale just for this.
class MatchRing extends StatelessWidget {
  final int match; // 0-100
  final double size;

  const MatchRing({super.key, required this.match, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final clamped = match.clamp(0, 100);
    // 0-100 -> 1-10 so this can borrow the diary's existing rating gradient
    // instead of a second color scale.
    final color = SeenlyPalette.ratingColor((clamped / 10).ceil().clamp(1, 10));
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
              value: clamped / 100,
              strokeWidth: 3.5,
              backgroundColor: SeenlyPalette.border,
              valueColor: AlwaysStoppedAnimation(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '$clamped',
            style: SeenlyText.mono(size: size * 0.32, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
