import 'package:flutter_test/flutter_test.dart';

import 'package:teamira/models/pair_album.dart';
import 'package:teamira/utils/album_dates.dart';

/// The Dart calendar rules must give the same answers as the backend's
/// (backend/app/pair_album.py, pinned by tests/test_pair_album.py::
/// TestDateMath): the "100 days" push and the screen it opens can't
/// disagree. The cases below are the same ones, in the same order.
void main() {
  group('anniversaries', () {
    test('a leap-day start celebrates on Feb 28 in common years', () {
      final start = DateTime(2024, 2, 29);
      expect(isAnniversaryToday(start, DateTime(2027, 2, 28)), isTrue);
      expect(isAnniversaryToday(start, DateTime(2028, 2, 29)), isTrue);
      expect(fullYears(start, DateTime(2027, 2, 27)), 2);
      expect(fullYears(start, DateTime(2027, 2, 28)), 3);
    });

    test('day one is not an anniversary; nextAnniversary skips to next year', () {
      final start = DateTime(2026, 9, 29);
      expect(isAnniversaryToday(start, start), isFalse);
      expect(nextAnniversary(start, start), DateTime(2027, 9, 29));
    });

    test('nextAnniversary is today when today is one, else the coming one', () {
      expect(nextAnniversary(DateTime(2025, 10, 5), DateTime(2026, 10, 5)), DateTime(2026, 10, 5));
      expect(nextAnniversary(DateTime(2026, 3, 1), DateTime(2026, 9, 29)), DateTime(2027, 3, 1));
      expect(nextAnniversary(DateTime(2024, 2, 29), DateTime(2026, 1, 1)), DateTime(2026, 2, 28));
    });
  });

  group('day counts', () {
    test('the first day is day 1 and the 100th calendar day is a milestone', () {
      final start = DateTime(2026, 1, 1);
      expect(daysTogether(start, start), 1);
      expect(milestoneToday(start, DateTime(2026, 4, 10)), 100);
      expect(milestoneToday(start, DateTime(2026, 4, 11)), isNull);
    });

    test('next milestone lands on the right day', () {
      final next = nextDayMilestone(DateTime(2026, 1, 1), DateTime(2026, 9, 29));
      expect(next, isNotNull);
      expect(next!.days, 300);
      expect(next.on, DateTime(2026, 10, 27));
    });

    test('daysBetween ignores DST shifts', () {
      // A plain Duration.inDays across a spring-forward can be off by one.
      expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    });
  });

  test('yearProgress runs 0..1 across a year of togetherness', () {
    final start = DateTime(2025, 1, 1);
    expect(yearProgress(start, DateTime(2026, 1, 1)), 0.0);
    final mid = yearProgress(start, DateTime(2026, 7, 2));
    expect(mid, greaterThan(0.45));
    expect(mid, lessThan(0.55));
  });

  test('Russian plurals, including the 11–14 exception', () {
    String years(int n) => '$n ${ruPlural(n, 'год', 'года', 'лет')}';
    expect(years(1), '1 год');
    expect(years(3), '3 года');
    expect(years(11), '11 лет');
    expect(years(21), '21 год');
    expect(years(112), '112 лет');
  });

  group('wire format', () {
    test('a calendar day round-trips without a timezone', () {
      expect(albumDayToWire(DateTime(2026, 9, 5)), '2026-09-05');
      expect(parseAlbumDay('2026-09-05'), DateTime(2026, 9, 5));
      expect(parseAlbumDay(null), isNull);
      expect(parseAlbumDay('nope'), isNull);
    });

    test('a sealed note arrives with no text and stays that way', () {
      final page = AlbumPage.fromJson({
        'source': 'tmdb',
        'media_id': '603',
        'media_type': 'movie',
        'round': 1,
        'state': 'waiting',
        'mine': null,
        'partner': null,
        'partner_sealed': true,
      });
      expect(page.revealed, isFalse);
      expect(page.partnerSealed, isTrue);
      expect(page.partner, isNull);
      expect(page.key, 'tmdb:603');
    });

    test('a sealed capsule carries no letters', () {
      final c = Capsule.fromJson({
        'id': 'c1',
        'opens_on': '2027-09-29',
        'created_at': '2026-09-29T10:00:00Z',
        'created_by_me': true,
        'state': 'sealed',
        'days_left': 365,
        'my_letter_sealed': true,
        'partner_letter_sealed': false,
        'letters': [],
        'opened_by_me': false,
        'can_delete': true,
      });
      expect(c.isOpen, isFalse);
      expect(c.ready, isFalse);
      expect(c.letters, isEmpty);
    });
  });
}
