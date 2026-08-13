import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/co_view_vote_session.dart';
import '../../models/media_item.dart';
import '../../services/co_view_vote_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_poster_tile.dart';
import '../decide/decide_filters_screen.dart' show DecideFiltersScreen;
import '../title/title_detail_screen.dart';

const _pollInterval = Duration(seconds: 2);

enum _Phase { setup, starting, swiping, matched, recap, error }

/// Puts [item] up for the whole circle's yes/no instead of letting
/// whoever picked it (a reel spin, a random draw, teamira's shortlist)
/// add it straight to the shared list on their own — proposes it, then
/// reuses this exact same swipe screen to confirm, since a one-card
/// "does everyone want this" round is just [CoViewVoteScreen]'s normal
/// deck at its smallest. [onRetry] is handed straight to the vote
/// screen (see its own doc) — typically just closing back to whatever
/// picker offered [item], so a "no" can lead to trying a different
/// pick instead of hitting a dead end.
Future<MediaItem?> proposeToCircle(
  BuildContext context,
  MediaItem item, {
  VoidCallback? onRetry,
}) async {
  try {
    await context.read<AppState>().coViewVote.propose([item]);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't propose that just now — try again")),
      );
    }
    return null;
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<MediaItem?>(
    MaterialPageRoute(builder: (_) => CoViewVoteScreen(autoStart: true, onRetry: onRetry)),
  );
}

/// One pill row for picking which pool a round (or a random draw) comes
/// from — shared between this screen's setup step and the "pick for us"
/// sheet on the co-viewing screen, so the options read the same
/// wherever they show up.
class PoolSourcePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const PoolSourcePicker({super.key, required this.value, required this.onChanged});

  static const _options = [
    (CoViewVotePoolSource.personal, 'what you each queued'),
    (CoViewVotePoolSource.coview, 'already agreed together'),
    (CoViewVotePoolSource.both, 'both of those'),
    (CoViewVotePoolSource.catalog, 'everything'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (key, label) in _options)
          PillChip(label: label, active: value == key, onTap: () => onChanged(key)),
      ],
    );
  }
}

