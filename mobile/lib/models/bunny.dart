import 'package:flutter/foundation.dart';

/// One companion ("заяц") in Seenly's level-based rabbit collection —
/// the character that shows up around the app (after logging, on the
/// welcome screen, loading states, empty states, achievements, ...)
/// instead of one fixed mascot.
///
/// Every bunny unlocks at a specific real level (see
/// backend/app/routers/profile.py::_compute_level for how level itself
/// is computed from actual logged activity) and, once unlocked, stays
/// unlocked forever in the person's collection.
///
/// See /BUNNY_SYSTEM.md at the repo root for the full guide on adding a
/// new tier — this file is the only thing that needs a new entry.
@immutable
class Bunny {
  /// Stable identifier — saved as the person's selection
  /// (BunnyCollectionService) and never shown in the UI, so it's safe
  /// to keep even if [name] changes later.
  final String id;

  /// The level this bunny unlocks at. Sort [kBunnies] ascending by this.
  final int unlockLevel;

  /// Shown in the profile's "bunny collection" and the level list.
  final String name;

  final String lightAsset;
  final String darkAsset;

  const Bunny({
    required this.id,
    required this.unlockLevel,
    required this.name,
    required this.lightAsset,
    required this.darkAsset,
  });

  String assetFor(bool isDark) => isDark ? darkAsset : lightAsset;
}

/// -----------------------------------------------------------------------
/// THE COLLECTION. Add new tiers here — see /BUNNY_SYSTEM.md for the
/// exact steps (art requirements + what to paste). Every screen that
/// shows a bunny (profile's collection grid, the level list, the
/// companion drawn around the app) reads from this list automatically;
/// nothing else needs to change to add a level 10/15/... tier.
///
/// Keep entries sorted ascending by unlockLevel.
/// -----------------------------------------------------------------------
const List<Bunny> kBunnies = [
  Bunny(
    id: 'popcorn',
    unlockLevel: 1,
    name: 'popcorn bunny',
    lightAsset: 'assets/mascot/bunny_with_popcorn_level1.png',
    darkAsset: 'assets/mascot/bunnyDark_with_popcorn_level1.png',
  ),
  Bunny(
    id: 'critic',
    unlockLevel: 5,
    name: 'critic bunny',
    lightAsset: 'assets/mascot/bunny_critic_level5.png',
    darkAsset: 'assets/mascot/bunnyDark_critic_level5.png',
  ),
];

/// Every bunny a given level has unlocked, oldest first.
List<Bunny> bunniesUnlockedAt(int level) =>
    kBunnies.where((b) => level >= b.unlockLevel).toList(growable: false);

/// The bunny that matches someone's level exactly — i.e. "show
/// progress", not "show what I picked". Used by the level list (each
/// milestone card shows its own tier) and as the fallback when no
/// selection has been made yet. Falls back to the very first tier if,
/// somehow, nothing has unlocked (shouldn't happen since level 1 always
/// unlocks the first entry).
Bunny currentTierBunny(int level) {
  final unlocked = bunniesUnlockedAt(level);
  return unlocked.isEmpty ? kBunnies.first : unlocked.last;
}

/// Look up a bunny by its saved id — null if unknown (e.g. a stale
/// preference from a bunny that no longer exists).
Bunny? bunnyById(String id) {
  for (final b in kBunnies) {
    if (b.id == id) return b;
  }
  return null;
}

/// Levels that actually introduce a new tier — used by the level list
/// to say "a new look for your companion" only where that's true,
/// rather than on every single level.
List<int> get bunnyArtLevels => kBunnies.map((b) => b.unlockLevel).toList(growable: false);
