import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/profile_stats.dart';
import 'api_client.dart';

/// Everything that happens to an account: signing in, staying signed in,
/// recovering it, and deleting it.
///
/// The shape changed with the backend's move to a token pair. Every entry
/// point that used to store one access token now stores both halves via
/// [ApiClient.setTokens], including `expires_in` so the client can refresh
/// ahead of an expiry rather than discovering it through a failed request.
class AuthService {
  final ApiClient _client;
  AuthService(this._client);

  /// A human-readable device name, sent with every sign-in so the "where
  /// you're signed in" screen can say "Pixel 7" instead of an opaque
  /// session id. Best-effort: a failure here must never block a login, so
  /// everything is wrapped and the fallback is a plain platform name.
  static String? _cachedDeviceLabel;

  Future<String?> _deviceLabel() async {
    if (_cachedDeviceLabel != null) return _cachedDeviceLabel;
    // dart:io's Platform is only a stub on web — every getter on it
    // (isIOS, isAndroid, and critically the unconditional
    // `Platform.operatingSystem` fallback below) throws UnsupportedError
    // at runtime there instead of returning a value. That used to happen
    // outside any try/catch, so registering or logging in from the web
    // build threw before the request body was even built, and the
    // screen had nothing better to show than "something went wrong —
    // please try again" (see error_text.dart). kIsWeb is a compile-time
    // constant, so this branch is what actually keeps web from ever
    // touching Platform at all.
    if (kIsWeb) {
      try {
        final info = DeviceInfoPlugin();
        final web = await info.webBrowserInfo;
        _cachedDeviceLabel = web.browserName.name;
      } catch (_) {
        _cachedDeviceLabel = 'web';
      }
      return _cachedDeviceLabel;
    }
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        _cachedDeviceLabel = ios.utsname.machine;
      } else if (Platform.isAndroid) {
        final android = await info.androidInfo;
        _cachedDeviceLabel = '${android.manufacturer} ${android.model}';
      }
    } catch (_) {
      // Fall through to the platform name below.
    }
    _cachedDeviceLabel ??= Platform.operatingSystem;
    return _cachedDeviceLabel;
  }

  Future<void> _storePair(Map<String, dynamic> json) => _client.setTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String?,
        expiresInSeconds: json['expires_in'] as int?,
      );

  // --- Sign in / out -------------------------------------------------------

  Future<void> register(String username, String password, {String? referralCode}) async {
    final code = referralCode?.trim();
    final json = await _client.post(
      '/auth/register',
      body: {
        'username': username,
        'password': password,
        'device_label': await _deviceLabel(),
        if (code != null && code.isNotEmpty) 'referral_code': code,
      },
      auth: false,
    ) as Map<String, dynamic>;
    await _storePair(json);
  }

  Future<void> login(String username, String password) async {
    final json = await _client.post(
      '/auth/login',
      body: {
        'username': username,
        'password': password,
        'device_label': await _deviceLabel(),
      },
      auth: false,
    ) as Map<String, dynamic>;
    await _storePair(json);
  }

  /// Signs out, revoking this device's refresh session on the server so a
  /// copy of the token taken from a backup can't be used afterwards.
  ///
  /// The local clear happens regardless of whether the server call
  /// succeeds: "sign me out" has to work on a plane. The worst case is a
  /// refresh session left live on the server until it expires, which the
  /// person can also end from the sessions screen.
  Future<void> logout() async {
    final refresh = _client.refreshToken;
    if (refresh != null) {
      try {
        await _client.post('/auth/logout', body: {'refresh_token': refresh}, auth: false);
      } catch (_) {
        // Deliberately ignored — see above.
      }
    }
    await _client.clearTokens();
  }

  Future<SeenlyUser> me() async {
    final json = await _client.get('/auth/me') as Map<String, dynamic>;
    return SeenlyUser.fromJson(json);
  }

  // --- Password ------------------------------------------------------------

  /// Changes the password and adopts the fresh token pair that comes back.
  ///
  /// The new pair is not a nicety: changing a password revokes every
  /// existing session server-side, including the one that made this call,
  /// so without adopting the replacement the app would sign itself out the
  /// moment it succeeded.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final json = await _client.post('/auth/password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
      'device_label': await _deviceLabel(),
    }) as Map<String, dynamic>;
    await _storePair(json);
  }

  /// Asks for a reset link. Answers the same way whether or not the
  /// address is on an account (see the backend's own note on why), so the
  /// message it returns is the one to show — don't try to infer anything
  /// from it.
  Future<String> forgotPassword(String email) async {
    final json = await _client.post(
      '/auth/password/forgot',
      body: {'email': email.trim()},
      auth: false,
    ) as Map<String, dynamic>;
    return json['message'] as String;
  }

  Future<String> resetPassword(String token, String newPassword) async {
    final json = await _client.post(
      '/auth/password/reset',
      body: {'token': token, 'new_password': newPassword},
      auth: false,
    ) as Map<String, dynamic>;
    return json['message'] as String;
  }

  // --- Email ---------------------------------------------------------------

  Future<String> setEmail(String email, String password) async {
    final json = await _client.post('/auth/email', body: {
      'email': email.trim(),
      'password': password,
    }) as Map<String, dynamic>;
    return json['message'] as String;
  }

  Future<String> verifyEmail(String token) async {
    final json = await _client.post(
      '/auth/email/verify',
      body: {'token': token},
      auth: false,
    ) as Map<String, dynamic>;
    return json['message'] as String;
  }

  // --- Sessions ------------------------------------------------------------

  Future<List<AuthSession>> sessions() async {
    final json = await _client.get('/auth/sessions') as List<dynamic>;
    return json.map((e) => AuthSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String> signOutOtherDevices() async {
    final refresh = _client.refreshToken;
    if (refresh == null) return '';
    final json = await _client.post(
      '/auth/sessions/revoke-others',
      body: {'refresh_token': refresh},
    ) as Map<String, dynamic>;
    return json['message'] as String;
  }

  // --- EULA ----------------------------------------------------------------

  Future<Map<String, dynamic>> eula(String lang) async =>
      await _client.get('/legal/eula', query: {'lang': lang}) as Map<String, dynamic>;

  Future<void> acceptEula(String version) =>
      _client.post('/auth/eula', body: {'version': version});

  // --- Privacy policy --------------------------------------------------

  /// Read-only — nothing to accept, unlike [eula] above (see
  /// PrivacyPolicyScreen's own doc comment).
  Future<Map<String, dynamic>> privacyPolicy(String lang) async =>
      await _client.get('/legal/privacy', query: {'lang': lang}) as Map<String, dynamic>;

  // --- Data export and deletion --------------------------------------------

  /// The whole account as one JSON string, ready to be written to a file
  /// and handed to the share sheet.
  Future<String> exportData() => _client.getRaw('/auth/export');

  Future<AccountDeletion> deleteAccount(String password, {String? reason}) async {
    final json = await _client.deleteAndDecode('/auth/account', body: {
      'password': password,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    }) as Map<String, dynamic>;
    await _client.clearTokens();
    return AccountDeletion.fromJson(json);
  }

  Future<void> restoreAccount(String username, String password) async {
    final json = await _client.post(
      '/auth/account/restore',
      body: {
        'username': username,
        'password': password,
        'device_label': await _deviceLabel(),
      },
      auth: false,
    ) as Map<String, dynamic>;
    await _storePair(json);
  }
}

/// One row of "where you're signed in".
class AuthSession {
  final String id;
  final String? deviceLabel;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  final bool revoked;
  final String? revokedReason;

  AuthSession({
    required this.id,
    this.deviceLabel,
    this.lastUsedAt,
    this.createdAt,
    this.revoked = false,
    this.revokedReason,
  });

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String);

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        id: json['id'] as String,
        deviceLabel: json['device_label'] as String?,
        lastUsedAt: _date(json['last_used_at']),
        createdAt: _date(json['created_at']),
        revoked: json['revoked'] as bool? ?? false,
        revokedReason: json['revoked_reason'] as String?,
      );
}

/// What comes back from DELETE /auth/account — the deletion is scheduled,
/// not instant, and the person needs to be told exactly until when they
/// can change their mind.
class AccountDeletion {
  final DateTime purgeAfter;
  final int restoreDays;
  final String message;

  AccountDeletion({
    required this.purgeAfter,
    required this.restoreDays,
    required this.message,
  });

  factory AccountDeletion.fromJson(Map<String, dynamic> json) => AccountDeletion(
        purgeAfter: DateTime.parse(json['purge_after'] as String),
        restoreDays: json['restore_days'] as int,
        message: json['message'] as String,
      );
}
