import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ai_response.dart';
import '../../services/api_client.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/match_ring.dart';
import '../../widgets/poster_tile.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_pull_to_refresh.dart';
import '../title/title_detail_screen.dart';

/// The screen Ask Teamira opens into. Reads a query typed on Home (see
/// _AskTeamiraCard in home_screen.dart) and fetches the ranked shortlist
/// itself, so the card doesn't need to hold any loading state of its own.
///
/// Laid out as one big hero card for the top pick, then a poster grid for
/// the rest — not a uniform row list. A row list reads as a spreadsheet:
/// every entry gets the same visual weight regardless of how good a match
/// it actually is, and 20+ near-identical rows scroll past as a wall of
/// text. The hero singles out #1 the way the match score already singles
/// it out numerically; the grid puts poster art front and center for
/// everything else, which is both more scannable (recognize a cover
/// faster than read a title) and just more pleasant to scroll through.
class AskTeamiraResultsScreen extends StatefulWidget {
  final String query;
  const AskTeamiraResultsScreen({super.key, required this.query});

  @override
  State<AskTeamiraResultsScreen> createState() => _AskTeamiraResultsScreenState();
}

class _AskTeamiraResultsScreenState extends State<AskTeamiraResultsScreen> {
  late Future<List<AiMatch>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AiMatch>> _load() async {
    final app = context.read<AppState>();
    final response = await app.ai.ask(widget.query);
    return response.results;
  }

  Future<void> _retry() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    // Swallow the error here — the FutureBuilder below still surfaces it
    // in its own error state; this just needs the pull-to-refresh motif
    // to know when to stop spinning, not to react to the outcome itself.
    await next.then((_) {}, onError: (_) {});
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
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: SeenlyPalette.paper,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('teamira picked these', style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '"${widget.query}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<List<AiMatch>>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return const Center(child: ThemedLoadingIndicator());
                  }
                  if (snapshot.hasError) {
                    final message = snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : "couldn't reach teamira's catalog just now";
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome_outlined, size: 26, color: SeenlyPalette.placeholder),
                            const SizedBox(height: 10),
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
                            ),
                            const SizedBox(height: 14),
                            GestureDetector(
                              onTap: _retry,
                              child: Text('tap to try again',
                                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final results = snapshot.data!;
                  if (results.isEmpty) {
                    return Center(
                      child: Text("nothing matched that — try different words",
                          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted)),
                    );
                  }
                  final top = results.first;
                  final rest = results.length > 1 ? results.sublist(1) : const <AiMatch>[];
                  return ThemedPullToRefresh(
                    onRefresh: () async => _retry(),
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                          sliver: SliverToBoxAdapter(
                            child: _StaggerIn(index: 0, child: _HeroMatchCard(match: top)),
                          ),
                        ),
                        if (rest.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 12,
                                // Tall enough for a worst-case card: 2:3
                                // poster, a 2-line title, the meta line,
                                // a row of genre chips, AND a 2-line
                                // "why this matched" note all stacked
                                // below it (see _GridMatchCard). 0.6 only
                                // left room for the poster plus one short
                                // line, so anything with genres and a
                                // reasoning note overflowed the cell by
                                // 70-90px. Kept as a fixed ratio rather
                                // than measuring per-card so every row
                                // still lines up evenly.
                                childAspectRatio: 0.44,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => _StaggerIn(
                                  index: i + 1,
                                  child: _GridMatchCard(match: rest[i]),
                                ),
                                childCount: rest.length,
                              ),
                            ),
                          )
                        else
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades + slides a card in from just below its resting spot, staggered by
/// [index] — the data still arrives in one frame, this is purely a
/// one-shot entrance so a whole screen of cards lands as a cascade rather
/// than a slab of content popping in together. Delay is capped so a long
/// list's tail doesn't keep trickling in for ages after the top has
/// already settled.
class _StaggerIn extends StatefulWidget {
  final int index;
  final Widget child;
  const _StaggerIn({required this.index, required this.child});

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 10));
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// The English fragments `_reasoning` in backend/app/routers/ai.py joins
/// with "; " — translated here rather than server-side since they're
/// plain, stable substrings and every other piece of copy on this screen
/// is already client-side.
///
/// The "genres: ..." fragment is dropped entirely: both this screen's
/// hero card and grid cards already show a title's genre chips right
/// next to its poster, so repeating them again in the reasoning line is
/// pure duplication, not new information — worth showing a title's genre
/// tags once, not twice. Whatever's left (a resolved "like X" reference,
/// "era matches", the semantic "matches what you described") is the part
/// that's actually telling the person something the chips don't already
/// say, so that's what survives here. Returns null when nothing survives
/// (a pure genre-only match), so the caller can skip rendering the row
/// entirely rather than showing an empty bar.
String? _friendlyReasoning(String raw) {
  final kept = raw.split(';').map((p) => p.trim()).where((p) => !p.startsWith('genres: ')).map((p) {
    if (p.startsWith('similar to ')) return 'похоже на «${p.substring(11)}»';
    if (p == 'era matches') return 'подходящая эпоха';
    if (p == 'matches what you described') return 'совпадает с описанием';
    return p;
  }).toList();
  if (kept.isEmpty) return null;
  return kept.join(' · ');
}

