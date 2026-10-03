import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/release_calendar_item.dart';
import '../../services/app_translations.dart';
import '../../services/calendar_filters_prefs_service.dart';
import '../../theme/notebook_paper.dart';
import '../../theme/palette.dart';
import '../../theme/seenly_skin.dart';
import '../../theme/text_styles.dart';
import '../../utils/release_day_groups.dart';
import '../../utils/release_genres.dart';
import '../../widgets/genre_field.dart';
import '../../widgets/interest_picker.dart' show kInterests;
import '../../widgets/mosaic_poster_grid.dart';
import '../../widgets/scroll_reveal.dart';
import '../../widgets/small_pieces.dart' show ScrollableUnderlineTabs;
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/wow_motion.dart';
import '../collections/collection_full_screen.dart' show showMediaQuickActions;
import '../title/title_detail_screen.dart';
import '../../theme/clay_kit.dart';

/// Opens a [ReleaseCalendarItem] the way any poster card in this app opens
/// a title — except for `source == "shikimori"`, which has no MediaItem /
/// detail screen behind it at all (see that field's own doc comment on
/// [ReleaseCalendarItem]) and instead opens Shikimori's own page
/// externally, with the same failure handling as
/// widgets/source_video_link.dart's openSourceVideo.
///
/// Shared by the Home strip (which passes its own scoped [heroTag]) and
/// the full-screen calendar below, so the two can't drift apart on what a
/// tap does.
Future<void> openReleaseCalendarItem(
  BuildContext context,
  ReleaseCalendarItem entry, {
  String? heroTag,
}) async {
  if (entry.source == 'shikimori') {
    final url = entry.externalUrl;
    if (url == null) return;
    try {
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("couldn't open that link just now".tr)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("couldn't open that link just now".tr)));
      }
    }
    return;
  }
  final item = entry.item;
  if (item == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TitleDetailScreen(
        mediaId: item.id,
        source: entry.source,
        mediaType: entry.mediaType,
        seedTitle: entry.title.display,
        seedPosterUrl: entry.posterUrl,
        seedItem: item,
        heroTag: heroTag,
      ),
    ),
  );
}

// Decorative short forms, routed through `.tr` — 'jan' -> 'янв' etc. are
// already in the catalog (they're the same keys the Stats/Wrapped screens
// use), so the calendar reads in whichever interface language is on.
const _monthKeys = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];
const _weekdayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

String _monthLabel(DateTime d) => _monthKeys[d.month - 1].tr.toUpperCase();
String _weekdayLabel(DateTime d) => _weekdayKeys[d.weekday - 1].tr.toUpperCase();
String _dayMonthLabel(DateTime d) => '${d.day} ${_monthLabel(d)}';

String _typeLabel(String type) {
  for (final interest in kInterests) {
    if (interest.value == type) return interest.label.tr;
  }
  return type;
}

IconData _typeIcon(String type) {
  for (final interest in kInterests) {
    if (interest.value == type) return interest.icon;
  }
  return Icons.event_outlined;
}

/// Everything on the Home release calendar, as a full screen — reached by
/// tapping "see all →" on that section's header.
///
/// Built as the sibling of [CollectionFullScreen]: the same pinned,
/// collapsing hero (a soft, blurred mosaic of the shelf's own posters that
/// dissolves into the page), the same two-column poster grid with the
/// tilt-under-your-thumb tiles and parallax posters, the same long-press
/// quick actions. What's new is the *date*: the grid is split into one
/// block per release day, each under a header that sticks to the top while
/// its block scrolls past, so the day you're looking at never leaves the
/// screen. "Today" breathes, and switching the type tab resettles the
/// whole calendar the way shuffling does on a collection.
///
/// [items] is whatever Home was showing at the moment of the tap — i.e.
/// already narrowed by the Home tune-icon type filter — so "see all" means
/// "all of *this* section", the same contract every other "all →" in the
/// app has. The tabs under the summary then narrow it further, locally.
///
/// On top of the type tabs there is a genre filter, borrowed from the
/// "can't decide?" flow: the genres offered are the ones the current tab
/// actually contains, each with a count, several can be picked, and a
/// release passes if it has any of them. Unlike the tabs the genre pick
/// is remembered on the device (and Home's strip honours it too), so
/// [items] must *not* be pre-narrowed by genre — this screen applies
/// [initialGenres] itself, which is what lets the sheet still offer every
/// genre.
class ReleaseCalendarScreen extends StatefulWidget {
  final List<ReleaseCalendarItem> items;

