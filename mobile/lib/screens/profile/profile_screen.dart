import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app.dart';
import '../../models/achievement.dart';
import '../../models/active_journey.dart';
import '../../models/diary_entry.dart';
import '../../models/episode.dart';
import '../../models/friend.dart';
import '../../models/profile_stats.dart';
import '../../models/watchlist_entry.dart';
import '../../services/log_theme_service.dart';
import '../../services/premium_service.dart';
import '../../services/sources_display_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/log_theme_copy.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/achievement_badge.dart';
import '../../widgets/active_journey_badge.dart';
import '../../widgets/evening_plan_card.dart';
import '../../widgets/favorites_showcase_row.dart';
import '../../widgets/series_episodes_sheet.dart';
import '../../widgets/invite_friends_sheet.dart';
import '../../widgets/mosaic_poster_grid.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/planned_preview_sheet.dart';
import '../../widgets/planned_random_pick_sheet.dart';
import '../../widgets/small_pieces.dart';
import '../premium/premium_screen.dart';
import '../../widgets/watched_preview_sheet.dart';
import '../../widgets/wow_motion.dart';
import 'category_watched_screen.dart';
import 'favorite_films_screen.dart';
import '../friends/friends_screen.dart';
import '../shell/root_shell.dart';
import '../lists/lists_screen.dart';
import '../sources/sources_screen.dart';
import '../title/title_detail_screen.dart';
import 'achievements_screen.dart';
import 'level_detail_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'wrapped_screen.dart';
import '../../widgets/user_avatar.dart';
import '../../services/app_translations.dart';

