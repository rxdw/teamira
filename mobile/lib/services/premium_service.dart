import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import '../analytics/analytics.dart';

/// Solo account, two people, or a small company sharing one subscription
/// (see [PremiumScreen]'s plan picker — "на одного" / "на пару" /
/// "семья и друзья"). Each shared plan is priced well below the same
/// number of solo plans on purpose, so it reads as the obviously better
/// deal rather than just "solo + tax".
enum PremiumPlanKind { individual, couple, family }

extension PremiumPlanKindInfo on PremiumPlanKind {
  /// How many people one purchase of this plan covers, the payer
  /// included. Mirrors `PLAN_SEATS` in backend/app/routers/premium.py —
  /// the server is the authority (it also echoes the number back as
  /// `plan_seats`, see [PremiumService.planSeats]); this copy only feeds
  /// the price-per-person line before anything has been bought.
  int get seats => switch (this) {
        PremiumPlanKind.individual => 1,
        PremiumPlanKind.couple => 2,
        PremiumPlanKind.family => 4,
      };

  static PremiumPlanKind? parse(String? raw) => switch (raw) {
        'individual' => PremiumPlanKind.individual,
        'couple' => PremiumPlanKind.couple,
        'family' => PremiumPlanKind.family,
        _ => null,
      };
}

/// Billing length. `sixMonths` stays in this enum only so a historical
/// purchase/gift already on that plan still deserializes and displays
/// correctly (see PremiumPricing.individual/couple/gift below, which
/// still carry its price) — it's no longer offered as a choice
/// anywhere in the UI. [purchasableDurations] is the list every
/// duration picker should actually iterate over; see its own doc
/// comment.
enum PremiumDuration { month, threeMonths, sixMonths, year }

extension PremiumDurationInfo on PremiumDuration {
  int get months => switch (this) {
        PremiumDuration.month => 1,
        PremiumDuration.threeMonths => 3,
        PremiumDuration.sixMonths => 6,
        PremiumDuration.year => 12,
      };
}

/// The durations a person can actually pick today — deliberately
/// excludes [PremiumDuration.sixMonths] (see that value's own comment).
/// Every duration picker (PremiumScreen's `_DurationList`,
/// GiftPremiumScreen's `_GiftDurationList`) iterates this instead of
/// `PremiumDuration.values`.
const List<PremiumDuration> purchasableDurations = [
  PremiumDuration.month,
  PremiumDuration.threeMonths,
  PremiumDuration.year,
];

/// All prices in rubles, one flat total for the whole period (not a
/// per-month recurring amount) — same "pay once for the stretch you
/// picked" shape the rest of this demo app's local-only services use.
/// Couple is deliberately less than 2x individual at every length, family
/// (up to four people) less than 2x couple, with the same ~12% / ~33%
/// discount for three months / a year — so the better deal per person
/// never depends on which length someone picks. The gift table below is
/// deliberately a little cheaper than the matching individual price,
/// since a gift is a one-off rather than a standing subscription.
class PremiumPricing {
  const PremiumPricing._();

  static const Map<PremiumDuration, int> individual = {
    PremiumDuration.month: 299,
    PremiumDuration.threeMonths: 799,
    PremiumDuration.sixMonths: 1490, // legacy — see PremiumDuration.sixMonths
    PremiumDuration.year: 2390,
  };

  static const Map<PremiumDuration, int> couple = {
    PremiumDuration.month: 399,
    PremiumDuration.threeMonths: 1050,
    PremiumDuration.sixMonths: 1990, // legacy — see PremiumDuration.sixMonths
    PremiumDuration.year: 3190,
  };

  static const Map<PremiumDuration, int> family = {
    PremiumDuration.month: 549,
    PremiumDuration.threeMonths: 1450,
    PremiumDuration.sixMonths: 2740, // legacy — see PremiumDuration.sixMonths
    PremiumDuration.year: 4390,
  };

  static const Map<PremiumDuration, int> gift = {
    PremiumDuration.month: 249,
    PremiumDuration.threeMonths: 649,
    PremiumDuration.sixMonths: 1190, // legacy — see PremiumDuration.sixMonths
    PremiumDuration.year: 1890,
  };

