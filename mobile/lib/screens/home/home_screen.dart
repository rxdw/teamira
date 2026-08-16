import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/active_journey.dart';
import '../../models/activity_item.dart';
import '../../models/collection.dart';
import '../../models/diary_entry.dart';
import '../../models/episode.dart';
import '../../models/friend.dart';
import '../../models/media_item.dart';
import '../../models/partner_status.dart';
import '../../models/profile_stats.dart' hide ActivityItem;
import '../../models/suggestion.dart';
import '../../models/watchlist_entry.dart';
import '../../services/api_client.dart';
import '../../services/auto_tracking_prefs_service.dart';
import '../../services/log_theme_service.dart';
import '../../services/on_this_day_prefs_service.dart';
import '../../services/rabbit_mascot_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/active_journey_badge.dart';
import '../../widgets/heart_rating.dart';
import '../../widgets/coview_bunnies_corner.dart';
import '../../widgets/evening_plan_card.dart';
import '../../widgets/invite_friends_sheet.dart';
import '../../widgets/pairing_qr.dart';
import '../../widgets/parallax_poster.dart';
import '../../widgets/polaroid_card.dart';
import '../../widgets/rabbit_mascot.dart';
import '../../widgets/section_header.dart';
import '../../widgets/series_episodes_sheet.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/today_pick_card.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/card_snap_scroll_physics.dart';
import '../../widgets/trailer_preview_card.dart';
import '../../widgets/poster_lightbox.dart' show scopedPosterHeroTag;
import '../../widgets/watched_preview_sheet.dart';
import '../../widgets/wow_motion.dart';
import '../friends/friends_screen.dart';
import '../decide/decide_filters_screen.dart';
import '../friends/friends_activity_feed_screen.dart';
import '../shell/root_shell.dart';
import '../partner/co_viewing_screen.dart';
import '../profile/integrations_screen.dart';
import '../scan/ticket_scan_screen.dart';
import '../search/search_screen.dart';
import '../title/title_detail_screen.dart';
import '../trailers/trailer_reels_screen.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_pull_to_refresh.dart';
import 'ask_teamira_results_screen.dart';
import '../../services/app_translations.dart';

/// Home-specific shorthand for [scopedPosterHeroTag] — every call site in
/// this file scopes under 'home', trailer reels under 'foryou' (see
/// TrailerPreviewCard's use site below and trailer_reels_screen.dart).
String _homePosterHeroTag(String scope, String source, String id) =>
    scopedPosterHeroTag('home-$scope', source, id);

/// One "on this day" match — a diary entry logged exactly [monthsAgo]
/// months before [today], same day of the month. See [_onThisDayMatches].
class _OnThisDayMatch {
  final DiaryEntry entry;
  final int monthsAgo;
  const _OnThisDayMatch({required this.entry, required this.monthsAgo});
}

/// Every logged evening that lands on today's date in a past month —
/// "exactly a month ago", "exactly 2 months ago", "exactly a year ago",
/// and so on — not just full-year anniversaries. A month with no such
/// day (e.g. today is the 31st and a candidate month only has 30) simply
/// has no match that month, same as any other "on this day" feature.
/// Only the closest match per title is kept (a title logged both a
/// month and a year ago on this date shows once, at its nearer match),
/// closest first.
List<_OnThisDayMatch> _onThisDayMatches(List<DiaryEntry> diary, DateTime today) {
  final matches = <_OnThisDayMatch>[];
  for (final e in diary) {
    if (e.watchedAt.day != today.day) continue;
    final monthsAgo =
        (today.year - e.watchedAt.year) * 12 + (today.month - e.watchedAt.month);
    if (monthsAgo < 1) continue;
    matches.add(_OnThisDayMatch(entry: e, monthsAgo: monthsAgo));
  }
  matches.sort((a, b) => a.monthsAgo.compareTo(b.monthsAgo));
  final seen = <String>{};
  final deduped = <_OnThisDayMatch>[];
  for (final m in matches) {
    if (seen.add('${m.entry.source}:${m.entry.mediaId}')) deduped.add(m);
  }
  return deduped;
}

/// Plain `yyyy-MM-dd` for [date] — the key [OnThisDayPrefsService] dismisses
/// against, so the "on this day" section reappears on its own once the
/// calendar day actually changes rather than staying closed forever.
String _onThisDayDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// A network image that flies under [heroTag] when one's given (a card
/// that lands on TitleDetailScreen), and is just a plain image otherwise
/// (cards that open something else — a sheet, a journey screen — where
/// there's no matching Hero on the other side anyway).
class _HeroableImage extends StatelessWidget {
  final String? heroTag;
  final String url;
  final Color fallbackColor;
  const _HeroableImage({required this.heroTag, required this.url, required this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: fallbackColor),
    );
    final tag = heroTag;
    return tag == null ? image : Hero(tag: tag, child: image);
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  final List<DiaryEntry> diary;
  final ProfileYearStats stats;
  final List<SeenlyCollection> collections;
  final bool collectionsFailed;
  final List<MediaItem> forYou;
  // Best-effort, same reasoning as forYou below — only used to back the
  // "watching now" strip up top, so a failed fetch just means that strip
  // quietly falls back to whatever live journeys AppState already has
  // (or doesn't show at all), never a blocked Home load.
  final ProfileCollections? profileCollections;
  const _HomeData(this.diary, this.stats, this.collections,
      {this.collectionsFailed = false, this.forYou = const [], this.profileCollections});
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<_HomeData> _future;
  DateTime _lastLoadedAt = DateTime.now();

