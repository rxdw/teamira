import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/tmdb_review.dart';
import '../services/spoiler_prefs_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'spoiler_veil.dart';
import 'themed_loading_indicator.dart';
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// Opened by tapping the "N reviews" line under a title's ratings —
/// written reviews come from TMDB and Trakt (see
/// backend/app/routers/reviews.py for why IMDB still isn't an
/// option). `tmdbId` is expected non-null; callers already hide the tap
/// target otherwise.
Future<void> showReviewsSheet(
  BuildContext context, {
  required String mediaType,
  required String tmdbId,
  required String title,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _ReviewsSheet(mediaType: mediaType, tmdbId: tmdbId, title: title),
  );
}

class _ReviewsSheet extends StatefulWidget {
  final String mediaType;
  final String tmdbId;
  final String title;
  const _ReviewsSheet({required this.mediaType, required this.tmdbId, required this.title});

  @override
  State<_ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends State<_ReviewsSheet> {
  TmdbReviewsResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppState>().media.reviews(
            mediaType: widget.mediaType,
            tmdbId: widget.tmdbId,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviews = _result?.reviews ?? const [];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('reviews'.tr, style: SeenlyText.serif(italic: true, size: 16)),
            const SizedBox(height: 4),
            Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            const SizedBox(height: 14),
            if (_loading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: SizedBox(
                    width: 20, height: 20,
                    child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
                  ),
                ),
              )
            else if (reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  "No written reviews for this title yet".tr,
                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
                ),
              )
            else ...[
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: reviews.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, i) => _ReviewCard(review: reviews[i]),
                ),
              ),
              const SizedBox(height: 12),
              Text(_result!.attribution.tr,
                  style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final TmdbReview review;
  const _ReviewCard({required this.review});

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: SeenlyPalette.accent.withOpacity(0.15),
                backgroundImage: r.avatarUrl != null ? NetworkImage(r.avatarUrl!) : null,
                child: r.avatarUrl == null
                    ? Text(r.author.isNotEmpty ? r.author[0].toUpperCase() : '?',
                        style: SeenlyText.serif(size: 12, weight: FontWeight.w600, color: SeenlyPalette.accent))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(r.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: 13, weight: FontWeight.w600)),
              ),
              if (r.rating != null) ...[
                Icon(Icons.star_rounded, size: 14, color: SeenlyPalette.mustard),
                const SizedBox(width: 2),
                Text(r.rating!.toStringAsFixed(1), style: SeenlyText.mono(size: 11)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SpoilerVeil(
            active: context.watch<SpoilerPrefsService>().blurReviews,
            label: 'this review might spoil it'.tr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.content,
                  maxLines: _expanded ? null : 5,
                  overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: SeenlyText.bodyText.copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'show less' : 'read more',
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
                ),
              ],
            ),
          ),
          if (r.url.isNotEmpty) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication),
              child: Text('${'open on'.tr} ${r.source == 'trakt' ? 'Trakt' : 'TMDB'}',
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            ),
          ],
        ],
      ),
    );
  }
}
