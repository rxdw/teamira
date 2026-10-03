import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../theme/notebook_paper.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/poster_tile.dart';
import '../scan/ticket_scan_screen.dart';
import '../title/title_detail_screen.dart';
import '../home/ask_teamira_results_screen.dart';
import '../decide/decide_ask_teamira_screen.dart';
import '../decide/decide_filters_screen.dart' show DecideFilters, kDecidePickableTypes;
import '../../widgets/wow_motion.dart' show ShimmerBlock, PressScale, Entrance;
import '../../widgets/scroll_reveal.dart';
import '../../services/app_translations.dart';
import '../../widgets/saved_celebration.dart';
import '../../widgets/decide_motion.dart' show BouncingDots;
import '../../widgets/soft_motion.dart';
import '../../theme/clay_kit.dart';
import '../../theme/seenly_skin.dart';

class SearchScreen extends StatefulWidget {
  // Prefilled and auto-searched on open — used by the ticket-scan flow
  // (see screens/scan/ticket_scan_screen.dart) to hand off its best
  // guess at a title without duplicating this screen's own search,
  // filter, and "add to plan to watch" logic.
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  // The last raw, unfiltered response from the backend for the current
  // query — kept separately from `_results` so switching `_filter` is a
  // pure in-memory re-filter, never a new network round trip. Before this
  // split, tapping a filter tab called _search() again with the exact same
  // query text, which meant every tab tap was a fresh search request for
  // data we'd already just fetched — needless load against TMDB's own
  // rate limit for zero new information.
  List<MediaItem> _allResults = [];
  List<MediaItem> _results = [];
  bool _loading = false;
  String _filter = 'all'; // all | movie | series | anime | game | book | manga

  // Same set, same order, same (value, label) shape as Collections'
  // _filters — this screen's tabs are meant to look and behave like that
  // one, not like its own thing.
  static const _filters = [
    ('all', 'all'),
    ('movie', 'movies'),
    ('series', 'series'),
    ('anime', 'anime'),
    ('game', 'games'),
    ('book', 'books'),
    ('manga', 'manga'),
  ];

  // "source:mediaId" -> "watched" | "watching" | "watch_later" — lets the
  // list show what's already on a shelf and turn the quick-add button into
  // a plain indicator instead of letting you queue the same title twice.
  Map<String, String> _statusByKey = {};

  // Titles whose "queue it" tap is still on its way to the server — their
  // button shows waiting dots instead of looking like nothing happened.
  final Set<String> _addingKeys = {};

  @override
  void initState() {
    super.initState();
    _preloadStatuses();
    final initial = widget.initialQuery?.trim();
    if (initial != null && initial.isNotEmpty) {
      _controller.text = initial;
      _search(initial);
    }
  }

  Future<void> _preloadStatuses() async {
    try {
      final collections = await context.read<AppState>().profile.collections();
      final statuses = <String, String>{};
      for (final e in collections.watchLater) {
        statuses['${e.source}:${e.mediaId}'] = 'watch_later';
      }
      for (final e in collections.watching) {
        statuses['${e.source}:${e.mediaId}'] = 'watching';
      }
      for (final e in collections.watched) {
        statuses['${e.source}:${e.mediaId}'] = 'watched'; // watched wins if both
      }
      if (mounted) setState(() => _statusByKey = statuses);
    } catch (_) {
      // Non-critical — the "already ..." hints just won't show.
    }
  }

