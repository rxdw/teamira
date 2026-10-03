// Unit tests for models/watchlist_entry.dart — the "watched / plan to
// watch" shelf row backing Profile's grid.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/watchlist_entry.dart';

void main() {
  Map<String, dynamic> _baseJson() => {
        'id': 'w1',
        'media_id': '603',
        'media_type': 'movie',
        'source': 'tmdb',
        'title_ru': 'Матрица',
        'title_en': 'The Matrix',
        'status': 'watched',
      };

  group('WatchlistEntry.fromJson', () {
    test('parses a full row', () {
      final entry = WatchlistEntry.fromJson({
        ..._baseJson(),
        'poster_url': 'https://example.com/p.jpg',
        'year': 1999,
        'genres': ['Sci-Fi'],
        'rating': 8.7,
        'user_rating': 5,
        'note': 'great rewatch',
        'mood_tags': ['cozy night in'],
        'favorite_cast': [
          {'person_id': '6384', 'name': 'Keanu Reeves', 'character': null, 'photo_url': null},
        ],
        'watched_at': '2026-01-02T20:00:00',
        'is_favorite': true,
      });

      expect(entry.id, 'w1');
      expect(entry.userRating, 5);
      expect(entry.moodTags, ['cozy night in']);
      expect(entry.favoriteCast, hasLength(1));
      expect(entry.watchedAt, DateTime.parse('2026-01-02T20:00:00'));
      expect(entry.isFavorite, isTrue);
    });

    test('defaults optional collections/flags when absent', () {
      final entry = WatchlistEntry.fromJson(_baseJson());
      expect(entry.genres, isEmpty);
      expect(entry.moodTags, isEmpty);
      expect(entry.favoriteCast, isEmpty);
      expect(entry.isFavorite, isFalse);
      expect(entry.watchedAt, isNull);
    });

    test('a malformed watched_at parses to null instead of throwing', () {
      // DateTime.tryParse, not DateTime.parse — a corrupt/unexpected date
      // string must degrade gracefully (Profile just doesn't show a date)
      // rather than crash the whole shelf fetch over one bad row.
      final entry = WatchlistEntry.fromJson({
        ..._baseJson(),
        'watched_at': 'not-a-date',
      });
      expect(entry.watchedAt, isNull);
    });
  });

  group('WatchlistEntry.displayTitle', () {
    test('prefers the English title when present', () {
      final entry = WatchlistEntry.fromJson(_baseJson());
      expect(entry.displayTitle, 'The Matrix');
    });

    test('falls back to the Russian title when English is missing', () {
      final entry = WatchlistEntry.fromJson({
        ..._baseJson(),
        'title_en': null,
      });
      expect(entry.displayTitle, 'Матрица');
    });

    test('falls back to the Russian title when English is blank', () {
      final entry = WatchlistEntry.fromJson({
        ..._baseJson(),
        'title_en': '   ',
      });
      expect(entry.displayTitle, 'Матрица');
    });

    test('renders the em-dash placeholder when both titles are missing', () {
      final entry = WatchlistEntry.fromJson({
        ..._baseJson(),
        'title_en': null,
        'title_ru': null,
      });
      expect(entry.displayTitle, '—');
    });
  });
}
