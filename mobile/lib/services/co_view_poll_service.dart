import '../models/co_view_poll_session.dart';
import 'api_client.dart';
import 'co_view_vote_service.dart' show CoViewVotePoolSource;

/// Talks to /partner/co-viewing/poll — the "vote it out" method: a small
/// shortlist drawn from the same [CoViewVotePoolSource] pools a swipe
/// round or a random/reel draw would use, that the whole circle votes
/// on together on a clock instead of swiping through alone. See
/// backend/app/routers/co_view_poll.py for the runoff-on-a-tie reasoning.
class CoViewPollService {
  final ApiClient _client;
  CoViewPollService(this._client);

  /// Starts a poll on the given pool, or hands back one already running —
  /// same "whoever taps first" reasoning as CoViewVoteService.start.
  Future<CoViewPollSession> start({String source = CoViewVotePoolSource.personal}) async {
    final json = await _client.post('/partner/co-viewing/poll/start?source=$source') as Map<String, dynamic>;
    return CoViewPollSession.fromJson(json);
  }

  /// Polled on a timer while a poll is open — also what actually resolves
  /// it once the deadline passes with no new vote in between.
  Future<CoViewPollSession> poll(String sessionId) async {
    final json = await _client.get('/partner/co-viewing/poll/$sessionId') as Map<String, dynamic>;
    return CoViewPollSession.fromJson(json);
  }

  /// Casts (or changes) this account's vote for the candidate at
  /// [candidateIndex] in the *current* round's shortlist.
  Future<CoViewPollSession> vote(String sessionId, int candidateIndex) async {
    final json = await _client.post('/partner/co-viewing/poll/$sessionId/vote', body: {
      'candidate_index': candidateIndex,
    }) as Map<String, dynamic>;
    return CoViewPollSession.fromJson(json);
  }

  Future<void> end(String sessionId) =>
      _client.delete('/partner/co-viewing/poll/$sessionId');
}
