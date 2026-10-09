import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/tmdb_review.dart';
import '../services/spoiler_prefs_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';
import 'spoiler_veil.dart';
import 'themed_loading_indicator.dart';
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// Opened by tapping the "N reviews" line under a title's ratings —
/// written reviews come from TMDB and Trakt, plus Kinopoisk for
/// Russian-language users (see backend/app/routers/reviews.py for why IMDB
/// still isn't an option); Steam for a game, AniList for a manga. When more
/// than one source has reviews, a row of filter chips lets the reader narrow
/// to one. Films/series are looked up by `tmdbId`, games/manga by `mediaId`;
/// whichever one the title needs is expected
/// non-null; callers already hide the tap target otherwise.
Future<void> showReviewsSheet(
  BuildContext context, {
  required String mediaType,
  String? tmdbId,
  String? mediaId,
  required String title,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _ReviewsSheet(
      mediaType: mediaType,
      tmdbId: tmdbId,
      mediaId: mediaId,
      title: title,
    ),
  );
}

class _ReviewsSheet extends StatefulWidget {
  final String mediaType;
  final String? tmdbId;
  final String? mediaId;
  final String title;
  const _ReviewsSheet({
    required this.mediaType,
    this.tmdbId,
    this.mediaId,
    required this.title,
  });

  @override
  State<_ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends State<_ReviewsSheet> {
  TmdbReviewsResult? _result;
  bool _loading = true;
  String _filter = 'all'; // 'all' | a TmdbReview.source

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
            mediaId: widget.mediaId,
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

  /// Sources that actually have reviews, in the order the chips show
  /// them — Kinopoisk first (it's the one Russian-language readers came
  /// for), then Trakt, then TMDB (a game's Steam and a manga's AniList are
  /// always alone, so their place in the order doesn't matter) — with how
  /// many each contributed.
  List<MapEntry<String, int>> _sourceCounts(List<TmdbReview> all) {
    const order = ['kinopoisk', 'trakt', 'tmdb', 'steam', 'anilist'];
    final counts = <String, int>{};
    for (final r in all) {
      counts[r.source] = (counts[r.source] ?? 0) + 1;
    }
    return [
      for (final key in order)
        if (counts.containsKey(key)) MapEntry(key, counts[key]!),
      for (final e in counts.entries)
        if (!order.contains(e.key)) e,
    ];
  }

  Widget _filterChips(List<MapEntry<String, int>> sources, int total) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          PillChip(
            label: '${'all'.tr} · $total',
            active: _filter == 'all',
            onTap: () => setState(() => _filter = 'all'),
          ),
          for (final s in sources) ...[
            const SizedBox(width: 6),
            PillChip(
              label: '${_sourceLabel(s.key)} · ${s.value}',
              active: _filter == s.key,
              onTap: () => setState(() => _filter = s.key),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _result?.reviews ?? const <TmdbReview>[];
    final sources = _sourceCounts(all);
    // A single source needs no filter; and if the active one vanished
    // (it can't today, but a reload could), fall back to everything.
    final showFilter = sources.length > 1;
    final activeFilter =
        showFilter && sources.any((e) => e.key == _filter) ? _filter : 'all';
    final reviews = activeFilter == 'all'
        ? all
        : all.where((r) => r.source == activeFilter).toList();
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
            if (!_loading && showFilter) ...[
              _filterChips(sources, all.length),
              const SizedBox(height: 14),
            ],
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
                  itemBuilder: (context, i) => _ReviewCard(
                    // Keyed so switching filters doesn't carry one card's
                    // expanded state over to a different review.
                    key: ValueKey('${reviews[i].source}-${reviews[i].url}-$i'),
                    review: reviews[i],
                  ),
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

/// How a source is named on chips and "open on …" links.
String _sourceLabel(String source) {
  switch (source) {
    case 'kinopoisk':
      return 'Kinopoisk'.tr;
    case 'trakt':
      return 'Trakt';
    case 'steam':
      return 'Steam';
    case 'anilist':
      return 'AniList';
    default:
      return 'TMDB';
  }
}

/// "170 h in game" — whole hours from ten up, one decimal below that.
String _playtimeLabel(double hours) {
  final shown = hours >= 10 ? hours.round().toString() : hours.toStringAsFixed(1);
  return '$shown ${'h in game'.tr}';
}

/// A review's tone, as a washi-tape tag in the palette's existing sage /
/// rose / mustard — warm for positive, muted for negative, never alarm-red.
/// Kinopoisk reviewers pick the tone themselves; for Steam it is the
/// reviewer's thumb (so the tag says "recommends" / "doesn't recommend");
/// for AniList it is derived from the reviewer's score.
class _ToneTag extends StatelessWidget {
  final String tone;
  final String source;
  const _ToneTag({required this.tone, required this.source});

  @override
  Widget build(BuildContext context) {
    final steam = source == 'steam';
    final (Color color, String label) = switch (tone) {
      'positive' => (SeenlyPalette.tapeSage, (steam ? 'recommends' : 'positive').tr),
      'negative' => (SeenlyPalette.tapeRose, (steam ? "doesn't recommend" : 'negative').tr),
      _ => (SeenlyPalette.tapeMustard, 'neutral'.tr),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: SeenlyText.mono(size: 9, color: SeenlyPalette.ink)),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final TmdbReview review;
  const _ReviewCard({super.key, required this.review});

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
              if (r.tone != null) ...[
                _ToneTag(tone: r.tone!, source: r.source),
                const SizedBox(width: 8),
              ],
              if (r.rating != null) ...[
                Icon(Icons.star_rounded, size: 14, color: SeenlyPalette.mustard),
                const SizedBox(width: 2),
                Text(r.rating!.toStringAsFixed(1), style: SeenlyText.mono(size: 11)),
              ],
            ],
          ),
          if (r.playtimeHours != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Text(_playtimeLabel(r.playtimeHours!),
                  style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
            ),
          ],
          const SizedBox(height: 8),
          SpoilerVeil(
            active: context.watch<SpoilerPrefsService>().blurReviews,
            label: 'this review might spoil it'.tr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.title != null && r.title!.isNotEmpty) ...[
                  Text(r.title!, style: SeenlyText.serif(size: 13, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                ],
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
          if (r.url.isNotEmpty || (r.likes ?? 0) > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if ((r.likes ?? 0) > 0) ...[
                  Icon(Icons.thumb_up_alt_outlined, size: 11, color: SeenlyPalette.inkFaint),
                  const SizedBox(width: 4),
                  Text('${r.likes}', style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                  const SizedBox(width: 12),
                ],
                if (r.url.isNotEmpty)
                  Flexible(
                    child: GestureDetector(
                      onTap: () => launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication),
                      // Kinopoisk, Steam and AniList texts are shortened
                      // server-side, so that link promises the whole
                      // review, not just "open".
                      child: Text(
                        '${(const {'kinopoisk', 'steam', 'anilist'}.contains(r.source) ? 'read in full on' : 'open on').tr} ${_sourceLabel(r.source)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
