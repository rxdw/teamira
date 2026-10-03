import 'package:flutter_test/flutter_test.dart';

import 'package:teamira/models/pair_album.dart';

/// The free-allowance arithmetic on [AlbumStatus]. The numbers themselves
/// come from the server (backend/app/pair_album.py); these tests only pin
/// what the client does with them.
AlbumStatus _status(Map<String, dynamic> extra) => AlbumStatus.fromJson({
      'is_couple': true,
      'is_premium': false,
      'server_today': '2026-10-01',
      ...extra,
    });

void main() {
  group('free allowance', () {
    test('a fresh free circle can start a note and seal a capsule', () {
      final s = _status({
        'notes_limit': 3,
        'notes_used': 0,
        'capsules_limit': 1,
        'capsules_used': 0,
      });
      expect(s.notesLeft, 3);
      expect(s.capsulesLeft, 1);
      expect(s.canWriteNote, isTrue);
      expect(s.canCreateCapsule, isTrue);
    });

    test('spent allowance closes new notes and capsules', () {
      final s = _status({
        'notes_limit': 3,
        'notes_used': 3,
        'capsules_limit': 1,
        'capsules_used': 1,
      });
      expect(s.notesLeft, 0);
      expect(s.capsulesLeft, 0);
      expect(s.canWriteNote, isFalse);
      expect(s.canCreateCapsule, isFalse);
    });

    test('never reports a negative number left', () {
      // E.g. someone who wrote under premium, then it lapsed.
      final s = _status({
        'notes_limit': 3,
        'notes_used': 7,
        'capsules_limit': 1,
        'capsules_used': 2,
      });
      expect(s.notesLeft, 0);
      expect(s.capsulesLeft, 0);
    });

    test('no limit means no ceiling (premium)', () {
      final s = _status({
        'is_premium': true,
        'notes_used': 40,
        'capsules_used': 3,
      });
      expect(s.isPremium, isTrue);
      expect(s.notesLeft, isNull);
      expect(s.capsulesLeft, isNull);
      expect(s.canWriteNote, isTrue);
      expect(s.canCreateCapsule, isTrue);
    });

    test('notes and capsules are independent', () {
      final s = _status({
        'notes_limit': 3,
        'notes_used': 3,
        'capsules_limit': 1,
        'capsules_used': 0,
      });
      expect(s.canWriteNote, isFalse);
      expect(s.canCreateCapsule, isTrue);
    });
  });
}