  static int priceFor(PremiumPlanKind kind, PremiumDuration duration) =>
      (switch (kind) {
        PremiumPlanKind.individual => individual,
        PremiumPlanKind.couple => couple,
        PremiumPlanKind.family => family,
      })[duration]!;

  static int perMonth(PremiumPlanKind kind, PremiumDuration duration) =>
      (priceFor(kind, duration) / duration.months).round();

  /// Per-person monthly cost on a shared plan, assuming every seat is
  /// used — the number that makes "выгоднее вдвоём / всей компанией"
  /// visible rather than just claimed.
  static int perPersonPerMonth(PremiumPlanKind kind, PremiumDuration duration) =>
      (priceFor(kind, duration) / duration.months / kind.seats).round();

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

  /// Whole months' worth of the plan's own monthly price saved by
  /// paying for [duration] up front instead of month-to-month — the
  /// "≈ 4 months free" framing on the year option. Always computed from
  /// the same tables the price itself comes from, so the line can never
  /// drift from what's actually charged; 0 (not shown) whenever the
  /// saving doesn't add up to at least one full month.
  static int freeMonths(PremiumPlanKind kind, PremiumDuration duration) {
    if (duration == PremiumDuration.month) return 0;
    final monthly = priceFor(kind, PremiumDuration.month);
    if (monthly <= 0) return 0;
    final saved = monthly * duration.months - priceFor(kind, duration);
    return saved <= 0 ? 0 : saved ~/ monthly;
  }

  /// [price] with [percent] taken off, to a whole ruble — the one place
  /// a discounted price is computed (the win-back card, the plan rows and
  /// the buy button all read it), so they can't show different numbers.
  static int discounted(int price, int percent) =>
      (price * (100 - percent) / 100).round();

  static int giftSavePercent(PremiumDuration duration) {
    final regular = individual[duration]!;
    final giftPrice = gift[duration]!;
    if (regular <= 0) return 0;
    return (100 * (1 - giftPrice / regular)).floor();
  }
}

/// The account's own premium subscription state, synced against the
/// server (see backend/app/routers/premium.py) with local
/// [SharedPreferences] as a fast, offline-tolerant cache — same "server
/// is truth, local is cache" shape used to fix the multi-device/
/// reinstall problem the old local-only version had (see that
/// docstring, kept below for history on the fields it introduced).
///
/// [load] (called before runApp, like every other device-only prefs
/// service — see main.dart) only ever reads the local cache: there's no
/// signed-in account yet at that point in startup to sync against.
/// [reloadForUser] is the actual sync point, called from
/// app.dart's `_AccountScopedPrefsScope` whenever the signed-in account
/// resolves or changes — same trigger EveningPlanService/
/// TodayPickPrefsService/OnThisDayPrefsService/SavedPeriodsService
/// already use for their own account-scoped state. A failed sync
/// (offline, server unreachable) just leaves the local cache as the
/// current best guess rather than surfacing an error — nothing reads
/// this service's getters knowing whether the last sync succeeded, and
/// the whole point of caching locally is that a moment offline
/// shouldn't suddenly make every premium check act as if the account
/// were free.
///
/// Also carries every free-tier ceiling premium lifts: AI asks
/// (teamira's "ask" card on Home) are now tracked server-side too (see
/// [recordAiAsk]) since that's the one counter that actually needs to
/// be shared across devices for the limit to mean anything; favorite
/// films are still tracked device-locally and reconciled against the
/// real count whenever Profile loads the person's collections (see
/// ProfileScreen._load) — that one was never the state-consistency
/// problem the AI-asks counter and the premium flag itself were, since
/// it already gets corrected from a real server fact on every load.
/// Co-viewing circle size and list count aren't tracked here at all,
/// since both are server facts already visible elsewhere
/// (PartnerStatus.members, ListsService.all) — see [canGrowCoViewCircle]
/// and [canAddList], which take the real count as a parameter instead.
class PremiumService extends ChangeNotifier {
  final ApiClient _client = ApiClient.instance;

  static const _isPremiumKey = 'seenly_premium_active';
  static const _planKindKey = 'seenly_premium_kind';
  static const _durationKey = 'seenly_premium_duration';
  static const _aiCountKey = 'seenly_premium_ai_count';
  static const _aiMonthKey = 'seenly_premium_ai_month';
  static const _favCountKey = 'seenly_premium_fav_count';

