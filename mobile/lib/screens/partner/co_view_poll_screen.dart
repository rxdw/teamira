import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/co_view_poll_session.dart';
import '../../models/media_item.dart';
import '../../services/co_view_vote_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/wow_motion.dart' show Entrance, PressScale;
import '../decide/decide_filters_screen.dart' show DecideFiltersScreen;
import 'co_view_vote_screen.dart' show NarrowDownPrompt, PoolSourcePicker;
import '../../services/app_translations.dart';

const _pollInterval = Duration(seconds: 2);
const _tickInterval = Duration(seconds: 1);

enum _Phase { setup, starting, voting, done, error }

/// The "vote it out" can't-decide method — a small shortlist, everyone
/// in the circle votes on it together on a countdown, and whichever has
/// strictly the most votes when time's up (or once everyone's voted)
/// wins. A tie for the lead doesn't dead-end the round: the backend
/// narrows this exact session down to just the tied leaders and reopens
/// it for a runoff (see backend/app/routers/co_view_poll.py) — this
/// screen doesn't need to know that happened, it just keeps polling and
/// re-renders whatever shortlist and deadline come back.
class CoViewPollScreen extends StatefulWidget {
  const CoViewPollScreen({super.key});

  @override
  State<CoViewPollScreen> createState() => _CoViewPollScreenState();
}

