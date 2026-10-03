import 'package:flutter/material.dart';

import '../../../models/co_view_entry.dart';
import '../../../models/co_view_room.dart';
import '../../../services/api_client.dart';
import '../../../services/co_view_room_service.dart';
import '../../../services/error_text.dart';
import 'room_screen.dart';
import 'room_strings.dart';

/// Everything that opens a room goes through here, so the three ways in —
/// the big card, a planned evening, a video from "your sources" — behave
/// the same: open (or join) the circle's one room, and push the screen with
/// a soft fade so it feels like stepping into a room, not into a page.
///
/// Nothing here checks premium: rooms are free.
class RoomLauncher {
  RoomLauncher._();

  static CoViewRoomService get _service => CoViewRoomService(ApiClient.instance);

  static Route<void> _route(RoomState state) => PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => RoomScreen(initial: state),
        transitionsBuilder: (context, anim, _, child) {
          final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          if (reduce) return child;
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: Tween<double>(begin: 0.97, end: 1).animate(curved), child: child),
          );
        },
      );

  /// Joins the circle's open room as it stands.
  static Future<void> enter(BuildContext context, RoomState state) =>
      Navigator.of(context).push<void>(_route(state));

  /// A guest steps in through an invitation: join first (the server checks the
  /// invitation), then open the room. Errors propagate so the caller's
  /// banner can show the server's reason.
  static Future<void> enterAsGuest(BuildContext context, String roomId) async {
    final state = await _service.join(roomId);
    if (!context.mounted) return;
    await enter(context, state);
  }

  static Future<void> _guard(BuildContext context, Future<RoomState> Function() open) async {
    try {
      final state = await open();
      if (!context.mounted) return;
      await enter(context, state);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  /// A catalog title (movie, series, anime…): each person plays it in their
  /// own streaming app and the room keeps the shared clock.
  static Future<void> startForPlanned(BuildContext context, CoViewEntry entry) => _guard(
        context,
        () => entry.mediaType == 'game'
            // A planned game is played, not watched: each person runs it on
            // their own machine and the room is the evening around it.
            ? _service.createPlay(
                mediaId: entry.mediaId,
                source: entry.source,
                titleRu: entry.titleRu,
                titleEn: entry.titleEn,
                posterUrl: entry.posterUrl,
                year: entry.year,
                entryId: entry.id,
              )
            : (entry.mediaType == 'book' || entry.mediaType == 'manga')
            // A planned book or manga is read, not watched: each person reads
            // it where they like and the room keeps the chapter counter.
            ? _service.createReading(
                mediaId: entry.mediaId,
                mediaType: entry.mediaType,
                source: entry.source,
                titleRu: entry.titleRu,
                titleEn: entry.titleEn,
                posterUrl: entry.posterUrl,
                year: entry.year,
                readKind: ReadKind.parallel,
                entryId: entry.id,
              )
            : _service.create(
          mediaId: entry.mediaId,
          mediaType: entry.mediaType,
          source: entry.source,
          titleRu: entry.titleRu,
          titleEn: entry.titleEn,
          posterUrl: entry.posterUrl,
          year: entry.year,
          playerKind: PlayerKind.parallel,
          entryId: entry.id,
        ),
      );

  /// A book or a manga read together. For a file ([ReadKind.epub] /
  /// [ReadKind.cbz]) the caller has already opened it on this device: only its
  /// fingerprint and length go to the server, never the text.
  static Future<void> startReading(
    BuildContext context, {
    required String mediaType, // book | manga
    required String title,
    required ReadKind kind,
    String? contentHash,
    int? units,
    String mode = 'own',
  }) {
    final clean = title.trim().isEmpty ? at('без названия', 'untitled') : title.trim();
    // A file is known by its fingerprint; something read elsewhere by its
    // title, so the same title starts the same shared entry again.
    final slug = clean.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    final id = contentHash != null ? 'file:${contentHash.substring(0, 24)}' : 'manual:$slug';
    return _guard(
      context,
      () => _service.createReading(
        mediaId: id.length > 180 ? id.substring(0, 180) : id,
        mediaType: mediaType,
        source: contentHash != null ? 'file' : 'manual',
        titleRu: clean,
        titleEn: clean,
        readKind: kind,
        contentHash: contentHash,
        readUnits: units,
        readMode: mode,
      ),
    );
  }

  /// A game nobody has planned: just its name, and where it is played.
  static Future<void> startPlay(
    BuildContext context, {
    required String title,
    String? platform, // pc | ps | xbox | switch | mobile | other
  }) {
    final clean = title.trim().isEmpty ? at('игра', 'a game') : title.trim();
    final slug = clean.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    return _guard(
      context,
      () => _service.createPlay(
        mediaId: 'manual:${slug.length > 150 ? slug.substring(0, 150) : slug}',
        source: 'manual',
        titleRu: clean,
        titleEn: clean,
        platform: platform,
      ),
    );
  }

  /// A video from "your sources" (YouTube / Twitch recording).
  static Future<void> startForVideo(
    BuildContext context, {
    required String source,
    required String videoId,
    String? title,
    String? thumbnailUrl,
  }) =>
      _guard(
        context,
        () => _service.create(
          mediaId: videoId,
          mediaType: 'video',
          source: source,
          titleRu: title,
          titleEn: title,
          posterUrl: thumbnailUrl,
          playerKind: source == 'twitch' ? PlayerKind.twitch : PlayerKind.youtube,
          playerRef: videoId,
        ),
      );

  /// Whatever the person pasted: a YouTube or Twitch link, or a direct https
  /// link to a file. The server validates it; the error is shown as is.
  static Future<void> startForLink(BuildContext context, String raw, {String? title}) {
    final link = raw.trim();
    final lower = link.toLowerCase();
    final isTwitch = lower.contains('twitch.tv');
    final isYoutube = lower.contains('youtu');
    final kind = isTwitch ? PlayerKind.twitch : (isYoutube ? PlayerKind.youtube : PlayerKind.direct);
    final source = isTwitch ? 'twitch' : (isYoutube ? 'youtube' : 'link');
    final id = _idFrom(link, kind);
    return _guard(
      context,
      () => _service.create(
        mediaId: id,
        mediaType: 'video',
        source: source,
        titleRu: (title == null || title.trim().isEmpty) ? at('видео по ссылке', 'video from a link') : title.trim(),
        titleEn: (title == null || title.trim().isEmpty) ? at('видео по ссылке', 'video from a link') : title.trim(),
        playerKind: kind,
        playerRef: link,
      ),
    );
  }

  static String _idFrom(String link, PlayerKind kind) {
    final uri = Uri.tryParse(link.contains('://') ? link : 'https://$link');
    if (uri == null) return link;
    switch (kind) {
      case PlayerKind.youtube:
        if (uri.host.contains('youtu.be')) return uri.pathSegments.isEmpty ? link : uri.pathSegments.first;
        return uri.queryParameters['v'] ?? (uri.pathSegments.length >= 2 ? uri.pathSegments[1] : link);
      case PlayerKind.twitch:
        return uri.pathSegments.length >= 2 ? uri.pathSegments[1] : link;
      default:
        return link.length > 180 ? link.substring(0, 180) : link;
    }
  }
}
