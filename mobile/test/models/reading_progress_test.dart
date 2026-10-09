// Unit tests for models/reading_progress.dart — the bookmark behind the
// reading tracker. The tracker's rules lean on two things: a bookmark with
// every counter at zero/null counts as "not started", and stepping a counter
// back to zero un-sets it (copyWith's clear flags) instead of storing 0.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/reading_progress.dart';

void main() {
  group('ReadingBookmark', () {
    test('parses the server shape, with nulls for untracked counters', () {
      final b = ReadingBookmark.fromJson({'volume': 7, 'chapter': null, 'page': null});
      expect(b.volume, 7);
      expect(b.chapter, isNull);
      expect(b.page, isNull);
      expect(b.isEmpty, isFalse);
    });

    test('an empty server answer is an empty bookmark', () {
      final b = ReadingBookmark.fromJson({'volume': null, 'chapter': null, 'page': null, 'updated_at': null});
      expect(b.isEmpty, isTrue);
      expect(ReadingBookmark.empty.isEmpty, isTrue);
    });

    test('zeros count as empty too', () {
      expect(const ReadingBookmark(volume: 0, chapter: 0, page: 0).isEmpty, isTrue);
    });

    test('copyWith changes one counter and leaves the others', () {
      const b = ReadingBookmark(volume: 7, chapter: 61);
      final next = b.copyWith(volume: 8);
      expect(next.volume, 8);
      expect(next.chapter, 61);
    });

    test('clear flags un-set a counter instead of storing zero', () {
      const b = ReadingBookmark(volume: 7, chapter: 61);
      final next = b.copyWith(volume: 0, clearVolume: true);
      expect(next.volume, isNull);
      expect(next.chapter, 61);
      expect(next.isEmpty, isFalse);
      expect(next.copyWith(clearChapter: true).isEmpty, isTrue);
    });
  });
}
