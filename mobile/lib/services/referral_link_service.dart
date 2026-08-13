import 'dart:io' show Platform;

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The client half of the no-external-service referral link — see
/// backend/app/routers/linking.py's module docstring for the full
/// design. Three ways a referral code reaches this app, all funnelled
/// through the same [extractFromUri]/[checkClipboard] + pending-code
/// storage so AppState only has one thing to call after sign-in:
///
/// 1. App already installed: GET /i/{code} redirects to
///    `seenly://invite?code=XXX`, the OS hands that straight to this
///    app — see app.dart's AppLinks listener.
/// 2. Android, app just installed from the link's Play Store fallback:
///    the referrer string Google's Play Install Referrer API hands back
///    on first launch carries the same code — see
///    [checkPlayInstallReferrerOnce], a real official Google API, not a
///    workaround like the two below.
/// 3. iOS, app just installed: the landing page copied
///    "seenly_ref:XXX" to the clipboard before sending the person to
///    the App Store — [checkClipboard] looks for that once, on first
///    cold start after install. iOS shows a one-time system paste
///    banner when this succeeds; a person who dismisses it just doesn't
///    get auto-credited, same "silent no-op, not a hard failure" story
///    as the backend's own claim endpoint.
class ReferralLinkService {
  static const _pendingKey = 'seenly_pending_referral_code';
  static const _clipboardCheckedKey = 'seenly_clipboard_referral_checked';
  static const _playReferrerCheckedKey = 'seenly_play_referrer_checked';

  /// Pulls `?code=` off either the custom-scheme link
  /// (`seenly://invite?code=XXX`) or an https App Link
  /// (`https://<domain>/i/XXX`, once one is configured) — the landing
  /// page in linking.py only ever sends one or the other.
  static String? extractFromUri(Uri uri) {
    final fromQuery = uri.queryParameters['code'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    if (uri.pathSegments.length >= 2 && uri.pathSegments[uri.pathSegments.length - 2] == 'i') {
      final code = uri.pathSegments.last;
      if (code.isNotEmpty) return code;
    }
    return null;
  }

  /// Best-effort iOS fallback — reads the clipboard exactly once per
  /// install (guarded by [_clipboardCheckedKey] so this app never keeps
  /// re-reading someone's clipboard on every cold start after the
  /// first). Swallows every failure: a blocked/empty/irrelevant
  /// clipboard is exactly as common as a real referral here and isn't
  /// worth surfacing as an error.
  static Future<String?> checkClipboardOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_clipboardCheckedKey) ?? false) return null;
    await prefs.setBool(_clipboardCheckedKey, true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.startsWith('seenly_ref:')) {
        final code = text.substring('seenly_ref:'.length).trim();
        if (code.isNotEmpty) return code;
      }
    } catch (_) {
      // Clipboard access can throw/refuse outright depending on OS
      // version and permission state — treated the same as "nothing
      // there".
    }
    return null;
  }

  /// The real, working Android deferred deep link — reads the referrer
  /// string Google Play attached to the install itself (see the Play
  /// Store link linking.py's landing page builds:
  /// `&referrer=seenly_ref%3D{code}`). Unlike the clipboard trick this
  /// needs no OS-level permission prompt and always works when the
  /// person genuinely installed from that link — it only comes back
  /// empty/thrown when there either wasn't a referrer (organic install,
  /// no link involved) or Play Services isn't available on the device.
  ///
  /// Checked once per install, same reasoning as [checkClipboardOnce].
  /// A no-op on every platform but Android — iOS/desktop just always
  /// return null here since there's no Play Store involved.
  static Future<String?> checkPlayInstallReferrerOnce() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_playReferrerCheckedKey) ?? false) return null;
    await prefs.setBool(_playReferrerCheckedKey, true);
    try {
      final details = await AndroidPlayInstallReferrer.installReferrer;
      final raw = details.installReferrer; // e.g. "seenly_ref=ABC123&utm_source=..."
      if (raw == null || raw.isEmpty) return null;
      for (final pair in raw.split('&')) {
        final parts = pair.split('=');
        if (parts.length == 2 && parts[0] == 'seenly_ref') {
          final code = Uri.decodeComponent(parts[1]).trim();
          if (code.isNotEmpty) return code;
        }
      }
    } catch (_) {
      // No Play Services, emulator without the Play Store, or a device
      // that genuinely has no referrer to report — all the same
      // "nothing found" outcome as an organic install.
    }
    return null;
  }

  /// Stashes a code found before the person is signed in yet (tapped
  /// the link on a fresh install, still has to register) so it survives
  /// until AppState can actually call POST /friends/invite/claim.
  static Future<void> savePending(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, code);
  }

  static Future<String?> takePending() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingKey);
    if (code != null) await prefs.remove(_pendingKey);
    return code;
  }
}
