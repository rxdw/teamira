import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_translations.dart';
import '../models/watchlist_entry.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';
import 'themed_poster_tile.dart';
import 'wow_motion.dart';

/// The "favorites" showcase — a little display shelf, not just a bare row:
/// a soft paper card (same resting-on-the-page language as every other
/// card on Profile — see [SeenlyPalette.softShadow]) holding a header
/// ("favorite" / "see all N ›") over a horizontal row of themed posters,
/// each one carrying the same pink heart badge as the full favorites
/// screen's swipeable card deck (see FavoriteFilmsScreen's
/// _FavoritesList) so it reads as the same collection rather than a
/// separate design. This row is now the *only* favorites showcase on the
/// profile header — there's no separate corner shortcut above it — so
/// [topKey], when set, marks the single most-favorite pick (see
/// ProfileService.setTopFavorite) with a gold ring, a warm glow, a small
/// held breath of motion, and a star badge in place of the plain heart —
/// the one deliberately "alive" thing in this card, same spirit as the
/// streak flame elsewhere, never more than one per shelf.
///
/// Every poster settles in with its own small stagger on first appearance
/// ([Entrance]) rather than popping in all at once, so opening a profile
/// — your own or a friend's — feels like watching a shelf of keepsakes
/// being set out, not a grid rendering.
///
/// Shared between the signed-in account's own profile
/// (see ProfileScreen, right under the header, before the stats grid)
/// and a friend's profile (see FriendProfileScreen, right under their
/// header) — the only difference between the two call sites is what
/// happens on tap and, for a friend, whether [visible] is false (their
/// own privacy_favorites setting — see FriendCollections.favoritesVisible),
/// in which case the row is replaced by a quiet [bodyPrivateText] instead
/// of an empty state, same "hidden vs merely empty" rule as every other
/// shelf on a friend's profile. The empty state itself is a small dashed
/// poster-shaped slot rather than a bare line of text — an invitation to
/// fill it, not just a note that it's blank.
class FavoritesShowcaseRow extends StatelessWidget {
  final String title;
  final List<WatchlistEntry> entries;
  final bool visible;
  final VoidCallback onSeeAll;
  final ValueChanged<WatchlistEntry> onTapEntry;

  // "source:mediaId" keys of the picks in the stories deck, if any (see
  // ProfileMe.topFavoritePicks / FriendCollections.topFavoritePicks).
  // Purely visual here — changing the picks still happens on
  // FavoriteFilmsScreen's stars, not from this row.
  final List<String> topKeys;

  // Trailing (top-right) label, one per state.
  final String trailingEmpty;
  final String trailingPrivate;

  // Body text shown instead of the poster row, one per state.
  final String bodyEmptyText;
  final String bodyPrivateText;

  const FavoritesShowcaseRow({
    super.key,
    this.title = 'favorite',
    required this.entries,
    this.visible = true,
    required this.onSeeAll,
    required this.onTapEntry,
    this.topKeys = const [],
    this.trailingEmpty = 'tap to add one',
    this.trailingPrivate = 'private',
    this.bodyEmptyText = "nothing pinned yet — the heart on a film's page adds it here",
    this.bodyPrivateText = 'kept private',
  });

  @override
  Widget build(BuildContext context) {
    final trailing = !visible
        ? trailingPrivate.tr
        : entries.isEmpty
            ? trailingEmpty.tr
            : '${'see all'.tr} ${entries.length} ›';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onSeeAll,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, size: 13, color: SeenlyPalette.pink),
                    const SizedBox(width: 7),
                    Text(title.tr, style: SeenlyText.serif(italic: true, size: 15.5, weight: FontWeight.w600)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.background,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(trailing, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!visible)
            _PrivateShelf(text: bodyPrivateText.tr)
          else if (entries.isEmpty)
            _EmptyShelf(text: bodyEmptyText.tr, onTap: onSeeAll)
          else
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  final isTop = topKeys.contains('${e.source}:${e.mediaId}');
                  return HorizontalReveal(
                    delay: Duration(milliseconds: 55 * math.min(i, 8)),
                    child: _ShowcaseTile(
                      entry: e,
                      index: i,
                      isTop: isTop,
                      onTap: () => onTapEntry(e),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// One poster on the shelf. Every tile gets a soft, warm-toned shadow
/// underneath it — the same "resting on paper" language [SeenlyPalette.
/// softShadow] uses for cards, applied here so the posters read as small
/// objects sitting on the shelf rather than flat cutouts. The single
/// [isTop] pick (see [FavoritesShowcaseRow.topKeys]) gets the full
/// treatment on top of that: a gold ring (unchanged from before), a
/// warmer mustard-tinted glow in place of the plain shadow, and a very
/// slow, very small [Breathe] — the one quietly-alive element in this
/// shelf, easy to miss at a glance and exactly right for that.
class _ShowcaseTile extends StatelessWidget {
  final WatchlistEntry entry;
  final int index;
  final bool isTop;
  final VoidCallback onTap;
  const _ShowcaseTile({
    required this.entry,
    required this.index,
    required this.isTop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final poster = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (isTop ? SeenlyPalette.mustard : SeenlyPalette.ink)
                .withOpacity(isTop ? 0.32 : 0.12),
            blurRadius: isTop ? 18 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ThemedPosterTile(
        title: entry.displayTitle,
        posterUrl: entry.posterUrl,
        mediaType: entry.mediaType,
        fallbackColor: SeenlyPalette.gridColorFor(index),
        badge: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            isTop ? Icons.star : Icons.favorite,
            size: isTop ? 15 : 13,
            color: isTop ? SeenlyPalette.mustard : SeenlyPalette.pink,
            shadows: isTop
                ? const [Shadow(color: Colors.black45, blurRadius: 3)]
                : null,
          ),
        ),
        onTap: onTap,
      ),
    );

    if (!isTop) {
      return SizedBox(width: 100, child: poster);
    }

    final ringed = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: SeenlyPalette.mustard, width: 2),
      ),
      child: poster,
    );

    return SizedBox(
      width: 100,
      child: Breathe(
        period: const Duration(milliseconds: 4200),
        minScale: 0.985,
        minOpacity: 1,
        child: ringed,
      ),
    );
  }
}

/// The empty state — "nothing pinned yet" as a small dashed, poster-
/// shaped slot with a faint outlined heart in it, next to the invite
/// text, rather than a bare line of italic type. Reads as a shelf with
/// one open spot on it, not just an absence.
class _EmptyShelf extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _EmptyShelf({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DashedBox(
            radius: 12,
            color: SeenlyPalette.pink.withOpacity(0.4),
            child: SizedBox(
              width: 60,
              height: 90,
              child: Center(
                child: Icon(Icons.favorite_border, size: 20, color: SeenlyPalette.pink.withOpacity(0.6)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.placeholder),
            ),
          ),
        ],
      ),
    );
  }
}

/// The private state — a quiet lock instead of a poster row, same warmth
/// as everywhere else this card can land, never a cold "no access" note.
class _PrivateShelf extends StatelessWidget {
  final String text;
  const _PrivateShelf({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: SeenlyPalette.placeholder),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.placeholder),
          ),
        ),
      ],
    );
  }
}
