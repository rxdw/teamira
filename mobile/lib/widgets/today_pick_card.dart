import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/today_pick.dart';
import '../screens/collections/collection_full_screen.dart';
import '../services/today_pick_prefs_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';

/// Home's "today's pick" card — a nudge toward one franchise shelf (see
/// backend/app/curated_franchises.py) picked fresh for today, with a thin
/// progress bar for however much of it this account has already watched.
/// One fetch per mount (GET /feed/today-pick, see FeedService.todayPick),
/// same "this card owns its own data" pattern as [_FriendsActivityCard]
/// on this same screen.
///
/// Renders nothing — not even a placeholder — when: the feature's off in
/// Settings, today's pick was already dismissed (see
/// [TodayPickPrefsService]), the fetch is still in flight or failed, or
/// the server had nothing to offer. A quiet miss here should never read
/// as a broken card sitting on Home.
///
/// Tapping "I'm in" marks the pick accepted (see
/// [TodayPickPrefsService.accept]) and opens the franchise shelf. From
/// then on — and any time there's already real progress even before
/// accepting — the card shows a segmented watched/total readout (see
/// [_WatchSegments]) instead of just the invite prompt.
class TodayPickCard extends StatefulWidget {
  const TodayPickCard({super.key});

  @override
  State<TodayPickCard> createState() => _TodayPickCardState();
}

class _TodayPickCardState extends State<TodayPickCard> {
  TodayPick? _pick;
  bool _loaded = false;

  // Drives the dismiss animation — set the moment "not now"/"×" is
  // tapped, well before `TodayPickPrefsService.dismiss` actually
  // finishes writing to SharedPreferences and notifies listeners
  // (which would otherwise make the card vanish on the very next
  // build). `_exiting` fades the card out in place; `_collapsed`
  // (set a beat later, once the fade has actually played) then lets
  // its height animate shut too, so the row it sits in settles closed
  // instead of snapping the moment the tap lands. See [_dismiss].
  bool _exiting = false;
  bool _collapsed = false;

  static const _fadeDuration = Duration(milliseconds: 220);
  static const _collapseDuration = Duration(milliseconds: 260);

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _shuffling = false;

