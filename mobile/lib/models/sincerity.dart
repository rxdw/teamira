/// Mirrors backend/app/schemas.py::SincerityTransactionOut — one line
/// in the history list on SincerityScreen. `reason` is the raw wire
/// value from models.SincerityReason (e.g. "closed_gestalt") — see
/// sincerity_screen.dart's `_reasonCopy` for how each one is turned
/// into a short, warm line instead of shown as a raw enum string.
class SincerityTransaction {
  final String id;
  final int delta;
  final String reason;
  final String? note;
  final DateTime createdAt;

  const SincerityTransaction({
    required this.id,
    required this.delta,
    required this.reason,
    this.note,
    required this.createdAt,
  });

  factory SincerityTransaction.fromJson(Map<String, dynamic> json) {
    return SincerityTransaction(
      id: json['id'] as String,
      delta: json['delta'] as int,
      reason: json['reason'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Mirrors [fromJson] — added for the on-device diary cache (see
  /// `services/local_json_cache.dart`), not for talking to the backend.
  Map<String, dynamic> toJson() => {
        'id': id,
        'delta': delta,
        'reason': reason,
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Mirrors backend/app/schemas.py::SincerityStaleItemOut — one row in
/// the "settle debt" section of SincerityScreen, for a watch_later item
/// old enough to owe (or already be exempt from) stale_debt.
class SincerityStaleItem {
  final String entryId;
  final String title;
  final String? posterUrl;
  final int ageDays;
  final bool debtExempt;
  final int settleCost;

  const SincerityStaleItem({
    required this.entryId,
    required this.title,
    this.posterUrl,
    required this.ageDays,
    required this.debtExempt,
    required this.settleCost,
  });

  factory SincerityStaleItem.fromJson(Map<String, dynamic> json) {
    return SincerityStaleItem(
      entryId: json['entry_id'] as String,
      title: json['title'] as String,
      posterUrl: json['poster_url'] as String?,
      ageDays: json['age_days'] as int,
      debtExempt: json['debt_exempt'] as bool,
      settleCost: json['settle_cost'] as int,
    );
  }
}

/// Mirrors backend/app/schemas.py::SincerityBalanceOut — the full
/// response of GET /sincerity/me.
class SincerityBalance {
  final int balance;
  final bool visibleToFriends;
  final List<SincerityTransaction> history;
  final bool hasMore;
  final List<SincerityStaleItem> staleItems;

  const SincerityBalance({
    required this.balance,
    required this.visibleToFriends,
    required this.history,
    required this.hasMore,
    this.staleItems = const [],
  });

  factory SincerityBalance.fromJson(Map<String, dynamic> json) {
    return SincerityBalance(
      balance: json['balance'] as int,
      visibleToFriends: json['visible_to_friends'] as bool,
      history: (json['history'] as List<dynamic>)
          .map((e) => SincerityTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: json['has_more'] as bool,
      staleItems: (json['stale_items'] as List<dynamic>? ?? [])
          .map((e) => SincerityStaleItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  SincerityBalance withMoreHistory(SincerityBalance older) {
    return SincerityBalance(
      balance: balance,
      visibleToFriends: visibleToFriends,
      history: [...history, ...older.history],
      hasMore: older.hasMore,
      staleItems: staleItems,
    );
  }
}