  /// The genre pick Home already loaded, so the first frame is already
  /// filtered instead of flashing the full list and then re-settling.
  final Set<String> initialGenres;

  const ReleaseCalendarScreen({
    super.key,
    required this.items,
    this.initialGenres = const {},
  });

  @override
  State<ReleaseCalendarScreen> createState() => _ReleaseCalendarScreenState();
}

class _ReleaseCalendarScreenState extends State<ReleaseCalendarScreen> {
  static const _typeOrder = ['movie', 'series', 'anime', 'game', 'book', 'manga'];

  // Frozen for the life of the screen: "today" shouldn't flip under
  // someone's thumb if they leave it open past midnight, and every
  // relative label below has to agree with every other.
  late final DateTime _now = DateTime.now();
  late final List<ReleaseDayGroup> _allGroups = groupReleasesByDay(widget.items);
  late final List<String> _types = [
    for (final t in _typeOrder)
      if (widget.items.any((e) => e.mediaType == t)) t,
  ];
  late final List<String> _heroPosters = _pickHeroPosters();
  late final ReleaseCalendarItem? _nextUp = _pickNextUp();

  String _type = 'all';
  // Bumped on every tab change and folded into each day block's key — a
  // brand new key is a brand new State, which replays the settle-in
  // exactly like a first appearance (same trick as the shuffle button on
  // a collection), so the filter reads as "the calendar just resettled"
  // instead of a silent swap.
  int _gen = 0;
  late List<ReleaseDayGroup> _groups;

  final _prefs = CalendarFiltersPrefsService();
  // Everything the person has picked, across tabs. Only the part that
  // exists in the current tab's pool takes effect (see
  // activeReleaseGenres), so switching to a tab without a picked genre
  // doesn't blank the screen — and coming back restores it.
  late Set<String> _genres = {...widget.initialGenres};

  @override
  void initState() {
    super.initState();
    _groups = _computeGroups();
  }

  /// The releases of the current type tab, before any genre pick.
  List<ReleaseCalendarItem> get _typePool =>
      _type == 'all' ? widget.items : widget.items.where((e) => e.mediaType == _type).toList();

  List<ReleaseDayGroup> _computeGroups() {
    final pool = _typePool;
    final active = activeReleaseGenres(pool, _genres);
    if (_type == 'all' && active.isEmpty) return _allGroups;
    return groupReleasesByDay(filterReleasesByGenres(pool, _genres));
  }

  /// Bumps [_gen] and rebuilds the day blocks — one place for both
  /// filters, so a tab change and a genre change resettle identically.
  void _refilter() {
    _gen++;
    _groups = _computeGroups();
  }

  /// Up to four poster URLs for the hero, spread evenly across everything
  /// still to come (not just the first four — those would all be the same
  /// week's releases) so the backdrop reads as "the whole calendar".
  List<String> _pickHeroPosters() {
    final upcoming = <String>[];
    void collect(bool onlyUpcoming) {
      for (final g in _allGroups) {
        if (onlyUpcoming && daysFromToday(g.day, _now) < 0) continue;
        for (final e in g.items) {
          final url = e.posterUrl;
          if (url != null && url.isNotEmpty && !upcoming.contains(url)) upcoming.add(url);
        }
      }
    }

    collect(true);
    if (upcoming.isEmpty) collect(false);
    if (upcoming.length <= 4) return upcoming;
    return [
      for (var i = 0; i < 4; i++) upcoming[(i * (upcoming.length - 1) / 3).round()],
    ];
  }

