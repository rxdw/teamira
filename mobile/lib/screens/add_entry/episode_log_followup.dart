import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/diary_entry.dart';
import '../../models/episode.dart';
import '../../models/media_item.dart';
import '../../services/log_theme_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/achievement_unlock_overlay.dart';
import '../../widgets/level_up_celebration.dart';
import '../../widgets/sincerity_toast.dart';
import '../../widgets/watch_complete_celebration.dart';
import '../../widgets/wow_motion.dart' show Entrance, PressScale;
import '../../services/app_translations.dart';
import '../../theme/clay_kit.dart';

/// Call this once a single episode has actually been watched — whether
/// that's the "already watched" instant path (see watching_choice_screen)
/// or the "watching now" journey's arrival step (see
/// journey_progress_screen's `_imBack`). Marks it watched
/// (`POST /progress/toggle`) and hands off to [maybeLogCompletedSeason]
/// to check whether that was the episode completing its season.
///
/// This episode's own rating/note is a separate, lighter action — see
/// the episode list's own star tap (routers/progress.py::rate_episode) —
/// not something this "I watched it" moment collects.
Future<void> markEpisodeWatched({
  required BuildContext context,
  required MediaItem item,
  required int season,
  required int episode,
}) async {
  final app = context.read<AppState>();
  try {
    await app.progress.toggle(
      mediaId: item.id,
      source: item.source,
      watched: true,
      episodes: [Episode(season: season, episode: episode)],
    );
  } catch (_) {
    // Best-effort — the season tracker will just be a beat behind; still
    // worth trying the completion check below with what we can reach.
  }
  if (!context.mounted) return;
  await maybeLogCompletedSeason(context: context, item: item, season: season);
}

/// Checks whether every episode of [season] is now watched and, if so,
/// whether it's already been logged — series like this are the only
/// place a diary row for a series gets written at all (see
/// routers/diary.py::log_watched's own docstring on why individual
/// episodes never get their own row). Safe to call after *any*
/// progress-changing action (a rating tap, the season checklist, "mark
/// whole season watched", or an episode leg finishing) — idempotent, so
/// calling it again on an already-logged season is a no-op rather than a
/// duplicate/"rewatch" row.
///
/// The one row this creates uses the season's own episodes' individual
/// ratings (see the episode list's star tap), averaged — not a rating
/// prompt of its own. If this also happens to be the last unwatched
/// season in the whole series, this also promotes the title straight to
/// `watched` via POST /progress/complete, same as the old per-episode
/// chain used to.
///
/// Any failure fetching episodes/progress/history (offline, etc.) just
/// leaves things as they were — the episode's own watched-mark already
/// went out before this is ever called, this is only the season/series
/// bookkeeping on top.
Future<void> maybeLogCompletedSeason({
  required BuildContext context,
  required MediaItem item,
  required int season,
}) async {
  final app = context.read<AppState>();
  try {
    final results = await Future.wait([
      app.media.episodes(mediaId: item.id, source: item.source),
      app.progress.series(mediaId: item.id, source: item.source),
      app.diary.mediaHistory(item.id, item.source),
    ]);
    final seriesEpisodes = results[0] as SeriesEpisodes;
    final progress = results[1] as SeriesProgress;
    final history = results[2] as List<DiaryEntry>;

    final thisSeason = seriesEpisodes.seasons.firstWhere(
      (s) => s.season == season,
      orElse: () => Season(season: season, episodes: []),
    );
    if (thisSeason.episodes.isEmpty) return;
    final seasonComplete =
        thisSeason.episodes.every((e) => progress.isWatched(e.season, e.episode));
    if (!seasonComplete) return;

    // A series now has exactly one diary row, whose `season` is always
    // the latest one reached (see models.DiaryEntry's own doc comment on
    // the backend) — so "already logged" means that row is already at or
    // past this season, not an exact match. Exact match would work for
    // the common case, but a stale/out-of-order call for an earlier
    // season would otherwise re-log it and walk the row's season back
    // down, which upsert would then take at face value.
    final alreadyLogged =
        history.isNotEmpty && (history.first.season ?? 0) >= season;
    if (alreadyLogged) return;

    final ratings = [
      for (final e in thisSeason.episodes) progress.ratingFor(e.season, e.episode),
    ].whereType<int>().toList();
    final avgRating =
        ratings.isEmpty ? null : (ratings.reduce((a, b) => a + b) / ratings.length).round();

    final entry = await app.diary.logEntry(
      item: item,
      season: season,
      episodeCount: thisSeason.episodes.length,
      rating: avgRating,
      // Explicit, same as every other logEntry call site (see
      // watching_choice_screen.dart, the themed log screens' own
      // _resolvedDate) — left out, this falls through to the backend's
      // own default (datetime.utcnow(), a real UTC instant with no
      // timezone marker), which DiaryEntry.fromJson then reads back as
      // if it were local wall-clock time. Near a midnight boundary that
      // can land the auto-logged entry on the wrong calendar day.
      watchedAt: DateTime.now(),
    );
    if (context.mounted) showSincerityToasts(context, entry.sincerityAwarded);
    // A save here is exactly the same kind of moment the themed log
    // screens refresh level after — this path just never called it, so
    // a season/series finish never nudged the cached level even when
    // it should have. Awaited (not fire-and-forget like the themed
    // screens' own call) since there's no ticket-drop animation here to
    // protect from a blocking network hop, and the level-up check right
    // below needs the result to actually be there.
    await app.refreshLevel();

    final all = [for (final s in seriesEpisodes.seasons) ...s.episodes];
    final seriesComplete =
        all.isNotEmpty && all.every((e) => progress.isWatched(e.season, e.episode));
    if (seriesComplete) {
      try {
        await app.progress.completeSeries(mediaId: item.id, source: item.source);
      } catch (_) {
        // Best-effort — the season tracker will still show every episode
        // ticked even if the shelf promotion didn't make it through.
      }
    }

    // The moment itself: finishing a season (or, bigger, the whole
    // series) previously happened with zero visual acknowledgement —
    // this was the one save-completing flow in the app that skipped
    // both the level check every themed log screen already does and
    // any celebration of its own. Level-up first (if this happened to
    // cross one), then the season/series moment, then any badge that
    // came with it — same ordering as the themed ritual screens' own
    // "keep the stub" handler.
    if (context.mounted) {
      final leveledUp = app.consumePendingLevelUp();
      if (leveledUp != null && context.mounted) {
        await showLevelUpCelebration(context, leveledUp);
      }
      if (context.mounted) {
        await showWatchCompleteCelebration(context, wholeSeries: seriesComplete);
      }
      if (context.mounted) {
        await checkAndCelebrateNewAchievements(context);
      }
    }
  } catch (_) {
    // Best-effort — see the function's own docstring.
  }
}