const _kWeekdayAbbrev = ['', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

// -----------------------------------------------------------------------
// Placeholder figures — everything here is called out explicitly because
// there's no backend feature behind it yet (see the comment at each call
// site for what's real vs. dressed-up). Achievements and the level ring
// used to be here too; both are real now (see AchievementsScreen +
// ProfileService.achievements, and ProfileService.level) — what's left is
// just the social graph, which has no backend model at all yet.


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileData {
  final ProfileCollections collections;
  final ProfileYearStats stats;
  final WrappedStat? wrapped; // best-effort — a failed wrapped call shouldn't sink the whole profile
  final AchievementsResponse? achievements; // best-effort, same reasoning as wrapped
  final ProfileLevel? level; // best-effort, same reasoning as wrapped
  final ProfileMe? me; // best-effort, same reasoning as wrapped — carries the header's top-favorite pick
  final List<DiaryEntry> recentEntries; // newest-first, already trimmed to a handful
  final List<DiaryEntry> allEntries; // newest-first, full list — used to pull real posters per category
  const _ProfileData(this.collections, this.stats, this.wrapped, this.achievements, this.level, this.me, this.recentEntries, this.allEntries);
}

class _ProfileScreenState extends State<ProfileScreen> with RouteAware {
  late Future<_ProfileData> _future;
  int _tab = 0; // 0 = watched, 1 = plan to watch, 2 = watching now

  // How far past the top the list has been pulled — 0 whenever it's
  // resting or scrolled normally, positive only during an actual
  // overscroll drag. Drives the cover banner's zoom in _StoriesBanner (see
  // its own docstring) — a ValueNotifier rather than setState so that
  // stretch redraws every scroll frame without rebuilding the rest of
  // this fairly heavy screen.
  final ValueNotifier<double> _pullExtent = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // RootShell's IndexedStack keeps this screen alive across tab
  // switches instead of recreating it, so `initState` only ever runs
  // once — marking something "plan to watch"/"watching now"/"watched"
  // from a title screen (or logging it via search) never re-runs
  // `_load` on its own, and this tab kept showing the stale shelves
  // until a hot restart threw the cache away. Subscribing to the app's
  // shared [routeObserver] and refetching in [didPopNext] covers that:
  // any time a screen pushed on top of RootShell gets popped back — a
  // title screen, the log flow, search, wherever — Profile quietly
  // refreshes, whether or not it happens to be the visible tab right
  // then.
  //
  // Subscribes with the plain `ModalRoute` (not a `PageRoute` cast) —
  // [routeObserver] is typed on `ModalRoute` precisely so this still
  // fires when the episode-log flow was opened from a
  // `showGeneralDialog` sheet (showSeriesEpisodesSheet, reachable right
  // from this screen's own "watched" shelf) instead of a plain pushed
  // screen; see the doc comment on [routeObserver] in app.dart.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _pullExtent.dispose();
    super.dispose();
  }

  @override
  void didPopNext() => _refresh();

  Future<_ProfileData> _load() async {
    final app = context.read<AppState>();
    final mergeSources = context.read<SourcesDisplayPrefsService>().mergeIntoMainList;
    final results = await Future.wait([
      app.profile.collections(),
      app.profile.yearStats(),
      app.diary.list(),
      // Only fetched when the "mix your sources into the main list?"
      // setting is on (see SourcesDisplayPrefsService + Settings) — this
      // is the same request SourcesScreen itself makes, just folded into
      // the shelves below instead of staying on its own screen.
      if (mergeSources) app.sources.collections(),
    ]);
    var collections = results[0] as ProfileCollections;
    if (mergeSources) {
      final sourcesCollections = results[3] as ProfileCollections;
      collections = ProfileCollections(
        watchLater: [...collections.watchLater, ...sourcesCollections.watchLater],
        watching: [...collections.watching, ...sourcesCollections.watching],
        watched: [...collections.watched, ...sourcesCollections.watched],
      );
    }
    WrappedStat? wrapped;
    try {
      wrapped = await app.profile.wrapped(period: 'month');
    } catch (_) {
      // Wrapped is a bonus on this screen — if it fails, the rest of the
      // profile still renders fine without the teaser card.
    }
    AchievementsResponse? achievements;
    try {
      achievements = await app.profile.achievements();
    } catch (_) {
      // Same reasoning as wrapped above — the achievements teaser just
      // falls back to its own empty state rather than failing the screen.
    }
    ProfileLevel? level;
    try {
      level = await app.profile.level();
      app.cachedLevel = level.level;
    } catch (_) {
      // Same reasoning as wrapped/achievements above — the ring just
      // falls back to its own "not loaded" look rather than failing the
      // whole screen.
    }
    ProfileMe? me;
    try {
      me = await app.profile.me();
    } catch (_) {
      // Same reasoning as above — the favorites row just falls back to
      // its plain look with no top pick highlighted.
    }
    final allEntries = results[2] as List<DiaryEntry>; // already newest-first, see DiaryService.list
    // Keeps PremiumService's local favorites counter honest against the
    // real collections data, so the free-tier ceiling check in
    // FavoriteAddScreen/TitleDetailScreen (see canAddFavorite) reflects
    // reality even after a hot restart threw the optimistic count away.
    if (mounted) {
      context.read<PremiumService>().syncFavoritesCount(_allFavoriteMovies(collections).length);
    }
    return _ProfileData(
      collections,
      results[1] as ProfileYearStats,
      wrapped,
      achievements,
      level,
      me,
      allEntries.take(3).toList(),
      allEntries,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final logTheme = context.watch<LogThemeService>().theme;
    // Another tab (right now, just Diary's "pick something from your
    // shelf" strip) can ask to land on a specific shelf tab instead of
    // whichever one this screen was last left on — see
    // AppState.requestProfileTab. Consumed straight out of build rather
    // than initState/didChangeDependencies since this screen is kept
    // alive in RootShell's IndexedStack the whole time, so a fresh
    // request can arrive on any rebuild, not just the first one.
    final pendingTab = app.consumePendingProfileTab();
    if (pendingTab != null && pendingTab != _tab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tab = pendingTab);
      });
    }
    return FutureBuilder<_ProfileData>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return _fadeSwitch(const _ProfileSkeleton(key: ValueKey('profile-skeleton')));
        }
        if (snapshot.hasError) {
          return _fadeSwitch(RefreshIndicator(
            key: const ValueKey('profile-error'),
            onRefresh: _refresh,
            color: SeenlyPalette.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 60),
              children: [
                Text('couldn\'t load your profile'.tr,
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(italic: true, color: SeenlyPalette.inkMuted)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _refresh,
                  child: Text('pull down, or tap here, to try again'.tr,
                      textAlign: TextAlign.center,
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
                ),
              ],
            ),
          ));
        }
        final data = snapshot.data!;
        final shelf = _tab == 0
            ? data.collections.watched
            : _tab == 1
                ? data.collections.watchLater
                : const <WatchlistEntry>[];
        final journeys = app.activeJourneysList;
        // Live journeys already say "in progress" with a running timer;
        // a series can also be "in progress" from episode logging alone,
        // with no route ever started (or not started *right now*) — see
        // ProfileCollections.watching. Skip any of those whose title
        // already has a live journey above, so the same show doesn't
        // show up twice.
        final journeyMediaKeys = {
          for (final j in journeys) '${j.item.source}:${j.item.id}',
        };
        final watchingWithoutJourney = data.collections.watching
            .where((e) => !journeyMediaKeys.contains('${e.source}:${e.mediaId}'))
            .toList();
        final watchingNowCount = journeys.length + watchingWithoutJourney.length;
        final allFavoriteMovies = _allFavoriteMovies(data.collections);
        // The stories deck for the header banner — each pick resolved
        // against the account's own favorite movies, in the order the
        // person arranged them on FavoriteFilmsScreen. A pick whose
        // title has since vanished from favorites (shouldn't happen,
        // but the backend doesn't hard-guarantee it on every path) is
        // just skipped rather than shown as a blank slide.
        final favoritesByKey = {
          for (final e in allFavoriteMovies) '${e.source}:${e.mediaId}': e,
        };
        final topFavorites = <WatchlistEntry>[
          for (final pick in data.me?.topFavoritePicks ?? const [])
            if (favoritesByKey[pick.key] != null) favoritesByKey[pick.key]!,
        ];
        // Claims one stagger slot per top-level section (header, favorites
        // row, stats card, friends block, ...) — same capped cascade as
        // Home's `nextStagger` and Collections'/Diary's `nextReveal`: only
        // matters for whatever's simultaneously visible on first paint,
        // since anything scrolled to individually later has nothing to
        // cascade alongside.
        var revealSlot = 0;
        Duration nextReveal({int step = 60, int maxSlots = 4}) {
          final slot = revealSlot < maxSlots ? revealSlot : maxSlots;
          final d = Duration(milliseconds: slot * step);
          revealSlot++;
          return d;
        }
        return _fadeSwitch(RefreshIndicator(
          key: const ValueKey('profile-content'),
          onRefresh: _refresh,
          color: SeenlyPalette.accent,
          child: NotificationListener<ScrollNotification>(
            // Tracks how far past the top the list has actually been
            // pulled (RefreshIndicator's own drag, before it lets go)
            // and feeds it to the cover banner as a zoom amount — see
            // _StoriesBanner. `metrics.pixels` goes negative during that
            // pull; 0 the rest of the time (normal scroll, or once it's
            // let go and RefreshIndicator's spinner takes over).
            onNotification: (notification) {
              final pixels = notification.metrics.pixels;
              final pull = pixels < 0 ? -pixels : 0.0;
              if (_pullExtent.value != pull) _pullExtent.value = pull;
              return false;
            },
            child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                sliver: SliverToBoxAdapter(
                  child: _ProfileHeader(
                    app: app,
                    theme: logTheme,
                    stats: data.stats,
                    wrapped: data.wrapped,
                    level: data.level,
                    achievements: data.achievements,
                    topFavorites: topFavorites,
                    pullExtent: _pullExtent,
                    onChangeTopFavorite: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FavoriteFilmsScreen()),
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 0, 21, 18),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextReveal(),
                    child: FavoritesShowcaseRow(
                      entries: allFavoriteMovies,
                      topKeys: topFavorites.map((e) => '${e.source}:${e.mediaId}').toList(),
                      onSeeAll: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FavoriteFilmsScreen()),
                      ),
                      onTapEntry: (e) =>
                          showWatchedPreview(context, WatchedPreviewData.fromWatchlistEntry(e)),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextReveal(),
                    child: _StatsGridCard(stats: data.stats, watched: data.collections.watched),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(delay: nextReveal(), child: const _FriendsBlock()),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 0, 21, 4),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextReveal(),
                    riseBy: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('recently logged'.tr,
                            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)
                                .copyWith(letterSpacing: 0.6)),
                        GestureDetector(
                          onTap: () => RootShell.switchTab(context, RootShell.diaryTab),
                          child: Text('diary ›'.tr,
                              style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 0, 21, 16),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextReveal(),
                    child: _RecentlyLoggedRow(entries: data.recentEntries, theme: logTheme),
                  ),
                ),
              ),
              if (!context.watch<PremiumService>().isPremium)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  sliver: SliverToBoxAdapter(
                    child: ScrollReveal(
                      delay: nextReveal(),
                      child: _PremiumBanner(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PremiumScreen())),
                      ),
                    ),
                  ),
                ),
              if (data.wrapped != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  sliver: SliverToBoxAdapter(
                    child: ScrollReveal(
                      delay: nextReveal(),
                      child: _WrappedTeaser(
                        wrapped: data.wrapped!,
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const WrappedScreen())),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 0, 21, 4),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextReveal(),
                    riseBy: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          data.achievements != null
                              ? 'badges · ${data.achievements!.unlockedCount} of ${data.achievements!.totalCount}'
                              : 'badges',
                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)
                              .copyWith(letterSpacing: 0.6),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AchievementsScreen(initial: data.achievements),
                            ),
                          ),
                          child: Text('all ›'.tr, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 0, 21, 6),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextReveal(),
                    child: _AchievementsTeaserRow(achievements: data.achievements),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 22, 21, 4),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextReveal(),
                    child: _YourListsRow(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ListsScreen()),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 10, 21, 4),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextReveal(),
                    child: _YourSourcesRow(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SourcesScreen()),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 22)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 0, 21, 18),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(delay: nextReveal(), child: const EveningPlanCard()),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 21),
                  child: UnderlineTabRow(
                    labels: const ['watched', 'plan to watch', 'watching now'],
                    activeIndex: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(21, 16, 21, 6),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Text(
                        _tab == 2
                            ? '$watchingNowCount ${'in progress'.tr}'
                            : ruCount(shelf.length, one: 'тайтл', few: 'тайтла', many: 'тайтлов', englishOne: 'title', englishOther: 'titles'),
                        style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted),
                      ),
                      if (_tab == 1 && shelf.isNotEmpty) ...[
                        const Spacer(),
                        GestureDetector(
                          onTap: () => showPlannedRandomPickSheet(context, shelf),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Icon(Icons.casino_outlined, size: 13, color: SeenlyPalette.accent),
                              const SizedBox(width: 4),
                              Text('random'.tr, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.accent)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_tab == 2)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(21, 4, 21, 28),
                  sliver: watchingNowCount == 0
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'nothing in progress — start watching something to see it here'.tr,
                              style: SeenlyText.serif(
                                  italic: true, color: SeenlyPalette.placeholder),
                            ),
                          ),
                        )
                      : SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 2 / 3,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => ScrollReveal(
                              // Capped rather than growing with i — this
                              // is a scroll-triggered stagger, not a
                              // mount-once one, so only whichever handful
                              // of tiles enter the viewport together in a
                              // given scroll pass actually stagger
                              // against each other; nothing below the
                              // fold should be queuing up an ever-longer
                              // delay it'll never actually wait out.
                              delay: Duration(milliseconds: 35 * (i % 6)),
                              child: i < journeys.length
                                  ? _WatchingNowTile(journey: journeys[i])
                                  : _WatchingCollectionTile(
                                      entry: watchingWithoutJourney[i - journeys.length],
                                    ),
                            ),
                            childCount: watchingNowCount,
                          ),
                        ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(21, 4, 21, 28),
                  sliver: shelf.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              _tab == 0
                                  ? 'nothing marked watched yet'
                                  : 'nothing queued yet — search to add something',
                              style: SeenlyText.serif(
                                  italic: true, color: SeenlyPalette.placeholder),
                            ),
                          ),
                        )
                      : SliverToBoxAdapter(
                          child: MosaicPosterGrid(
                            itemCount: shelf.length,
                            order: List.generate(shelf.length, (i) => i),
                            revealGen: 0,
                            keyOf: (i) => shelf[i].id,
                            tileBuilder: (context, i, gridIndex, aspect) {
                              final e = shelf[i];
                              final isSeries = _tab == 0 &&
                                  (e.mediaType == 'series' || e.mediaType == 'anime');
                              return TiltPosterTile(
                                onTap: () => isSeries
                                    ? showSeriesEpisodesSheet(
                                        context,
                                        mediaId: e.mediaId,
                                        source: e.source,
                                        title: e.displayTitle,
                                        mediaType: e.mediaType,
                                        posterUrl: e.posterUrl,
                                      )
                                    : _tab == 0
                                        ? showWatchedPreview(context, WatchedPreviewData.fromWatchlistEntry(e))
                                        : showPlannedPreview(
                                            context,
                                            PlannedPreviewData.fromWatchlistEntry(e),
                                            onMarkedWatched: _refresh,
                                          ),
                                onLongPress: () => _shareEntry(e),
                                child: MosaicParallaxPoster(
                                  builder: (parallax) => ThemedPosterTile(
                                    title: e.displayTitle,
                                    posterUrl: e.posterUrl,
                                    mediaType: e.mediaType,
                                    fallbackColor: SeenlyPalette.gridColorFor(i),
                                    aspectRatio: aspect,
                                    parallax: parallax,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
            ],
          ),
          ),
        ));
      },
    );
  }

  /// Shared cross-fade for the three top-level states this screen can be
  /// in (skeleton / error / real content) — one [AnimatedSwitcher] keyed
  /// off each child's own [Key] so a transition between any two of them
  /// dissolves rather than cuts, matching Home's/Collections'/Diary's own
  /// `_fadeSwitch`. A rebuild that keeps the same state (fresh data
  /// landing under the same 'profile-content' key on refresh) is a no-op
  /// here, not a re-triggered fade.
  Widget _fadeSwitch(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

/// A quiet stand-in for Profile while the first load is in flight — rough
/// bones of the real layout (avatar row, favorites strip, stats card,
/// recently-logged row, a couple of shelves) in the same soft shimmering
/// paper tones as [ShimmerBlock], sized and spaced to roughly match what's
/// about to land underneath it. The point isn't a pixel-perfect preview —
/// it's that the very first frame already reads as *this* screen, so the
/// cross-fade into real content (see [_ProfileScreenState._fadeSwitch])
/// feels like a settle, not a swap — same reasoning as Home's, Collections'
/// and Diary's own skeletons.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton({super.key});

  static Widget _bone({double? w, double h = 16, double r = 8}) => ShimmerBlock(
        width: w,
        height: h,
        borderRadius: BorderRadius.circular(r),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bone(w: 74, h: 74, r: 37),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bone(w: 140, h: 18, r: 9),
                  const SizedBox(height: 9),
                  _bone(w: 190, h: 12, r: 6),
                  const SizedBox(height: 8),
                  _bone(w: 110, h: 12, r: 6),
                ],
              ),
            ),
            _bone(w: 30, h: 30, r: 15),
          ],
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 92,
          child: Row(
            children: [
              Expanded(child: _bone(h: 92, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 92, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 92, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 92, r: 14)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _bone(h: 108, r: 20),
        const SizedBox(height: 18),
        _bone(h: 72, r: 18),
        const SizedBox(height: 24),
        _bone(w: 150, h: 12, r: 6),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: Row(
            children: [
              Expanded(child: _bone(h: 90, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 90, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 90, r: 14)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _bone(w: 130, h: 12, r: 6),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(child: _bone(h: 64, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 64, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 64, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 64, r: 14)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _bone(h: 48, r: 14),
        const SizedBox(height: 10),
        _bone(h: 48, r: 14),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header — avatar (with a themed corner badge), name, a bio line built from
// the person's own real top genre when there is one, the join date, and the
// settings gear. Follow counts are placeholder — see the constants up top;
// there's no social graph behind Seenly yet.
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  final AppState app;
  final LogTheme theme;
  final ProfileYearStats stats;
  final WrappedStat? wrapped;
  final ProfileLevel? level;
  final AchievementsResponse? achievements;
  // The stories deck for the header banner (see ProfileMe.topFavoritePicks)
  // — swiped through like a stories row. Empty until someone picks at
  // least one on FavoriteFilmsScreen, in which case the banner falls
  // back to a plain tinted invitation to go pick one.
  final List<WatchlistEntry> topFavorites;
  final VoidCallback onChangeTopFavorite;
  // Overscroll-pull amount, fed straight through to the cover banner's
  // zoom (see _StoriesBanner) — see _ProfileScreenState._pullExtent.
  final ValueListenable<double> pullExtent;
  const _ProfileHeader({
    required this.app,
    required this.theme,
    required this.stats,
    required this.wrapped,
    required this.level,
    this.achievements,
    this.topFavorites = const [],
    required this.onChangeTopFavorite,
    required this.pullExtent,
  });

  static const double _bannerHeight = 190;
  static const double _avatarSize = 88;
  // How much of the avatar sits up over the banner's bottom edge, rather
  // than below it — a Pinterest-style cover-photo overlap, not just a
  // bigger version of the old inline avatar.
  static const double _avatarOverlap = 34;

  String get _bio {
    if (stats.topGenres.isEmpty) return LogThemeCopy.bioFallback(theme);
    return LogThemeCopy.bioWithGenre(theme, stats.topGenres.first.genre.toLowerCase());
  }

  List<Achievement> get _pinnedAchievements {
    final data = achievements;
    if (data == null || data.pinnedIds.isEmpty) return const [];
    final byId = {for (final a in data.achievements) a.id: a};
    return [
      for (final id in data.pinnedIds)
        if (byId[id] != null) byId[id]!
    ];
  }

  @override
  Widget build(BuildContext context) {
    final badgeBg = theme == LogTheme.garden
        ? SeenlyPalette.sage.withOpacity(0.28)
        : SeenlyPalette.tapeMustard;
    final badgeIconColor = theme == LogTheme.garden ? SeenlyPalette.sage : SeenlyPalette.clay;
    final stackHeight = _bannerHeight + (_avatarSize - _avatarOverlap) + 10;

    // The header opens with a wide cover banner — the current top-favorite
    // pick's poster, cropped to fill a horizontal frame instead of its
    // usual vertical 2:3 — with the bigger avatar sitting half over its
    // bottom edge, left-aligned. Name/bio/badges follow underneath as a
    // plain flow, same as before; only the avatar+cover live inside this
    // Stack. No card frame behind any of it — this rests directly on the
    // page background, same as everything else on Profile now.
    return Entrance(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: stackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  // Its own drop-in, separate from the Entrance fade+rise
                  // wrapping the whole header below — a wide banner just
                  // rising the same tiny 26px as everything else reads as
                  // barely moving at all, so it gets a real slide down
                  // from above instead, on top of (not instead of) the
                  // header's own settle.
                  child: BannerReveal(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        height: _bannerHeight,
                        width: double.infinity,
                        child: _StoriesBanner(
                          entries: topFavorites,
                          onTap: onChangeTopFavorite,
                          pullExtent: pullExtent,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _ChangeFavoriteButton(onTap: onChangeTopFavorite),
                ),
                Positioned(
                  top: _bannerHeight + 10,
                  right: 2,
                  child: PressScale(
                    scaleTo: 0.85,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    child: Icon(Icons.settings_outlined, size: 17, color: SeenlyPalette.inkMuted),
                  ),
                ),
                Positioned(
                  top: _bannerHeight - _avatarOverlap + 10,
                  left: 4,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LevelDetailScreen(stats: stats, wrapped: wrapped, initial: level),
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // A soft shadow behind the avatar itself, plus a
                        // paper-colored ring so it reads as a framed
                        // portrait resting half on the cover photo, half
                        // on the page — not a flat circle cut into either.
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SeenlyPalette.paper,
                            boxShadow: [
                              BoxShadow(
                                color: SeenlyPalette.ink.withOpacity(0.22),
                                blurRadius: 16,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: UserAvatar(
                            avatarUrl: app.currentUser?.avatarUrl,
                            avatarPreset: app.currentUser?.avatarPreset,
                            fallbackLetter: (app.currentUser?.username.isNotEmpty ?? false)
                                ? app.currentUser!.username.substring(0, 1).toLowerCase()
                                : '?',
                            size: _avatarSize,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: badgeBg,
                              shape: BoxShape.circle,
                              border: Border.all(color: SeenlyPalette.paper, width: 2),
                            ),
                            child: Icon(LogThemeCopy.avatarBadgeIcon(theme), size: 11, color: badgeIconColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Nickname + level ring + status, placed to the right of the
                // avatar instead of stacked underneath it — lines up with
                // the lower half of the avatar, the part that rests on the
                // plain page background below the cover banner.
                Positioned(
                  top: _bannerHeight + 14,
                  left: 4 + _avatarSize + 14,
                  right: 40,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LevelDetailScreen(stats: stats, wrapped: wrapped, initial: level),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(app.currentUser?.nameForDisplay ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: SeenlyText.serif(size: 19, italic: true, weight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 8),
                            _LevelRing(theme: theme, level: level, size: 32),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // A small opening quote before the status/bio line —
                        // a quiet nod to this being a personal diary entry
                        // about yourself, not just a form field, without
                        // adding any extra UI chrome.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('“'.tr,
                                style: SeenlyText.serif(
                                    size: 13, italic: true, color: SeenlyPalette.accent.withOpacity(0.55))),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                  (app.currentUser?.statusText?.isNotEmpty ?? false)
                                      ? app.currentUser!.statusText!
                                      : _bio,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pinned badges — up to 3 chosen from the tap-to-pin
                // interaction on AchievementsScreen, shown right in the
                // header itself ("here's what I'm proud of") rather than
                // further down the scroll. Small and label-less on purpose
                // — this is a glance, not the showcase; AchievementsScreen
                // is still where each one gets its full explanation.
                // Absent entirely until something's actually pinned.
                if (_pinnedAchievements.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (int i = 0; i < _pinnedAchievements.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        RoundBadgeMedallion(
                          iconKey: _pinnedAchievements[i].iconKey,
                          title: _pinnedAchievements[i].title,
                          rarity: _pinnedAchievements[i].rarity,
                          pinned: true,
                          diameter: 30,
                          showLabel: false,
                          onTap: () => showBadgeDetailCard(
                            context,
                            achievement: _pinnedAchievements[i],
                            pinned: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The header's cover banner — swipeable like a stories deck across up
/// to 5 favorite-film picks (see ProfileMe.topFavoritePicks), each
/// cropped to a wide frame instead of its usual vertical 2:3, with a
/// faint bottom scrim so the overlapping avatar's ring and the
/// change-favorite pill both stay readable over busy artwork. A thin
/// segmented bar along the top tracks position the same way Instagram/
/// Stories does, auto-advancing every few seconds when there's more
/// than one slide; a long-press pauses it, and releasing (or swiping,
/// which resets the clock to wherever it lands) picks back up. Tapping
/// the left/right edge steps a slide at a time; tapping the middle band
/// opens the same favorite-picker [onTap] the old single-cover banner
/// used for any tap.
class _StoriesBanner extends StatefulWidget {
  final List<WatchlistEntry> entries;
  final VoidCallback onTap;
  // See _ProfileScreenState._pullExtent — 0 at rest, positive while the
  // list is being dragged down past its top.
  final ValueListenable<double> pullExtent;
  const _StoriesBanner({required this.entries, required this.onTap, required this.pullExtent});

  @override
  State<_StoriesBanner> createState() => _StoriesBannerState();
}

class _StoriesBannerState extends State<_StoriesBanner> with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(milliseconds: 10000);

  late final PageController _pageController = PageController();
  late final AnimationController _progress = AnimationController(vsync: this, duration: _slideDuration)
    ..addStatusListener(_onProgressStatus);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant _StoriesBanner old) {
    super.didUpdateWidget(old);
    // The deck can change size (a pick added/removed elsewhere while
    // this screen is still mounted, e.g. via pull-to-refresh) — clamp
    // the current slide back into range rather than pointing at
    // nothing, and restart the clock for whatever's now showing.
    if (old.entries.length != widget.entries.length && widget.entries.isNotEmpty) {
      _index = _index.clamp(0, widget.entries.length - 1);
      _restart();
    }
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _advance(1);
  }

  void _maybeStart() {
    if (widget.entries.length > 1) {
      _progress.forward(from: 0);
    } else {
      _progress.value = widget.entries.isEmpty ? 0 : 1;
    }
  }

  void _restart() {
    _progress.stop();
    _maybeStart();
  }

  void _advance(int delta) {
    if (widget.entries.length <= 1) return;
    final next = _index + delta;
    if (next < 0 || next >= widget.entries.length) {
      // Loops back to the start rather than stalling on the last slide
      // — a stories deck that dead-ends reads as broken, not finished.
      _pageController.jumpToPage(0);
      return;
    }
    _pageController.animateToPage(next, duration: const Duration(milliseconds: 550), curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _progress.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    return ValueListenableBuilder<double>(
      valueListenable: widget.pullExtent,
      builder: (context, pull, child) {
        final scale = 1.0 + (pull / 320).clamp(0.0, 0.15);
        return Transform.scale(scale: scale, alignment: Alignment.center, child: child);
      },
      child: GestureDetector(
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (entries.isEmpty)
              GestureDetector(onTap: widget.onTap, child: _fallback())
            else
              PageView.builder(
                controller: _pageController,
                itemCount: entries.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _restart();
                },
                // Slides crossfade into each other as the page settles,
                // rather than the flat hard cut a bare PageView gives —
                // each slide's opacity tracks how close it is to being
                // the current page, for both the auto/edge-tap animateToPage
                // glide and a manual swipe.
                itemBuilder: (context, i) => AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, child) {
                    double page = i.toDouble();
                    if (_pageController.hasClients && _pageController.position.haveDimensions) {
                      page = _pageController.page ?? _index.toDouble();
                    }
                    final delta = (page - i).abs().clamp(0.0, 1.0);
                    return Opacity(opacity: 1 - delta, child: child);
                  },
                  child: _Slide(entry: entries[i]),
                ),
              ),
            // Bottom scrim for legibility, not decoration — just enough to
            // keep the avatar's ring and the pill button from disappearing
            // into a bright or busy poster.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black26],
                  stops: [0.55, 1.0],
                ),
              ),
            ),
            if (entries.length > 1)
              Positioned(
                top: 8,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    for (int i = 0; i < entries.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (context, _) => _SegmentBar(
                            fill: i < _index ? 1.0 : (i == _index ? _progress.value : 0.0),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (entries.isNotEmpty)
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _advance(-1),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: widget.onTap,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _advance(1),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SeenlyPalette.tapeRose, SeenlyPalette.cork],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          'выбери любимые фильмы'.tr,
          style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted),
        ),
      );
}

/// One slide of the stories banner — the wide backdrop still image (same
/// field the title screen's own hero banner uses — see
/// TitleDetailScreen's _PosterBanner) instead of the vertical poster, a
/// real horizontal shot rather than a cropped-down portrait frame.
/// Falls back to the poster only for the rare title that has no
/// backdrop on file.
class _Slide extends StatelessWidget {
  final WatchlistEntry entry;
  const _Slide({required this.entry});

  @override
  Widget build(BuildContext context) {
    final url = entry.backdropUrl ?? entry.posterUrl;
    if (url == null || url.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SeenlyPalette.tapeRose, SeenlyPalette.cork],
          ),
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (_, __, ___) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SeenlyPalette.tapeRose, SeenlyPalette.cork],
          ),
        ),
      ),
    );
  }
}

/// One pill of the stories progress bar — a rounded track with a
/// gently-eased fill, softer than Instagram's hard-edged version to
/// match this app's paper-and-ink language.
class _SegmentBar extends StatelessWidget {
  final double fill;
  const _SegmentBar({required this.fill});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            Container(color: Colors.white.withOpacity(0.32)),
            FractionallySizedBox(
              widthFactor: fill.clamp(0.0, 1.0),
              child: Container(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// The button sitting top-right on the cover banner — the only place this
/// screen offers "change your top favorite" as an explicit action, rather
/// than folding it into the star on FavoriteFilmsScreen alone. Just the
/// pencil, no backdrop — a soft drop shadow on the icon itself keeps it
/// legible over busy artwork instead of a filled pill behind it.
class _ChangeFavoriteButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ChangeFavoriteButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scaleTo: 0.88,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        child: const Icon(
          Icons.edit_outlined,
          size: 18,
          color: Colors.white,
          shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friends block — its own self-contained fetch (like Home's co-viewing
// card) rather than riding on ProfileScreen's big Future.wait, since
// accepting/declining a request here shouldn't force a refetch of the
// whole profile. See backend/app/routers/friends.py for the data model.
// ---------------------------------------------------------------------------

class _FriendsBlock extends StatefulWidget {
  const _FriendsBlock();

  @override
  State<_FriendsBlock> createState() => _FriendsBlockState();
}

class _FriendsBlockState extends State<_FriendsBlock> {
  FriendsData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppState>().friends.list();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openFriendsScreen() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen())).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final friends = _data?.friends ?? const [];
    final incoming = _data?.incomingRequests.length ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressScale(
            haptics: true,
            onTap: _openFriendsScreen,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('friends'.tr, style: SeenlyText.sectionTitle),
                // A quiet pill instead of a bare "see all" link once
                // there's something to actually flag — a plain trailing
                // label doesn't compete with the eye for attention the
                // way a request genuinely deserves to.
                if (incoming > 0)
                  BreathingGlow(
                    color: SeenlyPalette.coral,
                    size: 30,
                    period: const Duration(milliseconds: 3400),
                    maxOpacity: 0.28,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.coral,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$incoming ${'new ›'.tr}',
                          style: SeenlyText.mono(size: 10, color: Colors.white, weight: FontWeight.w700)),
                    ),
                  )
                else
                  Text('see all ›'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
              ),
            )
          else
            PressScale(
              haptics: true,
              onTap: _openFriendsScreen,
              child: friends.isEmpty
                  ? Text(
                      "you haven't added any friends yet — search a username or invite someone".tr,
                      style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ..._avatarStack(friends),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                CountUpNumber(
                                  value: friends.length.toDouble(),
                                  decimals: 0,
                                  style: SeenlyText.serif(size: 20, weight: FontWeight.w700),
                                ),
                                const SizedBox(width: 4),
                                Text(ruPluralForm(friends.length, one: 'друг', few: 'друга', many: 'друзей', englishOne: 'friend', englishOther: 'friends'),
                                    style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
                              ],
                            ),
                            Text('tap to see everyone'.tr,
                                style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                          ],
                        ),
                      ],
                    ),
            ),
          const SizedBox(height: 12),
          // A small dashed pill rather than a bare underlined link —
          // reads as an actual invite, same "open slot waiting to be
          // filled" language DashedBox uses for every other empty
          // collection in the app.
          PressScale(
            haptics: true,
            onTap: () => showInviteFriendsSheet(context),
            child: DashedBox(
              radius: 20,
              color: SeenlyPalette.accent.withOpacity(0.4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_add_alt_1_rounded, size: 13, color: SeenlyPalette.accent),
                    const SizedBox(width: 6),
                    Text('invite friends'.tr,
                        style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _avatarStack(List<Friend> friends) {
    const maxShown = 4;
    final shown = friends.take(maxShown).toList();
    final overflow = friends.length - shown.length;
    return [
      SizedBox(
        height: 34,
        width: shown.length * 22.0 + (overflow > 0 ? 22 : 0) + 8,
        child: Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * 22.0,
                child: UserAvatar(
                  avatarUrl: shown[i].avatarUrl,
                  avatarPreset: shown[i].avatarPreset,
                  fallbackLetter: shown[i].username.isNotEmpty ? shown[i].username[0].toUpperCase() : '?',
                  size: 34,
                  borderColor: SeenlyPalette.paper,
                ),
              ),
            // A "+N" stub for whatever didn't fit in the stack, so the
            // count text below isn't the only place the real total
            // shows up.
            if (overflow > 0)
              Positioned(
                left: shown.length * 22.0,
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SeenlyPalette.cork,
                    border: Border.all(color: SeenlyPalette.paper, width: 2),
                  ),
                  child: Text('+$overflow',
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkMuted, weight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Streak card. The streak figure is real (ProfileYearStats.streakDays, same
// number the old two-tile row used to show) with a themed headline; the
// "longest" subline only appears when this month's Wrapped actually has a
// longest-streak figure to show, and is skipped rather than invented
// otherwise. The level ring used to live on the right of this card — it now
// sits up in the header next to the avatar/name (see _ProfileHeader), but
// tapping anywhere on this card still opens LevelDetailScreen (see
// ProfileService.level / backend/app/routers/profile.py::get_level for the
// xp formula), same full-screen breakdown of where the xp came from.
// ---------------------------------------------------------------------------

class _StreakAndLevelCard extends StatelessWidget {
  final LogTheme theme;
  final ProfileYearStats stats;
  final WrappedStat? wrapped;
  final ProfileLevel? level;
  const _StreakAndLevelCard({required this.theme, required this.stats, required this.wrapped, required this.level});

  @override
  Widget build(BuildContext context) {
    final best = wrapped?.longestStreak;
    final headline = LogThemeCopy.streakHeadline(theme, stats.streakDays);
    final subline = (best != null && best > 0) ? LogThemeCopy.streakBest(theme, best) : null;

    return Transform.rotate(
      angle: -0.5 * math.pi / 180,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LevelDetailScreen(stats: stats, wrapped: wrapped, initial: level),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: SeenlyPalette.paper,
              borderRadius: BorderRadius.circular(16),
              boxShadow: SeenlyPalette.softShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (theme != LogTheme.garden) _TicketStub(theme: theme),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: [
                          if (theme == LogTheme.garden) ...[
                            const SizedBox(width: 34, height: 50, child: CustomPaint(painter: _SproutPainter())),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(headline, style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
                                if (subline != null) ...[
                                  const SizedBox(height: 3),
                                  Text(subline, style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkMuted)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed-divider strip on the left of the ticket/coach streak card —
/// "ADMIT ONE" for ticket, a plain pin icon for coach. Garden skips this
/// entirely in favor of the sprout illustration (see _StreakAndLevelCard).
class _TicketStub extends StatelessWidget {
  final LogTheme theme;
  const _TicketStub({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      decoration: BoxDecoration(
        color: SeenlyPalette.tapeMustard,
        border: Border(right: BorderSide(color: SeenlyPalette.tapeRose, width: 1.5)),
      ),
      alignment: Alignment.center,
      child: theme == LogTheme.ticket
          ? RotatedBox(
              quarterTurns: 3,
              child: Text('ADMIT ONE'.tr,
                  style: SeenlyText.mono(size: 7, color: SeenlyPalette.clay)
                      .copyWith(letterSpacing: 2)),
            )
          : theme == LogTheme.shuttle
              ? Icon(Icons.rocket_launch_outlined, size: 13, color: SeenlyPalette.clay)
              : Icon(Icons.location_on_outlined, size: 13, color: SeenlyPalette.clay),
    );
  }
}

/// The level ring — real xp/level from the backend (see ProfileService.level
/// / get_level). Lives in the profile header now, right next to the avatar
/// and name (see _ProfileHeader), sized down via [size] to fit there; the
/// streak card below still opens the same detail screen on tap. While the
/// level is still loading, or if that best-effort call failed, this falls
/// back to an empty level-1 ring rather than blocking on it. Only the
/// decorative marks around the ring change per theme: sprocket dots for
/// ticket, spokes for coach, a plain track for garden.
/// Simple filled-ring level indicator — accent arc over a muted track,
/// number centred in a clean paper disc. No theme decorations, no "lvl"
/// label: the context makes it obvious.
class _LevelRing extends StatefulWidget {
  final LogTheme theme;
  final ProfileLevel? level;
  final double size;
  const _LevelRing({required this.theme, required this.level, this.size = 52});

  @override
  State<_LevelRing> createState() => _LevelRingState();
}

class _LevelRingState extends State<_LevelRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  late Animation<double> _progress;
  double _target = 0;

  @override
  void initState() {
    super.initState();
    _target = (widget.level?.progress ?? 0.0).clamp(0.0, 1.0);
    _progress =
        Tween<double>(begin: 0, end: _target).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    // A small pre-fill delay so the ring's own fill reads as a distinct
    // beat right after the header settles in (see Entrance on the header
    // above it) rather than fighting that same motion for attention.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didUpdateWidget(covariant _LevelRing old) {
    super.didUpdateWidget(old);
    // A pull-to-refresh that changes the level (e.g. logging something
    // just bumped it) re-fills from wherever the ring currently sits to
    // the new value rather than snapping — same "count up, don't jump"
    // spirit as the stat numbers below. Rebuilding the tween (not just
    // restarting the same one) is what makes this work: the old tween's
    // `end` is fixed forever once created.
    final next = (widget.level?.progress ?? 0.0).clamp(0.0, 1.0);
    if (next != _target) {
      final current = _progress.value;
      _target = next;
      _progress = Tween<double>(begin: current, end: next)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
      _c
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayLevel = widget.level?.level ?? 1;
    final size = widget.size;
    // Slightly thicker stroke so the ring reads clearly at small sizes.
    final strokeWidth = (size * 0.12).clamp(3.0, 6.0);
    final innerSize = size - strokeWidth * 2.4;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _progress,
            builder: (context, _) => CustomPaint(
              size: Size(size, size),
              painter: _RingArcPainter(
                progress: _progress.value,
                trackColor: SeenlyPalette.border,
                progressColor: SeenlyPalette.accent,
                strokeWidth: strokeWidth,
              ),
            ),
          ),
          Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              color: SeenlyPalette.paper,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: SeenlyPalette.ink.withOpacity(0.10),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$displayLevel',
                style: SeenlyText.serif(
                  size: 13,
                  weight: FontWeight.w700,
                  color: SeenlyPalette.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the accent progress ring as a rounded stroke over a neutral track
/// stroke — a thin halo around the floating level disc, rather than a
/// filled pie slice behind it.
class _RingArcPainter extends CustomPainter {
  final double progress; // 0..1
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;
  const _RingArcPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final center = rect.center;
    final radius = rect.width / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = progressColor;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.strokeWidth != strokeWidth;
}



/// A little window-box sprout, traced from the same illustration used in
/// the garden-theme reference mockup — three leaf pairs and a bud, not a
/// generic plant icon.
class _SproutPainter extends CustomPainter {
  const _SproutPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 40;
    final sy = size.height / 56;
    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final stem = Paint()
      ..color = SeenlyPalette.sage
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(20, 54), p(20, 14), stem);

    void leaf(double cx, double cy, double rx, double ry, double degrees, Color color) {
      canvas.save();
      canvas.translate(cx * sx, cy * sy);
      canvas.rotate(degrees * math.pi / 180);
      canvas.scale(sx, sy);
      final paint = Paint()..color = color;
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), paint);
      canvas.restore();
    }

    leaf(12, 42, 9, 5, -25, SeenlyPalette.sage);
    leaf(28, 42, 9, 5, 25, const Color(0xFF729566));
    leaf(11, 27, 8, 4.5, -20, SeenlyPalette.sage);
    leaf(29, 27, 8, 4.5, 20, const Color(0xFF729566));
    leaf(20, 13, 6.5, 8.5, 0, const Color(0xFF9FB593));
  }

  @override
  bool shouldRepaint(covariant _SproutPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Stats card — all six figures are real (ProfileYearStats), same numbers
// the old grid of six tiles used to show. Now a shelf-style list: movies
// settles in first, series eases in a beat behind it, then a "show all"
// row invites the rest (games/anime/books/manga) to unfold below, with a
// matching collapse. Every color and shape here is already load-bearing
// elsewhere in the app (SeenlyPalette.mediaColor family, softShadow,
// SeenlyText) — this just arranges them shelf-row style instead of a grid.
// Poster previews are pulled from the "watched" shelf (ProfileCollections
// .watched, from /profile/collections) rather than the diary — the same
// source the watched/plan-to-watch/watching-now tabs further down this
// screen already use, so a title shows here exactly when it shows there.
// ---------------------------------------------------------------------------

class _StatsGridCard extends StatefulWidget {
  final ProfileYearStats stats;
  // Posters come from the "watched" shelf (ProfileCollections.watched —
  // same data the watched/plan-to-watch/watching-now tabs further down
  // this screen use) rather than the diary, so a title logged more than
  // once or without a poster on its most recent diary entry still shows
  // up here correctly.
  final List<WatchlistEntry> watched;
  const _StatsGridCard({required this.stats, required this.watched});

  @override
  State<_StatsGridCard> createState() => _StatsGridCardState();
}

class _StatsGridCardState extends State<_StatsGridCard>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _moviesFade;
  late final Animation<Offset> _moviesSlide;
  late final Animation<double> _seriesFade;
  late final Animation<Offset> _seriesSlide;
  late final Animation<double> _moreFade;

  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _moviesFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _moviesSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(_moviesFade);
    _seriesFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.35, 0.8, curve: Curves.easeOut),
    );
    _seriesSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(_seriesFade);
    _moreFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    );
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  void _openCategory(String label, List<WatchlistEntry> entries) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryWatchedScreen(label: label, entries: entries),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final primary = <(IconData, int, String, Color)>[
      (Icons.movie_outlined, stats.movies, 'movies', SeenlyPalette.coral),
      (Icons.tv_outlined, stats.series, 'series', SeenlyPalette.sage),
    ];
    final rest = <(IconData, int, String, Color)>[
      (Icons.sports_esports_outlined, stats.games, 'games', SeenlyPalette.periwinkle),
      (Icons.auto_awesome_outlined, stats.anime, 'anime', SeenlyPalette.mustard),
      (Icons.menu_book_outlined, stats.books, 'books', SeenlyPalette.pink),
      (Icons.auto_stories_outlined, stats.manga, 'manga', SeenlyPalette.clay),
    ];
    final restTotal = rest.fold<int>(0, (sum, e) => sum + e.$2);

    // watchlist entries use the singular media type ("movie", "book", ...)
    // while the labels above are plural for display — map label -> type.
    const typeForLabel = <String, String>{
      'movies': 'movie',
      'series': 'series',
      'games': 'game',
      'anime': 'anime',
      'books': 'book',
      'manga': 'manga',
    };
    // The watched shelf can carry more than one row for the same title
    // (e.g. a rewatch, or the same source appearing twice after merging
    // in "your sources" — see AppState.sources / mergeIntoMainList in
    // _ProfileScreenState._load). This card counts and shows *titles*,
    // not watch events, so collapse to one row per title (source:mediaId)
    // before splitting into categories below.
    final seenTitles = <String>{};
    final dedupedWatched = <WatchlistEntry>[];
    for (final e in widget.watched) {
      final key = '${e.source}:${e.mediaId}';
      if (seenTitles.add(key)) dedupedWatched.add(e);
    }

    final postersByLabel = <String, List<WatchlistEntry>>{};
    final watchedByLabel = <String, List<WatchlistEntry>>{};
    for (final label in typeForLabel.keys) {
      final type = typeForLabel[label];
      final matches = dedupedWatched.where((e) => e.mediaType == type).toList();
      watchedByLabel[label] = matches;
      postersByLabel[label] =
          matches.where((e) => e.posterUrl?.isNotEmpty ?? false).take(3).toList();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeTransition(
            opacity: _moviesFade,
            child: SlideTransition(
              position: _moviesSlide,
              child: _CategoryRow(
                icon: primary[0].$1,
                value: primary[0].$2,
                label: primary[0].$3,
                color: primary[0].$4,
                posters: postersByLabel[primary[0].$3] ?? const [],
                onTap: () => _openCategory(primary[0].$3, watchedByLabel[primary[0].$3] ?? const []),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FadeTransition(
            opacity: _seriesFade,
            child: SlideTransition(
              position: _seriesSlide,
              child: _CategoryRow(
                icon: primary[1].$1,
                value: primary[1].$2,
                label: primary[1].$3,
                color: primary[1].$4,
                posters: postersByLabel[primary[1].$3] ?? const [],
                onTap: () => _openCategory(primary[1].$3, watchedByLabel[primary[1].$3] ?? const []),
                // The last row visible before "show all" — cut short with
                // a blurred bottom edge as a visual "there's more just
                // below" cue, same idea as a half-open drawer. Flips back
                // to a normal full poster the instant _expanded flips
                // true, since at that point it no longer IS the last row
                // (games/anime/books/manga now follow it directly).
                peek: !_expanded,
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      for (final e in rest)
                        Container(
                          padding: const EdgeInsets.only(top: 14),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: SeenlyPalette.border, width: 0.6),
                            ),
                          ),
                          child: _CategoryRow(
                            icon: e.$1,
                            value: e.$2,
                            label: e.$3,
                            color: e.$4,
                            posters: postersByLabel[e.$3] ?? const [],
                            onTap: () => _openCategory(e.$3, watchedByLabel[e.$3] ?? const []),
                          ),
                        ),
                    ],
                  ),
          ),
          FadeTransition(
            opacity: _moreFade,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _ExpandToggle(
                expanded: _expanded,
                remainingCount: restTotal,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: SeenlyPalette.border, width: 0.6)),
            ),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StatsScreen())),
              child: Row(
                children: [
                  Icon(Icons.bar_chart_rounded, size: 15, color: SeenlyPalette.accent),
                  const SizedBox(width: 7),
                  Text('подробная статистика'.tr,
                      style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.accent, weight: FontWeight.w600)),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 15, color: SeenlyPalette.accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One shelf row: icon in a soft tinted circle, label + count on top, a
/// little strip underneath standing in for the titles themselves — the
/// actual posters of the most recently logged entries in this category
/// when we have them, a flat color swatch per entry as a fallback when a
/// title has no poster on file, and a single dashed placeholder when
/// there's nothing logged there yet (same dashedBorder tone the rest of
/// the app already uses for empty states).
class _CategoryRow extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final Color color;
  final List<WatchlistEntry> posters; // up to 3, from the watched shelf, only entries with a real poster
  final VoidCallback onTap;
  // When true (only ever the row sitting right above "show all" while
  // collapsed — see _StatsGridCardState.build), the posters below are
  // shown cut short with a blurred bottom edge instead of at full
  // height. Purely decorative — a "there's more just below" cue, not a
  // different data shape.
  final bool peek;
  const _CategoryRow({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.posters,
    required this.onTap,
    this.peek = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Text(label.tr, style: SeenlyText.serif(size: 14.5, weight: FontWeight.w600, italic: true)),
              const Spacer(),
              CountUpNumber(
                value: value.toDouble(),
                decimals: 0,
                duration: const Duration(milliseconds: 900),
                style: SeenlyText.serif(size: 14, weight: FontWeight.w600, color: SeenlyPalette.inkMuted),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 15, color: SeenlyPalette.inkFaint),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.zero,
          child: posters.isNotEmpty
              ? _posterRow(context)
              : (value > 0
                  ? GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: _swatchRow())
                  : GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: _emptySwatch())),
        ),
      ],
    );
  }

  Widget _posterRow(BuildContext context) {
    final count = posters.length >= 3 ? 3 : posters.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: peek
                ? _peekPosterTile(context, i)
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showWatchedPreview(context, WatchedPreviewData.fromWatchlistEntry(posters[i])),
                    child: ThemedPosterTile(
                      title: posters[i].displayTitle,
                      posterUrl: posters[i].posterUrl,
                      mediaType: posters[i].mediaType,
                      fallbackColor: color.withOpacity(0.75 - i * 0.14),
                    ),
                  ),
          ),
        ],
        if (count < 3) ...[
          const SizedBox(width: 6),
          Expanded(flex: 3 - count, child: const SizedBox.shrink()),
        ],
      ],
    );
  }

  // Same 2:3 aspect ratio ThemedPosterTile itself renders at (kept in
  // sync here since this deliberately doesn't render a full
  // ThemedPosterTile at all — it needs the poster's *natural* full
  // height available to clip against, not whatever height a shrunk
  // container would give it).
  static const _posterAspectRatio = 2 / 3;

  /// The collapsed peek treatment: the poster's top ~58% at full size,
  /// clipped short, with its own bottom edge blurred (a real,
  /// gradually-thickening BackdropFilter blur — not one uniform blur
  /// switched on at a hard line, which reads as a layout bug rather
  /// than an intentional "there's more below") and faded toward the
  /// card's paper background underneath the blur for a softer seam.
  Widget _peekPosterTile(BuildContext context, int i) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullHeight = constraints.maxWidth / _posterAspectRatio;
        final peekHeight = fullHeight * 0.58;
        final blurBandHeight = peekHeight * 0.4;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showWatchedPreview(context, WatchedPreviewData.fromWatchlistEntry(posters[i])),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: peekHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: fullHeight,
                    maxHeight: fullHeight,
                    child: ThemedPosterTile(
                      title: posters[i].displayTitle,
                      posterUrl: posters[i].posterUrl,
                      mediaType: posters[i].mediaType,
                      fallbackColor: color.withOpacity(0.75 - i * 0.14),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: blurBandHeight,
                    child: _ProgressiveBlurBand(height: blurBandHeight),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _swatchRow() {
    final count = value >= 3 ? 3 : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.75 - i * 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
        if (count < 3) ...[
          const SizedBox(width: 6),
          Expanded(flex: 3 - count, child: const SizedBox.shrink()),
        ],
      ],
    );
  }

  Widget _emptySwatch() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('nothing here yet'.tr, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.placeholder)),
    );
  }
}

/// A soft, gradually-thickening blur band for the bottom edge of a
/// "peeked" poster (see `_CategoryRow._peekPosterTile`).
///
/// A single BackdropFilter has one fixed blur strength across its whole
/// area, so no matter how soft the color gradient laid over it looks,
/// the *blur itself* still switches on at a hard line the instant the
/// filter's clip rect begins — that line is what read as a sharp edge
/// rather than a smooth transition. This stacks several blur strengths,
/// each faded in over a slightly lower/wider band via its own gradient
/// mask, so the blur ramps up top-to-bottom instead of turning on all
/// at once — the same trick behind iOS's "variable blur". A plain
/// paper-colored gradient sits on top so the band still settles into
/// the card's background at the very bottom.
class _ProgressiveBlurBand extends StatelessWidget {
  final double height;
  const _ProgressiveBlurBand({required this.height});

  // Blur strength per layer, weakest (near-invisible) at the top of the
  // band to strongest at the bottom.
  static const _sigmas = [1.0, 2.5, 5.0, 9.0, 15.0];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (int layer = 0; layer < _sigmas.length; layer++) _blurLayer(layer),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  SeenlyPalette.paper.withOpacity(0.0),
                  SeenlyPalette.paper.withOpacity(0.85),
                ],
                stops: const [0.3, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blurLayer(int layer) {
    // Each successive layer's mask starts a bit lower and reaches full
    // strength a bit lower still than the one before it, so the sigma
    // values above blend into one continuously thickening blur instead
    // of a stack of visibly discrete bands.
    final start = layer / (_sigmas.length + 1);
    final end = (layer + 2) / (_sigmas.length + 1);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Colors.transparent, Colors.white],
        stops: [start, end.clamp(0.0, 1.0)],
      ).createShader(rect),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: _sigmas[layer], sigmaY: _sigmas[layer]),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}

/// The "show all" / "collapse" row. Soft accent-tinted pill, chevron
/// flips in place rather than swapping icons so the motion reads as one
/// continuous gesture instead of two.
class _ExpandToggle extends StatelessWidget {
  final bool expanded;
  final int remainingCount;
  final VoidCallback onTap;
  const _ExpandToggle({
    required this.expanded,
    required this.remainingCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: SeenlyPalette.accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded
                  ? 'collapse'.tr
                  : '${'show all'.tr}${remainingCount > 0 ? ' · ${'$remainingCount ${'more'.tr}'}' : ''}',
              style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w600)
                  .copyWith(letterSpacing: 0.4),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: Icon(Icons.keyboard_arrow_down, size: 16, color: SeenlyPalette.accent),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recently logged — real diary entries (see _ProfileScreenState._load,
// newest three from the same list the Diary tab shows). Empty state reuses
// the theme's own empty-diary line so it doesn't say something different
// than the diary itself would.
// ---------------------------------------------------------------------------

class _RecentlyLoggedRow extends StatelessWidget {
  final List<DiaryEntry> entries;
  final LogTheme theme;
  const _RecentlyLoggedRow({required this.entries, required this.theme});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Text(LogThemeCopy.emptyDiary(theme),
          style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.placeholder));
    }
    return Row(
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _RecentEntryCard(entry: entries[i])),
        ],
      ],
    );
  }
}

