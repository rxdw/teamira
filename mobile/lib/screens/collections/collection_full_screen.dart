import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/collection.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/franchise_info_sheet.dart';
import '../../widgets/wow_motion.dart';
import '../title/title_detail_screen.dart';

/// Everything in one editorial shelf, as a grid — reached by tapping
/// "all →" on a Collections row.
///
/// Dressed up from a bare grid into something with a bit more presence:
/// a soft, blurred mosaic of the shelf's own posters sits behind the
/// title as the shelf scrolls under a pinned header, and every tile
/// settles into place with the same cascading reveal the rest of the
/// app uses. A shuffle button gives the grid something to *do* — a
/// quick way to see the same shelf in a different order, with the
/// whole grid resettling to mark the change.
class CollectionFullScreen extends StatefulWidget {
  final SeenlyCollection collection;
  const CollectionFullScreen({super.key, required this.collection});

  @override
  State<CollectionFullScreen> createState() => _CollectionFullScreenState();
}

class _CollectionFullScreenState extends State<CollectionFullScreen> {
  late List<int> _order =
      List.generate(widget.collection.items.length, (i) => i);
  // Bumped on every shuffle so each ScrollReveal below gets a fresh key —
  // a brand new key means a brand new State, which replays the settle-in
  // exactly like a first appearance, giving the shuffle a visible "the
  // grid just resettled" moment instead of silently reordering.
  int _revealGen = 0;
  int _shuffleCount = 0;

