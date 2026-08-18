import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/episode.dart';
import '../models/media_item.dart';
import '../screens/add_entry/episode_log_followup.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../widgets/themed_loading_indicator.dart';
import '../services/app_translations.dart';

/// The series title screen's season/episode checklist. Loads the show's
/// season structure (public, cached forever server-side) and the current
/// user's watched marks (private) side by side, then lets them tick off
/// single episodes or a whole season at once.
///
/// Renders nothing — not even an empty state — until it actually has
/// something to show: a series with no episode data from TMDB just
/// quietly skips this section rather than showing a dead "unavailable"
/// card on every such title.
class SeasonTracker extends StatefulWidget {
  final String mediaId;
  final String source;
  // Needed to log a season's diary row the moment ticking a box here
  // completes it (see episode_log_followup.dart::maybeLogCompletedSeason)
  // — optional so any existing caller that doesn't have a MediaItem handy
  // yet keeps working, just without that side effect.
  final MediaItem? item;
  const SeasonTracker({super.key, required this.mediaId, required this.source, this.item});

  @override
  State<SeasonTracker> createState() => _SeasonTrackerState();
}

class _SeasonTrackerState extends State<SeasonTracker> {
  SeriesEpisodes? _episodes;
  SeriesProgress _progress = const SeriesProgress({});
  bool _loading = true;
  final Set<String> _pending = {}; // episode keys mid-request, for a subtle busy state

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final results = await Future.wait([
        app.media.episodes(mediaId: widget.mediaId, source: widget.source),
        app.progress.series(mediaId: widget.mediaId, source: widget.source),
      ]);
      if (!mounted) return;
      final episodes = results[0] as SeriesEpisodes;
      setState(() {
        _episodes = episodes;
        _progress = results[1] as SeriesProgress;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false); // degrade silently — see class docstring
    }
  }

  Future<void> _toggleEpisodes(List<Episode> episodes, bool watched) async {
    setState(() {
      _pending.addAll(episodes.map((e) => e.key));
      // Optimistic update so the tap feels instant — placeholder "now"
      // timestamps for newly-added keys get overwritten by the server's
      // real ones the moment the request below comes back.
      final next = {..._progress.watchedAt};
      for (final e in episodes) {
        if (watched) {
          next[e.key] = DateTime.now();
        } else {
          next.remove(e.key);
        }
      }
      _progress = SeriesProgress(next);
    });
    try {
      final result = await context.read<AppState>().progress.toggle(
            mediaId: widget.mediaId,
            source: widget.source,
            watched: watched,
            episodes: episodes,
          );
      if (!mounted) return;
      setState(() {
        _progress = result;
        _pending.removeAll(episodes.map((e) => e.key));
      });
      if (watched && widget.item != null) {
        // Best-effort, one call per distinct season touched — usually
        // just one, but "mark whole series watched" (if that's ever
        // wired up here) could span several at once.
        for (final season in episodes.map((e) => e.season).toSet()) {
          unawaited(maybeLogCompletedSeason(context: context, item: widget.item!, season: season));
        }
      }
    } catch (_) {
      if (!mounted) return;
      // Roll back — the optimistic update above was wrong.
      setState(() {
        final next = {..._progress.watchedAt};
        for (final e in episodes) {
          if (watched) {
            next.remove(e.key);
          } else {
            next[e.key] = DateTime.now();
          }
        }
        _progress = SeriesProgress(next);
        _pending.removeAll(episodes.map((e) => e.key));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't save that just now — try again".tr)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 18,
          width: 18,
          child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
        ),
      );
    }
    final episodes = _episodes;
    if (episodes == null || episodes.seasons.isEmpty) return const SizedBox.shrink();

    final total = episodes.totalEpisodes;
    final watched = episodes.seasons
        .expand((s) => s.episodes)
        .where((e) => _progress.isWatched(e.season, e.episode))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('seasons'.tr,
                style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accent)),
            Text('$watched/$total ${ruPluralForm(total, one: 'серия', few: 'серии', many: 'серий', englishOne: 'episode', englishOther: 'episodes')}', style: SeenlyText.metaLabel),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: total == 0 ? 0.0 : watched / total,
            minHeight: 5,
            backgroundColor: SeenlyPalette.paper,
            valueColor: const AlwaysStoppedAnimation(SeenlyPalette.accent),
          ),
        ),
        const SizedBox(height: 12),
        _SeasonPager(
          seasons: episodes.seasons,
          progress: _progress,
          pending: _pending,
          onToggleEpisode: (ep, watched) => _toggleEpisodes([ep], watched),
          onToggleSeason: (season, watched) => _toggleEpisodes(season.episodes, watched),
        ),
      ],
    );
  }
}

