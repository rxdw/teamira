import 'package:flutter_test/flutter_test.dart';

import 'package:teamira/models/evenings_book.dart';

/// The arithmetic behind the "book of your evenings" — parsing the server's
/// payload and the numbers on the book's "at a glance" page. What may go in
/// the book is the server's call (backend/tests/test_circle_review_book.py);
/// these pin what the client does with what it is given.

Map<String, dynamic> _person(
  String id, {
  int? rating,
  List<String> tags = const [],
  String? line,
  bool skipped = false,
}) =>
    {
      'user_id': id,
      'username': id,
      'is_you': id == 'a',
      'done': true,
      'skipped': skipped,
      'rating': rating,
      'tags': tags,
      'line': line,
    };

Map<String, dynamic> _review(
  String id, {
  String day = '2026-03-01',
  String created = '2026-03-01T20:00:00Z',
  double? average,
  int? spread,
  String verdict = 'solo',
  List<Map<String, dynamic>> people = const [],
  List<Map<String, dynamic>>? moments,
}) =>
    {
      'id': id,
      'origin': moments == null ? 'logged' : 'room',
      'media_id': 'm$id',
      'media_type': 'movie',
      'source': 'tmdb',
      'title_en': 'Title $id',
      'watched_on': day,
      'revealed': true,
      'i_am_done': true,
      'people': people,
      'summary': {
        'average': average,
        'spread': spread,
        'verdict': verdict,
        'rated_count': people.where((p) => p['rating'] != null).length,
        'shared_tags': <String>[],
      },
      'moments': moments,
      'moments_locked': false,
      'created_at': created,
      'expires_at': '2026-03-08T20:00:00Z',
    };

Map<String, dynamic> _moment(int ms, {bool shared = false, String top = 'warm'}) => {
      'position_ms': ms,
      'people': shared ? 2 : 1,
      'shared': shared,
      'count': 1,
      'top': top,
    };

EveningsBook _book(List<Map<String, dynamic>> reviews, {bool truncated = false}) => EveningsBook.fromJson({
      'people': [
        {'user_id': 'a', 'username': 'anya', 'display_name': 'Аня', 'is_you': true},
        {'user_id': 'b', 'username': 'misha', 'is_you': false},
      ],
      'reviews': reviews,
      'truncated': truncated,
    });