  static const int freeAiAsksPerMonth = 3;
  static const int freeFavoritesLimit = 5;
  static const int freeListsLimit = 5;
  // A couple (you + one other person) stays free forever — this only
  // gates growing that into a company. Not a locally-tracked counter
  // like the two above, since circle membership is a server fact (see
  // PartnerStatus.members): callers pass in the real count they
  // already have rather than this service tracking its own.
  static const int freeCoViewCircleSize = 2;

  bool _isPremium = false;
  PremiumPlanKind? _planKind;
  // People this account's own purchase covers — PremiumStatusOut.
  // plan_seats. Null without a purchase (and for someone who is only
  // covered by another person's plan).
  int? _planSeats;
  PremiumDuration? _planDuration;
  int _aiAsksUsed = 0;
  int _favoritesCount = 0;
  // Referral-granted bonus expiry (see models.UserPremiumState.
  // premium_expires_at on the backend) — purely informational here;
  // [isPremium] already reflects it since the server folds both sources
  // together before ever answering. Null for an account that has never
  // received a referral bonus, regardless of whether it's premium via
  // an actual purchase.
  DateTime? _premiumExpiresAt;

  // Whether POST /premium/start-trial is still open to this account —
  // see PremiumStatusOut.trial_available on the backend. Defaults to
  // true (rather than false) before the first server sync, same
  // optimistic-default reasoning as the rest of this class's local
  // cache: showing the trial CTA for a moment on a brand-new install,
  // before [reloadForUser] has ever run, is the harmless direction to
  // be wrong in — the opposite (hiding a trial someone is actually
  // eligible for) is the one that costs a conversion.
  bool _trialAvailable = true;
  int _trialDays = 3;

  // Where the account is in its free period — mirrors
  // PremiumStatusOut.trial_phase / trial_ends_at / trial_logged_count on
  // the backend (see app/trial.py): 'active', 'expired', or null.
  String? _trialPhase;
  DateTime? _trialEndsAt;
  int _trialLoggedCount = 0;

  // "own" | "partner" | null — see PremiumStatusOut.premium_source.
  String? _premiumSource;

  // A purchased plan's life — mirrors PremiumStatusOut.subscription_phase
  // and friends (backend app/subscription.py): 'active', 'cancelling'
  // (cancelled, still running until [cancelEffectiveAt]), 'paused' (until
  // [pausedUntil]), 'lapsed' (cancelled and run out — the win-back
  // moment) or null for an account that never bought anything.
  String? _subscriptionPhase;
  DateTime? _paidUntil;
  DateTime? _cancelEffectiveAt;
  DateTime? _pausedUntil;
  bool _pauseAvailable = false;
  int _pauseDays = 30;
  // The personal comeback discount open right now, if any.
  int? _winbackPercent;
  DateTime? _winbackExpiresAt;
  // Which kind of discount the last purchase used ('promo' | 'winback') —
  // a one-shot receipt like the percent [purchase] returns, for the
  // success sheet's wording.
  String? _lastDiscountKind;

  // Who the nudge bookkeeping below is scoped to; set by [reloadForUser].
  String? _userId;

  bool get isPremium => _isPremium;
  PremiumPlanKind? get planKind => _planKind;

  /// How many people the plan this account *bought* covers, itself
  /// included; null when it has bought nothing. Prefers the number the
  /// server sent, falling back to the plan kind's own for a cache
  /// written before the field existed.
  int? get planSeats => _planSeats ?? _planKind?.seats;

  /// Whether adding one more person to a circle that has
  /// [currentMemberCount] people now would push it past what the plan
  /// this account bought can cover — a couple plan covers two, a family
  /// plan four; past that, *nobody* in the circle is covered (see
  /// backend `_seat_covers`). False for a solo plan (it never covered
  /// anyone else) and for accounts with no purchase, so the caller only
  /// warns someone who is about to lose something they're paying for.
  bool circleOutgrowsPlan(int currentMemberCount) {
    final seats = planSeats;
    if (_premiumSource != 'own' || seats == null || seats < 2) return false;
    return currentMemberCount + 1 > seats;
  }
  PremiumDuration? get planDuration => _planDuration;
  int get favoritesCount => _favoritesCount;
  int get aiAsksUsed => _aiAsksUsed;
  DateTime? get premiumExpiresAt => _premiumExpiresAt;
  bool get trialAvailable => _trialAvailable && !_isPremium;
  int get trialDays => _trialDays;

