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
        LogTheme.garden => 'nothing planted yet — tap + to write your first evening'.tr,
        LogTheme.coach => 'the route hasn\'t started yet — tap + to write your first evening'.tr,
        LogTheme.ticket => 'no tickets yet — tap + to write your first evening'.tr,
        LogTheme.shuttle => 'no launches yet — tap + to write your first evening'.tr,
      };

  /// Diary tab icon in the bottom nav — table row "Иконки навигации".
  static IconData navIcon(LogTheme theme, {required bool active}) => switch (theme) {
        LogTheme.garden => active ? Icons.local_florist : Icons.local_florist_outlined,
        LogTheme.coach => active ? Icons.route : Icons.route_outlined,
        LogTheme.ticket => active ? Icons.confirmation_number : Icons.confirmation_number_outlined,
        LogTheme.shuttle => active ? Icons.rocket_launch : Icons.rocket_launch_outlined,
      };

  /// "Still on the road" — same wording as ActiveJourneyBadge's own label,
  /// factored out here so the series episodes sheet's watching-now strip
  /// (widgets/series_episodes_sheet.dart) can say the same thing without
  /// reaching into that widget's private state.
  static String stillUnderway(LogTheme theme) => switch (theme) {
        LogTheme.coach => 'still on the road'.tr,
        LogTheme.garden => 'still out in the garden'.tr,
        LogTheme.ticket => 'still in the air'.tr,
        LogTheme.shuttle => 'still in orbit'.tr,
      };

  /// Profile/stats headline — table row "Профиль/статистика".
  static String profileHeadline(LogTheme theme) => switch (theme) {
        LogTheme.garden => 'your garden in bloom'.tr,
        LogTheme.coach => 'the road so far'.tr,
        LogTheme.ticket => 'your collected stubs'.tr,
        LogTheme.shuttle => 'your flight log'.tr,
      };

  /// Profile streak card, big line — real number, themed phrasing. `count`
  /// is the person's current streak in days (same value as the "day
  /// streak" figure everywhere else on Profile — see
  /// ProfileYearStats.streakDays), just dressed in the theme's own words.
  static String streakHeadline(LogTheme theme, int count) => switch (theme) {
        LogTheme.garden => '${nCount('nDays', count)} ${'growing'.tr}',
        LogTheme.coach => '${nCount('nStops', count)} ${'so far'.tr}',
        LogTheme.ticket => '${nCount('nNights', count)} ${'running'.tr}',
        LogTheme.shuttle => '${nCount('nLaunches', count)} ${'so far'.tr}',
      };

  /// Profile streak card, small line underneath — only ever shown when a
  /// real "best" figure is available (this month's longest streak — see
  /// WrappedStat.longestStreak); callers skip this line entirely rather
  /// than invent a lifetime-best number that isn't tracked anywhere.
  static String streakBest(LogTheme theme, int best) => switch (theme) {
        LogTheme.garden => '${'longest this month was'.tr} $best',
        LogTheme.coach => '${'longest ride this month was'.tr} $best',
        LogTheme.ticket => '${'longest run this month was'.tr} $best',
        LogTheme.shuttle => '${'longest run of launches this month was'.tr} $best',
      };

  /// Small badge pinned on the avatar's corner — table row "Профиль/статистика"
  /// dressed the same way the diary/log ritual already is.
  static IconData avatarBadgeIcon(LogTheme theme) => switch (theme) {
        LogTheme.garden => Icons.eco,
        LogTheme.coach => Icons.train,
        LogTheme.ticket => Icons.confirmation_number,
        LogTheme.shuttle => Icons.rocket_launch,
      };

  /// One-line "how it's going" bio under the username, used when there's
  /// no logged genre yet to build a real one from (see
  /// _ProfileHeader._bioLine in profile_screen.dart, which prefers the
  /// person's actual top genre over this).
  static String bioFallback(LogTheme theme) => switch (theme) {
        LogTheme.garden => 'just getting the garden started'.tr,
        LogTheme.coach => 'just getting the engine warmed up'.tr,
        LogTheme.ticket => 'just getting the reel loaded'.tr,
        LogTheme.shuttle => 'just clearing the launch pad'.tr,
      };

  /// Same real top-genre, three different sentences — table row
  /// "Профиль/статистика" again: the one place genre already showed up
  /// before this redesign, just phrased in the theme's own voice now
  /// instead of a flat "mostly X".
  static String bioWithGenre(LogTheme theme, String genreLower) => switch (theme) {
        LogTheme.garden => '${'mostly'.tr} $genreLower${', growing slowly'.tr}',
        LogTheme.coach => '${'always up for'.tr} $genreLower ${'on a long drive'.tr}',
        LogTheme.ticket => '${'always down for a'.tr} $genreLower ${'marathon'.tr}',
        LogTheme.shuttle => '${'always cleared for a'.tr} $genreLower ${'launch'.tr}',
      };

  /// Evening reminder push copy — table row "Пуш-уведомление". Not wired
  /// to anything yet: Seenly has no reminder/notification feature today,
  /// this is just the copy ready for whenever one exists.
  static String reminderTitle(LogTheme theme) => switch (theme) {
        LogTheme.garden => 'time to water the garden'.tr,
        LogTheme.coach => 'next stop is waiting'.tr,
        LogTheme.ticket => 'tonight\'s showing is coming up'.tr,
        LogTheme.shuttle => 'tonight\'s launch window is open'.tr,
      };

  /// Small honesty note on the full achievements screen — every badge
  /// there is computed straight from the person's own logged rows (see
  /// backend/app/routers/profile.py::get_achievements), so this is really
  /// just a gentle "these reflect what you actually log", not a policy.
  static String achievementsHonesty(LogTheme theme) => switch (theme) {
        LogTheme.garden => 'these only count what\'s actually grown here — please log your evenings honestly'.tr,
        LogTheme.coach => 'these only count the road you\'ve actually driven — please log your evenings honestly'.tr,
        LogTheme.ticket => 'these only count what\'s actually played on the reel — please log your evenings honestly'.tr,
        LogTheme.shuttle => 'these only count what\'s actually launched here — please log your evenings honestly'.tr,
      };

  /// Title line on the level detail sheet — real level number (see
  /// ProfileService.level / backend/app/routers/profile.py::get_level),
  /// dressed in the theme's own words.
  static String levelHeadline(LogTheme theme, int level) => switch (theme) {
        LogTheme.garden => '${'your garden is at level'.tr} $level',
        LogTheme.coach => '${'level'.tr} $level ${'on the road'.tr}',
        LogTheme.ticket => '${'level'.tr} $level ${'at the cinema'.tr}',
        LogTheme.shuttle => '${'level'.tr} $level ${'in orbit'.tr}',
      };

  /// Honesty note under the points bar on the level detail sheet — same
  /// reasoning as achievementsHonesty above, updated for the merged
  /// sincerity system (see backend/app/sincerity.py's module docstring):
  /// points are earned once, for real logged activity (watched titles,
  /// reviews, rewatches, genres explored, streaks) and a short list of
  /// rarer honest acts — never a counter that can drift or be bought.
  static String levelPointsNote(LogTheme theme) => switch (theme) {
        LogTheme.garden =>
          'points grow from what you actually plant here — logged evenings, reviews, rewatches, streaks, and genres explored'.tr,
        LogTheme.coach =>
          'points come from the miles you\'ve actually driven — logged evenings, reviews, rewatches, streaks, and genres explored'.tr,
        LogTheme.ticket =>
          'points come from what\'s actually played on the reel — logged evenings, reviews, rewatches, streaks, and genres explored'.tr,
        LogTheme.shuttle =>
          'points come from what you\'ve actually launched — logged evenings, reviews, rewatches, streaks, and genres explored'.tr,
      };

  /// Row labels for the activity breakdown on the full-screen level
  /// detail page — one per well levelPointsNote already names, dressed
  /// in the theme's words.
  static String levelBreakdownLabel(LogTheme theme, String key) => switch ((theme, key)) {
        (LogTheme.garden, 'watched') => 'evenings planted'.tr,
        (LogTheme.coach, 'watched') => 'evenings driven'.tr,
        (LogTheme.ticket, 'watched') => 'evenings screened'.tr,
        (LogTheme.shuttle, 'watched') => 'evenings launched'.tr,
        (LogTheme.garden, 'reviews') => 'notes left on the vine'.tr,
        (LogTheme.coach, 'reviews') => 'notes from the road'.tr,
        (LogTheme.ticket, 'reviews') => 'reviews written'.tr,
        (LogTheme.shuttle, 'reviews') => 'flight logs written'.tr,
        (LogTheme.garden, 'rewatches') => 'replanted a favorite'.tr,
        (LogTheme.coach, 'rewatches') => 'retraced routes'.tr,
        (LogTheme.ticket, 'rewatches') => 'rewatches logged'.tr,
        (LogTheme.shuttle, 'rewatches') => 'repeat launches'.tr,
        (LogTheme.garden, 'genres') => 'genres in bloom'.tr,
        (LogTheme.coach, 'genres') => 'genres explored'.tr,
        (LogTheme.ticket, 'genres') => 'genres on the marquee'.tr,
        (LogTheme.shuttle, 'genres') => 'genres charted'.tr,
        (LogTheme.garden, 'streak') => 'longest growing streak'.tr,
        (LogTheme.coach, 'streak') => 'longest run of the road'.tr,
        (LogTheme.ticket, 'streak') => 'longest run at the cinema'.tr,
        (LogTheme.shuttle, 'streak') => 'longest launch streak'.tr,
        (_, _) => key,
      };

  /// The "you just watched every episode of this" moment — table row
  /// none of the others cover, since finishing a whole season is its
  /// own kind of milestone (a specific show, not a running total).
  /// [wholeSeries] picks the bigger of the two phrasings for when this
  /// was also the last unwatched season in the whole series, not just
  /// this one.
  static String seasonCompleteHeadline(LogTheme theme, {required bool wholeSeries}) {
    if (wholeSeries) {
      return switch (theme) {
        LogTheme.garden => 'the whole garden bloomed'.tr,
        LogTheme.coach => 'end of the line — whole route driven'.tr,
        LogTheme.ticket => 'that\'s a wrap — whole reel watched'.tr,
        LogTheme.shuttle => 'mission complete — whole series launched'.tr,
      };
    }
    return switch (theme) {
      LogTheme.garden => 'this bed is fully grown'.tr,
      LogTheme.coach => 'that stretch of road is done'.tr,
      LogTheme.ticket => 'that reel\'s fully screened'.tr,
      LogTheme.shuttle => 'that stage is fully launched'.tr,
    };
  }
}
