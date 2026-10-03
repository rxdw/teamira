import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/co_view_room.dart';
import '../../../services/api_client.dart';
import '../../../services/co_view_room_service.dart';
import '../../../services/realtime_socket.dart';

/// What the screen reacts to as it happens, beyond "the state changed".
class RoomHappening {
  final RoomEvent event;
  final bool mine;
  const RoomHappening(this.event, this.mine);
}

/// Owns one open room on this device: the live socket, the latest
/// [RoomState], the optimistic echo of my own taps, and the stream of new
/// events the screen turns into floating hearts, chat bubbles and pulses.
///
/// The server is the only clock. Intents (`play`, `pause`, `seek`) are sent
/// as commands; the reply and the socket push carry the truth. A player
/// compares [RoomState.controlSeq] to decide whether a command is news, so
/// the echo of my own tap never makes the picture jump twice.
class RoomController extends ChangeNotifier {
  RoomController({required RoomState initial, CoViewRoomService? service})
      : _service = service ?? CoViewRoomService(ApiClient.instance),
        _state = initial,
        _seenSeq = initial.lastSeq,
        _events = List.of(initial.events) {
    _socket = _service.watch(initial.id);
    _sub = _socket.updates.listen(_onPush);
    // A film's clock needs a redraw every second; a book has no clock, and a
    // reader that redrew every second would never be still.
    if (!initial.isReading) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed) notifyListeners();
      });
    }
    _markJoined();
  }

  final CoViewRoomService _service;
  late final RealtimeSocket<RoomState> _socket;
  StreamSubscription<RoomState>? _sub;
  Timer? _tick;
  bool _disposed = false;

  RoomState _state;
  RoomState get state => _state;

  final List<RoomEvent> _events;
  List<RoomEvent> get events => List.unmodifiable(_events);

  int _seenSeq;
  final _happenings = StreamController<RoomHappening>.broadcast();
  Stream<RoomHappening> get happenings => _happenings.stream;

  /// Set once a room's ending has been seen, so the finishing ritual runs
  /// exactly once per device no matter how many pushes repeat it.
  bool _endHandled = false;
  bool get endAlreadyHandled => _endHandled;
  void markEndHandled() => _endHandled = true;

  Object? lastError;

  /// The server no longer lets me into this room (a guest whose invitation
  /// was taken back): every call answers 404. The screen steps out gracefully.
  bool get lostAccess => lastError is ApiException && (lastError as ApiException).statusCode == 404;

  String get roomId => _state.id;
  String? get myId => _state.me?.userId;

  Future<void> _markJoined() async {
    try {
      _apply(await _service.join(_state.id));
    } catch (e) {
      lastError = e;
    }
  }

  void _onPush(RoomState s) => _apply(s);

  void _apply(RoomState next) {
    if (_disposed) return;
    // Never go backwards: a slow HTTP reply can land after a fresher push.
    if (next.lastSeq < _state.lastSeq) return;

    final fresh = next.events.where((e) => e.seq > _seenSeq).toList();
    if (fresh.isNotEmpty) {
      final known = _events.map((e) => e.seq).toSet();
      for (final e in fresh) {
        if (known.add(e.seq)) _events.add(e);
      }
      _events.sort((a, b) => a.seq.compareTo(b.seq));
      if (_events.length > 400) _events.removeRange(0, _events.length - 400);
      _seenSeq = next.lastSeq > _seenSeq ? next.lastSeq : _seenSeq;
      for (final e in fresh) {
        _happenings.add(RoomHappening(e, e.userId != null && e.userId == next.me?.userId));
      }
    }
    _state = next;
    notifyListeners();
  }

  Future<T?> _run<T>(Future<T> Function() call, {void Function(T)? onOk}) async {
    try {
      final r = await call();
      lastError = null;
      if (r is RoomState) _apply(r);
      if (onOk != null) onOk(r);
      return r;
    } catch (e) {
      lastError = e;
      notifyListeners();
      rethrow;
    }
  }

  // --- playback intents -------------------------------------------------

  Future<void> play({int? positionMs}) =>
      _run(() => _service.control(_state.id, 'play', positionMs: positionMs ?? _state.positionNowMs()));

  Future<void> pause() =>
      _run(() => _service.control(_state.id, 'pause', positionMs: _state.positionNowMs()));

  Future<void> seek(int positionMs) =>
      _run(() => _service.control(_state.id, 'seek', positionMs: positionMs));

  Future<void> togglePlay() => _state.isPlaying ? pause() : play();

  // --- talking to each other --------------------------------------------

  Future<void> sendChat(String text) {
    final body = text.trim();
    if (body.isEmpty) return Future.value();
    return _run(() => _service.chat(_state.id, body));
  }

  Future<void> react(String key) =>
      _run(() => _service.react(_state.id, key, positionMs: _state.positionNowMs()));

  Future<void> signal(String key) => _run(() => _service.signal(_state.id, key));

  Future<void> emotion(String key) =>
      _run(() => _service.emotion(_state.id, key, positionMs: _state.positionNowMs()));

  // --- reading ------------------------------------------------------------

  Future<void> reportLocator(String locator, int progress, {String? contentHash}) =>
      _run(() => _service.reportLocator(_state.id, locator, progress, contentHash: contentHash));

  Future<void> lead(String locator, int progress) => _run(() => _service.lead(_state.id, locator, progress));

  Future<void> setReadMode(String mode, {String? locator, int? progress}) =>
      _run(() => _service.setReadMode(_state.id, mode, locator: locator, progress: progress));

  Future<void> margin(String body, String locator, int progress, {String? quote}) =>
      _run(() => _service.margin(_state.id, body, locator, progress, quote: quote));

  Future<void> reactAt(String key, String locator, int progress) =>
      _run(() => _service.reactAt(_state.id, key, locator, progress));

  // --- playing -------------------------------------------------------------

  Future<void> setReady(bool ready) => _run(() => _service.setReady(_state.id, ready));

  Future<void> round(String key) => _run(() => _service.round(_state.id, key));

  Future<void> highlight(String locator, bool on, int progress, {String? quote}) =>
      _run(() => _service.highlight(_state.id, locator, on, progress, quote: quote));

  Future<void> emotionAt(String key, String locator, int progress) =>
      _run(() => _service.emotionAt(_state.id, key, locator, progress));

  Future<AlbumQuoteResult> albumQuote(String quote) => _service.albumQuote(_state.id, quote);

  Future<void> learnUnits(int units) async {
    if (_state.readUnits != null && _state.readUnits! > 0) return;
    if (units <= 0) return;
    try {
      await _run(() => _service.setReadUnits(_state.id, units));
    } catch (_) {
      // A missing length only costs a label; never worth an error.
    }
  }

  /// "Дочитали": a book has no clock to read, so the server takes the furthest
  /// place anybody got to as where the evening ended.
  Future<RoomState?> finishReading() => _run(() => _service.finish(_state.id));

  // --- the room itself ---------------------------------------------------

  Future<void> setSaveToShared(bool value) => _run(() => _service.setSaveToShared(_state.id, value));

  Future<void> learnDuration(int ms) async {
    if (_state.durationMs != null && _state.durationMs! > 0) return;
    if (ms <= 0) return;
    try {
      await _run(() => _service.setDuration(_state.id, ms));
    } catch (_) {
      // A missing length only costs the progress bar; never worth an error.
    }
  }

  Future<RoomState?> finish({int? positionMs}) =>
      _run(() => _service.finish(_state.id, positionMs: positionMs ?? _state.positionNowMs()));

  Future<void> leave() async {
    try {
      await _service.leave(_state.id);
    } catch (_) {}
  }

  Future<void> closeRoom() => _run(() => _service.close(_state.id));

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _sub?.cancel();
    _socket.close();
    _happenings.close();
    super.dispose();
  }
}