void main() {
  group('EveningsBook.fromJson', () {
    test('keeps the circle, the flag and the evenings', () {
      final book = _book([_review('1')], truncated: true);
      expect(book.people.map((p) => p.userId), ['a', 'b']);
      expect(book.people.first.isYou, isTrue);
      expect(book.truncated, isTrue);
      expect(book.isEmpty, isFalse);
      // Display name wins, the username is the fallback.
      expect(book.names, ['Аня', 'misha']);
    });

    test('an empty payload is an empty book, not an error', () {
      final book = EveningsBook.fromJson({});
      expect(book.isEmpty, isTrue);
      expect(book.people, isEmpty);
      expect(book.truncated, isFalse);
    });

    test('puts the evenings oldest first whatever order they arrive in', () {
      final book = _book([
        _review('late', day: '2026-05-01'),
        _review('early', day: '2026-01-10'),
        _review('mid', day: '2026-03-01'),
      ]);
      expect(book.reviews.map((r) => r.id), ['early', 'mid', 'late']);
    });

    test('two evenings on one day keep the order they were opened in', () {
      final book = _book([
        _review('second', day: '2026-03-01', created: '2026-03-01T22:30:00Z'),
        _review('first', day: '2026-03-01', created: '2026-03-01T19:00:00Z'),
      ]);
      expect(book.reviews.map((r) => r.id), ['first', 'second']);
    });
  });

  group('EveningsBookStats', () {
    test('an empty book has nothing to average', () {
      final stats = EveningsBookStats.of(_book([]));
      expect(stats.evenings, 0);
      expect(stats.average, isNull);
      expect(stats.first, isNull);
      expect(stats.last, isNull);
      expect(stats.best, isNull);
      expect(stats.topTags, isEmpty);
      expect(stats.perPerson, isEmpty);
    });

    test('the average counts each evening once, however many people rated it', () {
      final stats = EveningsBookStats.of(_book([
        _review('1', average: 8, verdict: 'close', people: [_person('a', rating: 8), _person('b', rating: 8)]),
        _review('2', day: '2026-03-02', average: 6, verdict: 'solo', people: [_person('a', rating: 6)]),
      ]));
      expect(stats.evenings, 2);
      expect(stats.average, 7);
    });

    test('the span runs from the first evening to the last', () {
      final stats = EveningsBookStats.of(_book([
        _review('1', day: '2026-02-14'),
        _review('2', day: '2026-09-30'),
      ]));
      expect(stats.first, DateTime(2026, 2, 14));
      expect(stats.last, DateTime(2026, 9, 30));
    });

    test('verdicts are tallied and solo evenings fall in none', () {
      final stats = EveningsBookStats.of(_book([
        _review('1', verdict: 'unison', average: 9),
        _review('2', day: '2026-03-02', verdict: 'unison', average: 8),
        _review('3', day: '2026-03-03', verdict: 'close', average: 7),
        _review('4', day: '2026-03-04', verdict: 'split', average: 6, spread: 5),
        _review('5', day: '2026-03-05', verdict: 'solo', average: 5),
      ]));
      expect(stats.unison, 2);
      expect(stats.close, 1);
      expect(stats.split, 1);
    });

    test('the best evening is the highest average; the latest wins a tie', () {
      final stats = EveningsBookStats.of(_book([
        _review('old', day: '2026-01-01', average: 9),
        _review('mid', day: '2026-02-01', average: 7),
        _review('new', day: '2026-03-01', average: 9),
      ]));
      expect(stats.best?.id, 'new');
    });

    test('the most disputed evening is the widest real disagreement', () {
      final stats = EveningsBookStats.of(_book([
        _review('a', day: '2026-01-01', verdict: 'split', average: 6, spread: 4),
        _review('b', day: '2026-02-01', verdict: 'split', average: 5, spread: 7),
        _review('c', day: '2026-03-01', verdict: 'split', average: 6, spread: 5),
      ]));
      expect(stats.mostDisputed?.id, 'b');
    });

    test('a near miss is not a dispute', () {
      final stats = EveningsBookStats.of(_book([
        _review('a', verdict: 'close', average: 7, spread: 3),
        _review('b', day: '2026-03-02', verdict: 'unison', average: 9, spread: 0),
      ]));
      expect(stats.mostDisputed, isNull);
    });

    test('tags are merged ignoring case, most used first, ties alphabetical', () {
      final stats = EveningsBookStats.of(_book([
        _review('1', people: [
          _person('a', rating: 8, tags: ['уют', 'смешно']),
          _person('b', rating: 8, tags: ['Уют', 'тревожно']),
        ]),
        _review('2', day: '2026-03-02', people: [
          _person('a', rating: 7, tags: ['уют', ' ']),
        ]),
      ]));
      expect(stats.topTags.map((t) => t.tag), ['уют', 'смешно', 'тревожно']);
      expect(stats.topTags.map((t) => t.count), [3, 1, 1]);
    });

    test('only the most used tags make the strip', () {
      final tags = [for (var i = 0; i < 12; i++) 'тег${i.toString().padLeft(2, '0')}'];
      final stats = EveningsBookStats.of(_book([
        _review('1', people: [_person('a', rating: 8, tags: tags)]),
      ]));
      expect(stats.topTags.length, EveningsBookStats.topTagsLimit);
    });

    test('each person gets their own mean, in the circle\'s order', () {
      final stats = EveningsBookStats.of(_book([
        _review('1', average: 7, people: [_person('b', rating: 6), _person('a', rating: 8)]),
        _review('2', day: '2026-03-02', average: 7, people: [_person('b', rating: 8), _person('a', rating: 6)]),
        _review('3', day: '2026-03-03', average: 10, people: [_person('a', rating: 10)]),
      ]));
      expect(stats.perPerson.map((p) => p.person.userId), ['a', 'b']);
      expect(stats.perPerson[0].average, 8);
      expect(stats.perPerson[0].rated, 3);
      expect(stats.perPerson[1].average, 7);
      expect(stats.perPerson[1].rated, 2);
    });

    test('someone who never rated is left off the per-person list', () {
      final stats = EveningsBookStats.of(_book([
        _review('1', average: 8, people: [
          _person('a', rating: 8),
          _person('b', tags: ['уют']),
        ]),
      ]));
      expect(stats.perPerson.map((p) => p.person.userId), ['a']);
    });

    test('moments: evenings with a timeline and how many were shared', () {
      final stats = EveningsBookStats.of(_book([
        _review('1', moments: [_moment(61000, shared: true), _moment(90000)]),
        _review('2', day: '2026-03-02', moments: [_moment(10000, shared: true), _moment(20000, shared: true)]),
        _review('3', day: '2026-03-03', moments: []),
        _review('4', day: '2026-03-04'),
      ]));
      expect(stats.momentEvenings, 2);
      expect(stats.sharedMoments, 3);
    });
  });
}
