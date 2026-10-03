import 'package:flutter/material.dart' show DateTimeRange;

import '../models/diary_entry.dart';
import '../models/profile_stats.dart';
import 'locale_service.dart';

/// Builds a [WrappedSummary]-shaped object for an arbitrary date range and
/// a person-chosen title ("Отпуск в Турции", "Наши полгода") — entirely
/// on-device, from the diary entries already loaded for
/// [KeepsakeExportScreen]'s export. There's no backend support for a
/// custom range (`/profile/wrapped/summary` only ever takes
/// `scope=month|year|all`), so this fills in the same fields that
/// endpoint would, computed locally instead.
///
/// A few fields the backend can compute that this genuinely can't, for
/// lack of the underlying metadata on a diary row (see DiaryEntry — no
/// genre, director, runtime, or release-decade field at all, and no
/// cross-account data to build a percentile from): [WrappedSummary]'s
/// `topGenre`, `topDirectors`, `decades`, and `hoursPercentile` are left
/// null/empty here. wrapped_screen.dart's cards for those already
/// degrade gracefully to a "not enough data yet" line when empty — see
/// `_GenreStripCard`, `_DirectorsCard`, `_DecadeCard`, `_ClockCard` — so
/// nothing renders broken, they just quietly sit those cards out.
/// `totalHours` and `archetypeLabel` are the two exceptions: the former
/// is a clearly-labelled ("≈", already this app's house style for
/// derived time figures) rough estimate from typical runtimes per media
/// type, and the latter — since `_ArchetypeCard` has no empty-state
/// fallback — comes from [_deriveArchetype], a small local heuristic
/// rather than the backend's own (unseen) rule set.
class CustomWrappedService {
  const CustomWrappedService._();

