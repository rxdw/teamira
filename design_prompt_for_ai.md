# Seenly — design system prompt for AI

Copy this into ChatGPT / Copilot / any AI design assistant:

---

Create a modern mobile app design for a warm personal evening diary / media tracker with a cozy paper-and-ink aesthetic. Use this exact design language and palette.

## Brand / visual direction
- Product name: Seenly
- Mood: cozy, warm, intimate, reflective, editorial, not cold or sterile
- Style: paper journal + soft evening mood + premium modern app UI
- Look and feel: warm paper background, soft shadows, subtle borders, calm typography, premium but personal
- Not: dark mode-first, harsh neon, gloomy fintech, ultra minimal corporate SaaS
- Primary metaphor: a diary / reading / watching / planning journal on paper, not a social feed

## Core palette
Use these exact values:

- background: #F5EFE4
- paper: #FFFDF8
- cork: #E9DBBF
- ink: #4A3F38
- inkMuted: #8A7A68
- inkFaint: #A8967F
- placeholder: #B3A48F
- border: #E4D9C4
- dashedBorder: #D8CBB4
- accent: #7D5A6B (plum)
- accentOnAccent: #F5E9EE
- sage: #8FA382
- mustard: #C99A4C
- coral: #D85A30
- pink: #D4537E
- periwinkle: #7F77DD
- clay: #B6704A
- tapeRose: #D9B8A8
- tapeSage: #C9D9BE
- tapeMustard: #EAD9B8

