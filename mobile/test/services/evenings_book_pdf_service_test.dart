import 'package:flutter_test/flutter_test.dart';

import 'package:teamira/models/evenings_book.dart';
import 'package:teamira/services/evenings_book_pdf_service.dart';
import 'package:teamira/services/locale_service.dart';

/// Smoke tests for the PDF "book of your evenings": the document has to come
/// out whole for the awkward inputs real circles produce — emoji in every
/// field, a company of six, hundreds of words in a line, no posters at all —
/// because a card taller than a page, or a glyph the font lacks, would
/// otherwise surface only when somebody taps the button.
///
/// Fonts and the mascot load from the asset bundle (declared in pubspec);
/// posters are the only network dependency and every test leaves `poster_url`
/// null, so nothing here touches the network.

Map<String, dynamic> _person(
  String id,
  String name, {
  int? rating = 8,
  List<String> tags = const ['уют'],
  String? line = 'очень тепло',
  bool skipped = false,
}) =>
    {
      'user_id': id,
      'username': id,
      'display_name': name,
      'is_you': id == 'u0',
      'done': true,
      'skipped': skipped,
      'rating': rating,
      'tags': tags,
      'line': line,
    };

Map<String, dynamic> _review(
  int n, {
  required List<Map<String, dynamic>> people,
  List<Map<String, dynamic>>? moments,
  String title = 'Амели',
  String? verdict,
  double? average = 8,
}) {
  final day = DateTime(2026, 1 + n % 9, 1 + n % 27);
  String two(int v) => v.toString().padLeft(2, '0');
  return {
    'id': 'r$n',
    'origin': moments == null ? 'logged' : 'room',
    'media_id': 'm$n',
    'media_type': ['movie', 'series', 'anime', 'game'][n % 4],
    'source': 'tmdb',
    'title_ru': title,
    'year': 2001,
    'watched_on': '${day.year}-${two(day.month)}-${two(day.day)}',
    'revealed': true,
    'i_am_done': true,
    'people': people,
    'summary': {
      'average': average,
      'spread': 1,
      'verdict': verdict ?? 'close',
      'rated_count': people.length,
      'shared_tags': <String>[],
    },
    'moments': moments,
    'moments_locked': false,
    'created_at': '2026-03-01T20:00:00Z',
    'expires_at': '2026-03-08T20:00:00Z',
  };
}

EveningsBook _book(int people, List<Map<String, dynamic>> reviews, {bool truncated = false}) => EveningsBook.fromJson({
      'people': [
        for (var i = 0; i < people; i++)
          {'user_id': 'u$i', 'username': 'u$i', 'display_name': 'Имя $i', 'is_you': i == 0},
      ],
      'reviews': reviews,
      'truncated': truncated,
    });

void expectPdf(List<int> bytes) {
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  expect(bytes.length, greaterThan(5000));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final ru in [true, false]) {
    group(ru ? 'ru' : 'en', () {
      setUp(() => LocaleService.contentPrefersRussian = ru);
      tearDown(() => LocaleService.contentPrefersRussian = false);

      test('a small book of a pair comes out as a PDF', () async {
        final book = _book(2, [
          _review(1, people: [_person('u0', 'Аня'), _person('u1', 'Миша', rating: 9, line: 'я бы пересмотрел')]),
          _review(2, people: [_person('u0', 'Аня', rating: 6), _person('u1', 'Миша', rating: 10)], verdict: 'split'),
          _review(3, people: [_person('u0', 'Аня')], moments: [
            {'position_ms': 61000, 'people': 2, 'shared': true, 'count': 3, 'top': 'funny'},
            {'position_ms': 90000, 'people': 1, 'shared': false, 'count': 1, 'top': 'sad'},
          ]),
        ]);
        expectPdf(await EveningsBookPdfService.build(book));
      });

      test('an empty book still makes a cover and a back cover', () async {
        expectPdf(await EveningsBookPdfService.build(_book(2, [])));
      });

      test('emoji in every field never reach the fonts', () async {
        final book = _book(2, [
          _review(1, title: '🎬 Кино 🍿', people: [
            _person('u0', 'Аня 🌸', tags: ['😭 слёзы', '🔥'], line: '🥹🥹🥹'),
            _person('u1', 'Миша', line: 'ну это просто 😂😂😂 ❤️‍🔥'),
          ]),
        ]);
        expectPdf(await EveningsBookPdfService.build(book));
      });

      test('an evening whose only words were emoji leaves no empty card', () async {
        final book = _book(2, [
          _review(1, people: [
            _person('u0', 'Аня', rating: null, tags: ['🔥'], line: '😭'),
            _person('u1', 'Миша', rating: null, tags: const [], line: '🥹'),
          ], average: null),
          _review(2, people: [_person('u0', 'Аня'), _person('u1', 'Миша')]),
        ]);
        expectPdf(await EveningsBookPdfService.build(book));
      });

      test('a company of six with long lines still fits a page per card', () async {
        final long = List.filled(80, 'очень длинная мысль').join(' ');
        final people = [for (var i = 0; i < 6; i++) _person('u$i', 'Человек $i', line: long, tags: ['раз', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь'])];
        final book = _book(6, [
          _review(1, people: people, moments: [
            for (var i = 0; i < 8; i++)
              {'position_ms': 30000 * (i + 1), 'people': 3, 'shared': true, 'count': 2, 'top': 'wow'},
          ]),
        ]);
        expectPdf(await EveningsBookPdfService.build(book));
      });

      test('a long book paginates (and notes truncation)', () async {
        final book = _book(
          2,
          [
            for (var i = 0; i < 60; i++)
              _review(i, people: [_person('u0', 'Аня', rating: 1 + i % 10), _person('u1', 'Миша', rating: 10 - i % 10)]),
          ],
          truncated: true,
        );
        expectPdf(await EveningsBookPdfService.build(book));
      });

      test('a title with no printable characters still prints', () async {
        final book = _book(2, [
          _review(1, title: '🎬', people: [_person('u0', 'Аня'), _person('u1', 'Миша')]),
        ]);
        expectPdf(await EveningsBookPdfService.build(book));
      });
    });
  }
}
