import 'package:flutter/material.dart';

/// The co-viewing pair's own mascot art — two bunnies together. Purely
/// decorative: sits in a corner of a co-viewing surface (the Home
/// card, the co-viewing screen's own header) with no animation and no
/// tap target of its own, so it never competes with the real content or
/// the card's own tap handler.
///
/// Swaps in the dark-mode artwork
/// (assets/mascot/bunnies_coViewing_dark.png) whenever the app's theme
/// is dark, rather than always drawing the light pair.
///
/// The source art (assets/mascot/bunnies_coViewing.png) has the same
/// kind of transparent padding around the drawing that the companion
/// mascot's art does, so this crops in on it the same way — otherwise
/// it reads as small no matter what [size] is passed.
class CoViewingBunniesCorner extends StatelessWidget {
  final double size;
  const CoViewingBunniesCorner({super.key, this.size = 64});

  static const double _aspectRatio = 1336 / 1428;
  static const double _artFillFraction = 0.94;
  static const double _artContentHeightFrac = 1049 / 1428;
  static const double _cropScale = _artFillFraction / _artContentHeightFrac;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/mascot/bunnies_coViewing_dark.png'
        : 'assets/mascot/bunnies_coViewing.png';
    final height = size / _aspectRatio;
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: height,
        child: ClipRect(
          child: Transform.scale(
            scale: _cropScale,
            child: Image.asset(
              asset,
              width: size,
              height: height,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
