import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bunny.dart';

/// The person's choice of which unlocked bunny keeps them company
/// around the app — backs the profile's "your bunny collection"
/// section and every place the companion is drawn (see
/// /BUNNY_SYSTEM.md). Device-only SharedPreferences, same pattern as
/// the other small look/feel prefs (RabbitMascotPrefsService,
/// ThemePrefsService, ...) — this is a look, not account data.
///
/// No selection saved yet, or a saved id that isn't unlocked at the
/// person's current level (e.g. a stale id from a bunny that no longer
/// exists) → [activeBunny] falls back to [currentTierBunny], i.e. the
/// bunny always matches the person's real level until they actually
/// pick a favorite.
class BunnyCollectionService extends ChangeNotifier {
  static const _selectedIdKey = 'seenly_selected_bunny_id';
  static const _guideSeenKey = 'seenly_bunny_guide_seen';

  String? _selectedId;
  String? get selectedId => _selectedId;

  bool _guideSeen = false;
  /// Whether the person has ever opened the "what's a bunny?" guide
  /// (widgets/bunny_guide_sheet.dart) — profile_screen.dart shows a
  /// small dot next to the info icon until this flips true, so the
  /// explainer actually gets noticed the first time someone reaches
  /// the collection section instead of sitting there unopened forever.
  bool get guideSeen => _guideSeen;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedId = prefs.getString(_selectedIdKey);
    _guideSeen = prefs.getBool(_guideSeenKey) ?? false;
    notifyListeners();
  }

  Future<void> markGuideSeen() async {
    if (_guideSeen) return;
    _guideSeen = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guideSeenKey, true);
  }

  /// Only meaningful if [bunnyId] is actually unlocked at the person's
  /// level — callers (the collection grid) should only ever offer this
  /// for unlocked tiles, but this doesn't re-check itself since it has
  /// no level of its own to check against.
  Future<void> select(String bunnyId) async {
    if (_selectedId == bunnyId) return;
    _selectedId = bunnyId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedIdKey, bunnyId);
  }

  /// The bunny to actually draw right now, given the person's current
  /// level — every mascot call site in the app goes through this
  /// rather than picking a tier itself.
  Bunny activeBunny(int level) {
    final unlocked = bunniesUnlockedAt(level);
    if (unlocked.isEmpty) return currentTierBunny(level);
    final id = _selectedId;
    if (id != null) {
      for (final b in unlocked) {
        if (b.id == id) return b;
      }
    }
    return unlocked.last;
  }
}
