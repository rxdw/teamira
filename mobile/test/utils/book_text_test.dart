import 'package:flutter_test/flutter_test.dart';

import 'package:teamira/utils/book_text.dart';

/// The text rules of the PDF book: the bundled fonts have no emoji, and a
/// character they lack prints as an empty box.
void main() {
  group('pdfHasGlyph', () {
    test('Latin, Latin-1 and Cyrillic are covered', () {
      expect(pdfHasGlyph('a'.codeUnitAt(0)), isTrue);
      expect(pdfHasGlyph('è'.codeUnitAt(0)), isTrue);
      expect(pdfHasGlyph('«'.codeUnitAt(0)), isTrue);
      expect(pdfHasGlyph('я'.codeUnitAt(0)), isTrue);
      expect(pdfHasGlyph('ё'.codeUnitAt(0)), isTrue);
    });

    test('typographic marks the app writes are covered', () {
      for (final ch in ['—', '–', '…', '’', '“', '”', '№', '•']) {
        expect(pdfHasGlyph(ch.runes.first), isTrue, reason: ch);
      }
    });

    test('emoji and symbols are not', () {
      expect(pdfHasGlyph(0x1F600), isFalse); // 😀
      expect(pdfHasGlyph(0x2665), isFalse); // ♥
      expect(pdfHasGlyph(0xFE0F), isFalse); // variation selector
      expect(pdfHasGlyph(0x200D), isFalse); // zero-width joiner
    });
  });

  group('pdfSafe', () {
    test('null and empty come back empty', () {
      expect(pdfSafe(null), '');
      expect(pdfSafe(''), '');
    });

    test('plain text passes through', () {
      expect(pdfSafe('Мы смотрели «Амели» — и плакали'), 'Мы смотрели «Амели» — и плакали');
    });

    test('emoji are dropped and the gap they leave is closed', () {
      expect(pdfSafe('до слёз 😭 просто 🥹 спасибо'), 'до слёз просто спасибо');
    });

    test('an emoji-only line becomes empty', () {
      expect(pdfSafe('❤️🔥😂'), '');
    });

    test('a ZWJ sequence leaves no stray pieces', () {
      expect(pdfSafe('семья 👨‍👩‍👧 вместе'), 'семья вместе');
    });

    test('line breaks and runs of spaces fold into single spaces', () {
      expect(pdfSafe('  раз\n\nдва\t три   '), 'раз два три');
    });

    test('a non-breaking space is an ordinary space', () {
      expect(pdfSafe('раз\u00A0два'), 'раз два');
    });
  });

  group('pdfClip', () {
    test('a short string is left alone', () {
      expect(pdfClip('коротко', 20), 'коротко');
    });

    test('cuts on a word boundary when one is near the end', () {
      final out = pdfClip('один два три четыре пять', 12);
      expect(out, 'один два…');
      expect(out.length, lessThanOrEqualTo(12));
    });

    test('hard-cuts a string with no spaces', () {
      expect(pdfClip('abcdefghijklmnop', 8), 'abcdefg…');
    });
  });

  group('joinNames', () {
    test('one, two and three names', () {
      expect(joinNames(['Аня'], ru: true), 'Аня');
      expect(joinNames(['Аня', 'Миша'], ru: true), 'Аня и Миша');
      expect(joinNames(['Аня', 'Миша', 'Оля'], ru: true), 'Аня, Миша и Оля');
      expect(joinNames(['Anya', 'Misha', 'Olya'], ru: false), 'Anya, Misha and Olya');
    });

    test('no names is an empty string', () {
      expect(joinNames([], ru: true), '');
    });

    test('a name that is all emoji falls back rather than leaving a gap', () {
      expect(joinNames(['Аня', '😀'], ru: true), 'Аня и …');
      expect(joinNames(['😀', 'Миша'], ru: true, fallback: '?'), '? и Миша');
    });

    test('emoji are cleaned out of names', () {
      expect(joinNames(['Аня 🌸', 'Миша'], ru: true), 'Аня и Миша');
    });
  });
}