class _CoViewPollScreenState extends State<CoViewPollScreen> {
  _Phase _phase = _Phase.setup;
  String _source = CoViewVotePoolSource.personal;
  CoViewPollSession? _session;
  String? _errorMessage;
  Timer? _pollTimer;
  Timer? _tickTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.starting;
      _errorMessage = null;
    });
    try {
      final session = await context.read<AppState>().coViewPoll.start(source: _source);
      if (!mounted) return;
      setState(() {
        _session = session;
        _phase = session.isDone ? _Phase.done : _Phase.voting;
      });
      if (!session.isDone) _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "couldn't start a vote just now — try again";
        _phase = _Phase.error;
      });
    }
  }

  /// Same as [_start], but for a poll seeded from a client-filtered pool
  /// (type/genre/year narrowed down first — see DecideFiltersScreen)
  /// instead of one built server-side straight from [_source].
  Future<void> _startFiltered(List<MediaItem> pool) async {
    setState(() {
      _phase = _Phase.starting;
      _errorMessage = null;
    });
    try {
      final session = await context.read<AppState>().coViewPoll.propose(pool);
      if (!mounted) return;
      setState(() {
        _session = session;
        _phase = session.isDone ? _Phase.done : _Phase.voting;
      });
      if (!session.isDone) _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "couldn't start a vote just now — try again";
        _phase = _Phase.error;
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
            if (pool.length < 2) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text("need at least two titles to vote between — try loosening the filters".tr)),
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
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh());
    _tickTimer?.cancel();
    // Purely for the live countdown text — doesn't touch the network,
    // just forces a rebuild every second so "until HH:MM" (and the
    // deadline's own resolution once it passes) stays current.
    _tickTimer = Timer.periodic(_tickInterval, (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _refresh() async {
    final session = _session;
    if (session == null || !mounted) return;
    try {
      final updated = await context.read<AppState>().coViewPoll.poll(session.id);
      if (!mounted) return;
      setState(() {
        _session = updated;
        if (updated.isDone) {
          _phase = _Phase.done;
          _pollTimer?.cancel();
          _tickTimer?.cancel();
        }
      });
    } catch (_) {
      // A missed poll just tries again on the next tick.
    }
  }

  Future<void> _vote(int index) async {
    final session = _session;
    if (session == null || session.myVote == index) return;
    // Optimistic — shows the tap landing immediately rather than
    // waiting a round trip, same as the swipe screen's own _myIndex bump.
    setState(() {
      _session = CoViewPollSession(
        id: session.id,
        status: session.status,
        poolSource: session.poolSource,
        roundNumber: session.roundNumber,
        deadline: session.deadline,
        candidates: session.candidates,
        voteCounts: [
          for (var i = 0; i < session.voteCounts.length; i++)
            session.voteCounts[i] + (i == index ? 1 : 0) - (i == session.myVote ? 1 : 0),
        ],
        myVote: index,
        votedCount: session.hasVoted ? session.votedCount : session.votedCount + 1,
        memberCount: session.memberCount,
        winner: session.winner,
        createdAt: session.createdAt,
      );
    });
    try {
      final updated = await context.read<AppState>().coViewPoll.vote(session.id, index);
      if (!mounted) return;
      setState(() {
        _session = updated;
        if (updated.isDone) {
          _phase = _Phase.done;
          _pollTimer?.cancel();
          _tickTimer?.cancel();
        }
      });
    } catch (_) {
      if (!mounted) return;
      await _refresh();
    }
  }

  Future<void> _endAndClose() async {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    final session = _session;
    if (session != null && !session.isDone) {
      try {
        await context.read<AppState>().coViewPoll.end(session.id);
      } catch (_) {
        // best-effort
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(session?.winner);
  }

  Future<void> _voteAgain() async {
    final session = _session;
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    if (session != null && !session.isDone) {
      try {
        await context.read<AppState>().coViewPoll.end(session.id);
      } catch (_) {
        // best-effort
      }
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.setup);
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
                  PressScale(
                    onTap: () => _endAndClose(),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    ),
                  ),
                  const Spacer(),
                  Text('vote it out'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(_phase), child: _body()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.setup:
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
          children: [
            Entrance(child: Icon(Icons.how_to_vote_outlined, size: 28, color: SeenlyPalette.accent)),
            const SizedBox(height: 14),
            Entrance(
              delay: const Duration(milliseconds: 60),
              child: Text('vote it out'.tr, style: SeenlyText.screenTitle),
            ),
            const SizedBox(height: 8),
            Entrance(
              delay: const Duration(milliseconds: 110),
              child: Text(
                "a shortlist, a countdown, whoever's got the most votes when time's up — a tie just runs another round between whoever's left.".tr,
                style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
              ),
            ),
            const SizedBox(height: 8),
            Entrance(
              delay: const Duration(milliseconds: 150),
              child: Text(
                "what should the shortlist come from?".tr,
                style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
              ),
            ),
            const SizedBox(height: 18),
            Entrance(
              delay: const Duration(milliseconds: 190),
              child: PoolSourcePicker(value: _source, onChanged: (v) => setState(() => _source = v)),
            ),
            const SizedBox(height: 26),
            Entrance(
              delay: const Duration(milliseconds: 230),
              riseBy: 14,
              child: NarrowDownPrompt(onNarrowDown: _narrowDown, onTakeItAll: _start),
            ),
          ],
        );
      case _Phase.starting:
        return Center(
          child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
        );
      case _Phase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Entrance(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _errorMessage ?? 'something went wrong',
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(italic: true, size: 15, color: SeenlyPalette.inkMuted),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(label: 'try again'.tr, onTap: _start, expand: false),
                ],
              ),
            ),
          ),
        );
      case _Phase.voting:
        final session = _session!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            _PollCard(session: session, onVote: _vote),
            const SizedBox(height: 16),
            Center(
              child: Entrance(
                delay: const Duration(milliseconds: 120),
                riseBy: 10,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    session.isCompany
                        ? '${session.votedCount} of ${session.memberCount} in the circle have voted'
                        : session.votedCount >= 2
                            ? 'everyone has voted'
                            : session.hasVoted
                                ? 'waiting on the others'
                                : "you haven't voted yet",
                    key: ValueKey('${session.votedCount}-${session.hasVoted}'),
                    style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                  ),
                ),
              ),
            ),
          ],
        );
      case _Phase.done:
        final session = _session!;
        final winner = session.winner;
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 24),
          children: [
            Entrance(child: Icon(Icons.check_circle_outline, size: 30, color: SeenlyPalette.accent)),
            const SizedBox(height: 14),
            Entrance(
              delay: const Duration(milliseconds: 60),
              child: Text(winner != null ? "it's decided" : 'round closed', style: SeenlyText.screenTitle),
            ),
            const SizedBox(height: 8),
            if (winner != null) ...[
              Entrance(
                delay: const Duration(milliseconds: 110),
                child: Text(
                  "put on the shared list for tonight.".tr,
                  style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
                ),
              ),
              const SizedBox(height: 20),
              Entrance(
                delay: const Duration(milliseconds: 150),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 74,
                      child: ThemedPosterTile(
                        title: winner.title.display,
                        posterUrl: winner.posterUrl,
                        mediaType: winner.mediaType,
                        fallbackColor: SeenlyPalette.mediaColor(winner.mediaType),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(winner.title.display, style: SeenlyText.serif(size: 16, italic: true, weight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(winner.mediaType, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              Entrance(
                delay: const Duration(milliseconds: 110),
                child: Text(
                  'nobody voted before time ran out.'.tr,
                  style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
                ),
              ),
            const SizedBox(height: 26),
            Entrance(
              delay: const Duration(milliseconds: 200),
              riseBy: 14,
              child: PrimaryButton(label: 'done'.tr, onTap: () => Navigator.of(context).pop(winner)),
            ),
            const SizedBox(height: 10),
            Center(
              child: PressScale(
                onTap: _voteAgain,
                child: Text('vote on something else'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
              ),
            ),
          ],
        );
    }
  }
}

/// The dark countdown card — shortlist candidates in a row, each with a
/// poster, name, and a live vote-count pill; tap one to cast (or change)
/// your vote. Scrolls horizontally past two candidates instead of
/// squeezing a 4-wide shortlist down to illegibility.
class _PollCard extends StatelessWidget {
  final CoViewPollSession session;
  final ValueChanged<int> onVote;
  const _PollCard({required this.session, required this.onVote});

  String _deadlineLabel() {
    final left = session.timeLeft;
    if (left == Duration.zero) return 'wrapping up…'.tr;
    final local = session.deadline.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${'voting until'.tr} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final candidates = session.candidates;
    return Entrance(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: SeenlyPalette.ink,
          borderRadius: BorderRadius.circular(22),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _deadlineLabel(),
                  style: SeenlyText.serif(size: 17, weight: FontWeight.w600, color: SeenlyPalette.paper),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: session.roundNumber > 1
                      ? Container(
                          key: ValueKey(session.roundNumber),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.paper.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${'runoff · round'.tr} ${session.roundNumber}',
                            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.paper.withOpacity(0.8)),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('no-round')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              children: [
                for (var i = 0; i < candidates.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _CandidateTile(
                    item: candidates[i],
                    votes: session.votesFor(i),
                    selected: session.myVote == i,
                    onTap: () => onVote(i),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final MediaItem item;
  final int votes;
  final bool selected;
  final VoidCallback onTap;

  const _CandidateTile({
    required this.item,
    required this.votes,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      haptics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SeenlyPalette.accent : Colors.white.withOpacity(0.08),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ThemedPosterTile(
                    title: item.title.display,
                    posterUrl: item.posterUrl,
                    mediaType: item.mediaType,
                    fallbackColor: SeenlyPalette.mediaColor(item.mediaType),
                    onTap: onTap,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title.display,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(size: 14.5, weight: FontWeight.w600, color: SeenlyPalette.paper),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? SeenlyPalette.accent.withOpacity(0.22)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  ruCount(votes, one: 'голос', few: 'голоса', many: 'голосов', englishOne: 'vote', englishOther: 'votes'),
                  key: ValueKey(votes),
                  style: SeenlyText.mono(
                    size: 12,
                    weight: FontWeight.w600,
                    color: selected ? SeenlyPalette.accent : SeenlyPalette.paper.withOpacity(0.85),
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
