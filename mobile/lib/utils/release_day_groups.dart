import 'dart:collection';

import '../models/release_calendar_item.dart';

/// One calendar day's worth of releases on the full-screen release
/// calendar (screens/calendar/release_calendar_screen.dart) — everything
/// that lands on [day], in the order the server sent it (already
/// date-sorted, see backend/app/routers/calendar.py).
class ReleaseDayGroup {
  /// Local midnight of the day these releases land on.
  final DateTime day;
  final List<ReleaseCalendarItem> items;

  const ReleaseDayGroup({required this.day, required this.items});

  /// Stable across rebuilds and filter changes for the same calendar day
  /// — what the screen keys its per-day slivers on.
  String get key => '${day.year}-${day.month}-${day.day}';
}

/// Buckets [items] by the local day they release on, oldest day first.
///
/// Rows whose `releaseDate` doesn't parse are dropped — there's nowhere
/// on a calendar to put them. Within a day the input order is kept (a
/// Dart [SplayTreeMap] only orders the *keys*), so the server's own
/// ordering — including Shikimori's air-time order — survives.
List<ReleaseDayGroup> groupReleasesByDay(Iterable<ReleaseCalendarItem> items) {
  final byDay = SplayTreeMap<DateTime, List<ReleaseCalendarItem>>();
  for (final item in items) {
    final day = item.releaseDay;
    if (day == null) continue;
    byDay.putIfAbsent(day, () => <ReleaseCalendarItem>[]).add(item);
  }
  return [
    for (final entry in byDay.entries)
      ReleaseDayGroup(day: entry.key, items: entry.value),
  ];
}

/// Whole calendar days from [now]'s date to [day] — 0 for today, 1 for
/// tomorrow, negative for a release that already came out.
///
/// Both sides are compared as UTC midnights on purpose: subtracting two
/// *local* midnights across a daylight-saving change is 23 or 25 hours,
/// and `Duration.inDays` truncates 23h to 0 — which would call
/// "tomorrow" "today" for a whole day twice a year.
int daysFromToday(DateTime day, DateTime now) {
  final a = DateTime.utc(day.year, day.month, day.day);
  final b = DateTime.utc(now.year, now.month, now.day);
  return a.difference(b).inDays;
}
