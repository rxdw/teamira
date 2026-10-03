import 'package:flutter/material.dart';

import '../../../models/co_view_entry.dart';
import '../../../services/api_client.dart';
import '../../../services/pair_album_service.dart';
import 'album_strings.dart';
import 'note_reveal_screen.dart';

/// The one place that answers "the evening was just marked watched — did
/// that unseal a note for me?". Called from every spot that flips a
/// co-viewing entry to watched (the co-viewing hub, and the two buttons on
/// the evening plan card), so the ceremony can't be forgotten by one of
/// them.
///
/// Best-effort by design: the evening is already logged by the time this
/// runs, so nothing here may throw into the caller — a failed lookup just
/// means the envelope waits in the book, marked "new", instead of opening
/// on the spot.
Future<void> playRevealIfAny(
  BuildContext context, {
  required CoViewEntry watched,
  String? partnerName,
}) async {
  if (watched.albumRevealCount <= 0) return;
  try {
    final service = PairAlbumService(ApiClient.instance);
    final pages = await service.pages(limit: 8);
    final page = pages.items.cast<dynamic>().firstWhere(
          (p) => p.mediaId == watched.mediaId && p.source == watched.source && p.unread == true,
          orElse: () => null,
        );
    if (page == null || !context.mounted) return;
    await showPageReveal(
      context,
      page: page,
      partnerName: partnerName ?? at('партнёр', 'partner'),
    );
  } catch (_) {
    // See above: never let the bonus moment break the flow that earned it.
  }
}
