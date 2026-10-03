import 'package:flutter/material.dart';

import 'seenly_brightness.dart';
import 'seenly_flavor.dart';
import 'seenly_skin.dart';

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
    clay: Color(0xFFB97B62),
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

  // "Cozy diary" skin — the pastel, hand-drawn-paper look from Settings
  // > appearance > visual style: a blush cream page, a deep wine-plum
  // ink/accent instead of the standard skin's dustier plum, and the
  // same categorical colors pushed a shade warmer and more saturated so
  // washi tape, pills, and hearts read as *playful* rather than muted.
  // Still built on the exact same token set as the standard skin — every
  // call site that already reads SeenlyPalette.x picks this up for free,
  // no widget-level changes required.
  static const SeenlyColorSet _cozyLight = SeenlyColorSet(
    background: Color(0xFFF7ECDD),
    paper: Color(0xFFFFFBF2),
    cork: Color(0xFFE9D5B8),
    ink: Color(0xFF603B46),
    inkMuted: Color(0xFF946C70),
    inkFaint: Color(0xFFB99A99),
    placeholder: Color(0xFFC7AAA0),
    border: Color(0xFFEAD8C5),
    dashedBorder: Color(0xFFD9C0A8),
    accent: Color(0xFF8B5268),
    accentOnAccent: Color(0xFFFFF5F0),
    sage: Color(0xFF9AAE8A),
    mustard: Color(0xFFD4A55E),
    coral: Color(0xFFD98268),
    pink: Color(0xFFD991A5),
    periwinkle: Color(0xFF9A93D2),
    clay: Color(0xFFB6704A),
    tapeRose: Color(0xFFE7C3BF),
    tapeSage: Color(0xFFD0DCC7),
    tapeMustard: Color(0xFFEAD8B5),
    shadowColor: Color(0xFF603B46),
    shadowOpacity: 0.085,
  );

  // Cozy skin's own "evening lamp": the same blush-wine room carried
  // into dark mode rather than swapped out for the standard skin's
  // espresso-brown one, so choosing cozy still looks cozy after dark.
  // Categorical colors lifted the same way [_dark] lifts [_light]'s, to
  // keep contrast without turning neon.
  static const SeenlyColorSet _cozyDark = SeenlyColorSet(
    background: Color(0xFF241317),
    paper: Color(0xFF331B21),
    cork: Color(0xFF402029),
    ink: Color(0xFFF6E3DA),
    inkMuted: Color(0xFFD9B9AE),
    inkFaint: Color(0xFFA9847E),
    placeholder: Color(0xFF7A5750),
    border: Color(0xFF4A2830),
    dashedBorder: Color(0xFF5A323C),
    accent: Color(0xFFE5A6B8),
    accentOnAccent: Color(0xFF3A1620),
    sage: Color(0xFFA9C79C),
    mustard: Color(0xFFE3BB77),
    coral: Color(0xFFEE9068),
    pink: Color(0xFFEF9DB2),
    periwinkle: Color(0xFFA79EF2),
    clay: Color(0xFFD89A70),
    tapeRose: Color(0xFF5C2F34),
    tapeSage: Color(0xFF3A4A38),
    tapeMustard: Color(0xFF4E3A28),
    shadowColor: Color(0xFF000000),
    shadowOpacity: 0.30,
  );

  // "Clay" skin — kawaii claymorphism. A milky peach-and-strawberry room
  // instead of the old neon lavender: every surface is a soft, low-chroma
  // pastel (the way real polymer clay / candy-toy renders look), ink is a
  // cocoa-berry rather than black, and the single accent is a bubblegum
  // pink that carries every CTA. The categorical colours are candy pastels
  // (mint, butter, peach, sky-lilac) — friendly, never neon.
  //
  // shadowColor is a dusty rose, not a grey or the accent itself: the puffy
  // drop shadow in [SeenlyPalette.softShadow] / clay_kit.dart reads as a
  // warm tinted shadow beneath a soft object. The *inner* highlight and
  // shade that actually make the surface look like clay are painted by
  // ClayBoxDecoration (theme/clay_kit.dart).
  static const SeenlyColorSet _clayLight = SeenlyColorSet(
    background: Color(0xFFFFEFE9),
    paper: Color(0xFFFFF9F5),
    cork: Color(0xFFFAD9D0),
    ink: Color(0xFF5B3F4D),
    inkMuted: Color(0xFF8E6E7F),
    inkFaint: Color(0xFFB39AA6),
    placeholder: Color(0xFFC6AEB8),
    border: Color(0xFFF7DCD3),
    dashedBorder: Color(0xFFEFC9BF),
    accent: Color(0xFFEA6B9B),
    accentOnAccent: Color(0xFFFFFFFF),
    sage: Color(0xFF7ED1AD),
    mustard: Color(0xFFF7C862),
    coral: Color(0xFFFF9A7B),
    pink: Color(0xFFF79AC0),
    periwinkle: Color(0xFF9AA8F7),
    clay: Color(0xFFE2A480),
    tapeRose: Color(0xFFFFC9DC),
    tapeSage: Color(0xFFCDEEDC),
    tapeMustard: Color(0xFFFFE6A6),
    shadowColor: Color(0xFFD57C9C),
    shadowOpacity: 0.30,
  );

  // Clay skin's night mode: "candy at bedtime" — deep aubergine-cocoa
  // surfaces, the same pastels lifted just enough to glow softly against
  // them. shadowColor goes near-black: a coloured shadow reads as puffy on
  // a pale page but as murky on an already-dark one.
  static const SeenlyColorSet _clayDark = SeenlyColorSet(
    background: Color(0xFF2B2030),
    paper: Color(0xFF382B40),
    cork: Color(0xFF44344D),
    ink: Color(0xFFFFEFF4),
    inkMuted: Color(0xFFDCC3CF),
    inkFaint: Color(0xFFAD94A3),
    placeholder: Color(0xFF8D7784),
    border: Color(0xFF45364F),
    dashedBorder: Color(0xFF553F60),
    accent: Color(0xFFFF8FB6),
    accentOnAccent: Color(0xFF3B1830),
    sage: Color(0xFF8FDDBB),
    mustard: Color(0xFFFBD37B),
    coral: Color(0xFFFFA98C),
    pink: Color(0xFFFFA6C8),
    periwinkle: Color(0xFFA9B6FF),
    clay: Color(0xFFEFB794),
    tapeRose: Color(0xFF5A3049),
    tapeSage: Color(0xFF2F4A3D),
    tapeMustard: Color(0xFF4F422B),
    shadowColor: Color(0xFF150E1A),
    shadowOpacity: 0.50,
  );


  // Premium flavor: "апельсиновая" (orange/tangerine) — Settings >
  // appearance, next to system/light/dark. See seenly_flavor.dart for
  // why there's no dark variant. Two hard constraints shaped every
  // value below, both found in the actual screens that read this
  // palette rather than assumed:
  //  - `ink` doubles as the full-bleed backdrop color for the cinema/
  //    coach/garden logging rituals (screens/add_entry/*_log_screen.dart
  //    literally paint `backgroundColor: SeenlyPalette.ink`), so it has
  //    to stay genuinely dark here too, not a pale tint — the flavor
  //    only gets to pick *which* dark (burnt umber, not neutral brown).
  //  - The six categorical colors keep their existing hue family
  //    (sage=series stays green, mustard=anime stays gold, etc. — see
  //    `mediaColor` below) and just warm up, the same move `_cozyLight`
  //    already makes relative to `_light`. `coral` (movies) is pushed
  //    further toward red than usual so it doesn't collide with the
  //    orange accent sitting right next to it.
  static const SeenlyColorSet _orangeClassic = SeenlyColorSet(
    background: Color(0xFFFCEAD3),
    paper: Color(0xFFFFF8EC),
    cork: Color(0xFFF0D3A0),
    ink: Color(0xFF4A2E1C),
    inkMuted: Color(0xFF8C6A4A),
    inkFaint: Color(0xFFB08F68),
    placeholder: Color(0xFFC2A47C),
    border: Color(0xFFF0DAB0),
    dashedBorder: Color(0xFFE3C48C),
    accent: Color(0xFFE8823A),
    accentOnAccent: Color(0xFFFFF3E4),
    sage: Color(0xFF92A876),
    mustard: Color(0xFFD9A030),
    coral: Color(0xFFE2532A),
    pink: Color(0xFFDE5C82),
    periwinkle: Color(0xFF8078D9),
    clay: Color(0xFFC17A4A),
    tapeRose: Color(0xFFEFC3A0),
    tapeSage: Color(0xFFCFDCB0),
    tapeMustard: Color(0xFFF2DBA0),
    shadowColor: Color(0xFF4A2E1C),
    shadowOpacity: 0.08,
  );

  // Orange flavor + cozy skin — same relationship cozy always has to
  // classic (accent more saturated, ink pushed a shade deeper/warmer),
  // applied on top of the orange mood instead of the neutral one.
  static const SeenlyColorSet _orangeCozy = SeenlyColorSet(
    background: Color(0xFFFBE4C8),
    paper: Color(0xFFFFF6E8),
    cork: Color(0xFFF0CE96),
    ink: Color(0xFF5C3018),
    inkMuted: Color(0xFF96704A),
    inkFaint: Color(0xFFBB9668),
    placeholder: Color(0xFFCBA478),
    border: Color(0xFFF0D6A0),
    dashedBorder: Color(0xFFE0BC82),
    accent: Color(0xFFF0904A),
    accentOnAccent: Color(0xFFFFF3E0),
    sage: Color(0xFF9CB080),
    mustard: Color(0xFFE0A83C),
    coral: Color(0xFFE85C34),
    pink: Color(0xFFE4708E),
    periwinkle: Color(0xFF8D84E0),
    clay: Color(0xFFC4824E),
    tapeRose: Color(0xFFF2CBA8),
    tapeSage: Color(0xFFD6E0B8),
    tapeMustard: Color(0xFFF5E0A8),
    shadowColor: Color(0xFF5C3018),
    shadowOpacity: 0.09,
  );

  // Premium flavor: "клубничная" (strawberry). Same two constraints as
  // orange above — `ink` stays a genuinely dark wine-maroon (still
  // works as the log-flow backdrop color), and `pink` (books) is kept
  // noticeably lighter/rosier than the accent so the two read as two
  // different berries rather than one color repeated twice.
  static const SeenlyColorSet _strawberryClassic = SeenlyColorSet(
    background: Color(0xFFFCE7E4),
    paper: Color(0xFFFFF7F5),
    cork: Color(0xFFF0C9C0),
    ink: Color(0xFF4A1E24),
    inkMuted: Color(0xFF8C5C60),
    inkFaint: Color(0xFFB08488),
    placeholder: Color(0xFFC2989A),
    border: Color(0xFFF0D2CC),
    dashedBorder: Color(0xFFE0B0AA),
    accent: Color(0xFFE0344F),
    accentOnAccent: Color(0xFFFFEEF0),
    sage: Color(0xFF8CA87E),
    mustard: Color(0xFFD2A040),
    coral: Color(0xFFE2603A),
    pink: Color(0xFFEA5C84),
    periwinkle: Color(0xFF8078DC),
    clay: Color(0xFFB06850),
    tapeRose: Color(0xFFEFC0BC),
    tapeSage: Color(0xFFCEDCC0),
    tapeMustard: Color(0xFFF0DAB0),
    shadowColor: Color(0xFF4A1E24),
    shadowOpacity: 0.08,
  );

  // Strawberry flavor + cozy skin.
  static const SeenlyColorSet _strawberryCozy = SeenlyColorSet(
    background: Color(0xFFFADFDE),
    paper: Color(0xFFFFF3F2),
    cork: Color(0xFFF0BFB8),
    ink: Color(0xFF5C1E28),
    inkMuted: Color(0xFF96585E),
    inkFaint: Color(0xFFBB8084),
    placeholder: Color(0xFFCB9498),
    border: Color(0xFFF0CAC4),
    dashedBorder: Color(0xFFE0A8A0),
    accent: Color(0xFFEA3E5C),
    accentOnAccent: Color(0xFFFFEEF0),
    sage: Color(0xFF96B086),
    mustard: Color(0xFFDCA848),
    coral: Color(0xFFEA6840),
    pink: Color(0xFFF26890),
    periwinkle: Color(0xFF8D84E0),
    clay: Color(0xFFBC7256),
    tapeRose: Color(0xFFF4C8C4),
    tapeSage: Color(0xFFD6E0BC),
    tapeMustard: Color(0xFFF4E0B8),
    shadowColor: Color(0xFF5C1E28),
    shadowOpacity: 0.09,
  );

  static SeenlyColorSet _flavorSet(AppFlavor flavor) => switch (flavor) {
        AppFlavor.orange => SeenlySkin.isCozy ? _orangeCozy : _orangeClassic,
        AppFlavor.strawberry => SeenlySkin.isCozy ? _strawberryCozy : _strawberryClassic,
        AppFlavor.none => throw StateError('_flavorSet called with AppFlavor.none'),
      };

  /// The explicit light set for whichever skin is currently chosen —
  /// used by [SeenlyAppTheme.light] (and anything else that needs
  /// "light, no matter what brightness mode is active right now") to
  /// build its `ThemeData`. Everyday call sites should keep using the
  /// ambient getters below instead.
  /// A flavor is always-light (see seenly_flavor.dart), and
  /// [AppAppearance.themeMode] forces `ThemeMode.light` whenever one is
  /// chosen — so this is exactly the set `SeenlyAppTheme.light` (and so
  /// every already-mounted screen reading the ambient getters below)
  /// actually renders while a flavor is active. [darkColors] doesn't
  /// need the same check: nothing ever asks for it while a flavor is on.
  static SeenlyColorSet get lightColors {
    final flavor = SeenlyFlavor.current;
    if (flavor != AppFlavor.none) return _flavorSet(flavor);
    if (SeenlySkin.isCozy) return _cozyLight;
    if (SeenlySkin.isClay) return _clayLight;
    return _light;
  }

  /// The explicit dark set for whichever skin is currently chosen —
  /// same idea as [lightColors], for [SeenlyAppTheme.dark].
  static SeenlyColorSet get darkColors {
    if (SeenlySkin.isCozy) return _cozyDark;
    if (SeenlySkin.isClay) return _clayDark;
    return _dark;
  }

  static SeenlyColorSet get _current {
    final flavor = SeenlyFlavor.current;
    final isDark = SeenlyBrightness.isDark;
    // Flavors are always-light, so they only apply while the palette is
    // light (AppAppearance.themeMode forces light whenever one is chosen).
    if (flavor != AppFlavor.none && !isDark) {
      final f = _flavorSet(flavor);
      return SeenlyBrightness.videoBackdrop ? _forVideo(f, dark: false) : f;
    }
    final SeenlyColorSet base;
    if (SeenlySkin.isCozy) {
      base = isDark ? _cozyDark : _cozyLight;
    } else if (SeenlySkin.isClay) {
      base = isDark ? _clayDark : _clayLight;
    } else {
      base = isDark ? _dark : _light;
    }
    return SeenlyBrightness.videoBackdrop ? _forVideo(base, dark: isDark) : base;
  }

  // The video backdrop has both bright (~90% luminance) and dark patches,
  // and plenty of text sits straight on it with no card behind. Measured
  // over the footage's real frames at the old 50% scrim, secondary tones
  // fell to 1.4-2.4:1 in the dark sets and ~2:1 in the light ones. The
  // backdrop now scrims harder toward the palette's own background
  // (AppVideoBackground), and this pulls the secondary tones toward `ink`
  // so, together with the scrim values (0.64 dark / 0.68 light), primary
  // text holds >= ~4.1:1 and secondary tones ~3-4.6:1 against the worst 1% of
  // pixels. Light sets need the stronger pull: their mid-tone greys
  // (A8967F and friends) have little headroom against a light page.
  // Cached per base set: getters are read thousands of times per frame.
  static final Map<SeenlyColorSet, SeenlyColorSet> _videoSets = {};

  static SeenlyColorSet _forVideo(SeenlyColorSet b, {required bool dark}) =>
      _videoSets[b] ??= SeenlyColorSet(
        background: b.background,
        paper: b.paper,
        cork: b.cork,
        ink: b.ink,
        inkMuted: Color.lerp(b.inkMuted, b.ink, dark ? 0.40 : 0.60)!,
        inkFaint: Color.lerp(b.inkFaint, b.ink, dark ? 0.55 : 0.75)!,
        placeholder: Color.lerp(b.placeholder, b.inkMuted, 0.60)!,
        border: b.border,
        dashedBorder: b.dashedBorder,
        accent: b.accent,
        accentOnAccent: b.accentOnAccent,
        sage: b.sage,
        mustard: b.mustard,
        coral: b.coral,
        pink: b.pink,
        periwinkle: b.periwinkle,
        clay: b.clay,
        tapeRose: b.tapeRose,
        tapeSage: b.tapeSage,
        tapeMustard: b.tapeMustard,
        shadowColor: b.shadowColor,
        shadowOpacity: b.shadowOpacity,
      );

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

  // Shared shadow tokens for widgets that need a single BoxShadow color/opacity.
  static Color get shadowColor => _current.shadowColor;
  static double get shadowOpacity => _current.shadowOpacity;

  /// A permanently light "paper" tone that does NOT follow the active
  /// app theme — unlike the ambient [paper] getter above, which is meant
  /// for surfaces that sit on the page background and is deliberately a
  /// dark espresso-brown in dark mode.
  ///
  /// Some UI paints its own backdrop that never changes with the theme:
  /// a fixed dark scrim over a poster/video (trailer cards, the trailer
  /// reels feed) or a permanently dark "night" canvas (onboarding). Text
  /// and icons sitting on top of those need a color that stays light no
  /// matter what — reaching for the ambient [paper] there is a recurring
  /// bug, because it turns dark in dark mode and reads as near-invisible
  /// dark-on-dark against a backdrop that was already dark to begin with.
  static const Color paperOnDark = Color(0xFFFFFDF8);

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

  /// Shadow for the app's many flat, hairline-bordered "paper" cards
  /// (settings groups, list rows, source tiles...). Empty in the classic and
  /// cozy skins so those keep their flat bordered look exactly as before; in
  /// clay it is a slightly lighter version of [softShadow] so these cards
  /// also read as puffed-up clay instead of outlined rectangles.
  static List<BoxShadow> get flatCardShadow {
    if (!SeenlySkin.isClay) return const <BoxShadow>[];
    final dark = SeenlyBrightness.isDark;
    return <BoxShadow>[
      BoxShadow(
        color: _current.shadowColor.withOpacity(dark ? 0.36 : 0.20),
        blurRadius: 20,
        offset: const Offset(0, 9),
        spreadRadius: -3,
      ),
      BoxShadow(
        color: _current.shadowColor.withOpacity(dark ? 0.26 : 0.10),
        blurRadius: 5,
        offset: const Offset(0, 2),
      ),
      if (!dark)
        BoxShadow(
          color: Colors.white.withOpacity(0.9),
          blurRadius: 12,
          offset: const Offset(-4, -4),
        ),
    ];
  }

  /// One soft shadow used on every card that should feel like it's
  /// resting on the paper rather than painted flat onto it — the profile
  /// header, stat tiles, and shelf grid all use this. Dark mode uses a
  /// true black shadow at higher opacity (a warm-brown shadow disappears
  /// against a warm-brown background) so cards still read as lifted.
  /// Cozy skin spreads the same shadow wider and softer still (bigger
  /// blur, gentler opacity, a touch more drop) — a plush, sunk-into-a
  /// pillow feel rather than a crisp UI drop shadow.
  ///
  /// Clay skin goes further and stacks a *second* shadow: a soft light
  /// highlight on the corner opposite the (colored, not neutral) main
  /// shadow — the actual claymorphism trick that makes a plain rounded
  /// card read as puffed up off the page rather than merely shadowed
  /// underneath. Light-mode only (a light highlight over the clay dark
  /// set would just read as a stray bright smear, the same reason plain
  /// dark mode and cozy dark don't get one either).
  static List<BoxShadow> get softShadow {
    if (SeenlySkin.isClay) {
      // The same stack ClaySurface/ClayButton use — see ClayShadows in
      // theme/clay_kit.dart (kept inline here to avoid an import cycle).
      final dark = SeenlyBrightness.isDark;
      return <BoxShadow>[
        BoxShadow(
          color: _current.shadowColor.withOpacity(dark ? 0.42 : 0.26),
          blurRadius: 26,
          offset: const Offset(0, 12),
          spreadRadius: -3,
        ),
        BoxShadow(
          color: _current.shadowColor.withOpacity(dark ? 0.30 : 0.13),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
        if (!dark)
          BoxShadow(
            color: Colors.white.withOpacity(0.95),
            blurRadius: 16,
            offset: const Offset(-6, -6),
          ),
      ];
    }
    return [
      BoxShadow(
        color: _current.shadowColor
            .withOpacity(SeenlySkin.isCozy ? _current.shadowOpacity * 0.8 : _current.shadowOpacity),
        blurRadius: SeenlySkin.isCozy ? 22 : 14,
        offset: Offset(0, SeenlySkin.isCozy ? 6 : 4),
      ),
    ];
  }
}