  // Coming back to the app counts as "probably wants fresh data" without
  // anyone needing to remember to pull down — but only past this interval,
  // so hopping briefly to another app and back doesn't spend a round trip
  // for nothing. Safe to keep short: the backend's own 24h TMDB cache
  // (see backend/app/cache.py) means this is a cheap Postgres read either
  // way, never an extra TMDB call.
  static const _autoRefreshAfter = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        DateTime.now().difference(_lastLoadedAt) > _autoRefreshAfter) {
      _silentRefresh();
    }
  }

  Future<_HomeData> _load() async {
    final app = context.read<AppState>();

    // Diary + stats failing means something fundamental is wrong (backend
    // unreachable, bad token) — let that throw and show the real error
    // state below. Collections is fetched separately and allowed to fail
    // on its own (most common cause: TMDB_API_KEY missing/invalid in
    // the backend's .env, see mobile/README.md) — a mis-set catalog key
    // shouldn't blank out a diary that's otherwise loading fine.
    final diaryEntries = await app.diary.list();
    final stats = await app.profile.yearStats();

    List<SeenlyCollection> collections = const [];
    bool collectionsFailed = false;
    try {
      // A fresh copy, shuffled once here at load time — not in build().
      // The Collections tab fetches its own copy independently and keeps
      // the original shelf order (so "browse by shelf" stays predictable);
      // Home's job is different — every pull-to-refresh should plausibly
      // put a different shelf in the spotlight and feed the mosaic below,
      // not just re-sort the same items from the same one or two shelves
      // that happened to sort first. Shuffling here, once per load, means
      // the choice is stable for the rest of this build (no flicker on
      // unrelated rebuilds) but genuinely different on the next refresh.
      collections = (await app.feed.collections())..shuffle();
    } catch (_) {
      collectionsFailed = true;
    }

    // Best-effort, same reasoning as collections above — a brand-new
    // account (nothing logged yet) gets an empty list back by design, and
    // any other failure here just means the shelf quietly doesn't show,
    // never a blocked Home load.
    List<MediaItem> forYou = const [];
    try {
      forYou = await app.feed.forYou();
    } catch (_) {
      // Ignored on purpose — see doc comment above.
    }

    // Feeds the "watching now" strip up top (see _WatchingNowSection) —
    // same shelf ProfileScreen's own "watching now" tab reads. Best-effort
    // like collections/forYou above: this strip is a nice-to-have, not
    // something worth blocking the whole Home load over.
    ProfileCollections? profileCollections;
    try {
      profileCollections = await app.profile.collections();
    } catch (_) {
      // Ignored on purpose — see doc comment above.
    }

    _lastLoadedAt = DateTime.now();
    return _HomeData(diaryEntries, stats, collections,
        collectionsFailed: collectionsFailed,
        forYou: forYou,
        profileCollections: profileCollections);
  }

  Future<void> _refresh() async {
    // A little tick right as the pull commits to a refresh — the same
    // "this registered" cue the logging flows already give (see
    // HapticFeedback.mediumImpact() in the drop overlays), just here at
    // the very top of the app instead of at the end of a ritual.
    HapticFeedback.mediumImpact();
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  /// Same reload as [_refresh], but for the automatic, unattended case —
  /// triggered by [didChangeAppLifecycleState] rather than someone's
  /// finger on the screen. A dropped request here just leaves whatever's
  /// already showing in place instead of swapping in an error state
  /// nobody asked to see; the next pull-to-refresh or resume tries again.
  Future<void> _silentRefresh() async {
    try {
      final data = await _load();
      if (!mounted) return;
      setState(() => _future = Future.value(data));
    } catch (_) {
      // Ignored on purpose — see doc comment above.
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'still up?';
    if (hour < 12) return 'good morning';
    if (hour < 18) return 'good afternoon';
    return 'good evening';
  }

  Future<void> _showStreakInfo(int streakDays) async {
    await showGeneralDialog(
      context: context,
      barrierLabel: 'streak',
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) => _StreakInfoSheet(streakDays: streakDays),
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

  /// Chunks the feed into an alternating mosaic — two big tiles, then three
  /// smaller ones, repeating — instead of one flat list. Purely a layout
  /// decision made here at build time; the data itself is just a flat list.
  List<Widget> _feedMosaicRows(List<MediaItem> items) {
    final rows = <Widget>[];
    var i = 0;
    var large = true;
    while (i < items.length) {
      final take = large ? 2 : 3;
      final chunk = items.skip(i).take(take).toList();
      if (chunk.isEmpty) break;
      rows.add(_FeedRow(items: chunk, large: large));
      i += chunk.length;
      large = !large;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snapshot) {
        // The first paint of Home used to be a bare spinner centered on
        // an empty page, then a hard cut to the whole feed at once —
        // technically fine, but it reads as the app booting up rather
        // than settling in. Swapping that first frame for a skeleton
        // shaped like the real layout, then cross-fading into the
        // actual content once it lands (rather than snapping to it),
        // makes the wait itself feel like part of the same smooth
        // motion as everything the Entrance cascade below already does
        // — never a seam between "loading" and "loaded". All three
        // states share one AnimatedSwitcher (see the bottom of this
        // builder) so the swap between any of them cross-fades instead
        // of cutting.
        if (!snapshot.hasData && !snapshot.hasError) {
          return _fadeSwitch(const _HomeSkeleton(key: ValueKey('home-skeleton')));
        }
        if (snapshot.hasError) {
          return _fadeSwitch(_ErrorState(key: const ValueKey('home-error'), onRetry: _refresh));
        }
        final data = snapshot.data!;
        final recentSeries = data.diary
            .where((e) => e.mediaType == 'series' || e.mediaType == 'anime')
            .cast<DiaryEntry?>()
            .firstWhere((_) => true, orElse: () => null);
        final freshEntries = data.diary.take(6).toList();
        final today = DateTime.now();
        final onThisDay = _onThisDayMatches(data.diary, today);
        final watchCollections = data.collections
            .where((c) => c.items.isNotEmpty && c.items.first.mediaType != 'game')
            .toList();
        final gameCollections = data.collections
            .where((c) => c.items.isNotEmpty && c.items.first.mediaType == 'game')
            .toList();
        final pickedCollection = watchCollections.isNotEmpty ? watchCollections.first : null;
        final pickedGameCollection = gameCollections.isNotEmpty ? gameCollections.first : null;

        // What's actually playing right now, for the "watching now" strip
        // above ask teamira — same two sources, combined the same way, as
        // ProfileScreen's own "watching now" tab (see profile_screen.dart):
        // live journeys first, then anything mid-series with no journey
        // running, skipping duplicates so the same title never shows twice.
        final watchingNowJourneys = context.watch<AppState>().activeJourneysList;
        final watchingNowJourneyKeys = {
          for (final j in watchingNowJourneys) '${j.item.source}:${j.item.id}',
        };
        final watchingNowEntries = (data.profileCollections?.watching ?? const <WatchlistEntry>[])
            .where((e) => !watchingNowJourneyKeys.contains('${e.source}:${e.mediaId}'))
            .toList();

        // Everything the two "tonight" banners above didn't use, flattened
        // into one deduplicated list — this is the vertical feed below,
        // deliberately not another horizontal shelf (Collections already
        // browses by category; Home just needs a few honest suggestions).
        final usedCollections = {
          if (pickedCollection != null) pickedCollection,
          if (pickedGameCollection != null) pickedGameCollection,
        };
        // Round-robins one item at a time across every remaining shelf
        // (movies, series, anime, genre shelves, ...) instead of draining
        // the first shelf entirely before touching the next. Previously
        // this loop finished an entire collection before checking the
        // length cap, so in practice "more for tonight" was just *one*
        // shelf's ~15-20 items end to end — same set every refresh within
        // the cache window, only their order changing. Interleaving means
        // the 10 tiles shown are a genuine mix pulled from several shelves
        // each time, not one shelf's full contents.
        final feedItems = <MediaItem>[];
        final seenKeys = <String>{};
        final pools = data.collections
            .where((c) => !usedCollections.contains(c))
            .map((c) => List<MediaItem>.from(c.items))
            .where((p) => p.isNotEmpty)
            .toList();
        var round = 0;
        while (feedItems.length < 10 && pools.any((p) => p.isNotEmpty)) {
          final pool = pools[round % pools.length];
          if (pool.isNotEmpty) {
            final item = pool.removeAt(0);
            if (seenKeys.add('${item.source}:${item.id}')) feedItems.add(item);
          }
          round++;
        }

        // Sequential entrance cascade: each call hands out the next delay
        // in the "held breath" cascade and advances the counter. Sections
        // below are gated behind their own `if` (no "for you", no picked
        // collection, no continue-watching, ...), and this call only
        // happens when a section actually builds — so a skipped section
        // simply never claims a slot, and whatever comes after it inherits
        // the next slot in line instead of waiting out a gap for a delay
        // nobody claimed. A nested list (polaroid strip, feed mosaic) grabs
        // one slot for the whole group via this same call, then staggers
        // its own items within that slot — see the two loops below.
        //
        // Capped at 4 slots (240ms): sections now reveal via ScrollReveal
        // — on their own top edge crossing into view, not all at once on
        // mount — so this delay only matters for whatever happens to be
        // simultaneously visible together (typically the first handful of
        // sections on first paint). Anything scrolled to individually
        // later has nothing to cascade alongside, so letting the slot
        // count keep growing the further down the page a section sits
        // would just be dead air after it's already in view, not a
        // cascade — capping keeps the nice stagger where it's actually
        // seen and drops the pointless tail of it everywhere else.
        var entranceSlot = 0;
        Duration nextStagger({int step = 60, int maxSlots = 4}) {
          final slot = entranceSlot < maxSlots ? entranceSlot : maxSlots;
          final d = Duration(milliseconds: slot * step);
          entranceSlot++;
          return d;
        }
        // Set by the "fresh in your diary" header below, then read by its
        // polaroid strip so the whole group shares one slot.
        var freshDelay = Duration.zero;
        // Set by the "more for tonight" header below, then read by its
        // feed mosaic rows for the same reason.
        var feedDelay = Duration.zero;

        return _fadeSwitch(ThemedPullToRefresh(
          key: const ValueKey('home-content'),
          onRefresh: _refresh,
          child: CustomScrollView(
            // Without this, pull-to-refresh silently does nothing whenever
            // there's too little content to naturally overscroll (e.g. a
            // near-empty diary + few collections) — RefreshIndicator needs
            // the scrollable underneath it to always permit the gesture,
            // not just when content happens to exceed the viewport.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextStagger(),
                    riseBy: 10,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Just the faintest, slowest breathing
                                  // glow behind the moon — no scale on the
                                  // icon itself anymore (that read as an
                                  // actual pulsing/wobbling motion right at
                                  // the top of the screen, which is
                                  // uncomfortable to sit next to while
                                  // reading — see BreathingGlow's doc
                                  // comment). The icon stays perfectly
                                  // still; only the soft halo around it
                                  // very slowly breathes.
                                  BreathingGlow(
                                    color: SeenlyPalette.accent,
                                    size: 30,
                                    period: const Duration(milliseconds: 6000),
                                    minSize: 0.9,
                                    maxOpacity: 0.18,
                                    child: const Icon(Icons.nights_stay_outlined,
                                        size: 16, color: SeenlyPalette.accent),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(_greeting(), style: SeenlyText.greeting),
                                  if (data.stats.streakDays > 0) ...[
                                    const SizedBox(width: 8),
                                    PressScale(
                                      haptics: true,
                                      onTap: () => _showStreakInfo(data.stats.streakDays),
                                      scaleTo: 0.9,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          children: [
                                            BreathingGlow(
                                              color: SeenlyPalette.mustard,
                                              size: 26,
                                              period: const Duration(milliseconds: 4200),
                                              minSize: 0.88,
                                              maxOpacity: 0.22,
                                              child: const Icon(Icons.local_fire_department_rounded,
                                                  size: 17, color: SeenlyPalette.mustard),
                                            ),
                                            const SizedBox(width: 2),
                                            CountUpNumber(
                                              value: data.stats.streakDays.toDouble(),
                                              decimals: 0,
                                              duration: const Duration(milliseconds: 700),
                                              style: SeenlyText.mono(
                                                  size: 14, weight: FontWeight.w700, color: SeenlyPalette.mustard),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('what shall we watch?'.tr,
                                  style: SeenlyText.serif(
                                      size: 23, weight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        PressScale(
                          haptics: true,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const TicketScanScreen()),
                          ),
                          child: Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.only(top: 2, right: 8),
                            decoration: const BoxDecoration(
                              color: SeenlyPalette.paper,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.confirmation_number_outlined,
                                size: 16, color: SeenlyPalette.ink),
                          ),
                        ),
                        PressScale(
                          haptics: true,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const SearchScreen()),
                          ),
                          child: Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: const BoxDecoration(
                              color: SeenlyPalette.paper,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.search,
                                size: 16, color: SeenlyPalette.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextStagger(),
                    child: const TodayPickCard(),
                  ),
                ),
              ),
              if (!context.watch<AutoTrackingPrefsService>().bannerDismissed)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  sliver: SliverToBoxAdapter(
                    child: ScrollReveal(
                      delay: nextStagger(),
                      child: _AutoTrackingBanner(
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const IntegrationsScreen()),
                        ),
                      ),
                    ),
                  ),
                ),
              if (watchingNowJourneys.isNotEmpty || watchingNowEntries.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
                  sliver: SliverToBoxAdapter(
                    child: ScrollReveal(
                      delay: nextStagger(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(22, 0, 22, 6),
                            child: SectionHeader(title: 'watching now'),
                          ),
                          _WatchingNowSection(
                            journeys: watchingNowJourneys,
                            entries: watchingNowEntries,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextStagger(),
                    child: const _AskTeamiraCard(),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextStagger(),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _CoViewingCard()),
                          const SizedBox(width: 10),
                          Expanded(child: _CantDecideCard()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextStagger(),
                    child: const EveningPlanCard(),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                sliver: SliverToBoxAdapter(
                  child: ScrollReveal(
                    delay: nextStagger(),
                    child: const _FriendsActivityCard(),
                  ),
                ),
              ),
              if (recentSeries != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  sliver: SliverToBoxAdapter(
                    child: ScrollReveal(
                      delay: nextStagger(),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'continue watching'),
                        const SizedBox(height: 10),
                        _ContinueWatchingCard(entry: recentSeries),
                      ],
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                sliver: SliverToBoxAdapter(
                  // Claims one slot for the whole "fresh in your diary"
                  // group (this header + the polaroid strip below) — the
                  // strip's cards stagger off `freshDelay` instead of
                  // claiming their own slots, so the group reads as one
                  // section in the cascade no matter how many cards it
                  // holds.
                  child: ScrollReveal(
                    delay: freshDelay = nextStagger(),
                    child: SectionHeader(
                      title: 'fresh in your diary',
                      trailing: freshEntries.isNotEmpty ? 'all →' : null,
                      onTrailingTap: () => RootShell.switchTab(context, RootShell.diaryTab),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                // Wrapped in its own ScrollReveal (reusing `freshDelay`
                // rather than claiming a fresh nextStagger() slot, so it
                // still settles in lockstep with the header above) purely
                // so the strip becomes a RevealPulse ancestor — that's
                // what lets the HorizontalReveal cards below replay their
                // slide-in every time this section re-enters view, not
                // just once on first mount. See HorizontalReveal's doc
                // comment in widgets/wow_motion.dart for why a card in a
                // horizontal list can't detect that on its own.
                child: ScrollReveal(
                  delay: freshDelay,
                  child: freshEntries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                        child: Builder(builder: (context) {
                          final showMascot = context.watch<RabbitMascotPrefsService>().enabled;
                          // The rabbit sits in the Row itself now, not floated
                          // over it with a negative offset — that's what let
                          // it bleed past this row's own bounds and land on
                          // top of whatever section happened to be next
                          // (the diary header above, or "picked for tonight"
                          // below, depending on which other sections were
                          // present). Sized to sit comfortably next to a
                          // single line of text with no overflow either way.
                          const mascotSize = 92.0;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (showMascot) ...[
                                const RabbitMascot(mood: RabbitMood.sad, size: mascotSize),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Text(
                                  'nothing logged yet — find something and tuck it in'.tr,
                                  style: SeenlyText.serif(
                                      italic: true, color: SeenlyPalette.placeholder),
                                ),
                              ),
                            ],
                          );
                        }),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: SizedBox(
                          height: 118,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            // Polaroid width (70 + 12 frame) + the 10px
                            // gap below — snaps one card at a time
                            // instead of coasting to a stop mid-card.
                            physics: const CardSnapScrollPhysics(
                              itemExtent: 92,
                              leadingPadding: 22,
                            ),
                            itemCount: freshEntries.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (context, i) {
                              final e = freshEntries[i];
                              const tapes = [
                                SeenlyPalette.tapeRose,
                                SeenlyPalette.tapeSage,
                                SeenlyPalette.tapeMustard,
                              ];
                              return HorizontalReveal(
                                delay: Duration(milliseconds: 40 + i * 70),
                                child: PolaroidCard(
                                  caption: e.displayTitle,
                                  posterUrl: e.posterUrl,
                                  fallbackColor: SeenlyPalette.mediaColor(e.mediaType),
                                  tapeColor: tapes[i % tapes.length],
                                  rotationTurns: i.isEven ? -0.02 : 0.02,
                                  onTap: () => showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(e)),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                ),
              ),
              if (onThisDay.isNotEmpty &&
                  !context.watch<OnThisDayPrefsService>().isDismissed(_onThisDayDateKey(today)))
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  sliver: SliverToBoxAdapter(
                    child: ScrollReveal(
                      delay: nextStagger(),
                      child: _OnThisDaySection(
                        dateKey: _onThisDayDateKey(today),
                        matches: onThisDay.take(3).toList(),
                      ),
                    ),
                  ),
                ),
              if (data.forYou.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 0, 24),
                  sliver: SliverToBoxAdapter(
                    child: ScrollReveal(
                      delay: nextStagger(),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 22),
                          child: SectionHeader(
                            title: 'for you, with trailers',
                            trailing: 'watch all →',
                            onTrailingTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TrailerReelsScreen(items: data.forYou),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.only(right: 22),
                          child: Text(
                            'picked from what you\'ve loved so far — tap one to watch its trailer'.tr,
                            style: SeenlyText.serif(
                                italic: true, size: 12, color: SeenlyPalette.inkMuted),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 198,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 22),
                            // TrailerPreviewCard's default width (132) +
                            // the 12px gap below — same one-card-at-a-
                            // time snap as the polaroid strip above.
                            physics: const CardSnapScrollPhysics(
                              itemExtent: 144,
                            ),
                            itemCount: data.forYou.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, i) => TrailerPreviewCard(
                              item: data.forYou[i],
                              heroTag: _homePosterHeroTag(
                                  'foryou', data.forYou[i].source, data.forYou[i].id),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TrailerReelsScreen(
                                    items: data.forYou,
                                    initialIndex: i,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      ),
                    ),
                  ),
                ),
              if (pickedCollection != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  sliver: SliverToBoxAdapter(
                    child: ScrollReveal(
                      delay: nextStagger(),
                      child: pickedGameCollection != null
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _TonightBanner(
                                    label: 'picked for tonight',
                                    collection: pickedCollection,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _TonightBanner(
                                    label: 'game of the evening',
                                    collection: pickedGameCollection,
                                  ),
                                ),
                              ],
                            )
                          : _TonightBanner(
                              label: 'picked for tonight', collection: pickedCollection),
                    ),
                  ),
                )
              else if (data.collectionsFailed)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      "couldn't reach the catalog for tonight's pick — the rest of your diary loaded fine".tr,
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                    ),
                  ),
                ),
              if (feedItems.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Claims one slot for this whole "more for
                        // tonight" group (this header + the mosaic rows
                        // below) — the rows stagger off `feedDelay`
                        // instead of claiming their own slots, matching
                        // the "fresh in your diary" group above.
                        ScrollReveal(
                          delay: feedDelay = nextStagger(),
                          child: const SectionHeader(title: 'more for tonight'),
                        ),
                        const SizedBox(height: 10),
                        for (final entry in _feedMosaicRows(feedItems).asMap().entries) ...[
                          ScrollReveal(
                            // Capped for the same reason as `nextStagger`
                            // above — rows further down this shelf don't
                            // reveal alongside the ones before them, so
                            // there's nothing for a growing offset to
                            // cascade with.
                            delay: feedDelay +
                                Duration(milliseconds: 40 + entry.key.clamp(0, 2) * 70),
                            riseBy: 14,
                            child: entry.value,
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ));
      },
    );
  }

  /// Shared cross-fade for the three top-level states this screen can be
  /// in (skeleton / error / real content) — one [AnimatedSwitcher] keyed
  /// off each child's own [Key] so a transition between any two of them
  /// dissolves rather than cuts, while a rebuild that keeps the same
  /// state (e.g. new data landing under the same 'home-content' key
  /// during pull-to-refresh) is a no-op here, not a re-triggered fade.
  Widget _fadeSwitch(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

/// A quiet stand-in for Home while the first load is in flight — rough
/// bones of the real layout (greeting row, the "watching now" strip, the
/// ask-teamira card, the two square cards, a shelf) in the same soft
/// shimmering paper tones as [ShimmerBlock], sized and spaced to roughly
/// match what's about to land underneath it. The point isn't a pixel-
/// perfect preview — it's that the very first frame already reads as
/// *this* screen, so the cross-fade into real content (see
/// [_HomeScreenState._fadeSwitch]) feels like a settle, not a swap.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton({super.key});

  static Widget _bone({double? w, double h = 16, double r = 8}) => ShimmerBlock(
        width: w,
        height: h,
        borderRadius: BorderRadius.circular(r),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bone(w: 120, h: 14, r: 7),
                  const SizedBox(height: 9),
                  _bone(w: 190, h: 22, r: 10),
                ],
              ),
            ),
            _bone(w: 34, h: 34, r: 17),
            const SizedBox(width: 8),
            _bone(w: 34, h: 34, r: 17),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 96,
          child: Row(
            children: [
              Expanded(child: _bone(h: 96, r: 16)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 96, r: 16)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 96, r: 16)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _bone(h: 92, r: 20),
        const SizedBox(height: 12),
        SizedBox(
          height: 128,
          child: Row(
            children: [
              Expanded(child: _bone(h: 128, r: 18)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 128, r: 18)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _bone(h: 84, r: 18),
        const SizedBox(height: 24),
        _bone(w: 150, h: 14, r: 7),
        const SizedBox(height: 12),
        SizedBox(
          height: 118,
          child: Row(
            children: [
              Expanded(child: _bone(h: 118, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 118, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 118, r: 14)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Friends' activity — a soft, easy-to-ignore card, not a feed you're
// steered toward. Collapses to nothing (no header, no empty state) for
// anyone with no friends yet or whose friends haven't logged anything
// recently, so Home never carries an empty "friends" section just to
// advertise the feature — see backend/app/routers/activity.py for where
// this list comes from (own account's events are already elsewhere on
// Home; only the friend-authored ones show up here).
// ---------------------------------------------------------------------------

/// The very top of Home: describe what you're in the mood for in your own
/// words ("a 2010s sci-fi game", "a movie like Interstellar") and get a
/// ranked shortlist back — see AskTeamiraResultsScreen. No model call
/// behind this (see backend/app/routers/ai.py's module docstring): local
/// keyword/genre matching against the same catalogs the rest of the app
/// already searches, so it costs nothing extra to run.
class _AskTeamiraCard extends StatefulWidget {
  const _AskTeamiraCard();

  @override
  State<_AskTeamiraCard> createState() => _AskTeamiraCardState();
}

class _AskTeamiraCardState extends State<_AskTeamiraCard> {
  // A bigger pool than we show at once, so the row of examples changes
  // between visits instead of showing the same three every time.
  static const _examplePool = [
    'a movie like Interstellar',
    '2010s sci-fi game',
    'cozy comedy series',
    'something that\'ll make me cry',
    'rainy day, no thinking required',
    'a twisty whodunit',
    'just spooky enough',
    'mindless popcorn action',
    'high-fantasy, big world',
    'slow-burn slice of life',
    'co-op game for two',
    'a nostalgic 90s pick',
  ];

  late final List<String> _examples;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final pool = [..._examplePool]..shuffle();
    _examples = pool.take(3).toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    _focusNode.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AskTeamiraResultsScreen(query: query)),
    );
  }

  void _useExample(String example) {
    setState(() {
      _controller.text = example;
      _controller.selection = TextSelection.collapsed(offset: example.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 16, color: SeenlyPalette.accent),
              const SizedBox(width: 7),
              Text('ask teamira'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            ],
          ),
          const SizedBox(height: 6),
          Text('not sure what to watch or play?'.tr,
              style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: SeenlyPalette.border, width: 1.4)),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: SeenlyText.serif(size: 13.5),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                hintText: 'describe a mood, a genre, "like [title]"…'.tr,
                hintStyle: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _ExampleChipsLayout(
            examples: _examples,
            onTap: _useExample,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PressScale(
              onTap: _submit,
              scaleTo: 0.96,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('find matches'.tr,
                        style: SeenlyText.mono(
                            size: 12, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent)),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward, size: 14, color: SeenlyPalette.accentOnAccent),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single horizontal row of the mood examples under "ask teamira"'s
/// input, rather than the old two-column grid — reads more like a hint
/// row (the way a search bar's own suggestion chips usually sit) than a
/// block of options to scan. Three examples rarely all fit on one line
/// at once, so the row scrolls horizontally; to make that scrollability
/// obvious without anyone having to discover it by touch, the row gently
/// drifts on its own the moment it settles in — a slow, soft sway that
/// peeks the next chip in and out from the edge, the same "there's more
/// here" cue a carousel's own peeking edge gives, just for a row that's
/// otherwise easy to mistake for exactly two options and nothing else.
/// A real touch on the row pauses the drift for as long as someone's
/// actually interacting with it; once they let go and it's been idle a
/// moment, the row eases itself back to the start and the sway picks
/// back up on its own — same as before anyone touched it, not stopped
/// for good after a single swipe.
class _ExampleChipsLayout extends StatefulWidget {
  const _ExampleChipsLayout({required this.examples, required this.onTap});

  final List<String> examples;
  final ValueChanged<String> onTap;

  @override
  State<_ExampleChipsLayout> createState() => _ExampleChipsLayoutState();
}

class _ExampleChipsLayoutState extends State<_ExampleChipsLayout>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  late final AnimationController _driftController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  // How far the idle drift peeks the row over, at most — just enough to
  // reveal a sliver of whatever's sitting past the edge, never a full
  // guided tour through every chip. Clamped down further at tick time
  // whenever the row's actual overflow is smaller than this.
  static const _maxPeek = 34.0;

  // How long to wait, once someone lets go of the row, before it eases
  // back into the idle sway — long enough that a quick glance-and-swipe
  // doesn't immediately snap back under their finger, short enough that
  // the row doesn't just sit there looking abandoned.
  static const _resumeDelay = Duration(milliseconds: 2200);
  static const _resumeEaseDuration = Duration(milliseconds: 500);

  bool _userTouched = false;
  Timer? _resumeTimer;
  // Bumped on every genuine touch so a resume that was already underway
  // (mid glide-back, mid-await) can tell it's been superseded by a new
  // touch and bail out instead of yanking the row out from under a
  // still-active drag.
  int _touchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _driftController.addListener(_onDriftTick);
  }

  void _onDriftTick() {
    if (_userTouched || !_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    // Nothing overflows (a narrow pool of very short examples all fit
    // at once) — no scrollable distance to drift across, so stay put
    // rather than jumping to 0 over and over.
    if (maxExtent <= 0) return;
    final peek = maxExtent < _maxPeek ? maxExtent : _maxPeek;
    final t = Curves.easeInOut.transform(_driftController.value);
    _scrollController.jumpTo(peek * t);
  }

  void _onRealDragStart() {
    _touchGeneration++;
    _userTouched = true;
    _driftController.stop();
    _resumeTimer?.cancel();
  }

  void _onScrollSettled() {
    if (!_userTouched) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeDelay, _resumeDrift);
  }

  Future<void> _resumeDrift() async {
    final generation = _touchGeneration;
    if (!mounted || !_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent <= 0) {
      _userTouched = false;
      _driftController
        ..value = 0
        ..repeat(reverse: true);
      return;
    }
    // Glide back to the drift's own starting point before rejoining the
    // cycle, rather than snapping the row out from under wherever the
    // person left it.
    await _scrollController.animateTo(
      0,
      duration: _resumeEaseDuration,
      curve: Curves.easeInOut,
    );
    // A fresh touch landed while we were easing back — that touch owns
    // the row now, not this resume.
    if (!mounted || generation != _touchGeneration) return;
    _userTouched = false;
    _driftController
      ..value = 0
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _driftController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Only a genuine finger-drag carries dragDetails — the
        // programmatic jumpTo()/animateTo() calls driving the idle sway
        // and the resume glide don't — so this only fires for an actual
        // touch, whether it's the first one or a later one after the
        // drift had already picked back up.
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _onRealDragStart();
        } else if (n is ScrollEndNotification) {
          _onScrollSettled();
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < widget.examples.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _ExampleChip(
                label: widget.examples[i],
                onTap: () => widget.onTap(widget.examples[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One of the tappable mood examples under "ask teamira"'s input. A small
/// tagged rectangle with an accent flag on the left, rather than the plain
/// oval pill — reads more like a sticky note than a generic filter chip.
class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: SeenlyPalette.background,
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: SeenlyPalette.accent.withOpacity(0.55)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.serif(
                    size: 11.5,
                    italic: true,
                    color: SeenlyPalette.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return PressScale(
      onTap: onTap,
      scaleTo: 0.96,
      child: chip,
    );
  }
}


class _FriendsActivityCard extends StatefulWidget {
  const _FriendsActivityCard();

  @override
  State<_FriendsActivityCard> createState() => _FriendsActivityCardState();
}

class _FriendsActivityCardState extends State<_FriendsActivityCard> {
  List<ActivityItem> _items = const [];
  bool _hasFriends = true; // assume yes until we know otherwise, to avoid a false invite-nudge flash
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final app = context.read<AppState>();
      final feed = await app.activity.feed();
      final friendsData = await app.friends.list();
      if (!mounted) return;
      setState(() {
        _items = feed.where((e) => !e.isMine).take(4).toList();
        _hasFriends = friendsData.friends.isNotEmpty;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  String _relativeTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    // No friends yet: one quiet line, not a whole card — tapping it
    // opens the same invite sheet as the profile block, nothing new to
    // learn. Skipped entirely (not even this line) once there's real
    // friend activity to show instead, so it never lingers as clutter.
    if (!_hasFriends) {
      return PressScale(
        scaleTo: 0.98,
        onTap: () => showInviteFriendsSheet(context),
        child: Row(
          children: [
            const Icon(Icons.person_add_alt_1_rounded, size: 12, color: SeenlyPalette.inkFaint),
            const SizedBox(width: 6),
            Text('invite friends to see their activity here'.tr,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
          ],
        ),
      );
    }

    if (_items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'friends',
          trailing: 'see all →',
          onTrailingTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FriendsActivityFeedScreen()),
          ),
        ),
        const SizedBox(height: 10),
        PressScale(
          scaleTo: 0.98,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FriendsActivityFeedScreen()),
          ),
          child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
          decoration: BoxDecoration(color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              for (var i = 0; i < _items.length; i++)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: i == 0 || i == _items.length - 1 ? 10 : 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${_items[i].who} ',
                                style: SeenlyText.serif(size: 12.5, weight: FontWeight.w700, color: SeenlyPalette.ink),
                              ),
                              TextSpan(
                                text: _items[i].text,
                                style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_relativeTime(_items[i].createdAt),
                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                    ],
                  ),
                ),
            ],
          ),
          ),
        ),
      ],
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  final DiaryEntry entry;
  const _ContinueWatchingCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry)),
      scaleTo: 0.98,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 80,
              child: ThemedPosterTile(
                title: entry.displayTitle,
                posterUrl: entry.posterUrl,
                fallbackColor: SeenlyPalette.mediaColor(entry.mediaType),
                mediaType: entry.mediaType,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.displayTitle, style: SeenlyText.cardTitle),
                  const SizedBox(height: 5),
                  Text('last logged ${_relativeDay(entry.watchedAt)}',
                      style: SeenlyText.metaLabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeDay(DateTime d) {
    final diff = DateTime.now().difference(d).inDays;
    if (diff <= 0) return 'today'.tr;
    if (diff == 1) return 'yesterday'.tr;
    return '$diff days ago';
  }
}

/// The "watching now" strip above ask teamira: one horizontal card per
/// title currently in progress — a live journey, or a series with at
/// least one episode logged but not finished (see ProfileCollections
/// .watching) — swipeable left/right when there's more than one. Reuses
/// the exact same tap destinations ProfileScreen's own "watching now"
/// tab already opens (openActiveJourney / showSeriesEpisodesSheet /
/// TitleDetailScreen), so tapping a card here lands on the same familiar
/// screen either way.
///
/// Auto-advances every 10 seconds when there's more than one card, the
/// same idle-rotation idea as Profile's cover [_StoriesBanner] — a soft
/// [Curves.easeInOutCubic] glide rather than a hard page-snap. A manual
/// swipe (or tapping a dot) resets the clock to wherever it lands, and
/// a finger down on the strip pauses the clock until it lifts, exactly
/// like the stories banner's long-press-to-pause — so the rotation
/// never fights a swipe that's still in progress.
class _WatchingNowSection extends StatefulWidget {
  final List<ActiveJourney> journeys;
  final List<WatchlistEntry> entries;
  const _WatchingNowSection({required this.journeys, required this.entries});

  @override
  State<_WatchingNowSection> createState() => _WatchingNowSectionState();
}

class _WatchingNowSectionState extends State<_WatchingNowSection> {
  static const _autoAdvanceDelay = Duration(seconds: 10);
  static const _glideDuration = Duration(milliseconds: 550);

  late final PageController _controller;
  double _page = 0;
  Timer? _autoAdvanceTimer;
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
    _controller.addListener(() {
      if (!_controller.hasClients || _controller.page == null) return;
      setState(() => _page = _controller.page!);
    });
    _scheduleAutoAdvance();
  }

  int get _count => widget.journeys.length + widget.entries.length;

  void _scheduleAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    if (_count <= 1) return;
    _autoAdvanceTimer = Timer(_autoAdvanceDelay, _advance);
  }

  void _advance() {
    if (!mounted || _held || _count <= 1 || !_controller.hasClients) return;
    final current = _controller.page?.round() ?? 0;
    final next = current + 1;
    // Loops back to the first card rather than stalling on the last one
    // — same "deck, not a dead end" behaviour as the stories banner.
    _controller.animateToPage(
      next >= _count ? 0 : next,
      duration: _glideDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _WatchingNowSection old) {
    super.didUpdateWidget(old);
    // The strip can change size while still mounted (a journey finishing,
    // a new one starting) — restart the clock for whatever's showing now.
    if (old.journeys.length + old.entries.length != _count) {
      _scheduleAutoAdvance();
    }
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return Listener(
      onPointerDown: (_) {
        _held = true;
        _autoAdvanceTimer?.cancel();
      },
      onPointerUp: (_) {
        _held = false;
        _scheduleAutoAdvance();
      },
      onPointerCancel: (_) {
        _held = false;
        _scheduleAutoAdvance();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (count > 1) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Row(
                children: [
                  for (var i = 0; i < count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 5),
                      width: _page.round() == i ? 16 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _page.round() == i
                            ? SeenlyPalette.accent
                            : SeenlyPalette.accent.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ],
          SizedBox(
            height: 196,
            child: PageView.builder(
              controller: _controller,
              padEnds: false,
              itemCount: count,
              onPageChanged: (_) => _scheduleAutoAdvance(),
              itemBuilder: (context, i) {
                final card = i < widget.journeys.length
                    ? _WatchingNowJourneyCard(journey: widget.journeys[i])
                    : _WatchingNowEntryCard(entry: widget.entries[i - widget.journeys.length]);
                return Padding(
                  padding: const EdgeInsets.only(left: 22, right: 8),
                  child: card,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A labeled progress bar sitting *underneath* a "watching now" card's
/// poster — deliberately its own separate strip rather than another
/// overlay on the artwork (see _PosterProgressBar in profile_screen.dart
/// for that overlay style, used on the grid tiles), so the remaining
/// amount reads clearly against the card's own paper background instead
/// of competing with whatever's in the image behind it.
class _UnderPosterProgressBar extends StatelessWidget {
  final double? progress; // 0..1, or null for an indeterminate "in progress" dash
  final String label;
  final Color accent;
  const _UnderPosterProgressBar({required this.progress, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            // A determinate bar snapping straight to its value on first
            // frame reads as data, not as progress — it never actually
            // shows anything filling up. Growing it in from empty once,
            // the same "settle into place" beat as everything else on
            // this screen, is what makes it read as a diary that's
            // tracking your evening rather than a stat dump. On the
            // live journey card this rebuilds every tick as time
            // passes; TweenAnimationBuilder only replays `begin` on its
            // very first build, so later ticks glide from wherever the
            // bar currently sits to the new value instead of resetting.
            child: progress == null
                ? LinearProgressIndicator(
                    value: null,
                    minHeight: 5,
                    backgroundColor: SeenlyPalette.border,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  )
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: progress),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      backgroundColor: SeenlyPalette.border,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
      ],
    );
  }
}

Color _watchingNowAccent(LogTheme theme) => switch (theme) {
      LogTheme.coach => SeenlyPalette.periwinkle,
      LogTheme.garden => SeenlyPalette.sage,
      LogTheme.ticket => SeenlyPalette.coral,
    };

String _fmtMinutesLeft(int minutes) {
  if (minutes <= 0) return 'almost there';
  if (minutes < 60) return '$minutes min left';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h left' : '${h}h ${m}min left';
}

/// The "watching now" card for a title with a live journey running right
/// now — horizontal backdrop up top, progress-against-the-route strip
/// underneath. Ticks its own timer for the same reason
/// [_WatchingNowTile] in profile_screen.dart does: pause/resume/start
/// are the only things that fire AppState's own notifyListeners, not
/// plain elapsed time.
class _WatchingNowJourneyCard extends StatefulWidget {
  final ActiveJourney journey;
  const _WatchingNowJourneyCard({required this.journey});

  @override
  State<_WatchingNowJourneyCard> createState() => _WatchingNowJourneyCardState();
}

class _WatchingNowJourneyCardState extends State<_WatchingNowJourneyCard> {
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

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final elapsed = journey.elapsedAt(DateTime.now());
    final progress = (elapsed.inSeconds / (journey.routeMinutes * 60)).clamp(0, 1).toDouble();
    final minutesLeft = journey.routeMinutes - elapsed.inMinutes;
    final accent = _watchingNowAccent(journey.theme);

    return PressScale(
      scaleTo: 0.98,
      onTap: () => openActiveJourney(context, journey),
      child: _WatchingNowCardChrome(
        title: journey.item.title.display,
        imageUrl: journey.item.backdropUrl ?? journey.item.posterUrl,
        fallbackColor: SeenlyPalette.mediaColor(journey.item.mediaType),
        badge: Icon(
          journey.isPaused ? Icons.pause_circle_filled : Icons.play_circle_fill,
          size: 16,
          color: SeenlyPalette.paper,
        ),
        progressBar: _UnderPosterProgressBar(
          progress: progress,
          label: journey.isPaused ? 'paused' : _fmtMinutesLeft(minutesLeft),
          accent: accent,
        ),
      ),
    );
  }
}

/// The "watching now" card for a title that's mid-series with no live
/// journey running (see ProfileCollections.watching) — fetches the same
/// watched/total episode counts [_WatchingCollectionTile] in
/// profile_screen.dart does, for the exact same reason: a real fraction
/// against episode count rather than a dash, wherever that data is
/// available.
class _WatchingNowEntryCard extends StatefulWidget {
  final WatchlistEntry entry;
  const _WatchingNowEntryCard({required this.entry});

  @override
  State<_WatchingNowEntryCard> createState() => _WatchingNowEntryCardState();
}

class _WatchingNowEntryCardState extends State<_WatchingNowEntryCard> {
  double? _progress;
  int? _watched;
  int? _total;

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
      setState(() {
        _progress = watched / total;
        _watched = watched;
        _total = total;
      });
    } catch (_) {
      // best-effort — leave the indeterminate dash showing
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final label = _watched != null && _total != null ? '$_watched/$_total episodes' : 'in progress';
    // Only meaningful for the non-series tap path below (straight to
    // TitleDetailScreen) — series taps open a sheet instead, so this tag
    // just never gets matched there, which is harmless.
    final heroTag = _homePosterHeroTag('watchingnow', entry.source, entry.mediaId);
    return PressScale(
      scaleTo: 0.98,
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
                  heroTag: heroTag,
                ),
              ),
            ),
      child: _WatchingNowCardChrome(
        title: entry.displayTitle,
        imageUrl: entry.posterUrl,
        fallbackColor: SeenlyPalette.mediaColor(entry.mediaType),
        heroTag: _isSeries ? null : heroTag,
        progressBar: _UnderPosterProgressBar(
          progress: _progress,
          label: label,
          accent: SeenlyPalette.inkFaint,
        ),
      ),
    );
  }
}

/// Shared shell for both "watching now" cards above: the horizontal
/// image with the title floated over a bottom gradient (same "melts
/// into the page" treatment as [TitleDetailScreen]'s own backdrop —
/// see _PosterBanner in title_detail_screen.dart), the progress strip
/// living underneath it rather than layered on top.
class _WatchingNowCardChrome extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final Color fallbackColor;
  final Widget progressBar;
  final Widget? badge;
  // Only set for cards that actually land on TitleDetailScreen (see
  // _WatchingNowEntryCard's non-series branch) — the live-journey card
  // opens its own journey screen instead, so it never passes one and
  // this stays a plain image there, same as before.
  final String? heroTag;
  const _WatchingNowCardChrome({
    required this.title,
    required this.imageUrl,
    required this.fallbackColor,
    required this.progressBar,
    this.badge,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 150,
            width: double.infinity,
            color: fallbackColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null)
                  _HeroableImage(
                    heroTag: heroTag,
                    url: imageUrl!,
                    fallbackColor: fallbackColor,
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x99000000)],
                      stops: [0.5, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Row(
                    children: [
                      if (badge != null) ...[badge!, const SizedBox(width: 6)],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(
                              italic: true, size: 15, color: SeenlyPalette.paper),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        progressBar,
      ],
    );
  }
}

class _TonightBanner extends StatelessWidget {
  final String label;
  final SeenlyCollection collection;
  const _TonightBanner({required this.label, required this.collection});

  @override
  Widget build(BuildContext context) {
    final firstItem = collection.items.first;
    final heroTag = _homePosterHeroTag('tonight', firstItem.source, firstItem.id);
    return PressScale(
      scaleTo: 0.97,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TitleDetailScreen(
            mediaId: firstItem.id,
            source: firstItem.source,
            mediaType: firstItem.mediaType,
            seedTitle: firstItem.title.display,
            seedPosterUrl: firstItem.posterUrl,
            heroTag: heroTag,
          ),
        ),
      ),
      child: Container(
        height: 150,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: SeenlyPalette.accent,
          borderRadius: BorderRadius.circular(14),
        ),
        // Used to be a single DecorationImage (with its darkening
        // colorFilter) on the Container itself — but a Hero needs an
        // actual Image *widget* to fly, not a decoration, so the tinted
        // poster and the text now sit in their own Stack layers instead.
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (firstItem.posterUrl != null)
              Hero(
                tag: heroTag,
                child: Image.network(
                  firstItem.posterUrl!,
                  fit: BoxFit.cover,
                  color: Colors.black.withOpacity(0.35),
                  colorBlendMode: BlendMode.darken,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: SeenlyText.mono(size: 9, color: SeenlyPalette.accentOnAccent)),
                    const SizedBox(height: 4),
                    Text(collection.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SeenlyText.serif(
                            italic: true, size: 15, color: SeenlyPalette.paper)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "on this day" header plus its stack of [_OnThisDayCard]s, with a
/// "×" that closes the whole section for [dateKey] (today). Same
/// fade-then-collapse dismiss as [_AutoTrackingBanner] — see that
/// widget's docstring — so tapping the "×" fades the section out in
/// place first, then lets its height collapse a beat later, and only
/// then tells [OnThisDayPrefsService] to persist the dismissal (which
/// is what makes home_screen's own `!isDismissed(...)` check drop this
/// section's whole SliverPadding from the list). By the time that
/// happens the section is already visually gone, so there's no snap.
/// Tomorrow's different `dateKey` brings the section back on its own.
class _OnThisDaySection extends StatefulWidget {
  final String dateKey;
  final List<_OnThisDayMatch> matches;
  const _OnThisDaySection({required this.dateKey, required this.matches});

  @override
  State<_OnThisDaySection> createState() => _OnThisDaySectionState();
}

class _OnThisDaySectionState extends State<_OnThisDaySection> {
  bool _exiting = false;
  bool _collapsed = false;

  static const _fadeDuration = Duration(milliseconds: 220);
  static const _collapseDuration = Duration(milliseconds: 260);

  Future<void> _dismiss() async {
    if (_exiting) return;
    setState(() => _exiting = true);
    await Future.delayed(_fadeDuration);
    if (mounted) setState(() => _collapsed = true);
    await context.read<OnThisDayPrefsService>().dismiss(widget.dateKey);
  }

  @override
  Widget build(BuildContext context) {
    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: _dismiss,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(right: 6, top: 2, bottom: 2),
                child: Icon(Icons.close, size: 16, color: SeenlyPalette.inkFaint),
              ),
            ),
            const Icon(Icons.auto_stories_outlined, size: 15, color: SeenlyPalette.accent),
            const SizedBox(width: 7),
            Text('on this day'.tr, style: SeenlyText.sectionTitle),
          ],
        ),
        const SizedBox(height: 10),
        for (final m in widget.matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OnThisDayCard(entry: m.entry, monthsAgo: m.monthsAgo),
          ),
      ],
    );

    return AnimatedSize(
      duration: _collapseDuration,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: _fadeDuration,
        curve: Curves.easeOut,
        opacity: _exiting ? 0 : 1,
        child: _collapsed ? const SizedBox.shrink() : section,
      ),
    );
  }
}

/// A little memory card on Home: today's date, some months or years
/// back, lined up against a diary entry. Cropped to a wide frame — the
/// same horizontal-backdrop language as the Profile header's "stories"
/// banner (see ProfileScreen's _StoriesBanner/_Slide) and the favorite-
/// films shelf, rather than a stretched vertical poster — sitting on a
/// soft paper card with the same resting shadow every other card here
/// uses, so it reads as a warm little keepsake rather than a data row.
class _OnThisDayCard extends StatelessWidget {
  final DiaryEntry entry;
  final int monthsAgo;
  const _OnThisDayCard({required this.entry, required this.monthsAgo});

  String get _label {
    if (monthsAgo % 12 == 0) {
      final years = monthsAgo ~/ 12;
      return years == 1
          ? 'a year ago today, you watched'
          : '$years years ago today, you watched';
    }
    return monthsAgo == 1
        ? 'a month ago today, you watched'
        : '$monthsAgo months ago today, you watched';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = entry.backdropUrl ?? entry.posterUrl;
    return PressScale(
      onTap: () => showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry)),
      scaleTo: 0.98,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 7,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? FadeInNetworkImage(
                      url: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: Container(color: SeenlyPalette.mediaColor(entry.mediaType)),
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [SeenlyPalette.tapeRose, SeenlyPalette.cork],
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_label, style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                        const SizedBox(height: 3),
                        Text(
                          entry.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.cardTitle,
                        ),
                      ],
                    ),
                  ),
                  if (entry.rating != null) ...[
                    const SizedBox(width: 10),
                    HeartRating(value: entry.rating!, size: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Link once with a partner via a short code — after that the link just
/// sits there quietly, ready for the one-tap "suggest this for tonight"
/// button on any title screen. Also doubles as the inbox for whatever
/// they've sent back: a light poll (same rhythm as Watch Together's
/// session screen) keeps it current without anyone needing to pull to
/// refresh.
///
/// On Home this now only ever shows as a compact half-width teaser (see
/// build() below, paired with _CantDecideCard): a glance at status plus how
/// many suggestions are waiting. Tapping it opens everything else —
/// pairing, joining, and the suggestion inbox itself — in a bottom sheet
/// (see _openSheet), rather than spending half the Home screen on a form
/// most visits don't need to touch. The polling and all the pairing/
/// suggestion logic below are unchanged from before; only where it's
/// drawn changed. [_rebuild] is the one addition: it mirrors every state
/// change into the open sheet too (via a StatefulBuilder's own setState,
/// captured in [_sheetRebuild] for as long as the sheet is open) since a
/// bottom sheet route sits above this widget in the tree and won't
/// otherwise notice this State rebuilding.
class _CoViewingCard extends StatefulWidget {
  @override
  State<_CoViewingCard> createState() => _CoViewingCardState();
}

class _CoViewingCardState extends State<_CoViewingCard> {
  static const _pollInterval = Duration(seconds: 4);

  PartnerStatus? _status;
  List<Suggestion> _suggestions = const [];
  bool _loading = true;
  bool _busy = false; // pairing/joining/unlinking in flight
  bool _entering = false; // showing the "type a code" field
  final _codeController = TextEditingController();
  String? _joinError;
  Timer? _pollTimer;
  bool _accepting = false;

  // Set while the sheet from _openSheet is on screen; see the class doc
  // comment above for why every state change below also pokes this.
  void Function(void Function())? _sheetRebuild;

  void _rebuild(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _sheetRebuild?.call(() {});
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) _rebuild(() => _loading = true);
    try {
      final app = context.read<AppState>();
      final status = await app.partner.status();
      final suggestions =
          status.linked ? await app.partner.suggestions() : const <Suggestion>[];
      if (!mounted) return;
      _rebuild(() {
        _status = status;
        _suggestions = suggestions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // A missed poll just tries again next tick — no need to interrupt
      // the person over one dropped request.
      if (!silent) _rebuild(() => _loading = false);
    }
  }

  Future<void> _generateCode() async {
    _rebuild(() => _busy = true);
    try {
      final status = await context.read<AppState>().partner.pair();
      if (!mounted) return;
      _rebuild(() {
        _status = status;
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _rebuild(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      _rebuild(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't get a code just now — try again".tr)));
    }
  }

  Future<void> _submitJoin() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _rebuild(() => _joinError = 'codes are 6 characters');
      return;
    }
    _rebuild(() {
      _busy = true;
      _joinError = null;
    });
    try {
      final status = await context.read<AppState>().partner.join(code);
      if (!mounted) return;
      _rebuild(() {
        _status = status;
        _busy = false;
        _entering = false;
        _codeController.clear();
      });
      _refresh(silent: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _rebuild(() {
        _busy = false;
        _joinError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      _rebuild(() {
        _busy = false;
        _joinError = 'check the connection and try again';
      });
    }
  }

  void _dismiss(Suggestion s) {
    _rebuild(() => _suggestions = _suggestions.where((x) => x.id != s.id).toList());
    context.read<AppState>().partner.dismiss(s.id).catchError((_) {
      // Best-effort — worst case it reappears on the next poll.
    });
  }

  Future<void> _accept(Suggestion s) async {
    if (_accepting) return;
    _rebuild(() => _accepting = true);
    try {
      await context.read<AppState>().partner.acceptSuggestion(s.id);
      if (!mounted) return;
      _rebuild(() {
        _suggestions = _suggestions.where((x) => x.id != s.id).toList();
        _accepting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('planned together — watch it whenever you\'re both ready'.tr)),
      );
    } catch (_) {
      if (!mounted) return;
      _rebuild(() => _accepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't agree to that just now — try again".tr)),
      );
    }
  }

  Future<void> _openCoViewing() async {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(); // close the sheet first
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CoViewingScreen()),
    );
    // Unlinking happens from the new screen's settings now, so re-check
    // status on return rather than assuming we're still linked.
    if (mounted) _refresh(silent: true);
  }

  void _open(Suggestion s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TitleDetailScreen(
          mediaId: s.mediaId,
          source: s.source,
          mediaType: s.mediaType,
          seedTitle: s.displayTitle,
          seedPosterUrl: s.posterUrl,
        ),
      ),
    );
  }

  /// Was a bottom sheet — for the "not linked yet" states especially
  /// (just a code, or a short entry field) that left a small card
  /// stranded low on an otherwise-empty screen. Centered instead, over
  /// a softly blurred, warm-tinted backdrop — same treatment as the
  /// seat-picker/ticket overlays elsewhere in the app (see
  /// widgets/seat_picker_overlay.dart) — so it reads as its own quiet
  /// moment rather than a sheet that forgot to fill itself out. Tapping
  /// the blurred backdrop, or the close mark on the card, dismisses it;
  /// tapping the card itself doesn't.
  Future<void> _openSheet() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (routeContext, anim, __) => FadeTransition(
          opacity: anim,
          child: StatefulBuilder(
            builder: (sheetContext, sheetSetState) {
              _sheetRebuild = sheetSetState;
              return Scaffold(
                backgroundColor: Colors.transparent,
                body: GestureDetector(
                  onTap: () => Navigator.of(sheetContext).maybePop(),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: SeenlyPalette.ink.withOpacity(0.32),
                      child: SafeArea(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.only(
                              left: 24,
                              right: 24,
                              top: 24,
                              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
                            ),
                            child: GestureDetector(
                              onTap: () {}, // swallow — don't let a tap on the card dismiss it
                              child: Container(
                                width: math.min(MediaQuery.of(sheetContext).size.width - 48, 380),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: SeenlyPalette.paper,
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.22),
                                      blurRadius: 30,
                                      offset: const Offset(0, 14),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: GestureDetector(
                                        onTap: () => Navigator.of(sheetContext).maybePop(),
                                        child: const Padding(
                                          padding: EdgeInsets.only(bottom: 6),
                                          child: Icon(Icons.close, size: 18, color: SeenlyPalette.inkFaint),
                                        ),
                                      ),
                                    ),
                                    _buildSheetBody(sheetContext),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    _sheetRebuild = null;
  }

  Widget _buildSheetBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (_status?.linked ?? false) ? _openCoViewing : null,
          child: Row(
            children: [
              const Icon(Icons.favorite_border, size: 15, color: SeenlyPalette.accent),
              const SizedBox(width: 7),
              Text('co-viewing'.tr, style: SeenlyText.sectionTitle),
              if (_status?.linked ?? false) ...[
                const Spacer(),
                const Icon(Icons.chevron_right, size: 16, color: SeenlyPalette.inkFaint),
              ],
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _status?.linked ?? false
              ? 'linked with ${_status!.partnerUsername} — suggest a title from any title page'
              : 'link with a partner, then suggest titles with one tap',
          style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(
              width: 16,
              height: 16,
              child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
            ),
          )
        else if (_status?.linked ?? false)
          _LinkedBody(
            suggestions: _suggestions,
            onOpen: _open,
            onAcceptSuggestion: _accept,
            onDismissSuggestion: _dismiss,
            onOpenCoViewing: _openCoViewing,
            accepting: _accepting,
          )
        else if (_entering)
          _JoinCodeInline(
            controller: _codeController,
            error: _joinError,
            busy: _busy,
            onJoin: _submitJoin,
            onBack: () => _rebuild(() {
              _entering = false;
              _joinError = null;
            }),
          )
        else if (_status?.pendingCode != null)
          _PendingCodeBody(
            code: _status!.pendingCode!,
            onEnterInstead: () => _rebuild(() => _entering = true),
          )
        else
          Row(
            children: [
              PrimaryButton(
                label: 'get a code',
                onTap: _generateCode,
                loading: _busy,
                expand: false,
              ),
              const SizedBox(width: 14),
              TextButton(
                onPressed: () => _rebuild(() => _entering = true),
                child: Text('have a code already?'.tr,
                    style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final linked = _status?.linked ?? false;
    final pendingSuggestions = linked ? _suggestions.length : 0;
    return PressScale(
      onTap: _openSheet,
      scaleTo: 0.97,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: const BoxDecoration(color: SeenlyPalette.paper),
          child: Stack(
            children: [
              // Decorative, sits behind the real content and bleeds
              // slightly past the card's own edge — the ClipRRect above
              // trims it back to the card's rounded corner.
              if (context.watch<RabbitMascotPrefsService>().enabled)
                Positioned(
                  right: -8,
                  bottom: -6,
                  child: Opacity(
                    opacity: 0.9,
                    child: CoViewingBunniesCorner(size: 58),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.favorite_border, size: 17, color: SeenlyPalette.accent),
                    const SizedBox(height: 10),
                    Text('co-viewing'.tr, style: SeenlyText.sectionTitle),
                    const SizedBox(height: 3),
                    Text(
                      linked ? 'linked with ${_status!.partnerUsername}' : 'link with a partner',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(italic: true, size: 11, color: SeenlyPalette.inkMuted),
                    ),
                    const SizedBox(height: 10),
                    if (pendingSuggestions > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: SeenlyPalette.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          pendingSuggestions == 1 ? '1 suggestion waiting' : '$pendingSuggestions suggestions waiting',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.accent, weight: FontWeight.w700),
                        ),
                      )
                    else if (!linked && (_status?.pendingCode != null))
                      Text('code waiting for them'.tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint))
                    else
                      Text(linked ? 'tap to see or suggest' : 'tap to get started',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Short "what's the flame" explainer, opened by tapping the streak
/// count next to the greeting. Same soft, blurred-backdrop centered
/// card language as HowItWorksSheet and the title preview sheets — a
/// small paper card floating over a blurred page, not a bottom sheet —
/// since that's the register everything else someone taps into for a
/// quick explanation already uses.
class _StreakInfoSheet extends StatelessWidget {
  final int streakDays;
  const _StreakInfoSheet({required this.streakDays});

  @override
  Widget build(BuildContext context) {
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
            child: GestureDetector(
              onTap: () {}, // swallow — a tap on the card itself shouldn't dismiss it
              child: Container(
                width: 300,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                decoration: BoxDecoration(
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: SeenlyPalette.ink.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 12)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            size: 18, color: SeenlyPalette.mustard),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            streakDays == 1 ? '1 evening streak' : '$streakDays evening streak',
                            style: SeenlyText.serif(size: 16, weight: FontWeight.w700),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 13, color: SeenlyPalette.inkMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "the flame counts consecutive evenings with at least one log — any diary entry keeps it going. today doesn't break it until it's over, so there's still time before it resets.".tr,
                      style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Taking the streak card's old spot beside co-viewing: a single tap
/// into the whole "can't decide?" flow (filters → ask teamira / random
/// pick / spin the reel / swipe through — see screens/decide/). This
/// card itself holds no state at all; it's just the door in.
/// Home teaser for Settings > auto-tracking (see integrations_screen.dart)
/// — most people never open Settings on their own, so this puts the
/// feature where they'll actually see it. Tapping it opens the real
/// screen; the × just hides this card on this device (see
/// [AutoTrackingPrefsService.dismissBanner]) — it doesn't touch
/// auto-tracking itself, which stays exactly as connected/unconnected as
/// it already was.
class _AutoTrackingBanner extends StatefulWidget {
  final VoidCallback onOpen;
  const _AutoTrackingBanner({required this.onOpen});

  @override
  State<_AutoTrackingBanner> createState() => _AutoTrackingBannerState();
}

class _AutoTrackingBannerState extends State<_AutoTrackingBanner> {
  // Same fade-then-collapse pattern as TodayPickCard's own dismiss —
  // see that widget's docstring. `_exiting` fades the banner out in
  // place the instant "×" is tapped; `_collapsed` (a beat later) then
  // lets its height animate shut too. `AutoTrackingPrefsService.dismissBanner`
  // — which is what makes home_screen's own `if (!bannerDismissed)`
  // drop this widget's whole SliverPadding from the list — is only
  // called once that sequence finishes, so by the time home_screen
  // removes the slot it's already visually collapsed to nothing and
  // there's no snap.
  bool _exiting = false;
  bool _collapsed = false;

  static const _fadeDuration = Duration(milliseconds: 220);
  static const _collapseDuration = Duration(milliseconds: 260);

  Future<void> _dismiss() async {
    if (_exiting) return;
    setState(() => _exiting = true);
    await Future.delayed(_fadeDuration);
    if (mounted) setState(() => _collapsed = true);
    await context.read<AutoTrackingPrefsService>().dismissBanner();
  }

  @override
  Widget build(BuildContext context) {
    final banner = PressScale(
      onTap: widget.onOpen,
      scaleTo: 0.97,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: SeenlyPalette.accent.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.sync_outlined, size: 15, color: SeenlyPalette.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('log evenings without opening the app'.tr,
                      style: SeenlyText.serif(size: 12.5, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    'auto-tracking picks it up from Plex, Jellyfin, Kodi or your browser and logs it here on its own — set it up once'.tr,
                    style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: widget.onOpen,
                    child: Text(
                      'set it up →'.tr,
                      style: SeenlyText.serif(size: 12.5, weight: FontWeight.w600, color: SeenlyPalette.accent),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _dismiss,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close, size: 16, color: SeenlyPalette.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );

    return AnimatedSize(
      duration: _collapseDuration,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: _fadeDuration,
        curve: Curves.easeOut,
        opacity: _exiting ? 0 : 1,
        child: _collapsed ? const SizedBox.shrink() : banner,
      ),
    );
  }
}

class _CantDecideCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DecideFiltersScreen()),
      ),
      scaleTo: 0.97,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline_rounded, size: 16, color: SeenlyPalette.accent),
                const SizedBox(width: 6),
                Text('can\'t decide?'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 15, color: SeenlyPalette.inkFaint),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.accent.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.auto_awesome_outlined, size: 15, color: SeenlyPalette.accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'let\'s figure it out'.tr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SeenlyText.serif(size: 12.5, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCodeBody extends StatelessWidget {
  final String code;
  final VoidCallback onEnterInstead;
  const _PendingCodeBody({required this.code, required this.onEnterInstead});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('if they\'re nearby, let them scan it'.tr,
            style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
        const SizedBox(height: 10),
        Center(child: PairingQrCode(code: code)),
        const SizedBox(height: 14),
        Center(
          child: Text('or read them the code'.tr,
              style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: SeenlyPalette.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SeenlyPalette.border),
            ),
            child: Text(
              code,
              style: SeenlyText.mono(size: 20, color: SeenlyPalette.ink, weight: FontWeight.w700)
                  .copyWith(letterSpacing: 5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: onEnterInstead,
            child: Text('got a code from them instead?'.tr,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
          ),
        ),
      ],
    );
  }
}

/// The other half of pairing — typing in a code someone sent you.
class _JoinCodeInline extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onBack;

  const _JoinCodeInline({
    required this.controller,
    required this.error,
    required this.busy,
    required this.onJoin,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: TextButton.icon(
            onPressed: () async {
              final scanned = await showPairingScanner(context);
              if (scanned != null) {
                controller.text = scanned;
                onJoin();
              }
            },
            icon: const Icon(Icons.qr_code_scanner, size: 16, color: SeenlyPalette.accent),
            label: Text('scan their code instead'.tr,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: SeenlyText.mono(size: 16, color: SeenlyPalette.ink, weight: FontWeight.w700)
                    .copyWith(letterSpacing: 4),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: SeenlyPalette.background,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: SeenlyPalette.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            PrimaryButton(label: 'join', onTap: onJoin, loading: busy, expand: false),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: SeenlyText.mono(size: 10, color: SeenlyPalette.coral)),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: onBack,
          child: Text('back'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
        ),
      ],
    );
  }
}

/// Linked state: who you're linked with, an escape hatch to unlink, and
/// whatever they've suggested — each row tappable to open the title, with
/// a quiet X to clear it without looking.
class _LinkedBody extends StatelessWidget {
  final List<Suggestion> suggestions;
  final ValueChanged<Suggestion> onOpen;
  final ValueChanged<Suggestion> onAcceptSuggestion;
  final ValueChanged<Suggestion> onDismissSuggestion;
  final VoidCallback onOpenCoViewing;
  final bool accepting;

  const _LinkedBody({
    required this.suggestions,
    required this.onOpen,
    required this.onAcceptSuggestion,
    required this.onDismissSuggestion,
    required this.onOpenCoViewing,
    required this.accepting,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (suggestions.isEmpty)
          Text('nothing suggested yet — it\'ll show up here'.tr,
              style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder))
        else
          Column(
            children: [
              for (final s in suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SuggestionRow(
                    suggestion: s,
                    busy: accepting,
                    onOpen: () => onOpen(s),
                    onAccept: () => onAcceptSuggestion(s),
                    onDecline: () => onDismissSuggestion(s),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onOpenCoViewing,
          child: Text('open co-viewing'.tr,
              style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
        ),
      ],
    );
  }
}

/// A suggestion sits here as an open question, not a done deal — it only
/// becomes "planned together" once the receiver taps "watch together".
/// Tapping the poster/title just opens it for a closer look and doesn't
/// count as a decision either way.
class _SuggestionRow extends StatelessWidget {
  final Suggestion suggestion;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _SuggestionRow({
    required this.suggestion,
    required this.busy,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onOpen,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    width: 36,
                    height: 50,
                    child: suggestion.posterUrl != null
                        ? Image.network(suggestion.posterUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: SeenlyPalette.mediaColor(suggestion.mediaType)))
                        : Container(color: SeenlyPalette.mediaColor(suggestion.mediaType)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${suggestion.senderUsername} suggested this',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                      const SizedBox(height: 3),
                      Text(suggestion.displayTitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.cardTitle),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: busy ? null : onAccept,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: busy
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: ThemedLoadingIndicator(
                                strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                          )
                        : Text('tap to agree — watch it together'.tr,
                            style: SeenlyText.mono(
                                size: 9.5, color: SeenlyPalette.accentOnAccent, weight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: busy ? null : onDecline,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.close, size: 14, color: SeenlyPalette.inkFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A row in the "more for tonight" mosaic — either 2 large tiles or 3
/// smaller ones, see [_HomeScreenState._feedMosaicRows].
class _FeedRow extends StatelessWidget {
  final List<MediaItem> items;
  final bool large;
  const _FeedRow({required this.items, required this.large});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _FeedTile(item: items[i], large: large)),
        ],
      ],
    );
  }
}

/// One poster-backed tile in the mosaic — full-bleed image, a dark gradient
/// at the bottom, and the title (plus year/genre when [large]) sitting on
/// top. Same "picked for tonight" visual language, just resized.
class _FeedTile extends StatelessWidget {
  final MediaItem item;
  final bool large;
  const _FeedTile({required this.item, required this.large});

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (item.year != null) '${item.year}',
      if (item.genres.isNotEmpty) item.genres.first,
    ].join(' · ');

    final heroTag = _homePosterHeroTag('feed', item.source, item.id);
    return PressScale(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TitleDetailScreen(
            mediaId: item.id,
            source: item.source,
            mediaType: item.mediaType,
            seedTitle: item.title.display,
            seedPosterUrl: item.posterUrl,
            seedItem: item,
            heroTag: heroTag,
          ),
        ),
      ),
      scaleTo: 0.97,
      child: Container(
        height: large ? 172 : 128,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: SeenlyPalette.mediaColor(item.mediaType),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A plain colour fill first — the same one the decoration
            // used to carry — so there's always something solid under
            // the image while it fades in, never a flash of white. The
            // image itself drifts a few px as the feed scrolls (see
            // ParallaxPoster) — tiles above the middle of the screen
            // nudge one way, tiles below nudge the other, so the whole
            // mosaic feels like it has a little depth rather than
            // scrolling as one flat sheet.
            Hero(
              tag: heroTag,
              child: ParallaxPoster(
                url: item.posterUrl,
                tileHeight: large ? 172 : 128,
                placeholder: Container(color: SeenlyPalette.mediaColor(item.mediaType)),
              ),
            ),
            Container(
              alignment: Alignment.bottomLeft,
              padding: EdgeInsets.all(large ? 12 : 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.45, 1],
                  colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.display,
                    maxLines: large ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(
                        italic: true,
                        size: large ? 14 : 11,
                        color: SeenlyPalette.paper),
                  ),
                  if (large && meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(meta,
                        style: SeenlyText.mono(
                            size: 9, color: SeenlyPalette.paper.withOpacity(0.8))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final showMascot = context.watch<RabbitMascotPrefsService>().enabled;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Entrance(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showMascot) ...[
                const RabbitMascot(mood: RabbitMood.sad, size: 92),
                const SizedBox(height: 10),
              ],
              Text('couldn\'t reach the diary just now'.tr,
                  style: SeenlyText.serif(italic: true, color: SeenlyPalette.inkMuted)),
              const SizedBox(height: 14),
              PressScale(
                haptics: true,
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('try again'.tr,
                      style: SeenlyText.mono(color: SeenlyPalette.accent, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
