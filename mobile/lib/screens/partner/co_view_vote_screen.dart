import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/co_view_vote_session.dart';
import '../../models/media_item.dart';
import '../../services/co_view_vote_service.dart';
import '../../services/realtime_socket.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/soft_motion.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/together_motion.dart';
import '../../widgets/wow_motion.dart' show BreathingGlow, Entrance, Breathe, PressScale;
import '../decide/decide_filters_screen.dart' show DecideFiltersScreen;
import '../title/title_detail_screen.dart';
import '../../services/app_translations.dart';
import '../../theme/clay_kit.dart';

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
        SnackBar(content: Text("couldn't propose that just now — try again".tr)),
      );
    }
    return null;
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<MediaItem?>(
    MaterialPageRoute(builder: (_) => CoViewVoteScreen(autoStart: true, onRetry: onRetry)),
  );
}

/// One pool a round (or a random draw) can come from — what it's called,
/// what's in it, and the icon/colour it wears on the big setup cards.
class _PoolSourceInfo {
  final String key;
  final String title;
  final String blurb;
  final IconData icon;
  final Color color;
  const _PoolSourceInfo({
    required this.key,
    required this.title,
    required this.blurb,
    required this.icon,
    required this.color,
  });
}

List<_PoolSourceInfo> _poolSourceInfos() => [
      _PoolSourceInfo(
        key: CoViewVotePoolSource.personal,
        title: 'what you each queued'.tr,
        blurb: 'the titles on each of your plan-to-watch shelves'.tr,
        icon: Icons.bookmarks_outlined,
        color: SeenlyPalette.mustard,
      ),
      _PoolSourceInfo(
        key: CoViewVotePoolSource.coview,
        title: 'already agreed together'.tr,
        blurb: "what's already on your shared list".tr,
        icon: Icons.favorite_border_rounded,
        color: SeenlyPalette.pink,
      ),
      _PoolSourceInfo(
        key: CoViewVotePoolSource.both,
        title: 'both of those'.tr,
        blurb: 'your shelves and your shared list, together'.tr,
        icon: Icons.layers_outlined,
        color: SeenlyPalette.periwinkle,
      ),
      _PoolSourceInfo(
        key: CoViewVotePoolSource.catalog,
        title: 'everything'.tr,
        blurb: "the whole catalog — even what nobody's queued yet".tr,
        icon: Icons.explore_outlined,
        color: SeenlyPalette.sage,
      ),
    ];

/// One pill row for picking which pool a round (or a random draw) comes
/// from — the compact form, used inside the "pick for us" sheets on the
/// co-viewing screen. The full-screen setup steps use [PoolSourceCards]
/// instead; both read from the same list of pools, so the options are the
/// same wherever they show up.
class PoolSourcePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const PoolSourcePicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final info in _poolSourceInfos())
          PillChip(label: info.title, active: value == info.key, onTap: () => onChanged(info.key)),
      ],
    );
  }
}

/// The big form of the same choice, for the full-screen setup steps: one
/// pool per row, full width, each with its icon, a line on what's in it
/// and a check on the one that's picked. Meant to sit in an `Expanded`
/// (see [PoolSetupLayout]) — the cards then grow to use the height that's
/// there (within limits) instead of leaving it empty; give [cardHeight]
/// to pin them at a fixed height instead (inside a scrolling list).
class PoolSourceCards extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final double? cardHeight;
  const PoolSourceCards({super.key, required this.value, required this.onChanged, this.cardHeight});

  static const _gap = 10.0;
  static const _minCard = 72.0;
  static const _maxCard = 124.0;

  @override
  Widget build(BuildContext context) {
    final infos = _poolSourceInfos();

    Widget cards(double height) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < infos.length; i++) ...[
              if (i > 0) const SizedBox(height: _gap),
              Entrance(
                delay: Duration(milliseconds: 140 + 55 * i),
                duration: const Duration(milliseconds: 460),
                riseBy: 14,
                child: SizedBox(
                  height: height,
                  child: _PoolSourceCard(
                    info: infos[i],
                    selected: value == infos[i].key,
                    onTap: () => onChanged(infos[i].key),
                  ),
                ),
              ),
            ],
          ],
        );

    final fixed = cardHeight;
    if (fixed != null) return cards(fixed);
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.hasBoundedHeight
            ? (constraints.maxHeight - _gap * (infos.length - 1)) / infos.length
            : 92.0;
        // Scrolls only when even the smallest cards don't fit.
        return SingleChildScrollView(child: cards(room.clamp(_minCard, _maxCard).toDouble()));
      },
    );
  }
}

