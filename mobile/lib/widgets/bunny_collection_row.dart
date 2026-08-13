import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bunny.dart';
import '../services/bunny_collection_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'level_mascot.dart';

/// A bunny collection lane — every bunny in [level]'s reach, unlocked
/// ones with their art, the rest as a locked silhouette. Two modes:
///
/// - **Own profile** (`readOnly: false`, the default): tapping an
///   unlocked bunny makes it the person's favorite
///   (BunnyCollectionService) — the one widgets/rabbit_mascot.dart
///   draws everywhere else in the app. The current favorite is
///   highlighted.
/// - **Someone else's profile** (`readOnly: true`, see
///   screens/friends/friend_profile_screen.dart): no tap, nothing to
///   select — a friend's favorite pick lives only on their own device
///   (BunnyCollectionService is device-local, never synced), so there's
///   no way to know it from here. Highlights their current level tier
///   instead, i.e. "where they've gotten to" rather than "what they
///   picked".
///
/// See /BUNNY_SYSTEM.md.
class BunnyCollectionRow extends StatelessWidget {
  final int level;
  final bool readOnly;
  const BunnyCollectionRow({super.key, required this.level, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    final unlocked = bunniesUnlockedAt(level);
    final highlightId = readOnly
        ? currentTierBunny(level).id
        : context.watch<BunnyCollectionService>().activeBunny(level).id;
    final collection = readOnly ? null : context.read<BunnyCollectionService>();

    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kBunnies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final bunny = kBunnies[i];
          final isUnlocked = unlocked.contains(bunny);
          final isHighlighted = isUnlocked && bunny.id == highlightId;
          return _BunnyTile(
            bunny: bunny,
            unlocked: isUnlocked,
            selected: isHighlighted,
            badge: readOnly ? (isHighlighted ? 'current' : null) : null,
            onTap: (!readOnly && isUnlocked) ? () => collection!.select(bunny.id) : null,
          );
        },
      ),
    );
  }
}

class _BunnyTile extends StatelessWidget {
  final Bunny bunny;
  final bool unlocked;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  const _BunnyTile({
    required this.bunny,
    required this.unlocked,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 88,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent.withOpacity(0.10) : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SeenlyPalette.accent : SeenlyPalette.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 44,
              height: 44 / LevelMascot.aspectRatio,
              child: unlocked
                  ? LevelMascot(level: bunny.unlockLevel, size: 44, animate: selected)
                  : Opacity(
                      opacity: 0.28,
                      child: Icon(Icons.lock_outline, size: 30, color: SeenlyPalette.inkFaint),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              unlocked ? bunny.name : 'level ${bunny.unlockLevel}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.mono(
                size: 9,
                color: unlocked ? SeenlyPalette.inkMuted : SeenlyPalette.inkFaint,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(height: 2),
              Text(
                badge!,
                style: SeenlyText.mono(size: 8, color: SeenlyPalette.accent, weight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
