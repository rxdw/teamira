import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

// Shared genre-picking widgets. Extracted verbatim from
// screens/decide/decide_filters_screen.dart (the "can't decide?" flow) so the
// release calendar's genre filter looks and behaves the same way — same
// scattered chips, same counts, same palette rotation.

/// Lays the genre chips out like a loosely scattered sheet — each one
/// given a small vertical lift and a slight tilt so the board doesn't
/// read as a tidy grid — while guaranteeing they never overlap or clip.
///
/// The previous version used [Stack]/[Positioned] on a fixed grid: chips
/// were nudged and rotated *after* their cell was assigned, so a big
/// jitter or steep rotation could push one chip into its neighbour's
/// cell. This version uses [Wrap] instead, which reserves real, actual
/// layout space for every child based on its measured size — so chips
/// can never overlap. The scattered feel comes entirely from per-chip
/// padding (the "lift") and a [Transform.rotate] (the "tilt"), both kept
/// small enough, and both padded around generously enough, that a
/// rotated chip's silhouette never reaches outside its own reserved box.
/// Every lift/tilt is derived deterministically from the chip's index in
/// a fixed shuffle order, so toggling a selection or a count refreshing
/// never makes the board jump — same input, same layout, every rebuild.
class ScatteredGenreField extends StatelessWidget {
  final List<String> genres;
  final Map<String, int> counts;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const ScatteredGenreField({
    required this.genres,
    required this.counts,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // A fixed shuffle order (not list order) so alphabetically adjacent
    // genres — which otherwise tend to share a first letter and read as
    // a little cluster — end up scattered across the board instead of
    // sitting next to each other.
    final order = [...genres]..shuffle(math.Random(7));

    Widget chip(String label) {
      // Called in the same, deterministic order every build (row-major
      // over the fixed shuffle), so a given label always gets the same
      // tilt/lift regardless of which layout branch below is used —
      // toggling a selection never makes the board jump.
      final rnd = math.Random(label.hashCode);
      final angle = (rnd.nextDouble() - 0.5) * 0.16; // ~ ±4.6°
      final liftTop = rnd.nextBool();
      final lift = 6 + rnd.nextDouble() * 8; // 6–14
      return Padding(
        padding: EdgeInsets.only(
          top: liftTop ? 4 : lift,
          bottom: liftTop ? lift : 4,
          left: 8,
          right: 8,
        ),
        child: Transform.rotate(
          angle: angle,
          child: GenreTag(
            label: label,
            count: counts[label] ?? 0,
            color: SeenlyPalette.gridColorFor(genres.indexOf(label)),
            active: selected.contains(label),
            onTap: () => onToggle(label),
          ),
        ),
      );
    }

    // A rough but precise-enough estimate of each chip's natural
    // on-screen width — same fonts/padding as [GenreTag] plus the
    // wrapper padding from `chip()` above — so column counts can be
    // compared without actually laying anything out first.
    double chipWidth(String label) {
      final count = counts[label] ?? 0;
      final labelPainter = TextPainter(
        text: TextSpan(text: label.toLowerCase(), style: SeenlyText.serif(size: 13, weight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final countPainter = TextPainter(
        text: TextSpan(text: '$count', style: SeenlyText.mono(size: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      // chip() wrapper padding (8+8) + GenreTag padding (14+14) +
      // border (~2) + label + inter-text gap (6) + count.
      return 16 + 28 + 2 + labelPainter.width + 6 + countPainter.width;
    }

    // One fixed vertical footprint per chip: GenreTag's own padding
    // and line height plus the largest possible lift/rotation padding
    // from `chip()` above — deliberately a slight over-estimate, so the
    // grid never ends up taller than expected once actually laid out.
    const chipHeight = 58.0;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final widths = {for (final label in order) label: chipWidth(label)};

      // Try a handful of column counts and, for each, work out how much
      // a single uniform scale could enlarge that arrangement before it
      // hit either edge of the available box. A short, wide area wants
      // few, wide columns; a tall, narrow one wants more, narrower
      // columns — picking whichever arrangement's own width-to-height
      // shape best matches the screen's is what actually lets the grid
      // fill it, instead of matching one axis and leaving the other
      // mostly empty.
      var bestCols = 1;
      var bestScale = 0.0;
      var bestRows = order.length;
      for (var cols = 1; cols <= math.min(4, order.length); cols++) {
        final rows = (order.length / cols).ceil();
        var maxRowWidth = 0.0;
        for (var r = 0; r < rows; r++) {
          var rowWidth = 0.0;
          for (var c = r * cols; c < (r + 1) * cols && c < order.length; c++) {
            rowWidth += widths[order[c]]!;
          }
          if (rowWidth > maxRowWidth) maxRowWidth = rowWidth;
        }
        final scale = math.min(width / maxRowWidth, height / (rows * chipHeight));
        if (scale > bestScale) {
          bestScale = scale;
          bestCols = cols;
          bestRows = rows;
        }
      }

      // If even the best arrangement would need real shrinking to fit,
      // there are simply too many genres for one screen — fall back to
      // a scrolling wrap at normal chip size instead of cramming.
      final fitsWithoutScroll = height.isFinite && bestScale >= 0.92;

      if (fitsWithoutScroll) {
        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < bestRows; r++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = r * bestCols; c < (r + 1) * bestCols && c < order.length; c++)
                        chip(order[c]),
                    ],
                  ),
              ],
            ),
          ),
        );
      }

      // Too many genres to fill one screen without cramming — fall back
      // to a scrolling wrap instead of squeezing rows unreadably thin.
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 2,
          children: [for (final label in order) chip(label)],
        ),
      );
    });
  }
}

/// A genre chip, sized and colored a bit more generously than the plain
/// [PillChip] — a soft tint of a rotating palette color plus a count, so
/// a wall of genre names doesn't read as flat gray text.
class GenreTag extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const GenreTag({
    required this.label,
    required this.count,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color : Color.alphaBlend(color.withOpacity(0.10), SeenlyPalette.paper),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? color : color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toLowerCase(),
              style: SeenlyText.serif(
                size: 13,
                weight: FontWeight.w600,
                color: active ? SeenlyPalette.accentOnAccent : SeenlyPalette.ink,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: SeenlyText.mono(
                size: 10,
                color: active ? SeenlyPalette.accentOnAccent.withOpacity(0.8) : SeenlyPalette.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
