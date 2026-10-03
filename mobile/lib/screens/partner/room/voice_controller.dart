import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../models/co_view_room.dart';
import '../../../services/co_view_room_service.dart';

enum VoiceStatus { off, connecting, on, unavailable, denied }

/// The room's voice channel: a thin shell over a self-hosted LiveKit room.
/// Audio only, free for everyone, never recorded — the server only hands
/// out a short-lived token (see backend routers/co_view_room.py::voice_token).
///
/// The controller exposes exactly what the screen draws: am I connected, am
/// I muted, and who is speaking *right now* with how loudly (by app user id,
/// which is the LiveKit identity), so an avatar can glow in time with a
/// voice without the screen knowing anything about LiveKit.
class VoiceController extends ChangeNotifier {
  VoiceController({required this.roomId, required CoViewRoomService service}) : _service = service;

  final String roomId;
  final CoViewRoomService _service;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  Timer? _levels;
  bool _disposed = false;

  VoiceStatus status = VoiceStatus.off;
  bool muted = false;

  /// 0..1 per user id, only for people currently speaking.
  final Map<String, double> speaking = {};

  bool get isOn => status == VoiceStatus.on;

  double levelOf(String userId) => speaking[userId] ?? 0;

  Future<void> join() async {
    if (status == VoiceStatus.connecting || status == VoiceStatus.on) return;
    status = VoiceStatus.connecting;
    notifyListeners();
    try {
      final VoiceToken t = await _service.voiceToken(roomId);
      final room = lk.Room(
        roomOptions: const lk.RoomOptions(adaptiveStream: false, dynacast: false),
      );
      _room = room;
      _listener = room.createListener();
      room.addListener(_onRoomChanged);
      await room.connect(t.url, t.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      muted = false;
      status = VoiceStatus.on;
      _levels = Timer.periodic(const Duration(milliseconds: 140), (_) => _sampleLevels());
    } on lk.TrackCreateException {
      status = VoiceStatus.denied;
      await _teardown();
    } catch (e) {
      final text = e.toString().toLowerCase();
      status = (text.contains('503') || text.contains('не настроен')) ? VoiceStatus.unavailable : VoiceStatus.off;
      if (text.contains('permission')) status = VoiceStatus.denied;
      await _teardown();
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setMuted(bool value) async {
    final p = _room?.localParticipant;
    if (p == null) return;
    await p.setMicrophoneEnabled(!value);
    muted = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> toggleMute() => setMuted(!muted);

  Future<void> leave() async {
    await _teardown();
    status = VoiceStatus.off;
    speaking.clear();
    if (!_disposed) notifyListeners();
    try {
      await _service.voiceOff(roomId);
    } catch (_) {}
  }

  void _onRoomChanged() {
    if (_room?.connectionState == lk.ConnectionState.disconnected && status == VoiceStatus.on) {
      status = VoiceStatus.off;
      speaking.clear();
      _levels?.cancel();
      if (!_disposed) notifyListeners();
    }
  }

  void _sampleLevels() {
    final room = _room;
    if (room == null) return;
    final next = <String, double>{};
    void add(lk.Participant p) {
      if (p.isSpeaking) next[p.identity] = p.audioLevel.clamp(0.0, 1.0).toDouble();
    }

    final local = room.localParticipant;
    if (local != null && !muted) add(local);
    for (final p in room.remoteParticipants.values) {
      add(p);
    }
    if (!mapEquals(next, speaking)) {
      speaking
        ..clear()
        ..addAll(next);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _teardown() async {
    _levels?.cancel();
    _levels = null;
    final room = _room;
    _room = null;
    await _listener?.dispose();
    _listener = null;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _teardown();
    super.dispose();
  }
}
