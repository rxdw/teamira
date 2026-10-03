import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../services/co_view_vote_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/co_view_pick_sheets.dart' show coViewEmptyPoolHint;
import '../decide/decide_filters_screen.dart' show DecideFiltersScreen;
import '../decide/decide_random_screen.dart';
import '../decide/decide_roulette_screen.dart';
import '../../widgets/wow_motion.dart' show Entrance, PressScale;
import 'co_view_vote_screen.dart' show NarrowDownPrompt, PoolSetupHero, PoolSetupLayout, proposeToCircle;
import '../../services/app_translations.dart';

enum CoViewPickMethod { random, reel }

/// Step one of "random pick" / "spin the reel" from the co-viewing
/// can't-decide grid — the "what should it come from?" pool choice,
/// then whether to narrow that pool down by type/genre/year first (same
/// [NarrowDownPrompt] the swipe and poll methods ask too) or just take
/// it as-is, all on its own full screen.
///
/// Once that's settled, this fetches the (possibly filtered) pool and
/// hands off to the *exact same* [DecideRandomScreen] /
/// [DecideRouletteScreen] Home's own solo can't-decide uses (see their
/// own docs) — same reveal, same reroll/spin, same everything — just
/// with the secondary button swapped from "plan to watch" to proposing
/// the pick to the whole circle. Replaces itself (pushReplacement)
/// rather than stacking on top, so popping the reveal screen lands back
/// on whatever opened this step, not on this one.
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

  void _openReveal(List<MediaItem> pool) {
    if (!mounted) return;
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
  }

  Future<void> _takeItAll() async {
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
      _openReveal(pool);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't load that pool just now — try again".tr)),
      );
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
            _openReveal(pool);
          },
        ),
      ),
    );
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
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_isReel ? 'spin the reel' : 'random pick', style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: PoolSetupLayout(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                hero: PoolSetupHero(
                  icon: _isReel ? Icons.rotate_right_rounded : Icons.casino_outlined,
                  title: "what should it come from?".tr,
                  titleStyle: SeenlyText.serif(size: 21, weight: FontWeight.w600),
                  subtitle: _isReel
                      ? "the reel draws from whichever pool you pick, then everyone votes on where it lands."
                      : "one title gets drawn from whichever pool you pick, then everyone votes on it.",
                ),
                value: _source,
                onChanged: (v) => setState(() => _source = v),
                footer: Entrance(
                  delay: const Duration(milliseconds: 210),
                  riseBy: 14,
                  child: NarrowDownPrompt(
                    onNarrowDown: _narrowDown,
                    onTakeItAll: _takeItAll,
                    loading: _loading,
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
