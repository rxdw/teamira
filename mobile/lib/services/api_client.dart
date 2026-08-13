import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown for any non-2xx response; carries the status code and whatever
/// `detail` FastAPI put in the body, so screens can show a real message
/// instead of a generic "something went wrong".
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
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

  static const String _explicitBaseUrl =
      String.fromEnvironment('SEENLY_API_BASE_URL');
  static const _tokenKey = 'seenly_access_token';
  static const _lastGoodBaseUrlKey = 'seenly_last_good_base_url';

  static const List<String> _candidateBaseUrls = [
    'http://10.0.2.2:8000', // Android emulator -> host machine
    'http://localhost:8000',
    'http://127.0.0.1:8000',
  ];

  String? _resolvedBaseUrl;
  String? _token;
  Completer<String>? _resolving;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  bool get isAuthenticated => _token != null;

  /// Public wrapper around [_baseUrl] — needed wherever the client has to
  /// build a full URL itself instead of just calling get/post/etc, e.g.
  /// turning a relative `avatar_url` like `/static/avatars/x.png` (as
  /// returned by POST /profile/avatar) into something Image.network can
  /// actually load.
  Future<String> resolveBaseUrl() => _baseUrl();

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
    String message = 'Request failed (${res.statusCode})';
    if (body is Map && body['detail'] != null) {
      message = body['detail'].toString();
    }
    throw ApiException(res.statusCode, message);
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

  Future<dynamic> get(String path, {Map<String, String>? query}) {
    return _withRetry((baseUrl) async {
      final uri =
          Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final res = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 12));
      return _decode(res);
    });
  }

  Future<dynamic> post(String path,
      {Map<String, dynamic>? body, bool auth = true, Duration timeout = const Duration(seconds: 12)}) {
    return _withRetry((baseUrl) async {
      final res = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers(auth: auth),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      return _decode(res);
    });
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) {
    return _withRetry((baseUrl) async {
      final res = await http
          .patch(
            Uri.parse('$baseUrl$path'),
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 12));
      return _decode(res);
    });
  }

  Future<void> delete(String path) {
    return _withRetry((baseUrl) async {
      final res = await http
          .delete(Uri.parse('$baseUrl$path'), headers: _headers())
          .timeout(const Duration(seconds: 12));
      await _decode(res);
    });
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
    return _withRetry((baseUrl) async {
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
    });
  }

  /// Same as [delete], but for endpoints that hand back an updated resource
  /// instead of a bare 204 (e.g. removing one item returns the list it was
  /// removed from, so the caller doesn't need a second round-trip).
  Future<dynamic> deleteAndDecode(String path) {
    return _withRetry((baseUrl) async {
      final res = await http
          .delete(Uri.parse('$baseUrl$path'), headers: _headers())
          .timeout(const Duration(seconds: 12));
      return _decode(res);
    });
  }
}