/// First season/episode pair, in order, that isn't marked watched yet —
/// same "what's next" logic as series_episodes_sheet.dart's own
/// `_nextUnwatched`, just reachable from the log flow itself so
/// [WatchingChoiceScreen]'s "already watched" can offer to chain
/// straight into it once this episode's own ritual is done. Null once
/// the whole series has been seen, or if the episode list/progress
/// can't be reached right now.
Future<(int season, int episode)?> nextUnwatchedEpisode({
  required BuildContext context,
  required MediaItem item,
}) async {
  final app = context.read<AppState>();
  try {
    final results = await Future.wait([
      app.media.episodes(mediaId: item.id, source: item.source),
      app.progress.series(mediaId: item.id, source: item.source),
    ]);
    final seriesEpisodes = results[0] as SeriesEpisodes;
    final progress = results[1] as SeriesProgress;
    for (final season in seriesEpisodes.seasons) {
      for (final ep in season.episodes) {
        if (!progress.isWatched(ep.season, ep.episode)) {
          return (ep.season, ep.episode);
        }
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// A plain "keep going?" ask, shown right after one episode's own
/// ritual finishes and there's a next unwatched episode waiting — see
/// [WatchingChoiceScreen._alreadyWatched] and
/// [JourneyProgressScreen._imBackFromEpisodeLeg]. Deliberately simpler
/// than [startEpisodeJourney]'s own continuation sheet (see
/// services/episode_continuation.dart): that one also decides whether
/// to resume or restart a *route*, which only applies to the
/// "watching now" arrival; this is just yes/not now, since from
/// "already watched" the next step is picking already-watched-or-
/// watching-now fresh, not resuming anything.
Future<bool> confirmWatchNextEpisode(BuildContext context, LogTheme theme) async {
  final accent = switch (theme) {
    LogTheme.coach => SeenlyPalette.periwinkle,
    LogTheme.garden => SeenlyPalette.sage,
    LogTheme.ticket => SeenlyPalette.coral,
    LogTheme.shuttle => SeenlyPalette.periwinkle,
  };
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: Container(
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Entrance(
              child: Text('watch the next episode?'.tr, style: SeenlyText.serif(italic: true, size: 18)),
            ),
            const SizedBox(height: 6),
            Entrance(
              delay: const Duration(milliseconds: 60),
              child: Text('keep the evening going with what comes next'.tr,
                  style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
            ),
            const SizedBox(height: 22),
            Entrance(
              delay: const Duration(milliseconds: 110),
              riseBy: 14,
              child: PressScale(
                onTap: () => Navigator.of(sheetContext).pop(true),
                haptics: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: Text('yes'.tr,
                      style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.paper)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: PressScale(
                onTap: () => Navigator.of(sheetContext).pop(false),
                child: Text('not now'.tr, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
