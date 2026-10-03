import 'package:flutter/foundation.dart';

import '../../../../models/co_view_room.dart';
import '../room_controller.dart';
import 'reading_locator.dart';

/// What the room adds on top of a page: notes in the margin, highlights, the
/// line being read aloud, and where the other people are. Built from the
/// room's state and handed to the readers through a [ValueNotifier] — so a
/// reader redraws only the few places that changed instead of the whole
/// chapter every time anything in the room moves.
class ReadingOverlay {
  /// Margin notes, by place.
  final Map<String, List<RoomMark>> notesAt;

  /// Who has highlighted a paragraph, by place (user ids).
  final Map<String, List<String>> highlightsAt;
  final Map<String, List<RoomParticipant>> othersAt;

  /// The line being read aloud right now (null unless the room is reading aloud).
  final String? cursor;

  /// Me, so a reader can tell my highlight from somebody else's.
  final String? meId;
  final String signature;
  const ReadingOverlay._(this.notesAt, this.highlightsAt, this.othersAt, this.cursor, this.meId, this.signature);

  static const empty = ReadingOverlay._({}, {}, {}, null, null, '');

  static ReadingOverlay of(RoomState s) {
    final notes = <String, List<RoomMark>>{};
    final lights = <String, List<String>>{};
    for (final m in s.marks) {
      if (m.isMargin) {
        notes.putIfAbsent(m.locator, () => []).add(m);
      } else if (m.isHighlight && m.userId != null) {
        lights.putIfAbsent(m.locator, () => []).add(m.userId!);
      }
    }
    final others = <String, List<RoomParticipant>>{};
    for (final p in s.participants) {
      if (p.isYou || !p.present || p.locator == null) continue;
      others.putIfAbsent(p.locator!, () => []).add(p);
    }
    final cursor = s.isAloud ? s.leadLocator : null;
    final me = [for (final p in s.participants) if (p.isYou) p.userId].firstOrNull;

    // Anything that changes what is drawn must change this string — and
    // nothing else may, or every page turn of somebody else redraws the chapter.
    final sig = StringBuffer()
      ..write(s.marks.length)
      ..write('/')
      ..write(s.marks.fold<int>(0, (m, e) => e.seq > m ? e.seq : m))
      ..write('|c:')
      ..write(cursor ?? '');
    for (final p in s.participants) {
      if (p.isYou) continue;
      sig
        ..write('|')
        ..write(p.userId)
        ..write(p.present ? '+' : '-')
        ..write(p.locator ?? '');
    }
    return ReadingOverlay._(notes, lights, others, cursor, me, sig.toString());
  }

  List<RoomMark> notesFor(ReadLocator at) => notesAt[at.wire] ?? const [];
  List<RoomParticipant> othersFor(ReadLocator at) => othersAt[at.wire] ?? const [];
  List<String> highlightersFor(ReadLocator at) => highlightsAt[at.wire] ?? const [];

  bool isCursor(ReadLocator at) => cursor != null && cursor == at.wire;
  bool iHighlighted(ReadLocator at) => meId != null && highlightersFor(at).contains(meId);
  bool othersHighlighted(ReadLocator at) => highlightersFor(at).any((u) => u != meId);
}

/// Keeps a [ReadingOverlay] current from a [RoomController], notifying only
/// when its content actually changed.
class ReadingOverlayNotifier extends ValueNotifier<ReadingOverlay> {
  ReadingOverlayNotifier(this._room) : super(ReadingOverlay.of(_room.state)) {
    _room.addListener(_refresh);
  }

  final RoomController _room;

  void _refresh() {
    final next = ReadingOverlay.of(_room.state);
    if (next.signature != value.signature) value = next;
  }

  @override
  void dispose() {
    _room.removeListener(_refresh);
    super.dispose();
  }
}