  static const _monthNamesRu = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];
  static const _monthNamesEn = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _monthAbbrevRu = [
    '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  static String _dayMonth(DateTime d) {
    final months = LocaleService.appIsRussian ? _monthNamesRu : _monthNamesEn;
    return LocaleService.appIsRussian ? '${d.day} ${months[d.month]}' : '${months[d.month]} ${d.day}';
  }

  static String rangeLabel(DateTimeRange range) {
    final start = range.start;
    final end = range.end;
    if (LocaleService.appIsRussian) {
      if (start.year == end.year) return '${_dayMonth(start)} — ${_dayMonth(end)} ${end.year}';
      return '${_dayMonth(start)} ${start.year} — ${_dayMonth(end)} ${end.year}';
    }
    if (start.year == end.year) return '${_dayMonth(start)} – ${_dayMonth(end)}, ${end.year}';
    return '${_dayMonth(start)} ${start.year} – ${_dayMonth(end)} ${end.year}';
  }

  static WrappedSummary build({
    required String title,
    required DateTimeRange range,
    required List<DiaryEntry> allEntries,
  }) {
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    final entries = allEntries.where((e) => !e.watchedAt.isBefore(start) && !e.watchedAt.isAfter(end)).toList()
      ..sort((a, b) => a.watchedAt.compareTo(b.watchedAt));

    final daysSpan = end.difference(start).inDays + 1;
    final total = entries.length;

    if (total == 0) {
      return WrappedSummary(
        scope: 'custom',
        year: start.year,
        periodLabel: title,
        rangeLabel: rangeLabel(range),
        totalLogged: 0,
        totalHours: 0,
        daysSpan: daysSpan,
        isPremium: true,
        unlocked: true,
      );
    }

    final newCount = entries.where((e) => !e.isRewatch).length;
    final rewatchCount = total - newCount;

    final weekdayCounts = List<int>.filled(7, 0); // 0=Mon..6=Sun
    for (final e in entries) {
      weekdayCounts[(e.watchedAt.weekday - 1) % 7]++;
    }
    final weekendCount = weekdayCounts[5] + weekdayCounts[6];
    final weekendPercent = total == 0 ? 0.0 : weekendCount / total * 100;

    final soloCount = entries.where((e) => e.watchedWithUsername == null).length;
    final companyCount = total - soloCount;
    final soloPercent = total == 0 ? 0.0 : soloCount / total * 100;

    final rated = entries.where((e) => e.rating != null).toList();
    final averageRating = rated.isEmpty ? 0.0 : rated.map((e) => e.rating!).reduce((a, b) => a + b) / rated.length;
    final fullMarksCount = rated.where((e) => e.rating == 10).length;
    final histogramCounts = List<int>.filled(10, 0);
    for (final e in rated) {
      histogramCounts[e.rating!.clamp(1, 10) - 1]++;
    }
    final ratingHistogram = [
      for (var i = 0; i < 10; i++)
        if (histogramCounts[i] > 0) WrappedRatingBucket(rating: i + 1, count: histogramCounts[i]),
    ];

    final reviewed = entries.where((e) => (e.note?.trim().isNotEmpty ?? false)).toList()
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    final topReviews = [
      for (final e in reviewed.take(6))
        WrappedReviewItem(
          title: e.displayTitle,
          rating: e.rating,
          note: e.note,
          dateLabel: _dayMonth(e.watchedAt),
          posterUrl: e.posterUrl,
        ),
    ];
    final favoriteReview = topReviews.isEmpty ? null : topReviews.first;

    // Day buckets for a short stretch (a couple of months or less) read
    // like the app's own "month" wrapped; longer ranges fall back to
    // month buckets, same split the backend makes between its own
    // scope=month and scope=year/all timelines.
    //
    // The aggregation key must stay unique across the *whole* range even
    // in day-bucket mode: unlike the backend's own scope=month endpoint
    // (which this label format was designed for, and where "one day
    // bucket per calendar month" is a given), this local version's
    // day-bucket window goes up to 62 days — comfortably more than one
    // month — so two different calendar days that happen to share a
    // day-of-month (Jan 15 and Feb 15) would otherwise collapse into one
    // bucket and silently double-count. Keying by the full date and
    // deriving the day-of-month label separately keeps every distinct
    // day its own bucket while the *display* label stays exactly the
    // bare "1".."31" WrappedTimelineBucket already documents.
    final byDay = daysSpan <= 62;
    final timelineCounts = <String, int>{};
    for (final e in entries) {
      final key = byDay
          ? '${e.watchedAt.year}-${e.watchedAt.month}-${e.watchedAt.day}'
          : '${e.watchedAt.year}-${e.watchedAt.month}';
      timelineCounts[key] = (timelineCounts[key] ?? 0) + 1;
    }
    final timeline = [
      for (final entry in timelineCounts.entries)
        WrappedTimelineBucket(
          label: byDay
              ? entry.key.split('-').last
              : (LocaleService.appIsRussian ? _monthAbbrevRu : _monthNamesEn)[int.parse(entry.key.split('-')[1])],
          count: entry.value,
        ),
    ];
    String? busiestTimelineLabel;
    var busiestCount = 0;
    for (final b in timeline) {
      if (b.count > busiestCount) {
        busiestCount = b.count;
        busiestTimelineLabel = b.label;
      }
    }

    // Longest run of consecutive calendar days with at least one entry.
    final distinctDays = entries.map((e) => DateTime(e.watchedAt.year, e.watchedAt.month, e.watchedAt.day)).toSet().toList()
      ..sort();
    var longestStreak = 0;
    var currentStreak = 0;
    DateTime? prevDay;
    for (final d in distinctDays) {
      if (prevDay != null && d.difference(prevDay).inDays == 1) {
        currentStreak++;
      } else {
        currentStreak = 1;
      }
      if (currentStreak > longestStreak) longestStreak = currentStreak;
      prevDay = d;
    }

    // Rough, clearly-approximate runtime estimate — see class doc
    // comment. No per-title runtime data exists on a diary row, so this
    // leans on typical lengths per media type rather than real minutes.
    double hoursFor(DiaryEntry e) {
      switch (e.mediaType) {
        case 'movie':
          return 1.9;
        case 'series':
        case 'anime':
          return e.episodesWatched != null && e.episodesWatched! > 0 ? e.episodesWatched! * 0.75 : 3.0;
        case 'game':
          return 4.0;
        case 'book':
        case 'manga':
          return 3.0;
        default:
          return 1.5;
      }
    }

    final totalHours = entries.fold<double>(0, (sum, e) => sum + hoursFor(e));

    // Peak hour only when there's real spread in logged clock times —
    // otherwise every diary entry defaulting to midnight would falsely
    // read as "you always watch at 00:00".
    final hours = entries.map((e) => e.watchedAt.hour).where((h) => h != 0).toList();
    int? peakHour;
    double peakHourPercent = 0;
    if (hours.length >= 3) {
      final counts = <int, int>{};
      for (final h in hours) {
        counts[h] = (counts[h] ?? 0) + 1;
      }
      final sortedHours = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      peakHour = sortedHours.first.key;
      final peak = peakHour;
      final within = hours.where((h) => (h - peak).abs() <= 1 || (h - peak).abs() >= 23).length;
      peakHourPercent = within / hours.length * 100;
    }

    final receiptCounts = <String, int>{};
    for (final e in entries) {
      receiptCounts[e.displayTitle] = (receiptCounts[e.displayTitle] ?? 0) + 1;
    }
    final receiptItems = (receiptCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => WrappedReceiptItem(title: e.key, count: e.value))
        .toList();

    final posterUrls = [
      for (final e in entries.reversed)
        if (e.posterUrl != null) e.posterUrl!,
    ].toSet().take(8).toList();

    return WrappedSummary(
      scope: 'custom',
      year: start.year,
      periodLabel: title,
      rangeLabel: rangeLabel(range),
      totalLogged: total,
      totalHours: totalHours,
      first: WrappedTitleMoment(
        title: entries.first.displayTitle,
        dateLabel: _dayMonth(entries.first.watchedAt),
        posterUrl: entries.first.posterUrl,
      ),
      last: WrappedTitleMoment(
        title: entries.last.displayTitle,
        dateLabel: _dayMonth(entries.last.watchedAt),
        posterUrl: entries.last.posterUrl,
      ),
      daysSpan: daysSpan,
      newCount: newCount,
      rewatchCount: rewatchCount,
      timeline: timeline,
      busiestTimelineLabel: busiestTimelineLabel,
      longestStreakDays: longestStreak,
      weekdays: [for (var i = 0; i < 7; i++) WrappedWeekdayCount(weekday: i, count: weekdayCounts[i])],
      weekendPercent: weekendPercent,
      soloCount: soloCount,
      companyCount: companyCount,
      soloPercent: soloPercent,
      peakHour: peakHour,
      peakHourPercent: peakHourPercent,
      archetypeLabel: _deriveArchetype(
        soloPercent: soloPercent,
        weekendPercent: weekendPercent,
        rewatchCount: rewatchCount,
        newCount: newCount,
        longestStreakDays: longestStreak,
        daysSpan: daysSpan,
        totalLogged: total,
      ),
      reviewCount: reviewed.length,
      averageRating: averageRating,
      fullMarksCount: fullMarksCount,
      topReviews: topReviews,
      favoriteReview: favoriteReview,
      ratingHistogram: ratingHistogram,
      receiptItems: receiptItems,
      posterUrls: posterUrls,
      isPremium: true,
      unlocked: true,
    );
  }

  static String _deriveArchetype({
    required double soloPercent,
    required double weekendPercent,
    required int rewatchCount,
    required int newCount,
    required int longestStreakDays,
    required int daysSpan,
    required int totalLogged,
  }) {
    final ru = LocaleService.appIsRussian;
    if (rewatchCount > 0 && rewatchCount >= newCount) {
      return ru ? 'верный своим любимым' : 'loyal to old favorites';
    }
    if (longestStreakDays >= 5 && longestStreakDays >= daysSpan * 0.6) {
      return ru ? 'марафонец без перерыва' : 'the no-break marathoner';
    }
    if (soloPercent >= 75) {
      return ru ? 'ценит вечер в одиночку' : 'treasures a solo evening';
    }
    if (soloPercent <= 25) {
      return ru ? 'смотрит компанией' : 'always with someone';
    }
    if (weekendPercent >= 65) {
      return ru ? 'герой выходных' : 'weekend specialist';
    }
    if (totalLogged / (daysSpan == 0 ? 1 : daysSpan) >= 0.8) {
      return ru ? 'почти не пропускает вечер' : 'rarely misses a night';
    }
    return ru ? 'исследует не спеша' : 'the unhurried explorer';
  }
}
