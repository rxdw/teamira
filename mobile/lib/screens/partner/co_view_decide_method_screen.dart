import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/wow_motion.dart';
import 'co_view_ask_teamira_screen.dart';
import 'co_view_pick_screens.dart';
import 'co_view_poll_screen.dart';
import 'co_view_vote_screen.dart';

/// The can't-decide entry point for co-viewing — same five methods as
/// Home's own [DecideMethodScreen] plus one co-viewing-only extra
/// ("vote it out"), just every method's outcome goes up for the whole
/// circle's yes/no (or vote) instead of one phone deciding for everyone:
///
/// - ask teamira / random pick / spin the reel all land on one candidate
///   and put it up via [proposeToCircle] (see co_view_vote_screen.dart).
/// - swipe through opens the existing pool-wide vote round, which
///   already matches on a yes from every member, not just one partner.
/// - vote it out is the one method with no solo equivalent — a small
///   shortlist everyone votes on head-to-head, on a countdown, rather
///   than a yes/no per title (see co_view_poll_screen.dart).
///
/// No filters step first, unlike the solo version — co-viewing's own
/// "what you each queued / already agreed together / everything" pool
/// picker already does that narrowing, one level in on whichever method
/// needs it.
class CoViewDecideMethodScreen extends StatelessWidget {
  const CoViewDecideMethodScreen({super.key});

  Future<void> _openAskTeamira(BuildContext context) async {
    final winner = await Navigator.of(context).push<MediaItem?>(
      MaterialPageRoute(builder: (_) => const CoViewAskTeamiraScreen()),
    );
    if (winner != null && context.mounted) Navigator.of(context).pop(winner);
  }

  Future<void> _openRandom(BuildContext context) async {
    final winner = await Navigator.of(context).push<MediaItem?>(
      MaterialPageRoute(builder: (_) => const CoViewPoolSourceScreen(method: CoViewPickMethod.random)),
    );
    if (winner != null && context.mounted) Navigator.of(context).pop(winner);
  }

  Future<void> _openReel(BuildContext context) async {
    final winner = await Navigator.of(context).push<MediaItem?>(
      MaterialPageRoute(builder: (_) => const CoViewPoolSourceScreen(method: CoViewPickMethod.reel)),
    );
    if (winner != null && context.mounted) Navigator.of(context).pop(winner);
  }

  Future<void> _openSwipe(BuildContext context) async {
    final winner = await Navigator.of(context).push<MediaItem?>(
      MaterialPageRoute(builder: (_) => const CoViewVoteScreen()),
    );
    if (winner != null && context.mounted) Navigator.of(context).pop(winner);
  }

  Future<void> _openPoll(BuildContext context) async {
    final winner = await Navigator.of(context).push<MediaItem?>(
      MaterialPageRoute(builder: (_) => const CoViewPollScreen()),
    );
    if (winner != null && context.mounted) Navigator.of(context).pop(winner);
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('how should you decide?', style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          'whatever you land on, everyone votes yes first',
                          style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: HorizontalReveal(
                              slideBy: -28,
                              child: _MethodTile(
                                icon: Icons.auto_awesome_outlined,
                                color: SeenlyPalette.periwinkle,
                                title: 'ask teamira',
                                blurb: 'describe the evening, propose the pick',
                                onTap: () => _openAskTeamira(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: HorizontalReveal(
                              slideBy: 28,
                              delay: const Duration(milliseconds: 70),
                              child: _MethodTile(
                                icon: Icons.casino_outlined,
                                color: SeenlyPalette.coral,
                                title: 'random pick',
                                blurb: 'one title, drawn from the pool',
                                onTap: () => _openRandom(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: HorizontalReveal(
                              slideBy: -28,
                              delay: const Duration(milliseconds: 140),
                              child: _MethodTile(
                                icon: Icons.rotate_right_rounded,
                                color: SeenlyPalette.mustard,
                                title: 'spin the reel',
                                blurb: 'watch it roll and land on something',
                                onTap: () => _openReel(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: HorizontalReveal(
                              slideBy: 28,
                              delay: const Duration(milliseconds: 210),
                              child: _MethodTile(
                                icon: Icons.swipe_outlined,
                                color: SeenlyPalette.sage,
                                title: 'swipe through',
                                blurb: 'everyone swipes, a match wins',
                                onTap: () => _openSwipe(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    HorizontalReveal(
                      slideBy: -28,
                      delay: const Duration(milliseconds: 280),
                      child: _WideMethodTile(
                        icon: Icons.how_to_vote_outlined,
                        color: SeenlyPalette.pink,
                        title: 'vote it out',
                        blurb: 'a shortlist, a countdown, most votes wins',
                        onTap: () => _openPoll(context),
                      ),
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

/// One big, colorful quarter-screen card — same language as the solo
/// decide screen's own tile, minus its four distinct idle animations
/// (kept to one static badge here, since this screen doesn't need to
/// carry that much extra motion to read as inviting).
class _MethodTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String blurb;
  final VoidCallback onTap;

  const _MethodTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.blurb,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.97,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withOpacity(0.09), SeenlyPalette.paper),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: SeenlyPalette.border),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: color.withOpacity(0.16), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 27, color: color),
                ),
              ),
            ),
            Text(title, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(
              blurb,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.serif(italic: true, size: 13.5, color: SeenlyPalette.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-width variant of [_MethodTile] for the one method that doesn't
/// fit neatly in a quarter-screen square — "vote it out" needs room to
/// read as its own distinct kind of decide (a countdown, a shortlist)
/// rather than another same-shaped tile in the grid above it.
class _WideMethodTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String blurb;
  final VoidCallback onTap;

  const _WideMethodTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.blurb,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.98,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withOpacity(0.09), SeenlyPalette.paper),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SeenlyPalette.border),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color.withOpacity(0.16), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, size: 23, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SeenlyText.serif(size: 16.5, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    blurb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}
