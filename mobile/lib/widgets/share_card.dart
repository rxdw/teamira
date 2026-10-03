import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/profile_stats.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';
import '../theme/notebook_paper.dart';
import '../theme/clay_kit.dart';

/// The bit every share card ends on — small, quiet, and the same
/// everywhere, so a screenshot of one is instantly recognizable as "from
/// teamira" without shouting about it.
class _ShareFooter extends StatelessWidget {
  const _ShareFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 68,
          child: CozyDivider(color: SeenlyPalette.dashedBorder, thickness: 1),
        ),
        const SizedBox(height: 12),
        Text('teamira'.tr, style: SeenlyText.serif(italic: true, size: 16, color: SeenlyPalette.accent)),
        const SizedBox(height: 3),
        Text('a cozy watch diary'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
      ],
    );
  }
}

/// The soft, floating drop-shadow every share card sits on top of — a
/// little heavier than [SeenlyPalette.softShadow], since these cards are
/// meant to be looked at on their own (in the preview sheet, and again
/// as a screenshot in someone's camera roll) rather than sitting flush
/// in a scrolling list of other cards.
List<BoxShadow> get _shareCardShadow => [
      BoxShadow(
        color: SeenlyPalette.shadowColor.withOpacity(SeenlyPalette.shadowOpacity * 2.1),
        blurRadius: 32,
        offset: const Offset(0, 14),
      ),
    ];

/// A bigger, standalone cousin of [PolaroidCard] — sized for a share card
/// rather than a shelf row, and without the rotation (a share card reads
/// better sitting straight).
class _PinnedPoster extends StatelessWidget {
  final String? posterUrl;
  final Color fallbackColor;
  final double width;
  final double height;

