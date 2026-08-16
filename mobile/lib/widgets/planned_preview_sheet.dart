import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/co_view_entry.dart';
import '../models/media_item.dart';
import '../models/watchlist_entry.dart';
import '../screens/title/title_detail_screen.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'source_video_link.dart';
import 'themed_loading_indicator.dart';
import '../services/app_translations.dart';

/// Everything [PlannedPreviewCard] needs — the "plan to watch" grid's
/// counterpart to [WatchedPreviewData] (see watched_preview_sheet.dart).
/// There's no watched date, rating, or note yet — that's the whole point
/// of this shelf — so this only carries what a not-yet-watched title
/// actually has: the snapshot plus enough ids to flip it to watched.
class PlannedPreviewData {
  final String mediaId;
  final String source;
  final String mediaType;
  final String title;
  final String? posterUrl;
  final int? year;
  // Set only for a co-viewing entry planned with a schedule (see
  // PlannedEvening / plan_evening_sheet.dart's co-viewing toggle) — a
  // personal watchlist row, a bare suggest-heart, or a Watch Together
  // match never has one.
  final DateTime? scheduledDate;
  final int? scheduledHour;
  final int? scheduledMinute;

  const PlannedPreviewData({
    required this.mediaId,
    required this.source,
    required this.mediaType,
    required this.title,
    this.posterUrl,
    this.year,
    this.scheduledDate,
    this.scheduledHour,
    this.scheduledMinute,
  });

  bool get hasSchedule => scheduledDate != null;

  /// "Aug 12" or "Aug 12 · 7:30 PM" — everything the card needs to say
  /// *when* this evening is, in one line.
  String? get scheduledLabel {
    final date = scheduledDate;
    if (date == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateLabel = '${months[date.month - 1]} ${date.day}';
    if (scheduledHour == null || scheduledMinute == null) return dateLabel;
    final h = scheduledHour!;
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mm = scheduledMinute!.toString().padLeft(2, '0');
    return '$dateLabel · $h12:$mm $period';
  }

  factory PlannedPreviewData.fromWatchlistEntry(WatchlistEntry entry) =>
      PlannedPreviewData(
        mediaId: entry.mediaId,
        source: entry.source,
        mediaType: entry.mediaType,
        title: entry.displayTitle,
        posterUrl: entry.posterUrl,
        year: entry.year,
      );

  /// A row from the shared co-viewing "planned" grid — same card, just
  /// fed from the pair's shared entry instead of this account's own
  /// personal watchlist row. The caller supplies its own
  /// [showPlannedPreview] `onMarkWatched` (marking a co-view entry
  /// watched is a different endpoint than a personal one — see
  /// CoViewingScreen), so this factory only needs to carry the snapshot.
  factory PlannedPreviewData.fromCoViewEntry(CoViewEntry entry) => PlannedPreviewData(
        mediaId: entry.mediaId,
        source: entry.source,
        mediaType: entry.mediaType,
        title: entry.displayTitle,
        posterUrl: entry.posterUrl,
        year: entry.year,
        scheduledDate: entry.scheduledDate,
        scheduledHour: entry.scheduledHour,
        scheduledMinute: entry.scheduledMinute,
      );

  /// A minimal [MediaItem] built from the snapshot — same reasoning as
  /// `Suggestion.toMediaItem()` — enough for `/feed/react` to mark it
  /// watched; the full title screen refetches everything else itself.
  MediaItem toMediaItem() => MediaItem(
        id: mediaId,
        mediaType: mediaType,
        externalIds: const ExternalIds(),
        title: LocalizedText(en: title),
        description: const LocalizedText(),
        posterUrl: posterUrl,
        year: year,
        source: source,
      );
}

/// Opens the same soft, blurred-backdrop card style as
/// [showWatchedPreview] — this is the "plan to watch" grid's version:
/// tapping the poster opens the full title page, and the action button
/// flips it over to watched right from here, without a trip through the
/// full title screen. Calls [onMarkedWatched] once that succeeds so the
/// caller (the profile grid, or CoViewingScreen) can refresh itself.
///
/// [onMarkWatched] defaults to a personal `/feed/react` "watched" call
/// (the profile's own "plan to watch" grid). CoViewingScreen passes its
/// own — marking a *shared* entry watched is a different endpoint (see
/// `PartnerService.markCoViewWatched`) and logs the evening into both
/// diaries at once, not just this account's.
Future<void> showPlannedPreview(
  BuildContext context,
  PlannedPreviewData data, {
  required VoidCallback onMarkedWatched,
  Future<void> Function()? onMarkWatched,
  String actionLabel = 'mark as watched',
  String placeholderText = 'still on your plan to watch — mark it once you have',
}) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'plan to watch preview',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, __) => PlannedPreviewCard(
      data: data,
      onMarkedWatched: onMarkedWatched,
      onMarkWatched: onMarkWatched,
      actionLabel: actionLabel,
      placeholderText: placeholderText,
    ),
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

class PlannedPreviewCard extends StatefulWidget {
  final PlannedPreviewData data;
  final VoidCallback onMarkedWatched;
  final Future<void> Function()? onMarkWatched;
  final String actionLabel;
  final String placeholderText;
  const PlannedPreviewCard({
    super.key,
    required this.data,
    required this.onMarkedWatched,
    this.onMarkWatched,
    this.actionLabel = 'mark as watched',
    this.placeholderText = 'still on your plan to watch — mark it once you have',
  });

  @override
  State<PlannedPreviewCard> createState() => _PlannedPreviewCardState();
}

class _PlannedPreviewCardState extends State<PlannedPreviewCard> {
  bool _marking = false;

  void _openTitle(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TitleDetailScreen(
          mediaId: widget.data.mediaId,
          source: widget.data.source,
          mediaType: widget.data.mediaType,
          seedTitle: widget.data.title,
          seedPosterUrl: widget.data.posterUrl,
        ),
      ),
    );
  }

  Future<void> _markWatched(BuildContext context) async {
    if (_marking) return;
    setState(() => _marking = true);
    try {
      if (widget.onMarkWatched != null) {
        await widget.onMarkWatched!();
      } else {
        await context.read<AppState>().feed.react(widget.data.toMediaItem(), 'watched');
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onMarkedWatched();
    } catch (_) {
      if (!mounted) return;
      setState(() => _marking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't mark that watched — try again".tr)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
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
                      data.year != null ? '${data.mediaType} · ${data.year}' : data.mediaType,
                      style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                    ),
                    const SizedBox(height: 16),
                    if (data.hasSchedule) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: SeenlyPalette.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.event, size: 14, color: SeenlyPalette.accent),
                            const SizedBox(width: 6),
                            Text(
                              data.scheduledLabel!,
                              style: SeenlyText.mono(
                                size: 11,
                                weight: FontWeight.w600,
                                color: SeenlyPalette.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        widget.placeholderText,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
                      ),
                    ),
                    if (isSourceVideo(data.source)) ...[
                      const SizedBox(height: 12),
                      WatchOnSourceButton(source: data.source, mediaId: data.mediaId),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _marking ? null : () => _markWatched(context),
                        icon: _marking
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                              )
                            : const Icon(Icons.check_circle_outline, size: 16, color: SeenlyPalette.accentOnAccent),
                        label: Text(widget.actionLabel,
                            style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SeenlyPalette.accent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
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
