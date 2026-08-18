import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/active_journey.dart';
import '../models/diary_entry.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../screens/add_entry/watching_choice_screen.dart';
import '../screens/title/title_detail_screen.dart';
import '../services/episode_continuation.dart';
import '../state/app_state.dart';
import '../theme/log_theme_copy.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'active_journey_badge.dart';
import 'edit_review_sheet.dart';
import 'heart_rating.dart';
import 'review_composer.dart';
import 'themed_loading_indicator.dart';
import '../services/app_translations.dart';

/// Opened from a series' single roll-up card on the Diary tab or the
/// "watched" shelf — one card per series rather than one row per logged
/// episode (a diary row here only ever represents a whole completed
/// season — see routers/diary.py::log_watched).
///
/// Deliberately the same floating, blurred-backdrop paper card as
/// [showWatchedPreview] (see watched_preview_sheet.dart) rather than a
/// separate full-screen sheet design — a movie and a series are both
/// "something you tapped from the watched shelf", so they open the same
/// way. The series version just carries more: a progress bar, a "watch
/// next episode" button, and a season pager (poster + episode list per
/// season) underneath the same poster/title header the movie card uses.
///
/// Lists every season/episode in order: watched ones ticked with their
/// date, tappable to set that episode's own lightweight rating/note (see
/// routers/progress.py::rate_episode — episode_log_followup.dart
/// averages a season's worth of these into the one diary entry once
/// every episode in it is watched); unwatched ones dimmed, with the
/// show's own runtime as a rough per-episode length where the caller has
/// one to pass in. If this title is "watching now", a strip up top links
/// straight to the full route — see [openActiveJourney].
Future<void> showSeriesEpisodesSheet(
  BuildContext context, {
  required String mediaId,
  required String source,
  required String title,
  required String mediaType,
  String? posterUrl,
  int? runtimeMinutes,
}) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'series preview',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, __) => _SeriesEpisodesSheet(
      mediaId: mediaId,
      source: source,
      title: title,
      mediaType: mediaType,
      posterUrl: posterUrl,
      runtimeMinutes: runtimeMinutes,
    ),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _SeriesEpisodesSheet extends StatefulWidget {
  final String mediaId;
  final String source;
  final String title;
  final String mediaType;
  final String? posterUrl;
  final int? runtimeMinutes;

  const _SeriesEpisodesSheet({
    required this.mediaId,
    required this.source,
    required this.title,
    required this.mediaType,
    this.posterUrl,
    this.runtimeMinutes,
  });

  @override
  State<_SeriesEpisodesSheet> createState() => _SeriesEpisodesSheetState();
}