class _RecentEntryCard extends StatelessWidget {
  final DiaryEntry entry;
  const _RecentEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final weekday = _kWeekdayAbbrev[entry.watchedAt.weekday];
    return GestureDetector(
      onTap: () => showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(2), right: Radius.circular(10)),
          border: Border(left: BorderSide(color: SeenlyPalette.border, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(entry.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(size: 11, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (entry.rating != null) ...[
                  Icon(Icons.favorite, size: 9, color: SeenlyPalette.ratingColor(entry.rating)),
                  const SizedBox(width: 3),
                  Text('${entry.rating} · $weekday', style: SeenlyText.mono(size: 8, color: SeenlyPalette.inkFaint)),
                ] else
                  Text(weekday, style: SeenlyText.mono(size: 8, color: SeenlyPalette.inkFaint)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Achievements — real, computed on the backend from the person's own
// logged rows (see backend/app/routers/profile.py::get_achievements and
// AchievementsScreen for the full grid). This teaser row shows a handful:
// whatever's already unlocked, plus the locked ones closest to unlocking,
// so it reads as "here's where you stand" rather than a random sample.
// Same round medallions as the pinned showcase right above it (see
// [RoundBadgeMedallion]) rather than the ticket/garden [AchievementBadge]
// shape this used to draw — one consistent badge shape on the whole
// screen instead of two competing ones.
// ---------------------------------------------------------------------------

class _AchievementsTeaserRow extends StatelessWidget {
  final AchievementsResponse? achievements;
  const _AchievementsTeaserRow({required this.achievements});

  @override
  Widget build(BuildContext context) {
    final all = achievements?.achievements ?? const <Achievement>[];
    if (all.isEmpty) {
      return Text(
        achievements == null ? 'couldn\'t load achievements right now' : 'nothing unlocked yet — keep logging',
        style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.placeholder),
      );
    }
    final pinnedIds = achievements?.pinnedIds.toSet() ?? const <String>{};
    final sorted = [...all]..sort((a, b) {
        if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
        return b.progressRatio.compareTo(a.progressRatio);
      });
    final preview = sorted.take(6).toList();

    // A plain horizontal scroll row rather than a fixed-height
    // ListView — the badge's own icon + up-to-two-line label needs
    // slightly different height depending on the label and the
    // person's text-scale setting, and a hardcoded height here was
    // exactly what clipped it before (see the fixed 76px this used to
    // be). Sizing to content instead means it can never overflow again.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < preview.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            RoundBadgeMedallion(
              iconKey: preview[i].iconKey,
              title: preview[i].title,
              rarity: preview[i].rarity,
              unlocked: preview[i].unlocked,
              pinned: pinnedIds.contains(preview[i].id),
              progressLabel: !preview[i].unlocked && preview[i].progressCurrent > 0
                  ? '${preview[i].progressCurrent} / ${preview[i].progressTarget}'
                  : null,
              onTap: () => showBadgeDetailCard(context, achievement: preview[i]),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favorite films — status-independent (a favorite can be pinned from any
// shelf, not only `watched` — see WatchlistEntry.is_favorite's own
// docstring), set from the film's own heart button or the log form's
// favorite toggle. Same filter FavoriteFilmsScreen's own _ownFavorites
// uses, so the count/poster here always match what that full screen
// shows — the FavoritesShowcaseRow below the header reads from this one
// list.
// ---------------------------------------------------------------------------

List<WatchlistEntry> _allFavoriteMovies(ProfileCollections collections) {
  return [...collections.watchLater, ...collections.watching, ...collections.watched]
      .where((e) => e.isFavorite && e.mediaType == 'movie')
      .toList();
}

// ---------------------------------------------------------------------------
// The row/tile widgets that used to live here (_FavoriteFilmsRow,
// _FavoriteFilmTile — small rotated polaroid-style tiles) are gone; the
// showcase now uses the shared FavoritesShowcaseRow (see
// widgets/favorites_showcase_row.dart), the same ThemedPosterTile-based
// look as the full favorites grid, and it's built right after the
// profile header now rather than down here — see the CustomScrollView
// above.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Unchanged from before this redesign — "your lists" row, the Wrapped
// teaser, and the watched/plan-to-watch tabs below.
// ---------------------------------------------------------------------------

class _YourListsRow extends StatelessWidget {
  final VoidCallback onTap;
  const _YourListsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.collections_bookmark_outlined,
                size: 17, color: SeenlyPalette.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('your lists'.tr, style: SeenlyText.sectionTitle),
            ),
            Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Same row treatment as [_YourListsRow] right above it — a quiet, single
/// line rather than its own promoted section, since this is a niche
/// entry point (YouTube/Twitch imports) most people won't touch. Lives
/// here on Profile rather than inside Settings so it's still reachable
/// in one tap without getting buried; see SourcesScreen's own docstring
/// for why it's a separate screen from the main watched/watching/plan-
/// to-watch tabs just above.
class _YourSourcesRow extends StatelessWidget {
  final VoidCallback onTap;
  const _YourSourcesRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.smart_display_outlined, size: 17, color: SeenlyPalette.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('your sources'.tr, style: SeenlyText.sectionTitle),
            ),
            Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// A progress pill floated a few pixels above the bottom edge of a
/// poster, in its own solid (not gradient-into-artwork) chip — deliberately
/// *not* flush with the very bottom, because that's where the themed
/// poster's own decoration lives (filmstrip sprockets, the boarding-pass
/// stub's barcode, the plant tag's label). Sitting right on top of that
/// decoration made the two unreadable together; floating the pill above
/// it with an opaque backing keeps the real progress the only thing
/// reads there, whatever theme or artwork is behind it. Shared by both
/// "watching now" tiles below.
class _PosterProgressBar extends StatelessWidget {
  final double? progress; // 0..1, or null for an indeterminate "in progress" dash
  final Color accent;
  const _PosterProgressBar({required this.progress, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 6,
      right: 6,
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: SeenlyPalette.ink.withOpacity(0.78),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: Colors.white.withOpacity(0.28),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ),
    );
  }
}

/// One tile on the "watching now" grid for a title with a live journey
/// running right now — the poster plus a thin progress bar against the
/// route's own length (not the full map/scene, just enough to say
/// "partway there"), overlaid at the bottom of the artwork itself. Ticks
/// its own timer rather than relying on AppState's notifyListeners,
/// since pause/resume/start/clear are the only things that fire that —
/// plain elapsed time isn't. Tapping opens the same full "in progress"
/// screen the badge does (see [openActiveJourney]).
class _WatchingNowTile extends StatefulWidget {
  final ActiveJourney journey;
  const _WatchingNowTile({required this.journey});

  @override
  State<_WatchingNowTile> createState() => _WatchingNowTileState();
}

class _WatchingNowTileState extends State<_WatchingNowTile> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Color _accentFor(LogTheme theme) => switch (theme) {
        LogTheme.coach => SeenlyPalette.periwinkle,
        LogTheme.garden => SeenlyPalette.sage,
        LogTheme.ticket => SeenlyPalette.coral,
        LogTheme.shuttle => SeenlyPalette.periwinkle,
      };

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final elapsed = journey.elapsedAt(DateTime.now());
    final progress = (elapsed.inSeconds / (journey.routeMinutes * 60)).clamp(0, 1).toDouble();
    final accent = _accentFor(journey.theme);

    return GestureDetector(
      onTap: () => openActiveJourney(context, journey),
      child: Stack(
        children: [
          ThemedPosterTile(
            title: journey.item.title.display,
            posterUrl: journey.item.posterUrl,
            mediaType: journey.item.mediaType,
            fallbackColor: accent,
            badge: Icon(
              journey.isPaused ? Icons.pause_circle_filled : Icons.play_circle_fill,
              size: 16,
              color: SeenlyPalette.paper,
            ),
          ),
          _PosterProgressBar(progress: progress, accent: accent),
        ],
      ),
    );
  }
}

/// A "watching now" tile for a title that's mid-series (at least one
/// episode logged, not completed — see ProfileCollections.watching) but
/// has no live journey running right now, so there's no elapsed timer to
/// clock a percentage against. Fetches the same watched/total episode
/// counts the episodes sheet itself uses (see _Header in
/// series_episodes_sheet.dart) so the bar here shows that real fraction
/// rather than a dash — falling back to an indeterminate dash only while
/// that's loading, or if it fails to load. Tapping opens the season
/// tracker for series/anime, or the title screen otherwise.
class _WatchingCollectionTile extends StatefulWidget {
  final WatchlistEntry entry;
  const _WatchingCollectionTile({required this.entry});

  @override
  State<_WatchingCollectionTile> createState() => _WatchingCollectionTileState();
}

class _WatchingCollectionTileState extends State<_WatchingCollectionTile> {
  double? _progress;

  bool get _isSeries =>
      widget.entry.mediaType == 'series' || widget.entry.mediaType == 'anime';

  @override
  void initState() {
    super.initState();
    if (_isSeries) _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final results = await Future.wait([
        app.media.episodes(mediaId: widget.entry.mediaId, source: widget.entry.source),
        app.progress.series(mediaId: widget.entry.mediaId, source: widget.entry.source),
      ]);
      if (!mounted) return;
      final episodes = results[0] as SeriesEpisodes;
      final progress = results[1] as SeriesProgress;
      final total = episodes.totalEpisodes;
      if (total == 0) return; // no episode data — keep the indeterminate dash
      final watched = episodes.seasons
          .expand((s) => s.episodes)
          .where((e) => progress.isWatched(e.season, e.episode))
          .length;
      setState(() => _progress = watched / total);
    } catch (_) {
      // best-effort — leave the indeterminate dash showing
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return GestureDetector(
      onTap: () => _isSeries
          ? showSeriesEpisodesSheet(
              context,
              mediaId: entry.mediaId,
              source: entry.source,
              title: entry.displayTitle,
              mediaType: entry.mediaType,
              posterUrl: entry.posterUrl,
            )
          : Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TitleDetailScreen(
                  mediaId: entry.mediaId,
                  source: entry.source,
                  mediaType: entry.mediaType,
                  seedTitle: entry.displayTitle,
                  seedPosterUrl: entry.posterUrl,
                ),
              ),
            ),
      child: Stack(
        children: [
          ThemedPosterTile(
            title: entry.displayTitle,
            posterUrl: entry.posterUrl,
            mediaType: entry.mediaType,
            fallbackColor: SeenlyPalette.inkFaint,
          ),
          _PosterProgressBar(progress: _progress, accent: SeenlyPalette.inkFaint),
        ],
      ),
    );
  }
}

/// Soft, low-pressure premium plug — sits above the Wrapped teaser,
/// only for accounts that aren't premium yet (see PremiumService).
/// Same rounded-card shape as everything else on this screen, warm
/// gradient rather than a flat accent fill so it reads as an invite
/// rather than an ad banner.
class _PremiumBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _PremiumBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SeenlyPalette.mustard.withOpacity(0.85),
              SeenlyPalette.coral.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: SeenlyPalette.accentOnAccent.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.auto_awesome, size: 17, color: SeenlyPalette.accentOnAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('go premium'.tr,
                      style: SeenlyText.serif(
                          italic: true, size: 15, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
                  const SizedBox(height: 2),
                  Text('unlimited ai asks, favorites, and the shuttle theme'.tr,
                      style: SeenlyText.mono(
                          size: 9.5, color: SeenlyPalette.accentOnAccent.withOpacity(0.85))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 17, color: SeenlyPalette.accentOnAccent),
          ],
        ),
      ),
    );
  }
}