/// Second half of "what should it come from?" — once a pool's picked,
/// whether to narrow it down by type/genre/year first (the exact same
/// three-step wizard Home's own solo can't-decide uses — see
/// DecideFiltersScreen) or just take the whole pool as-is. Shared
/// between every entry point that asks the pool-source question, same
/// reasoning as [PoolSourcePicker] itself.
class NarrowDownPrompt extends StatelessWidget {
  final VoidCallback onNarrowDown;
  final VoidCallback onTakeItAll;
  final bool loading;
  const NarrowDownPrompt({
    super.key,
    required this.onNarrowDown,
    required this.onTakeItAll,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: 'narrow it down first',
          onTap: loading ? null : onNarrowDown,
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: loading ? null : onTakeItAll,
          child: Center(
            child: Text(
              loading ? 'loading…' : 'no, just take the whole pool',
              style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.accent).copyWith(
                decoration: TextDecoration.underline,
                decorationColor: SeenlyPalette.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Voting through whichever pool you pick — personal shelves, what's
/// already agreed, or the whole app catalog — see
/// backend/app/routers/co_view_vote.py. No code to join: getting here
/// already means you're linked, so after picking which pool to draw
/// from this starts (or rejoins) a round and polls it the same way
/// Watch Together's own network mode does.
class CoViewVoteScreen extends StatefulWidget {
  // Skips the "what should the deck come from?" setup step and jumps
  // straight into starting/polling a round — for a propose() flow
  // (reel/random/teamira) where there's no pool source to pick, just
  // whichever single-item round the caller already put up. start()'s
  // own "hand back the round already active for this link" behavior
  // does the actual work of landing on it, regardless of what source
  // this call happens to pass along.
  final bool autoStart;
  // Overrides "vote again" (and the recap/error retry buttons) to hand
  // control back to the caller instead of restarting with the same
  // pool source — the right behavior for a propose() round, since
  // "proposed" isn't one of the personal/coview/both/catalog sources
  // start() knows how to rebuild a pool from. Left null for the plain swipe-
  // through entry, which restarts itself exactly as before.
  final VoidCallback? onRetry;

  const CoViewVoteScreen({super.key, this.autoStart = false, this.onRetry});

  @override
  State<CoViewVoteScreen> createState() => _CoViewVoteScreenState();
}

class _CoViewVoteScreenState extends State<CoViewVoteScreen> {
  _Phase _phase = _Phase.setup;
  String _source = CoViewVotePoolSource.personal;
  CoViewVoteSession? _session;
  int _myIndex = 0;
  Timer? _pollTimer;
  String? _errorMessage;
  int _matchPulseTick = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) _start();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.starting;
      _errorMessage = null;
    });
    try {
      final session = await context.read<AppState>().coViewVote.start(source: _source);
      if (!mounted) return;
      setState(() {
        _session = session;
        _source = session.poolSource;
        _myIndex = session.myDecided.length;
        _phase = session.isDone ? _Phase.matched : _Phase.swiping;
      });
      if (session.isDone && session.matched) {
        _matchPulseTick++;
      }
      _startPolling();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = "couldn't start a round — check your connection and try again";
      });
    }
  }

  /// Same as [_start], but for a round seeded from a client-filtered
  /// pool (type/genre/year narrowed down first — see DecideFiltersScreen)
  /// instead of one built server-side straight from [_source]. Reuses
  /// propose() — the deck itself is already decided, this just turns it
  /// into an actual synced round.
  Future<void> _startFiltered(List<MediaItem> pool) async {
    setState(() {
      _phase = _Phase.starting;
      _errorMessage = null;
    });
    try {
      final session = await context.read<AppState>().coViewVote.propose(pool);
      if (!mounted) return;
      setState(() {
        _session = session;
        _source = session.poolSource;
        _myIndex = session.myDecided.length;
        _phase = session.isDone ? _Phase.matched : _Phase.swiping;
      });
      if (session.isDone && session.matched) {
        _matchPulseTick++;
      }
      _startPolling();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = "couldn't start a round — check your connection and try again";
      });
    }
  }

  void _narrowDown() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DecideFiltersScreen(
          poolLoader: () => context.read<AppState>().coViewVote.deck(source: _source),
          persistPrefs: false,
          onFinished: (ctx, pool, filters) {
            if (pool.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text("nothing matches that in this pool — try loosening it up")),
              );
              return;
            }
            Navigator.of(ctx).pop();
            _startFiltered(pool);
          },
        ),
      ),
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null || !mounted) return;
    try {
      final updated = await context.read<AppState>().coViewVote.poll(session.id);
      if (!mounted) return;
      final justMatched = !session.isDone && updated.isDone && updated.matched;
      setState(() {
        _session = updated;
        if (justMatched) {
          _phase = _Phase.matched;
          _matchPulseTick++;
        } else if (updated.isDone && !updated.matched) {
          // The other side ended it from their side.
          _phase = _Phase.recap;
        }
      });
    } catch (_) {
      // A missed poll just tries again on the next tick.
    }
  }

  Future<void> _decide(MediaItem item, bool decision) async {
    final session = _session;
    if (session == null) return;
    setState(() => _myIndex++);
    try {
      final updated = await context.read<AppState>().coViewVote.cast(
            session.id,
            mediaId: item.id,
            source: item.source,
            decision: decision,
          );
      if (!mounted) return;
      setState(() {
        _session = updated;
        if (updated.isDone && updated.matched) {
          _phase = _Phase.matched;
          _matchPulseTick++;
        } else if (_myIndex >= updated.deck.length) {
          _phase = _Phase.recap;
        }
      });
    } catch (_) {
      if (!mounted) return;
      if (_myIndex >= (_session?.deck.length ?? 0)) {
        setState(() => _phase = _Phase.recap);
      }
    }
  }

  Future<void> _endAndClose({bool showSnack = false}) async {
    _pollTimer?.cancel();
    final session = _session;
    if (session != null && !session.isDone) {
      try {
        await context.read<AppState>().coViewVote.end(session.id);
      } catch (_) {
        // best-effort
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(session?.winner);
  }

  Future<void> _startOver() async {
    final session = _session;
    _pollTimer?.cancel();
    if (session != null) {
      try {
        await context.read<AppState>().coViewVote.end(session.id);
      } catch (_) {
        // best-effort
      }
    }
    if (!mounted) return;
    final onRetry = widget.onRetry;
    if (onRetry != null) {
      onRetry();
      return;
    }
    setState(() => _myIndex = 0);
    await _start();
  }

  String _emptyHint(String source) {
    switch (source) {
      case CoViewVotePoolSource.coview:
        return "nothing planned together yet — suggest a few titles first";
      case CoViewVotePoolSource.both:
        return "add a few titles to your plan-to-watch shelves, or plan something together first";
      case CoViewVotePoolSource.catalog:
        return "couldn't load the catalog just now — try again in a moment";
      default:
        return 'add a few titles to your plan-to-watch shelves first, then come back to vote on them';
    }
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
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => _endAndClose(),
                  ),
                  const Spacer(),
                  Text('vote together', style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.setup:
        return _SetupView(
          source: _source,
          onSourceChanged: (v) => setState(() => _source = v),
          onStart: _start,
          onNarrowDown: _narrowDown,
        );
      case _Phase.starting:
        return const Center(
          child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
        );
      case _Phase.error:
        return _MessageView(
          title: _errorMessage ?? 'something went wrong',
          buttonLabel: 'try again',
          onButtonTap: _start,
        );
      case _Phase.swiping:
        final session = _session!;
        if (session.deck.isEmpty) {
          return _MessageView(
            title: 'nothing there to vote on yet',
            subtitle: _emptyHint(session.poolSource),
            buttonLabel: 'close',
            onButtonTap: () => _endAndClose(),
          );
        }
        if (_myIndex >= session.deck.length) {
          return _RecapView(
            partnerDecidedCount: session.partnerDecidedCount,
            deckSize: session.deck.length,
            memberCount: session.memberCount,
            onStartOver: _startOver,
            onClose: () => _endAndClose(),
          );
        }
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            _VoteDeck(
              deck: session.deck,
              index: _myIndex,
              partnerDecided: session.partnerDecidedCount,
              memberCount: session.memberCount,
              onDecide: _decide,
            ),
            Positioned(top: 90, child: _MatchPulse(tick: _matchPulseTick, isCompany: session.isCompany)),
          ],
        );
      case _Phase.matched:
        final winner = _session?.winner;
        return _MatchedView(winner: winner, isCompany: _session?.isCompany ?? false, onDone: () => _endAndClose());
      case _Phase.recap:
        return _RecapView(
          partnerDecidedCount: _session?.partnerDecidedCount ?? 0,
          deckSize: _session?.deck.length ?? 0,
          memberCount: _session?.memberCount ?? 2,
          onStartOver: _startOver,
          onClose: () => _endAndClose(),
        );
    }
  }
}

