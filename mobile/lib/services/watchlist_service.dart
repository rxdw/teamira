import '../models/sincerity.dart';
import 'api_client.dart';
import '../analytics/analytics.dart';

/// Talks to POST /watchlist/drop (backend/app/routers/watchlist.py) —
/// the "honestly close this out without watching it" action. Either a
/// watch_later item that turned out not to be for you (no reason
/// needed) or something you started and gave up on partway through
/// (reason required — the backend awards nothing without one, see
/// app/sincerity.py::earn_honest_drop).
class WatchlistDropResult {
  final String status;
  final List<SincerityTransaction> sincerityAwarded;
  const WatchlistDropResult({required this.status, required this.sincerityAwarded});

  factory WatchlistDropResult.fromJson(Map<String, dynamic> json) {
    return WatchlistDropResult(
      status: json['status'] as String,
      sincerityAwarded: (json['sincerity_awarded'] as List<dynamic>?)
              ?.map((e) => SincerityTransaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class WatchlistService {
  final ApiClient _client;
  WatchlistService(this._client);

  Future<WatchlistDropResult> drop({
    required String mediaId,
    required String source,
    String? reason,
  }) async {
    final json = await _client.post('/watchlist/drop', body: {
      'media_id': mediaId,
      'source': source,
      if (reason != null) 'reason': reason,
    }) as Map<String, dynamic>;
    Analytics.instance.track('watchlist_dropped', {
      'had_reason': reason != null && reason.trim().isNotEmpty,
    });
    return WatchlistDropResult.fromJson(json);
  }

  /// POST /watchlist/{entry_id}/settle-debt — pays
  /// sincerity.DEBT_SETTLEMENT_COST once so this one stale watch_later
  /// item never gets charged stale_debt again. Reuses
  /// [WatchlistDropResult]'s shape (status + sincerity delta) even
  /// though status doesn't actually change here — the caller only cares
  /// about the sincerity delta to show the "-N" toast.
  Future<WatchlistDropResult> settleDebt(String entryId) async {
    final json = await _client.post('/watchlist/$entryId/settle-debt') as Map<String, dynamic>;
    Analytics.instance.track('sincerity_debt_settled', {});
    return WatchlistDropResult.fromJson(json);
  }
}
