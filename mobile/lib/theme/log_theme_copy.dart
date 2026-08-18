import 'package:flutter/material.dart';

import '../services/app_translations.dart';
import '../services/log_theme_service.dart';

/// Everywhere the [LogTheme] shows up *outside* the logging ritual
/// itself: the empty diary, the nav bar's diary tab, the profile
/// headline, the loading spinner, and (for whenever reminders exist)
/// push copy. [log_ritual.dart] is the one place that knows all three
/// themes for the seat/drop/centerpiece/button; this is that same idea
/// for the rest of the app, so a theme switch in Settings doesn't
/// leave any corner still dressed as ticket.
class LogThemeCopy {
  const LogThemeCopy._();

  /// Empty diary / watchlist caption — table row "Пустой список/вотчлист".
  static String emptyDiary(LogTheme theme) => switch (theme) {
        LogTheme.garden => 'nothing planted yet — tap + to write your first evening',
        LogTheme.coach => 'the route hasn\'t started yet — tap + to write your first evening',
        LogTheme.ticket => 'no tickets yet — tap + to write your first evening',
      };

  /// Diary tab icon in the bottom nav — table row "Иконки навигации".
  static IconData navIcon(LogTheme theme, {required bool active}) => switch (theme) {
        LogTheme.garden => active ? Icons.local_florist : Icons.local_florist_outlined,
        LogTheme.coach => active ? Icons.route : Icons.route_outlined,
        LogTheme.ticket => active ? Icons.confirmation_number : Icons.confirmation_number_outlined,
      };

  /// "Still on the road" — same wording as ActiveJourneyBadge's own label,
  /// factored out here so the series episodes sheet's watching-now strip
  /// (widgets/series_episodes_sheet.dart) can say the same thing without
  /// reaching into that widget's private state.
  static String stillUnderway(LogTheme theme) => switch (theme) {
        LogTheme.coach => 'still on the road',
        LogTheme.garden => 'still out in the garden',
        LogTheme.ticket => 'still in the air',
      };

  /// Profile/stats headline — table row "Профиль/статистика".
  static String profileHeadline(LogTheme theme) => switch (theme) {
        LogTheme.garden => 'your garden in bloom',
        LogTheme.coach => 'the road so far',
        LogTheme.ticket => 'your collected stubs',
      };

  /// Profile streak card, big line — real number, themed phrasing. `count`
  /// is the person's current streak in days (same value as the "day
  /// streak" figure everywhere else on Profile — see
  /// ProfileYearStats.streakDays), just dressed in the theme's own words.
  static String streakHeadline(LogTheme theme, int count) => switch (theme) {
        LogTheme.garden => '${ruCount(count, one: 'день', few: 'дня', many: 'дней', englishOne: 'day', englishOther: 'days')} ${'growing'.tr}',
        LogTheme.coach => '${ruCount(count, one: 'остановка', few: 'остановки', many: 'остановок', englishOne: 'stop', englishOther: 'stops')} ${'so far'.tr}',
        LogTheme.ticket => '${ruCount(count, one: 'ночь', few: 'ночи', many: 'ночей', englishOne: 'night', englishOther: 'nights')} ${'running'.tr}',
      };

  /// Profile streak card, small line underneath — only ever shown when a
  /// real "best" figure is available (this month's longest streak — see
  /// WrappedStat.longestStreak); callers skip this line entirely rather
  /// than invent a lifetime-best number that isn't tracked anywhere.
  static String streakBest(LogTheme theme, int best) => switch (theme) {
        LogTheme.garden => 'longest this month was $best',
        LogTheme.coach => 'longest ride this month was $best',
        LogTheme.ticket => 'longest run this month was $best',
      };

  /// Small badge pinned on the avatar's corner — table row "Профиль/статистика"
  /// dressed the same way the diary/log ritual already is.
  static IconData avatarBadgeIcon(LogTheme theme) => switch (theme) {
        LogTheme.garden => Icons.eco,
        LogTheme.coach => Icons.train,
        LogTheme.ticket => Icons.confirmation_number,
      };

  /// One-line "how it's going" bio under the username, used when there's
  /// no logged genre yet to build a real one from (see
  /// _ProfileHeader._bioLine in profile_screen.dart, which prefers the
  /// person's actual top genre over this).
  static String bioFallback(LogTheme theme) => switch (theme) {
        LogTheme.garden => 'just getting the garden started',
        LogTheme.coach => 'just getting the engine warmed up',
        LogTheme.ticket => 'just getting the reel loaded',
      };

