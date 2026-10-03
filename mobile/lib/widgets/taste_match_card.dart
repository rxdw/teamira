import 'package:flutter/material.dart';

import '../models/taste_match.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'match_ring.dart';
import 'poster_tile.dart';
import 'small_pieces.dart';
import 'wow_motion.dart';
import '../theme/clay_kit.dart';

/// A small ring-only badge for a corner of a photo/polaroid — the
/// friends screen's compact card treatment. Deliberately just the
/// number (see [TasteMatchDetail] below for "not just a percent"):
/// a card already crowded with a name, a level, and an activity line
/// has no room for a headline too, so the full story lives one tap
/// away instead.
class TasteMatchBadge extends StatelessWidget {
  final TasteMatch match;
  final double size;

  const TasteMatchBadge({super.key, required this.match, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        shape: BoxShape.circle,
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: MatchRing(match: match.overall, size: size),
    );
  }
}

/// The full "why you're a match" card — a ring, the single best
/// plain-language reason for it, an honest note on how much data it
/// rests on, the shared genres, and a little row of the shared titles
/// themselves. This is the "не тупо процент, а подробнее" treatment:
/// every surface that shows a taste match anywhere beyond the compact
/// badge above uses this same shape, so the reasoning always looks and
/// reads the same no matter where someone meets it.
///
/// [animateIn] plays the same settle-in-from-below cascade as the rest
/// of the app's "wow" vocabulary (see wow_motion.dart's [Entrance]) —
/// on by default since this card is usually the payoff of a moment
/// (a freshly loaded friend profile, onboarding's reveal), not
/// something sitting on screen from the first frame.
class TasteMatchDetail extends StatelessWidget {
  final TasteMatch match;
  final bool animateIn;
  final bool compact;

  const TasteMatchDetail({
    super.key,
    required this.match,
    this.animateIn = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SeenlyPalette.border),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MatchRing(match: match.overall, size: compact ? 44 : 56, animateIn: animateIn),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.headline,
                      style: SeenlyText.serif(
                        size: compact ? 14 : 16,
                        weight: FontWeight.w600,
                        italic: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(match.basis, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
          if (match.sharedGenres.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: match.sharedGenres.map((g) => PillChip(label: g)).toList(),
            ),
          ],
          if (match.sharedTitles.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: compact ? 84 : 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: match.sharedTitles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final t = match.sharedTitles[i];
                  return SizedBox(
                    width: compact ? 56 : 68,
                    child: PosterTile(
                      title: t.displayTitle,
                      posterUrl: t.posterUrl,
                      fallbackColor: SeenlyPalette.mediaColor(t.mediaType),
                      showLabel: false,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );

    if (!animateIn) return card;
    return Entrance(child: card);
  }
}
