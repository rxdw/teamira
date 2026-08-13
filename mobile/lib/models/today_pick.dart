import 'collection.dart';

/// Mirrors `TodayPickOut` in backend/app/schemas.py — the Home screen's
/// "today's pick" card: one franchise shelf, plus how far the current
/// user already is into it. See FeedService.todayPick() /
/// GET /feed/today-pick.
class TodayPick {
  final SeenlyCollection collection;
  final int watchedCount;
  final int totalCount;
  // ISO `YYYY-MM-DD`, server-side (UTC) — the same for every user on a
  // given day. TodayPickPrefsService keys its "dismissed" / "seen" state
  // off this rather than the device's own clock, so a midnight rollover
  // the device just hasn't noticed yet doesn't leave a stale dismissal
  // hiding a pick that's actually already tomorrow's.
  final String pickDate;

  const TodayPick({
    required this.collection,
    required this.watchedCount,
    required this.totalCount,
    required this.pickDate,
  });

  /// True when the server had nothing to offer (e.g. TMDB unreachable) —
  /// an empty-titled, empty collection rather than a null response. The
  /// card should render nothing in this case, same as any other
  /// "nothing to show right now" shelf.
  bool get isEmpty => collection.items.isEmpty;

  double get progress => totalCount == 0 ? 0.0 : (watchedCount / totalCount).clamp(0.0, 1.0);

  factory TodayPick.fromJson(Map<String, dynamic> json) => TodayPick(
        collection: SeenlyCollection.fromJson(json['collection'] as Map<String, dynamic>),
        watchedCount: json['watched_count'] as int? ?? 0,
        totalCount: json['total_count'] as int? ?? 0,
        pickDate: json['pick_date'] as String? ?? '',
      );
}
