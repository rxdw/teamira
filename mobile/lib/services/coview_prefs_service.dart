import 'package:flutter/foundation.dart';

import 'persisted_pref.dart';

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
  final _addMatchesToOwnList =
      PersistedPref.boolean('seenly_coview_add_matches_to_own_list', defaultValue: true);
  final _hasSeenGuide = PersistedPref.boolean('seenly_coview_seen_guide');

  bool get addMatchesToOwnList => _addMatchesToOwnList.value;
  bool get hasSeenGuide => _hasSeenGuide.value;

  Future<void> load() async {
    await _addMatchesToOwnList.load();
    await _hasSeenGuide.load();
    notifyListeners();
  }

  Future<void> markGuideSeen() async {
    await _hasSeenGuide.save(true, onChanged: notifyListeners);
  }

  Future<void> setAddMatchesToOwnList(bool value) async {
    await _addMatchesToOwnList.save(value, onChanged: notifyListeners);
  }
}
