import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings > co-viewing: whether a Watch Together match (one-phone or
/// network mode) should also be dropped onto *your own* personal "watch
/// together" list, in addition to wherever it already lands.
///
/// This never touches the shared co-viewing screen a linked partner has —
/// that one always gets every match, on purpose, since it's the whole
/// point of linking (see backend/app/routers/partner.py's
/// add_coview_entries and the docstring on _add_match_to_both_lists in
/// together.py). Turning this off just means matches stop also piling up
/// on *your* solo watch-later shelf.
///
/// Same device-only SharedPreferences pattern as [RitualPrefsService].
/// For network sessions this value is sent along with the create/join
/// call (see TogetherService.create/join) since the match itself is
/// decided on the server; for one-phone mode TogetherScreen reads it
/// directly before adding a match to the local list.
class CoViewPrefsService extends ChangeNotifier {
  static const _addToOwnListKey = 'seenly_coview_add_matches_to_own_list';
  static const _seenGuideKey = 'seenly_coview_seen_guide';

  bool _addMatchesToOwnList = true;
  bool get addMatchesToOwnList => _addMatchesToOwnList;

  bool _hasSeenGuide = false;
  bool get hasSeenGuide => _hasSeenGuide;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _addMatchesToOwnList = prefs.getBool(_addToOwnListKey) ?? true;
    _hasSeenGuide = prefs.getBool(_seenGuideKey) ?? false;
    notifyListeners();
  }

  Future<void> markGuideSeen() async {
    if (_hasSeenGuide) return;
    _hasSeenGuide = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenGuideKey, true);
  }

  Future<void> setAddMatchesToOwnList(bool value) async {
    if (_addMatchesToOwnList == value) return;
    _addMatchesToOwnList = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_addToOwnListKey, value);
  }
}
