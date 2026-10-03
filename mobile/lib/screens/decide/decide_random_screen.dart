import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/decide_motion.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/soft_motion.dart';
import '../../widgets/together_motion.dart' show SettleIn;
import '../../widgets/wow_motion.dart';
import '../title/title_detail_screen.dart';
import '../../services/app_translations.dart';
import '../../widgets/saved_celebration.dart';

/// One decision method from [DecideMethodScreen] — draws a single item
/// from the filtered [pool] and shows it big, with a reroll and a quick
/// "plan to watch" action alongside opening the title itself. Same
/// picking logic the old Home random-pick card used, just full-screen
/// and scoped to whatever pool the filters step already narrowed down.
///
/// Built to feel like a real reveal rather than a poster floating on
/// empty paper: a soft color wash sits behind the poster, a rating
/// badge rides its corner, and the year/runtime/rating/genres/synopsis
/// the item actually has fill out underneath — the same meta lines and
/// genre tags the title's own movie card uses — whatever's missing (no
/// rating, no genres, no synopsis) just quietly isn't shown, no
/// placeholder dashes.
///
/// Reused as-is for co-viewing's own "random pick" (see
/// co_view_pick_screens.dart) via [onSecondary] — passing it swaps the
/// secondary button from "plan to watch" (adds straight to this
/// account's own shelf) to whatever the caller needs, e.g. proposing
/// the pick to the whole circle for a vote instead. Everything else —
/// the reveal, the reroll, opening the title — stays identical between
/// the two.
class DecideRandomScreen extends StatefulWidget {
  final List<MediaItem> pool;
  // Overrides the secondary button's action and copy. Returning a
  // non-null MediaItem pops this whole screen with that value (for
  // co-viewing's propose-and-vote flow, once the circle's agreed);
  // returning null just marks the button "done" without leaving, same
  // as the default "added" state. Left null for the solo entry, which
  // keeps its own straight-to-my-shelf behavior untouched.
  final Future<MediaItem?> Function(BuildContext context, MediaItem item)? onSecondary;
  final String secondaryLabel;
  final String secondaryDoneLabel;
  final IconData secondaryIcon;
  final IconData secondaryDoneIcon;
  // False when the pool is already the person's own plan-to-watch shelf
  // (the profile's "random" uses this same screen): there's nothing to
  // "plan" about a title that's already planned, so the reroll button just
  // takes the whole row.
  final bool showSecondary;

  const DecideRandomScreen({
    super.key,
    required this.pool,
    this.showSecondary = true,
    this.onSecondary,
    this.secondaryLabel = 'plan to watch',
    this.secondaryDoneLabel = 'added',
    this.secondaryIcon = Icons.bookmark_add_outlined,
    this.secondaryDoneIcon = Icons.bookmark,
  });

  @override
  State<DecideRandomScreen> createState() => _DecideRandomScreenState();
}

class _DecideRandomScreenState extends State<DecideRandomScreen> {
  late MediaItem _pick = widget.pool[math.Random().nextInt(widget.pool.length)];
  bool _addingToPlan = false;
  bool _addedToPlan = false;
  // Bumped on every reroll so the poster/details block below can key off
  // it and replay its entrance instead of just silently swapping content.
  int _revealGeneration = 0;
  // Bumped on every reroll too — the die on the button gives one roll each
  // time.
  int _rerollTick = 0;

  // The pool comes straight from the feed (see DecideFiltersScreen), and
  // feed-sourced MediaItems never carry runtime/certification — those
  // only ever arrive via MediaService.detail() (see MediaItem's own field
  // comments). So each pick is enriched lazily, one at a time, rather
  // than paying for a full detail fetch on the whole pool up front. Keyed
  // by id so a reroll back to an already-seen pick doesn't refetch.
  final Map<String, MediaItem> _detailCache = {};

  @override
  void initState() {
    super.initState();
    _fetchDetail(_pick);
  }

