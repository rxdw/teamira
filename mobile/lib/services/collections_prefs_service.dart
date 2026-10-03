import 'persisted_pref.dart';

/// Remembers whether this device has been through the Collections "what
/// are you into" picker yet, and what was chosen — same pattern
/// [ApiClient] uses for the auth token: plain [SharedPreferences], no
/// backend endpoint involved. This is a shelf-arranging preference, not
/// account data, so it's fine for it to live only on this device.
class CollectionsPrefsService {
  final _onboarded = PersistedPref.boolean('seenly_collections_onboarded');
  final _interests = PersistedPref.stringSet('seenly_collections_interests');

  Future<bool> hasOnboarded() async {
    await _onboarded.load();
    return _onboarded.value;
  }

  Future<Set<String>> loadInterests() async {
    await _interests.load();
    return _interests.value;
  }

  Future<void> saveInterests(Set<String> interests) async {
    await _onboarded.save(true);
    await _interests.save(interests);
  }
}
