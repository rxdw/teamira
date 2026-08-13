import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _blurDescriptionsKey = 'seenly_spoiler_blur_descriptions';
  static const _blurReviewsKey = 'seenly_spoiler_blur_reviews';

  bool _blurDescriptions = false;
  bool get blurDescriptions => _blurDescriptions;

  bool _blurReviews = true;
  bool get blurReviews => _blurReviews;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _blurDescriptions = prefs.getBool(_blurDescriptionsKey) ?? false;
    _blurReviews = prefs.getBool(_blurReviewsKey) ?? true;
    notifyListeners();
  }

  Future<void> setBlurDescriptions(bool value) async {
    if (_blurDescriptions == value) return;
    _blurDescriptions = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_blurDescriptionsKey, value);
  }

  Future<void> setBlurReviews(bool value) async {
    if (_blurReviews == value) return;
    _blurReviews = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_blurReviewsKey, value);
  }
}
