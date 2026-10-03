import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palette.dart';
import 'seenly_skin.dart';

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
    if (isHeading && SeenlySkin.isCozy) {
      // Cozy skin's headings are set in Caveat — an actual cursive,
      // hand-lettered face (full Cyrillic included, not just Latin) —
      // instead of the standard skin's geometric Unbounded. This is the
      // one call site where "cozy diary" should look literally
      // handwritten rather than just rounded/bubbly.
      //
      // A script face reads noticeably smaller than a geometric one at
      // the same pixel size (thin strokes, no fixed cap-height block),
      // so every heading is scaled up ~30% to land at the same visual
      // weight the rest of the layout (padding, icon sizes, FittedBox
      // shrink targets) was tuned for. Caveat only ships 400-700; a
      // "w600 heading" and a "w800 emphasis" would otherwise both
      // collapse onto the same 700 weight, so anything w700+ also gets
      // a darker ink tint to keep the *emphasis* legible even though
      // the weight itself can't go any bolder.
      final extraBold = weight.index >= FontWeight.w800.index;
      return GoogleFonts.caveat(
        fontSize: resolvedSize * 1.3,
        color: color ?? SeenlyPalette.ink,
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.normal,
        height: 1.05,
        letterSpacing: extraBold ? 0.2 : 0,
        decoration: TextDecoration.none,
      );
    }
    final builder = isHeading ? GoogleFonts.unbounded : GoogleFonts.comfortaa;
    if (SeenlySkin.isClay) {
      // Clay's voice: Nunito — soft round terminals, chunky at w800/w900,
      // and (unlike the Fredoka/Quicksand pair this skin used before) it
      // actually ships Cyrillic. The Russian interface was silently falling
      // back to the platform font for every clay heading and label, which is
      // a big part of why the skin looked broken. Headings are pushed to
      // w800+ for the "puffy" feel; body text sits at w600+ so thin strokes
      // never look scratchy against the pastel surfaces.
      final FontWeight w = isHeading
          ? (weight.index >= FontWeight.w800.index ? FontWeight.w900 : FontWeight.w800)
          : (weight.index < FontWeight.w600.index ? FontWeight.w600 : weight);
      return GoogleFonts.nunito(
        fontSize: resolvedSize,
        color: color ?? SeenlyPalette.ink,
        fontWeight: w,
        fontStyle: FontStyle.normal,
        height: isHeading ? 1.2 : 1.32,
        letterSpacing: isHeading ? -0.1 : 0,
        decoration: TextDecoration.none,
      );
    }
    return builder(
      fontSize: resolvedSize,
      color: color ?? SeenlyPalette.ink,
      fontWeight: weight,
      fontStyle: FontStyle.normal,
      height: 1.3,
      decoration: TextDecoration.none,
    );
  }

  /// The app's one consistent "empty state" voice — "no collections
  /// available right now", "nothing logged yet", and so on, everywhere
  /// from Collections to Search to Profile. Centralized (rather than
  /// each screen calling [serif] with the same italic/placeholder pair
  /// directly) specifically so it can become a genuinely different,
  /// warmer voice in Cozy Diary — a jotted note rather than a system
  /// message — without having to touch every call site again later.
  static TextStyle emptyState({double size = 15, Color? color}) {
    final resolvedColor = color ?? SeenlyPalette.placeholder;
    if (SeenlySkin.isCozy) {
      return handwrittenNote(size: size + 2, color: resolvedColor);
    }
    return serif(italic: true, size: size, color: resolvedColor);
  }

  /// The literal date stamp at the top of each diary day-group ("today",
  /// "June 2") — handwritten like every other cozy heading, but
  /// deliberately calmer than [screenTitle]/[sectionTitle]: a medium
  /// weight rather than bold, and sized down a touch, so a date reads
  /// as a quiet note jotted in the margin rather than shouting as loud
  /// as the page's actual title. Falls back to the standard skin's
  /// regular heading treatment otherwise.
  static TextStyle diaryDate({double size = 17, Color? color}) {
    if (!SeenlySkin.isCozy) {
      return serif(size: size, weight: FontWeight.w700, color: color);
    }
    return GoogleFonts.caveat(
      fontSize: size * 1.15,
      color: color ?? SeenlyPalette.ink,
      fontWeight: FontWeight.w600,
      height: 1.1,
      decoration: TextDecoration.none,
    );
  }

  /// A margin-note / sticky-note voice — Caveat at body size rather than
  /// heading size, for the odd bit of copy that should look *jotted*
  /// rather than typed even though it isn't a heading: empty states
  /// ("nothing here yet"), banners, little asides. Cozy skin only —
  /// falls back to [serif]'s regular body face otherwise, since the
  /// standard skin has no handwritten register to switch into.
  static TextStyle handwrittenNote({
    double size = 17,
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) {
    if (!SeenlySkin.isCozy) {
      return serif(size: size, color: color, weight: weight);
    }
    return GoogleFonts.caveat(
      fontSize: size * 1.25,
      color: color ?? SeenlyPalette.ink,
      fontWeight: weight.index >= FontWeight.w600.index
          ? FontWeight.w600
          : FontWeight.w500,
      height: 1.15,
      decoration: TextDecoration.none,
    );
  }

  static TextStyle mono({
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w400,
    bool enforceFloor = true,
  }) {
    final resolvedSize = (enforceFloor && size < _monoFloor) ? _monoFloor : size;
    final builder = SeenlySkin.isClay ? GoogleFonts.nunito : GoogleFonts.comfortaa;
    return builder(
      fontSize: resolvedSize,
      color: color ?? SeenlyPalette.inkFaint,
      fontWeight: SeenlySkin.isClay && weight.index < FontWeight.w700.index ? FontWeight.w700 : weight,
      height: 1.35,
      decoration: TextDecoration.none,
    );
  }

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
