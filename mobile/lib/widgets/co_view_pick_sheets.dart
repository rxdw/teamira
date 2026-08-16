import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../screens/partner/co_view_vote_screen.dart';
import '../screens/title/title_detail_screen.dart';
import '../services/co_view_vote_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';
import 'themed_loading_indicator.dart';
import 'themed_poster_tile.dart';
import '../services/app_translations.dart';

// Random draw and reel-spin "pick for us" flows for co-viewing — split
// out of co_view_decide_card.dart so co_view_decide_method_screen.dart
// can reach these two methods (plus co_view_vote_screen.dart's swipe
// flow) without an import cycle back through the card widget.
/// A single random draw from both of your "plan to watch" shelves — same
/// reroll-in-place idea as Home's own random pick card, just shared
/// between two people (or a whole company) instead of decided by one.
/// The sheet only picks the candidate; once confirmed it's put up for
/// the circle's yes/no via [proposeToCircle], same as every other
/// can't-decide method. Returns the winner once everyone's said yes, or
/// null if nothing was picked or proposed.
Future<MediaItem?> showCoViewRandomPickSheet(BuildContext context) async {
  final pick = await showModalBottomSheet<MediaItem?>(
    context: context,
    backgroundColor: SeenlyPalette.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _RandomPickSheet(),
  );
  if (pick == null || !context.mounted) return null;
  return proposeToCircle(context, pick, onRetry: () => Navigator.of(context).pop());
}

class _RandomPickSheet extends StatefulWidget {
  const _RandomPickSheet();

  @override
  State<_RandomPickSheet> createState() => _RandomPickSheetState();
}

class _RandomPickSheetState extends State<_RandomPickSheet> {
  String _source = CoViewVotePoolSource.personal;
  List<MediaItem> _pool = const [];
  MediaItem? _pick;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _changeSource(String source) {
    if (source == _source) return;
    setState(() => _source = source);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final pool = await context.read<AppState>().coViewVote.deck(source: _source);
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _pick = pool.isEmpty ? null : pool[math.Random().nextInt(pool.length)];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _reroll() {
    if (_pool.length < 2) return;
    final current = _pick;
    MediaItem next;
    do {
      next = _pool[math.Random().nextInt(_pool.length)];
    } while (identical(next, current));
    setState(() => _pick = next);
  }

  // Just hands the picked candidate back — proposing it to the circle
  // (and adding it once everyone's agreed) is showCoViewRandomPickSheet's
  // job, same as every other can't-decide method.
  void _choose() {
    final pick = _pick;
    if (pick == null) return;
    Navigator.of(context).pop(pick);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, MediaQuery.of(context).viewInsets.bottom + 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.casino_outlined, size: 16, color: SeenlyPalette.accent),
              const SizedBox(width: 6),
              Text('pick for us'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
              const Spacer(),
              if (_pool.length > 1)
                GestureDetector(
                  onTap: _reroll,
                  behavior: HitTestBehavior.opaque,
                  child: const Icon(Icons.refresh, size: 17, color: SeenlyPalette.inkMuted),
                ),
            ],
          ),
          const SizedBox(height: 14),
          PoolSourcePicker(value: _source, onChanged: _changeSource),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent)),
            )
          else if (_failed)
            _SheetMessage(text: 'tap to try again', onTap: _load)
          else if (_pick == null)
            _SheetMessage(text: coViewEmptyPoolHint(_source))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 74,
                  child: ThemedPosterTile(
                    title: _pick!.title.display,
                    posterUrl: _pick!.posterUrl,
                    mediaType: _pick!.mediaType,
                    fallbackColor: SeenlyPalette.mediaColor(_pick!.mediaType),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TitleDetailScreen(
                          mediaId: _pick!.id,
                          source: _pick!.source,
                          mediaType: _pick!.mediaType,
                          seedTitle: _pick!.title.display,
                          seedPosterUrl: _pick!.posterUrl,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_pick!.title.display, style: SeenlyText.serif(size: 16, italic: true, weight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(_pick!.mediaType, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            PrimaryButton(label: 'propose it to the circle', onTap: _choose),
          ],
        ],
      ),
    );
  }
}

/// Same idea as [showCoViewRandomPickSheet] — draws one title and puts
/// it up for the circle's yes/no — just with the reel's spin flourish
/// on the way there instead of landing on the pick immediately.
Future<MediaItem?> showCoViewReelPickSheet(BuildContext context) async {
  final pick = await showModalBottomSheet<MediaItem?>(
    context: context,
    backgroundColor: SeenlyPalette.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _ReelPickSheet(),
  );
  if (pick == null || !context.mounted) return null;
  return proposeToCircle(context, pick, onRetry: () => Navigator.of(context).pop());
}

class _ReelPickSheet extends StatefulWidget {
  const _ReelPickSheet();

