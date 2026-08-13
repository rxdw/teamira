import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/collection.dart';
import '../../services/collections_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/section_header.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/hero_stack_carousel.dart';
import '../../widgets/shelf_stack_carousel.dart';
import '../title/title_detail_screen.dart';
import '../decide/decide_filters_screen.dart';
import 'collection_full_screen.dart';
import 'collection_interests_screen.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  final _prefs = CollectionsPrefsService();
  late Future<List<SeenlyCollection>> _future;
  bool _refreshing = false;
  String _filter = 'all'; // all | movie | series | game
  String _source = 'editorial'; // editorial (TMDB/IGDB/Open Library) | teamira (hand-curated)
  bool? _onboarded; // null while we're still checking storage
  Set<String> _interests = {};

  static const _allFilters = [
    ('all', 'all'),
    ('movie', 'movies'),
    ('series', 'series'),
    ('anime', 'anime'),
    ('game', 'games'),
    ('book', 'books'),
    ('manga', 'manga'),
  ];

  // Only offer tabs for what the person actually picked in "your interests"
  // (image 2's bar showed every category regardless of selection before).
  // Empty selection means "show me everything" — same meaning it has on
  // the interests screen itself — so the full list is the right fallback,
  // not an empty tab bar.
  List<(String, String)> get _filters {
    if (_interests.isEmpty) return _allFilters;
    return [
      for (final f in _allFilters)
        if (f.$1 == 'all' || _interests.contains(f.$1)) f,
    ];
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<List<SeenlyCollection>> _fetchCollections() {
    final feed = context.read<AppState>().feed;
    return _source == 'teamira' ? feed.teamiraCollections() : feed.collections();
  }

  Future<void> _switchSource(String source) async {
    if (_source == source) return;
    setState(() {
      _source = source;
      _future = _fetchCollections();
    });
  }

  Future<void> _bootstrap() async {
    final onboarded = await _prefs.hasOnboarded();
    if (!onboarded) {
      if (mounted) setState(() => _onboarded = false);
      return;
    }
    final interests = await _prefs.loadInterests();
    if (!mounted) return;
    setState(() {
      _interests = interests;
      _filter = interests.length == 1 ? interests.first : 'all';
      _onboarded = true;
      _future = _fetchCollections();
    });
  }

  /// Called both from the first-run picker (inline) and from the header
  /// icon when someone comes back to change their mind later.
  Future<void> _saveInterests(Set<String> selected) async {
    // First run already tells the person on-screen that they can change
    // this later (see CollectionInterestsScreen's copy) — the notice
    // below is for the *revisit* path, where the tab bar just changed
    // shape and it's worth a reminder of where to undo that.
    final isRevisit = _onboarded == true;
    await _prefs.saveInterests(selected);
    if (!mounted) return;
    setState(() {
      _interests = selected;
      _filter = selected.length == 1 ? selected.first : 'all';
      if (_onboarded != true) {
        _future = _fetchCollections();
      }
      _onboarded = true;
    });
    if (isRevisit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('updated — come back to this menu anytime to bring a tab back'),
        ),
      );
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final next = _fetchCollections();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Header + swipeable poster stack for a regular (non-franchise) shelf —
  /// shared by both the editorial and teamira picks tabs.
  List<Widget> _buildPosterSection(BuildContext context, SeenlyCollection c) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
        child: SectionHeader(
          title: c.title,
          trailing: 'all →',
          centerTitle: true,
          onTrailingTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CollectionFullScreen(collection: c),
            ),
          ),
        ),
      ),
      ShelfStackCarousel(
        items: c.items,
        onTap: (item) => Navigator.of(context).push(
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_onboarded == null) {
      return const Center(
        child: ThemedLoadingIndicator(
            strokeWidth: 2, color: SeenlyPalette.accent),
      );
    }
    if (_onboarded == false) {
      return CollectionInterestsScreen(
        isFirstRun: true,
        initialSelected: _interests,
        onSave: _saveInterests,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('collections', style: SeenlyText.screenTitle),
              Row(
                children: [
                  PressScale(
                    haptics: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CollectionInterestsScreen(
                          isFirstRun: false,
                          initialSelected: _interests,
                          onSave: _saveInterests,
                        ),
                      ),
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: SeenlyPalette.paper,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.tune, size: 15, color: SeenlyPalette.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressScale(
                    haptics: true,
                    onTap: _refreshing ? null : _refresh,
                    child: Container(
                      width: 32,
                      height: 32,
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
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
          child: Text(
            _source == 'teamira'
                ? 'franchises, best-of lists — picked by us'
                : 'gathered by the editors for tonight',
            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ScrollableUnderlineTabs(
            labels: [for (final f in _filters) f.$2],
            activeIndex: _filters.indexWhere((f) => f.$1 == _filter),
            onChanged: (i) => setState(() => _filter = _filters[i].$1),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: UnderlineTabRow(
            labels: const ['collections', 'teamira picks'],
            activeIndex: _source == 'teamira' ? 1 : 0,
            onChanged: (i) => _switchSource(i == 1 ? 'teamira' : 'editorial'),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: FutureBuilder<List<SeenlyCollection>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) {
                return _fadeSwitch(const _CollectionsSkeleton(key: ValueKey('collections-skeleton')));
              }
              if (snapshot.hasError) {
                // Scrollable + wrapped in RefreshIndicator even though
                // there's barely any content — a pull-down gesture needs
                // *something* scrollable to grab onto, and this state used
                // to have no way to retry at all besides the header button.
                return _fadeSwitch(RefreshIndicator(
                  key: const ValueKey('collections-error'),
                  onRefresh: _refresh,
                  color: SeenlyPalette.accent,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 60),
                    children: [
                      Text('couldn\'t reach the collections',
                          textAlign: TextAlign.center,
                          style: SeenlyText.serif(italic: true, color: SeenlyPalette.inkMuted)),
                      const SizedBox(height: 10),
                      Text('pull down, or tap the refresh icon above, to try again',
                          textAlign: TextAlign.center,
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
                    ],
                  ),
                ));
              }
              // The chips above (all / movies / series / …) already sit
              // above the collections↔teamira split and apply to both —
              // but filtering only by each shelf's *first* item let mixed
              // shelves slip through with other media types still inside
              // them. Filter every shelf's items down to just the picked
              // type instead, so "movies" really only ever shows movies.
              //
              // That alone created a new problem, most visible on the
              // "anime" tab: a general genre shelf that was never about
              // anime to begin with (e.g. the plain "Action" movie shelf)
              // can still contain a couple of TMDB titles that happen to
              // carry a Japanese-animation media type — leaving that
              // shelf's *title* ("Action") sitting right next to the real,
              // dedicated "Action Anime" shelf with barely 1-2 posters in
              // it. Two shelves that read as duplicates at a glance, one
              // of them basically empty. A stray couple of matches isn't
              // "a shelf" — require a small minimum before a general
              // shelf earns its own section under a type filter.
              const minShelfSize = 4;
              final rawCollections =
                  snapshot.data!.where((c) => c.items.isNotEmpty).toList();
              final collections = <SeenlyCollection>[];
              for (final c in rawCollections) {
                if (_filter == 'all') {
                  collections.add(c);
                  continue;
                }
                final onlyThisType =
                    c.items.where((it) => it.mediaType == _filter).toList();
                if (onlyThisType.length < minShelfSize) continue;
                collections.add(SeenlyCollection(
                  title: c.title,
                  titleEn: c.titleEn,
                  items: onlyThisType,
                  isFranchise: c.isFranchise,
                  description: c.description,
                  descriptionRu: c.descriptionRu,
                  history: c.history,
                  historyUrl: c.historyUrl,
                ));
              }
              // Belt-and-braces: if two shelves still ended up with the
              // exact same title (whatever the source — a genuinely
              // repeated label from the backend, say), merge them into
              // one rather than showing the same header twice. Keeps the
              // first shelf's spot in the order; items are deduped by id
              // so nothing doubles up within the merged shelf either.
              final merged = <String, SeenlyCollection>{};
              final order = <String>[];
              for (final c in collections) {
                final key = c.title.trim().toLowerCase();
                final existing = merged[key];
                if (existing == null) {
                  merged[key] = c;
                  order.add(key);
                } else {
                  final seenIds = existing.items.map((it) => it.id).toSet();
                  merged[key] = SeenlyCollection(
                    title: existing.title,
                    titleEn: existing.titleEn,
                    items: [
                      ...existing.items,
                      ...c.items.where((it) => seenIds.add(it.id)),
                    ],
                    isFranchise: existing.isFranchise,
                    description: existing.description,
                    descriptionRu: existing.descriptionRu,
                    history: existing.history,
                    historyUrl: existing.historyUrl,
                  );
                }
              }
              collections
                ..clear()
                ..addAll(order.map((key) => merged[key]!));
              if (collections.isEmpty) {
                final label =
                    _filters.firstWhere((f) => f.$1 == _filter).$2;
                return _fadeSwitch(RefreshIndicator(
                  key: const ValueKey('collections-empty'),
                  onRefresh: _refresh,
                  color: SeenlyPalette.accent,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 60),
                    children: [
                      Text(
                        _filter == 'all'
                            ? 'no collections available right now'
                            : 'no $label collections right now',
                        textAlign: TextAlign.center,
                        style: SeenlyText.serif(italic: true, color: SeenlyPalette.placeholder),
                      ),
                      const SizedBox(height: 10),
                      Text('pull down, or tap the refresh icon above, to check again',
                          textAlign: TextAlign.center,
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
                    ],
                  ),
                ));
              }
              // Claims one stagger slot per top-level group (the hero, or
              // each shelf/franchise banner) — capped the same way Home's
              // own `nextStagger` and Diary's `nextReveal` are, since a
              // group far down the page has nothing to cascade alongside
              // by the time anyone actually scrolls to it.
              var revealSlot = 0;
              Duration nextReveal({int step = 60, int maxSlots = 4}) {
                final slot = revealSlot < maxSlots ? revealSlot : maxSlots;
                final d = Duration(milliseconds: slot * step);
                revealSlot++;
                return d;
              }
              // Franchise shelves (teamira picks only) get a full-width
              // banner — tap opens the shelf as a 2-col grid rather than
              // scrolling posters inline. Editorial keeps its existing
              // "collection of the week" hero on the very first shelf.
              // Every group (the banner, or a header+carousel pair) is
              // wrapped in its own [ScrollReveal] — same "settle in on
              // the way down" reveal Diary's day groups and Home's own
              // sections use — so scrolling itself keeps unveiling
              // fresh shelves rather than everything below the fold
              // having already finished animating unseen.
              final List<Widget> children = [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                  child: _CantDecideBanner(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DecideFiltersScreen()),
                    ),
                  ),
                ),
              ];
              if (_source == 'teamira') {
                for (final c in collections) {
                  if (children.isNotEmpty) children.add(const SizedBox(height: 22));
                  if (c.isFranchise) {
                    children.add(
                      ScrollReveal(
                        delay: nextReveal(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: _FranchiseBanner(collection: c),
                        ),
                      ),
                    );
                  } else {
                    children.add(
                      ScrollReveal(
                        delay: nextReveal(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _buildPosterSection(context, c),
                        ),
                      ),
                    );
                  }
                }
              } else {
                final featured = collections.first;
                children.add(const SizedBox(height: 22));
                children.add(
                  ScrollReveal(
                    delay: nextReveal(),
                    child: HeroStackCarousel(
                      items: featured.items.take(8).toList(),
                      onTap: (item) => Navigator.of(context).push(
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
                for (final c in collections.skip(1)) {
                  children.add(const SizedBox(height: 22));
                  children.add(
                    ScrollReveal(
                      delay: nextReveal(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _buildPosterSection(context, c),
                      ),
                    ),
                  );
                }
              }
              return _fadeSwitch(RefreshIndicator(
                key: const ValueKey('collections-content'),
                onRefresh: _refresh,
                color: SeenlyPalette.accent,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: children,
                ),
              ));
            },
          ),
        ),
      ],
    );
  }

  /// Shared cross-fade for the collections body's top-level states
  /// (skeleton / error / empty / real content) — one [AnimatedSwitcher]
  /// keyed off each child's own [Key] so swapping between any two of
  /// them dissolves rather than cuts, matching Home's and Diary's own
  /// `_fadeSwitch`. A rebuild that keeps the same state (fresh data
  /// landing under the same content key during pull-to-refresh) is a
  /// no-op here, not a re-triggered fade.
  Widget _fadeSwitch(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

/// A quiet stand-in for the collections body while the first load is in
/// flight — rough bones of the real layout (the hero stack, a couple of
/// shelves) in the same soft shimmering paper tones [ShimmerBlock] uses
/// everywhere else, so the very first frame already reads as *this*
/// screen instead of a bare spinner. The cross-fade into real content
/// (see [_CollectionsScreenState._fadeSwitch]) then feels like a
/// settle, not a swap — same reasoning as Home's and Diary's own
/// skeletons.
class _CollectionsSkeleton extends StatelessWidget {
  const _CollectionsSkeleton({super.key});

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
        Center(child: _bone(w: 176, h: 264, r: 24)),
        const SizedBox(height: 14),
        Center(child: _bone(w: 120, h: 12, r: 6)),
        const SizedBox(height: 28),
        _bone(w: 130, h: 14, r: 7),
        const SizedBox(height: 12),
        SizedBox(
          height: 177,
          child: Row(
            children: [
              Expanded(child: _bone(h: 177, r: 18)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 177, r: 18)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 177, r: 18)),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _bone(w: 110, h: 14, r: 7),
        const SizedBox(height: 12),
        SizedBox(
          height: 177,
          child: Row(
            children: [
              Expanded(child: _bone(h: 177, r: 18)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 177, r: 18)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 177, r: 18)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CantDecideBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _CantDecideBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: SeenlyPalette.accent.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.auto_awesome_outlined, size: 18, color: SeenlyPalette.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('can\'t decide?', style: SeenlyText.sectionTitle),
                  const SizedBox(height: 2),
                  Text('let\'s figure it out',
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
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

/// Full-width banner for a franchise shelf (Star Wars, Marvel, ...) on the
/// teamira picks tab — a plain full-width poster banner, no "collection
/// of the week" overline, and tapping opens the shelf as a
/// grid (CollectionFullScreen) rather than jumping to a single title.
class _FranchiseBanner extends StatelessWidget {
  final SeenlyCollection collection;
  const _FranchiseBanner({required this.collection});

  @override
  Widget build(BuildContext context) {
    final firstItem = collection.items.first;
    return PressScale(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CollectionFullScreen(collection: collection),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (firstItem.posterUrl != null)
                FadeInNetworkImage(
                  url: firstItem.posterUrl!,
                  fit: BoxFit.cover,
                  placeholder: Container(color: SeenlyPalette.accent),
                )
              else
                Container(color: SeenlyPalette.accent),
              // A soft dark wash over the poster so the title stays
              // legible regardless of what's underneath it — same
              // reasoning as the old DecorationImage colorFilter, just
              // layered on top instead of baked into the image paint so
              // it still applies while FadeInNetworkImage is still
              // fading its own placeholder in.
              Container(color: Colors.black.withOpacity(0.4)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    collection.displayTitle,
                    style: SeenlyText.serif(italic: true, size: 19, color: SeenlyPalette.paper),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