## Design logic
- There is one main accent color: plum (#7D5A6B), used for buttons, active states, filled hearts, selected UI, and important actions.
- Most surfaces are warm off-white or paper color.
- Ink is dark brown / warm charcoal for text.
- Secondary text is muted warm gray-brown.
- Category colors are used consistently for media types and mood mapping: movie = coral, series = sage, game = periwinkle, anime = mustard, book = pink, manga = clay.
- The app should feel like printed card layouts and soft paper objects resting on a warm board.
- Use gentle shadows with warm gray transparency, not harsh black shadows.

## Theme structure
- Use Material 3 theme with light mode as the default.
- Main app background: warm paper (#F5EFE4)
- Cards and sheets: white paper tone (#FFFDF8)
- App bars: background matches page background, no heavy elevation
- Buttons: rounded pill shapes, soft radius around 24px
- Inputs: filled boxes with paper surfaces, round corners around 14px
- Snackbars: dark warm ink background with paper text

## Exact code references from the project
Use these as direct design source material:

```dart
class SeenlyPalette {
  const SeenlyPalette._();

  static const Color background = Color(0xFFF5EFE4);
  static const Color paper = Color(0xFFFFFDF8);
  static const Color cork = Color(0xFFE9DBBF);

  static const Color ink = Color(0xFF4A3F38);
  static const Color inkMuted = Color(0xFF8A7A68);
  static const Color inkFaint = Color(0xFFA8967F);
  static const Color placeholder = Color(0xFFB3A48F);

  static const Color border = Color(0xFFE4D9C4);
  static const Color dashedBorder = Color(0xFFD8CBB4);

  static const Color accent = Color(0xFF7D5A6B);
  static const Color accentOnAccent = Color(0xFFF5E9EE);

  static const Color sage = Color(0xFF8FA382);
  static const Color mustard = Color(0xFFC99A4C);
  static const Color coral = Color(0xFFD85A30);
  static const Color pink = Color(0xFFD4537E);
  static const Color periwinkle = Color(0xFF7F77DD);
  static const Color clay = Color(0xFFB6704A);

  static const Color tapeRose = Color(0xFFD9B8A8);
  static const Color tapeSage = Color(0xFFC9D9BE);
  static const Color tapeMustard = Color(0xFFEAD9B8);
}
```

```dart
static ThemeData get light {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: SeenlyPalette.background,
    colorScheme: base.colorScheme.copyWith(
      primary: SeenlyPalette.accent,
      onPrimary: SeenlyPalette.accentOnAccent,
      surface: SeenlyPalette.paper,
      error: SeenlyPalette.coral,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: SeenlyPalette.background,
      foregroundColor: SeenlyPalette.ink,
      elevation: 0,
      centerTitle: false,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SeenlyPalette.accent,
        foregroundColor: SeenlyPalette.accentOnAccent,
        textStyle: SeenlyText.serif(italic: true, size: 14),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SeenlyPalette.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      hintStyle: SeenlyText.serif(color: SeenlyPalette.placeholder),
    ),
    useMaterial3: true,
  );
}
```

```dart
class SeenlyText {
  static TextStyle serif({
    double size = 15,
    Color color = SeenlyPalette.ink,
    FontWeight weight = FontWeight.w500,
    bool italic = false,
    bool enforceFloor = true,
  }) {
    final resolvedSize =
        (enforceFloor && size < 13) ? 13 : size;
    final isHeading = weight.index >= FontWeight.w600.index;
    final builder = isHeading ? GoogleFonts.unbounded : GoogleFonts.comfortaa;
    return builder(
      fontSize: resolvedSize,
      color: color,
      fontWeight: weight,
      fontStyle: FontStyle.normal,
      height: 1.3,
      decoration: TextDecoration.none,
    );
  }

  static TextStyle mono({
    double size = 12,
    Color color = SeenlyPalette.inkFaint,
    FontWeight weight = FontWeight.w400,
    bool enforceFloor = true,
  }) =>
      GoogleFonts.comfortaa(
        fontSize: (enforceFloor && size < 12) ? 12 : size,
        color: color,
        fontWeight: weight,
        height: 1.35,
        decoration: TextDecoration.none,
      );

  static TextStyle get screenTitle => serif(size: 26, weight: FontWeight.w600);
  static TextStyle get sectionTitle => serif(size: 16, weight: FontWeight.w600);
  static TextStyle get cardTitle => serif(size: 16, weight: FontWeight.w600, italic: true);
  static TextStyle get metaLabel => mono(size: 12);
}
```

## Typography
Use a two-font system:
- Heading / hero / section titles: Unbounded, semi-bold or bold
- Body / labels / meta / notes: Comfortaa

Important rules:
- Small text should not go below floor values for legibility
- All labels and metadata should stay readable and comfortable on mobile
- Avoid sharp geometric sans fonts; keep it friendly and organic
- Italics are optional but should not dominate; the app mainly uses upright text

Typical type usage:
- Screen titles: size around 26, semibold
- Section titles: size around 16, semibold
- Card titles: size around 16, semibold
- Body text: size around 15, regular
- Meta labels: size around 12, monoline-like rounded style

## Layout / component rules
- Use soft rounded cards and subtle separation lines.
- Keep spacing calm and airy; no dense compact layouts.
- Use paper-like surfaces with warm borders and low-contrast separation.
- Buttons should be clean, rounded, and high-clarity.
- Lists and frames should feel like pinned notes / bookmarks, not like a dashboard.
- Use subtle framing to suggest a physical notebook or scrapbook.

## UI examples to preserve
- The visual language should resemble a cozy journal app for media tracking and memory capture.
- Titles / cards may be grouped in shelves, collections, and watched lists.
- There should be a premium editorial feel, but not over-designed or luxury-brand sterile.
- The application should feel personal, warm, and lived-in.

## Abstract design summary
The app is a warm paper journal for media and personal taste. It mixes soft evening tones, a single plum accent, and a coherent set of media-category colors. The core philosophy is “personal archive on paper” rather than “dark app shell with accent colors”.

## Ready-to-use prompt
"Design a modern mobile app UI in the style of a cozy personal media diary. Use a warm paper background (#F5EFE4), paper cards (#FFFDF8), dark warm ink (#4A3F38), a plum accent (#7D5A6B), and category colors: sage (#8FA382), mustard (#C99A4C), coral (#D85A30), pink (#D4537E), periwinkle (#7F77DD), clay (#B6704A). The interface should feel like a premium physical journal, with soft shadows, rounded cards, subtle borders, and an intimate editorial aesthetic. Use Unbounded for headings and Comfortaa for body text. Keep it warm, calm, personal, and not too dark or clinical. Prioritize a cozy evening diary / archive / media tracking experience, with shelves, cards, lists, forms, and actions styled with soft paper surfaces and one dominant plum accent."

---

Also keep these design principles in mind when generating screens:
- Warm, low-contrast, high-readability palette
- Calm emotional tone
- Personal archive / diary aesthetic
- Elegant paper textures and simple structure
- Use accent sparingly and consistently
- Prefer gentle shadows over dramatic contrast