  /// A free period that hasn't run out yet (referral days stacked on it
  /// included). [isPremium] is true during it — features are unlocked —
  /// but nothing has been *bought*, which is exactly why the paywall
  /// must keep offering a purchase instead of "premium is on".
  bool get trialActive => _trialPhase == 'active';

  /// Tried the free period, never bought, and premium has run out.
  bool get trialExpired => _trialPhase == 'expired';
  DateTime? get trialEndsAt => _trialEndsAt;
  int get trialLoggedCount => _trialLoggedCount;

  String? get subscriptionPhase => _subscriptionPhase;
  bool get isPaused => _subscriptionPhase == 'paused';
  bool get isCancelling => _subscriptionPhase == 'cancelling';
  bool get isLapsed => _subscriptionPhase == 'lapsed';

  /// A purchased plan that is still the person's to manage: running,
  /// cancelled-but-running, or paused. A lapsed one isn't — that one goes
  /// back to the paywall (with the win-back offer, if it is still open).
  bool get hasSubscription =>
      _subscriptionPhase == 'active' ||
      _subscriptionPhase == 'cancelling' ||
      _subscriptionPhase == 'paused';

  /// The next renewal of an active plan; null in every other phase.
  DateTime? get paidUntil => _paidUntil;

  /// When a cancelled plan stops working; null unless one was cancelled.
  DateTime? get cancelEffectiveAt => _cancelEffectiveAt;
  DateTime? get pausedUntil => _pausedUntil;
  bool get pauseAvailable => _pauseAvailable;
  int get pauseDays => _pauseDays;
  String? get lastDiscountKind => _lastDiscountKind;

  /// The personal comeback discount, only while it is really open. The
  /// server decides that; the clock check here just stops a stale cache
  /// from advertising an offer that has since run out.
  bool get winbackActive {
    final expires = _winbackExpiresAt;
    return _winbackPercent != null &&
        expires != null &&
        expires.isAfter(DateTime.now());
  }

  int? get winbackPercent => winbackActive ? _winbackPercent : null;
  DateTime? get winbackExpiresAt => winbackActive ? _winbackExpiresAt : null;

  /// Time left on the comeback offer; null when there isn't one.
  Duration? get winbackTimeLeft {
    if (!winbackActive) return null;
    return _winbackExpiresAt!.difference(DateTime.now());
  }

