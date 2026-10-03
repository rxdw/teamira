import 'package:flutter/material.dart';

import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../services/api_client.dart';
import 'share_card.dart';
import 'share_sheet.dart';

/// The link a shared title carries — points at Seenly's own landing page
/// (backend/app/routers/linking.py's `GET /t`, the title counterpart of
/// the referral `/i/{code}` page) rather than sending whoever opens it
/// off to IMDb or TMDB. That page tries to open the app itself first and
/// only falls back to a store link, so tapping a shared title leads back
/// into Seenly instead of away from it.
///
/// Carries `source` (not just `type`/`id`) so the app can call
/// MediaService.detail straight off the link on the other end — see
/// services/title_link_service.dart, which is what actually reads this
/// back apart.
Future<String> titleShareLink(MediaItem item) async {
  final baseUrl = await ApiClient.instance.resolveBaseUrl();
  final title = Uri.encodeComponent(item.title.display);
  return '$baseUrl/t?type=${item.mediaType}&id=${item.id}&source=${item.source}&title=$title';
}

/// Opens the same warm, corkboard-styled preview-then-share sheet used
/// for an evening or a wrapped year (see share_sheet.dart), but for a
/// title itself — the "look what I found" share rather than "look what
/// I watched". Reachable from the title card's own action row and from
/// the poster lightbox, so it reads the same wherever it's opened from.
Future<void> shareTitle(
  BuildContext context, {
  required MediaItem item,
  required Color fallbackColor,
  MediaRatings? ratings,
}) async {
  final bits = [
    item.title.display,
    if (item.year != null) '(${item.year})',
  ].join(' ');
  final link = await titleShareLink(item);
  if (!context.mounted) return;
  await showShareCardSheet(
    context,
    card: TitleShareCard(item: item, fallbackColor: fallbackColor, ratings: ratings),
    fileName: 'title-${item.id}',
    shareText: '$bits\n$link',
    rewardKey: 'title-${item.id}',
  );
}