  /// One-tap "watch later" add, no form — matches `/feed/react` with
  /// action "like", which the backend maps straight to watch_later status.
  Future<void> _addToWatchLater(MediaItem item) async {
    final key = '${item.source}:${item.id}';
    if (_addingKeys.contains(key)) return;
    setState(() => _addingKeys.add(key));
    try {
      await context.read<AppState>().feed.react(item, 'like');
      if (!mounted) return;
      setState(() {
        _addingKeys.remove(key);
        _statusByKey = {..._statusByKey, key: 'watch_later'};
      });
      showSavedCelebration(
        context,
        kind: SavedKind.planned,
        title: item.title.display,
        posterUrl: item.posterUrl,
        mediaType: item.mediaType,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingKeys.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('couldn\'t add that just now — try again'.tr)),
      );
    }
  }

  /// Straight to results with a specific mood/query — used by both the
  /// example chips (a preset mood) and the "no matches" case (the exact
  /// text someone already typed here).
  void _askTeamira(String query) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AskTeamiraResultsScreen(query: query)),
    );
  }

  /// The full compose screen (same one Decide's flow uses) for when none
  /// of the example moods fit and someone wants to write their own.
  void _openTeamiraCompose() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DecideAskTeamiraScreen(
          filters: DecideFilters(types: kDecidePickableTypes, genres: {}, decade: null),
        ),
      ),
    );
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _allResults = [];
        _results = [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await context.read<AppState>().media.search(query.trim());
      if (!mounted) return;
      setState(() {
        _allResults = results;
        _results = _applyFilter(results);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MediaItem> _applyFilter(List<MediaItem> results) {
    return _filter == 'all'
        ? results
        : results.where((r) => r.mediaType == _filter).toList();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
              child: Row(
                children: [
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: WobblyCircle(
                      size: 32,
                      color: SeenlyPalette.paper,
                      child: Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // The bar warms up while you're typing in it: an accent
                    // outline fades in and a soft glow lifts it off the page.
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      child: Builder(
                        builder: (context) {
                          final focused = Focus.of(context).hasFocus;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: SeenlySkin.isClay ? clayWellDecoration(focused: focused) : BoxDecoration(
                              color: SeenlyPalette.paper,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: focused ? SeenlyPalette.accent.withOpacity(0.5) : Colors.transparent,
                                width: 1.2,
                              ),
                              boxShadow: focused
                                  ? [
                                      BoxShadow(
                                        color: SeenlyPalette.accent.withOpacity(0.14),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : const [],
                            ),
                            child: TextField(
                        controller: _controller,
                        autofocus: widget.initialQuery == null || widget.initialQuery!.trim().isEmpty,
                        onChanged: _onQueryChanged,
                        style: SeenlyText.serif(italic: true, size: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'search a film, show, or game'.tr,
                          hintStyle: SeenlyText.serif(
                              italic: true, size: 14, color: SeenlyPalette.placeholder),
                          prefixIcon: Icon(Icons.search,
                              size: 16, color: SeenlyPalette.inkFaint),
                        ),
                      ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PressScale(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TicketScanScreen()),
                    ),
                    haptics: true,
                    child: WobblyCircle(
                      size: 32,
                      color: SeenlyPalette.paper,
                      child: Icon(Icons.confirmation_number_outlined,
                          size: 15, color: SeenlyPalette.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
            ScrollableUnderlineTabs(
              labels: [for (final f in _filters) f.$2.tr],
              activeIndex: _filters.indexWhere((f) => f.$1 == _filter),
              onChanged: (i) {
                setState(() {
                  _filter = _filters[i].$1;
                  _results = _applyFilter(_allResults);
                });
              },
            ),
            // A hairline that slides along while a search is in flight —
            // the quiet "still looking" cue that doesn't cover anything.
            _SearchLine(active: _loading),
            // Sits right under the tabs, not buried down in empty space —
            // the first thing anyone sees once literal results aren't
            // (yet) on screen. Hidden the moment real results come back,
            // and while a search is still in flight, so it never competes
            // with either.
            if (!_loading && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                child: Entrance(
                  child: _AskTeamiraInvite(
                    query: _controller.text.trim().isEmpty ? null : _controller.text.trim(),
                    onPickMood: _askTeamira,
                    onWriteOwn: _openTeamiraCompose,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                // First search (nothing on screen yet): poster-shaped
                // skeletons in the shape of the rows about to arrive.
                // Searching again with results already showing: they
                // stay, dimmed, until the new ones replace them — no
                // blank flash on every keystroke.
                child: _loading && _results.isEmpty
                    ? const _SearchSkeleton(key: ValueKey('loading'))
                    : _results.isEmpty
                        ? Center(
                            key: const ValueKey('empty'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: SoftSwap(
                                alignment: Alignment.center,
                                child: Text(
                                  _controller.text.trim().isEmpty
                                      ? 'or start typing to look through tanè\'s catalog'.tr
                                      : 'nothing turned up for that in the catalog itself'.tr,
                                  key: ValueKey<bool>(_controller.text.trim().isEmpty),
                                  textAlign: TextAlign.center,
                                  style: SeenlyText.emptyState(),
                                ),
                              ),
                            ),
                          )
                        : AnimatedOpacity(
                            key: const ValueKey('results'),
                            duration: const Duration(milliseconds: 220),
                            opacity: _loading ? 0.45 : 1.0,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                              itemCount: _results.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final item = _results[i];
                                final key = '${item.source}:${item.id}';
                                final row = _ResultRow(
                                  item: item,
                                  status: _statusByKey[key],
                                  adding: _addingKeys.contains(key),
                                  onAddToWatchLater: () => _addToWatchLater(item),
                                );
                                // The first screenful settles in one row
                                // after another (keyed by the title, so a
                                // filter tab that keeps a row doesn't
                                // replay it); further down, rows come in
                                // as the scroll reaches them.
                                return i < 8
                                    ? Entrance(
                                        key: ValueKey<String>('found:$key'),
                                        delay: Duration(milliseconds: 45 * i),
                                        duration: const Duration(milliseconds: 420),
                                        riseBy: 14,
                                        child: row,
                                      )
                                    : ScrollRevealEntrance(
                                        key: ValueKey<String>('found:$key'),
                                        index: i,
                                        child: row,
                                      );
                              },
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lives right under the filter tabs — the first thing on the search
/// screen once there's nothing (yet) to show from the literal catalog
/// search. More than a single tap target: a small shimmering sparkle
/// badge (the same motif [DecideAskTeamiraScreen]'s hero uses, just
/// pocket-sized) plus a horizontally scrollable row of ready-made mood
/// prompts, so there's something to tap immediately instead of a lone
/// button that only makes sense once you already know what you want.
///
/// With nothing typed in the search bar, the chips are a shuffled sample
/// of generic moods. Once there's a query the catalog search came up
/// empty on, that exact query becomes the first, highlighted chip —
/// tapping it skips straight to teamira's results — with a couple of
/// generic moods after it as a fallback in case it wasn't really a
/// literal title in the first place. A trailing "write your own" chip
/// always opens the full compose screen (the same one Decide's flow
/// uses) for anything none of the presets capture.
class _AskTeamiraInvite extends StatefulWidget {
  final String? query;
  final ValueChanged<String> onPickMood;
  final VoidCallback onWriteOwn;

  const _AskTeamiraInvite({
    required this.query,
    required this.onPickMood,
    required this.onWriteOwn,
  });

  @override
  State<_AskTeamiraInvite> createState() => _AskTeamiraInviteState();
}

class _AskTeamiraInviteState extends State<_AskTeamiraInvite> {
  // A bigger pool than shown at once, shuffled once per screen visit —
  // same idea as Home's own Ask Teamira card — so the row doesn't show
  // the same three moods every single time this screen opens.
  static const _moodPool = [
    'a movie like Interstellar',
    'cozy comedy series',
    'something that\'ll make me cry',
    'rainy day, no thinking required',
    'a twisty whodunit',
    'just spooky enough',
    'mindless popcorn action',
    'high-fantasy, big world',
    'slow-burn slice of life',
    'a nostalgic 90s pick',
  ];

  late final List<String> _shuffledMoods;

  @override
  void initState() {
    super.initState();
    _shuffledMoods = [..._moodPool]..shuffle();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.query;
    final hasQuery = query != null && query.isNotEmpty;
    final moods = _shuffledMoods.take(hasQuery ? 2 : 4).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: ClayBoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SeenlyPalette.paper,
            Color.alphaBlend(SeenlyPalette.periwinkle.withOpacity(0.07), SeenlyPalette.paper),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.border),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: ShimmerBlock(
                        width: 26,
                        height: 26,
                        borderRadius: BorderRadius.circular(13),
                        baseColor: Color.alphaBlend(
                            SeenlyPalette.periwinkle.withOpacity(0.30), SeenlyPalette.paper),
                        highlightColor: SeenlyPalette.paper,
                      ),
                    ),
                    Icon(Icons.auto_awesome_outlined, size: 13, color: SeenlyPalette.periwinkle),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasQuery
                      ? '${'nothing matched'.tr} "$query" — ${'try tanè'.tr}'
                      : 'not sure what to search for?'.tr,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: moods.length + (hasQuery ? 1 : 0) + 1, // + the query chip, + "write your own"
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (hasQuery && i == 0) {
                  return _MoodChip(
                    label: '"$query"',
                    highlighted: true,
                    onTap: () => widget.onPickMood(query),
                  );
                }
                final moodIndex = i - (hasQuery ? 1 : 0);
                if (moodIndex < moods.length) {
                  final mood = moods[moodIndex];
                  return _MoodChip(label: mood.tr, onTap: () => widget.onPickMood(mood));
                }
                return _MoodChip(
                  label: 'write your own…'.tr,
                  outlined: true,
                  onTap: widget.onWriteOwn,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable pill in [_AskTeamiraInvite]'s horizontal row. Three looks
/// sharing one shape: a plain mood suggestion (neutral paper fill), the
/// literal query someone already typed (filled periwinkle — visually the
/// "main" option when it's there), and the trailing "write your own"
/// escape hatch (dashed-feeling outline only, no fill, so it doesn't
/// compete with the actual suggestions for attention).
class _MoodChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  final bool outlined;
  const _MoodChip({
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlighted ? SeenlyPalette.periwinkle.withOpacity(0.16) : SeenlyPalette.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted ? SeenlyPalette.periwinkle : SeenlyPalette.border,
            width: highlighted ? 1.3 : 1,
          ),
        ),
        child: Text(
          label,
          style: SeenlyText.mono(
            size: 11.5,
            color: highlighted ? SeenlyPalette.periwinkle : SeenlyPalette.inkMuted,
            weight: highlighted ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final MediaItem item;
  final String? status; // null | "watched" | "watch_later"
  final bool adding;
  final VoidCallback onAddToWatchLater;

  const _ResultRow({
    required this.item,
    required this.status,
    required this.adding,
    required this.onAddToWatchLater,
  });

  @override
  Widget build(BuildContext context) {
    final alreadyOnAShelf = status != null;
    return ClipPath(
      clipper: const _SoftSideNotchClipper(),
      // Queuing a title draws the accent outline in around the row (it
      // fades from nothing rather than appearing), in step with the
      // bookmark below.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: alreadyOnAShelf ? SeenlyPalette.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
            child: PressScale(
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
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    height: 81,
                    child: PosterTile(
                      title: item.title.display,
                      posterUrl: item.posterUrl,
                      fallbackColor: SeenlyPalette.mediaColor(item.mediaType),
                      showLabel: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title.display, style: SeenlyText.cardTitle),
                        const SizedBox(height: 4),
                        Text('${mediaTypeLabel(item.mediaType)} · ${item.year ?? '—'}',
                            style: SeenlyText.metaLabel),
                        // The "already …" line slides in under the meta line
                        // (and the row makes room for it) when a title gets
                        // queued, instead of appearing all at once.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topLeft,
                          child: SoftSwap(
                            alignment: Alignment.topLeft,
                            rise: 0.4,
                            child: status == null
                                ? const SizedBox(key: ValueKey<String>('none'), width: double.infinity)
                                : Padding(
                                    key: ValueKey<String>(status!),
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      switch (status) {
                                        'watched' => 'already in your diary'.tr,
                                        'watching' => 'already watching'.tr,
                                        _ => 'already queued to watch'.tr,
                                      },
                                      style: SeenlyText.mono(size: 9, color: SeenlyPalette.accent),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _AddButton(status: status, adding: adding, onTap: onAddToWatchLater),
        ],
        ),
      ),
    );
  }
}

/// Rounded rect with one soft, shallow notch cut into the middle of each
/// side edge — a faint "ticket stub" pinch on the whole search row, instead
/// of on the poster itself. Kept small and gentle so it reads as a subtle
/// texture rather than a sprocket-hole gimmick.
class _SoftSideNotchClipper extends CustomClipper<Path> {
  final double cornerRadius;
  final double notchRadius;
  const _SoftSideNotchClipper({this.cornerRadius = 10, this.notchRadius = 5});

  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cornerRadius)));
    final fy = size.height / 2;
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, fy), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(size.width, fy), radius: notchRadius));
    return Path.combine(PathOperation.difference, path, notches);
  }

  @override
  bool shouldReclip(covariant _SoftSideNotchClipper oldClipper) =>
      oldClipper.cornerRadius != cornerRadius || oldClipper.notchRadius != notchRadius;
}

/// Bookmark-style quick action: outline "+" when the title isn't on any
/// shelf yet (tap -> watch later, no form); waiting dots while that's on its
/// way; then a filled, non-tappable bookmark once it's queued — which drops
/// in with a little overshoot and a ring that spreads and fades, so the tap
/// visibly *lands*; a play icon once it's mid-series ("watching"); a small
/// check once it's already fully watched.
class _AddButton extends StatelessWidget {
  final String? status;
  final bool adding;
  final VoidCallback onTap;
  const _AddButton({required this.status, required this.adding, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget icon;
    if (status == 'watched') {
      icon = _Landed(key: const ValueKey('watched'), icon: Icons.check_circle);
    } else if (status == 'watching') {
      icon = _Landed(key: const ValueKey('watching'), icon: Icons.play_circle_fill);
    } else if (status == 'watch_later') {
      icon = _Landed(key: const ValueKey('watch_later'), icon: Icons.bookmark);
    } else if (adding) {
      icon = Container(
        key: const ValueKey('adding'),
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const BouncingDots(),
      );
    } else {
      icon = PressScale(
        key: const ValueKey('add'),
        onTap: onTap,
        haptics: true,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: SeenlyPalette.background,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.bookmark_add_outlined, size: 14, color: SeenlyPalette.accent),
        ),
      );
    }
    return SizedBox(
      width: 30,
      height: 30,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
        child: icon,
      ),
    );
  }
}

/// A shelf indicator arriving: drops in from a bit larger with an
/// overshoot, and a ring spreads out from it once.
class _Landed extends StatefulWidget {
  final IconData icon;
  const _Landed({super.key, required this.icon});

  @override
  State<_Landed> createState() => _LandedState();
}

class _LandedState extends State<_Landed> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = Icon(widget.icon, size: 20, color: SeenlyPalette.accent);
    if (MediaQuery.of(context).disableAnimations) return still;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final drop = Curves.easeOutBack.transform((t / 0.55).clamp(0.0, 1.0).toDouble());
        final ring = Curves.easeOutCubic.transform(((t - 0.1) / 0.9).clamp(0.0, 1.0).toDouble());
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (t > 0.1 && t < 1)
              Container(
                width: 14 + 26 * ring,
                height: 14 + 26 * ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SeenlyPalette.accent.withOpacity(0.45 * (1 - ring)),
                    width: 1.6 * (1 - ring) + 0.4,
                  ),
                ),
              ),
            Transform.scale(scale: 1.7 - 0.7 * drop, child: Opacity(opacity: drop.clamp(0.0, 1.0).toDouble(), child: still)),
          ],
        );
      },
    );
  }
}