/// Tries [backdropUrl] first (a wide still — what a hero banner actually
/// wants), falls back to [posterUrl] cropped to fill, and only drops to a
/// flat color fill (matching PosterTile's own placeholder style) if
/// neither loaded — games/books/manga rarely carry a backdrop, so this is
/// the common path for those, not an edge case.
class _HeroBackdrop extends StatelessWidget {
  final String? backdropUrl;
  final String? posterUrl;
  final Color fallbackColor;

  const _HeroBackdrop({this.backdropUrl, this.posterUrl, required this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    final url = (backdropUrl != null && backdropUrl!.isNotEmpty) ? backdropUrl : posterUrl;
    if (url == null || url.isEmpty) {
      return Container(color: fallbackColor.withOpacity(0.55));
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: fallbackColor.withOpacity(0.55)),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(color: fallbackColor.withOpacity(0.35));
      },
    );
  }
}

class _HeroMatchCard extends StatefulWidget {
  final AiMatch match;
  const _HeroMatchCard({required this.match});

  @override
  State<_HeroMatchCard> createState() => _HeroMatchCardState();
}

class _HeroMatchCardState extends State<_HeroMatchCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final item = match.item;
    final reasoning = _friendlyReasoning(match.reasoning ?? '');
    final fallbackColor = SeenlyPalette.mediaColor(item.mediaType);

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            SizedBox(
              height: 240,
              width: double.infinity,
              child: _HeroBackdrop(
                backdropUrl: item.backdropUrl,
                posterUrl: item.posterUrl,
                fallbackColor: fallbackColor,
              ),
            ),
            // Warm-ink gradient instead of flat black, so the overlay
            // still reads as part of this app's paper-and-ink palette
            // rather than a generic dark scrim.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      SeenlyPalette.ink.withOpacity(0.0),
                      SeenlyPalette.ink.withOpacity(0.30),
                      SeenlyPalette.ink.withOpacity(0.86),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '✦ лучшее совпадение',
                  style: SeenlyText.mono(size: 10, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: SeenlyPalette.paper.withOpacity(0.92),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: MatchRing(match: match.match, size: 50),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title.display,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: SeenlyPalette.paper),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.year != null ? '${item.mediaType} · ${item.year}' : item.mediaType,
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.paper.withOpacity(0.78)),
                  ),
                  if (item.genres.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final g in item.genres.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: SeenlyPalette.paper.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: SeenlyPalette.paper.withOpacity(0.35), width: 0.8),
                            ),
                            child: Text(g, style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper)),
                          ),
                      ],
                    ),
                  ],
                  if (reasoning != null) ...[
                    const SizedBox(height: 9),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome, size: 12, color: SeenlyPalette.paper.withOpacity(0.85)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            reasoning,
                            style: SeenlyText.serif(
                                italic: true, size: 12, color: SeenlyPalette.paper.withOpacity(0.9)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
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
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: card,
      ),
    );
  }
}

/// One poster-forward card in the grid below the hero — art does most of
/// the work here (recognizing a cover is faster than reading a title),
/// with the match % as a small badge over the poster's corner rather than
/// a full row of its own, and the reasoning line (when it survives
/// [_friendlyReasoning]'s genre-dedup) as a compact caption underneath.
class _GridMatchCard extends StatefulWidget {
  final AiMatch match;
  const _GridMatchCard({required this.match});

  @override
  State<_GridMatchCard> createState() => _GridMatchCardState();
}

class _GridMatchCardState extends State<_GridMatchCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final item = match.item;
    final reasoning = _friendlyReasoning(match.reasoning ?? '');

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: SeenlyPalette.softShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: PosterTile(
                    title: item.title.display,
                    posterUrl: item.posterUrl,
                    fallbackColor: SeenlyPalette.mediaColor(item.mediaType),
                    showLabel: false,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: SeenlyPalette.paper.withOpacity(0.92),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: MatchRing(match: match.match, size: 34),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          item.title.display,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: SeenlyText.cardTitle.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: 2),
        Text(
          item.year != null ? '${item.mediaType} · ${item.year}' : item.mediaType,
          style: SeenlyText.metaLabel.copyWith(fontSize: 10.5),
        ),
        if (item.genres.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final g in item.genres.take(2))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(g, style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.inkMuted)),
                ),
            ],
          ),
        ],
        if (reasoning != null) ...[
          const SizedBox(height: 4),
          Text(
            reasoning,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.serif(italic: true, size: 10, color: SeenlyPalette.inkMuted),
          ),
        ],
      ],
    );

    return GestureDetector(
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
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: card,
      ),
    );
  }
}