  /// Time left of an active free period, never negative; null when
  /// there isn't one. Read against the device clock, which is fine at
  /// the hour granularity every use of it works at.
  Duration? get trialTimeLeft {
    final ends = _trialEndsAt;
    if (!trialActive || ends == null) return null;
    final left = ends.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether this account already *owns* premium in a way the paywall
  /// has nothing left to sell for: a purchased plan, or coverage by a
  /// partner's couple plan. A trial or referral days do NOT count —
  /// they unlock features ([isPremium]) but still leave the door to a
  /// real purchase open. A paused plan counts: [isPremium] is off while
  /// it is, but the person owns it and comes back to it by resuming, not
  /// by buying again.
  bool get ownsPlan =>
      isPaused ||
      (_isPremium && (_planKind != null || _premiumSource == 'partner'));
  int get aiAsksRemaining =>
      (freeAiAsksPerMonth - _aiAsksUsed).clamp(0, freeAiAsksPerMonth);

  bool get canAskAi => _isPremium || _aiAsksUsed < freeAiAsksPerMonth;
  bool get canAddFavorite =>
      _isPremium || _favoritesCount < freeFavoritesLimit;

  /// Whether one more person can join a co-viewing circle that
  /// currently has [currentMemberCount] people in it (self included).
  /// A couple — two people — is always free; a third seat is premium.
  /// Call this right before sending an invite or accepting one; show
  /// the upsell instead of proceeding on a false result.
  bool canGrowCoViewCircle(int currentMemberCount) =>
      _isPremium || currentMemberCount < freeCoViewCircleSize;

  /// Whether one more custom list can be created, given the account
  /// already has [currentListCount] of them. Not a locally-tracked
  /// counter like favorites — list count is a server fact (see
  /// ListsService.all) — so, same shape as [canGrowCoViewCircle],
  /// callers pass in the real count rather than this service tracking
  /// its own. Call this right before ListsService.create; show the
  /// upsell instead of proceeding on a false result.
  bool canAddList(int currentListCount) =>
      _isPremium || currentListCount < freeListsLimit;

  String get _currentMonthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month}';
  }

  /// Local-cache-only load, called before runApp — see this class's own
  /// docstring for why the server sync is a separate step
  /// ([reloadForUser]) rather than happening here.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isPremium = prefs.getBool(_isPremiumKey) ?? false;
    _planKind = PremiumPlanKindInfo.parse(prefs.getString(_planKindKey));
    final durationStored = prefs.getString(_durationKey);
    _planDuration = switch (durationStored) {
      'month' => PremiumDuration.month,
      'threeMonths' => PremiumDuration.threeMonths,
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

  /// Syncs this account's premium state from the server — the actual
  /// fix for "bought premium on one device, another device signed into
  /// the same account doesn't know it" (see backend/app/routers/
  /// premium.py's own docstring). Called from app.dart's
  /// `_AccountScopedPrefsScope` whenever the signed-in account resolves
  /// or changes, same trigger four other account-scoped services
  /// already use — `userId == null` (signed out) just leaves the local
  /// cache as-is rather than clearing it, same as those.
  Future<void> reloadForUser(String? userId) async {
    if (userId == null) return;
    _userId = userId;
    try {
      final json = await _client.get('/premium/status') as Map<String, dynamic>;
      await _applyServerStatus(json);
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getBool(_expiredBannerKey) ?? false;
      if (dismissed != _expiredBannerDismissed) {
        _expiredBannerDismissed = dismissed;
        notifyListeners();
      }
    } catch (_) {
      // Offline, or the server's unreachable — keep whatever the local
      // cache already had (either last successful sync, or the
      // local-only defaults on a brand new install). See this class's
      // own docstring on why a failed sync isn't surfaced as an error.
    }
  }

  static DateTime? _parseDate(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() : null;

  Future<void> _applyServerStatus(Map<String, dynamic> json) async {
    _isPremium = json['is_premium'] as bool? ?? false;
    final kind = json['plan_kind'] as String?;
    _planKind = PremiumPlanKindInfo.parse(kind);
    _planSeats = json['plan_seats'] as int?;
    final duration = json['plan_duration'] as String?;
    _planDuration = switch (duration) {
      'month' => PremiumDuration.month,
      'threeMonths' => PremiumDuration.threeMonths,
      'sixMonths' => PremiumDuration.sixMonths,
      'year' => PremiumDuration.year,
      _ => null,
    };
    _aiAsksUsed = json['ai_asks_used'] as int? ?? _aiAsksUsed;
    final expiresRaw = json['premium_expires_at'] as String?;
    _premiumExpiresAt = expiresRaw != null ? DateTime.tryParse(expiresRaw) : null;
    _trialAvailable = json['trial_available'] as bool? ?? _trialAvailable;
    _trialDays = json['trial_days'] as int? ?? _trialDays;
    _premiumSource = json['premium_source'] as String?;
    _trialPhase = json['trial_phase'] as String?;
    final endsRaw = json['trial_ends_at'] as String?;
    _trialEndsAt = endsRaw != null ? DateTime.tryParse(endsRaw)?.toLocal() : null;
    _trialLoggedCount = json['trial_logged_count'] as int? ?? 0;
    _subscriptionPhase = json['subscription_phase'] as String?;
    _paidUntil = _parseDate(json['paid_until']);
    _cancelEffectiveAt = _parseDate(json['cancel_effective_at']);
    _pausedUntil = _parseDate(json['paused_until']);
    _pauseAvailable = json['pause_available'] as bool? ?? false;
    _pauseDays = json['pause_days'] as int? ?? _pauseDays;
    _winbackPercent = json['winback_percent'] as int?;
    _winbackExpiresAt = _parseDate(json['winback_expires_at']);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isPremiumKey, _isPremium);
    await prefs.setString(_planKindKey, kind ?? '');
    await prefs.setString(_durationKey, duration ?? '');
    await prefs.setInt(_aiCountKey, _aiAsksUsed);
    await prefs.setString(_aiMonthKey, _currentMonthKey);
  }

  /// Call right before an AI ask actually goes out. Returns false (and
  /// leaves the counter untouched) when the free monthly ceiling is
  /// already hit — callers should show the upsell instead of
  /// navigating on a false result.
  ///
  /// Checks in with the server (POST /premium/ai-ask) since this is the
  /// one counter that actually needs to be shared across every device
  /// on the account for the limit to mean anything — a purely local
  /// count could be reset just by asking from a second device. Falls
  /// back to the old local-only optimistic increment if the request
  /// fails, so a moment offline doesn't block Ask Teamira outright; the
  /// next successful [reloadForUser] or [recordAiAsk] reconciles
  /// against the server's own count once reachable again.
  Future<bool> recordAiAsk() async {
    if (!canAskAi) return false;
    if (_isPremium) return true;
    try {
      final json = await _client.post('/premium/ai-ask') as Map<String, dynamic>;
      final allowed = json['allowed'] as bool? ?? true;
      _aiAsksUsed = json['ai_asks_used'] as int? ?? (_aiAsksUsed + 1);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_aiCountKey, _aiAsksUsed);
      await prefs.setString(_aiMonthKey, _currentMonthKey);
      return allowed;
    } catch (_) {
      _aiAsksUsed += 1;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_aiCountKey, _aiAsksUsed);
      await prefs.setString(_aiMonthKey, _currentMonthKey);
      return true;
    }
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

  /// Still not a real checkout (see backend/app/routers/premium.py's
  /// own docstring on that) — this now writes through to the account on
  /// the server rather than only flipping a local flag, so a purchase
  /// made on one device is visible on every other device signed into
  /// the same account, and survives a reinstall. Deliberately lets an
  /// [ApiException] from a failed request propagate instead of quietly
  /// only updating local state — showing "premium unlocked" locally
  /// when the server never recorded it would recreate exactly the kind
  /// of state mismatch this change exists to remove. Callers (see
  /// PremiumScreen._purchase) already handle that, including the 400
  /// an invalid/foreign/already-used [promoCode] comes back as (see
  /// backend routers/premium.py::purchase) — that's a real validation
  /// error the person can act on, not silently ignored.
  ///
  /// Returns the discount percent actually applied this call (see
  /// PremiumStatusOut.applied_discount_percent), or null when no promo
  /// code was redeemed — a one-shot receipt for the purchase-success
  /// sheet, not a standing property, so it's never read back from
  /// [reloadForUser].
  Future<int?> purchase(PremiumPlanKind kind, PremiumDuration duration, {String? promoCode}) async {
    final trimmedPromo = promoCode?.trim();
    final json = await _client.post('/premium/purchase', body: {
      'plan_kind': kind.name,
      'plan_duration': switch (duration) {
        PremiumDuration.month => 'month',
        PremiumDuration.threeMonths => 'threeMonths',
        PremiumDuration.sixMonths => 'sixMonths',
        PremiumDuration.year => 'year',
      },
      if (trimmedPromo != null && trimmedPromo.isNotEmpty) 'promo_code': trimmedPromo,
    }) as Map<String, dynamic>;
    final wasWinback = winbackActive;
    await _applyServerStatus(json);
    _lastDiscountKind = json['applied_discount_kind'] as String?;
    Analytics.instance.track('premium_purchase', {
      'plan_kind': kind.name,
      'duration': duration.name,
      'used_promo': trimmedPromo != null && trimmedPromo.isNotEmpty,
      'used_winback': _lastDiscountKind == 'winback',
      'from_winback_offer': wasWinback,
    });
    return json['applied_discount_percent'] as int?;
  }

  // -------------------------------------------------------------------
  // Keeping people who are about to leave (backend app/subscription.py).
  // Each call lets a real ApiException propagate, like [purchase]: a 400
  // ("pause already used") is a state the screen should show.
  // -------------------------------------------------------------------

  /// Cancel at the end of the period already paid for. Premium keeps
  /// working until [cancelEffectiveAt]; [reason] is the optional chip the
  /// person picked (closed vocabulary, for the analytics only).
  Future<void> cancelSubscription({String? reason}) async {
    final kind = _planKind?.name;
    final json = await _client.post('/premium/cancel') as Map<String, dynamic>;
    await _applyServerStatus(json);
    Analytics.instance.track('subscription_cancelled', {
      'reason': reason ?? 'none',
      'plan_kind': kind,
    });
  }

  /// Freeze the plan for [pauseDays] instead of cancelling it.
  Future<void> pauseSubscription({String? source}) async {
    final json = await _client.post('/premium/pause') as Map<String, dynamic>;
    await _applyServerStatus(json);
    Analytics.instance.track('subscription_paused', {'source': source ?? 'manage'});
  }

  /// End a pause early and/or take back a cancellation that hasn't taken
  /// effect yet.
  Future<void> resumeSubscription() async {
    final from = _subscriptionPhase;
    final json = await _client.post('/premium/resume') as Map<String, dynamic>;
    await _applyServerStatus(json);
    Analytics.instance.track('subscription_resumed', {'from': from});
  }

  String get _winbackNudgeKey => 'seenly_winback_nudge_${_userId ?? ''}';

  /// Whether to open the paywall with the comeback offer right now — once
  /// per offer (an account can only ever have one, but the marker is the
  /// offer's own end time so a future second one would still be shown).
  /// Recording it as shown happens here, so callers must only ask when
  /// they're actually about to show it, same contract as [takeTrialNudge].
  Future<bool> takeWinbackNudge() async {
    final expires = _winbackExpiresAt;
    if (!winbackActive || expires == null || _userId == null) return false;
    final marker = expires.toUtc().toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_winbackNudgeKey) == marker) return false;
    await prefs.setString(_winbackNudgeKey, marker);
    Analytics.instance.track('winback_nudge_shown', {'percent': _winbackPercent});
    return true;
  }

  /// The paywall's "restore purchases" button — same request
  /// [reloadForUser] makes, but this one is user-initiated from a tap
  /// rather than a silent background sync, so a network failure should
  /// actually reach the person as an error instead of quietly keeping
  /// the stale local cache the way [reloadForUser] does on purpose.
  Future<void> restorePurchases() async {
    final json = await _client.get('/premium/status') as Map<String, dynamic>;
    await _applyServerStatus(json);
  }

  /// The paywall's other call-to-action (see [trialAvailable]) — starts
  /// the one-time free trial instead of a purchase. Same "let a real
  /// ApiException propagate" contract as [purchase]: a 400 (trial
  /// already used, see backend routers/premium.py::start_trial) is a
  /// real state the caller should show, not swallow.
  Future<void> startTrial() async {
    final json = await _client.post('/premium/start-trial') as Map<String, dynamic>;
    await _applyServerStatus(json);
    Analytics.instance.track('premium_trial_started', {});
  }

  // -------------------------------------------------------------------
  // The "your free period is ending" moments, in-app half. The server
  // sends the matching pushes (backend app/trial.py); this covers
  // everyone who has push off, and turns each stage into one automatic,
  // skippable paywall — never more than one per stage per account.
  // -------------------------------------------------------------------

  /// 0 = nothing due, 1 = ends soon (<= 36h left), 2 = last hours
  /// (<= 12h left), 3 = it has ended.
  int get trialNudgeStage {
    if (trialExpired) return 3;
    final left = trialTimeLeft;
    if (left == null) return 0;
    if (left <= const Duration(hours: 12)) return 2;
    if (left <= const Duration(hours: 36)) return 1;
    return 0;
  }

  String get _nudgeKey => 'seenly_trial_nudge_stage_${_userId ?? ''}';

  /// Which stage's paywall to open right now, or null. Returning a
  /// stage also records it as shown (per account, on this device), so a
  /// second app open in the same stage stays quiet. Callers must only
  /// ask when they are actually about to show it.
  Future<int?> takeTrialNudge() async {
    final stage = trialNudgeStage;
    if (stage == 0 || _userId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getInt(_nudgeKey) ?? 0;
    if (stage <= shown) return null;
    await prefs.setInt(_nudgeKey, stage);
    Analytics.instance.track('trial_nudge_shown', {'stage': stage});
    return stage;
  }

  /// Whether the "it ended" strip on Home was dismissed. Loaded from
  /// disk during [reloadForUser] so the banner can read it synchronously.
  bool get expiredBannerDismissed => _expiredBannerDismissed;
  bool _expiredBannerDismissed = false;

  String get _expiredBannerKey => 'seenly_trial_expired_banner_dismissed_${_userId ?? ''}';

  Future<void> dismissExpiredBanner() async {
    _expiredBannerDismissed = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expiredBannerKey, true);
  }
}
