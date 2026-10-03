// Unit tests for models/diary_entry.dart — one row per logged evening,
// backing the Diary tab and the "your evenings with this film" timeline.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/diary_entry.dart';

void main() {
  Map<String, dynamic> _baseJson() => {
        'id': 'd1',
        'media_id': '603',
        'media_type': 'movie',
        'source': 'tmdb',
        'title_en': 'The Matrix',
        'is_rewatch': false,
        'watched_at': '2026-01-02T20:00:00',
        'created_at': '2026-01-02T20:05:00',
      };

  group('DiaryEntry.isEpisodeEntry', () {
    test('true only when both season and episode are set', () {
      final entry = DiaryEntry.fromJson({
        ..._baseJson(),
        'season': 1,
        'episode': 4,
      });
      expect(entry.isEpisodeEntry, isTrue);
    });

    test('false for a plain movie row with neither set', () {
      final entry = DiaryEntry.fromJson(_baseJson());
      expect(entry.isEpisodeEntry, isFalse);
    });

    test('false when only one of season/episode is set', () {
      // A half-populated row (shouldn't happen from the backend, but the
      // client-side getter must not crash or misclassify it as an
      // episode entry off partial data).
      final entry = DiaryEntry.fromJson({..._baseJson(), 'season': 1});
      expect(entry.isEpisodeEntry, isFalse);
    });
  });

  group('DiaryEntry.fromJson', () {
    test('parses rating, mood tags, and rewatch flag', () {
      final entry = DiaryEntry.fromJson({
        ..._baseJson(),
        'rating': 9,
        'note': 'Rewatched with the whole circle',
        'mood_tags': ['cozy night in', 'background noise'],
        'is_rewatch': true,
        'watched_with_username': 'alex',
      });
      expect(entry.rating, 9);
      expect(entry.moodTags, ['cozy night in', 'background noise']);
      expect(entry.isRewatch, isTrue);
      expect(entry.watchedWithUsername, 'alex');
    });

    test('defaults isRewatch to false when the backend omits it', () {
      final json = _baseJson()..remove('is_rewatch');
      final entry = DiaryEntry.fromJson(json);
      expect(entry.isRewatch, isFalse);
    });
  });

  group('DiaryEntry.displayTitle', () {
    test('falls back to Russian when English is absent', () {
      final entry = DiaryEntry.fromJson({
        ..._baseJson(),
        'title_en': null,
        'title_ru': 'Матрица',
      });
      expect(entry.displayTitle, 'Матрица');
    });
  });
}
