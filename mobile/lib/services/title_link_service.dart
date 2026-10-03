import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The parsed payload of a shared-title deep link — everything
/// screens/title/title_detail_screen.dart's `TitleDetailScreen` needs to
/// open straight to that title (`mediaId`/`source` feed
/// MediaService.detail exactly the way any other caller's
/// item.id/item.source would). `title` is only ever a seed for the
/// screen's very first frame before the real fetch resolves — same role
/// `seedTitle` plays for every other caller of that screen — so an empty
/// one just falls back to the id.
class PendingTitleLink {
  final String mediaId;
  final String mediaType;
  final String source;
  final String title;

  const PendingTitleLink({
    required this.mediaId,
    required this.mediaType,
    required this.source,
    required this.title,
  });

  Map<String, dynamic> _toJson() => {
        'mediaId': mediaId,
        'mediaType': mediaType,
        'source': source,
        'title': title,
      };

  static PendingTitleLink? _fromJson(Map<String, dynamic> json) {
    final mediaId = json['mediaId'] as String?;
    final mediaType = json['mediaType'] as String?;
    final source = json['source'] as String?;
    if (mediaId == null || mediaId.isEmpty || mediaType == null || mediaType.isEmpty || source == null || source.isEmpty) {
      // A stored link that can't even resolve a title isn't worth
      // surfacing — same "silent no-op" story as a bad referral code.
      return null;
    }
    return PendingTitleLink(
      mediaId: mediaId,
      mediaType: mediaType,
      source: source,
      title: json['title'] as String? ?? '',
    );
  }
}

/// The client half of a shared-title deep link — see
/// backend/app/routers/linking.py's `GET /t` (the title counterpart of
/// the referral `/i/{code}` landing page) and widgets/title_share.dart's
/// `titleShareLink` for how the link itself gets built.
///
/// Deliberately much smaller than ReferralLinkService: there's no
/// deferred-install attribution to recover here. A referral code has to
/// survive a fresh install (clipboard/Play-referrer tricks) because
/// crediting the right person depends on it; a title link that arrives
/// mid-install just gets dropped, and whoever installed lands on the
/// ordinary post-install flow — the same thing that happens if they'd
/// opened the app any other way. This only has to handle the link
/// reaching an app that's already installed, via
/// `seenly://title?type=...&id=...&source=...` or the eventual
/// `https://<domain>/t?...` App Link (see linking.py's `ios_aasa` for
/// the iOS side of that; Android's own assetlinks.json isn't
/// path-restricted, so it's already covered).
class TitleLinkService {
  static const _pendingKey = 'seenly_pending_title_link';

  /// Pulls `type`/`id`/`source`/`title` off either shape of link above
  /// — AppState.handleIncomingLink tries this only after
  /// ReferralLinkService.extractFromUri comes back empty, since the two
  /// schemes share the same host and only differ in which query params
  /// are actually present. `id` and `source` are both required —
  /// without `source`, MediaService.detail has nothing to pass as its
  /// own `source` query param and would just 404 — so a link missing
  /// either returns null rather than one that's guaranteed to fail once
  /// used.
  static PendingTitleLink? extractFromUri(Uri uri) {
    final id = uri.queryParameters['id'];
    final mediaType = uri.queryParameters['type'];
    final source = uri.queryParameters['source'];
    if (id == null || id.isEmpty || mediaType == null || mediaType.isEmpty || source == null || source.isEmpty) {
      return null;
    }
    return PendingTitleLink(
      mediaId: id,
      mediaType: mediaType,
      source: source,
      title: uri.queryParameters['title'] ?? '',
    );
  }

  /// Stashes a link tapped before the person is signed in yet — mirrors
  /// ReferralLinkService.savePending/takePending exactly, just storing a
  /// small JSON blob instead of a bare code string since there's more
  /// than one field to carry.
  static Future<void> savePending(PendingTitleLink link) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, jsonEncode(link._toJson()));
  }

  static Future<PendingTitleLink?> takePending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return null;
    await prefs.remove(_pendingKey);
    try {
      return PendingTitleLink._fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Malformed stored JSON (shouldn't happen — this app is the only
      // writer — but a corrupt SharedPreferences value shouldn't crash
      // the sign-in flow that reads this back).
      return null;
    }
  }
}
