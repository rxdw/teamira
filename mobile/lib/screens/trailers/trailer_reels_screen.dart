import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/media_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/poster_lightbox.dart' show scopedPosterHeroTag;
import '../../widgets/scroll_reveal.dart' show ScrollRevealEntrance;
import '../../widgets/wow_motion.dart' show PressScale;
import '../title/title_detail_screen.dart';
import '../../services/app_translations.dart';
import '../../services/locale_service.dart';
import '../../theme/clay_kit.dart';

/// The "for you" trailer feed — reached by tapping a [TrailerPreviewCard] or
/// Home's "watch all" link, never shown by default.
///
/// A plain, freely-scrollable feed of full cards (like the App Store's
/// "Today" story cards), NOT a TikTok-style snap-paged carousel. An earlier
/// version used a vertical [PageView] with `viewportFraction: 0.78` plus a
/// live scale animation so neighbouring cards would "peek" in above/below —
/// in practice that peek reads as a glitch (a card cut off mid-way at the
/// top of the screen) rather than a second, legible card, so it's gone.
/// Each title here is a single complete card with normal margins; scrolling
/// past one reveals the next one in full, the same as any other list.
///
/// This used to autoplay the trailer inline via a WebView + the YouTube
/// IFrame Player API. As of mid-2026 YouTube requires embedded players
/// inside Android apps to pass an app-attestation check (the Android
/// WebView Media Integrity API) before they'll play at all — something a
/// debug/emulator build can never satisfy, and that a hobby project has no
/// good way to set up even on a signed release build. Rather than keep
/// fighting an ever-stricter anti-embedding wall, each card shows the
/// title's own poster/backdrop art and a "watch trailer" button in its info
/// panel that opens the real YouTube app (or a browser tab) on tap —
/// slower than autoplay, but it always works. The YouTube thumbnail
/// (`hqdefault.jpg`, a 480x360 still) is kept only as a last-resort cover
/// image: forcing that landscape still to fill a tall card via `BoxFit
/// .cover` crops away most of the frame and is the other half of why the
/// old feed looked rough, so the title's own poster/backdrop art (already
/// shaped for this) takes priority whenever it exists.
class TrailerReelsScreen extends StatefulWidget {
  final List<MediaItem> items;
  final int initialIndex;

  const TrailerReelsScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<TrailerReelsScreen> createState() => _TrailerReelsScreenState();
}

class _TrailerReelsScreenState extends State<TrailerReelsScreen> {
  late final ScrollController _scrollController;
  final Set<String> _reactedKeys = {};

  @override
  void initState() {
    super.initState();
    // Land on roughly the tapped card rather than always starting at the
    // very top of the feed — an approximate offset (card height is only
    // known once laid out) is enough since this is a normal scroll, not a
    // hard-snapped page.
    _scrollController = ScrollController(
      initialScrollOffset: widget.initialIndex * 520.0,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _react(MediaItem item, String action, String confirmation) async {
    final key = '${item.source}:${item.id}:$action';
    if (_reactedKeys.contains(key)) return;
    _reactedKeys.add(key);
    try {
      await context.read<AppState>().feed.react(item, action);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(confirmation)),
      );
    } catch (_) {
      _reactedKeys.remove(key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't save that just now — try again".tr)),
      );
    }
  }

