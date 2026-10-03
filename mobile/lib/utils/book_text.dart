/// Text helpers for the PDF "book of your evenings". Pure Dart — no Flutter,
/// no locale lookups — so they can be tested on their own.
///
/// Why they exist: the PDF fonts (assets/pdf_fonts) are Latin + Cyrillic
/// subsets with no emoji and no symbols. A character the font lacks is drawn
/// as an empty box, and people write emoji in their one-liners all the time.
/// Everything that comes from a person goes through [pdfSafe] before it is
/// drawn.

/// Whether the bundled PDF fonts have a glyph for this code point. Mirrors
/// the subset listed in assets/pdf_fonts/README.md: basic Latin, Latin-1,
/// the Cyrillic block (without the historic letters) and a handful of
/// typographic marks.
bool pdfHasGlyph(int cp) {
  if (cp >= 0x20 && cp <= 0x7E) return true; // basic Latin
  if (cp >= 0xA0 && cp <= 0xFF) return true; // Latin-1 (è, é, ü, «, » …)
  if (cp >= 0x400 && cp <= 0x45F) return true; // Cyrillic incl. ё
  return const {
    0x2013, // –
    0x2014, // —
    0x2018, // ‘
    0x2019, // ’
    0x201C, // “
    0x201D, // ”
    0x201E, // „
    0x2022, // •
    0x2026, // …
    0x2116, // №
    0x2192, // →
    0x2212, // −
  }.contains(cp);
}

/// [s] with every character the PDF fonts cannot draw removed (emoji,
/// variation selectors, zero-width joiners, exotic symbols), line breaks and
/// runs of spaces folded into single spaces, and the ends trimmed. An
/// emoji-only string comes back empty — callers decide what to print then.
String pdfSafe(String? s) {
  if (s == null || s.isEmpty) return '';
  final out = StringBuffer();
  var lastWasSpace = false;
  for (final cp in s.runes) {
    final isBreak = cp == 0x0A || cp == 0x0D || cp == 0x09 || cp == 0xA0;
    final c = isBreak ? 0x20 : cp;
    if (!pdfHasGlyph(c)) continue;
    if (c == 0x20) {
      if (lastWasSpace) continue;
      lastWasSpace = true;
    } else {
      lastWasSpace = false;
    }
    out.writeCharCode(c);
  }
  return out.toString().trim();
}

/// [s] cut to at most [max] characters, on a word boundary when there is one
/// in the last stretch, with an ellipsis. Meant for text that already went
/// through [pdfSafe]: that leaves no surrogate pairs, so a cut can never
/// land inside one.
String pdfClip(String s, int max) {
  if (max < 2 || s.length <= max) return s;
  var end = max - 1;
  final cut = s.substring(0, end);
  final space = cut.lastIndexOf(' ');
  if (space > max * 0.6) end = space;
  return '${s.substring(0, end).trimRight()}…';
}

/// Names for the cover: "Аня", "Аня и Миша", "Аня, Миша и Оля". Names are
/// cleaned of unprintable characters; one that is left empty falls back to
/// [fallback] so the cover never reads "Аня и ".
String joinNames(List<String> names, {required bool ru, String fallback = '…'}) {
  final clean = [
    for (final n in names) pdfSafe(n).isEmpty ? fallback : pdfSafe(n),
  ];
  if (clean.isEmpty) return '';
  if (clean.length == 1) return clean.first;
  final and = ru ? 'и' : 'and';
  if (clean.length == 2) return '${clean[0]} $and ${clean[1]}';
  return '${clean.sublist(0, clean.length - 1).join(', ')} $and ${clean.last}';
}
