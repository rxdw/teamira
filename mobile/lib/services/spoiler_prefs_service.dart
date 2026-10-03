import 'package:flutter/foundation.dart';

import 'persisted_pref.dart';
import '../analytics/analytics.dart';

/// Settings > spoilers: whether a title's synopsis and whether written
/// reviews get a soft blurred veil (see widgets/spoiler_veil.dart) until
/// someone taps to reveal them.
///
/// The two defaults are deliberately different, since the two kinds of
/// text carry very different risk: a synopsis is usually just setup
/// (TMDB/studio copy, written not to spoil), so it starts unveiled —
/// [blurDescriptions] defaults to false. A stranger's written review is a
/// different animal — plenty of people just say what happens — so
/// [blurReviews] defaults to true. Either can be flipped independently
/// in Settings.
///
/// Same device-only SharedPreferences pattern as [CoViewPrefsService].
class SpoilerPrefsService extends ChangeNotifier {
  final _blurDescriptions = PersistedPref.boolean('seenly_spoiler_blur_descriptions');
  final _blurReviews = PersistedPref.boolean('seenly_spoiler_blur_reviews', defaultValue: true);

  bool get blurDescriptions => _blurDescriptions.value;
  bool get blurReviews => _blurReviews.value;

  Future<void> load() async {
    await _blurDescriptions.load();
    await _blurReviews.load();
    notifyListeners();
  }

  Future<void> setBlurDescriptions(bool value) async {
    await _blurDescriptions.save(value, onChanged: notifyListeners);
    Analytics.instance.track('setting_changed', {'setting': 'blur_descriptions', 'value': value});
  }

  Future<void> setBlurReviews(bool value) async {
    await _blurReviews.save(value, onChanged: notifyListeners);
    Analytics.instance.track('setting_changed', {'setting': 'blur_reviews', 'value': value});
  }
}