class _SeriesEpisodesSheetState extends State<_SeriesEpisodesSheet> {
  SeriesEpisodes? _episodes;
  SeriesProgress _progress = const SeriesProgress({});
  MediaItem? _mediaItem;
  // The series' one diary row (see DiaryEntry's own doc comment on why
  // there's ever only one) — null until a season's actually been
  // completed and logged, at which point [_SeriesReviewCard] appears
  // with whatever rating/review it carries.
  DiaryEntry? _reviewEntry;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  MediaItem _fallbackItem() => MediaItem(
        id: widget.mediaId,
        mediaType: widget.mediaType,
        externalIds: const ExternalIds(),
        title: LocalizedText(en: widget.title),
        description: const LocalizedText(),
        posterUrl: widget.posterUrl,
        source: widget.source,
      );

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final results = await Future.wait([
        app.media.episodes(mediaId: widget.mediaId, source: widget.source),
        app.progress.series(mediaId: widget.mediaId, source: widget.source),
        app.diary.mediaHistory(widget.mediaId, widget.source),
      ]);
      // Best-effort, separately — a slow/failed detail fetch shouldn't
      // block the episode list itself from rendering, only the "watch
      // next episode" button's item (which falls back to a synthetic
      // one built from what this sheet was already given).
      MediaItem? item;
      try {
        final detail = await app.media.detail(
          mediaId: widget.mediaId,
          mediaType: widget.mediaType,
          source: widget.source,
        );
        item = detail?.item;
      } catch (_) {
        item = null;
      }
      final history = results[2] as List<DiaryEntry>;
      if (!mounted) return;
      setState(() {
        _episodes = results[0] as SeriesEpisodes;
        _progress = results[1] as SeriesProgress;
        _mediaItem = item ?? _fallbackItem();
        _reviewEntry = history.isEmpty ? null : history.first;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// First season/episode pair, in order, that isn't marked watched —
  /// null once the whole thing's been seen. Drives the "watch next
  /// episode" button; see [_NextEpisodeButton].
  (int season, int episode)? get _nextUnwatched {
    final episodes = _episodes;
    if (episodes == null) return null;
    for (final season in episodes.seasons) {
      for (final ep in season.episodes) {
        if (!_progress.isWatched(ep.season, ep.episode)) {
          return (ep.season, ep.episode);
        }
      }
    }
    return null;
  }

  int get _watchedCount {
    final episodes = _episodes;
    if (episodes == null) return 0;
    return episodes.seasons
        .expand((s) => s.episodes)
        .where((e) => _progress.isWatched(e.season, e.episode))
        .length;
  }

  void _openTitle(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TitleDetailScreen(
          mediaId: widget.mediaId,
          source: widget.source,
          mediaType: widget.mediaType,
          seedTitle: widget.title,
          seedPosterUrl: widget.posterUrl,
        ),
      ),
    );
  }

