import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/co_view_entry.dart';
import '../models/diary_entry.dart';
import '../models/media_item.dart' show CastMember;
import '../models/watchlist_entry.dart';
import '../screens/title/title_detail_screen.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'edit_review_sheet.dart';
import 'heart_rating.dart';
import 'review_composer.dart';
import 'share_card.dart';
import 'share_sheet.dart';
import 'source_video_link.dart';
import '../services/app_translations.dart';

/// Everything [WatchedPreviewCard] needs to draw itself, gathered from
/// whichever shelf the person tapped into — the diary log, a "route"/
/// "stops" screen, the ticket garland, or the profile's watched grid.
/// Those four sources hand over slightly different models
/// ([DiaryEntry], [WatchlistEntry]), so this is the one shape they all
/// get funneled into rather than the card knowing about any of them.
class WatchedPreviewData {
  final String mediaId;
  final String source;
  final String mediaType;
  final String title;
  final String? posterUrl;
  final int? rating; // hearts, 0-10
  final String? note;
  final DateTime? date;
  final List<String> moodTags;
  // Up to 3 cast members picked as this evening's standouts (see
  // DiaryEntry.favoriteCast) — shown here as a small unlabeled row of
  // faces, same "just avatars, no names" treatment the confirm step's
  // own preview gives them before anything's even saved. Empty when
  // that step was skipped, or for a row logged before this shipped —
  // see WatchlistEntry.favoriteCast's own docstring for how the
  // shelf-level sources (`fromWatchlistEntry`/`fromFriendEntry`) get
  // this. `fromCoViewEntry` never sets it: that grid deliberately has
  // no personal layer at all (see its own docstring).
  final List<CastMember> favoriteCast;
  final String? watchedWithUsername;
  final bool isRewatch;
  final Widget shareCard;
  final String shareFileName;
  final String shareText;
  // Turned off for a friend's activity row (see
  // widgets/activity_preview.dart) — there's no real "evening" to
  // render into a shareable card for someone else's watch, just a
  // logged fact, so the button is hidden entirely rather than sharing
  // an empty card.
  final bool showShareButton;
  // Set only for a friend's activity row (see activity_preview.dart) —
  // rendered as a small "seen by ___" line under the title instead of
  // the "watched with" heart row above, which implies a shared/co-
  // viewed evening rather than someone else's own.
  final String? friendLabel;
  // Set only when this preview came from an actual [DiaryEntry] (see
  // `fromDiaryEntry` below) — that's what `PATCH /diary/{entry_id}` needs
  // to edit the review. Left null for `fromWatchlistEntry`: a
  // `WatchlistEntry` is a title-level snapshot with no diary row of its
  // own to edit, so the card just doesn't offer an edit affordance there.
  final String? entryId;

  const WatchedPreviewData({
    required this.mediaId,
    required this.source,
    required this.mediaType,
    required this.title,
    this.posterUrl,
    this.rating,
    this.note,
    this.date,
    this.moodTags = const [],
    this.favoriteCast = const [],
    this.watchedWithUsername,
    this.isRewatch = false,
    required this.shareCard,
    required this.shareFileName,
    required this.shareText,
    this.showShareButton = true,
    this.friendLabel,
    this.entryId,
  });

  /// A logged evening straight from the diary, a route/stop card, or the
  /// ticket garland.
  factory WatchedPreviewData.fromDiaryEntry(DiaryEntry entry) => WatchedPreviewData(
        mediaId: entry.mediaId,
        source: entry.source,
        mediaType: entry.mediaType,
        title: entry.displayTitle,
        posterUrl: entry.posterUrl,
        rating: entry.rating,
        note: entry.note,
        date: entry.watchedAt,
        moodTags: entry.moodTags,
        favoriteCast: entry.favoriteCast,
        watchedWithUsername: entry.watchedWithUsername,
        isRewatch: entry.isRewatch,
        shareCard: EveningShareCard(entry: entry, fallbackColor: SeenlyPalette.mediaColor(entry.mediaType)),
        shareFileName: 'seenly-${entry.id}',
        shareText: 'watched "${entry.displayTitle}" — logged in seenly',
        entryId: entry.id,
      );