  Future<void> _load() async {
    try {
      final feed = context.read<AppState>().feed;
      var pick = await feed.todayPick();
      // If this day was already shuffled earlier in the session (e.g. the
      // app was restarted), pick back up from that same offset instead of
      // silently resetting to the shared daily pick.
      if (mounted && !pick.isEmpty) {
        final saved = context.read<TodayPickPrefsService>().rerollCount(pick.pickDate);
        if (saved > 0) {
          pick = await feed.todayPick(offset: saved);
        }
      }
      if (!mounted) return;
      setState(() {
        _pick = pick.isEmpty ? null : pick;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _shuffle() async {
    final pick = _pick;
    if (pick == null || _shuffling) return;
    final prefs = context.read<TodayPickPrefsService>();
    if (!prefs.hasRerollsLeft(pick.pickDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("that's 3 for today — more tomorrow".tr)),
      );
      return;
    }
    setState(() => _shuffling = true);
    try {
      final nextOffset = await prefs.reroll(pick.pickDate);
      final next = await context.read<AppState>().feed.todayPick(offset: nextOffset);
      if (!mounted) return;
      setState(() {
        if (!next.isEmpty) _pick = next;
        _shuffling = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _shuffling = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't find another pick — try again".tr)));
    }
  }

  void _openFranchise() {
    final pick = _pick;
    if (pick == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CollectionFullScreen(collection: pick.collection)),
    );
  }

  Future<void> _accept() async {
    final pick = _pick;
    if (pick == null) return;
    await context.read<TodayPickPrefsService>().accept(pick.pickDate);
    _openFranchise();
  }

  Future<void> _dismiss({required bool announce}) async {
    final pick = _pick;
    if (pick == null || _exiting) return;
    setState(() => _exiting = true);
    if (announce && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("okay — there'll be a new pick tomorrow".tr)),
      );
    }
    // Let the fade actually play before the card also collapses out of
    // the layout — collapsing immediately would yank the space shut
    // mid-fade instead of settling once the card's already invisible.
    await Future.delayed(_fadeDuration);
    if (mounted) setState(() => _collapsed = true);
    await context.read<TodayPickPrefsService>().dismiss(pick.pickDate);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<TodayPickPrefsService>();
    if (!prefs.loaded || !_loaded || _pick == null) return const SizedBox.shrink();
    final pick = _pick!;
    // Once dismissed in prefs, this would normally vanish on the very
    // next build — `_exiting` (set the instant "not now"/"×" is
    // tapped, well before prefs actually finishes persisting it) keeps
    // rendering the card through its fade-then-collapse instead. See
    // [_dismiss].
    if (prefs.isDismissed(pick.pickDate) && !_exiting) return const SizedBox.shrink();

    final accepted = prefs.isAccepted(pick.pickDate);
    // The progress readout shows once someone's actually said "I'm in",
    // even at 0 watched — that's the whole point of accepting, there's
    // now a marathon to track. It also shows before accepting if there's
    // already real progress on this franchise (titles watched before
    // this card ever existed) — the card shouldn't pretend that's not
    // there just because "I'm in" was never tapped.
    final showProgress = accepted || pick.watchedCount > 0;
    final collection = pick.collection;
    final headerImage = collection.items
        .map((i) => i.backdropUrl ?? i.posterUrl)
        .firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);

    final String headline;
    if (pick.watchedCount >= pick.totalCount && pick.totalCount > 0) {
      headline = 'you finished ${collection.displayTitle} — nice binge';
    } else if (accepted) {
      headline = 'keep going with ${collection.displayTitle}';
    } else {
      headline = '${pick.totalCount} evenings of ${collection.displayTitle} — ready to start?';
    }

    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: _openFranchise,
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 8,
                  child: headerImage != null
                      ? Image.network(
                          headerImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.accent.withOpacity(0.5)),
                        )
                      : Container(color: SeenlyPalette.accent.withOpacity(0.5)),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          SeenlyPalette.ink.withOpacity(0.05),
                          Colors.transparent,
                          SeenlyPalette.ink.withOpacity(0.55),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.paper.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text((accepted ? 'your marathon' : "today's pick").tr,
                        style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.accent, weight: FontWeight.w700)),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Row(
                    children: [
                      Builder(builder: (_) {
                        final rerollsLeft = prefs.hasRerollsLeft(pick.pickDate);
                        return GestureDetector(
                          onTap: _shuffling ? null : _shuffle,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: SeenlyPalette.ink.withOpacity(rerollsLeft ? 0.35 : 0.18),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: _shuffling
                                ? SizedBox(
                                    width: 11,
                                    height: 11,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: SeenlyPalette.paper),
                                  )
                                : Icon(Icons.shuffle, size: 13,
                                    color: SeenlyPalette.paper.withOpacity(rerollsLeft ? 1 : 0.55)),
                          ),
                        );
                      }),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _dismiss(announce: false),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: SeenlyPalette.ink.withOpacity(0.35),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.close, size: 13, color: SeenlyPalette.paper),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 10,
                  child: Text(
                    headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(
                      italic: true,
                      size: 15.5,
                      weight: FontWeight.w600,
                      color: SeenlyPalette.paper,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showProgress) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _WatchSegments(watched: pick.watchedCount, total: pick.totalCount),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${pick.watchedCount}/${pick.totalCount}',
                        style: SeenlyText.serif(size: 13, weight: FontWeight.w700, color: SeenlyPalette.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pick.watchedCount == 0
                        ? 'none watched yet — first one\'s a click away'.tr
                        : '${'watched'.tr} ${pick.watchedCount} ${'of'.tr} ${pick.totalCount}',
                    style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _dismiss(announce: true),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: Text('not now'.tr,
                              style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint, weight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: accepted ? _openFranchise : _accept,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.accent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text((accepted ? 'keep going' : "I'm in").tr,
                              style: SeenlyText.mono(
                                  size: 11, color: SeenlyPalette.accentOnAccent, weight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // AnimatedSize (outer) reacts once `_collapsed` swaps the child to
    // a zero-size SizedBox, smoothly shutting the space the card
    // occupied; AnimatedOpacity (inner) fades the card itself first.
    // The two are staggered by [_fadeDuration] in [_dismiss] so the
    // collapse only starts once there's nothing left to see collapsing.
    return AnimatedSize(
      duration: _collapseDuration,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: _fadeDuration,
        curve: Curves.easeOut,
        opacity: _exiting ? 0 : 1,
        child: _collapsed ? const SizedBox.shrink() : card,
      ),
    );
  }
}

/// A row of small rounded segments, one per title in the franchise —
/// filled for however many are already watched, hollow for the rest.
/// Reads more like a chapter/episode tracker (Netflix's own "episodes
/// watched" strip, a passport's row of stamps) than a plain bar, which
/// is the point: this card is about a marathon with discrete evenings in
/// it, not a smooth continuous quantity. Works the same for a trilogy or
/// a thirty-film franchise — segments just get thinner, never special-cased.
class _WatchSegments extends StatelessWidget {
  final int watched;
  final int total;
  const _WatchSegments({required this.watched, required this.total});

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    return Row(
      children: List.generate(total, (i) {
        final filled = i < watched;
        return Expanded(
          child: Container(
            height: 7,
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 3),
            decoration: BoxDecoration(
              color: filled ? SeenlyPalette.accent : SeenlyPalette.background,
              borderRadius: BorderRadius.circular(4),
              border: filled ? null : Border.all(color: SeenlyPalette.dashedBorder, width: 1),
            ),
          ),
        );
      }),
    );
  }
}
