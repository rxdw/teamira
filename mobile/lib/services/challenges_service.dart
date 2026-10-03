import '../models/challenge.dart';
import 'api_client.dart';
import '../analytics/analytics.dart';

/// Talks to /challenges — the weekly and yearly goals.
///
/// Note that GET /challenges writes on the server (it records the moment
/// a challenge first crosses its target — see
/// backend/app/routers/challenges.py for why that has to happen on read).
/// It's idempotent, so polling it from Home is safe, but it's not a
/// free/cacheable read either: call it when a screen opens or after
/// something is logged, not on a timer.
class ChallengesService {
  final ApiClient _client;
  ChallengesService(this._client);

  Future<Challenges> load({bool russian = true}) async {
    final json = await _client.get(
      '/challenges',
      query: {'lang': russian ? 'ru' : 'en'},
    ) as Map<String, dynamic>;
    return Challenges.fromJson(json);
  }

  /// Collects a finished challenge's sincerity points. Throws ApiException(409) if it
  /// isn't finished or was already collected — both are real states the
  /// UI can hit by double-tapping, so callers should catch rather than
  /// assume.
  Future<ChallengeClaim> claim(String challengeId, {bool russian = true}) async {
    final json = await _client.post(
      '/challenges/$challengeId/claim?lang=${russian ? 'ru' : 'en'}',
    ) as Map<String, dynamic>;
    Analytics.instance.track('challenge_claimed');
    return ChallengeClaim.fromJson(json);
  }

  /// Dismisses every pending "готово!" banner. Deliberately separate from
  /// [claim]: swiping a toast away must never quietly collect a reward.
  Future<void> markSeen() => _client.post('/challenges/seen').then((_) {});
}