  Future<void> _share(MediaItem item) async {
    final bits = [
      item.title.display,
      if (item.year != null) '(${item.year})',
    ].join(' ');
    final link = _shareableLink(item);
    await Share.share(link != null ? '$bits\n$link' : bits);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: Stack(
        children: [
          SafeArea(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: widget.items.length,
              itemBuilder: (context, i) {
                final item = widget.items[i];
                final heroTag = scopedPosterHeroTag('home-foryou', item.source, item.id);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  // Each card lifts and fades in as it's scrolled into
                  // view — driven by scroll offset, not a timer, so it
                  // plays exactly once per card, the moment it actually
                  // appears (see ScrollRevealEntrance).
                  child: ScrollRevealEntrance(
                    index: i,
                    driftDistance: 0,
                    child: AspectRatio(
                    aspectRatio: 0.62,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: _ReelCard(
                        item: item,
                        liked: _reactedKeys.contains('${item.source}:${item.id}:like'),
                        watchedMarked: _reactedKeys.contains('${item.source}:${item.id}:watched'),
                        // Same tag Home's TrailerPreviewCard used for this
                        // item (see _homePosterHeroTag there), and reused
                        // again below for the detail push — so the poster
                        // carries one continuous flight from Home, through
                        // this card, into TitleDetailScreen's header,
                        // rather than hard-cutting at either hop.
                        heroTag: heroTag,
                        onLike: () => _react(item, 'like', 'tucked into plan to watch'.tr),
                        onWatched: () => _react(item, 'watched', 'marked as watched'.tr),
                        onShare: () => _share(item),
                        onOpenDetail: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TitleDetailScreen(
                              mediaId: item.id,
                              source: item.source,
                              mediaType: item.mediaType,
                              seedTitle: item.title.display,
                              seedPosterUrl: item.posterUrl,
                              seedItem: item,
                              heroTag: heroTag,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: PressScale(
                onTap: () => Navigator.of(context).pop(),
                scaleTo: 0.88,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.ink.withOpacity(0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, color: SeenlyPalette.paper, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple public link for the title, when there's one to build — IMDb if
/// we have that id, else TMDB, else nothing (share still works, just as
/// plain text).
String? _shareableLink(MediaItem item) {
  final imdb = item.externalIds.imdb;
  if (imdb != null && imdb.isNotEmpty) return 'https://www.imdb.com/title/$imdb/';
  final tmdb = item.externalIds.tmdb;
  if (tmdb != null && tmdb.isNotEmpty) {
    final section = item.mediaType == 'movie' ? 'movie' : 'tv';
    return 'https://www.themoviedb.org/$section/$tmdb';
  }
  return null;
}

/// Builds the YouTube-hosted URL a trailer opens to. `LaunchMode
/// .externalApplication` hands this to the OS, which — on a device with
/// the YouTube app installed — opens the video natively there (autoplay,
/// full controls, none of the embedding restrictions above apply to
/// YouTube's own app); otherwise it falls back to the browser.
Uri _trailerWatchUri(String videoId) =>
    Uri.parse('https://www.youtube.com/watch?v=$videoId');

/// YouTube's predictable, keyless thumbnail URL for a video id.
/// `hqdefault.jpg` (480×360) exists for essentially every public video,
/// unlike `maxresdefault.jpg`, which many uploaders never get generated —
/// so this is the safe first choice, not a fallback. Only reached here once
/// the title's own poster and backdrop are both unavailable — see the
/// class doc above for why.
String _youtubeThumbnailUrl(String videoId) =>
    'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

/// Opens [uri] externally, surfacing a gentle, on-brand message if nothing
/// on the device can handle it (no YouTube app, no browser at all — rare,
/// but the alternative is a silent no-op tap that just feels broken).
Future<void> _openExternally(BuildContext context, Uri uri) async {
  try {
    final opened =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't open that — no app to handle it".tr)),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't open that — no app to handle it".tr)),
      );
    }
  }
}

/// A tidy fallback chain for cover art: tries each url in order, in place,
/// so a missing image quietly resolves to the next candidate instead of an
/// empty frame — never a hard error banner.
class _FallbackCover extends StatelessWidget {
  final List<String> urls;
  final Color emptyColor;

  const _FallbackCover({required this.urls, required this.emptyColor});

  Widget _build(int i) {
    if (i >= urls.length) return Container(color: emptyColor);
    return Image.network(
      urls[i],
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _build(i + 1),
      // Fades the art in once it's actually decoded — already-cached
      // images (a re-scroll, coming back to the feed) show up straight
      // away instead of replaying a fade that was never needed.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => _build(0);
}

/// One small pill-shaped label, used for the media-type badge and the
/// rating badge that sit in the top corners of the card — same paper/ink
/// treatment as the rest of the app, just floating over art instead of
/// sitting on the page background.
class _CardBadge extends StatelessWidget {
  final Widget child;
  const _CardBadge({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: child,
    );
  }
}

String _mediaTypeLabel(String mediaType) {
  if (LocaleService.appIsRussian) return mediaTypeLabel(mediaType);
  if (mediaType.isEmpty) return mediaType;
  return mediaType[0].toUpperCase() + mediaType.substring(1);
}

IconData _mediaTypeIcon(String mediaType) {
  switch (mediaType) {
    case 'movie':
      return Icons.local_movies_outlined;
    case 'series':
      return Icons.live_tv_outlined;
    case 'anime':
      return Icons.auto_awesome_outlined;
    case 'game':
      return Icons.sports_esports_outlined;
    case 'book':
      return Icons.menu_book_outlined;
    case 'manga':
      return Icons.import_contacts_outlined;
    default:
      return Icons.movie_filter_outlined;
  }
}

/// One full card in the feed: cover art, a type badge and (when we have
/// one) a rating badge up top, and an info panel over a bottom scrim with
/// title, a short blurb, and the action row.
class _ReelCard extends StatelessWidget {
  final MediaItem item;
  final bool liked;
  final bool watchedMarked;
  final VoidCallback onLike;
  final VoidCallback onWatched;
  final VoidCallback onShare;
  final VoidCallback onOpenDetail;
  final String heroTag;

  const _ReelCard({
    required this.item,
    required this.liked,
    required this.watchedMarked,
    required this.onLike,
    required this.onWatched,
    required this.onShare,
    required this.onOpenDetail,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final videoId = item.trailerYoutubeId;
    final hasTrailer = videoId != null && videoId.isNotEmpty;

    final meta = [
      if (item.year != null) '${item.year}',
      if (item.genres.isNotEmpty) item.genres.take(2).join(' · '),
    ].join(' · ');

    return PressScale(
      onTap: onOpenDetail,
      scaleTo: 0.985,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The title's own poster/backdrop first — already shaped for a
          // tall card — falling back to the trailer's YouTube thumbnail,
          // and finally a plain media-color fill. Only the real
          // poster/backdrop layer flies under [heroTag] — the YouTube
          // thumbnail and plain-color fallback aren't what Home's card
          // (or TitleDetailScreen's header) show, so Hero-ing them would
          // just make the flight jump to a mismatched image partway
          // through.
          Hero(
            tag: heroTag,
            child: _FallbackCover(
              urls: [
                if (item.posterUrl != null) item.posterUrl!,
                if (item.backdropUrl != null) item.backdropUrl!,
                if (hasTrailer) _youtubeThumbnailUrl(videoId),
              ],
              emptyColor: SeenlyPalette.mediaColor(item.mediaType),
            ),
          ),
          // Scrim only over the lower portion, so the top of the poster
          // stays clean behind the badges.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.42, 1],
                  colors: [Colors.transparent, Color(0xCC1D1712)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardBadge(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_mediaTypeIcon(item.mediaType),
                          size: 13, color: SeenlyPalette.ink),
                      const SizedBox(width: 6),
                      Text(_mediaTypeLabel(item.mediaType),
                          style: SeenlyText.mono(
                              size: 10.5,
                              color: SeenlyPalette.ink,
                              weight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Spacer(),
                if (item.rating != null)
                  _CardBadge(
                    child: Text('★ ${item.rating!.toStringAsFixed(1)}',
                        style: SeenlyText.mono(
                            size: 10.5,
                            color: SeenlyPalette.mustard,
                            weight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title.display,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(
                        italic: true,
                        size: 21,
                        weight: FontWeight.w600,
                        color: SeenlyPalette.paperOnDark)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta,
                      style: SeenlyText.mono(
                          size: 11, color: SeenlyPalette.paperOnDark.withOpacity(0.75))),
                ],
                if ((item.description.display).isNotEmpty &&
                    item.description.display != '—') ...[
                  const SizedBox(height: 10),
                  Text(
                    item.description.display,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(
                        size: 13, color: SeenlyPalette.paperOnDark.withOpacity(0.85)),
                  ),
                ],
                if (hasTrailer) ...[
                  const SizedBox(height: 14),
                  _WatchTrailerButton(
                    onTap: () => _openExternally(context, _trailerWatchUri(videoId)),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _RoundIconButton(icon: Icons.ios_share_rounded, onTap: onShare),
                    const SizedBox(width: 10),
                    // Marking watched here is the quick path (no rating,
                    // no ritual) — it just needs to visibly land: the
                    // icon fills and pops with a small ring, then stays
                    // that way.
                    _RoundIconButton(
                      icon: Icons.check_circle_outline,
                      activeIcon: Icons.check_circle,
                      active: watchedMarked,
                      activeColor: SeenlyPalette.accent,
                      onTap: watchedMarked ? null : onWatched,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PrimaryPill(
                        icon: Icons.favorite_border,
                        activeIcon: Icons.favorite,
                        label: 'plan to watch'.tr,
                        activeLabel: 'on your plan'.tr,
                        active: liked,
                        onTap: liked ? null : onLike,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The clear "go watch it" action that replaces autoplay — a proper
/// full-width button living in the info panel with the rest of the card's
/// actions, not a pill floating in the middle of the poster.
class _WatchTrailerButton extends StatelessWidget {
  final VoidCallback onTap;
  const _WatchTrailerButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.96,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: SeenlyPalette.paperOnDark.withOpacity(0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SeenlyPalette.paperOnDark.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_fill, size: 20, color: SeenlyPalette.paperOnDark),
            const SizedBox(width: 9),
            Text('watch trailer'.tr,
                style: SeenlyText.serif(
                    italic: true,
                    size: 14.5,
                    weight: FontWeight.w600,
                    color: SeenlyPalette.paperOnDark)),
          ],
        ),
      ),
    );
  }
}

/// The single, prominent call-to-action pill — the equivalent of the
/// App Store card's "Посмотрю" button: one clear primary action, full
/// width, using the app's own accent rather than a row of equally-weighted
/// buttons competing for attention.
class _PrimaryPill extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final String? activeLabel;
  final bool active;
  final VoidCallback? onTap;

  const _PrimaryPill({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.activeLabel,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.96,
      haptics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: SeenlyPalette.accent,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: _Landed(
          active: active,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? (activeIcon ?? icon) : icon, size: 16, color: SeenlyPalette.accentOnAccent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  active ? (activeLabel ?? label) : label,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.serif(
                      italic: true,
                      size: 14,
                      weight: FontWeight.w600,
                      color: SeenlyPalette.accentOnAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small round secondary action (share, watched) — same footprint as the
/// screenshot's share icon: quiet, square-ish, off to the side of the one
/// primary pill.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final bool active;
  final Color? activeColor;
  final VoidCallback? onTap;

  const _RoundIconButton({
    required this.icon,
    this.activeIcon,
    this.active = false,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? (activeColor ?? SeenlyPalette.paperOnDark) : SeenlyPalette.paperOnDark;
    return PressScale(
      onTap: onTap,
      scaleTo: 0.88,
      haptics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: active
              ? (activeColor ?? SeenlyPalette.paperOnDark).withOpacity(0.22)
              : SeenlyPalette.paperOnDark.withOpacity(0.16),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(active ? 0.7 : 0.35)),
        ),
        child: _Landed(
          active: active,
          child: Icon(active ? (activeIcon ?? icon) : icon, color: color, size: 20),
        ),
      ),
    );
  }
}

/// Marks the moment a quick action actually "lands": when [active] turns
/// true, [child] pops in with a small overshoot and a thin ring spreads
/// out from it once. Purely decorative on the way there — [child] itself
/// carries the real before/after look (a filled vs outline icon, a
/// changed label); this only plays the arrival.
class _Landed extends StatefulWidget {
  final bool active;
  final Widget child;
  const _Landed({required this.active, required this.child});

  @override
  State<_Landed> createState() => _LandedState();
}

class _LandedState extends State<_Landed> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  @override
  void didUpdateWidget(_Landed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final pop = t <= 0 || t >= 1 ? 1.0 : Curves.easeOutBack.transform((t / 0.55).clamp(0.0, 1.0).toDouble());
        final ring = Curves.easeOutCubic.transform(t);
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (t > 0 && t < 1)
              Container(
                width: 20 + 30 * ring,
                height: 20 + 30 * ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SeenlyPalette.paperOnDark.withOpacity(0.4 * (1 - ring)),
                    width: 1.6 * (1 - ring) + 0.3,
                  ),
                ),
              ),
            Transform.scale(scale: 0.6 + 0.4 * pop, child: widget.child),
          ],
        );
      },
    );
  }
}
