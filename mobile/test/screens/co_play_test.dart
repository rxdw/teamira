// Unit tests for playing together (a real game, each on their own machine):
// what the client reads from a game room, and the words it shows for rounds,
// signals and platforms. The room carries nothing of the game itself, so
// there is little else to pin down on this side.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/co_view_room.dart';
import 'package:teamira/screens/partner/room/room_strings.dart';

Map<String, dynamic> _base() => {
      'id': 'r', 'status': 'lobby', 'media_id': '1942', 'media_type': 'game', 'source': 'igdb',
      'title_ru': 'It Takes Two', 'player_kind': 'parallel', 'player_ref': 'pc', 'is_playing': false,
      'position_ms': 0, 'server_now': '2026-10-03T10:00:00', 'control_seq': 0, 'save_to_shared': true,
      'participants': [], 'events': [], 'last_seq': 0, 'voice_available': false, 'created_at': '2026-10-03T10:00:00',
      'activity': 'play',
    };

void main() {
  group('a game room as the client sees it', () {
    test('it is a game, and says where it is played', () {
      final r = RoomState.fromJson(_base());
      expect(r.isGame, isTrue);
      expect(r.isReading, isFalse);
      expect(r.platform, 'pc');
      expect(r.durationMs, isNull);
    });

    test('a film or a book is never a game, and has no platform', () {
      final film = RoomState.fromJson({..._base(), 'activity': 'watch', 'media_type': 'movie'});
      final book = RoomState.fromJson({..._base(), 'activity': 'read', 'media_type': 'book', 'read_kind': 'parallel'});
      for (final r in [film, book]) {
        expect(r.isGame, isFalse);
        expect(r.platform, isNull);
        expect(r.rounds, isEmpty);
        expect(r.allReady, isFalse);
      }
    });

    test('the tally and the ready check arrive with the room', () {
      final r = RoomState.fromJson({
        ..._base(),
        'status': 'live',
        'rounds': {'win': 3, 'loss': 1, 'draw': 0, 'checkpoint': 2},
        'all_ready': true,
        'participants': [
          {
            'user_id': 'a', 'username': 'anya', 'is_you': true, 'is_host': true, 'joined': true,
            'present': true, 'voice_on': false, 'ready': true,
          },
          {
            'user_id': 'b', 'username': 'boris', 'is_you': false, 'is_host': false, 'joined': true,
            'present': true, 'voice_on': false,
          },
        ],
      });
      expect(r.roundsOf('win'), 3);
      expect(r.roundsOf('draw'), 0);
      expect(r.roundsOf('nonsense'), 0);
      expect(r.roundsTotal, 6);
      expect(r.allReady, isTrue);
      expect(r.participants.first.ready, isTrue);
      expect(r.participants.last.ready, isFalse); // absent from the payload means not ready
    });

    test('a guest invite to a game says so', () {
      final i = GuestInvite.fromJson({
        'room_id': 'r', 'title': 'It Takes Two', 'inviter_name': 'Аня', 'inviter_username': 'anya',
        'room_status': 'lobby', 'created_at': '2026-10-03T10:00:00', 'activity': 'play',
      });
      expect(i.isGame, isTrue);
      expect(i.isReading, isFalse);
    });
  });

  group('what a game room speaks', () {
    test('a game has its own signals, and none of a film’s', () {
      expect(RoomKeys.gameSignals, ['ready', 'brb', 'help', 'gg', 'again']);
      expect(RoomKeys.gameSignals.toSet().intersection(RoomKeys.signals.toSet()), isEmpty);
    });

    test('every round, signal and platform has words and a picture', () {
      for (final k in RoomKeys.rounds) {
        expect(roundLabel(k).isNotEmpty, isTrue, reason: k);
        expect(roundEmoji(k), isNot('🎮'), reason: k);
      }
      for (final k in RoomKeys.gameSignals) {
        expect(signalLabel(k).isNotEmpty, isTrue, reason: k);
        expect(signalEmoji(k), isNot('💛'), reason: k);
      }
      for (final k in RoomKeys.platforms) {
        expect(platformLabel(k).isNotEmpty, isTrue, reason: k);
      }
    });

    test('the session clock reads like a clock', () {
      expect(clockLabel(0), '0:00');
      expect(clockLabel(65000), '1:05');
      expect(clockLabel(3725000), '1:02:05');
    });
  });
}
