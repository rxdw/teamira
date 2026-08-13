import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../services/co_view_vote_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/co_view_pick_sheets.dart' show coViewEmptyPoolHint;
import '../../widgets/small_pieces.dart';
import '../decide/decide_random_screen.dart';
import '../decide/decide_roulette_screen.dart';
import 'co_view_vote_screen.dart' show PoolSourcePicker, proposeToCircle;

enum CoViewPickMethod { random, reel }

/// Step one of "random pick" / "spin the reel" from the co-viewing
/// can't-decide grid — just the "what should it come from?" choice on
/// its own full screen, same [PoolSourcePicker] the swipe and poll
/// methods already ask up front, rather than folding it into the same
/// small card as the pick itself.
///
/// Once a source is picked, this fetches that pool and hands off to the
/// *exact same* [DecideRandomScreen] / [DecideRouletteScreen] Home's
/// own solo can't-decide uses (see their own docs) — same reveal, same
/// reroll/spin, same everything — just with the secondary button
/// swapped from "plan to watch" to proposing the pick to the whole
/// circle. Replaces itself (pushReplacement) rather than stacking on
/// top, so popping the reveal screen lands back on whatever opened this
/// step, not on this one.
class CoViewPoolSourceScreen extends StatefulWidget {
  final CoViewPickMethod method;
  const CoViewPoolSourceScreen({super.key, required this.method});

  @override
  State<CoViewPoolSourceScreen> createState() => _CoViewPoolSourceScreenState();
}

class _CoViewPoolSourceScreenState extends State<CoViewPoolSourceScreen> {
  String _source = CoViewVotePoolSource.personal;
  bool _loading = false;

  bool get _isReel => widget.method == CoViewPickMethod.reel;

  Future<MediaItem?> _propose(BuildContext context, MediaItem item) {
    return proposeToCircle(context, item, onRetry: () => Navigator.of(context).pop());
  }

  Future<void> _continue() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final pool = await context.read<AppState>().coViewVote.deck(source: _source);
      if (!mounted) return;
      if (pool.isEmpty) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(coViewEmptyPoolHint(_source))),
        );
        return;
      }
      Navigator.of(context).pushReplacement<MediaItem?, void>(
        MaterialPageRoute(
          builder: (_) => _isReel
              ? DecideRouletteScreen(
                  pool: pool,
                  onSecondary: _propose,
                  secondaryLabel: 'propose it',
                  secondaryDoneLabel: 'proposed',
                  secondaryIcon: Icons.how_to_vote_outlined,
                  secondaryDoneIcon: Icons.how_to_vote,
                )
              : DecideRandomScreen(
                  pool: pool,
                  onSecondary: _propose,
                  secondaryLabel: 'propose it',
                  secondaryDoneLabel: 'proposed',
                  secondaryIcon: Icons.how_to_vote_outlined,
                  secondaryDoneIcon: Icons.how_to_vote,
                ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't load that pool just now — try again")),
      );
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
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
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
                  Text(_isReel ? 'spin the reel' : 'random pick', style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _isReel ? Icons.rotate_right_rounded : Icons.casino_outlined,
                      size: 28,
                      color: SeenlyPalette.accent,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "what should it come from?",
                      style: SeenlyText.serif(size: 18.5, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isReel
                          ? "the reel draws from whichever pool you pick, then everyone votes on where it lands."
                          : "one title gets drawn from whichever pool you pick, then everyone votes on it.",
                      style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
                    ),
                    const SizedBox(height: 22),
                    PoolSourcePicker(value: _source, onChanged: (v) => setState(() => _source = v)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: PrimaryButton(label: 'continue', onTap: _continue, loading: _loading),
            ),
          ],
        ),
      ),
    );
  }
}
