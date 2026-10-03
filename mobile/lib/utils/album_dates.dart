/// Calendar arithmetic for the pair album's anniversary screen. Mirrors
/// backend/app/pair_album.py (`full_years`, `next_anniversary`,
/// `milestone_today`, ...) rule for rule, so the number on the screen is
/// the number the server would compute — a "100 days" push and the screen
/// it opens can never disagree.
///
/// Every function takes plain y/m/d days (local-midnight `DateTime`s built
/// from the server's calendar day) and never reads the phone's clock.
library;

/// Day counts worth a celebration. Yearly anniversaries are by calendar
/// (a year is 365 *or* 366 days), not by this list.
const List<int> kAlbumDayMilestones = [
  100, 200, 300, 500, 777, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 7500, 10000,
];

DateTime _day(int y, int m, int d) => DateTime(y, m, d);

/// The day the anniversary falls on in [year]. A Feb 29 start celebrates
/// on Feb 28 in common years — the day before, so it always lands inside
/// the month it belongs to.
DateTime anniversaryInYear(DateTime start, int year) {
  if (start.month == 2 && start.day == 29 && !_isLeap(year)) return _day(year, 2, 28);
  return _day(year, start.month, start.day);
}

bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

bool _before(DateTime a, DateTime b) =>
    a.year != b.year ? a.year < b.year : (a.month != b.month ? a.month < b.month : a.day < b.day);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Whole years elapsed, by calendar.
int fullYears(DateTime start, DateTime today) {
  var years = today.year - start.year;
  if (_before(today, anniversaryInYear(start, today.year))) years -= 1;
  return years < 0 ? 0 : years;
}

/// Days since [start], counting the first day as day 1 — "we've been
/// together 100 days" on the hundredth calendar day.
int daysTogether(DateTime start, DateTime today) => daysBetween(start, today) + 1;

bool isAnniversaryToday(DateTime start, DateTime today) =>
    today.year > start.year && sameDay(anniversaryInYear(start, today.year), today);

/// The next anniversary on or after [today] — today itself when today is
/// one (the screen celebrates on the day, it doesn't skip past it). Day
/// one isn't an anniversary, so a start of today points at next year.
DateTime nextAnniversary(DateTime start, DateTime today) {
  var candidate = anniversaryInYear(start, today.year);
  if (_before(candidate, today) || candidate.year <= start.year) {
    candidate = anniversaryInYear(start, today.year + 1);
  }
  return candidate;
}

int? milestoneToday(DateTime start, DateTime today) {
  final n = daysTogether(start, today);
  return kAlbumDayMilestones.contains(n) ? n : null;
}

/// The next day-count milestone after today and the day it lands on.
({int days, DateTime on})? nextDayMilestone(DateTime start, DateTime today) {
  final n = daysTogether(start, today);
  for (final m in kAlbumDayMilestones) {
    // Calendar arithmetic, not `start.add(Duration(days: ...))`: a Duration
    // is 24-hour blocks, so across a DST change it lands an hour off — on
    // the wrong calendar day half the year.
    if (m > n) return (days: m, on: DateTime(start.year, start.month, start.day + m - 1));
  }
  return null;
}

/// How far through the current year-of-togetherness we are, 0..1 — what
/// the anniversary ring fills to.
double yearProgress(DateTime start, DateTime today) {
  final years = fullYears(start, today);
  final from = anniversaryInYear(start, start.year + years);
  final to = anniversaryInYear(start, start.year + years + 1);
  final span = daysBetween(from, to);
  if (span <= 0) return 0;
  final done = daysBetween(from, today);
  return (done / span).clamp(0.0, 1.0).toDouble();
}

/// "1 год / 2 года / 5 лет" — Russian plural rule, 11–14 exception included.
String ruPlural(int n, String one, String few, String many) {
  final a = n.abs();
  if (a % 100 >= 11 && a % 100 <= 14) return many;
  if (a % 10 == 1) return one;
  if (a % 10 >= 2 && a % 10 <= 4) return few;
  return many;
}

const List<String> _ruMonthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];
const List<String> _enMonths = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

/// "29 сентября 2026" / "29 september 2026" — lowercase, the app's own
/// register for dates.
String albumDateLabel(DateTime d, {required bool ru, bool withYear = true}) {
  final month = ru ? _ruMonthsGen[d.month - 1] : _enMonths[d.month - 1];
  final base = ru ? '${d.day} $month' : '$month ${d.day}';
  if (!withYear) return base;
  return '$base ${d.year}';
}