  Future<void> _openEpisodeDetail(Episode ep) async {
    final watchedAt = _progress.watchedAtFor(ep.season, ep.episode);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EpisodeRatingDialog(
        mediaId: widget.mediaId,
        source: widget.source,
        episode: ep,
        rating: _progress.ratingFor(ep.season, ep.episode),
        note: _progress.noteFor(ep.season, ep.episode),
        watchedAt: watchedAt,
      ),
    );
    if (saved == true) _load();
  }

  /// The checkmark's own tap — removes just this one episode from
  /// watched, right from the list, no dialog. Optimistic: flips the
  /// local progress immediately (so the tap reads as instant) and
  /// reconciles with whatever the server actually has once the request
  /// lands; a failure just reloads to whatever's really there rather
  /// than leaving the UI showing something that didn't stick.
  Future<void> _unmarkWatched(Episode ep) async {
    HapticFeedback.selectionClick();
    final previous = _progress;
    setState(() => _progress = _progress.without(ep.season, ep.episode));
    try {
      final updated = await context.read<AppState>().progress.toggle(
            mediaId: widget.mediaId,
            source: widget.source,
            watched: false,
            episodes: [ep],
          );
      if (mounted) setState(() => _progress = updated);
    } catch (_) {
      if (mounted) setState(() => _progress = previous);
    }
  }

  /// Opens the series' one diary row for editing — same
  /// [showEditReviewSheet] a movie's preview card uses, just reached
  /// from here since a series never opens that card (see
  /// [_SeriesReviewCard]'s own doc comment for why). A `deleted` result
  /// closes this whole sheet too, same reasoning as
  /// WatchedPreviewCard._edit: there's no season progress worth
  /// sitting on top of a row that no longer exists.
  Future<void> _editReview() async {
    final entry = _reviewEntry;
    if (entry == null) return;
    final result = await showEditReviewSheet(context, entry);
    if (result == null || !mounted) return;
    if (result.deleted) {
      Navigator.of(context).pop();
      return;
    }
    if (result.entry != null) setState(() => _reviewEntry = result.entry);
  }

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<AppState>().activeJourneysList;
    final matches = journeys.where((j) => j.item.id == widget.mediaId);
    final activeJourney = matches.isEmpty ? null : matches.first;
    final episodes = _episodes;
    final total = episodes?.totalEpisodes ?? 0;
    final watched = _watchedCount;

    // showGeneralDialog (unlike showModalBottomSheet, which wrapped its
    // builder in one automatically) doesn't give this an ancestor
    // Material of its own — and the episode rows below use InkWell for
    // their tap/ripple, which needs one. Wrapping here, transparently,
    // is the fix rather than pulling InkWell back out.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(color: SeenlyPalette.ink.withOpacity(0.28)),
            ),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Container(
              width: 320,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.86),
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              decoration: BoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: SeenlyPalette.ink.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 12)),
                ],
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 14, color: SeenlyPalette.inkMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () => _openTitle(context),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: SizedBox(
                              width: 128,
                              height: 186,
                              child: widget.posterUrl != null && widget.posterUrl!.isNotEmpty
                                  ? Image.network(
                                      widget.posterUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(color: SeenlyPalette.mediaColor(widget.mediaType)),
                                    )
                                  : Container(
                                      color: SeenlyPalette.mediaColor(widget.mediaType),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.movie_creation_outlined,
                                          color: SeenlyPalette.paper, size: 28),
                                    ),
                            ),
                          ),
                          Positioned(
                            right: -8,
                            bottom: -8,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: SeenlyPalette.accent,
                                shape: BoxShape.circle,
                                border: Border.all(color: SeenlyPalette.paper, width: 2.5),
                                boxShadow: SeenlyPalette.softShadow,
                              ),
                              child: const Icon(Icons.open_in_new, size: 14, color: SeenlyPalette.accentOnAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // No title/mediaType line here on purpose — the
                    // poster (tap to open the title) already identifies
                    // what this is, and the sheet's real job is showing
                    // as many episode rows as possible without forcing
                    // a scroll; a title repeats what's already visible
                    // one tap away, at the cost of the space episodes
                    // actually need.
                    Text(
                      _loading ? '' : 'watched $watched of $total episodes',
                      style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                    ),
                    if (!_loading && total > 0) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0.0 : watched / total,
                          minHeight: 5,
                          backgroundColor: SeenlyPalette.border,
                          valueColor: const AlwaysStoppedAnimation(SeenlyPalette.accent),
                        ),
                      ),
                    ],
                    if (!_loading && _reviewEntry != null) ...[
                      const SizedBox(height: 16),
                      _SeriesReviewCard(entry: _reviewEntry!, onEdit: _editReview),
                    ],
                    if (_loading) ...[
                      const SizedBox(height: 40),
                      const ThemedLoadingIndicator(color: SeenlyPalette.accent),
                      const SizedBox(height: 24),
                    ] else if (_failed || episodes == null || episodes.seasons.isEmpty) ...[
                      const SizedBox(height: 28),
                      Text(
                        _failed ? "couldn't load episodes — try again" : 'no episode data for this one yet',
                        textAlign: TextAlign.center,
                        style: SeenlyText.serif(italic: true, color: SeenlyPalette.placeholder),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      const SizedBox(height: 12),
                      if (activeJourney != null)
                        _WatchingNowStrip(journey: activeJourney)
                      else if (_nextUnwatched != null && _mediaItem != null)
                        _NextEpisodeButton(
                          item: _mediaItem!,
                          season: _nextUnwatched!.$1,
                          episode: _nextUnwatched!.$2,
                          onLogged: _load,
                        ),
                      const SizedBox(height: 14),
                      _SeasonPager(
                        seasons: episodes.seasons,
                        progress: _progress,
                        runtimeMinutes: widget.runtimeMinutes,
                        onTapWatched: _openEpisodeDetail,
                        onUnmarkWatched: _unmarkWatched,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}

/// The series' own single diary row's rating + review — same
/// "quote box with an edit pencil" language [WatchedPreviewCard] gives
/// a movie (see watched_preview_sheet.dart), just scoped to the one
/// row a whole series ever gets logged under (see [DiaryEntry]'s own
/// doc comment on why). Only ever built once that row exists — i.e.
/// once at least one season's been completed — there's nothing yet to
/// rate or review before then, so [_SeriesEpisodesSheetState] simply
/// skips this widget rather than passing it a null entry.
class _SeriesReviewCard extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onEdit;
  const _SeriesReviewCard({required this.entry, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final hasNote = entry.note != null && entry.note!.trim().isNotEmpty;
    final hasRating = entry.rating != null && entry.rating! > 0;
    // Same "won't fit in this card's own short preview" heuristic as
    // WatchedPreviewCard — see that file for the reasoning.
    final isLongNote = hasNote &&
        (entry.note!.trim().length > 220 || '\n'.allMatches(entry.note!.trim()).length >= 4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('your review'.tr, style: SeenlyText.metaLabel),
              GestureDetector(
                onTap: onEdit,
                behavior: HitTestBehavior.opaque,
                child: const Icon(Icons.edit_outlined, size: 13, color: SeenlyPalette.inkMuted),
              ),
            ],
          ),
          if (hasRating) ...[
            const SizedBox(height: 9),
            HeartRating(value: entry.rating!, size: 14),
          ],
          const SizedBox(height: 9),
          GestureDetector(
            onTap: isLongNote
                ? () => showReviewComposer(
                      context,
                      initialText: entry.note!,
                      forTitle: entry.displayTitle,
                      readOnly: true,
                    )
                : onEdit,
            child: Column(
              children: [
                Text(
                  hasNote ? '“${entry.note!.trim()}”' : 'no review left for this one yet',
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.serif(
                    italic: true,
                    size: 12.5,
                    color: hasNote ? SeenlyPalette.ink : SeenlyPalette.placeholder,
                  ),
                ),
                if (isLongNote) ...[
                  const SizedBox(height: 6),
                  Text('read the full review →'.tr,
                      style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.accent)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The entry point into logging the next episode — tapping this opens
/// the same already-watched/watching-now split (and its own quick-log
/// banner/skip-ritual offer) as any other log button in the app, see
/// [WatchingChoiceScreen], rather than assuming "watching now" and
/// jumping straight into [startEpisodeJourney].
class _NextEpisodeButton extends StatelessWidget {
  final MediaItem item;
  final int season;
  final int episode;
  // Re-runs the sheet's own _load() once the journey/log flow this
  // button starts actually finishes — without this, the episode grid
  // and header count underneath keep showing whatever was true when
  // the sheet first opened, so a just-logged episode wouldn't tick off
  // (or the whole series move to "watched") until the sheet was closed
  // and reopened, even though the save itself already went through.
  final VoidCallback onLogged;
  const _NextEpisodeButton({
    required this.item,
    required this.season,
    required this.episode,
    required this.onLogged,
  });

  @override
  Widget build(BuildContext context) {
    // Deliberately always the one house accent here, not the per-theme
    // coach/garden/ticket color this used to switch on — inside this
    // card that read as a loud, alert-colored box next to the quiet
    // plum/serif everything else uses. The theme still decides what
    // [WatchingChoiceScreen] itself looks like once this is tapped; it
    // just doesn't need to announce itself here too.
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => WatchingChoiceScreen(item: item, season: season, episode: episode),
          ),
        );
        // Always refresh, whether or not anything actually got logged —
        // a re-fetch of unchanged progress is harmless, and the return
        // value isn't reliable enough to branch on here (the choice
        // screen's own chaining into further episodes makes "was
        // anything saved" ambiguous by the time it closes anyway).
        onLogged();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: SeenlyPalette.background,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 15, color: SeenlyPalette.accent),
            const SizedBox(width: 5),
            Text('${'watch'.tr} S${season}E$episode',
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// "still on the road/in the cinema/in the garden" strip — same journey
/// this title's [ActiveJourneyBadge] entry links to, just surfaced here
/// too since the person is already looking at this show. Doesn't claim
/// to know which episode is currently playing — ActiveJourney isn't
/// episode-aware yet (that's the continuation/transfer logic, a separate
/// pass), so this only speaks to overall progress, not "S2E5 right now".
class _WatchingNowStrip extends StatelessWidget {
  final ActiveJourney journey;
  const _WatchingNowStrip({required this.journey});

  @override
  Widget build(BuildContext context) {
    final elapsed = journey.elapsedAt(DateTime.now());
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final label = LogThemeCopy.stillUnderway(journey.theme);
    return GestureDetector(
      onTap: () => openActiveJourney(context, journey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: SeenlyPalette.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              journey.isPaused ? Icons.pause_circle_outline : Icons.radio_button_checked,
              size: 16,
              color: SeenlyPalette.accent,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                journey.isPaused ? 'paused · $label' : label,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.ink, weight: FontWeight.w600),
              ),
            ),
            Text(h > 0 ? '$h:$m in' : '${elapsed.inMinutes}m in',
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 16, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// One season per page — swipe (or tap the arrows) to move between
/// seasons, each with its own poster up top the same way a movie's
/// poster anchors its own card, then that season's episodes in a
/// bounded, independently-scrolling list underneath so a season with a
/// lot of episodes doesn't fight the outer card's own scroll.
class _SeasonPager extends StatefulWidget {
  final List<Season> seasons;
  final SeriesProgress progress;
  final int? runtimeMinutes;
  final void Function(Episode) onTapWatched;
  final void Function(Episode) onUnmarkWatched;

  const _SeasonPager({
    required this.seasons,
    required this.progress,
    required this.runtimeMinutes,
    required this.onTapWatched,
    required this.onUnmarkWatched,
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
    // Land on the first season with something left unwatched — same
    // "pick up where they'd want to" default the old accordion had.
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

    return Container(
      decoration: BoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                if (season.posterUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      season.posterUrl!,
                      width: 40,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 40, height: 56),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${'season'.tr} ${season.season}',
                          style: SeenlyText.serif(italic: true, size: 14)),
                      const SizedBox(height: 2),
                      Text('$watchedCount/${season.episodes.length} ${ruPluralForm(season.episodes.length, one: 'серия', few: 'серии', many: 'серий', englishOne: 'episode', englishOther: 'episodes')}',
                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left, size: 17),
                  color: SeenlyPalette.inkFaint,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  splashRadius: 16,
                ),
                IconButton(
                  onPressed:
                      _page < widget.seasons.length - 1 ? () => _goTo(_page + 1) : null,
                  icon: const Icon(Icons.chevron_right, size: 17),
                  color: SeenlyPalette.inkFaint,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  splashRadius: 16,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: SeenlyPalette.paper),
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.seasons.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final s = widget.seasons[i];
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: s.episodes.length,
                  itemBuilder: (context, j) => _EpisodeListRow(
                    episode: s.episodes[j],
                    watched: widget.progress.isWatched(s.episodes[j].season, s.episodes[j].episode),
                    watchedAt:
                        widget.progress.watchedAtFor(s.episodes[j].season, s.episodes[j].episode),
                    rating: widget.progress.ratingFor(s.episodes[j].season, s.episodes[j].episode),
                    runtimeMinutes: widget.runtimeMinutes,
                    showDivider: j > 0,
                    onTap: () => widget.onTapWatched(s.episodes[j]),
                    onUnmark: () => widget.onUnmarkWatched(s.episodes[j]),
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
                        color: i == _page
                            ? SeenlyPalette.accent
                            : SeenlyPalette.dashedBorder,
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


class _EpisodeListRow extends StatelessWidget {
  final Episode episode;
  final bool watched;
  final DateTime? watchedAt;
  final int? rating;
  final int? runtimeMinutes;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onUnmark;

  const _EpisodeListRow({
    required this.episode,
    required this.watched,
    required this.watchedAt,
    required this.rating,
    required this.runtimeMinutes,
    required this.showDivider,
    required this.onTap,
    required this.onUnmark,
  });

  String _dateLabel(DateTime d) {
    const months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final hasTitle = episode.title != null && episode.title!.trim().isNotEmpty;
    return Column(
      children: [
        if (showDivider) Divider(height: 1, thickness: 1, color: SeenlyPalette.paper),
        InkWell(
          onTap: watched ? onTap : null,
          child: Opacity(
            opacity: watched ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  // Its own tap target, deliberately bigger than the icon
                  // itself — tapping the checkmark removes just this one
                  // episode from watched right away, no dialog; tapping
                  // the rest of the row still opens the rating dialog via
                  // the InkWell above. Only live once watched (nothing to
                  // remove otherwise, and turning an unwatched episode
                  // watched from here would skip the log ritual).
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: watched ? onUnmark : null,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        watched ? Icons.check_circle : Icons.circle_outlined,
                        size: 17,
                        color: watched ? SeenlyPalette.accent : SeenlyPalette.dashedBorder,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 22,
                    child: Text(episode.episode.toString().padLeft(2, '0'),
                        style: SeenlyText.mono(size: 10, color: watched ? SeenlyPalette.accent : SeenlyPalette.inkFaint)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasTitle ? episode.title! : 'episode ${episode.episode}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(size: 13, italic: !hasTitle, color: SeenlyPalette.ink),
                        ),
                        if (watched && rating != null) ...[
                          const SizedBox(height: 3),
                          HeartRating(value: rating!, size: 9),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (watched && watchedAt != null)
                    Text(_dateLabel(watchedAt!), style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint))
                  else if (!watched && runtimeMinutes != null)
                    Text('${runtimeMinutes}m', style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tapping a watched episode opens this — that episode's own lightweight
/// rating/note (see routers/progress.py::rate_episode), editable right
/// here. Separate from the full log ritual on purpose: rating every
/// episode you watch shouldn't mean a themed multi-step form every time,
/// and none of this creates its own diary row — see
/// episode_log_followup.dart::maybeLogCompletedSeason for how a whole
/// season's worth of these later becomes the one diary entry, averaged.
class _EpisodeRatingDialog extends StatefulWidget {
  final String mediaId;
  final String source;
  final Episode episode;
  final int? rating;
  final String? note;
  final DateTime? watchedAt;

  const _EpisodeRatingDialog({
    required this.mediaId,
    required this.source,
    required this.episode,
    required this.rating,
    required this.note,
    required this.watchedAt,
  });

  @override
  State<_EpisodeRatingDialog> createState() => _EpisodeRatingDialogState();
}

class _EpisodeRatingDialogState extends State<_EpisodeRatingDialog> {
  late int _rating = widget.rating ?? 0;
  late final TextEditingController _noteController = TextEditingController(text: widget.note ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppState>().progress.rateEpisode(
            mediaId: widget.mediaId,
            source: widget.source,
            season: widget.episode.season,
            episode: widget.episode.episode,
            rating: _rating > 0 ? _rating : null,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTitle = widget.episode.title != null && widget.episode.title!.trim().isNotEmpty;
    return Dialog(
      backgroundColor: SeenlyPalette.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'episode'.tr} ${widget.episode.episode}', style: SeenlyText.metaLabel),
            const SizedBox(height: 4),
            Text(hasTitle ? widget.episode.title! : '${'episode'.tr} ${widget.episode.episode}',
                style: SeenlyText.serif(size: 16, italic: !hasTitle)),
            const SizedBox(height: 10),
            if (widget.watchedAt != null)
              Text(
                '${'watched'.tr} ${widget.watchedAt!.day}/${widget.watchedAt!.month}/${widget.watchedAt!.year}',
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
              ),
            const SizedBox(height: 12),
            HeartRating(value: _rating, size: 18, onChanged: (v) => setState(() => _rating = v == _rating ? 0 : v)),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              minLines: 1,
              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
              decoration: InputDecoration(
                hintText: 'a quick note about this one (optional)'.tr,
                hintStyle: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  child: Text('cancel'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'saving…' : 'save',
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
