import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/co_view_room.dart';
import 'package:teamira/screens/partner/room/room_strings.dart';

Map<String, dynamic> _json({bool playing = false, int position = 0, int? duration}) => {
      'id': 'r1',
      'status': playing ? 'live' : 'lobby',
      'media_id': 'm',
      'media_type': 'video',
      'source': 'youtube',
      'player_kind': 'youtube',
      'player_ref': 'dQw4w9WgXcQ',
      'duration_ms': duration,
      'is_playing': playing,
      'position_ms': position,
      'server_now': '2026-10-01T10:00:00',
      'control_seq': 1,
      'save_to_shared': true,
      'participants': [
        {
          'user_id': 'a', 'username': 'anya', 'is_you': true, 'is_host': true,
          'joined': true, 'present': true, 'voice_on': false,
        },
        {
          'user_id': 'b', 'username': 'max', 'is_you': false, 'is_host': false,
          'joined': true, 'present': false, 'voice_on': false,
        },
      ],
      'events': [],
      'last_seq': 0,
      'voice_available': false,
      'created_at': '2026-10-01T09:59:00',
    };

void main() {
  group('RoomState', () {
    test('a paused room stays exactly where the server put it', () {
      final s = RoomState.fromJson(_json(position: 42000, duration: 100000));
      expect(s.positionNowMs(), 42000);
      expect(s.isLobby, isTrue);
      expect(s.progress, closeTo(0.42, 0.001));
    });

    test('a playing room never runs past the end', () {
      final s = RoomState.fromJson(_json(playing: true, position: 99999, duration: 100000));
      expect(s.positionNowMs(), lessThanOrEqualTo(100000));
    });

    test('zen is closed unless the server says the circle has it', () {
      expect(RoomState.fromJson(_json()).zenAvailable, isFalse);
      expect(RoomState.fromJson({..._json(), 'zen_available': true}).zenAvailable, isTrue);
    });

    test('who is here and who is me', () {
      final s = RoomState.fromJson(_json());
      expect(s.me?.userId, 'a');
      expect(s.others.single.name, 'max');
      expect(s.presentCount, 1);
    });

    test('player kinds round-trip and unknown ones fall back to parallel', () {
      expect(playerKindFromWire('youtube'), PlayerKind.youtube);
      expect(playerKindFromWire('nonsense'), PlayerKind.parallel);
      expect(playerKindToWire(PlayerKind.direct), 'direct');
    });

    test('allow-lists match the server', () {
      expect(RoomKeys.reactions.length, 10);
      expect(RoomKeys.signals, ['pause', 'rewind', 'pulse', 'hold']);
      expect(RoomKeys.emotions.length, 8);
    });
  });

  group('guests', () {
    test('a guest is marked, and a guest cannot steer', () {
      final j = _json();
      (j['participants'] as List)[1]['is_guest'] = true;
      (j['participants'] as List)[1]['invited_by'] = 'anya';
      final s = RoomState.fromJson({...j, 'me_is_guest': false, 'guest_slots_left': 2});
      expect(s.guests.single.username, 'max');
      expect(s.guests.single.invitedBy, 'anya');
      expect(s.canSteer, isTrue);
      expect(s.guestSlotsLeft, 2);
      expect(RoomState.fromJson({...j, 'me_is_guest': true}).canSteer, isFalse);
    });

    test('an invitation reads from the invites endpoint shape', () {
      final i = GuestInvite.fromJson({
        'room_id': 'r1', 'title': 'Ролик', 'inviter_name': 'аня', 'inviter_username': 'anya',
        'room_status': 'live', 'created_at': '2026-10-01T10:00:00',
      });
      expect(i.isLive, isTrue);
      expect(i.inviterName, 'аня');
    });
  });

  group('clockLabel', () {
    test('minutes and hours', () {
      expect(clockLabel(0), '0:00');
      expect(clockLabel(61000), '1:01');
      expect(clockLabel(2480000), '41:20');
      expect(clockLabel(3909000), '1:05:09');
      expect(clockLabel(-5), '0:00');
    });
  });
}
