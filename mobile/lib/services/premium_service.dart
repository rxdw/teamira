import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Solo account, or two people sharing one subscription (see
/// [PremiumScreen]'s top toggle — "на одного" / "на пару"). Couple is
/// priced below double the solo price on purpose, so it reads as the
/// obviously better deal for two people rather than just "solo + tax".
enum PremiumPlanKind { individual, couple }

/// Billing length. Six months rather than three — long enough that the
/// discount actually reads as a discount, short enough not to only ever
/// show the annual price as "the real one".
enum PremiumDuration { month, sixMonths, year }

extension PremiumDurationInfo on PremiumDuration {
  int get months => switch (this) {
        PremiumDuration.month => 1,
        PremiumDuration.sixMonths => 6,
        PremiumDuration.year => 12,
      };
}

/// All prices in rubles, one flat total for the whole period (not a
/// per-month recurring amount) — same "pay once for the stretch you
/// picked" shape the rest of this demo app's local-only services use.
/// Couple is deliberately less than 2x individual at every length, and
/// the gift table below is deliberately a little cheaper than the
/// matching individual price, since a gift is a one-off rather than a
/// standing subscription.
class PremiumPricing {
  const PremiumPricing._();

  static const Map<PremiumDuration, int> individual = {
    PremiumDuration.month: 299,
    PremiumDuration.sixMonths: 1490,
    PremiumDuration.year: 2390,
  };

  static const Map<PremiumDuration, int> couple = {
    PremiumDuration.month: 399,
    PremiumDuration.sixMonths: 1990,
    PremiumDuration.year: 3190,
  };

  static const Map<PremiumDuration, int> gift = {
    PremiumDuration.month: 249,
    PremiumDuration.sixMonths: 1190,
    PremiumDuration.year: 1890,
  };

  static int priceFor(PremiumPlanKind kind, PremiumDuration duration) =>
      (kind == PremiumPlanKind.couple ? couple : individual)[duration]!;

  static int perMonth(PremiumPlanKind kind, PremiumDuration duration) =>
      (priceFor(kind, duration) / duration.months).round();

  /// Per-person monthly cost on the couple plan — the number that makes
  /// "на пару выгоднее" visible rather than just claimed.
  static int perPersonPerMonth(PremiumDuration duration) =>
      (couple[duration]! / duration.months / 2).round();

  /// % saved on the monthly-equivalent price vs. paying month-to-month
  /// at that same plan kind, rounded down — drives the "-33%" style
  /// badge on the longer options.
  static int savePercent(PremiumPlanKind kind, PremiumDuration duration) {
    if (duration == PremiumDuration.month) return 0;
    final base = perMonth(kind, PremiumDuration.month);
    final now = perMonth(kind, duration);
    if (base <= 0) return 0;
    return (100 * (1 - now / base)).floor();
  }

  static int giftSavePercent(PremiumDuration duration) {
    final regular = individual[duration]!;
    final giftPrice = gift[duration]!;
    if (regular <= 0) return 0;
    return (100 * (1 - giftPrice / regular)).floor();
  }
}

/// Local-only stand-in for a real subscription/billing backend — same
/// spirit as every other `*_prefs_service.dart` in this app: plain
/// [SharedPreferences], no network call, since there's no payment
/// provider wired up yet. [purchase] flips state the same way a
/// successful checkout eventually will.
///
/// Also carries the two free-tier ceilings premium lifts: AI asks
/// (teamira's "ask" card on Home) and favorite films. Both are tracked
/// device-locally and reset accordingly — AI asks on the calendar
/// month, favorites by syncing against the real count whenever Profile
/// loads the person's collections (see ProfileScreen._load).
class PremiumService extends ChangeNotifier {
  static const _isPremiumKey = 'seenly_premium_active';
  static const _planKindKey = 'seenly_premium_kind';
  static const _durationKey = 'seenly_premium_duration';
  static const _aiCountKey = 'seenly_premium_ai_count';
  static const _aiMonthKey = 'seenly_premium_ai_month';
  static const _favCountKey = 'seenly_premium_fav_count';

  static const int freeAiAsksPerMonth = 3;
  static const int freeFavoritesLimit = 5;

  bool _isPremium = false;
  PremiumPlanKind? _planKind;
  PremiumDuration? _planDuration;
  int _aiAsksUsed = 0;
  int _favoritesCount = 0;

  bool get isPremium => _isPremium;
  PremiumPlanKind? get planKind => _planKind;
  PremiumDuration? get planDuration => _planDuration;
  int get favoritesCount => _favoritesCount;
  int get aiAsksUsed => _aiAsksUsed;
  int get aiAsksRemaining =>
      (freeAiAsksPerMonth - _aiAsksUsed).clamp(0, freeAiAsksPerMonth);

  bool get canAskAi => _isPremium || _aiAsksUsed < freeAiAsksPerMonth;
  bool get canAddFavorite =>
      _isPremium || _favoritesCount < freeFavoritesLimit;

  String get _currentMonthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month}';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isPremium = prefs.getBool(_isPremiumKey) ?? false;
    final kindStored = prefs.getString(_planKindKey);
    _planKind = kindStored == 'couple'
        ? PremiumPlanKind.couple
        : kindStored == 'individual'
            ? PremiumPlanKind.individual
            : null;
    final durationStored = prefs.getString(_durationKey);
    _planDuration = switch (durationStored) {
      'month' => PremiumDuration.month,
      'sixMonths' => PremiumDuration.sixMonths,
      'year' => PremiumDuration.year,
      _ => null,
    };

    final storedMonth = prefs.getString(_aiMonthKey);
    _aiAsksUsed = prefs.getInt(_aiCountKey) ?? 0;
    if (storedMonth != _currentMonthKey) {
      _aiAsksUsed = 0;
      await prefs.setString(_aiMonthKey, _currentMonthKey);
      await prefs.setInt(_aiCountKey, 0);
    }

    _favoritesCount = prefs.getInt(_favCountKey) ?? 0;
    notifyListeners();
  }

  /// Call right before an AI ask actually goes out. Returns false (and
  /// leaves the counter untouched) when the free monthly ceiling is
  /// already hit — callers should show the upsell instead of
  /// navigating on a false result.
  Future<bool> recordAiAsk() async {
    if (!canAskAi) return false;
    if (_isPremium) return true;
    _aiAsksUsed += 1;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_aiCountKey, _aiAsksUsed);
    await prefs.setString(_aiMonthKey, _currentMonthKey);
    return true;
  }

  /// Reconciles the local favorites counter against the real count from
  /// the account's collections (see ProfileScreen._load /
  /// _allFavoriteMovies) — the source of truth for whether the free
  /// ceiling has actually been hit.
  void syncFavoritesCount(int count) {
    if (_favoritesCount == count) return;
    _favoritesCount = count;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setInt(_favCountKey, count));
  }

  /// Optimistic local bump so a just-added favorite is reflected before
  /// the next full Profile reload — mirrors the optimistic-then-confirm
  /// pattern the toggle call sites themselves already use.
  void noteFavoriteAdded() => syncFavoritesCount(_favoritesCount + 1);
  void noteFavoriteRemoved() =>
      syncFavoritesCount((_favoritesCount - 1).clamp(0, 1 << 30));

  Future<void> purchase(PremiumPlanKind kind, PremiumDuration duration) async {
    _isPremium = true;
    _planKind = kind;
    _planDuration = duration;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isPremiumKey, true);
    await prefs.setString(
        _planKindKey, kind == PremiumPlanKind.couple ? 'couple' : 'individual');
    await prefs.setString(_durationKey, switch (duration) {
      PremiumDuration.month => 'month',
      PremiumDuration.sixMonths => 'sixMonths',
      PremiumDuration.year => 'year',
    });
  }
}
