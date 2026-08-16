import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../services/decide_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/interest_picker.dart' show InterestMotifPainter;
import 'decide_method_screen.dart';
import '../../services/app_translations.dart';

/// The narrowed-down pool a decision method (Teamira / random / roulette /
/// swipes) actually draws from, plus a short human-readable summary of
/// what was picked here — shown as a little breadcrumb on the method
/// screen and the individual method screens themselves, so the filters
/// chosen here don't just disappear from view once applied.
class DecideFilters {
  final Set<String> types;
  final Set<String> genres;
  final int? decade; // e.g. 2010 means "2010s"; null means "any year"

  const DecideFilters({required this.types, required this.genres, required this.decade});

  String get summary {
    final parts = <String>[
      if (types.length == 1) types.first else '${types.length} types',
      if (genres.isNotEmpty) (genres.length == 1 ? genres.first.toLowerCase() : '${genres.length} genres'),
      if (decade != null) decadeLabel(decade!),
    ];
    return parts.isEmpty ? 'anything, any year' : parts.join(' · ');
  }
}

String decadeLabel(int decade) => decade < 1980 ? 'before 1980' : '${decade}s';

/// Every content type the flow can draw from.
const kDecidePickableTypes = {'movie', 'series', 'anime', 'book', 'manga', 'game'};

const _kSteps = ['type', 'genre', 'year'];

/// Entry point for the whole "can't decide?" flow (Home's [_CantDecideCard]
/// pushes this first). One feed fetch, kept in [_fullFeed] and re-sliced
/// locally as each choice changes.
///
/// Presented as a short three-step wizard — type, then genre, then
/// year — rather than all three axes dumped on one screen: narrowing by
/// type first keeps the genre list from ballooning into a wall of every
/// genre across movies, series, anime, books and manga at once. Every
/// step can be skipped independently with a "doesn't matter" tap, so
/// someone who only cares about type can blow through genre and year in
/// two taps.
class DecideFiltersScreen extends StatefulWidget {
  // Overrides where the pool being narrowed down comes from — defaults
  // to the whole-app feed (Home's own "can't decide?" entry). Passed by
  // co-viewing's own entry points (see co_view_vote_screen.dart) to run
  // this exact same three-step wizard over whichever pool_source was
  // picked there instead (personal/coview/both/catalog).
  final Future<List<MediaItem>> Function()? poolLoader;
  // Overrides what happens once all three steps are confirmed — defaults
  // to pushing [DecideMethodScreen]. Co-viewing's entry points supply
  // their own instead, since "random"/"reel" there just carries the
  // filtered pool on to the same reveal screens Home uses, while
  // "swipe"/"poll" needs to open the filtered pool up as a *round* both
  // phones look at (see propose()), not just hand it to one method
  // screen locally.
  final void Function(BuildContext context, List<MediaItem> pool, DecideFilters filters)? onFinished;
  // Whether picking here should overwrite DecidePrefsService's
  // remembered type/genre/year for next time. True for Home's own
  // solo flow; co-viewing's entry points pass false so a filter picked
  // for tonight's circle round doesn't quietly become the default the
  // next time someone opens the solo can't-decide flow.
  final bool persistPrefs;

  const DecideFiltersScreen({
    super.key,
    this.poolLoader,
    this.onFinished,
    this.persistPrefs = true,
  });

  @override
  State<DecideFiltersScreen> createState() => _DecideFiltersScreenState();
}

class _DecideFiltersScreenState extends State<DecideFiltersScreen> {
  final _prefs = DecidePrefsService();

  List<MediaItem> _fullFeed = const [];
  bool _loading = true;
  bool _failed = false;

  int _step = 0;

