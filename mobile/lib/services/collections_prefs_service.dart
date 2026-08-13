import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether this device has been through the Collections "what
/// are you into" picker yet, and what was chosen — same pattern
/// [ApiClient] uses for the auth token: plain [SharedPreferences], no
/// backend endpoint involved. This is a shelf-arranging preference, not
/// account data, so it's fine for it to live only on this device.
class CollectionsPrefsService {
  static const _onboardedKey = 'seenly_collections_onboarded';
  static const _interestsKey = 'seenly_collections_interests';

  Future<bool> hasOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardedKey) ?? false;
  }

  Future<Set<String>> loadInterests() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_interestsKey) ?? const []).toSet();
  }

  Future<void> saveInterests(Set<String> interests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
    await prefs.setStringList(_interestsKey, interests.toList());
  }
}
