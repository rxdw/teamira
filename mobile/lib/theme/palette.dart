import 'package:flutter/material.dart';

/// The Seenly palette: warm paper, not dark mode, not the "cinema ticket"
/// look from an earlier pass — a personal evening diary. One accent color
/// (plum) carries every actionable element; everything else is a neutral
/// paper tone or a categorical color (see [SeenlyPalette.mediaColor]).
class SeenlyPalette {
  const SeenlyPalette._();

  // Paper
  static const Color background = Color(0xFFF5EFE4); // page background
  static const Color paper = Color(0xFFFFFDF8); // cards, sheets
  static const Color cork = Color(0xFFE9DBBF); // pinboard-style surfaces

  // Ink
  static const Color ink = Color(0xFF4A3F38); // primary text
  static const Color inkMuted = Color(0xFF8A7A68); // secondary text
  static const Color inkFaint = Color(0xFFA8967F); // metadata, timestamps
  static const Color placeholder = Color(0xFFB3A48F); // empty-state text

  // Structure
  static const Color border = Color(0xFFE4D9C4);
  static const Color dashedBorder = Color(0xFFD8CBB4);

  // The one accent — every button, active tab, and filled heart uses this.
  static const Color accent = Color(0xFF7D5A6B); // plum
  static const Color accentOnAccent = Color(0xFFF5E9EE); // text/icon on accent

  // Categorical colors — used to encode media type or mood, never decoration.
  static const Color sage = Color(0xFF8FA382);
  static const Color mustard = Color(0xFFC99A4C);
  static const Color coral = Color(0xFFD85A30);
  static const Color pink = Color(0xFFD4537E);
  static const Color periwinkle = Color(0xFF7F77DD);
  static const Color clay = Color(0xFFB6704A); // manga

  // Washi tape accents (polaroid corners)
  static const Color tapeRose = Color(0xFFD9B8A8);
  static const Color tapeSage = Color(0xFFC9D9BE);
  static const Color tapeMustard = Color(0xFFEAD9B8);

  /// One color per media type, used consistently everywhere a poster/spine
  /// placeholder needs a fill (search results, shelves, diary thumbnails).
  static Color mediaColor(String mediaType) {
    switch (mediaType) {
      case 'movie':
        return coral;
      case 'series':
        return sage;
      case 'game':
        return periwinkle;
      case 'anime':
        return mustard;
      case 'book':
        return pink;
      case 'manga':
        return clay;
      default:
        return accent;
    }
  }

  /// A small rotating set of card colors for grids where many titles sit
  /// side by side (profile grid, collection shelves) so it doesn't read as
  /// a monotone wall — still only pulled from the palette above.
  static const List<Color> gridRotation = [
    accent,
    coral,
    sage,
    mustard,
    pink,
    periwinkle,
  ];

  static Color gridColorFor(int index) =>
      gridRotation[index % gridRotation.length];

  /// A warm gradient across the 1-10 rating scale — "rough night" through
  /// "loved it" — used anywhere a rating needs to *read* as a feeling
  /// rather than just a number: the diary jar's tickets, the drop
  /// animation, and the filled hearts themselves. Four palette colors
  /// already in use elsewhere in the app, interpolated continuously
  /// rather than snapped into hard buckets, so 6/10 and 7/10 sit visibly
  /// close together instead of jumping categories. Null/0 (not yet rated)
  /// falls back to a quiet neutral rather than picking either end.
  static Color ratingColor(int? rating) {
    if (rating == null || rating <= 0) return inkFaint;
    const stops = [coral, mustard, sage, accent];
    final t = ((rating - 1) / 9).clamp(0.0, 1.0).toDouble(); // 1..10 -> 0.0..1.0
    final scaled = t * (stops.length - 1);
    final i = scaled.floor().clamp(0, stops.length - 2).toInt();
    final localT = scaled - i;
    return Color.lerp(stops[i], stops[i + 1], localT)!;
  }

  /// One soft, warm-toned shadow used on every card that should feel like
  /// it's resting on the paper rather than painted flat onto it — the
  /// profile header, stat tiles, and shelf grid all use this.
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: ink.withOpacity(0.07),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];
}
