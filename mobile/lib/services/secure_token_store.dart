import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the access and refresh tokens live.
///
/// They used to live in [SharedPreferences], which is a plain XML file in
/// the app's data directory on Android and a plain plist on iOS — readable
/// as text on a rooted or jailbroken device, in a full-filesystem backup,
/// or through any bug that lets another process reach app storage. The
/// token stored there was also good for a week and could not be revoked,
/// so a copy of that file was a week of somebody's diary.
///
/// Both halves are fixed: the backend now issues a short-lived access
/// token plus a revocable refresh token (see backend/app/security.py), and
/// both now go to the platform keystore — the iOS Keychain, and
/// EncryptedSharedPreferences backed by the Android Keystore.
///
/// **Migration.** An app updating from an older build still has a token
/// sitting in SharedPreferences under the old key. [migrateLegacyToken]
/// moves it across and deletes the original, so nobody is signed out by
/// the update and no readable copy is left behind. It runs once, from
/// [ApiClient.loadTokens].
///
/// **Failure is not fatal.** Keystore reads genuinely fail on some
/// devices — a corrupted keystore entry after an OS upgrade is the
/// classic one, and on Android it throws rather than returning null.
/// Every method here swallows that and reports "no token", which lands
/// the person on the login screen. That is a bad morning; a crash loop on
/// launch with no way out is worse.
class SecureTokenStore {
  SecureTokenStore._();
  static final SecureTokenStore instance = SecureTokenStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      // Readable only after the first unlock following a reboot, and
      // never written to an iCloud or iTunes backup. `first_unlock` (not
      // `unlocked`) because background refresh has to work with the
      // screen off; `ThisDeviceOnly` because a refresh token restored
      // onto a different device from a backup is a credential that
      // travelled somewhere nobody meant it to.
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _accessKey = 'tane_access_token';
  static const _refreshKey = 'tane_refresh_token';

  /// The key the pre-refresh-token builds wrote to, in SharedPreferences.
  /// Kept only so [migrateLegacyToken] can find and clear it.
  static const _legacyPrefsKey = 'seenly_access_token';

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<String?> readAccessToken() => read(_accessKey);
  Future<String?> readRefreshToken() => read(_refreshKey);

  Future<void> write({String? accessToken, String? refreshToken}) async {
    await _put(_accessKey, accessToken);
    await _put(_refreshKey, refreshToken);
  }

  Future<void> _put(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {
      // Nothing useful to do. The in-memory copy in ApiClient still works
      // for this session; the person signs in again next launch.
    }
  }

  Future<void> clear() async {
    await _put(_accessKey, null);
    await _put(_refreshKey, null);
  }

  /// Moves a token left behind by an older build into the keystore.
  ///
  /// Returns the migrated access token, or null if there was nothing to
  /// migrate. There is no legacy refresh token to bring across — refresh
  /// tokens did not exist before this change — so the migrated session
  /// runs on its access token until that expires, and the person signs in
  /// once more at that point. Kept deliberately: inventing a refresh
  /// token client-side isn't possible, and silently signing everyone out
  /// on update to avoid one extra login later is the worse trade.
  Future<String?> migrateLegacyToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_legacyPrefsKey);
      if (legacy == null || legacy.isEmpty) return null;

      await _put(_accessKey, legacy);
      // Removed whether or not the write above succeeded. A token that
      // stays in plain storage is the thing this class exists to prevent;
      // the cost of getting it wrong is one sign-in.
      await prefs.remove(_legacyPrefsKey);
      return legacy;
    } catch (_) {
      return null;
    }
  }
}
