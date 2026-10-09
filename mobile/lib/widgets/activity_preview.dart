import 'package:flutter/material.dart';

import '../models/activity_item.dart';
import '../theme/palette.dart';
import '../utils/server_time.dart';
import 'watched_preview_sheet.dart';
import '../services/locale_service.dart';

/// Turns a friend's [ActivityItem] into the same [WatchedPreviewData]
/// shape the diary/profile/co-viewing grids already use — so tapping a
/// friend's activity row or a poster in the friends feed opens the exact
/// same "you watched this" card (screenshot: poster, rating, review,
/// "open the title"), just with someone else's name on it instead of an
/// edit affordance (a friend's own event has no `entryId` this account
/// could PATCH, so [WatchedPreviewCard] already hides the edit button
/// for it — see its own `data.entryId != null` check).
///
/// Deliberately a plain, colorless card — [EveningShareCard] needs a
/// full [DiaryEntry] with fields (mood tags, precise watched-with) an
/// activity row simply never carried, and "share this evening" makes no
/// sense for an evening that wasn't this account's own. Sharing is
/// swapped out for "open the title" only, wired straight into the
/// preview card via [WatchedPreviewData.shareCard] never being invoked
/// (see friends_activity_feed_screen.dart / friend_profile_screen.dart,
/// which don't offer the share button for a friend's card).
WatchedPreviewData watchedPreviewFromActivity(ActivityItem item) {
  final date = tryParseServerUtc(item.createdAt);
  return WatchedPreviewData(
    mediaId: item.mediaId ?? '',
    source: item.source ?? '',
    mediaType: item.mediaType ?? 'movie',
    title: item.mediaTitle ?? item.text,
    posterUrl: item.posterUrl,
    rating: item.rating,
    date: date,
    watchedWithUsername: null,
    friendLabel: item.isMine ? null : LocaleService.pick('активность: ${item.nameForDisplay}', '${item.nameForDisplay}\'s activity'),
    showShareButton: false,
    shareCard: const SizedBox.shrink(),
    shareFileName: 'seenly-activity',
    shareText: '',
  );
}

/// A small round rating badge that rides a poster's corner — used
/// wherever a friend's rated title shows up as a bare poster (the
/// friends screen's "last seen" preview, the activity feed grid, the
/// suggested-friends preview) rather than inside the full preview card.
class PosterRatingBadge extends StatelessWidget {
  final int rating;
  const PosterRatingBadge({super.key, required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: SeenlyPalette.ink.withOpacity(0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite, size: 9, color: SeenlyPalette.accent),
          const SizedBox(width: 3),
          Text('$rating', style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
