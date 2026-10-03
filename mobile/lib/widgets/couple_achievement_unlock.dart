import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/couple_achievement_seen_service.dart';
import '../services/shared_diary_service.dart';
import '../state/app_state.dart';
import 'achievement_unlock_overlay.dart';

/// [checkAndCelebrateNewAchievements]'s own counterpart for the co-viewing
/// circle's badges (GET /partner/shared/achievements) — the same
/// fetch-diff-celebrate shape, with [CoupleAchievementSeenService]
/// standing in for [AchievementSeenService]. Call after anything that
/// could plausibly move a couple achievement (logging a shared evening,
/// marking a co-view entry watched together) as well as from the "мы"
/// tab itself, for whoever only notices a new badge on their next visit
/// there.
///
/// Best-effort and silent on failure, same spirit as the personal
/// version: a network hiccup here should never block or fail whatever
/// triggered it. That includes the 409 this throws for an account with
/// no active partner link at all — not a bug, just nothing to check yet.
Future<void> checkAndCelebrateNewCoupleAchievements(BuildContext context) async {
  try {
    final app = context.read<AppState>();
    final userId = app.currentUser?.id;
    final shared = SharedDiaryService(ApiClient.instance);
    final r = await shared.achievements();
    final unlockedNow = r.achievements.where((a) => a.unlocked).map((a) => a.id).toSet();

    if (await CoupleAchievementSeenService.isFirstEverCheck(userId)) {
      // Never checked before on this device/account — baseline every
      // already-unlocked badge as seen without celebrating any of them,
      // same reasoning as AchievementSeenService.isFirstEverCheck (most
      // relevant here for a couple who links up after already sharing a
      // long diary history together and would otherwise get hit with a
      // whole wall of "unlocked" at once).
      await CoupleAchievementSeenService.markSeen(userId, unlockedNow);
      return;
    }

    final seen = await CoupleAchievementSeenService.seenIds(userId);
    final freshlyUnlocked =
        r.achievements.where((a) => a.unlocked && !seen.contains(a.id)).toList();
    if (freshlyUnlocked.isEmpty) return;

    await CoupleAchievementSeenService.markSeen(userId, freshlyUnlocked.map((a) => a.id));
    if (!context.mounted) return;
    await showAchievementUnlockCelebration(context, freshlyUnlocked);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('checkAndCelebrateNewCoupleAchievements failed silently: $e\n$st');
    }
  }
}
