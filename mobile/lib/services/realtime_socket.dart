import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

/// What replaced the old `Timer.periodic(2s)` GET poll in
/// co_view_vote_screen.dart, co_view_poll_screen.dart, and
/// together_screen.dart — a small wrapper around a single session's
/// WebSocket (see backend/app/realtime.py for the server side) that
/// handles the handful of things every one of those three screens
/// needed identically:
///
/// - The auth token goes in the URL as `?token=...`, not an
///   `Authorization` header — a WebSocket handshake has no header this
///   app can rely on setting the same way on every platform it ships
///   to (a browser's native WebSocket, in particular, can't set one at
///   all), and mobile/web is a real build target here.
/// - A session can easily outlive one access token's lifetime, so a
///   fresh token is fetched (and refreshed first if needed — see
///   ApiClient.tokenForRealtime) on every single connection attempt,
///   not just the first.
/// - The server pushes the *whole* current state each time (the exact
///   same shape the old poll() call used to return), never a diff, so
///   decoding is just "parse this JSON, hand it to fromJson".
/// - A dropped connection reconnects with backoff rather than
///   surfacing an error — the same "a missed poll just tries again"
///   reasoning every one of those screens' old `catch (_) {}` poll
///   blocks already relied on, just event-driven instead of a fixed
///   2-second retry.
class RealtimeSocket<T> {
  /// Path only, e.g. `/partner/co-viewing/vote/$id/ws` — [ApiClient]
  /// resolves the actual host (see [ApiClient.wsBaseUrl]).
  final String path;
  final T Function(Map<String, dynamic> json) fromJson;
  final ApiClient _client;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _controller = StreamController<T>.broadcast();
  bool _closed = false;
  int _retryAttempt = 0;

  RealtimeSocket({
    required this.path,
    required this.fromJson,
    required ApiClient client,
  }) : _client = client {
    _connect();
  }

  /// Updates as they arrive. Never emits an error — a connection
  /// problem just means the next update arrives a little later, once
  /// reconnection succeeds, rather than something the caller needs its
  /// own try/catch for.
  Stream<T> get updates => _controller.stream;

  Future<void> _connect() async {
    if (_closed) return;
    try {
      final base = await _client.wsBaseUrl();
      final token = await _client.tokenForRealtime();
      final uri = Uri.parse('$base$path').replace(
        queryParameters: {if (token != null) 'token': token},
      );
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      if (_closed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _retryAttempt = 0;
      _sub = channel.stream.listen(
        (event) {
          if (event is! String) return;
          try {
            final decoded = jsonDecode(event) as Map<String, dynamic>;
            if (!_controller.isClosed) _controller.add(fromJson(decoded));
          } catch (_) {
            // A frame that doesn't parse is dropped, not fatal — the
            // next one (there's always a next one, per realtime.py's
            // own heartbeat) picks up normally.
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _retryAttempt = _retryAttempt < 6 ? _retryAttempt + 1 : 6;
    final delayMs = 300 * (1 << _retryAttempt); // ~0.6s .. ~19s
    Future.delayed(Duration(milliseconds: delayMs), _connect);
  }

  /// Caller owns the socket and must call this (e.g. from
  /// `State.dispose`), the same way it used to own and cancel its own
  /// poll `Timer`.
  void close() {
    if (_closed) return;
    _closed = true;
    _sub?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