class _PoolSourceCard extends StatelessWidget {
  final _PoolSourceInfo info;
  final bool selected;
  final VoidCallback onTap;
  const _PoolSourceCard({required this.info, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.985,
      haptics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: ClayBoxDecoration(
          color: selected
              ? Color.alphaBlend(SeenlyPalette.accent.withOpacity(0.08), SeenlyPalette.paper)
              : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? SeenlyPalette.accent : SeenlyPalette.border,
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: SeenlyPalette.accent.withOpacity(0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: info.color.withOpacity(0.16), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(info.icon, size: 23, color: info.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shrinks a little rather than cutting a long title off.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(info.title, style: SeenlyText.serif(size: 16.5, weight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    info.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                key: ValueKey<bool>(selected),
                size: 24,
                color: selected ? SeenlyPalette.accent : SeenlyPalette.dashedBorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The top of a pool-setup screen: a soft, gently breathing badge, the
/// title, and an optional line under it. Settles in a beat at a time,
/// like the rest of the setup steps.
class PoolSetupHero extends StatelessWidget {
  final IconData icon;
  final String title;
  final TextStyle? titleStyle;
  final String? subtitle;
  const PoolSetupHero({
    super.key,
    required this.icon,
    required this.title,
    this.titleStyle,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Entrance(
          child: BreathingGlow(
            color: SeenlyPalette.accent,
            size: 62,
            maxOpacity: 0.18,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: SeenlyPalette.accent.withOpacity(0.12), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, size: 26, color: SeenlyPalette.accent),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Entrance(
          delay: const Duration(milliseconds: 60),
          child: Text(title, style: titleStyle ?? SeenlyText.screenTitle),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Entrance(
            delay: const Duration(milliseconds: 110),
            child: Text(
              subtitle!,
              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
            ),
          ),
        ],
      ],
    );
  }
}

/// The whole pool-setup screen body, shared by every step that asks
/// "what should it come from?" (random pick / spin the reel, vote
/// together, vote it out): [hero] on top, an optional [question], the
/// pool cards, and [footer] (the narrow-it-down buttons) underneath.
///
/// On a normal phone the cards stretch to fill whatever height is left
/// between the two — there's no big empty half-screen below a short list.
/// On a very short screen it falls back to a plain scrolling list with
/// fixed-height cards.
class PoolSetupLayout extends StatelessWidget {
  final Widget hero;
  final String? question;
  final String value;
  final ValueChanged<String> onChanged;
  final Widget footer;
  final EdgeInsets padding;
  const PoolSetupLayout({
    super.key,
    required this.hero,
    this.question,
    required this.value,
    required this.onChanged,
    required this.footer,
    this.padding = const EdgeInsets.fromLTRB(22, 10, 22, 22),
  });

  @override
  Widget build(BuildContext context) {
    final q = question == null
        ? null
        : Entrance(
            delay: const Duration(milliseconds: 150),
            child: Text(
              question!,
              style: SeenlyText.serif(italic: true, size: 14.5, color: SeenlyPalette.inkMuted),
            ),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final roomy = constraints.hasBoundedHeight && constraints.maxHeight >= 560;
        if (roomy) {
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                hero,
                const SizedBox(height: 18),
                if (q != null) ...[q, const SizedBox(height: 12)],
                Expanded(child: PoolSourceCards(value: value, onChanged: onChanged)),
                const SizedBox(height: 18),
                footer,
              ],
            ),
          );
        }
        return ListView(
          padding: padding,
          children: [
            hero,
            const SizedBox(height: 18),
            if (q != null) ...[q, const SizedBox(height: 12)],
            PoolSourceCards(value: value, onChanged: onChanged, cardHeight: 88),
            const SizedBox(height: 22),
            footer,
          ],
        );
      },
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
          label: 'narrow it down first'.tr,
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
  RealtimeSocket<CoViewVoteSession>? _socket;
  StreamSubscription<CoViewVoteSession>? _socketSub;
  String? _errorMessage;
  int _matchPulseTick = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) _start();
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _socket?.close();
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
      _startWatching();
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
      _startWatching();
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
                SnackBar(content: Text("nothing matches that in this pool — try loosening it up".tr)),
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

  void _startWatching() {
    _socketSub?.cancel();
    _socket?.close();
    final session = _session;
    if (session == null) return;
    _socket = context.read<AppState>().coViewVote.watch(session.id);
    _socketSub = _socket!.updates.listen(_onSessionUpdate);
  }

  void _onSessionUpdate(CoViewVoteSession updated) {
    final session = _session;
    if (!mounted) return;
    final justMatched = session != null && !session.isDone && updated.isDone && updated.matched;
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
    _socketSub?.cancel();
    _socket?.close();
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
    _socketSub?.cancel();
    _socket?.close();
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
                    icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => _endAndClose(),
                  ),
                  const Spacer(),
                  Text('vote together'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
            Expanded(
              // Each picture of the round (set-up, the deck, the recap, the
              // match) glides into the next instead of cutting.
              child: SoftSwap(
                expand: true,
                alignment: Alignment.topCenter,
                rise: 0.02,
                child: KeyedSubtree(
                  key: ValueKey<String>(_bodyKey()),
                  child: _body(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Which picture [_body] is showing — the swiping phase is really three
  /// (nothing to vote on, the deck, and "you're through it"), so it needs
  /// more than the phase to tell them apart.
  String _bodyKey() {
    if (_phase != _Phase.swiping) return _phase.name;
    final session = _session;
    if (session == null || session.deck.isEmpty) return 'swiping-empty';
    return _myIndex >= session.deck.length ? 'swiping-done' : 'swiping-deck';
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
        return CardShuffleLoader(caption: 'gathering cards…'.tr);
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
            title: 'nothing there to vote on yet'.tr,
            subtitle: _emptyHint(session.poolSource),
            buttonLabel: 'close'.tr,
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
            Positioned(
              top: 60,
              child: IgnorePointer(
                child: MatchBeat(
                  tick: _matchPulseTick,
                  headline: session.isCompany ? 'everyone said yes'.tr : 'you both said yes'.tr,
                ),
              ),
            ),
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
    final othersTotal = deck.length * (others > 1 ? others : 1);
    final otherProgressLabel = others > 1
        ? 'others: $partnerDecided of $othersTotal'
        : 'them: $partnerDecided of ${deck.length}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Both pills fill like a tide as their owners work through
              // the same deck: you can watch the other side catch up.
              DeckPill('$remaining ${'left'.tr}', progress: index / deck.length),
              DeckPill(otherProgressLabel, progress: partnerDecided / othersTotal),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                String keyOf(int i) => '${deck[i].source}:${deck[i].id}';
                return DeckStack(
                  index: index,
                  count: deck.length,
                  keyOf: keyOf,
                  // The top, draggable card — releasing far enough either
                  // way commits the same decision as tapping a button
                  // below. Same tape-pinned paper look as Watch Together's
                  // own deck (kept as its own small copy of the face so
                  // this screen doesn't reach into that one's privates),
                  // and the same shared deck behaviour.
                  topBuilder: (i) => SwipeableCard(
                    key: ValueKey<String>(keyOf(i)),
                    yes: SwipeSide(
                      icon: Icons.favorite,
                      label: 'yes'.tr,
                      color: SeenlyPalette.accent,
                    ),
                    no: SwipeSide(
                      icon: Icons.close,
                      label: 'not this one'.tr,
                      color: SeenlyPalette.inkMuted,
                    ),
                    onDecide: (decision) => onDecide(deck[i], decision),
                    child: _VoteCardFace(
                      item: deck[i],
                      maxWidth: constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                      elevated: true,
                    ),
                  ),
                  backBuilder: (i) => _VoteCardFace(
                    item: deck[i],
                    maxWidth: constraints.maxWidth,
                    maxHeight: constraints.maxHeight,
                  ),
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
              DecisionButton(
                icon: Icons.close,
                label: 'not this one'.tr,
                iconColor: SeenlyPalette.inkMuted,
                background: SeenlyPalette.paper,
                bordered: true,
                onTap: () => onDecide(current, false),
              ),
              DecisionButton(
                icon: Icons.favorite,
                label: 'yes, this'.tr,
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

  static final _colors = [
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

/// Landed on the same title — the whole point of the round. Already on
/// the shared co-viewing list by the time this shows (see cast_vote), so
/// this is just the little celebration and a way out: a heart that beats
/// and opens with a shower of hearts, the winning poster set down on the
/// table, the words arriving one after another.
class _MatchedView extends StatelessWidget {
  final MediaItem? winner;
  final bool isCompany;
  final VoidCallback onDone;

  const _MatchedView({required this.winner, required this.isCompany, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final w = winner;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
      children: [
        const SizedBox(
          height: 110,
          child: Center(
            child: HeartsBurst(reach: 0.6, child: HeartbeatIcon(size: 36)),
          ),
        ),
        Entrance(
          delay: const Duration(milliseconds: 120),
          riseBy: 12,
          child: Text('settled, together'.tr, style: SeenlyText.screenTitle),
        ),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 200),
          riseBy: 12,
          child: Text(
            isCompany
                ? "everyone said yes — it's on your planned together list now.".tr
                : "you both said yes — it's on your planned together list now.".tr,
            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
          ),
        ),
        if (w != null) ...[
          const SizedBox(height: 22),
          SettleIn(
            child: SizedBox(
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
          ),
        ],
        const SizedBox(height: 26),
        Entrance(
          delay: const Duration(milliseconds: 520),
          riseBy: 12,
          child: PrimaryButton(label: 'nice'.tr, onTap: onDone, expand: false),
        ),
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
    final status = partnerDone
        ? "no match this round — try again, or just pick for us.".tr
        : others > 1
            ? '${'waiting on the others to finish voting'.tr} ($partnerDecidedCount ${'of'.tr} $othersTotal) — '
                "${'this updates the moment they catch up.'.tr}"
            : '${'waiting on them to finish voting'.tr} ($partnerDecidedCount ${'of'.tr} $deckSize) — '
                "${'this updates the moment they catch up.'.tr}";
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
      children: [
        SizedBox(
          height: 110,
          child: Center(
            // Still waiting: a heart with rings spreading from it, like a
            // signal sent out and not yet answered. Everyone in and no
            // match: the quiet moon.
            child: SoftSwap(
              alignment: Alignment.center,
              duration: const Duration(milliseconds: 420),
              child: partnerDone
                  ? Breathe(
                      key: const ValueKey<String>('done'),
                      child: Icon(Icons.nights_stay_outlined, size: 30, color: SeenlyPalette.accent),
                    )
                  : const WaitingRipples(key: ValueKey<String>('waiting'), size: 104),
            ),
          ),
        ),
        Entrance(
          delay: const Duration(milliseconds: 120),
          riseBy: 12,
          child: Text("you're through the deck".tr, style: SeenlyText.screenTitle),
        ),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 180),
          riseBy: 12,
          child: SoftSwap(
            child: Text(
              status,
              key: ValueKey<String>(status),
              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
            ),
          ),
        ),
        if (!partnerDone && othersTotal > 0) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: DeckPill(
              '$partnerDecidedCount ${'of'.tr} $othersTotal',
              progress: partnerDecidedCount / othersTotal,
            ),
          ),
        ],
        const SizedBox(height: 26),
        Entrance(
          delay: const Duration(milliseconds: 300),
          riseBy: 12,
          child: Column(
            children: [
              PrimaryButton(label: 'vote again'.tr, onTap: onStartOver),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onClose,
                child: Text('close'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
              ),
            ],
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
    return PoolSetupLayout(
      hero: PoolSetupHero(icon: Icons.how_to_vote_outlined, title: 'vote together'.tr),
      question: "what should the deck come from?".tr,
      value: source,
      onChanged: onSourceChanged,
      footer: Entrance(
        delay: const Duration(milliseconds: 300),
        riseBy: 12,
        child: NarrowDownPrompt(onNarrowDown: onNarrowDown, onTakeItAll: onStart),
      ),
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
        child: Entrance(
          riseBy: 14,
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
      ),
    );
  }
}