  /// The soonest release that hasn't come out yet (today counts) — the
  /// card under the summary. Prefers one with a poster on its day.
  ReleaseCalendarItem? _pickNextUp() {
    for (final g in _allGroups) {
      if (daysFromToday(g.day, _now) < 0 || g.items.isEmpty) continue;
      for (final e in g.items) {
        if (e.posterUrl != null && e.posterUrl!.isNotEmpty) return e;
      }
      return g.items.first;
    }
    return null;
  }

  void _setType(String type) {
    if (type == _type) return;
    HapticFeedback.selectionClick();
    setState(() {
      _type = type;
      _refilter();
    });
  }

  void _setGenres(Set<String> genres) {
    HapticFeedback.selectionClick();
    setState(() {
      _genres = genres;
      _refilter();
    });
    // Fire and forget, like the decide flow's prefs save.
    _prefs.saveGenres(genres);
  }

  Future<void> _openGenreSheet() async {
    final pool = _typePool;
    final counts = releaseGenreCounts(pool);
    final available = counts.keys.toList()..sort();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SeenlyPalette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final active = activeReleaseGenres(pool, _genres);
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.62,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    Text('genres'.tr,
                        style: SeenlyText.serif(size: 19, weight: FontWeight.w700, color: SeenlyPalette.ink)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: available.isEmpty
                          ? Center(
                              child: Text(
                                'no genres logged for this pool yet'.tr,
                                style: SeenlyText.serif(
                                    italic: true, size: 13, color: SeenlyPalette.placeholder),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: ScatteredGenreField(
                                genres: available,
                                counts: counts,
                                selected: active,
                                onToggle: (genre) {
                                  final next = {..._genres};
                                  if (!next.remove(genre)) next.add(genre);
                                  _setGenres(next);
                                  setSheet(() {});
                                },
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (active.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () {
                                _setGenres({});
                                setSheet(() {});
                              },
                              child: Text(
                                'clear'.tr,
                                style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent).copyWith(
                                  decoration: TextDecoration.underline,
                                  decorationColor: SeenlyPalette.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 22),
                          ],
                          GestureDetector(
                            onTap: () => Navigator.of(sheetContext).pop(),
                            child: Text(
                              'done'.tr,
                              style: SeenlyText.mono(
                                  size: 11, weight: FontWeight.w700, color: SeenlyPalette.accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  int get _visibleCount => _groups.fold<int>(0, (sum, g) => sum + g.items.length);

  @override
  Widget build(BuildContext context) {
    const expandedHeight = 300.0;
    final nextUp = _nextUp;
    final count = _visibleCount;

    // The hero backdrop is a dark image + dark scrim, so it needs light
    // (white) status-bar icons — same reasoning as CollectionFullScreen.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: SeenlyPalette.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              backgroundColor: SeenlyPalette.background,
              surfaceTintColor: Colors.transparent,
              expandedHeight: expandedHeight,
              automaticallyImplyLeading: false,
              leadingWidth: 56,
              leading: Padding(
                padding: const EdgeInsets.only(left: 14, top: 6),
                child: PressScale(
                  haptics: true,
                  onTap: () => Navigator.of(context).pop(),
                  child: WobblyCircle(
                    size: 34,
                    color: SeenlyPalette.paper.withOpacity(0.88),
                    boxShadow: SeenlyPalette.softShadow,
                    child: Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                  ),
                ),
              ),
              centerTitle: true,
              flexibleSpace: FlexibleSpaceBar(
                // See CollectionFullScreen for why all three of these are
                // needed to get the hero title truly centered and shrunk
                // to fit rather than ellipsized.
                centerTitle: true,
                expandedTitleScale: 1.0,
                titlePadding: const EdgeInsets.fromLTRB(60, 0, 60, 14),
                title: Builder(
                  builder: (context) {
                    // White over the dark backdrop while expanded, ink
                    // over the light bar once collapsed.
                    final settings = context
                        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
                    double collapseProgress = 0;
                    if (settings != null && settings.maxExtent > settings.minExtent) {
                      collapseProgress = ((settings.maxExtent - settings.currentExtent) /
                              (settings.maxExtent - settings.minExtent))
                          .clamp(0.0, 1.0);
                    }
                    final titleColor =
                        Color.lerp(SeenlyPalette.paper, SeenlyPalette.ink, collapseProgress)!;
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        'release calendar'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: SeenlyText.serif(
                            size: 19, weight: FontWeight.w700, color: titleColor),
                      ),
                    );
                  },
                ),
                background: _CalendarHeroBackdrop(posterUrls: _heroPosters),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
              sliver: SliverToBoxAdapter(
                child: BannerReveal(
                  from: -12,
                  duration: const Duration(milliseconds: 420),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            // Keyed on the count so a tab change re-tallies
                            // from zero — CountUpNumber only ever reads
                            // its value once, on first build.
                            CountUpNumber(
                              key: ValueKey('count-$count'),
                              value: count.toDouble(),
                              decimals: 0,
                              style: SeenlyText.metaLabel,
                            ),
                            const SizedBox(width: 5),
                            Text(nOnly('nReleases', count), style: SeenlyText.metaLabel),
                          ],
                        ),
                      ),
                      if (_groups.isNotEmpty)
                        Text(
                          _groups.length == 1
                              ? _dayMonthLabel(_groups.first.day)
                              : '${_dayMonthLabel(_groups.first.day)} – ${_dayMonthLabel(_groups.last.day)}',
                          style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (nextUp != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                sliver: SliverToBoxAdapter(
                  child: Entrance(
                    delay: const Duration(milliseconds: 120),
                    child: _NextUpCard(
                      entry: nextUp,
                      daysAway: daysFromToday(nextUp.releaseDay!, _now),
                    ),
                  ),
                ),
              ),
            if (_types.length > 1)
              SliverToBoxAdapter(
                child: Entrance(
                  delay: const Duration(milliseconds: 200),
                  riseBy: 14,
                  child: ScrollableUnderlineTabs(
                    labels: ['all'.tr, for (final t in _types) _typeLabel(t)],
                    activeIndex: _type == 'all' ? 0 : _types.indexOf(_type) + 1,
                    onChanged: (i) => _setType(i == 0 ? 'all' : _types[i - 1]),
                  ),
                ),
              ),
            if (_typePool.any((e) => e.allGenres.isNotEmpty))
              SliverToBoxAdapter(
                child: Entrance(
                  delay: const Duration(milliseconds: 240),
                  riseBy: 10,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
                    child: _GenreFilterBar(
                      activeCount: activeReleaseGenres(_typePool, _genres).length,
                      onOpen: _openGenreSheet,
                      onClear: () => _setGenres({}),
                    ),
                  ),
                ),
              ),
            if (_groups.isEmpty)
              SliverToBoxAdapter(
                child: Entrance(
                  delay: const Duration(milliseconds: 160),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 40, 22, 40),
                    child: Center(
                      child: Text('no matches'.tr, style: SeenlyText.emptyState()),
                    ),
                  ),
                ),
              )
            else
              for (var g = 0; g < _groups.length; g++) _daySliver(g, _groups[g]),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }

  /// One release day: a sticky header, then that day's posters.
  ///
  /// [SliverMainAxisGroup] is what makes the header stick only for as long
  /// as its own day is on screen — the next day's header then pushes it
  /// off, the way a contacts list's letter headers do. The grid is a real
  /// (lazy) [SliverGrid], so a calendar with a hundred releases still only
  /// builds — and only starts fetching posters for — the tiles near the
  /// viewport.
  Widget _daySliver(int index, ReleaseDayGroup group) {
    return SliverMainAxisGroup(
      key: ValueKey('day-${group.key}-$_gen'),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _DayHeaderDelegate(
            group: group,
            daysAway: daysFromToday(group.day, _now),
            today: _now,
            index: index,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 2 / 3,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _ReleaseTile(entry: group.items[i], indexInDay: i),
              childCount: group.items.length,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Genre filter
// ---------------------------------------------------------------------

/// The one-line entry point to the genre sheet: a "genres" pill that reads
/// "2 genres" once something is picked, and a "clear" link beside it.
class _GenreFilterBar extends StatelessWidget {
  final int activeCount;
  final VoidCallback onOpen;
  final VoidCallback onClear;
  const _GenreFilterBar({
    required this.activeCount,
    required this.onOpen,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final on = activeCount > 0;
    return Row(
      children: [
        PressScale(
          haptics: true,
          onTap: onOpen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: on ? SeenlyPalette.accent : SeenlyPalette.paper,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? SeenlyPalette.accent : SeenlyPalette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune,
                    size: 13, color: on ? SeenlyPalette.accentOnAccent : SeenlyPalette.ink),
                const SizedBox(width: 6),
                Text(
                  on ? nCount('nGenres', activeCount) : 'genres'.tr,
                  style: SeenlyText.mono(
                    size: 11,
                    weight: FontWeight.w600,
                    color: on ? SeenlyPalette.accentOnAccent : SeenlyPalette.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (on) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onClear,
            child: Text(
              'clear'.tr,
              style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.accent).copyWith(
                decoration: TextDecoration.underline,
                decorationColor: SeenlyPalette.accent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------

/// The pinned header's backdrop — the same soft, gently blurred, washed
/// dark and dissolved-into-the-page mosaic as a collection's, built from
/// posters picked across the whole calendar. On top of that it's *alive*:
/// it settles in from slightly zoomed on arrival, then drifts very slowly
/// side to side for as long as the screen is open (see [_SlowDrift]).
class _CalendarHeroBackdrop extends StatelessWidget {
  final List<String> posterUrls;
  const _CalendarHeroBackdrop({required this.posterUrls});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (posterUrls.isEmpty)
          Container(color: SeenlyPalette.gridColorFor(3))
        else
          // Clip: the zoom/drift below deliberately overshoots the box, and
          // the overshoot must not bleed onto the content underneath.
          ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion ? 1.0 : 1.16, end: 1.0),
              duration: const Duration(milliseconds: 1300),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: _SlowDrift(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1, tileMode: TileMode.clamp),
                  // Fixed, precomputed column widths (last column absorbs the
                  // leftover pixel) rather than Row + Expanded — see
                  // CollectionFullScreen's own backdrop for the seam this
                  // avoids, and why the Row has to stretch vertically.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const segments = 4;
                      final columnWidth = (constraints.maxWidth / segments).floorToDouble();
                      final lastColumnWidth = constraints.maxWidth - columnWidth * (segments - 1);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < segments; i++)
                            SizedBox(
                              width: i == segments - 1 ? lastColumnWidth : columnWidth,
                              child: i < posterUrls.length
                                  ? FadeInNetworkImage(
                                      url: posterUrls[i],
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      placeholder: Container(color: SeenlyPalette.gridColorFor(i)),
                                    )
                                  : Container(color: SeenlyPalette.gridColorFor(i)),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        Container(color: Colors.black.withOpacity(0.18)),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                SeenlyPalette.background,
              ],
              stops: const [0.0, 0.82, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// A very slow, very small side-to-side drift with a hair of zoom — the
/// backdrop equivalent of [Breathe]: meant to sit at the edge of noticing
/// (a full sweep takes ~26 s and moves a few px), never a motion the eye
/// tracks. Off entirely under "reduce motion", where it just holds still.
class _SlowDrift extends StatefulWidget {
  final Widget child;
  const _SlowDrift({required this.child});

  @override
  State<_SlowDrift> createState() => _SlowDriftState();
}

class _SlowDriftState extends State<_SlowDrift> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 26));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeInOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset((_t.value - 0.5) * 22, 0),
        child: Transform.scale(scale: 1.08, child: child),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Next up
// ---------------------------------------------------------------------

/// The soonest release that hasn't come out yet — a reason to tap before
/// scrolling anywhere. Same tap as the tile it duplicates.
class _NextUpCard extends StatelessWidget {
  final ReleaseCalendarItem entry;
  final int daysAway;
  const _NextUpCard({required this.entry, required this.daysAway});

  @override
  Widget build(BuildContext context) {
    final day = entry.releaseDay;
    final color = SeenlyPalette.mediaColor(entry.mediaType);
    final url = entry.posterUrl;
    final when = daysAway == 0
        ? 'today'.tr
        : (daysAway == 1 ? 'tomorrow'.tr : (day != null ? _dayMonthLabel(day) : ''));
    final ep = entry.episode;

    return PressScale(
      scaleTo: 0.98,
      onTap: () => openReleaseCalendarItem(context, entry),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SeenlyPalette.border),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 52,
                height: 76,
                child: url != null && url.isNotEmpty
                    ? FadeInNetworkImage(
                        url: url,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        placeholder: Container(color: color),
                      )
                    : Container(color: color),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 12, color: SeenlyPalette.accent),
                      const SizedBox(width: 5),
                      Text(
                        'next up'.tr.toUpperCase(),
                        style: SeenlyText.mono(
                            size: 10, weight: FontWeight.w700, color: SeenlyPalette.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.title.display,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: 15, weight: FontWeight.w600, color: SeenlyPalette.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    ep != null ? '$when · E$ep' : when,
                    style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 22, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Day header (sticky)
// ---------------------------------------------------------------------

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  final ReleaseDayGroup group;
  final int daysAway;
  final DateTime today;
  final int index;

  const _DayHeaderDelegate({
    required this.group,
    required this.daysAway,
    required this.today,
    required this.index,
  });

  static const double extent = 62;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _DayHeader(
      group: group,
      daysAway: daysAway,
      today: today,
      index: index,
      stuck: overlapsContent,
    );
  }

  @override
  bool shouldRebuild(covariant _DayHeaderDelegate oldDelegate) =>
      oldDelegate.group != group ||
      oldDelegate.daysAway != daysAway ||
      oldDelegate.index != index;
}

/// "25 · SEP · FRI", with a pill for today / tomorrow / already out and
/// the number of releases that day. While the block scrolls under it the
/// bar picks up a hairline and a soft shadow and the day number tucks down
/// a size — a state change, animated, rather than a hard cut. It also
/// eases in from the side as it first arrives, tied to the scroll offset
/// (not a timer) via [ScrollRevealEntrance], so it never fights the
/// pinning: once stuck at the top it is simply fully arrived.
class _DayHeader extends StatelessWidget {
  final ReleaseDayGroup group;
  final int daysAway;
  final DateTime today;
  final int index;
  final bool stuck;

  const _DayHeader({
    required this.group,
    required this.daysAway,
    required this.today,
    required this.index,
    required this.stuck,
  });

  @override
  Widget build(BuildContext context) {
    final day = group.day;
    final isToday = daysAway == 0;
    final month = day.year != today.year ? '${_monthLabel(day)} ${day.year}' : _monthLabel(day);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: _DayHeaderDelegate.extent,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: SeenlyPalette.background,
        border: Border(
          bottom: BorderSide(color: stuck ? SeenlyPalette.border : Colors.transparent),
        ),
        boxShadow: stuck
            ? [
                BoxShadow(
                  color: SeenlyPalette.shadowColor.withOpacity(0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : const [],
      ),
      child: ScrollRevealEntrance(
        index: index,
        driftDistance: 14,
        child: Row(
          children: [
            AnimatedScale(
              scale: stuck ? 0.86 : 1.0,
              alignment: Alignment.centerLeft,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Text(
                '${day.day}',
                style: SeenlyText.serif(
                  size: 28,
                  weight: FontWeight.w700,
                  color: isToday ? SeenlyPalette.accent : SeenlyPalette.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  month,
                  style: SeenlyText.mono(
                      size: 10, weight: FontWeight.w700, color: SeenlyPalette.accent),
                ),
                Text(
                  _weekdayLabel(day),
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                ),
              ],
            ),
            const Spacer(),
            _DayPill(daysAway: daysAway),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeenlyPalette.paper,
                border: Border.all(color: SeenlyPalette.border),
              ),
              child: Text(
                '${group.items.length}',
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.ink, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today (filled, breathing), tomorrow (outlined), or already out (muted,
/// with a check) — nothing at all for a day further away, where the date
/// itself is the whole message.
class _DayPill extends StatelessWidget {
  final int daysAway;
  const _DayPill({required this.daysAway});

  @override
  Widget build(BuildContext context) {
    if (daysAway == 0) {
      return BreathingGlow(
        color: SeenlyPalette.accent,
        size: 78,
        maxOpacity: 0.3,
        child: _pill('today'.tr, filled: true),
      );
    }
    if (daysAway == 1) return _pill('tomorrow'.tr, filled: false);
    if (daysAway < 0) {
      return _pill('just out'.tr, filled: false, icon: Icons.check_rounded, muted: true);
    }
    return const SizedBox.shrink();
  }

  Widget _pill(String label, {required bool filled, IconData? icon, bool muted = false}) {
    final fg = filled
        ? SeenlyPalette.accentOnAccent
        : (muted ? SeenlyPalette.inkFaint : SeenlyPalette.accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? SeenlyPalette.accent : SeenlyPalette.accent.withOpacity(muted ? 0.0 : 0.12),
        border: muted ? Border.all(color: SeenlyPalette.border) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          Text(label, style: SeenlyText.mono(size: 10, weight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Tiles
// ---------------------------------------------------------------------

/// One release: the same tilt-under-the-finger, parallax-poster tile a
/// collection's grid uses, dressed in whichever poster theme is chosen in
/// Settings. Tap opens the title (or Shikimori, for anime with no in-app
/// page); long-press opens the quick actions where there's a title to act
/// on.
class _ReleaseTile extends StatelessWidget {
  final ReleaseCalendarItem entry;
  final int indexInDay;
  const _ReleaseTile({required this.entry, required this.indexInDay});

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    return ScrollReveal(
      // Two tiles per row — the second trails the first by a beat, then
      // rows fall to zero again, so only tiles arriving together stagger.
      delay: Duration(milliseconds: 45 * (indexInDay % 2)),
      child: TiltPosterTile(
        onTap: () => openReleaseCalendarItem(context, entry),
        onLongPress: item == null ? null : () => showMediaQuickActions(context, item),
        child: MosaicParallaxPoster(
          builder: (parallax) => ThemedPosterTile(
            title: entry.title.display,
            posterUrl: entry.posterUrl,
            mediaType: entry.mediaType,
            fallbackColor: SeenlyPalette.mediaColor(entry.mediaType),
            parallax: parallax,
            badge: _ReleaseBadge(entry: entry),
            // Tap/navigation lives on the TiltPosterTile above, same as in
            // a collection's grid — a second recognizer here would fight
            // it for the same tap.
          ),
        ),
      ),
    );
  }
}

/// A small corner mark on the poster: the type icon, or — for an anime
/// episode row — "E5", since the episode number is the actual news there.
/// Mirrors the collection grid's rank badge (a stamp on the Cozy skin, a
/// dimmed dot/pill everywhere else).
class _ReleaseBadge extends StatelessWidget {
  final ReleaseCalendarItem entry;
  const _ReleaseBadge({required this.entry});

  @override
  Widget build(BuildContext context) {
    final episode = entry.episode;
    final cozy = SeenlySkin.isCozy;
    final fg = cozy ? SeenlyPalette.ink : SeenlyPalette.paper;
    final Widget content = episode != null
        ? Text('E$episode', style: SeenlyText.mono(size: 9.5, weight: FontWeight.w700, color: fg))
        : Icon(_typeIcon(entry.mediaType), size: 11, color: fg);

    if (cozy) {
      return StampBadge(
        color: SeenlyPalette.ink,
        child: SizedBox(
          height: 20,
          width: episode != null ? null : 20,
          child: Center(child: content),
        ),
      );
    }
    return Container(
      height: 20,
      constraints: const BoxConstraints(minWidth: 20),
      padding: EdgeInsets.symmetric(horizontal: episode != null ? 6 : 0),
      decoration: BoxDecoration(
        color: SeenlyPalette.ink.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: content,
    );
  }
}