  /// Same real top-genre, three different sentences — table row
  /// "Профиль/статистика" again: the one place genre already showed up
  /// before this redesign, just phrased in the theme's own voice now
  /// instead of a flat "mostly X".
  static String bioWithGenre(LogTheme theme, String genreLower) => switch (theme) {
        LogTheme.garden => 'mostly $genreLower, growing slowly',
        LogTheme.coach => 'always up for $genreLower on a long drive',
        LogTheme.ticket => 'always down for a $genreLower marathon',
      };

  /// Evening reminder push copy — table row "Пуш-уведомление". Not wired
  /// to anything yet: Seenly has no reminder/notification feature today,
  /// this is just the copy ready for whenever one exists.
  static String reminderTitle(LogTheme theme) => switch (theme) {
        LogTheme.garden => 'time to water the garden',
        LogTheme.coach => 'next stop is waiting',
        LogTheme.ticket => 'tonight\'s showing is coming up',
      };

  /// Small honesty note on the full achievements screen — every badge
  /// there is computed straight from the person's own logged rows (see
  /// backend/app/routers/profile.py::get_achievements), so this is really
  /// just a gentle "these reflect what you actually log", not a policy.
  static String achievementsHonesty(LogTheme theme) => switch (theme) {
        LogTheme.garden => 'these only count what\'s actually grown here — please log your evenings honestly',
        LogTheme.coach => 'these only count the road you\'ve actually driven — please log your evenings honestly',
        LogTheme.ticket => 'these only count what\'s actually played on the reel — please log your evenings honestly',
      };

  /// Title line on the level detail sheet — real level number (see
  /// ProfileService.level / backend/app/routers/profile.py::get_level),
  /// dressed in the theme's own words.
  static String levelHeadline(LogTheme theme, int level) => switch (theme) {
        LogTheme.garden => 'your garden is at level $level',
        LogTheme.coach => 'level $level on the road',
        LogTheme.ticket => 'level $level at the cinema',
      };

  /// Honesty note under the xp bar on the level detail sheet — same
  /// reasoning as achievementsHonesty above: xp is computed fresh from
  /// real logged rows (watched titles, reviews, rewatches, genres
  /// explored, longest streak), never a counter that can drift or be
  /// bought.
  static String levelXpNote(LogTheme theme) => switch (theme) {
        LogTheme.garden =>
          'xp grows from what you actually plant here — logged evenings, reviews, rewatches, streaks, and genres explored',
        LogTheme.coach =>
          'xp comes from the miles you\'ve actually driven — logged evenings, reviews, rewatches, streaks, and genres explored',
        LogTheme.ticket =>
          'xp comes from what\'s actually played on the reel — logged evenings, reviews, rewatches, streaks, and genres explored',
      };

  /// Row labels for the xp breakdown on the full-screen level detail page —
  /// one per well levelXpNote already names, dressed in the theme's words.
  static String levelBreakdownLabel(LogTheme theme, String key) => switch ((theme, key)) {
        (LogTheme.garden, 'watched') => 'evenings planted',
        (LogTheme.coach, 'watched') => 'evenings driven',
        (LogTheme.ticket, 'watched') => 'evenings screened',
        (LogTheme.garden, 'reviews') => 'notes left on the vine',
        (LogTheme.coach, 'reviews') => 'notes from the road',
        (LogTheme.ticket, 'reviews') => 'reviews written',
        (LogTheme.garden, 'rewatches') => 'replanted a favorite',
        (LogTheme.coach, 'rewatches') => 'retraced routes',
        (LogTheme.ticket, 'rewatches') => 'rewatches logged',
        (LogTheme.garden, 'genres') => 'genres in bloom',
        (LogTheme.coach, 'genres') => 'genres explored',
        (LogTheme.ticket, 'genres') => 'genres on the marquee',
        (LogTheme.garden, 'streak') => 'longest growing streak',
        (LogTheme.coach, 'streak') => 'longest run of the road',
        (LogTheme.ticket, 'streak') => 'longest run at the cinema',
        (_, _) => key,
      };
}