  Future<void> _fetchDetail(MediaItem pick) async {
    if (_detailCache.containsKey(pick.id)) return;
    try {
      final detail = await context.read<AppState>().media.detail(
            mediaId: pick.id,
            mediaType: pick.mediaType,
            source: pick.source,
          );
      if (!mounted || detail == null) return;
      setState(() => _detailCache[pick.id] = detail.item);
    } catch (_) {
      // Quietly keep showing the thin pool item — same "degrade, don't
      // fail" convention MediaService.detail() itself follows.
    }
  }

  // The enriched item once its detail fetch lands, the plain pool item
  // until then (or if the fetch never comes back).
  MediaItem get _displayPick => _detailCache[_pick.id] ?? _pick;

  void _reroll() {
    if (widget.pool.length < 2) return;
    final current = _pick;
    MediaItem next;
    do {
      next = widget.pool[math.Random().nextInt(widget.pool.length)];
    } while (identical(next, current));
    setState(() {
      _pick = next;
      _addedToPlan = false;
      _revealGeneration++;
      _rerollTick++;
    });
    _fetchDetail(next);
  }

  Future<void> _addToPlan() async {
    if (_addingToPlan || _addedToPlan) return;
    setState(() => _addingToPlan = true);
    if (widget.onSecondary != null) {
      final winner = await widget.onSecondary!(context, _pick);
      if (!mounted) return;
      if (winner != null) {
        Navigator.of(context).pop(winner);
        return;
      }
      setState(() => _addingToPlan = false);
      return;
    }
    try {
      await context.read<AppState>().feed.react(_pick, 'like');
      if (!mounted) return;
      setState(() {
        _addingToPlan = false;
        _addedToPlan = true;
      });
      showSavedCelebration(
        context,
        kind: SavedKind.planned,
        title: _pick.title.display,
        posterUrl: _pick.posterUrl,
        mediaType: _pick.mediaType,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingToPlan = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('couldn\'t add that just now — try again'.tr)),
      );
    }
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TitleDetailScreen(
          mediaId: _pick.id,
          source: _pick.source,
          mediaType: _pick.mediaType,
          seedTitle: _pick.title.display,
          seedPosterUrl: _pick.posterUrl,
        ),
      ),
    );
  }

  IconData _typeIcon(String mediaType) {
    switch (mediaType) {
      case 'movie':
        return Icons.local_movies_outlined;
      case 'series':
        return Icons.live_tv_outlined;
      case 'anime':
        return Icons.auto_awesome_outlined;
      case 'manga':
        return Icons.import_contacts_outlined;
      case 'book':
        return Icons.menu_book_outlined;
      case 'game':
        return Icons.sports_esports_outlined;
      default:
        return Icons.casino_outlined;
    }
  }

  // Same fields, same order, same widget as the title's own movie-card
  // header (see _HeaderTitleBlock in title_detail_screen.dart) — year,
  // then runtime (skipped for books, same as there), then rating.
  List<Widget> _metaLines(MediaItem pick) {
    return [
      if (pick.year != null)
        MetaLine(icon: Icons.calendar_today_outlined, label: '${pick.year}'),
      if (pick.runtimeMinutes != null && pick.mediaType != 'book')
        MetaLine(icon: Icons.schedule_outlined, label: '${pick.runtimeMinutes} ${'min'.tr}'),
      if (pick.rating != null)
        MetaLine(
          icon: Icons.star_rounded,
          label: pick.rating!.toStringAsFixed(1),
          iconColor: SeenlyPalette.accent,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pick = _displayPick;
    final color = SeenlyPalette.mediaColor(pick.mediaType);
    final description = pick.description.display;
    final hasDescription = description.trim().isNotEmpty && description != '—';

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
                    decoration: BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('random pick'.tr, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              // Rerolling: the old pick fades away while the new one is
              // dealt in (its poster settles from a little smaller and
              // tilted), instead of the whole block being swapped in place.
              child: SoftSwap(
                expand: true,
                alignment: Alignment.topCenter,
                rise: 0.03,
                duration: const Duration(milliseconds: 320),
                child: KeyedSubtree(
                  key: ValueKey<int>(_revealGeneration),
                  child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
                child: Center(
                  child: Entrance(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SettleIn(
                          duration: const Duration(milliseconds: 520),
                          fade: false,
                          child: _GlowingPoster(pick: pick, color: color, onTap: _open, typeIcon: _typeIcon(pick.mediaType)),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          pick.title.display,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(size: 23, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        // Same year/runtime/rating meta lines and genre
                        // tags as the title's own movie card (see
                        // MetaLine/GenreTagsFlow in small_pieces.dart), so
                        // a pick here reads exactly like it does once
                        // opened, not a different chip style just for
                        // this screen.
                        for (final line in _metaLines(pick)) line,
                        if (pick.genres.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: GenreTagsFlow(genres: pick.genres.take(4).toList()),
                          ),
                        ],
                        if (hasDescription) ...[
                          const SizedBox(height: 18),
                          Text(
                            description,
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.serif(size: 13.5, color: SeenlyPalette.inkMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryActionButton(
                          // A die that gives one roll each time.
                          leading: DiceGlyph(size: 18, color: SeenlyPalette.ink, rollTick: _rerollTick),
                          label: 'reroll'.tr,
                          onTap: widget.pool.length > 1 ? _reroll : null,
                          haptics: true,
                        ),
                      ),
                      if (widget.showSecondary) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: SecondaryActionButton(
                            icon: _addedToPlan ? widget.secondaryDoneIcon : widget.secondaryIcon,
                            label: _addedToPlan ? widget.secondaryDoneLabel : widget.secondaryLabel,
                            onTap: _addedToPlan ? null : _addToPlan,
                            loading: _addingToPlan,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  PrimaryButton(label: 'open'.tr, onTap: _open),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The poster, sized to actually anchor the screen, sitting on a soft
/// color-washed halo tuned to this title's media-type color and topped
/// with a floating rating badge — the same "reveal" weight a poster
/// gets on the title detail screen itself, not a small thumbnail lost
/// in the middle of a lot of empty paper.
class _GlowingPoster extends StatelessWidget {
  final MediaItem pick;
  final Color color;
  final VoidCallback onTap;
  final IconData typeIcon;

  const _GlowingPoster({required this.pick, required this.color, required this.onTap, required this.typeIcon});

  static const double _width = 236;
  static const double _height = 354;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.97,
      child: SizedBox(
        width: _width + 60,
        height: _height + 60,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient wash behind the poster — turns a flat "poster on
            // background" into something that feels like it's actually
            // lit, tinted to the title's own media-type color.
            IgnorePointer(
              child: Container(
                width: _width + 60,
                height: _height + 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [color.withOpacity(0.22), color.withOpacity(0)],
                  ),
                ),
              ),
            ),
            Container(
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: SeenlyPalette.border),
                boxShadow: [
                  BoxShadow(color: SeenlyPalette.ink.withOpacity(0.16), blurRadius: 32, offset: const Offset(0, 16)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: pick.posterUrl != null && pick.posterUrl!.isNotEmpty
                  ? FadeInNetworkImage(
                      url: pick.posterUrl!,
                      placeholder: Container(
                        color: color,
                        alignment: Alignment.center,
                        child: Icon(typeIcon, size: 64, color: SeenlyPalette.paper.withOpacity(0.7)),
                      ),
                    )
                  : Container(
                      color: color,
                      alignment: Alignment.center,
                      child: Icon(typeIcon, size: 64, color: SeenlyPalette.paper.withOpacity(0.7)),
                    ),
            ),
            if (pick.rating != null)
              Positioned(
                right: 26,
                top: 26,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.ink.withOpacity(0.82),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 14, color: SeenlyPalette.mustard),
                      const SizedBox(width: 3),
                      Text(
                        pick.rating!.toStringAsFixed(1),
                        style: SeenlyText.mono(size: 12, color: SeenlyPalette.paper, weight: FontWeight.w600),
                      ),
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
