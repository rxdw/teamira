import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bunny.dart';
import '../services/bunny_collection_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'level_mascot.dart';
import '../services/app_translations.dart';

/// The person-facing explainer for the bunny system — what a bunny is,
/// how new ones unlock, and how to pick a favorite. Opened from the
/// small info tap next to "your bunny collection" in the profile (see
/// screens/profile/profile_screen.dart).
Future<void> showBunnyGuideSheet(BuildContext context, {required int level}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: SeenlyPalette.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BunnyGuideSheet(level: level),
  );
}

class _BunnyGuideSheet extends StatelessWidget {
  final int level;
  const _BunnyGuideSheet({required this.level});

  @override
  Widget build(BuildContext context) {
    final unlockedIds = bunniesUnlockedAt(level).map((b) => b.id).toSet();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle.
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('a companion that grows with you'.tr,
                  style: SeenlyText.serif(italic: true, size: 19, weight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(
                "your level here comes from real evenings — what you log, the notes you write, the streaks you keep. it's the same number on your profile's level ring, nothing extra to farm.".tr,
                style: SeenlyText.serif(size: 13.5, color: SeenlyPalette.inkMuted).copyWith(height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                "every so often, reaching a new level brings a new bunny into your collection — for good. it doesn't leave even if a streak breaks later.".tr,
                style: SeenlyText.serif(size: 13.5, color: SeenlyPalette.inkMuted).copyWith(height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                "tap any bunny you've unlocked to make it your favorite — that's who tags along everywhere: right after you log something, on your welcome screen, while things load.".tr,
                style: SeenlyText.serif(size: 13.5, color: SeenlyPalette.inkMuted).copyWith(height: 1.5),
              ),
              const SizedBox(height: 22),
              Text('your bunnies'.tr,
                  style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)
                      .copyWith(letterSpacing: 0.6)),
              const SizedBox(height: 10),
              ...kBunnies.map((bunny) {
                final unlocked = unlockedIds.contains(bunny.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BunnyGuideRow(bunny: bunny, unlocked: unlocked),
                );
              }),
              const SizedBox(height: 4),
              Text(
                'more bunnies join the collection as new levels arrive.'.tr,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BunnyGuideRow extends StatelessWidget {
  final Bunny bunny;
  final bool unlocked;
  const _BunnyGuideRow({required this.bunny, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final selectedId = context.watch<BunnyCollectionService>().selectedId;
    final isFavorite = unlocked && selectedId == bunny.id;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36 / LevelMascot.aspectRatio,
            child: unlocked
                ? LevelMascot(level: bunny.unlockLevel, size: 36, animate: false)
                : Opacity(
                    opacity: 0.3,
                    child: Icon(Icons.lock_outline, size: 24, color: SeenlyPalette.inkFaint),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlocked ? bunny.name : 'a new bunny',
                  style: SeenlyText.serif(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: unlocked ? SeenlyPalette.ink : SeenlyPalette.inkFaint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unlocked
                      ? 'unlocked at level ${bunny.unlockLevel}'
                      : 'unlocks at level ${bunny.unlockLevel}',
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                ),
              ],
            ),
          ),
          if (isFavorite)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SeenlyPalette.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('favorite'.tr,
                  style: SeenlyText.mono(
                      size: 9, color: SeenlyPalette.accent, weight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