  const _PinnedPoster({
    required this.fallbackColor,
    this.posterUrl,
    this.width = 168,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(7),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -14,
            left: width / 2 - 24,
            child: Transform.rotate(
              angle: -0.06,
              child: Container(
                width: 40,
                height: 14,
                color: SeenlyPalette.tapeMustard.withOpacity(0.85),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              width: width,
              height: height,
              child: posterUrl != null && posterUrl!.isNotEmpty
                  ? Image.network(posterUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: fallbackColor))
                  : Container(color: fallbackColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Share this evening" — one logged title, dressed up as a small
/// scrapbook page: pinned poster, hearts, mood tags, and the note if there
/// is one. Fixed width so it captures cleanly as a PNG regardless of the
/// screen it's rendered on.
class EveningShareCard extends StatelessWidget {
  final DiaryEntry entry;
  final Color fallbackColor;

  const EveningShareCard({
    super.key,
    required this.entry,
    required this.fallbackColor,
  });

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  String get _dateLabel {
    final d = entry.watchedAt;
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 328,
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 30),
      decoration: BoxDecoration(
        color: SeenlyPalette.cork,
        borderRadius: BorderRadius.circular(24),
        boxShadow: _shareCardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(entry.isRewatch ? 'rewatched · $_dateLabel' : 'watched · $_dateLabel',
              style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
          const SizedBox(height: 20),
          _PinnedPoster(posterUrl: entry.posterUrl, fallbackColor: fallbackColor),
          const SizedBox(height: 20),
          Text(
            entry.displayTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.serif(italic: true, size: 22, weight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(entry.mediaType, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
          const SizedBox(height: 10),
          if (entry.rating != null) ...[
            _StaticHearts(value: entry.rating!),
            const SizedBox(height: 14),
          ],
          if (entry.moodTags.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final tag in entry.moodTags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.paper,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(tag, style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (entry.note != null && entry.note!.trim().isNotEmpty) ...[
            Transform.rotate(
              angle: -0.012,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '“${entry.note!.trim()}”',
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.ink),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          const _ShareFooter(),
        ],
      ),
    );
  }
}

/// Read-only hearts drawn without [HeartRating]'s gesture handling — this
/// card only ever needs to display a value, never edit one.
class _StaticHearts extends StatelessWidget {
  final int value;
  const _StaticHearts({required this.value});

  @override
  Widget build(BuildContext context) {
    final filledColor = SeenlyPalette.ratingColor(value);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (int i = 1; i <= 10; i++)
          Icon(
            i <= value ? Icons.favorite : Icons.favorite_border,
            size: 17,
            color: i <= value ? filledColor : SeenlyPalette.dashedBorder,
          ),
      ],
    );
  }
}

/// "Share your year" (or month) — the Wrapped stats dressed up the same
/// way: a big headline number, the shelf breakdown, a favorite title, and
/// the same footer as [EveningShareCard] so the two feel like one family.
class YearShareCard extends StatelessWidget {
  final WrappedStat stat;
  final Color favoriteFallbackColor;

  const YearShareCard({
    super.key,
    required this.stat,
    required this.favoriteFallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final topGenre = stat.topGenres.isNotEmpty ? stat.topGenres.first.genre : null;
    return Container(
      width: 328,
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 30),
      decoration: BoxDecoration(
        color: SeenlyPalette.cork,
        borderRadius: BorderRadius.circular(24),
        boxShadow: _shareCardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stat.periodLabel.toUpperCase(),
              style: SeenlyText.mono(size: 12, color: SeenlyPalette.accent, weight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text('${stat.totalLogged}',
              style: SeenlyText.serif(size: 60, weight: FontWeight.w700)),
          Text('evenings logged'.tr, style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
          const SizedBox(height: 7),
          Text('${stat.hours.toStringAsFixed(0)} ${'hours in'.tr}',
              style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.inkMuted)),
          const SizedBox(height: 20),
          if (stat.favoriteTitle != null) ...[
            _PinnedPoster(
              posterUrl: stat.favoritePoster,
              fallbackColor: favoriteFallbackColor,
              width: 124,
              height: 176,
            ),
            const SizedBox(height: 10),
            Text('${'favorite'.tr}: ${stat.favoriteTitle}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(italic: true, size: 14)),
            const SizedBox(height: 18),
          ],
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 9,
            runSpacing: 9,
            children: [
              if (topGenre != null) _StatChip(label: "${'top genre'.tr}: $topGenre"),
              if (stat.longestStreak > 1)
                _StatChip(label: "${'longest streak'.tr}: ${nCount('nDays', stat.longestStreak)}"),
            ],
          ),
          const SizedBox(height: 20),
          const _ShareFooter(),
        ],
      ),
    );
  }
}

/// "Look what I found" — a title on its own, dressed up the same
/// corkboard way as [EveningShareCard] but without anything personal
/// (no note, no own rating): just the poster, the community score if
/// there is one, and a couple of genre tags, so it reads well whether
/// the title has been watched yet or not.
class TitleShareCard extends StatelessWidget {
  final MediaItem item;
  final Color fallbackColor;
  final MediaRatings? ratings;

  const TitleShareCard({
    super.key,
    required this.item,
    required this.fallbackColor,
    this.ratings,
  });

  @override
  Widget build(BuildContext context) {
    final rating = ratings?.tmdbRating;
    return Container(
      width: 328,
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 30),
      decoration: BoxDecoration(
        color: SeenlyPalette.cork,
        borderRadius: BorderRadius.circular(24),
        boxShadow: _shareCardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.mediaType.toUpperCase(),
            style: SeenlyText.mono(size: 12, color: SeenlyPalette.accent, weight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _PinnedPoster(posterUrl: item.posterUrl, fallbackColor: fallbackColor),
          const SizedBox(height: 20),
          Text(
            item.title.display,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.serif(italic: true, size: 22, weight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            item.year != null ? '${item.year}' : item.mediaType,
            style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
          ),
          if (rating != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: SeenlyPalette.ratingColor(rating.round()).withOpacity(0.16),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: SeenlyPalette.ratingColor(rating.round()).withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 17, color: SeenlyPalette.ratingColor(rating.round())),
                  const SizedBox(width: 6),
                  Text(rating.toStringAsFixed(1),
                      style: SeenlyText.serif(size: 14, weight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          if (item.genres.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final genre in item.genres.take(3)) _StatChip(label: genre),
              ],
            ),
          ],
          const SizedBox(height: 20),
          const _ShareFooter(),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  const _StatChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(label, style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
    );
  }
}
