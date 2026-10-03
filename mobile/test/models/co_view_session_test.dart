// Unit tests for models/co_view_vote_session.dart and
// models/co_view_poll_session.dart — the client-side counterparts of the
// backend/app/routers/co_view_vote.py and co_view_poll.py rounds whose
// race conditions were fixed alongside these tests. Getting the client's
// own decision logic (which card is next, whether we've voted, is the
// round over) wrong would hide a backend fix behind a client that still
// shows stale state.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/co_view_poll_session.dart';
import 'package:teamira/models/co_view_vote_session.dart';

Map<String, dynamic> _mediaJson(String id) => {
      'id': id,
      'media_type': 'movie',
      'title': {'en': 'Title $id'},
      // A bare `{}` here would infer as Map<dynamic, dynamic> (no
      // downward context, since the slot type is `dynamic`) and blow up
      // the `as Map<String, dynamic>?` cast inside MediaItem.fromJson —
      // explicit type args avoid that.
      'description': <String, dynamic>{},
      'source': 'tmdb',
    };

void main() {
  group('CoViewVoteSession', () {
    Map<String, dynamic> _voteJson({
      List<String> myDecided = const [],
      Map<String, dynamic>? winner,
      String status = 'active',
    }) =>
        {
          'id': 'v1',
          'status': status,
          'pool_source': 'personal',
          'deck': [_mediaJson('1'), _mediaJson('2'), _mediaJson('3')],
          'my_decided': myDecided,
          'partner_decided_count': 0,
          'member_count': 2,
          'winner': winner,
          'created_at': '2026-01-02T20:00:00',
        };

    test('nextCard is the first deck item not yet decided by this account',
        () {
      final session = CoViewVoteSession.fromJson(
        _voteJson(myDecided: ['tmdb:1']),
      );
      expect(session.nextCard?.id, '2');
    });

    test('nextCard is null once every card has been decided', () {
      final session = CoViewVoteSession.fromJson(
        _voteJson(myDecided: ['tmdb:1', 'tmdb:2', 'tmdb:3']),
      );
      expect(session.nextCard, isNull);
    });

    test('remaining counts down as this account decides cards', () {
      final session = CoViewVoteSession.fromJson(
        _voteJson(myDecided: ['tmdb:1']),
      );
      expect(session.remaining, 2);
    });

    test('matched is true exactly when the backend has set a winner', () {
      final undecided = CoViewVoteSession.fromJson(_voteJson());
      expect(undecided.matched, isFalse);

      final decided = CoViewVoteSession.fromJson(
        _voteJson(status: 'done', winner: _mediaJson('2')),
      );
      expect(decided.matched, isTrue);
      expect(decided.winner?.id, '2');
      expect(decided.isDone, isTrue);
    });

    test('isCompany reflects member_count, not a hardcoded couple assumption',
        () {
      final couple = CoViewVoteSession.fromJson(_voteJson());
      expect(couple.isCompany, isFalse);

      final json = _voteJson()..['member_count'] = 4;
      final company = CoViewVoteSession.fromJson(json);
      expect(company.isCompany, isTrue);
    });
  });

  group('CoViewPollSession', () {
    Map<String, dynamic> _pollJson({
      String deadline = '2026-01-02T20:10:00',
      List<int> voteCounts = const [1, 0],
      int? myVote,
    }) =>
        {
          'id': 'p1',
          'status': 'active',
          'pool_source': 'personal',
          'round_number': 1,
          'deadline': deadline,
          'candidates': [_mediaJson('1'), _mediaJson('2')],
          'vote_counts': voteCounts,
          'my_vote': myVote,
          'voted_count': 1,
          'member_count': 2,
          'winner': null,
          'created_at': '2026-01-02T20:00:00',
        };

    test('deadline without a timezone marker is parsed as UTC, not local',
        () {
      // The backend sends a naive "...T20:10:00" string that really means
      // UTC (see co_view_poll_session.dart's own _parseUtc comment) — a
      // regression here would silently shift every round's countdown by
      // the device's own UTC offset.
      final session = CoViewPollSession.fromJson(_pollJson());
      expect(session.deadline.isUtc, isTrue);
      expect(session.deadline, DateTime.utc(2026, 1, 2, 20, 10, 0));
    });

    test('votesFor returns 0 for a candidate index the backend never sent',
        () {
      final session = CoViewPollSession.fromJson(
        _pollJson(voteCounts: const [2]),
      );
      expect(session.votesFor(0), 2);
      // Out-of-range must degrade to 0, not throw — a runoff narrows the
      // candidate list, and a stale client-held index could momentarily
      // point past the end of a freshly-shrunk vote_counts array.
      expect(session.votesFor(1), 0);
    });

    test('totalVotes sums every candidate\'s tally', () {
      final session = CoViewPollSession.fromJson(
        _pollJson(voteCounts: const [2, 3]),
      );
      expect(session.totalVotes, 5);
    });

    test('hasVoted reflects whether my_vote is present', () {
      expect(CoViewPollSession.fromJson(_pollJson()).hasVoted, isFalse);
      expect(
        CoViewPollSession.fromJson(_pollJson(myVote: 0)).hasVoted,
        isTrue,
      );
    });

    test('timeLeft is zero (never negative) once the deadline has passed',
        () {
      final pastDeadline =
          DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final session = CoViewPollSession.fromJson(
        _pollJson(deadline: pastDeadline.toIso8601String().replaceFirst(RegExp(r'Z?$'), '')),
      );
      expect(session.timeLeft, Duration.zero);
    });
  });
}