class _VoteDeck extends StatelessWidget {
  final List<MediaItem> deck;
  final int index;
  final int partnerDecided;
  final int memberCount;
  final void Function(MediaItem item, bool decision) onDecide;

  const _VoteDeck({
    required this.deck,
    required this.index,
    required this.partnerDecided,
    required this.memberCount,
    required this.onDecide,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = deck.length - index;
    final current = deck[index];
    final others = memberCount - 1;
    // A couple has exactly one other voter, so "them: X of Y" tracks
    // one-for-one with the deck. A company has several — the raw count
    // backend sends is every decision from every one of them combined
    // (see CoViewVoteSessionOut.partner_decided_count), so the
    // denominator has to scale by how many others there are too, or
    // "3 of 12" would misleadingly read like nobody's close to done.
    final otherProgressLabel = others > 1
        ? 'others: $partnerDecided of ${deck.length * others}'
        : 'them: $partnerDecided of ${deck.length}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CountPill(remaining == 1 ? 'one left' : '$remaining left'),
              _CountPill(otherProgressLabel),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxIndex = min(index + 2, deck.length - 1);
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
                              ? _VoteCard(
                                  key: ValueKey('${deck[i].source}:${deck[i].id}'),
                                  item: deck[i],
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight,
                                  onDecide: (decision) => onDecide(deck[i], decision),
                                )
                              : _VoteCardFace(
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
              _VoteDecisionButton(
                icon: Icons.close,
                label: 'not this one',
                iconColor: SeenlyPalette.inkMuted,
                background: SeenlyPalette.paper,
                bordered: true,
                onTap: () => onDecide(current, false),
              ),
              _VoteDecisionButton(
                icon: Icons.favorite,
                label: 'yes, this',
                iconColor: SeenlyPalette.accentOnAccent,
                background: SeenlyPalette.accent,
                large: true,
                onTap: () => onDecide(current, true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The top, draggable card — releasing far enough either direction commits
/// the same decision as tapping a button below. Same tape-pinned paper
/// look as Watch Together's own deck, kept as its own small copy here so
/// this screen doesn't reach into that one's private widgets.
class _VoteCard extends StatelessWidget {
  final MediaItem item;
  final double maxWidth;
  final double maxHeight;
  final ValueChanged<bool> onDecide;

  const _VoteCard({
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
      background: _VoteSwipeHint(
        alignment: Alignment.centerLeft,
        icon: Icons.favorite,
        label: 'yes',
        color: SeenlyPalette.accent,
      ),
      secondaryBackground: _VoteSwipeHint(
        alignment: Alignment.centerRight,
        icon: Icons.close,
        label: 'not this one',
        color: SeenlyPalette.inkMuted,
      ),
      child: _VoteCardFace(item: item, maxWidth: maxWidth, maxHeight: maxHeight, elevated: true),
    );
  }
}

class _VoteSwipeHint extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;
  final Color color;

  const _VoteSwipeHint({
    required this.alignment,
    required this.icon,
    required this.label,
    required this.color,
  });

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

class _VoteCardFace extends StatelessWidget {
  final MediaItem item;
  final double maxWidth;
  final double maxHeight;
  final bool elevated;
  final double rotation;

  const _VoteCardFace({
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
      default:
        return Icons.movie_filter_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.mediaColor(item.mediaType);
    final meta = [
      item.mediaType,
      if (item.year != null) '${item.year}',
    ].join(' · ');

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

    final rotated = rotation == 0 ? card : Transform.rotate(angle: rotation, child: card);
    if (!elevated) return rotated;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        rotated,
        Positioned(top: -9, left: maxWidth / 2 - 27, child: _VoteTapeAccent(seed: item.title.display)),
      ],
    );
  }
}

class _VoteTapeAccent extends StatelessWidget {
  final String seed;
  const _VoteTapeAccent({required this.seed});

  static const _colors = [
    SeenlyPalette.tapeRose,
    SeenlyPalette.tapeSage,
    SeenlyPalette.tapeMustard,
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[seed.hashCode.abs() % _colors.length];
    return Transform.rotate(
      angle: -0.08,
      child: Container(
        width: 54,
        height: 20,
        decoration: BoxDecoration(
          color: color.withOpacity(0.88),
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(color: SeenlyPalette.ink.withOpacity(0.10), blurRadius: 5, offset: const Offset(0, 2)),
          ],
        ),
      ),
    );
  }
}

class _VoteDecisionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color background;
  final bool large;
  final bool bordered;
  final VoidCallback onTap;

  const _VoteDecisionButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.background,
    required this.onTap,
    this.large = false,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 52.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: bordered ? Border.all(color: SeenlyPalette.border) : null,
              boxShadow: [
                BoxShadow(color: SeenlyPalette.ink.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(icon, color: iconColor, size: large ? 28 : 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final String label;
  const _CountPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Text(label, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
    );
  }
}

class _MatchPulse extends StatefulWidget {
  final int tick;
  final bool isCompany;
  const _MatchPulse({required this.tick, this.isCompany = false});

  @override
  State<_MatchPulse> createState() => _MatchPulseState();
}

class _MatchPulseState extends State<_MatchPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.08).chain(CurveTween(curve: Curves.easeOutBack)), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95), weight: 20),
  ]).animate(_controller);
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 33),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant _MatchPulse old) {
    super.didUpdateWidget(old);
    if (widget.tick != old.tick && widget.tick > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.isDismissed) return const SizedBox.shrink();
        return Opacity(opacity: _opacity.value, child: Transform.scale(scale: _scale.value, child: child));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: SeenlyPalette.ink.withOpacity(0.16), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite, size: 22, color: SeenlyPalette.accent),
            const SizedBox(height: 6),
            Text(widget.isCompany ? 'everyone said yes' : 'you both said yes',
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Landed on the same title — the whole point of the round. Already on
/// the shared co-viewing list by the time this shows (see cast_vote), so
/// this is just the little celebration and a way out.
class _MatchedView extends StatelessWidget {
  final MediaItem? winner;
  final bool isCompany;
  final VoidCallback onDone;

  const _MatchedView({required this.winner, required this.isCompany, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final w = winner;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 24),
      children: [
        const Icon(Icons.favorite, size: 30, color: SeenlyPalette.accent),
        const SizedBox(height: 14),
        Text('settled, together', style: SeenlyText.screenTitle),
        const SizedBox(height: 8),
        Text(
          isCompany
              ? "everyone said yes — it's on your planned together list now."
              : "you both said yes — it's on your planned together list now.",
          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
        ),
        if (w != null) ...[
          const SizedBox(height: 22),
          SizedBox(
            width: 140,
            child: ThemedPosterTile(
              title: w.title.display,
              posterUrl: w.posterUrl,
              mediaType: w.mediaType,
              fallbackColor: SeenlyPalette.mediaColor(w.mediaType),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TitleDetailScreen(
                    mediaId: w.id,
                    source: w.source,
                    mediaType: w.mediaType,
                    seedTitle: w.title.display,
                    seedPosterUrl: w.posterUrl,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 26),
        PrimaryButton(label: 'nice', onTap: onDone, expand: false),
      ],
    );
  }
}

class _RecapView extends StatelessWidget {
  final int partnerDecidedCount;
  final int deckSize;
  final int memberCount;
  final VoidCallback onStartOver;
  final VoidCallback onClose;

  const _RecapView({
    required this.partnerDecidedCount,
    required this.deckSize,
    required this.memberCount,
    required this.onStartOver,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final others = memberCount - 1;
    // Same scaled-denominator reasoning as _VoteDeck's own pill — a
    // company's partnerDecidedCount is everyone else's decisions
    // combined, so "done" means it's reached deckSize per other
    // member, not just deckSize once.
    final othersTotal = others > 1 ? deckSize * others : deckSize;
    final partnerDone = deckSize > 0 && partnerDecidedCount >= othersTotal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 24),
      children: [
        const Icon(Icons.nights_stay_outlined, size: 30, color: SeenlyPalette.accent),
        const SizedBox(height: 14),
        Text("you're through the deck", style: SeenlyText.screenTitle),
        const SizedBox(height: 8),
        Text(
          partnerDone
              ? "no match this round — try again, or just pick for us."
              : others > 1
                  ? 'waiting on the others to finish voting ($partnerDecidedCount of $othersTotal) — '
                      "this updates the moment they catch up."
                  : 'waiting on them to finish voting ($partnerDecidedCount of $deckSize) — '
                      "this updates the moment they catch up.",
          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
        ),
        const SizedBox(height: 26),
        PrimaryButton(label: 'vote again', onTap: onStartOver),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: onClose,
            child: Text('close', style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
          ),
        ),
      ],
    );
  }
}

class _SetupView extends StatelessWidget {
  final String source;
  final ValueChanged<String> onSourceChanged;
  final VoidCallback onStart;
  final VoidCallback onNarrowDown;

  const _SetupView({
    required this.source,
    required this.onSourceChanged,
    required this.onStart,
    required this.onNarrowDown,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
      children: [
        const Icon(Icons.how_to_vote_outlined, size: 28, color: SeenlyPalette.accent),
        const SizedBox(height: 14),
        Text('vote together', style: SeenlyText.screenTitle),
        const SizedBox(height: 8),
        Text(
          "what should the deck come from?",
          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
        ),
        const SizedBox(height: 18),
        PoolSourcePicker(value: source, onChanged: onSourceChanged),
        const SizedBox(height: 26),
        NarrowDownPrompt(onNarrowDown: onNarrowDown, onTakeItAll: onStart),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String buttonLabel;
  final VoidCallback onButtonTap;

  const _MessageView({
    required this.title,
    this.subtitle,
    required this.buttonLabel,
    required this.onButtonTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center, style: SeenlyText.serif(italic: true, size: 15, color: SeenlyPalette.inkMuted)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center, style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
            ],
            const SizedBox(height: 20),
            PrimaryButton(label: buttonLabel, onTap: onButtonTap, expand: false),
          ],
        ),
      ),
    );
  }
}
