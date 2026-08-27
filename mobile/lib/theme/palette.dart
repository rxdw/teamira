import 'package:flutter/material.dart';

import 'seenly_brightness.dart';

/// One immutable set of tokens — everything a screen needs to paint
/// itself. [SeenlyPalette] below holds one of these for light and one
/// for dark, and its ambient static getters (`SeenlyPalette.ink`,
/// `SeenlyPalette.accent`, ...) just forward to whichever is active, so
/// none of the app's existing call sites had to change to pick up dark
/// mode — only the handful that needed the *value* frozen at compile
/// time (a `const` widget, a constructor's default parameter) needed a
/// small local rework to resolve it at runtime instead.
class SeenlyColorSet {
  const SeenlyColorSet({
    required this.background,
    required this.paper,
    required this.cork,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.placeholder,
    required this.border,
    required this.dashedBorder,
    required this.accent,
    required this.accentOnAccent,
    required this.sage,
    required this.mustard,
    required this.coral,
    required this.pink,
    required this.periwinkle,
    required this.clay,
    required this.tapeRose,
    required this.tapeSage,
    required this.tapeMustard,
    required this.shadowColor,
    required this.shadowOpacity,
  });

  final Color background;
  final Color paper;
  final Color cork;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color placeholder;
  final Color border;
  final Color dashedBorder;
  final Color accent;
  final Color accentOnAccent;
  final Color sage;
  final Color mustard;
  final Color coral;
  final Color pink;
  final Color periwinkle;
  final Color clay;
  final Color tapeRose;
  final Color tapeSage;
  final Color tapeMustard;
  final Color shadowColor;
  final double shadowOpacity;
}

/// The Seenly palette: warm paper, not dark mode, not the "cinema ticket"
/// look from an earlier pass — a personal evening diary. One accent color
/// (plum) carries every actionable element; everything else is a neutral
/// paper tone or a categorical color (see [SeenlyPalette.mediaColor]).
///
/// Dark mode ("evening lamp") follows the same idea rather than switching
/// register: warm espresso-brown instead of the usual near-black, candle-
/// lit cream ink instead of pure white, the same plum accent lifted just
/// enough to stay legible. Every field below is an ambient getter that
/// resolves against [SeenlyBrightness.isDark] — see that file for why.
class SeenlyPalette {
  const SeenlyPalette._();

  static const SeenlyColorSet _light = SeenlyColorSet(
    background: Color(0xFFF5EFE4),
    paper: Color(0xFFFFFDF8),
    cork: Color(0xFFE9DBBF),
    ink: Color(0xFF4A3F38),
    inkMuted: Color(0xFF8A7A68),
    inkFaint: Color(0xFFA8967F),
    placeholder: Color(0xFFB3A48F),
    border: Color(0xFFE4D9C4),
    dashedBorder: Color(0xFFD8CBB4),
    accent: Color(0xFF7D5A6B),
    accentOnAccent: Color(0xFFF5E9EE),
    sage: Color(0xFF8FA382),
    mustard: Color(0xFFC99A4C),
    coral: Color(0xFFD85A30),
    pink: Color(0xFFD4537E),
    periwinkle: Color(0xFF7F77DD),
    clay: Color(0xFFB6704A),
    tapeRose: Color(0xFFD9B8A8),
    tapeSage: Color(0xFFC9D9BE),
    tapeMustard: Color(0xFFEAD9B8),
    shadowColor: Color(0xFF4A3F38),
    shadowOpacity: 0.07,
  );

  // "Evening lamp": a warm espresso room rather than a lit-up screen —
  // background/paper/cork stay in the same brown family as light mode's
  // ink, just inverted in role, so cards still read as "paper sitting on
  // a surface" instead of "panel floating on black". Categorical colors
  // (sage/mustard/coral/pink/periwinkle/clay) are each lifted in
  // lightness a touch from their light-mode values so they keep enough
  // contrast against the dark background without turning neon.
  static const SeenlyColorSet _dark = SeenlyColorSet(
    background: Color(0xFF211B18),
    paper: Color(0xFF2E2723),
    cork: Color(0xFF3B302A),
    ink: Color(0xFFF3EAE0),
    inkMuted: Color(0xFFC7B7A6),
    inkFaint: Color(0xFF97897B),
    placeholder: Color(0xFF6E6156),
    border: Color(0xFF473C34),
    dashedBorder: Color(0xFF554739),
    accent: Color(0xFFC495A5),
    accentOnAccent: Color(0xFF2E1B22),
    sage: Color(0xFFA6BC98),
    mustard: Color(0xFFDFAF64),
    coral: Color(0xFFE67D53),
    pink: Color(0xFFE0789A),
    periwinkle: Color(0xFF9F97F0),
    clay: Color(0xFFD08F63),
    tapeRose: Color(0xFF5C4038),
    tapeSage: Color(0xFF3E4A3A),
    tapeMustard: Color(0xFF4F4530),
    shadowColor: Color(0xFF000000),
    shadowOpacity: 0.28,
  );

  /// The explicit light set — used by [SeenlyAppTheme.light] (and
  /// anything else that needs "light, no matter what mode is active
  /// right now") to build its `ThemeData`. Everyday call sites should
  /// keep using the ambient getters below instead.
  static const lightColors = _light;

  /// The explicit dark set — same idea as [lightColors], for
  /// [SeenlyAppTheme.dark].
  static const darkColors = _dark;

  static SeenlyColorSet get _current =>
      SeenlyBrightness.isDark ? _dark : _light;

  // Paper
  static Color get background => _current.background; // page background
  static Color get paper => _current.paper; // cards, sheets
  static Color get cork => _current.cork; // pinboard-style surfaces

  // Ink
  static Color get ink => _current.ink; // primary text
  static Color get inkMuted => _current.inkMuted; // secondary text
  static Color get inkFaint => _current.inkFaint; // metadata, timestamps
  static Color get placeholder => _current.placeholder; // empty-state text

  // Structure
  static Color get border => _current.border;
  static Color get dashedBorder => _current.dashedBorder;

  // The one accent — every button, active tab, and filled heart uses this.
  static Color get accent => _current.accent; // plum
  static Color get accentOnAccent => _current.accentOnAccent; // text/icon on accent

  // Categorical colors — used to encode media type or mood, never decoration.
  static Color get sage => _current.sage;
  static Color get mustard => _current.mustard;
  static Color get coral => _current.coral;
  static Color get pink => _current.pink;
  static Color get periwinkle => _current.periwinkle;
  static Color get clay => _current.clay; // manga

  // Washi tape accents (polaroid corners)
  static Color get tapeRose => _current.tapeRose;
  static Color get tapeSage => _current.tapeSage;
  static Color get tapeMustard => _current.tapeMustard;

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
  static List<Color> get gridRotation => [
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
    final stops = [coral, mustard, sage, accent];
    final t = ((rating - 1) / 9).clamp(0.0, 1.0).toDouble(); // 1..10 -> 0.0..1.0
    final scaled = t * (stops.length - 1);
    final i = scaled.floor().clamp(0, stops.length - 2).toInt();
    final localT = scaled - i;
    return Color.lerp(stops[i], stops[i + 1], localT)!;
  }

  /// One soft shadow used on every card that should feel like it's
  /// resting on the paper rather than painted flat onto it — the profile
  /// header, stat tiles, and shelf grid all use this. Dark mode uses a
  /// true black shadow at higher opacity (a warm-brown shadow disappears
  /// against a warm-brown background) so cards still read as lifted.
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: _current.shadowColor.withOpacity(_current.shadowOpacity),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];
}