class _WrappedTeaser extends StatelessWidget {
  final WrappedStat wrapped;
  final VoidCallback onTap;
  const _WrappedTeaser({required this.wrapped, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hours = wrapped.hours;
    final hoursLabel = hours >= 10 ? hours.round().toString() : hours.toStringAsFixed(1);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SeenlyPalette.accent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.accentOnAccent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    // Wrapped is free for everyone now — premium gates
                    // unlimited AI asks, unlimited favorites, and the
                    // shuttle theme instead (see PremiumScreen), so this
                    // badge no longer claims a restriction that isn't real.
                    child: Text('your year, at a glance'.tr,
                        style: SeenlyText.mono(
                            size: 8, color: SeenlyPalette.accentOnAccent)),
                  ),
                  const SizedBox(height: 8),
                  Text('your wrapped'.tr,
                      style: SeenlyText.serif(
                          italic: true, size: 16, color: SeenlyPalette.accentOnAccent)),
                  const SizedBox(height: 3),
                  Text(
                    wrapped.totalLogged > 0
                        ? '$hoursLabel hrs · ${wrapped.totalLogged} logged this month'
                        : 'nothing logged yet this month',
                    style: SeenlyText.mono(
                        size: 10,
                        color: SeenlyPalette.accentOnAccent.withOpacity(0.75)),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 18, color: SeenlyPalette.accentOnAccent),
          ],
        ),
      ),
    );
  }
}

/// Long-press action for a shelf tile (see the mosaic grid in the
/// watched/plan-to-watch tabs above) — same title + year fallback as
/// collection_full_screen.dart's own `_shareMediaItem`, since a
/// [WatchlistEntry] carries no external ids to link out to.
void _shareEntry(WatchlistEntry e) {
  final bits = [
    e.displayTitle,
    if (e.year != null) '(${e.year})',
  ].join(' ');
  Share.share(bits);
}