/// A hairline that slides along under the filter tabs while [active] —
/// the quiet cue that a search is still running. A plain faint line (no
/// motion) when the system asks for reduced motion.
class _SearchLine extends StatefulWidget {
  final bool active;
  const _SearchLine({required this.active});

  @override
  State<_SearchLine> createState() => _SearchLineState();
}

class _SearchLineState extends State<_SearchLine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(_SearchLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _c.repeat();
    } else if (!widget.active && oldWidget.active) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: widget.active ? 1 : 0,
      child: SizedBox(
        height: 2,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            if (reduceMotion) {
              return ColoredBox(color: SeenlyPalette.accent.withOpacity(0.35));
            }
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final seg = w * 0.34;
                final x = _c.value * (w + seg) - seg;
                return ClipRect(
                  child: Stack(
                    children: [
                      Positioned(
                        left: x,
                        width: seg,
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                SeenlyPalette.accent.withOpacity(0),
                                SeenlyPalette.accent,
                                SeenlyPalette.accent.withOpacity(0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// What the results will look like, drawn in advance: six rows of the same
/// shape as [_ResultRow] (poster, two lines, a round button), shimmering,
/// each arriving a beat after the one above it.
class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => Entrance(
        key: ValueKey<int>(i),
        delay: Duration(milliseconds: 55 * i),
        duration: const Duration(milliseconds: 380),
        riseBy: 10,
        child: ClipPath(
          clipper: const _SoftSideNotchClipper(),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: ClayBoxDecoration(
              boxShadow: SeenlyPalette.flatCardShadow,
              color: SeenlyPalette.paper,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                ShimmerBlock(width: 54, height: 81, borderRadius: BorderRadius.circular(8)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.42 + 0.14 * ((i * 3) % 4),
                        child: ShimmerBlock(height: 14, borderRadius: BorderRadius.circular(6)),
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: 0.28,
                        child: ShimmerBlock(height: 10, borderRadius: BorderRadius.circular(5)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ShimmerBlock(width: 26, height: 26, borderRadius: BorderRadius.circular(13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
