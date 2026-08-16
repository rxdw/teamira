import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/wow_motion.dart';
import '../shell/root_shell.dart';
import '../title/title_detail_screen.dart';
import '../../services/app_translations.dart';

/// Solo version of the Watch Together vote deck — same swipe language
/// (left to pass, right to keep) but with nobody else's decisions to
/// wait on: every swipe resolves immediately, right just means "plan to
/// watch" (`POST /feed/react` with "like") instead of a match, and left
/// means "skip" (a no-op on the server, same as the co-view deck's own
/// "not this one"). See co_view_vote_screen.dart's `_VoteDeck` for the
/// two-person shape this is adapted from.
class DecideSwipeScreen extends StatefulWidget {
  final List<MediaItem> pool;
  const DecideSwipeScreen({super.key, required this.pool});

  @override
  State<DecideSwipeScreen> createState() => _DecideSwipeScreenState();
}

class _DecideSwipeScreenState extends State<DecideSwipeScreen> {
  late List<MediaItem> _deck = [...widget.pool]..shuffle();
  int _index = 0;
  int _added = 0;
  int _skipped = 0;

  void _decide(MediaItem item, bool keep) {
    final app = context.read<AppState>();
    unawaited(app.feed.react(item, keep ? 'like' : 'skip').catchError((_) {}));
    setState(() {
      _index += 1;
      if (keep) {
        _added += 1;
      } else {
        _skipped += 1;
      }
    });
    if (keep) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('added to plan to watch'.tr), duration: Duration(milliseconds: 900)),
      );
    }
  }

  void _restart() {
    setState(() {
      _deck = [...widget.pool]..shuffle();
      _index = 0;
      _added = 0;
      _skipped = 0;
    });
  }

  void _goToPlanToWatch() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    RootShell.switchTab(context, RootShell.profileTab);
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
                    decoration: const BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('swipe through'.tr, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: _index >= _deck.length
                  ? _RecapView(
                      added: _added,
                      skipped: _skipped,
                      onRestart: _restart,
                      onOpenPlan: _goToPlanToWatch,
                      onDone: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    )
                  : _SwipeDeck(deck: _deck, index: _index, onDecide: _decide),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeDeck extends StatelessWidget {
  final List<MediaItem> deck;
  final int index;
  final void Function(MediaItem item, bool keep) onDecide;

  const _SwipeDeck({required this.deck, required this.index, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    final remaining = deck.length - index;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _CountPill(remaining == 1 ? 'one left' : '$remaining left'),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxIndex = (index + 2).clamp(0, deck.length - 1);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = maxIndex; i >= index; i--)
                      Transform.translate(
                        offset: Offset(
                          (i - index) * ((i - index).isOdd ? 9.0 : -9.0),
                          (i - index) * 9.0,
                        ),
                        child: Transform.scale(
                          scale: 1 - (i - index) * 0.045,
                          child: i == index
                              ? _SwipeCard(
                                  key: ValueKey('${deck[i].source}:${deck[i].id}:$i'),
                                  item: deck[i],
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight,
                                  onDecide: (keep) => onDecide(deck[i], keep),
                                )
                              : _SwipeCardFace(
                                  item: deck[i],
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight,
                                  rotation: (i - index).isOdd ? 0.035 : -0.035,
                                ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _DecisionButton(
                icon: Icons.close,
                label: 'skip',
                iconColor: SeenlyPalette.inkMuted,
                background: SeenlyPalette.paper,
                bordered: true,
                onTap: () => onDecide(deck[index], false),
              ),
              _DecisionButton(
                icon: Icons.bookmark_add_outlined,
                label: 'plan to watch',
                iconColor: SeenlyPalette.accentOnAccent,
                background: SeenlyPalette.accent,
                large: true,
                onTap: () => onDecide(deck[index], true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwipeCard extends StatelessWidget {
  final MediaItem item;
  final double maxWidth;
  final double maxHeight;
  final ValueChanged<bool> onDecide;

  const _SwipeCard({
    super.key,
    required this.item,
    required this.maxWidth,
    required this.maxHeight,
    required this.onDecide,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.horizontal,
      onDismissed: (direction) => onDecide(direction == DismissDirection.startToEnd),
      background: _SwipeHint(
        alignment: Alignment.centerLeft,
        icon: Icons.bookmark_add_outlined,
        label: 'plan to watch',
        color: SeenlyPalette.accent,
      ),
      secondaryBackground: _SwipeHint(
        alignment: Alignment.centerRight,
        icon: Icons.close,
        label: 'skip',
        color: SeenlyPalette.inkMuted,
      ),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TitleDetailScreen(
              mediaId: item.id,
              source: item.source,
              mediaType: item.mediaType,
              seedTitle: item.title.display,
              seedPosterUrl: item.posterUrl,
            ),
          ),
        ),
        child: _SwipeCardFace(item: item, maxWidth: maxWidth, maxHeight: maxHeight, elevated: true),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;
  final Color color;

  const _SwipeHint({required this.alignment, required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: SeenlyPalette.ink.withOpacity(0.14), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), shape: BoxShape.circle),
            child: Icon(icon, color: SeenlyPalette.paper, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SwipeCardFace extends StatelessWidget {
  final MediaItem item;
  final double maxWidth;
  final double maxHeight;
  final bool elevated;
  final double rotation;

  const _SwipeCardFace({
    required this.item,
    required this.maxWidth,
    required this.maxHeight,
    this.elevated = false,
    this.rotation = 0,
  });

  IconData _iconFor(String mediaType) {
    switch (mediaType) {
      case 'movie':
        return Icons.local_movies_outlined;
      case 'series':
        return Icons.tv_outlined;
      case 'anime':
        return Icons.auto_awesome_outlined;
      case 'book':
        return Icons.menu_book_outlined;
      case 'manga':
        return Icons.import_contacts_outlined;
      case 'game':
        return Icons.sports_esports_outlined;
      default:
        return Icons.movie_filter_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.mediaColor(item.mediaType);
    final meta = [item.mediaType, if (item.year != null) '${item.year}'].join(' · ');

    final card = Container(
      width: maxWidth,
      height: maxHeight,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: SeenlyPalette.border),
        boxShadow: elevated
            ? [
                BoxShadow(color: SeenlyPalette.ink.withOpacity(0.16), blurRadius: 26, offset: const Offset(0, 14)),
                BoxShadow(color: SeenlyPalette.ink.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2)),
              ]
            : [
                BoxShadow(color: SeenlyPalette.ink.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 5)),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: item.posterUrl != null && item.posterUrl!.isNotEmpty
                  ? Image.network(
                      item.posterUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: color),
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : Container(color: color),
                    )
                  : Container(
                      color: color,
                      alignment: Alignment.center,
                      child: Icon(_iconFor(item.mediaType), size: 40, color: SeenlyPalette.paper.withOpacity(0.7)),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(item.title.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(italic: true, size: 17)),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Text(meta, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            ],
          ),
        ],
      ),
    );

    return rotation == 0 ? card : Transform.rotate(angle: rotation, child: card);
  }
}

class _DecisionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color background;
  final bool bordered;
  final bool large;
  final VoidCallback onTap;

  const _DecisionButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.background,
    required this.onTap,
    this.bordered = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 52.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PressScale(
          onTap: onTap,
          scaleTo: 0.9,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: bordered ? Border.all(color: SeenlyPalette.border) : null,
              boxShadow: [
                BoxShadow(color: SeenlyPalette.ink.withOpacity(0.1), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(icon, color: iconColor, size: large ? 26 : 20),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  final String text;
  const _CountPill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
    );
  }
}

class _RecapView extends StatelessWidget {
  final int added;
  final int skipped;
  final VoidCallback onRestart;
  final VoidCallback onOpenPlan;
  final VoidCallback onDone;

  const _RecapView({
    required this.added,
    required this.skipped,
    required this.onRestart,
    required this.onOpenPlan,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_florist_outlined, size: 34, color: SeenlyPalette.accent),
            const SizedBox(height: 14),
            Text('that\'s the whole pile'.tr, style: SeenlyText.serif(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              added == 0
                  ? 'nothing kept this round — try loosening the filters'
                  : '$added ${added == 1 ? 'title' : 'titles'} added to plan to watch · $skipped skipped',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 26),
            if (added > 0) ...[
              PrimaryButton(label: 'open plan to watch', onTap: onOpenPlan),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: _OutlineButton(label: 'swipe again', onTap: onRestart),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OutlineButton(label: 'done', onTap: onDone),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SeenlyPalette.border),
        ),
        alignment: Alignment.center,
        child: Text(label, style: SeenlyText.mono(size: 11, color: SeenlyPalette.ink)),
      ),
    );
  }
}