  Set<String> _selectedTypes = {};
  Set<String> _selectedGenres = {};
  int? _selectedDecade;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final savedTypes = await _prefs.loadTypes();
    final savedGenres = await _prefs.loadGenres();
    final savedDecade = await _prefs.loadDecade();
    if (mounted) {
      setState(() {
        if (savedTypes.isNotEmpty) _selectedTypes = savedTypes;
        _selectedGenres = savedGenres;
        _selectedDecade = savedDecade;
      });
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final app = context.read<AppState>();
      final feed = await (widget.poolLoader?.call() ?? app.feed.feed());
      if (!mounted) return;
      setState(() {
        _fullFeed = feed;
        _loading = false;
        // Drop any genre/decade picked previously that this feed simply
        // doesn't have anymore, rather than silently filtering to zero.
        _selectedGenres = _selectedGenres.intersection(_availableGenres());
        if (_selectedDecade != null && !_availableDecades().contains(_selectedDecade)) {
          _selectedDecade = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  // The pool as narrowed by whatever's been confirmed *so far* — empty
  // types/genres mean "no restriction on this axis yet", same "any"
  // semantics as before, just evaluated progressively per step.
  List<MediaItem> get _typedPool {
    final types = _selectedTypes.isEmpty ? kDecidePickableTypes : _selectedTypes;
    return _fullFeed.where((m) => types.contains(m.mediaType)).toList();
  }

  List<MediaItem> get _typedAndGenredPool {
    if (_selectedGenres.isEmpty) return _typedPool;
    return _typedPool.where((item) => item.genres.any(_selectedGenres.contains)).toList();
  }

  List<MediaItem> get _filteredPool {
    if (_selectedDecade == null) return _typedAndGenredPool;
    return _typedAndGenredPool.where((item) {
      final year = item.year;
      if (year == null) return false;
      final bucket = year < 1980 ? 1970 : (year ~/ 10) * 10;
      return bucket == _selectedDecade;
    }).toList();
  }

  /// The pool used for the live "N titles" counter at the bottom — grows
  /// stricter as each step is confirmed.
  List<MediaItem> get _poolSoFar {
    switch (_step) {
      case 0:
        return _typedPool;
      case 1:
        return _typedAndGenredPool;
      default:
        return _filteredPool;
    }
  }

  Map<String, int> _typeCounts() {
    final counts = <String, int>{};
    for (final type in kDecidePickableTypes) {
      counts[type] = _fullFeed.where((m) => m.mediaType == type).length;
    }
    return counts;
  }

  Set<String> _availableGenres() {
    final set = <String>{};
    for (final item in _typedPool) {
      set.addAll(item.genres);
    }
    return set;
  }

  Map<String, int> _genreCounts() {
    final counts = <String, int>{};
    for (final item in _typedPool) {
      for (final genre in item.genres) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    return counts;
  }

  Set<int> _availableDecades() {
    final set = <int>{};
    for (final item in _typedPool) {
      final year = item.year;
      if (year != null) set.add(year < 1980 ? 1970 : (year ~/ 10) * 10);
    }
    return set;
  }

  Map<int, int> _decadeCounts() {
    final counts = <int, int>{};
    for (final item in _typedAndGenredPool) {
      final year = item.year;
      if (year == null) continue;
      final bucket = year < 1980 ? 1970 : (year ~/ 10) * 10;
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    return counts;
  }

  void _toggleType(String type) {
    setState(() {
      final current = _selectedTypes.isEmpty ? {...kDecidePickableTypes} : {..._selectedTypes};
      if (current.contains(type)) {
        if (current.length > 1) current.remove(type);
      } else {
        current.add(type);
      }
      _selectedTypes = current;
      _selectedGenres = _selectedGenres.intersection(_availableGenres());
      if (_selectedDecade != null && !_availableDecades().contains(_selectedDecade)) {
        _selectedDecade = null;
      }
    });
  }

  void _toggleGenre(String genre) {
    setState(() {
      if (_selectedGenres.contains(genre)) {
        _selectedGenres = {..._selectedGenres}..remove(genre);
      } else {
        _selectedGenres = {..._selectedGenres, genre};
      }
    });
  }

  void _pickDecade(int? decade) {
    setState(() => _selectedDecade = _selectedDecade == decade ? null : decade);
  }

  void _goToStep(int step) {
    setState(() => _step = step);
  }

  void _back() {
    if (_step > 0) {
      _goToStep(_step - 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _skipType() {
    setState(() => _selectedTypes = {});
    _goToStep(1);
  }

  void _skipGenre() {
    setState(() => _selectedGenres = {});
    _goToStep(2);
  }

  void _skipYear() {
    setState(() => _selectedDecade = null);
    _finish();
  }

  Future<void> _finish() async {
    final filters = DecideFilters(
      types: _selectedTypes.isEmpty ? kDecidePickableTypes : _selectedTypes,
      genres: _selectedGenres,
      decade: _selectedDecade,
    );
    if (widget.persistPrefs) {
      unawaited(_prefs.save(types: filters.types, genres: filters.genres, decade: filters.decade));
    }
    final onFinished = widget.onFinished;
    if (onFinished != null) {
      onFinished(context, _filteredPool, filters);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DecideMethodScreen(pool: _filteredPool, filters: filters),
      ),
    );
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
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
              child: Row(
                children: [
                  _BackCircle(onTap: _back),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_headline, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          _subline,
                          style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  if (!_loading && !_failed) _StepDots(step: _step, count: _kSteps.length),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: ThemedLoadingIndicator())
                  : _failed
                      ? _ErrorState(onRetry: _load)
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                                  .animate(animation),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(_step),
                            child: _buildStep(),
                          ),
                        ),
            ),
            if (!_loading && !_failed) _buildFooter(),
          ],
        ),
      ),
    );
  }

  String get _headline {
    switch (_step) {
      case 0:
        return 'what\'s the mood tonight?';
      case 1:
        return 'any genre in mind?';
      default:
        return 'and roughly which era?';
    }
  }

  String get _subline {
    switch (_step) {
      case 0:
        return 'pick one or more to start narrowing';
      case 1:
        return 'based on what you just picked';
      default:
        return 'or leave it wide open';
    }
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildTypeStep();
      case 1:
        return _buildGenreStep();
      default:
        return _buildYearStep();
    }
  }

  Widget _buildTypeStep() {
    final counts = _typeCounts();
    final types = kDecidePickableTypes.toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
      children: [
        for (final type in types) ...[
          _TypeCard(
            type: type,
            color: SeenlyPalette.mediaColor(type),
            label: _typeLabel(type),
            count: counts[type] ?? 0,
            selected: _selectedTypes.isEmpty || _selectedTypes.contains(type),
            onTap: () => _toggleType(type),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 6),
        _DoesntMatterLink(label: 'doesn\'t matter — any type', onTap: _skipType),
      ],
    );
  }

  Widget _buildGenreStep() {
    final available = _availableGenres().toList()..sort();
    final counts = _genreCounts();
    return Column(
      children: [
        Expanded(
          child: available.isEmpty
              ? Center(
                  child: Text(
                    'no genres logged for this pool yet'.tr,
                    style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: _ScatteredGenreField(
                    genres: available,
                    counts: counts,
                    selected: _selectedGenres,
                    onToggle: _toggleGenre,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
          child: _DoesntMatterLink(label: 'doesn\'t matter — any genre', onTap: _skipGenre),
        ),
      ],
    );
  }

  Widget _buildYearStep() {
    final decades = _availableDecades().toList()..sort((a, b) => b.compareTo(a));
    final counts = _decadeCounts();
    return Column(
      children: [
        Expanded(
          child: decades.isEmpty
              ? Center(
                  child: Text(
                    'no years logged for this pool yet'.tr,
                    style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
                  child: _EraTimeline(
                    decades: decades,
                    counts: counts,
                    selected: _selectedDecade,
                    onTap: _pickDecade,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
          child: _DoesntMatterLink(label: 'doesn\'t matter — any year', onTap: _skipYear),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final pool = _poolSoFar;
    final isLastStep = _step == _kSteps.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      child: Column(
        children: [
          Text(
            pool.isEmpty
                ? 'nothing matches that combination'
                : '${pool.length} ${pool.length == 1 ? 'title' : 'titles'} to choose from',
            style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: isLastStep ? 'continue' : 'next',
            onTap: pool.isEmpty
                ? null
                : () {
                    if (isLastStep) {
                      _finish();
                    } else {
                      _goToStep(_step + 1);
                    }
                  },
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'movie':
        return 'movies';
      case 'series':
        return 'series';
      case 'anime':
        return 'anime';
      case 'book':
        return 'books';
      case 'manga':
        return 'manga';
      case 'game':
        return 'games';
      default:
        return type;
    }
  }
}

/// One full-width row in the type-picking list — a soft tinted card with
/// the type's categorical color, the same faint category illustration
/// used on the "your interests" screen (see widgets/interest_picker.dart's
/// InterestMotifPainter — a filmstrip, a screen, a burst, an open book, a
/// scatter of screentone dots) bleeding off the right edge, a count, and
/// a checkmark when selected. One per row rather than a 2-up grid so the
/// very first, most consequential choice in the flow (it's what shrinks
/// the genre list down to something browsable) reads as the same kind of
/// inviting, illustrated pick as everywhere else this set of categories
/// shows up, not a cramped icon tile.
class _TypeCard extends StatelessWidget {
  final String type;
  final Color color;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.type,
    required this.color,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withOpacity(selected ? 0.14 : 0.06), SeenlyPalette.paper),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? color : SeenlyPalette.border, width: selected ? 1.6 : 1),
          boxShadow: selected ? SeenlyPalette.softShadow : null,
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -14,
              bottom: -14,
              width: 108,
              child: CustomPaint(
                painter: InterestMotifPainter(
                  value: type,
                  color: color,
                  opacity: selected ? 0.20 : 0.11,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 34,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: SeenlyText.serif(size: 15.5, weight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text('$count', style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 20,
                    color: selected ? color : SeenlyPalette.dashedBorder,
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

/// Lays the genre chips out like a loosely scattered sheet — each one
/// given a small vertical lift and a slight tilt so the board doesn't
/// read as a tidy grid — while guaranteeing they never overlap or clip.
///
/// The previous version used [Stack]/[Positioned] on a fixed grid: chips
/// were nudged and rotated *after* their cell was assigned, so a big
/// jitter or steep rotation could push one chip into its neighbour's
/// cell. This version uses [Wrap] instead, which reserves real, actual
/// layout space for every child based on its measured size — so chips
/// can never overlap. The scattered feel comes entirely from per-chip
/// padding (the "lift") and a [Transform.rotate] (the "tilt"), both kept
/// small enough, and both padded around generously enough, that a
/// rotated chip's silhouette never reaches outside its own reserved box.
/// Every lift/tilt is derived deterministically from the chip's index in
/// a fixed shuffle order, so toggling a selection or a count refreshing
/// never makes the board jump — same input, same layout, every rebuild.
class _ScatteredGenreField extends StatelessWidget {
  final List<String> genres;
  final Map<String, int> counts;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _ScatteredGenreField({
    required this.genres,
    required this.counts,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // A fixed shuffle order (not list order) so alphabetically adjacent
    // genres — which otherwise tend to share a first letter and read as
    // a little cluster — end up scattered across the board instead of
    // sitting next to each other.
    final order = [...genres]..shuffle(math.Random(7));

    Widget chip(String label) {
      // Called in the same, deterministic order every build (row-major
      // over the fixed shuffle), so a given label always gets the same
      // tilt/lift regardless of which layout branch below is used —
      // toggling a selection never makes the board jump.
      final rnd = math.Random(label.hashCode);
      final angle = (rnd.nextDouble() - 0.5) * 0.16; // ~ ±4.6°
      final liftTop = rnd.nextBool();
      final lift = 6 + rnd.nextDouble() * 8; // 6–14
      return Padding(
        padding: EdgeInsets.only(
          top: liftTop ? 4 : lift,
          bottom: liftTop ? lift : 4,
          left: 8,
          right: 8,
        ),
        child: Transform.rotate(
          angle: angle,
          child: _GenreTag(
            label: label,
            count: counts[label] ?? 0,
            color: SeenlyPalette.gridColorFor(genres.indexOf(label)),
            active: selected.contains(label),
            onTap: () => onToggle(label),
          ),
        ),
      );
    }

    // A rough but precise-enough estimate of each chip's natural
    // on-screen width — same fonts/padding as [_GenreTag] plus the
    // wrapper padding from `chip()` above — so column counts can be
    // compared without actually laying anything out first.
    double chipWidth(String label) {
      final count = counts[label] ?? 0;
      final labelPainter = TextPainter(
        text: TextSpan(text: label.toLowerCase(), style: SeenlyText.serif(size: 13, weight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final countPainter = TextPainter(
        text: TextSpan(text: '$count', style: SeenlyText.mono(size: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      // chip() wrapper padding (8+8) + _GenreTag padding (14+14) +
      // border (~2) + label + inter-text gap (6) + count.
      return 16 + 28 + 2 + labelPainter.width + 6 + countPainter.width;
    }

    // One fixed vertical footprint per chip: _GenreTag's own padding
    // and line height plus the largest possible lift/rotation padding
    // from `chip()` above — deliberately a slight over-estimate, so the
    // grid never ends up taller than expected once actually laid out.
    const chipHeight = 58.0;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final widths = {for (final label in order) label: chipWidth(label)};

      // Try a handful of column counts and, for each, work out how much
      // a single uniform scale could enlarge that arrangement before it
      // hit either edge of the available box. A short, wide area wants
      // few, wide columns; a tall, narrow one wants more, narrower
      // columns — picking whichever arrangement's own width-to-height
      // shape best matches the screen's is what actually lets the grid
      // fill it, instead of matching one axis and leaving the other
      // mostly empty.
      var bestCols = 1;
      var bestScale = 0.0;
      var bestRows = order.length;
      for (var cols = 1; cols <= math.min(4, order.length); cols++) {
        final rows = (order.length / cols).ceil();
        var maxRowWidth = 0.0;
        for (var r = 0; r < rows; r++) {
          var rowWidth = 0.0;
          for (var c = r * cols; c < (r + 1) * cols && c < order.length; c++) {
            rowWidth += widths[order[c]]!;
          }
          if (rowWidth > maxRowWidth) maxRowWidth = rowWidth;
        }
        final scale = math.min(width / maxRowWidth, height / (rows * chipHeight));
        if (scale > bestScale) {
          bestScale = scale;
          bestCols = cols;
          bestRows = rows;
        }
      }

      // If even the best arrangement would need real shrinking to fit,
      // there are simply too many genres for one screen — fall back to
      // a scrolling wrap at normal chip size instead of cramming.
      final fitsWithoutScroll = height.isFinite && bestScale >= 0.92;

      if (fitsWithoutScroll) {
        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < bestRows; r++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = r * bestCols; c < (r + 1) * bestCols && c < order.length; c++)
                        chip(order[c]),
                    ],
                  ),
              ],
            ),
          ),
        );
      }

      // Too many genres to fill one screen without cramming — fall back
      // to a scrolling wrap instead of squeezing rows unreadably thin.
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 2,
          children: [for (final label in order) chip(label)],
        ),
      );
    });
  }
}

/// A genre chip, sized and colored a bit more generously than the plain
/// [PillChip] — a soft tint of a rotating palette color plus a count, so
/// a wall of genre names doesn't read as flat gray text.
class _GenreTag extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _GenreTag({
    required this.label,
    required this.count,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color : Color.alphaBlend(color.withOpacity(0.10), SeenlyPalette.paper),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? color : color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toLowerCase(),
              style: SeenlyText.serif(
                size: 13,
                weight: FontWeight.w600,
                color: active ? SeenlyPalette.accentOnAccent : SeenlyPalette.ink,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: SeenlyText.mono(
                size: 10,
                color: active ? SeenlyPalette.accentOnAccent.withOpacity(0.8) : SeenlyPalette.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A vertical "timeline" of decades — a spine running down the left with
/// a dot per era, and each row's own fill bar sized to how many titles
/// that decade actually holds. Reads as a shelf getting fuller toward
/// whichever era the pool is heaviest in, instead of a flat grid of
/// same-size cards that gives no sense of where the bulk of the pool
/// actually sits.
class _EraTimeline extends StatelessWidget {
  final List<int> decades;
  final Map<int, int> counts;
  final int? selected;
  final ValueChanged<int> onTap;

  const _EraTimeline({
    required this.decades,
    required this.counts,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxCount = decades.map((d) => counts[d] ?? 0).fold(1, (a, b) => a > b ? a : b);

    return LayoutBuilder(builder: (context, constraints) {
      // A rough floor for how short a row can get before the card
      // starts feeling cramped.
      const minRowHeight = 70.0;
      final fitsWithoutScroll =
          constraints.maxHeight.isFinite && decades.length * minRowHeight <= constraints.maxHeight;

      Widget row(int i, {required bool fillHeight}) {
        final decade = decades[i];
        final fillFraction = ((counts[decade] ?? 0) / maxCount).clamp(0.16, 1.0);
        return _EraRow(
          label: decadeLabel(decade),
          count: counts[decade] ?? 0,
          fillFraction: fillFraction,
          selected: selected == decade,
          isLast: i == decades.length - 1,
          fillHeight: fillHeight,
          onTap: () => onTap(decade),
        );
      }

      if (fitsWithoutScroll) {
        // Few enough eras that fixed-height cards would leave the rest
        // of the step empty — instead let each row claim a share of the
        // full available height weighted by its fill fraction, so a
        // short era list fills the screen the same way a long one does.
        return Column(
          children: [
            for (var i = 0; i < decades.length; i++)
              Expanded(
                flex: (30 + 70 * ((counts[decades[i]] ?? 0) / maxCount).clamp(0.16, 1.0)).round(),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: row(i, fillHeight: true),
                ),
              ),
          ],
        );
      }

      // Too many eras to fill one screen without cramming — fall back
      // to a scrolling column of fixed-height rows instead.
      return SingleChildScrollView(
        child: Column(
          children: [
            for (var i = 0; i < decades.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: row(i, fillHeight: false),
              ),
          ],
        ),
      );
    });
  }
}

/// One row of the era timeline: a spine dot connected by a line to the
/// next row, and a card whose height and internal fill bar both scale
/// with the decade's share of the pool — a taller, fuller-looking card
/// for a decade with more titles logged, a slimmer one for a decade
/// that's barely represented. When [fillHeight] is true the row instead
/// stretches to whatever height its parent [Expanded] gives it (used to
/// spread a short era list across the full screen); when false it uses
/// a fixed height sized from [fillFraction] (used in the scrolling
/// fallback for a long era list).
class _EraRow extends StatelessWidget {
  final String label;
  final int count;
  final double fillFraction;
  final bool selected;
  final bool isLast;
  final bool fillHeight;
  final VoidCallback onTap;

  const _EraRow({
    required this.label,
    required this.count,
    required this.fillFraction,
    required this.selected,
    required this.isLast,
    required this.fillHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spine = SizedBox(
      width: 18,
      child: Column(
        children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? SeenlyPalette.accent : SeenlyPalette.border,
              border: selected ? null : Border.all(color: SeenlyPalette.accent.withOpacity(0.4)),
            ),
          ),
          if (!isLast)
            Expanded(
              child: Container(width: 1.5, color: SeenlyPalette.dashedBorder),
            ),
        ],
      ),
    );

    final card = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: fillHeight ? null : 58.0 + 34.0 * fillFraction,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? SeenlyPalette.accent : SeenlyPalette.border),
          boxShadow: selected ? SeenlyPalette.softShadow : null,
        ),
        child: Stack(
          children: [
            // A proportional fill running along the bottom — the more
            // titles this decade holds relative to the fullest one, the
            // further it reaches.
            Align(
              alignment: Alignment.bottomLeft,
              child: FractionallySizedBox(
                widthFactor: fillFraction,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: selected
                        ? SeenlyPalette.accentOnAccent.withOpacity(0.35)
                        : SeenlyPalette.accent.withOpacity(0.28),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            // Since the count sits inside a Stack, this Positioned.fill
            // is what lets it use the card's *entire* height — a plain
            // Padding here would only be as tall as the label text and
            // leave everything below it empty, which was the actual
            // problem: the fill bar was the only thing acknowledging
            // how much taller a big-count card is than a small one.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: SeenlyText.serif(
                        size: 18,
                        weight: FontWeight.w600,
                        color: selected ? SeenlyPalette.accentOnAccent : SeenlyPalette.ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // The title count as a big, soft watermark-style
                    // number — scaled by FittedBox to claim whatever
                    // empty width and height the card actually has, so
                    // a tall card (more titles) gets a genuinely bigger
                    // number instead of the same small text just
                    // floating in more blank space.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$count',
                                style: SeenlyText.serif(
                                  size: 44,
                                  weight: FontWeight.w700,
                                  color: selected
                                      ? SeenlyPalette.accentOnAccent.withOpacity(0.32)
                                      : SeenlyPalette.ink.withOpacity(0.14),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (count == 1 ? 'title' : 'titles').toUpperCase(),
                                style: SeenlyText.mono(
                                  size: 15,
                                  weight: FontWeight.w600,
                                  color: selected
                                      ? SeenlyPalette.accentOnAccent.withOpacity(0.85)
                                      : SeenlyPalette.inkMuted,
                                ).copyWith(letterSpacing: 1.2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final row = Row(
      crossAxisAlignment: fillHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        spine,
        const SizedBox(width: 12),
        Expanded(child: card),
      ],
    );

    return fillHeight ? row : IntrinsicHeight(child: row);
  }
}

/// Small dot row in the header showing which of the three steps we're on
/// — filled for the current and completed steps, hollow for what's ahead.
class _StepDots extends StatelessWidget {
  final int step;
  final int count;
  const _StepDots({required this.step, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(left: 5),
            width: i == step ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i <= step ? SeenlyPalette.accent : SeenlyPalette.dashedBorder,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _DoesntMatterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DoesntMatterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.accent).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: SeenlyPalette.accent,
          ),
        ),
      ),
    );
  }
}

class _BackCircle extends StatelessWidget {
  final VoidCallback onTap;
  const _BackCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
        onPressed: onTap,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onRetry,
        child: Text('couldn\'t load — tap to try again'.tr,
            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted)),
      ),
    );
  }
}