  /// A row from the profile's watched grid — reshaped into a throwaway
  /// [DiaryEntry] just so it can ride the same [EveningShareCard] the
  /// diary already uses, rather than maintaining a second share design.
  factory WatchedPreviewData.fromWatchlistEntry(WatchlistEntry entry) {
    final asDiary = DiaryEntry(
      id: entry.id,
      mediaId: entry.mediaId,
      mediaType: entry.mediaType,
      source: entry.source,
      titleRu: entry.titleRu,
      titleEn: entry.titleEn,
      posterUrl: entry.posterUrl,
      rating: entry.userRating,
      note: entry.note,
      moodTags: entry.moodTags,
      favoriteCast: entry.favoriteCast,
      isRewatch: false,
      watchedAt: entry.watchedAt ?? DateTime.now(),
      createdAt: entry.watchedAt ?? DateTime.now(),
    );
    return WatchedPreviewData(
      mediaId: entry.mediaId,
      source: entry.source,
      mediaType: entry.mediaType,
      title: entry.displayTitle,
      posterUrl: entry.posterUrl,
      rating: entry.userRating,
      note: entry.note,
      date: entry.watchedAt,
      moodTags: entry.moodTags,
      favoriteCast: entry.favoriteCast,
      shareCard: EveningShareCard(entry: asDiary, fallbackColor: SeenlyPalette.mediaColor(entry.mediaType)),
      shareFileName: 'seenly-${entry.id}',
      shareText: 'watched "${entry.displayTitle}" — logged in seenly',
    );
  }

  /// A row from a friend's watched/watching/plan-to-watch shelf (see
  /// FriendProfileScreen) — same shape as [fromWatchlistEntry], but
  /// tagged with whose shelf it came from (shown as a quiet "seen by
  /// ___" line) and with sharing turned off, since there's no real
  /// "evening" here to share, just this account looking at a friend's
  /// logged fact.
  factory WatchedPreviewData.fromFriendEntry(WatchlistEntry entry, {required String friendLabel}) {
    final asDiary = DiaryEntry(
      id: entry.id,
      mediaId: entry.mediaId,
      mediaType: entry.mediaType,
      source: entry.source,
      titleRu: entry.titleRu,
      titleEn: entry.titleEn,
      posterUrl: entry.posterUrl,
      rating: entry.userRating,
      note: entry.note,
      moodTags: entry.moodTags,
      favoriteCast: entry.favoriteCast,
      isRewatch: false,
      watchedAt: entry.watchedAt ?? DateTime.now(),
      createdAt: entry.watchedAt ?? DateTime.now(),
    );
    return WatchedPreviewData(
      mediaId: entry.mediaId,
      source: entry.source,
      mediaType: entry.mediaType,
      title: entry.displayTitle,
      posterUrl: entry.posterUrl,
      rating: entry.userRating,
      note: entry.note,
      date: entry.watchedAt,
      moodTags: entry.moodTags,
      favoriteCast: entry.favoriteCast,
      friendLabel: friendLabel,
      showShareButton: false,
      shareCard: EveningShareCard(entry: asDiary, fallbackColor: SeenlyPalette.mediaColor(entry.mediaType)),
      shareFileName: 'seenly-${entry.id}',
      shareText: 'watched "${entry.displayTitle}" — logged in seenly',
    );
  }

  /// A row from the shared co-viewing "watched" grid. There's no personal
  /// rating or note at the co-viewing level (see CoViewEntry) — those
  /// live in each person's own diary — so this only ever shows the plain
  /// facts, with [watchedWith] always set (unlike the personal grids,
  /// where it's usually null: here it's always true by definition).
  /// Just a display string — the caller already joins everyone else in
  /// the circle into one line (e.g. "Alice, Bob & Carol") for a company,
  /// same as it would show one name for a couple.
  factory WatchedPreviewData.fromCoViewEntry(CoViewEntry entry, {String? watchedWith}) {
    final asDiary = DiaryEntry(
      id: entry.id,
      mediaId: entry.mediaId,
      mediaType: entry.mediaType,
      source: entry.source,
      titleRu: entry.titleRu,
      titleEn: entry.titleEn,
      posterUrl: entry.posterUrl,
      isRewatch: false,
      watchedWithUsername: watchedWith,
      watchedAt: entry.watchedAt ?? entry.createdAt,
      createdAt: entry.watchedAt ?? entry.createdAt,
    );
    return WatchedPreviewData(
      mediaId: entry.mediaId,
      source: entry.source,
      mediaType: entry.mediaType,
      title: entry.displayTitle,
      posterUrl: entry.posterUrl,
      date: entry.watchedAt ?? entry.createdAt,
      watchedWithUsername: watchedWith,
      shareCard: EveningShareCard(entry: asDiary, fallbackColor: SeenlyPalette.mediaColor(entry.mediaType)),
      shareFileName: 'seenly-${entry.id}',
      shareText: 'watched "${entry.displayTitle}" together — logged in seenly',
    );
  }
}