/// Seasons used to stack as one expandable card per season, scrolling
/// down through all of them. Now they page horizontally instead — swipe
/// (or tap the arrows) to move between seasons, one season's episodes
/// visible at a time.
class _SeasonPager extends StatefulWidget {
  final List<Season> seasons;
  final SeriesProgress progress;
  final Set<String> pending;
  final void Function(Episode, bool watched) onToggleEpisode;
  final void Function(Season, bool watched) onToggleSeason;

  const _SeasonPager({
    required this.seasons,
    required this.progress,
    required this.pending,
    required this.onToggleEpisode,
    required this.onToggleSeason,
  });

  @override
  State<_SeasonPager> createState() => _SeasonPagerState();
}

class _SeasonPagerState extends State<_SeasonPager> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    final firstUnfinished = widget.seasons.indexWhere(
      (s) => s.episodes.any((e) => !widget.progress.isWatched(e.season, e.episode)),
    );
    _page = firstUnfinished == -1 ? 0 : firstUnfinished;
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.seasons.isEmpty) return const SizedBox.shrink();
    final season = widget.seasons[_page];
    final watchedCount =
        season.episodes.where((e) => widget.progress.isWatched(e.season, e.episode)).length;
    final allWatched = watchedCount == season.episodes.length && season.episodes.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: SeenlyPalette.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
            child: Row(
              children: [
                IconButton(
                  onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  color: SeenlyPalette.inkFaint,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (season.posterUrl != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            season.posterUrl!,
                            width: 84,
                            height: 122,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(width: 84, height: 122),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => widget.onToggleSeason(season, !allWatched),
                            child: Icon(
                              allWatched ? Icons.check_circle : Icons.check_circle_outline,
                              size: 18,
                              color: allWatched ? SeenlyPalette.accent : SeenlyPalette.dashedBorder,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('${'season'.tr} ${season.season}',
                              style: SeenlyText.serif(italic: true, size: 15)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('$watchedCount/${season.episodes.length}',
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed:
                      _page < widget.seasons.length - 1 ? () => _goTo(_page + 1) : null,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  color: SeenlyPalette.inkFaint,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: SeenlyPalette.background),
          SizedBox(
            height: 340,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.seasons.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final s = widget.seasons[i];
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: s.episodes.length,
                  itemBuilder: (context, j) => _EpisodeRow(
                    episode: s.episodes[j],
                    watched: widget.progress.isWatched(s.episodes[j].season, s.episodes[j].episode),
                    busy: widget.pending.contains(s.episodes[j].key),
                    showDivider: j > 0,
                    onTap: () => widget.onToggleEpisode(s.episodes[j],
                        !widget.progress.isWatched(s.episodes[j].season, s.episodes[j].episode)),
                  ),
                );
              },
            ),
          ),
          if (widget.seasons.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.seasons.length; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: i == _page ? 14 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: i == _page ? SeenlyPalette.accent : SeenlyPalette.dashedBorder,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final Episode episode;
  final bool watched;
  final bool busy;
  final bool showDivider;
  final VoidCallback onTap;

  const _EpisodeRow({
    required this.episode,
    required this.watched,
    required this.busy,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasTitle = episode.title != null && episode.title!.trim().isNotEmpty;
    return Column(
      children: [
        if (showDivider)
          Divider(height: 1, thickness: 1, color: SeenlyPalette.background),
        InkWell(
          onTap: busy ? null : onTap,
          child: Opacity(
            opacity: busy ? 0.45 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    watched ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: watched ? SeenlyPalette.accent : SeenlyPalette.dashedBorder,
                  ),
                  const SizedBox(width: 11),
                  SizedBox(
                    width: 22,
                    child: Text(
                      episode.episode.toString().padLeft(2, '0'),
                      style: SeenlyText.mono(
                          size: 10,
                          color: watched ? SeenlyPalette.accent : SeenlyPalette.inkFaint),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hasTitle ? episode.title! : 'episode ${episode.episode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(
                        size: 13,
                        italic: !hasTitle,
                        color: watched ? SeenlyPalette.inkFaint : SeenlyPalette.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