  @override
  State<_ReelPickSheet> createState() => _ReelPickSheetState();
}

class _ReelPickSheetState extends State<_ReelPickSheet> {
  static const _spinTick = Duration(milliseconds: 90);
  static const _spinDuration = Duration(milliseconds: 1100);

  String _source = CoViewVotePoolSource.personal;
  List<MediaItem> _pool = const [];
  MediaItem? _pick;
  bool _loading = true;
  bool _failed = false;
  bool _spinning = false;
  Timer? _spinTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    super.dispose();
  }

  void _changeSource(String source) {
    if (source == _source) return;
    setState(() => _source = source);
    _load();
  }

  Future<void> _load() async {
    _spinTimer?.cancel();
    setState(() {
      _loading = true;
      _failed = false;
      _spinning = false;
    });
    try {
      final pool = await context.read<AppState>().coViewVote.deck(source: _source);
      if (!mounted) return;
      setState(() => _loading = false);
      if (pool.isEmpty) {
        setState(() => _pool = pool);
      } else {
        _pool = pool;
        _spin();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  // Flickers rapidly through the pool — same slot-machine feel as the
  // roulette method's own reel, just a lightweight text/poster cycle
  // rather than a full spinning wheel — then settles on the actual
  // random draw once the clock runs out.
  void _spin() {
    if (_pool.isEmpty) return;
    _spinTimer?.cancel();
    final rnd = math.Random();
    final stopwatch = Stopwatch()..start();
    setState(() {
      _spinning = true;
      _pick = _pool[rnd.nextInt(_pool.length)];
    });
    _spinTimer = Timer.periodic(_spinTick, (timer) {
      if (!mounted) return;
      if (stopwatch.elapsed >= _spinDuration) {
        timer.cancel();
        setState(() => _spinning = false);
        return;
      }
      setState(() => _pick = _pool[rnd.nextInt(_pool.length)]);
    });
  }

  void _choose() {
    final pick = _pick;
    if (pick == null || _spinning) return;
    Navigator.of(context).pop(pick);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, MediaQuery.of(context).viewInsets.bottom + 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rotate_right_rounded, size: 16, color: SeenlyPalette.accent),
              const SizedBox(width: 6),
              Text('spin the reel'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
              const Spacer(),
              if (_pool.length > 1 && !_spinning)
                GestureDetector(
                  onTap: _spin,
                  behavior: HitTestBehavior.opaque,
                  child: const Icon(Icons.refresh, size: 17, color: SeenlyPalette.inkMuted),
                ),
            ],
          ),
          const SizedBox(height: 14),
          PoolSourcePicker(value: _source, onChanged: _changeSource),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent)),
            )
          else if (_failed)
            _SheetMessage(text: 'tap to try again', onTap: _load)
          else if (_pick == null)
            _SheetMessage(text: coViewEmptyPoolHint(_source))
          else ...[
            AnimatedOpacity(
              opacity: _spinning ? 0.55 : 1,
              duration: const Duration(milliseconds: 120),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 74,
                    child: ThemedPosterTile(
                      title: _pick!.title.display,
                      posterUrl: _pick!.posterUrl,
                      mediaType: _pick!.mediaType,
                      fallbackColor: SeenlyPalette.mediaColor(_pick!.mediaType),
                      onTap: _spinning
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TitleDetailScreen(
                                    mediaId: _pick!.id,
                                    source: _pick!.source,
                                    mediaType: _pick!.mediaType,
                                    seedTitle: _pick!.title.display,
                                    seedPosterUrl: _pick!.posterUrl,
                                  ),
                                ),
                              ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_pick!.title.display, style: SeenlyText.serif(size: 16, italic: true, weight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(_pick!.mediaType, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              label: _spinning ? 'spinning…' : 'propose it to the circle',
              onTap: _spinning ? null : _choose,
            ),
          ],
        ],
      ),
    );
  }
}

/// Text for the empty/no-candidates state a random draw or reel spin can
/// land in — shared with [CoViewPoolSourceScreen] in
/// co_view_pick_screens.dart, since both there and in these quick sheets
/// it's the exact same pools that can come up empty. "catalog" only
/// lands here on a genuine fetch failure — the whole-app pool itself
/// is never actually empty.
String coViewEmptyPoolHint(String source) {
  switch (source) {
    case CoViewVotePoolSource.coview:
      return "nothing planned together yet — suggest a few titles first";
    case CoViewVotePoolSource.both:
      return "nothing queued on either side yet — add a few titles, or plan something together first";
    case CoViewVotePoolSource.catalog:
      return "couldn't load the catalog just now — try again in a moment";
    default:
      return "nothing queued on either side yet — add a few titles to your plan-to-watch shelves first";
  }
}

class _SheetMessage extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const _SheetMessage({required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Text(text, style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted)),
      ),
    );
  }
}