const _kPreviewMonths = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

String _previewDateLabel(DateTime? d) {
  if (d == null) return '';
  return '${d.day} ${_kPreviewMonths[d.month - 1]} ${d.year}';
}

/// Opens the soft, blurred-backdrop "you watched this" card — the same
/// stop everywhere someone taps into something already logged: the
/// diary row, a route/stop card, a ticket on the garland, or a tile in
/// the profile's watched grid. Tapping the poster inside is what
/// actually opens the full title page; everything else here is just a
/// quiet look back at the evening itself.
Future<void> showWatchedPreview(BuildContext context, WatchedPreviewData data) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'watched preview',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, __) => WatchedPreviewCard(data: data),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The card itself: a soft blur dims everything behind it, and a single
/// paper card floats in the middle with the poster, the evening's
/// details, and a way to share or open the title. Tapping anywhere
/// outside the card closes it, same as any other soft sheet.
class WatchedPreviewCard extends StatefulWidget {
  final WatchedPreviewData data;
  const WatchedPreviewCard({super.key, required this.data});

  @override
  State<WatchedPreviewCard> createState() => _WatchedPreviewCardState();
}

class _WatchedPreviewCardState extends State<WatchedPreviewCard> {
  late WatchedPreviewData _data;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
  }

  void _openTitle(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TitleDetailScreen(
          mediaId: _data.mediaId,
          source: _data.source,
          mediaType: _data.mediaType,
          seedTitle: _data.title,
          seedPosterUrl: _data.posterUrl,
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final entryId = _data.entryId;
    if (entryId == null) return;
    final asEntry = DiaryEntry(
      id: entryId,
      mediaId: _data.mediaId,
      mediaType: _data.mediaType,
      source: _data.source,
      titleEn: _data.title,
      posterUrl: _data.posterUrl,
      rating: _data.rating,
      note: _data.note,
      moodTags: _data.moodTags,
      favoriteCast: _data.favoriteCast,
      watchedWithUsername: _data.watchedWithUsername,
      isRewatch: _data.isRewatch,
      watchedAt: _data.date ?? DateTime.now(),
      createdAt: _data.date ?? DateTime.now(),
    );
    final result = await showEditReviewSheet(context, asEntry);
    if (result == null || !mounted) return;
    if (result.deleted) {
      // Nothing left to preview — close the card too rather than
      // leaving it showing an evening that's just been deleted.
      Navigator.of(context).pop();
      return;
    }
    if (result.entry != null) {
      setState(() {
        _data = WatchedPreviewData.fromDiaryEntry(result.entry!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final hasNote = data.note != null && data.note!.trim().isNotEmpty;
    // Rough "won't fit in the card's own 5-line preview" heuristic —
    // exact enough without measuring actual text layout, same spirit
    // as every other lightweight length check in this app. Long here
    // means "worth its own page", not a hard cutoff on what's saved.
    final isLongNote = hasNote &&
        (data.note!.trim().length > 220 || '\n'.allMatches(data.note!.trim()).length >= 4);
    final hasRating = data.rating != null && data.rating! > 0;
    // showGeneralDialog doesn't wrap its pageBuilder in a Material the
    // way showModalBottomSheet/showDialog's own Dialog widget do — the
    // share button below (OutlinedButton) needs one for its ripple, so
    // this supplies it rather than relying on whatever happens to sit
    // above wherever this got opened from.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(color: SeenlyPalette.ink.withOpacity(0.28)),
            ),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Container(
              width: 320,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              decoration: BoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: SeenlyPalette.ink.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 12)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (data.entryId != null) ...[
                        GestureDetector(
                          onTap: () => _edit(context),
                          child: Container(
                            width: 26,
                            height: 26,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                            child: const Icon(Icons.edit_outlined, size: 13, color: SeenlyPalette.inkMuted),
                          ),
                        ),
                      ],
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 14, color: SeenlyPalette.inkMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _openTitle(context),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 128,
                            height: 186,
                            child: data.posterUrl != null && data.posterUrl!.isNotEmpty
                                ? Image.network(
                                    data.posterUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.mediaColor(data.mediaType)),
                                  )
                                : Container(
                                    color: SeenlyPalette.mediaColor(data.mediaType),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.movie_creation_outlined, color: SeenlyPalette.paper, size: 28),
                                  ),
                          ),
                        ),
                        // A small, quiet badge riding the poster's corner —
                        // the visual cue that this image opens something,
                        // instead of a caption underneath that risks
                        // looking like a broken link on some devices.
                        Positioned(
                          right: -8,
                          bottom: -8,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: SeenlyPalette.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: SeenlyPalette.paper, width: 2.5),
                              boxShadow: SeenlyPalette.softShadow,
                            ),
                            child: Icon(
                              isSourceVideo(data.source) ? Icons.play_arrow_rounded : Icons.open_in_new,
                              size: 14,
                              color: SeenlyPalette.accentOnAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    data.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(italic: true, size: 19, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    data.isRewatch ? 'rewatch · ${data.mediaType} · ${_previewDateLabel(data.date)}' : '${data.mediaType} · ${_previewDateLabel(data.date)}',
                    style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                  ),
                  if (data.watchedWithUsername != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, size: 11, color: SeenlyPalette.accent),
                        const SizedBox(width: 4),
                        Text('watched with ${data.watchedWithUsername}',
                            style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
                      ],
                    ),
                  ],
                  if (data.friendLabel != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.visibility_outlined, size: 11, color: SeenlyPalette.inkFaint),
                        const SizedBox(width: 4),
                        Text(data.friendLabel!,
                            style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                      ],
                    ),
                  ],
                  if (hasRating) ...[
                    const SizedBox(height: 12),
                    HeartRating(value: data.rating!, size: 15),
                  ],
                  if (data.moodTags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in data.moodTags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: SeenlyPalette.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(tag, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkMuted)),
                          ),
                      ],
                    ),
                  ],
                  if (data.favoriteCast.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: SizedBox(
                        // Overlapping little stack of faces, no names —
                        // just enough to say "these stood out", not a
                        // second cast list. Each face after the first
                        // sits 30px to the right, so the whole stack is
                        // exactly one avatar plus 30px per extra face.
                        width: 44.0 + (data.favoriteCast.length - 1) * 30.0,
                        height: 44,
                        child: Stack(
                          children: [
                            for (var i = 0; i < data.favoriteCast.length; i++)
                              Positioned(
                                left: i * 30.0,
                                child: ClipOval(
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: SeenlyPalette.paper, width: 2.5),
                                    ),
                                    child: (data.favoriteCast[i].photoUrl != null)
                                        ? Image.network(data.favoriteCast[i].photoUrl!, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.mediaColor(data.mediaType)))
                                        : Container(color: SeenlyPalette.mediaColor(data.mediaType)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: isLongNote
                        ? () => showReviewComposer(
                              context,
                              initialText: data.note!,
                              forTitle: data.title,
                              readOnly: true,
                            )
                        : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Text(
                            hasNote ? '“${data.note!.trim()}”' : 'no review left for this one yet',
                            textAlign: TextAlign.center,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.serif(
                              italic: true,
                              size: 13,
                              color: hasNote ? SeenlyPalette.ink : SeenlyPalette.placeholder,
                            ),
                          ),
                          if (isLongNote) ...[
                            const SizedBox(height: 8),
                            Text('read the full review →'.tr,
                                style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (isSourceVideo(data.source)) ...[
                    const SizedBox(height: 12),
                    WatchOnSourceButton(source: data.source, mediaId: data.mediaId),
                  ],
                  const SizedBox(height: 18),
                  if (data.showShareButton)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        showShareCardSheet(
                          context,
                          card: data.shareCard,
                          fileName: data.shareFileName,
                          shareText: data.shareText,
                        );
                      },
                      icon: const Icon(Icons.ios_share, size: 15, color: SeenlyPalette.accent),
                      label: Text('share this evening'.tr,
                          style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.accent)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: SeenlyPalette.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}
