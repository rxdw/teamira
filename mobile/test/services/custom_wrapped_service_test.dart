// Unit tests for services/custom_wrapped_service.dart — the on-device
// "Wrapped" computation used for an arbitrary custom date range (no
// backend support for that; see the class's own doc comment). Pure
// function of (title, range, entries) -> WrappedSummary, no
// network/widgets/SharedPreferences involved, so this is straightforward
// to test directly and thoroughly.
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/diary_entry.dart';
import 'package:teamira/services/custom_wrapped_service.dart';
import 'package:teamira/services/locale_service.dart';

DiaryEntry _entry({
  required DateTime watchedAt,
  String id = 'd',
  String mediaId = 'm',
  String mediaType = 'movie',
  bool isRewatch = false,
  int? rating,
  String? note,
  String? watchedWithUsername,
  int? episodesWatched,
  String? posterUrl,
  String titleEn = 'Title',
}) =>
    DiaryEntry(
      id: id,
      mediaId: mediaId,
      mediaType: mediaType,
      source: 'tmdb',
      titleEn: titleEn,
      posterUrl: posterUrl,
      rating: rating,
      note: note,
      watchedWithUsername: watchedWithUsername,
      episodesWatched: episodesWatched,
      isRewatch: isRewatch,
      watchedAt: watchedAt,
      createdAt: watchedAt,
    );

