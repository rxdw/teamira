// Unit tests for utils/release_day_groups.dart and
// ReleaseCalendarItem.releaseDay — the day bucketing behind the
// full-screen release calendar's sticky date headers.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/media_item.dart';
import 'package:teamira/models/release_calendar_item.dart';
import 'package:teamira/utils/release_day_groups.dart';

ReleaseCalendarItem _item(String date, {String title = 'x', String type = 'movie'}) =>
    ReleaseCalendarItem(
      source: 'tmdb',
      mediaType: type,
      releaseDate: date,
      title: LocalizedText(en: title),
    );

void main() {
  group('ReleaseCalendarItem.releaseDay', () {
    test('a plain ISO date is that same local day at midnight', () {
      expect(_item('2026-09-25').releaseDay, DateTime(2026, 9, 25));
    });

    test('a datetime with an offset lands on the device-local day', () {
      const raw = '2026-09-25T23:30:00+09:00';
      final local = DateTime.parse(raw).toLocal();
      expect(_item(raw).releaseDay, DateTime(local.year, local.month, local.day));
    });

    test('unparseable dates have no day', () {
      expect(_item('soon').releaseDay, isNull);
    });
  });

  group('groupReleasesByDay', () {
    test('buckets by day, oldest day first, keeping order within a day', () {
      final groups = groupReleasesByDay([
        _item('2026-10-02', title: 'c'),
        _item('2026-09-25', title: 'a'),
        _item('2026-10-02', title: 'd'),
        _item('2026-09-25', title: 'b'),
      ]);

      expect(groups.map((g) => g.day), [DateTime(2026, 9, 25), DateTime(2026, 10, 2)]);
      expect(groups[0].items.map((e) => e.title.en), ['a', 'b']);
      expect(groups[1].items.map((e) => e.title.en), ['c', 'd']);
    });

    test('drops rows whose date does not parse', () {
      final groups = groupReleasesByDay([_item('2026-09-25'), _item('nope')]);
      expect(groups, hasLength(1));
      expect(groups.single.items, hasLength(1));
    });

    test('empty input gives no groups', () {
      expect(groupReleasesByDay(const []), isEmpty);
    });

    test('key is stable per calendar day', () {
      final a = groupReleasesByDay([_item('2026-09-05')]).single;
      final b = groupReleasesByDay([_item('2026-09-05', type: 'game')]).single;
      expect(a.key, b.key);
      expect(a.key, isNot(groupReleasesByDay([_item('2026-09-06')]).single.key));
    });
  });

  group('daysFromToday', () {
    final now = DateTime(2026, 9, 23, 23, 45);

    test('today is 0 whatever the time of day', () {
      expect(daysFromToday(DateTime(2026, 9, 23), now), 0);
    });

    test('tomorrow is 1 even a quarter hour before midnight', () {
      expect(daysFromToday(DateTime(2026, 9, 24), now), 1);
    });

    test('a day that already passed is negative', () {
      expect(daysFromToday(DateTime(2026, 9, 22), now), -1);
    });

    test('counts whole days across a month boundary', () {
      expect(daysFromToday(DateTime(2026, 10, 3), now), 10);
    });

    test('is not thrown off by a daylight-saving day', () {
      // Local midnights across a clock change are 23h/25h apart; comparing
      // them as durations would call tomorrow "today". Whatever timezone
      // the test machine is in, consecutive calendar days differ by 1.
      for (var d = 0; d < 366; d++) {
        final today = DateTime(2026, 1, 1).add(Duration(days: d));
        final next = DateTime(today.year, today.month, today.day + 1);
        expect(daysFromToday(next, today), 1, reason: '$today -> $next');
      }
    });
  });
}
