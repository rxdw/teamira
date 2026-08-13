import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// One heart per point on the scale (now 1-10, up from the original 1-5) —
/// wraps rather than sitting in a single Row so ten hearts never overflow
/// a narrow row the way five always safely did. Filled hearts pick up
/// [SeenlyPalette.ratingColor] for the current value, so a 9/10 genuinely
/// looks warmer than a 3/10 rather than every rating being the same plum.
class HeartRating extends StatelessWidget {
  final int value; // 0-10
  final int max;
  final double size;
  final ValueChanged<int>? onChanged; // null = read-only

  const HeartRating({
    super.key,
    required this.value,
    this.max = 10,
    this.size = 15,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filledColor = SeenlyPalette.ratingColor(value > 0 ? value : null);
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (int i = 1; i <= max; i++)
          GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(i),
            child: Icon(
              i <= value ? Icons.favorite : Icons.favorite_border,
              size: size,
              color: i <= value ? filledColor : SeenlyPalette.dashedBorder,
            ),
          ),
      ],
    );
  }
}