void main() {
  setUp(() => LocaleService.contentPrefersRussian = false);
  tearDown(() => LocaleService.contentPrefersRussian = false);

  group('CustomWrappedService.rangeLabel', () {
    test('collapses the year once when start and end share one', () {
      final label = CustomWrappedService.rangeLabel(
        DateTimeRange(start: DateTime(2026, 1, 3), end: DateTime(2026, 3, 10)),
      );
      expect(label, 'Jan 3 – Mar 10, 2026');
    });

    test('shows both years when the range crosses a new year', () {
      final label = CustomWrappedService.rangeLabel(
        DateTimeRange(start: DateTime(2025, 12, 20), end: DateTime(2026, 1, 5)),
      );
      expect(label, 'Dec 20 2025 – Jan 5 2026');
    });

    test('uses Russian day-then-month order and an em dash when preferred',
        () {
      LocaleService.contentPrefersRussian = true;
      final label = CustomWrappedService.rangeLabel(
        DateTimeRange(start: DateTime(2026, 1, 3), end: DateTime(2026, 3, 10)),
      );
      expect(label, '3 января — 10 марта 2026');
    });
  });

  group('CustomWrappedService.build — empty range', () {
    test('zero entries returns a well-formed, zeroed-out summary', () {
      final summary = CustomWrappedService.build(
        title: 'Empty',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        allEntries: const [],
      );
      expect(summary.totalLogged, 0);
      expect(summary.totalHours, 0);
      expect(summary.daysSpan, 31);
    });
  });

  group('CustomWrappedService.build — filtering by range', () {
    test('excludes entries watched outside the given range', () {
      final entries = [
        _entry(watchedAt: DateTime(2025, 12, 31, 23, 59)), // just before
        _entry(watchedAt: DateTime(2026, 1, 1, 0, 0)), // inclusive start
        _entry(watchedAt: DateTime(2026, 1, 31, 23, 59)), // inclusive end
        _entry(watchedAt: DateTime(2026, 2, 1, 0, 0)), // just after
      ];
      final summary = CustomWrappedService.build(
        title: 'January',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        allEntries: entries,
      );
      expect(summary.totalLogged, 2);
    });
  });

  group('CustomWrappedService.build — day-bucket timeline (BUG)', () {
    test(
        'two entries on the same day-of-month in different months of a '
        '<=62-day range must NOT be merged into one timeline bucket',
        () {
      // daysSpan here is 60 (Jan 1 -> Mar 1), which is <=62 -> day
      // buckets, not month buckets (see build()'s own "byDay" comment:
      // day buckets are meant for a *single*-month-ish stretch). One
      // entry lands on the 15th of January, another on the 15th of
      // February — different calendar days, but the same day-of-month.
      final entries = [
        _entry(watchedAt: DateTime(2026, 1, 15)),
        _entry(watchedAt: DateTime(2026, 2, 15)),
      ];
      final summary = CustomWrappedService.build(
        title: 'Two months',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 3, 1)),
        allEntries: entries,
      );

      expect(summary.totalLogged, 2);
      // The real bug: keying the day bucket by bare "15" (no month/year)
      // merges these into a single bucket with count 2, and
      // busiestTimelineLabel then reports "15" as though one single day
      // had two logs — losing the fact these were two separate evenings
      // a month apart. Correct behavior is two separate buckets of 1
      // each (both still labeled "15", since the label is deliberately
      // just the day-of-month — see WrappedTimelineBucket's own doc
      // comment — but they must be counted as distinct days).
      expect(summary.timeline, hasLength(2));
      for (final bucket in summary.timeline) {
        expect(bucket.label, '15');
        expect(bucket.count, 1);
      }
    });

    test('a real repeat on the exact same calendar day still merges correctly',
        () {
      // Two logs on the *same* day (e.g. a double feature) must still
      // count as one bucket with count 2 — the fix above must not
      // over-correct into treating every entry as its own bucket.
      final entries = [
        _entry(watchedAt: DateTime(2026, 1, 15, 14, 0)),
        _entry(watchedAt: DateTime(2026, 1, 15, 21, 0)),
      ];
      final summary = CustomWrappedService.build(
        title: 'Double feature',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 3, 1)),
        allEntries: entries,
      );
      expect(summary.timeline, hasLength(1));
      expect(summary.timeline.single.count, 2);
      expect(summary.busiestTimelineLabel, '15');
    });

    test('a range longer than 62 days buckets by month instead, unaffected by the day-key fix',
        () {
      final entries = [
        _entry(watchedAt: DateTime(2026, 1, 15)),
        _entry(watchedAt: DateTime(2026, 2, 15)),
        _entry(watchedAt: DateTime(2026, 3, 15)),
      ];
      final summary = CustomWrappedService.build(
        title: 'A whole quarter',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 3, 31)),
        allEntries: entries,
      );
      expect(summary.timeline, hasLength(3));
      expect(summary.timeline.map((b) => b.label), ['Jan', 'Feb', 'Mar']);
      for (final bucket in summary.timeline) {
        expect(bucket.count, 1);
      }
    });
  });

  group('CustomWrappedService.build — new vs. rewatch, solo vs. company', () {
    test('splits new logs from rewatches', () {
      final entries = [
        _entry(watchedAt: DateTime(2026, 1, 1), isRewatch: false),
        _entry(watchedAt: DateTime(2026, 1, 2), isRewatch: true),
        _entry(watchedAt: DateTime(2026, 1, 3), isRewatch: true),
      ];
      final summary = CustomWrappedService.build(
        title: 't',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        allEntries: entries,
      );
      expect(summary.newCount, 1);
      expect(summary.rewatchCount, 2);
    });

    test('soloCount counts entries with no watched-with partner', () {
      final entries = [
        _entry(watchedAt: DateTime(2026, 1, 1), watchedWithUsername: null),
        _entry(watchedAt: DateTime(2026, 1, 2), watchedWithUsername: 'alex'),
      ];
      final summary = CustomWrappedService.build(
        title: 't',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        allEntries: entries,
      );
      expect(summary.soloCount, 1);
      expect(summary.companyCount, 1);
      expect(summary.soloPercent, 50.0);
    });
  });

  group('CustomWrappedService.build — ratings', () {
    test('averageRating ignores unrated entries entirely (not counted as 0)',
        () {
      final entries = [
        _entry(watchedAt: DateTime(2026, 1, 1), rating: 10),
        _entry(watchedAt: DateTime(2026, 1, 2), rating: 8),
        _entry(watchedAt: DateTime(2026, 1, 3), rating: null),
      ];
      final summary = CustomWrappedService.build(
        title: 't',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        allEntries: entries,
      );
      // (10 + 8) / 2, not (10 + 8 + 0) / 3.
      expect(summary.averageRating, 9.0);
      expect(summary.reviewCount, 0); // none of these have a note
    });

    test('ratingHistogram omits ratings nobody actually gave', () {
      final entries = [
        _entry(watchedAt: DateTime(2026, 1, 1), rating: 10),
        _entry(watchedAt: DateTime(2026, 1, 2), rating: 10),
        _entry(watchedAt: DateTime(2026, 1, 3), rating: 7),
      ];
      final summary = CustomWrappedService.build(
        title: 't',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        allEntries: entries,
      );
      expect(summary.ratingHistogram, hasLength(2));
      final byRating = {for (final b in summary.ratingHistogram) b.rating: b.count};
      expect(byRating, {10: 2, 7: 1});
      expect(summary.fullMarksCount, 2);
    });
  });

  group('CustomWrappedService.build — streaks', () {
    test('longestStreakDays counts consecutive calendar days, not entries',
        () {
      final entries = [
        _entry(watchedAt: DateTime(2026, 1, 1)),
        _entry(watchedAt: DateTime(2026, 1, 2)),
        _entry(watchedAt: DateTime(2026, 1, 3)),
        // gap
        _entry(watchedAt: DateTime(2026, 1, 10)),
      ];
      final summary = CustomWrappedService.build(
        title: 't',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        allEntries: entries,
      );
      expect(summary.longestStreakDays, 3);
    });

    test('two logs on the same day count as one day toward the streak, not two',
        () {
      final entries = [
        _entry(watchedAt: DateTime(2026, 1, 1, 12, 0)),
        _entry(watchedAt: DateTime(2026, 1, 1, 20, 0)), // same day, second log
        _entry(watchedAt: DateTime(2026, 1, 2, 12, 0)),
      ];
      final summary = CustomWrappedService.build(
        title: 't',
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        allEntries: entries,
      );
      expect(summary.longestStreakDays, 2);
    });
  });
}