  void _shuffle() {
    HapticFeedback.mediumImpact();
    setState(() {
      _order.shuffle();
      _revealGen++;
      _shuffleCount++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    const expandedHeight = 300.0;

    // The hero backdrop is a dark image + dark scrim, so it needs light
    // (white) status-bar icons rather than the app-wide dark default —
    // otherwise the icons would be nearly invisible once the backdrop
    // extends under the now-transparent status bar (see main.dart).
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
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper.withOpacity(0.88),
                    shape: BoxShape.circle,
                    boxShadow: SeenlyPalette.softShadow,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                ),
              ),
            ),
            // FlexibleSpaceBar only reads this to position its *own* title
            // while collapsing — it doesn't reach into our FittedBox below.
            // Without it, the collapsed title sits left-aligned next to the
            // back button on Android while the expanded (hero) title reads
            // as centered, so the text visibly jumps sides mid-scroll.
            centerTitle: true,
            flexibleSpace: FlexibleSpaceBar(
              // Default is 1.5 — FlexibleSpaceBar re-enlarges the title by
              // that factor once fully expanded, on top of whatever
              // FittedBox below already fit it to. That round-trip is what
              // was pushing the text back past the available width and
              // into ellipsis territory at the expanded (hero) state.
              expandedTitleScale: 1.0,
              // Symmetric left/right padding (both sides wide enough to
              // clear the back button circle) so the centered text is
              // actually centered on screen, not just centered within a
              // lopsided 60/20 box that nudges it right.
              titlePadding: const EdgeInsets.fromLTRB(60, 0, 60, 14),
              title: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  collection.displayTitle,
                  maxLines: 1,
                  // AppBar/FlexibleSpaceBar wrap titles in a DefaultTextStyle
                  // with TextOverflow.ellipsis; without overriding it here,
                  // that ellipsis was firing before FittedBox got a chance
                  // to shrink the text to fit.
                  overflow: TextOverflow.visible,
                  style: SeenlyText.serif(size: 19, weight: FontWeight.w700, color: SeenlyPalette.paper),
                ),
              ),
              background: _CollectionHeroBackdrop(collection: collection),
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
                      child: Text('${collection.items.length} titles', style: SeenlyText.metaLabel),
                    ),
                    if (collection.isFranchise) ...[
                      _AboutFranchisePill(collection: collection),
                      const SizedBox(width: 8),
                    ],
                    _ShuffleButton(
                      turns: _shuffleCount.toDouble(),
                      onTap: collection.items.length > 1 ? _shuffle : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 2 / 3,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, gridIndex) {
                  final i = _order[gridIndex];
                  final item = collection.items[i];
                  return ScrollReveal(
                    key: ValueKey('${item.id}-$_revealGen'),
                    // Capped rather than growing with gridIndex — see
                    // the same reasoning on Profile's own shelf grid:
                    // only the handful of tiles entering the viewport
                    // together in one scroll pass should stagger
                    // against each other.
                    delay: Duration(milliseconds: 35 * (gridIndex % 6)),
                    child: ThemedPosterTile(
                      title: item.title.display,
                      posterUrl: item.posterUrl,
                      mediaType: item.mediaType,
                      fallbackColor: SeenlyPalette.gridColorFor(i),
                      badge: gridIndex < 3 && collection.isFranchise
                          ? _RankBadge(rank: gridIndex + 1)
                          : null,
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
                  );
                },
                childCount: collection.items.length,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// The pinned header's backdrop — a soft, gently blurred mosaic of up to
/// four of the shelf's own posters, washed dark and dissolved into the
/// page background at the bottom edge so the grid below feels like it's
/// emerging from the same image rather than sitting under an unrelated
/// banner. Falls back to a plain accent wash for a shelf with fewer than
/// four posters (or none at all — mock/offline data) rather than leaving
/// gaps in the mosaic.
class _CollectionHeroBackdrop extends StatelessWidget {
  final SeenlyCollection collection;
  const _CollectionHeroBackdrop({required this.collection});

  @override
  Widget build(BuildContext context) {
    final posterUrls = collection.items
        .map((e) => e.posterUrl)
        .where((u) => u != null && u.isNotEmpty)
        .take(4)
        .toList();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (posterUrls.isEmpty)
          Container(color: SeenlyPalette.gridColorFor(collection.title.hashCode))
        else
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1, tileMode: TileMode.clamp),
            // Row + Expanded divides leftover space by flex fraction using
            // double math, then each child gets rounded to whole physical
            // pixels independently at paint time — with an odd total width
            // that rounding doesn't land the same way on all four columns,
            // so one tile (usually the last) silently ends up a few
            // logical pixels wider than its neighbours, opening a
            // background-coloured seam next to it. Computing the four
            // widths ourselves up front and handing each tile a fixed
            // SizedBox sidesteps that: every column is deliberately equal,
            // and the one unavoidable leftover pixel (width isn't always
            // divisible by 4) is folded into the last column on purpose
            // instead of wherever the flex layout happens to round it.
            child: LayoutBuilder(
              builder: (context, constraints) {
                const segments = 4;
                final columnWidth = (constraints.maxWidth / segments).floorToDouble();
                final lastColumnWidth =
                    constraints.maxWidth - columnWidth * (segments - 1);

                return Row(
                  // Without this, each SizedBox below only gets a *loose*
                  // height constraint (0..full height), and an Image with a
                  // loose constraint lays itself out at its own aspect
                  // ratio instead of filling the box — BoxFit.cover only
                  // controls how the image is cropped *within* whatever
                  // box it's given, not how big that box is. That's also
                  // why this looked fine at first: while the network image
                  // was still loading, the plain color `placeholder`
                  // Container (which *does* expand to fill loose
                  // constraints) was what was on screen. The instant the
                  // real image swapped in — or on a later visit where it
                  // loads straight from cache with no loading frame at all
                  // — nothing was left to force the full height, and the
                  // strip collapsed down to a short, letterboxed band.
                  // Stretching the Row forces a tight height constraint
                  // all the way down, so every column — loading or loaded,
                  // fresh or cached — fills the same full height.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < segments; i++)
                      SizedBox(
                        width: i == segments - 1 ? lastColumnWidth : columnWidth,
                        child: i < posterUrls.length
                            ? FadeInNetworkImage(
                                url: posterUrls[i]!,
                                fit: BoxFit.cover,
                                // Posters are portrait (2:3) and get cropped to
                                // fit this wide, short strip — anchoring the
                                // crop to the top keeps the key art (title
                                // treatment, faces) in frame instead of
                                // centering into the middle of the poster.
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
        // Dark wash so the collapsed title stays legible over whatever
        // busy poster art sits underneath it...
        Container(color: Colors.black.withOpacity(0.18)),
        // ...then a short fade into the page background right at the
        // very bottom edge, so the header dissolves into the grid below
        // without eating into the poster art itself — the posters stay
        // full-bleed from the top of the screen all the way down to
        // just shy of the card's bottom edge.
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

/// A quiet "#1 / #2 / #3" ribbon on the first few tiles of a franchise
/// shelf — the grid already implies an order (release order, mostly),
/// this just makes it legible at a glance instead of something you'd
/// only notice by reading through the whole shelf in sequence.
class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: SeenlyPalette.ink.withOpacity(0.55),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: SeenlyText.mono(size: 10, weight: FontWeight.w600, color: SeenlyPalette.paper),
      ),
    );
  }
}

/// Reshuffles the grid's order on tap — the one bit of real
/// interactivity this screen otherwise lacks (everything else is just
/// "look, then tap through to a title"). [turns] only ever increases
/// (once per shuffle), so [TweenAnimationBuilder] always animates
/// forward from wherever it currently sits rather than ever winding
/// back the way a toggling 0↔1 value would — a full spin per tap, no
/// backward flick once it lands.
class _ShuffleButton extends StatelessWidget {
  final double turns;
  final VoidCallback? onTap;
  const _ShuffleButton({required this.turns, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: SeenlyPalette.paper,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: turns),
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Transform.rotate(
            angle: t * 6.283185307,
            child: child,
          ),
          child: Icon(
            Icons.shuffle,
            size: 15,
            color: onTap == null ? SeenlyPalette.placeholder : SeenlyPalette.ink,
          ),
        ),
      ),
    );
  }
}

/// "о франшизе" — quiet pill next to the title count, franchise shelves
/// only. Opens [showFranchiseInfoSheet] with the synopsis + history,
/// both already sitting on this same [SeenlyCollection] (see that
/// widget's docstring for where the data comes from).
class _AboutFranchisePill extends StatelessWidget {
  final SeenlyCollection collection;
  const _AboutFranchisePill({required this.collection});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => showFranchiseInfoSheet(context, collection),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: SeenlyPalette.accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories, size: 12, color: SeenlyPalette.accent),
            const SizedBox(width: 5),
            Text('о франшизе',
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
          ],
        ),
      ),
    );
  }
}
