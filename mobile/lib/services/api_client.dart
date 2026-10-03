import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_token_store.dart';

/// Thrown for any non-2xx response; carries the status code and whatever
/// `detail` FastAPI put in the body, so screens can show a real message
/// instead of a generic "something went wrong".
class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// The `error` parameter the backend puts in `WWW-Authenticate` on a
  /// 401 — `token_expired` or `token_revoked` (see backend's app/deps.py).
  /// The two need opposite responses: one is a routine expiry to refresh
  /// through, the other means the session is over and the person has to
  /// sign in. Without this the client would have to string-match a
  /// human-readable message that changes with the interface language.
  final String? authError;

  ApiException(this.statusCode, this.message, {this.authError});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thrown when a refresh has definitively failed and there is nothing
/// left to retry with. [ApiClient.onSessionExpired] has already fired by
/// the time this surfaces; screens catch it as an ordinary error.
class SessionExpiredException extends ApiException {
  SessionExpiredException()
      : super(401, 'your session has ended — please sign in again',
            authError: 'token_revoked');
}

/// Talks to the Seenly FastAPI backend.
///
/// Base URL resolution mirrors what the backend README documents for the
/// original app: if `SEENLY_API_BASE_URL` was passed via `--dart-define`,
/// that's the only address ever tried. Otherwise, on first use the client
/// races a handful of common local addresses against `/health` and keeps
/// whichever answers first — this is what makes `flutter run` "just work"
/// on an Android emulator (`10.0.2.2`), iOS simulator/desktop (`localhost`),
/// or a physical device on the same network once a real IP is supplied.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  // Empty by default so a build that forgets --dart-define falls
  // through to the candidate-discovery health-check below (still
  // covers emulator/simulator/desktop out of the box) instead of
  // silently baking in one specific developer's LAN IP into every
  // build forever, including release ones. A physical device on a
  // real network still needs --dart-define=SEENLY_API_BASE_URL=... —
  // see the README — this default was never a substitute for that,
  // it was just quietly standing in for it in a way that only worked
  // by accident, on one particular network.
  static const String _explicitBaseUrl = String.fromEnvironment(
    'SEENLY_API_BASE_URL',
    defaultValue: '',
  );
  static const _lastGoodBaseUrlKey = 'seenly_last_good_base_url';

  static const List<String> _candidateBaseUrls = [
    'http://10.0.2.2:8000', // Android emulator -> host machine
    'http://localhost:8000',
    'http://127.0.0.1:8000',
  ];

  String? _resolvedBaseUrl;
  Completer<String>? _resolving;

  // Kept in memory as well as in the keystore: every request reads the
  // access token, and a keystore read is a platform channel round trip.
  String? _token;
  String? _refreshToken;

  /// When the access token is expected to stop working. Used to refresh
  /// *before* a request fails rather than only after one does — a proactive
  /// refresh costs one request an hour, while discovering expiry by 401
  /// costs a visible stall on whichever screen happened to ask first.
  /// The 401 path below stays as the backstop for clock skew and for a
  /// token revoked server-side.
  DateTime? _accessExpiresAt;

  /// Fires when the session is definitively over — a refresh token that is
  /// expired, revoked, or was replayed. AppState listens and drops the
  /// person on the login screen (see state/app_state.dart::bootstrap).
  ///
  /// This is the piece that was missing entirely: the old client had no
  /// 401 handling at all, so an expired token turned into whatever error
  /// text the screen happened to show — usually a raw "Could not validate
  /// credentials" — and the person was stuck looking at a broken screen
  /// with no idea they needed to sign in.
  void Function()? onSessionExpired;

  /// Single-flight guard. Ten screens on one tab can hit 401 within the
  /// same frame; without this each would start its own refresh, and
  /// because the backend *rotates* refresh tokens and treats a reused one
  /// as a stolen-token replay (see backend/app/routers/auth.py::refresh),
  /// the second one through would revoke the whole session. So the first
  /// caller refreshes and everyone else awaits the same future.
  Completer<bool>? _refreshing;

  Future<void> loadTokens() async {
    final store = SecureTokenStore.instance;
    _token = await store.readAccessToken();
    _refreshToken = await store.readRefreshToken();
    if (_token == null) {
      // An app updating from a build that kept its token in
      // SharedPreferences — move it into the keystore rather than signing
      // the person out on update. See SecureTokenStore.migrateLegacyToken.
      final migrated = await store.migrateLegacyToken();
      if (migrated != null) _token = migrated;
    }
  }

  /// Kept for call sites that still say `loadToken()`.
  @Deprecated('Use loadTokens() — the client now holds a token pair')
  Future<void> loadToken() => loadTokens();

  Future<void> setTokens({
    required String? accessToken,
    String? refreshToken,
    int? expiresInSeconds,
  }) async {
    _token = accessToken;
    if (refreshToken != null) _refreshToken = refreshToken;
    if (accessToken == null) _refreshToken = null;

    _accessExpiresAt = (accessToken != null && expiresInSeconds != null)
        // Refreshed a minute early so a request issued just before the
        // boundary doesn't land just after it.
        ? DateTime.now().add(Duration(seconds: expiresInSeconds - 60))
        : null;

    if (accessToken == null) {
      await SecureTokenStore.instance.clear();
    } else {
      await SecureTokenStore.instance
          .write(accessToken: accessToken, refreshToken: _refreshToken);
    }
  }

  /// Signing out locally. The server-side half (revoking the refresh
  /// session) is [AuthService.logout]'s job — this only clears the device,
  /// so it still works with no network.
  Future<void> clearTokens() => setTokens(accessToken: null);

  String? get refreshToken => _refreshToken;

  bool get isAuthenticated => _token != null;

  /// Public wrapper around [_baseUrl] — needed wherever the client has to
  /// build a full URL itself instead of just calling get/post/etc, e.g.
  /// turning a relative `avatar_url` like `/static/avatars/x.png` (as
  /// returned by POST /profile/avatar) into something Image.network can
  /// actually load.
  Future<String> resolveBaseUrl() => _baseUrl();

  /// Same resolved host as [resolveBaseUrl], with the scheme swapped for
  /// a WebSocket one — what the co-viewing/Watch Together session sockets
  /// (see services/realtime_socket.dart) connect to. Goes through the
  /// exact same candidate-discovery/health-check logic as every plain
  /// HTTP request, so a websocket never ends up pointed at a different
  /// host than the one everything else in the app is actually talking to.
  Future<String> wsBaseUrl() async {
    final http = await _baseUrl();
    if (http.startsWith('https://')) return 'wss://${http.substring(8)}';
    if (http.startsWith('http://')) return 'ws://${http.substring(7)}';
    return http;
  }

  /// The access token to open a websocket with. A WebSocket handshake
  /// has no way to run back through [_authed]'s retry-on-401 dance once
  /// it's already connected — by the time a token expires mid-connection
  /// there's no request to retry, just a socket that stops being
  /// welcome — so this proactively refreshes first, the same early
  /// check [_authed] itself does before an ordinary request, rather than
  /// handing a socket a token that's about to expire moments after it
  /// opens.
  Future<String?> tokenForRealtime() async {
    if (_token != null && _accessTokenLooksExpired && _refreshToken != null) {
      await _refreshTokens();
    }
    return _token;
  }

  Future<String> _baseUrl() async {
    if (_explicitBaseUrl.isNotEmpty) return _explicitBaseUrl;
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;
    if (_resolving != null) return _resolving!.future;

    final completer = Completer<String>();
    _resolving = completer;

    try {
      final prefs = await SharedPreferences.getInstance();
      final remembered = prefs.getString(_lastGoodBaseUrlKey);
      final candidates = [
        if (remembered != null) remembered,
        ..._candidateBaseUrls.where((u) => u != remembered),
      ];

      String? found;
      for (final url in candidates) {
        if (await _healthCheck(url)) {
          found = url;
          break;
        }
      }
      // None answered — fall back to the emulator default so error
      // messages are at least consistent instead of null.
      found ??= _candidateBaseUrls.first;

      _resolvedBaseUrl = found;
      await prefs.setString(_lastGoodBaseUrlKey, found);
      completer.complete(found);
      return found;
    } finally {
      _resolving = null;
    }
  }

  Future<bool> _healthCheck(String baseUrl) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Call after any request throws a network-level error, so the *next*
  /// request re-races the candidates instead of hammering a dead address
  /// (e.g. the host toggled a VPN, as the README calls out).
  void _forgetResolvedBaseUrl() {
    _resolvedBaseUrl = null;
  }

  Map<String, String> _headers({bool auth = true}) => {
        'Content-Type': 'application/json',
        if (auth && _token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _decode(http.Response res) {
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Future.value(body);
    }
    String message = 'request failed (${res.statusCode})';
    if (body is Map && body['detail'] != null) {
      // Lowercased like all other copy in the app; this only
      // changes how the message reads in a snackbar/error state.
      message = body['detail'].toString().toLowerCase();
    }
    throw ApiException(res.statusCode, message, authError: _authError(res));
  }

  /// Pulls `error="..."` out of `WWW-Authenticate`. The backend sends
  /// `token_expired` for a routine expiry and `token_revoked` for a
  /// session that is over for good — see backend/app/deps.py.
  static String? _authError(http.Response res) {
    final header = res.headers['www-authenticate'];
    if (header == null) return null;
    final match = RegExp(r'error="([^"]+)"').firstMatch(header);
    return match?.group(1);
  }

  // --- Refresh -----------------------------------------------------------

  bool get _accessTokenLooksExpired {
    final at = _accessExpiresAt;
    return at != null && DateTime.now().isAfter(at);
  }

  /// Exchanges the refresh token for a new pair. Returns false when the
  /// session is over, having already cleared the tokens and fired
  /// [onSessionExpired].
  ///
  /// Every concurrent caller shares one attempt — see [_refreshing]. That
  /// is not an optimisation: the backend rotates refresh tokens and treats
  /// a second use of an already-rotated one as a stolen-token replay,
  /// revoking the entire session. Two parallel refreshes would therefore
  /// sign the person out, and would do it *only* under load, which is the
  /// worst kind of bug to find.
  Future<bool> _refreshTokens() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<bool>();
    _refreshing = completer;

    () async {
      try {
        final token = _refreshToken;
        if (token == null) {
          await _endSession();
          completer.complete(false);
          return;
        }

        final baseUrl = await _baseUrl();
        final res = await http
            .post(
              Uri.parse('$baseUrl/auth/refresh'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({'refresh_token': token}),
            )
            .timeout(const Duration(seconds: 12));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          await setTokens(
            accessToken: json['access_token'] as String,
            refreshToken: json['refresh_token'] as String?,
            expiresInSeconds: json['expires_in'] as int?,
          );
          completer.complete(true);
          return;
        }

        if (res.statusCode == 401 || res.statusCode == 403) {
          // Expired, revoked, or replayed. Nothing to retry with.
          await _endSession();
          completer.complete(false);
          return;
        }

        // A 5xx or a rate limit is the *server* having a bad moment, not
        // this session being over. Keeping the tokens means the next
        // request tries again instead of signing someone out over a blip.
        completer.complete(false);
      } catch (_) {
        // Network failure — same reasoning: don't destroy a valid session
        // because the train went into a tunnel.
        completer.complete(false);
      } finally {
        _refreshing = null;
      }
    }();

    return completer.future;
  }

  Future<void> _endSession() async {
    await clearTokens();
    onSessionExpired?.call();
  }

  /// Wraps one authenticated request with the refresh logic: refresh
  /// ahead of a known expiry, and retry exactly once on a 401.
  ///
  /// Retrying *once* and no more is deliberate. A loop here would hammer
  /// the server whenever a token is revoked server-side, which is exactly
  /// the moment it must not be hammered.
  Future<T> _authed<T>(Future<T> Function() send) async {
    if (_token != null && _accessTokenLooksExpired && _refreshToken != null) {
      await _refreshTokens();
    }

    try {
      return await send();
    } on ApiException catch (e) {
      if (!e.isUnauthorized || _refreshToken == null) rethrow;
      // `token_revoked` means the server has already decided this session
      // is finished (password changed, signed out elsewhere, account
      // suspended or deleted). Refreshing would just be told the same
      // thing a second time.
      if (e.authError == 'token_revoked') {
        await _endSession();
        throw SessionExpiredException();
      }
      final refreshed = await _refreshTokens();
      if (!refreshed) throw SessionExpiredException();
      return await send();
    }
  }

  Future<T> _withRetry<T>(Future<T> Function(String baseUrl) run) async {
    final baseUrl = await _baseUrl();
    try {
      return await run(baseUrl);
    } on SocketException {
      _forgetResolvedBaseUrl();
      final retryBaseUrl = await _baseUrl();
      return await run(retryBaseUrl);
    } on TimeoutException {
      _forgetResolvedBaseUrl();
      final retryBaseUrl = await _baseUrl();
      return await run(retryBaseUrl);
    }
  }

  Future<dynamic> get(String path,
      {Map<String, String>? query, Duration timeout = const Duration(seconds: 12)}) {
    return _authed(() => _withRetry((baseUrl) async {
      final uri =
          Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final res = await http
          .get(uri, headers: _headers())
          .timeout(timeout);
      return _decode(res);
    }));
  }

  Future<dynamic> post(String path,
      {Map<String, dynamic>? body, bool auth = true, Duration timeout = const Duration(seconds: 12)}) {
    Future<dynamic> send() => _withRetry((baseUrl) async {
          final res = await http
              .post(
                Uri.parse('$baseUrl$path'),
                headers: _headers(auth: auth),
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(timeout);
          return _decode(res);
        });
    // `auth: false` is login/register/refresh itself — a 401 there is the
    // answer to the question, not a stale token, and running it through
    // the refresh path would try to refresh with credentials that were
    // just rejected.
    return auth ? _authed(send) : send();
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) {
    return _authed(() => _withRetry((baseUrl) async {
      final res = await http
          .patch(
            Uri.parse('$baseUrl$path'),
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 12));
      return _decode(res);
    }));
  }

  /// PUT with a JSON body — used by the pair album (`PUT /partner/album/
  /// notes`, `PUT /partner/album/together-since`), whose writes are
  /// idempotent by design: sending the same note again edits it rather
  /// than adding a second one.
  Future<dynamic> put(String path, {Map<String, dynamic>? body}) {
    return _authed(() => _withRetry((baseUrl) async {
      final res = await http
          .put(
            Uri.parse('$baseUrl$path'),
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 12));
      return _decode(res);
    }));
  }

  /// DELETE with an optional JSON body — needed by DELETE /auth/account,
  /// which takes the password confirmation in the body. `http`'s
  /// convenience `delete` accepts one, but the shape is unusual enough
  /// that it's worth being explicit about here rather than leaving the
  /// next reader to wonder whether it works.
  Future<void> delete(String path, {Map<String, dynamic>? body}) {
    return _authed(() => _withRetry((baseUrl) async {
      final res = await http
          .delete(
            Uri.parse('$baseUrl$path'),
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 12));
      await _decode(res);
    }));
  }

  /// Multipart upload — currently just the avatar photo
  /// (POST /profile/avatar), but written generically in case another
  /// upload shows up later. `bytes` is the whole file in memory, which
  /// is fine for the 5 MB avatar cap this is built for; a much larger
  /// upload would want streaming instead.
  Future<dynamic> postMultipart(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) {
    return _authed(() => _withRetry((baseUrl) async {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      if (_token != null) {
        request.headers['Authorization'] = 'Bearer $_token';
      }
      request.files.add(http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
        contentType: contentType != null ? MediaType.parse(contentType) : null,
      ));
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);
      return _decode(res);
    }));
  }

  /// Same as [delete], but for endpoints that hand back an updated resource
  /// instead of a bare 204 (e.g. removing one item returns the list it was
  /// removed from, so the caller doesn't need a second round-trip).
  Future<dynamic> deleteAndDecode(String path, {Map<String, dynamic>? body}) {
    return _authed(() => _withRetry((baseUrl) async {
      final res = await http
          .delete(
            Uri.parse('$baseUrl$path'),
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 12));
      return _decode(res);
    }));
  }

  /// A raw authenticated GET that hands back the response body as a
  /// string rather than decoding it — used by the data export (GET
  /// /auth/export), which returns a whole file meant to be written to
  /// disk and shared, not parsed into a model.
  Future<String> getRaw(String path) {
    return _authed(() => _withRetry((baseUrl) async {
      final res = await http
          .get(Uri.parse('$baseUrl$path'), headers: _headers())
          .timeout(const Duration(seconds: 60));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.body;
      await _decode(res);
      return '';
    }));
  }
}
