import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/collection.dart';
import '../../models/diary_entry.dart';
import '../../models/media_item.dart' show CastMember;
import '../../models/watchlist_entry.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/heart_rating.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/section_header.dart';
import '../../widgets/share_card.dart';
import '../../widgets/share_sheet.dart';
import '../../widgets/series_episodes_sheet.dart';
import '../../widgets/watched_preview_sheet.dart';
import '../../services/log_theme_service.dart';
import '../../theme/log_theme_copy.dart';
import '../../widgets/log_ritual.dart';
import '../../widgets/log_timeline.dart';
import '../collections/collection_full_screen.dart';
import '../search/search_screen.dart';
import '../shell/root_shell.dart';
import '../title/title_detail_screen.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  late Future<List<DiaryEntry>> _future;
  late Future<SeenlyCollection?> _pickedFuture;
  late Future<ProfileCollections?> _shelvesFuture;
  bool _refreshing = false;

  // "watching now" and "picked for you" are just the first two things in
  // the diary log's own ListView (see build below) — regular top-of-page
  // content, not a pinned/sticky header. They scroll away with the rest
  // of the page like everything below them once the person actually
  // scrolls, instead of staying glued to the top of the screen forever.
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().diary.list();
    _pickedFuture = _loadPicked();
    _shelvesFuture = _loadShelves();
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  Future<SeenlyCollection?> _loadPicked() async {
    // Best-effort — this strip is a discovery nudge, not core diary data,
    // so it just quietly disappears rather than showing an error block if
    // the catalog isn't reachable.
    try {
      final collections = await context.read<AppState>().feed.collections();
      final withItems = collections.where((c) => c.items.isNotEmpty).toList();
      if (withItems.isEmpty) return null;
      // Prefer the second shelf over the first when there is one, purely
      // so this doesn't just mirror Home's "picked for tonight" banner.
      return withItems.length > 1 ? withItems[1] : withItems.first;
    } catch (_) {
      return null;
    }
  }

  Future<ProfileCollections?> _loadShelves() async {
    // Same "best-effort" reasoning as _loadPicked above — "watching now"
    // (see _ShelvesStrip) is a nudge back to what's already in motion,
    // not core diary content, so a failed fetch just quietly collapses
    // the strip rather than showing an error block.
    try {
      return await context.read<AppState>().profile.collections();
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final next = context.read<AppState>().diary.list();
    final nextPicked = _loadPicked();
    final nextShelves = _loadShelves();
    setState(() {
      _future = next;
      _pickedFuture = nextPicked;
      _shelvesFuture = nextShelves;
    });
    try {
      await next;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    const months = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  Map<String, List<DiaryEntry>> _grouped(List<DiaryEntry> entries) {
    final map = <String, List<DiaryEntry>>{};
    for (final e in entries) {
      final key = _dayLabel(e.watchedAt);
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    // DiaryScreen doubles as a RootShell tab (which already supplies a
    // Scaffold + SafeArea around every tab) and as a screen pushed on
    // its own from Home/Profile's "diary"/"all" links. Giving it its
    // own Scaffold here makes the standalone push self-contained —
    // without one there's nothing painting the paper background behind
    // it, so it showed through as plain black. Harmless when nested
    // inside RootShell's Scaffold: same background color either way,
    // and a SafeArea inside a SafeArea just no-ops on the inner one.
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('diary', style: SeenlyText.screenTitle),
                  Row(
                    children: [
                      PressScale(
                        onTap: _refreshing ? null : _refresh,
                        haptics: true,
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: const BoxDecoration(
                            color: SeenlyPalette.paper,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: _refreshing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: ThemedLoadingIndicator(
                                      strokeWidth: 2, color: SeenlyPalette.accent),
                                )
                              : const Icon(Icons.refresh, size: 17, color: SeenlyPalette.ink),
                        ),
                      ),
                      PressScale(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SearchScreen()),
                        ),
                        haptics: true,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: SeenlyPalette.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add,
                              size: 16, color: SeenlyPalette.accentOnAccent),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
              child: PressScale(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 16, color: SeenlyPalette.inkFaint),
                      const SizedBox(width: 8),
                      Text('search a film, show, or game',
                          style: SeenlyText.serif(
                              italic: true, size: 13, color: SeenlyPalette.placeholder)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<DiaryEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return _fadeSwitch(const _DiarySkeleton(key: ValueKey('diary-skeleton')));
                  }
                  if (snapshot.hasError) {
                    return _fadeSwitch(RefreshIndicator(
                      key: const ValueKey('diary-error'),
                      onRefresh: _refresh,
                      color: SeenlyPalette.accent,
                      child: ListView(
                        controller: _logScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 60),
                        children: [
                          _ShelvesStrip(future: _shelvesFuture),
                          _PickedForYouStrip(future: _pickedFuture),
                          _ShelfPickStrip(future: _shelvesFuture),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 40, 22, 0),
                            child: Column(
                              children: [
                                Text('couldn\'t load the diary',
                                    textAlign: TextAlign.center,
                                    style: SeenlyText.serif(
                                        italic: true, color: SeenlyPalette.inkMuted)),
                                const SizedBox(height: 10),
                                Text('pull down, or tap the refresh icon above, to try again',
                                    textAlign: TextAlign.center,
                                    style: SeenlyText.mono(
                                        size: 10, color: SeenlyPalette.placeholder)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ));
                  }
                  final entries = snapshot.data!;
                  // Claims one stagger slot per top-level section, capped the
                  // same way Home's own `nextStagger` is — a section far down
                  // the page has nothing to cascade alongside by the time
                  // anyone actually scrolls to it, so the stagger only needs
                  // to read nicely for what's visible on first paint.
                  var revealSlot = 0;
                  Duration nextReveal({int step = 60, int maxSlots = 4}) {
                    final slot = revealSlot < maxSlots ? revealSlot : maxSlots;
                    final d = Duration(milliseconds: slot * step);
                    revealSlot++;
                    return d;
                  }
                  if (entries.isEmpty) {
                    return _fadeSwitch(RefreshIndicator(
                      key: const ValueKey('diary-empty'),
                      onRefresh: _refresh,
                      color: SeenlyPalette.accent,
                      child: ListView(
                        controller: _logScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 60),
                        children: [
                          ScrollReveal(delay: nextReveal(), child: _ShelvesStrip(future: _shelvesFuture)),
                          ScrollReveal(
                              delay: nextReveal(), child: _PickedForYouStrip(future: _pickedFuture)),
                          ScrollReveal(
                              delay: nextReveal(), child: _ShelfPickStrip(future: _shelvesFuture)),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ScrollReveal(
                                  delay: nextReveal(),
                                  child: DiaryCenterpiece(entries: entries),
                                ),
                                const SizedBox(height: 40),
                                Text(
                                  LogThemeCopy.emptyDiary(
                                      context.watch<LogThemeService>().theme),
                                  textAlign: TextAlign.center,
                                  style: SeenlyText.serif(
                                      italic: true, color: SeenlyPalette.placeholder),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ));
                  }
                  final grouped = _grouped(entries);
                  final logTheme = context.watch<LogThemeService>().theme;
                  // Built imperatively (rather than inline in the ListView's
                  // children list) so the washi-tape corner's color cursor
                  // can keep running across day groups — every day picks up
                  // the cycle where the previous one left off, instead of
                  // every group restarting on the same tape color.
                  var tapeCursor = 0;
                  final dayGroups = <Widget>[];
                  for (final key in grouped.keys) {
                    final dayEntries = grouped[key]!;
                    dayGroups.add(ScrollReveal(
                      // Each day group gets its own scroll-triggered reveal
                      // (rather than one shared delay for the whole log) so
                      // scrolling down the diary keeps unveiling fresh
                      // groups one at a time, at whatever pace someone
                      // actually scrolls — the same "settle in on the way
                      // down" feeling Home's own feed rows have.
                      riseBy: 16,
                      child: LogDayGroup(
                        theme: logTheme,
                        dayLabel: key,
                        tapeStartIndex: tapeCursor,
                        entries: [
                          for (final entry in dayEntries)
                            // A series row (season != null) is always one
                            // persistent card for the whole watch, not one
                            // evening — tap opens the season/episode sheet
                            // instead of the usual rating/note row.
                            entry.season != null
                                ? _SeriesEntryRow(entry: entry)
                                : _DiaryRow(entry: entry, onChanged: _refresh),
                        ],
                      ),
                    ));
                    tapeCursor += dayEntries.length;
                  }
                  return _fadeSwitch(RefreshIndicator(
                    key: const ValueKey('diary-content'),
                    onRefresh: _refresh,
                    color: SeenlyPalette.accent,
                    child: ListView(
                      controller: _logScrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        ScrollReveal(delay: nextReveal(), child: _ShelvesStrip(future: _shelvesFuture)),
                        ScrollReveal(
                            delay: nextReveal(), child: _PickedForYouStrip(future: _pickedFuture)),
                        ScrollReveal(
                            delay: nextReveal(), child: _ShelfPickStrip(future: _shelvesFuture)),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ScrollReveal(
                                delay: nextReveal(),
                                child: DiaryCenterpiece(entries: entries),
                              ),
                              const SizedBox(height: 22),
                              ScrollReveal(
                                delay: nextReveal(),
                                riseBy: 10,
                                child: Text('the log', style: SeenlyText.metaLabel),
                              ),
                              const SizedBox(height: 14),
                              ...dayGroups,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shared cross-fade for the diary body's top-level states (skeleton /
  /// error / empty / real content) — one [AnimatedSwitcher] keyed off
  /// each child's own [Key] so swapping between any two of them dissolves
  /// rather than cuts, matching Home's own [_fadeSwitch]. A rebuild that
  /// keeps the same state (fresh data landing under the same content key
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

/// A quiet stand-in for the diary body while the first load is in flight
/// — rough bones of the real layout (a shelf strip, the picked-for-you
/// strip, the centerpiece, a couple of log rows) in the same soft
/// shimmering paper tones [ShimmerBlock] uses everywhere else, so the
/// very first frame already reads as *this* screen instead of a bare
/// spinner. The cross-fade into real content (see
/// [_DiaryScreenState._fadeSwitch]) then feels like a settle, not a
/// swap — same reasoning as Home's own `_HomeSkeleton`.
class _DiarySkeleton extends StatelessWidget {
  const _DiarySkeleton({super.key});

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
        _bone(w: 110, h: 12, r: 6),
        const SizedBox(height: 10),
        SizedBox(
          height: 74,
          child: Row(
            children: [
              Expanded(child: _bone(h: 74, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 74, r: 14)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _bone(w: 140, h: 12, r: 6),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: Row(
            children: [
              Expanded(child: _bone(h: 150, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 150, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 150, r: 14)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _bone(w: 170, h: 12, r: 6),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: Row(
            children: [
              Expanded(child: _bone(h: 150, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 150, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 150, r: 14)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _bone(h: 140, r: 20),
        const SizedBox(height: 24),
        _bone(w: 70, h: 12, r: 6),
        const SizedBox(height: 14),
        _bone(h: 100, r: 14),
        const SizedBox(height: 12),
        _bone(h: 100, r: 14),
      ],
    );
  }
}

/// "watching now" — a quiet nudge back to what's already in motion,
/// sitting right above "picked for you" so the diary opens on the
/// person's own shelf before it opens on a recommendation. A single
/// horizontally-scrolling row of landscape info-chips (poster thumb +
/// title + a small status pill) rather than another vertical-poster
/// carousel like Collections or "picked for you" below use — same warm
/// paper-and-shadow language as the rest of the app, just built as a
/// little index-card shelf instead of a wall of posters, so the tab
/// doesn't read as three copies of the same strip in a row. Quietly
/// collapses to nothing while loading, on a failed fetch, or once the
/// shelf is actually empty — same reasoning as _PickedForYouStrip.
class _ShelvesStrip extends StatelessWidget {
  final Future<ProfileCollections?> future;
  const _ShelvesStrip({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileCollections?>(
      future: future,
      builder: (context, snapshot) {
        final collections = snapshot.data;
        if (collections == null) return const SizedBox.shrink();
        final watching = collections.watching;
        if (watching.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: _ShelfRow(
            label: 'watching now',
            icon: Icons.play_circle_outline,
            tint: SeenlyPalette.sage,
            entries: watching,
          ),
        );
      },
    );
  }
}

class _ShelfRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final List<WatchlistEntry> entries;

  const _ShelfRow({
    required this.label,
    required this.icon,
    required this.tint,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    // Two or fewer entries never fills a scrollable strip — it just
    // sits stranded on the left with a lot of empty space to its
    // right. Give those cards the full row width instead (split evenly
    // for two) so the shelf reads as deliberately laid out rather than
    // a horizontal list that happens to be short. Three or more keeps
    // the original scrollable strip of fixed-width chips.
    final fullWidth = entries.length <= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: tint),
              const SizedBox(width: 5),
              Text(label, style: SeenlyText.metaLabel),
              const SizedBox(width: 6),
              Text('${entries.length}', style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            ],
          ),
        ),
        if (fullWidth)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: HorizontalReveal(
                      delay: Duration(milliseconds: 40 + i.clamp(0, 3) * 70),
                      child: _ShelfChip(entry: entries[i], tint: tint, label: label, fullWidth: true),
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => HorizontalReveal(
                delay: Duration(milliseconds: 40 + i.clamp(0, 3) * 70),
                child: _ShelfChip(entry: entries[i], tint: tint, label: label),
              ),
            ),
          ),
      ],
    );
  }
}

class _ShelfChip extends StatelessWidget {
  final WatchlistEntry entry;
  final Color tint;
  final String label;
  final bool fullWidth;
  const _ShelfChip({required this.entry, required this.tint, required this.label, this.fullWidth = false});

  bool get _isSeries => entry.mediaType == 'series' || entry.mediaType == 'anime';

  @override
  Widget build(BuildContext context) {
    final posterW = fullWidth ? 52.0 : 40.0;
    final posterH = fullWidth ? 76.0 : 58.0;
    return PressScale(
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
      child: Container(
        width: fullWidth ? null : 172,
        height: fullWidth ? 96 : null,
        padding: EdgeInsets.all(fullWidth ? 10 : 8),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: posterW,
                height: posterH,
                child: entry.posterUrl != null
                    ? FadeInNetworkImage(
                        url: entry.posterUrl!,
                        fit: BoxFit.cover,
                        placeholder: Container(color: SeenlyPalette.mediaColor(entry.mediaType)),
                      )
                    : Container(color: SeenlyPalette.mediaColor(entry.mediaType)),
              ),
            ),
            SizedBox(width: fullWidth ? 10 : 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: fullWidth ? 13 : 11.5, color: SeenlyPalette.ink),
                  ),
                  SizedBox(height: fullWidth ? 6 : 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tint.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(label, style: SeenlyText.mono(size: 8, color: tint)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "picked for you" — a thin editorial strip sitting between the shelves
/// strip above and the diary list itself, so there's always something to
/// reach for even on a day you're not adding anything. Quietly collapses
/// to nothing while loading or if the catalog isn't reachable — this is a
/// bonus, not core diary content, so it shouldn't compete for attention
/// with a spinner or an error block the way the diary list itself does.
class _PickedForYouStrip extends StatelessWidget {
  final Future<SeenlyCollection?> future;
  const _PickedForYouStrip({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SeenlyCollection?>(
      future: future,
      builder: (context, snapshot) {
        final collection = snapshot.data;
        if (collection == null || collection.items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: SectionHeader(
                  title: 'picked for you',
                  trailing: 'all →',
                  centerTitle: true,
                  onTrailingTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CollectionFullScreen(collection: collection),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  itemCount: collection.items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final item = collection.items[i];
                  return HorizontalReveal(
                    delay: Duration(milliseconds: 40 + i.clamp(0, 3) * 70),
                    child: SizedBox(
                      width: 92,
                      child: ThemedPosterTile(
                          title: item.title.display,
                          posterUrl: item.posterUrl,
                          mediaType: item.mediaType,
                          fallbackColor: SeenlyPalette.gridColorFor(i),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TitleDetailScreen(
                                mediaId: item.id,
                                source: item.source,
                                mediaType: item.mediaType,
                                seedTitle: item.title.display,
                                seedPosterUrl: item.posterUrl,
                                seedItem: item,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "pick something from your shelf" — sits right under "picked for
/// you" so the diary opens on a nudge back into the person's *own*
/// pile before it opens on the log itself: three random draws from the
/// "plan to watch" shelf (see [ProfileCollections.watchLater]), a quiet
/// way to surface something that's already been sitting there instead
/// of leaving it to be rediscovered by scrolling Profile. Reuses the
/// same [ProfileCollections] future [_ShelvesStrip] already fetches —
/// this is the second reader of it, not a second network call.
///
/// The draw is picked once per fresh fetch and then held in state, so
/// scrolling past it and back (or an unrelated rebuild higher up the
/// tree) doesn't silently swap the three titles out from under
/// someone mid-glance — only a genuine reroll tap, or new data landing
/// after pull-to-refresh, picks again. Quietly collapses to nothing
/// while loading, on a failed fetch, or once the shelf is empty — same
/// "bonus, not core diary content" reasoning as [_PickedForYouStrip].
class _ShelfPickStrip extends StatefulWidget {
  final Future<ProfileCollections?> future;
  const _ShelfPickStrip({required this.future});

  @override
  State<_ShelfPickStrip> createState() => _ShelfPickStripState();
}

class _ShelfPickStripState extends State<_ShelfPickStrip> {
  List<WatchlistEntry>? _sourceShelf;
  List<WatchlistEntry> _picks = const [];

  List<WatchlistEntry> _draw(List<WatchlistEntry> shelf) {
    final pool = [...shelf]..shuffle();
    return pool.take(3).toList();
  }

  void _reroll(List<WatchlistEntry> shelf) => setState(() => _picks = _draw(shelf));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileCollections?>(
      future: widget.future,
      builder: (context, snapshot) {
        final collections = snapshot.data;
        if (collections == null || collections.watchLater.isEmpty) {
          return const SizedBox.shrink();
        }
        final shelf = collections.watchLater;
        // A genuinely new list instance means fresh data (first load,
        // or a pull-to-refresh landed) — reshuffle. Same list instance
        // on a rebuild just re-renders the standing draw.
        if (!identical(_sourceShelf, shelf)) {
          _sourceShelf = shelf;
          _picks = _draw(shelf);
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: SectionHeader(
                  title: 'pick something from your shelf',
                  trailing: shelf.length > 3 ? '↻' : null,
                  trailingStyle: SeenlyText.mono(size: 15, weight: FontWeight.w700, color: SeenlyPalette.inkFaint),
                  centerTitle: true,
                  onTrailingTap: shelf.length > 3 ? () => _reroll(shelf) : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _picks.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      SizedBox(
                        width: 92,
                        child: HorizontalReveal(
                          delay: Duration(milliseconds: 40 + i.clamp(0, 3) * 70),
                          child: ThemedPosterTile(
                            title: _picks[i].displayTitle,
                            posterUrl: _picks[i].posterUrl,
                            mediaType: _picks[i].mediaType,
                            fallbackColor: SeenlyPalette.mediaColor(_picks[i].mediaType),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TitleDetailScreen(
                                  mediaId: _picks[i].mediaId,
                                  source: _picks[i].source,
                                  mediaType: _picks[i].mediaType,
                                  seedTitle: _picks[i].displayTitle,
                                  seedPosterUrl: _picks[i].posterUrl,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _ShelfPickCta(count: shelf.length),
            ],
          ),
        );
      },
    );
  }
}

/// The "to plan to watch" jump under [_ShelfPickStrip] — a soft,
/// tinted pill rather than a solid [PrimaryButton], so it reads as a
/// quiet way back to the shelf rather than competing with the "+" log
/// button up in the header for the one loud action on the page.
/// Requests Profile's "plan to watch" tab specifically (not just the
/// tab itself) before switching, via [AppState.requestProfileTab], so
/// landing there always shows the shelf this strip was drawn from.
class _ShelfPickCta extends StatelessWidget {
  final int count;
  const _ShelfPickCta({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      child: PressScale(
        haptics: true,
        onTap: () {
          context.read<AppState>().requestProfileTab(1); // plan to watch
          RootShell.switchTab(context, RootShell.profileTab);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: SeenlyPalette.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SeenlyPalette.accent.withOpacity(0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: SeenlyPalette.accent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.bookmark, size: 12, color: SeenlyPalette.accentOnAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('to plan to watch',
                    style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.accent)),
              ),
              Text('$count', style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, size: 16, color: SeenlyPalette.accent),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _diaryMediaIcon(String mediaType) {
  switch (mediaType) {
    case 'movie':
      return Icons.movie_outlined;
    case 'series':
      return Icons.tv_outlined;
    case 'game':
      return Icons.videogame_asset_outlined;
    case 'anime':
      return Icons.auto_awesome_outlined;
    case 'book':
      return Icons.menu_book_outlined;
    case 'manga':
      return Icons.import_contacts_outlined;
    default:
      return Icons.local_movies_outlined;
  }
}

/// The poster + its little media-type badge, shared between
/// [_SeriesEntryRow] and [_DiaryRow] — bigger than the old bare 50×70
/// Image.network (64×92, closer to a real poster) with a soft shadow of
/// its own so it reads as a small object sitting on the card rather than
/// a flat thumbnail, plus the media-type badge overlapping its corner so
/// a glance down the log tells movies from series from games without
/// reading the subtitle line.
class _DiaryPoster extends StatelessWidget {
  final String? posterUrl;
  final String mediaType;
  const _DiaryPoster({required this.posterUrl, required this.mediaType});

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.mediaColor(mediaType);
    return SizedBox(
      width: 64,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: SeenlyPalette.softShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 92,
                child: posterUrl != null && posterUrl!.isNotEmpty
                    ? FadeInNetworkImage(
                        url: posterUrl!,
                        fit: BoxFit.cover,
                        placeholder: Container(color: color),
                      )
                    : Container(color: color),
              ),
            ),
          ),
          Positioned(
            bottom: -6,
            left: -6,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: SeenlyPalette.paper, width: 2),
              ),
              child: Icon(_diaryMediaIcon(mediaType), size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// A series' one diary row — the running "N episodes watched" count
/// this row's own [DiaryEntry.episodesWatched] already carries, updated
/// in place on every log rather than accumulated from a run of separate
/// rows (see models.DiaryEntry's own doc comment on the backend). Tap
/// opens the full season/episode sheet the Watched shelf uses too (see
/// showSeriesEpisodesSheet), which fetches its own up-to-date progress —
/// this card doesn't need to.
class _SeriesEntryRow extends StatelessWidget {
  final DiaryEntry entry;
  const _SeriesEntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final watched = entry.episodesWatched;
    final progressLabel = watched == null || watched == 0
        ? 'S${entry.season}${entry.episode != null ? "E${entry.episode}" : ""}'
        : '$watched episode${watched == 1 ? "" : "s"} watched · S${entry.season}'
            '${entry.episode != null ? "E${entry.episode}" : ""}';
    return PressScale(
      onTap: () => showSeriesEpisodesSheet(
        context,
        mediaId: entry.mediaId,
        source: entry.source,
        title: entry.displayTitle,
        mediaType: entry.mediaType,
        posterUrl: entry.posterUrl,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          // .start now that a rating/note preview can push this
          // column taller than the poster — .center would leave the
          // poster and chevron visibly low against a two-line note.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DiaryPoster(posterUrl: entry.posterUrl, mediaType: entry.mediaType),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.sage.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('watching · series',
                        style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.sage)),
                  ),
                  const SizedBox(height: 6),
                  Text(entry.displayTitle, style: SeenlyText.cardTitle),
                  const SizedBox(height: 4),
                  Text(
                    entry.isRewatch ? 'rewatch · $progressLabel' : progressLabel,
                    style: SeenlyText.metaLabel,
                  ),
                  // The series' one rating/review, once it's logged one
                  // — see _SeriesReviewCard for where it's actually
                  // written/edited (this sheet just opens straight to
                  // it on tap). Same "rating then a quoted note preview"
                  // order _DiaryRow uses for a movie, so a series entry
                  // reads as the same kind of card at a glance.
                  if (entry.rating != null) ...[
                    const SizedBox(height: 7),
                    HeartRating(value: entry.rating!, size: 13),
                  ],
                  if (entry.note != null && entry.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      entry.note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// A quiet little overlapping-avatar row for the "who stole the show"
/// picks from the log flow (see DiaryEntry.favoriteCast) — small
/// enough to sit under the mood tags without competing with them, but
/// still a real "these were the faces you loved that night" touch
/// rather than a bare text list. A tiny heart badge on the lead avatar
/// mirrors the same glyph the pick step and confirm card use, so it
/// reads as the same gesture rather than a new icon language.
class _FavoriteCastRow extends StatelessWidget {
  final List<CastMember> cast;
  const _FavoriteCastRow({required this.cast});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          // Just wide enough for up to 3 overlapping 20px circles —
          // each new one only adds 14px since they overlap by 6.
          width: 20 + (cast.length - 1).clamp(0, 2) * 14,
          height: 22,
          child: Stack(
            children: [
              for (int i = 0; i < cast.length; i++)
                Positioned(
                  left: i * 14.0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: SeenlyPalette.paper, width: 1.5),
                    ),
                    child: ClipOval(
                      child: (cast[i].photoUrl != null)
                          ? FadeInNetworkImage(
                              url: cast[i].photoUrl!,
                              fit: BoxFit.cover,
                              placeholder: Container(color: SeenlyPalette.accent),
                            )
                          : Container(color: SeenlyPalette.accent),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            cast.map((m) => m.name).join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
          ),
        ),
      ],
    );
  }
}

class _DiaryRow extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback? onChanged;
  const _DiaryRow({required this.entry, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () async {
        await showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry));
        onChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DiaryPoster(posterUrl: entry.posterUrl, mediaType: entry.mediaType),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: SeenlyPalette.mediaColor(entry.mediaType).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(entry.mediaType,
                            style: SeenlyText.mono(
                                size: 8.5, color: SeenlyPalette.mediaColor(entry.mediaType))),
                      ),
                      if (entry.isRewatch) ...[
                        const SizedBox(width: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.replay, size: 11, color: SeenlyPalette.inkFaint),
                            const SizedBox(width: 2),
                            Text('rewatch',
                                style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.inkFaint)),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(entry.displayTitle, style: SeenlyText.cardTitle),
                  if (entry.watchedWithUsername != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, size: 10, color: SeenlyPalette.accent),
                        const SizedBox(width: 4),
                        Text('watched with ${entry.watchedWithUsername}',
                            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.accent)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 7),
                  if (entry.rating != null) HeartRating(value: entry.rating!, size: 13),
                  if (entry.moodTags.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final tag in entry.moodTags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: SeenlyPalette.background,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(tag,
                                style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkMuted)),
                          ),
                      ],
                    ),
                  ],
                  if (entry.favoriteCast.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _FavoriteCastRow(cast: entry.favoriteCast),
                  ],
                  if (entry.note != null && entry.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      entry.note!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(
                          italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
            PressScale(
              onTap: () => showShareCardSheet(
                context,
                card: EveningShareCard(
                  entry: entry,
                  fallbackColor: SeenlyPalette.mediaColor(entry.mediaType),
                ),
                fileName: 'seenly-${entry.id}',
                shareText: 'watched "${entry.displayTitle}" — logged in seenly',
              ),
              child: Container(
                margin: const EdgeInsets.only(left: 6),
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: SeenlyPalette.background,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.ios_share, size: 13, color: SeenlyPalette.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
