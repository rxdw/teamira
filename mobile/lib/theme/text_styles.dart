import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palette.dart';

/// Two typefaces, split by role — never mixed at the same call site:
///
/// - **headline** — Unbounded (w600+), used for screen titles, section
///   headers, card titles — any "main word" in the app. Picked
///   automatically by [serif] whenever a semibold-or-heavier weight is
///   requested, so every existing screenTitle/sectionTitle/cardTitle
///   call already gets it without having to change anything at those
///   call sites.
/// - **body** — Comfortaa, used for everything that isn't a header:
///   descriptions, notes, dates, counts, status strings, meta labels.
///   [serif] falls back to this at regular weight, and [mono] — kept
///   as the name the "factual" role (dates, runtimes, counts) call
///   sites already use — renders in this same body font too.
class SeenlyText {
  const SeenlyText._();

  // Legibility floors. Call sites across the app pass all sorts of
  // explicit sizes (some as small as 6.5-9px for "meta" labels, badges,
  // slider ends, etc.) that read as fine print rather than UI text.
  // Rather than hunt down every call site individually, both builders
  // below clamp up to these floors, so every label in the app becomes
  // readable in one place. Callers can still go *larger* than the floor
  // freely (screenTitle, big stats, etc. are unaffected).
  static const double _serifFloor = 13;
  static const double _monoFloor = 12;

  // Any weight at or above this counts as a heading and switches the
  // family from Comfortaa to Unbounded.
  static const FontWeight _headingThreshold = FontWeight.w600;

  // `italic` is still accepted so none of the hundreds of existing call
  // sites need to change, but it's ignored on purpose — slanted text
  // throughout the app didn't look good, so every style always renders
  // upright now regardless of what callers pass here.
  static TextStyle serif({
    double size = 15,
    Color? color,
    FontWeight weight = FontWeight.w500,
    bool italic = false,
    bool enforceFloor = true,
  }) {
    final resolvedSize =
        (enforceFloor && size < _serifFloor) ? _serifFloor : size;
    final isHeading = weight.index >= _headingThreshold.index;
    final builder = isHeading ? GoogleFonts.unbounded : GoogleFonts.comfortaa;
    return builder(
      fontSize: resolvedSize,
      color: color ?? SeenlyPalette.ink,
      fontWeight: weight,
      fontStyle: FontStyle.normal,
      height: 1.3,
      decoration: TextDecoration.none,
    );
  }

  static TextStyle mono({
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w400,
    bool enforceFloor = true,
  }) =>
      GoogleFonts.comfortaa(
        fontSize: (enforceFloor && size < _monoFloor) ? _monoFloor : size,
        color: color ?? SeenlyPalette.inkFaint,
        fontWeight: weight,
        height: 1.35,
        decoration: TextDecoration.none,
      );

  // A handful of named, reused combinations so screens don't reinvent sizes.
  static TextStyle get screenTitle =>
      serif(size: 26, weight: FontWeight.w600);
  static TextStyle get sectionTitle => serif(size: 16, weight: FontWeight.w600);
  static TextStyle get cardTitle => serif(size: 16, weight: FontWeight.w600, italic: true);
  static TextStyle get greeting =>
      serif(size: 15, italic: true, color: SeenlyPalette.accent);
  static TextStyle get metaLabel => mono(size: 12);
  static TextStyle get bodyText =>
      serif(size: 15, weight: FontWeight.w400, color: SeenlyPalette.ink);
}
