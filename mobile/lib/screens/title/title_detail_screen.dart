import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/diary_entry.dart';
import '../../models/episode.dart';
import '../../models/media_detail.dart';
import '../../models/media_item.dart';
import '../../models/watch_provider.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../services/log_theme_service.dart';
import '../../services/premium_service.dart';
import '../../services/spoiler_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/poster_palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/add_to_list_sheet.dart';
import '../../widgets/bezier_timeline.dart';
import '../../widgets/heart_burst.dart';
import '../../widgets/heart_rating.dart';
import '../../widgets/poster_lightbox.dart';
import '../../widgets/region_picker_sheet.dart';
import '../../widgets/recommend_sheet.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/reviews_sheet.dart';
import '../../widgets/log_ritual.dart';
import '../../widgets/season_tracker.dart';
import '../../widgets/shrink_to_fit_text.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/source_video_link.dart';
import '../../widgets/spoiler_veil.dart';
import '../../widgets/title_share.dart';
import '../add_entry/watching_choice_screen.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart';
import '../../widgets/premium_upsell_sheet.dart';
import '../person/person_detail_screen.dart';
import 'full_cast_screen.dart';
import '../../services/app_translations.dart';
import '../../theme/notebook_paper.dart';
import '../../widgets/saved_celebration.dart';
import '../../theme/clay_kit.dart';

class TitleDetailScreen extends StatefulWidget {
  final String mediaId;
  final String source;
  final String mediaType;
  final String seedTitle;
  final String? seedPosterUrl;
  final MediaItem? seedItem;
  // The Hero tag the poster this screen was opened from is already flying
  // under (see posterHeroTag in widgets/poster_lightbox.dart). Home builds
  // one per tapped card — not just per title — since the same title can
  // legitimately sit in two shelves at once (continue watching *and* a
  // collection, say), and two simultaneous Heroes sharing one tag is a
  // hard Flutter error. Callers that don't have a specific card flying in
  // (search results, "similar titles", deep links, ...) leave this null
  // and the header falls back to the plain item-id tag it always used.
  final String? heroTag;

  const TitleDetailScreen({
    super.key,
    required this.mediaId,
    required this.source,
    required this.mediaType,
    required this.seedTitle,
    this.seedPosterUrl,
    this.seedItem,
    this.heroTag,
  });

  @override
  State<TitleDetailScreen> createState() => _TitleDetailScreenState();
}

class _TitleDetailScreenState extends State<TitleDetailScreen> {
  // How short the pinned banner is allowed to get once scrolled all the
  // way down — see the AnimatedBuilder in build() that drives its
  // height directly off _scrollController.
  static const double _collapsedBannerHeight = 190;

  late MediaItem _item;
  late Future<List<DiaryEntry>> _historyFuture;
  MediaRatings? _ratings;
  List<MediaItem> _similar = [];
  List<TitleTrailer> _trailers = [];
  bool _addingToPlan = false;
  bool _addedToPlan = false;
  bool _suggesting = false;
  bool _justSuggested = false;
  String? _partnerUsername; // null while unlinked — the suggest strip just stays hidden
  List<WatchProvider> _watchProviders = [];
  bool _watchLoading = false;
  // False until the very first watch-providers fetch resolves (success or
  // failure) for an applicable title. Treated the same as _watchLoading by
  // _WhereToWatchSection so the "nothing streaming here" empty state can't
  // flash for a frame before the real request has even gone out — see
  // _loadWatchProviders.
  bool _watchChecked = false;
  String? _tmdbAttribution;
  bool _isFavorite = false;
  bool _favoriteBusy = false;
  final ScrollController _scrollController = ScrollController();
  // Tracks how far past the top the list has been pulled — feeds the
  // banner's zoom-on-pull, same pattern as _StoriesBanner on Profile
  // (see that screen's _pullExtent). 0 at rest; positive only during an
  // actual overscroll drag.
  final ValueNotifier<double> _pullExtent = ValueNotifier<double>(0);

  // Soft background wash pulled from the poster/backdrop — see
  // theme/poster_palette.dart. Null until it resolves (or if it fails),
  // in which case the screen just sits on the plain paper background it
  // always had; this is a mood touch, never something the rest of the
  // screen depends on.
  Color? _posterTint;
  String? _posterTintUrl;

  @override
  void initState() {
    super.initState();
    _item = widget.seedItem ?? _fallbackItem();
    _historyFuture =
        context.read<AppState>().diary.mediaHistory(widget.mediaId, widget.source);
    _loadDetail();
    _loadPartnerStatus();
    _loadFavoriteStatus();
    _loadPosterTint();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pullExtent.dispose();
    super.dispose();
  }

  /// Best-effort, same reasoning as _loadFavoriteStatus/_loadPartnerStatus
  /// — a failed or slow extraction just leaves the screen on its normal
  /// flat background rather than blocking or retrying aggressively.
  /// Called again once _loadDetail() resolves, since the seed poster
  /// (passed in from whatever list this screen was opened from) is
  /// sometimes a lower-res or different crop than the real backdrop the
  /// detail call comes back with; re-running against the same URL is a
  /// free in-memory cache hit via PosterPaletteService, so this only
  /// ever does real work when the image actually changed.
  Future<void> _loadPosterTint() async {
    final url = _item.backdropUrl ?? _item.posterUrl ?? widget.seedPosterUrl;
    if (url == null || url == _posterTintUrl) return;
    _posterTintUrl = url;
    final tint = await PosterPaletteService.extract(url);
    if (!mounted || _posterTintUrl != url) return; // a newer poster won since this started
    if (kDebugMode) {
      debugPrint('TitleDetailScreen: poster tint for ${_item.title.display} -> $tint');
    }
    setState(() => _posterTint = tint);
  }

  /// Best-effort, same reasoning as _loadPartnerStatus below — a failed
  /// lookup just leaves the heart unfilled rather than blocking the rest
  /// of the screen on it; the person can still tap it either way.
  Future<void> _loadFavoriteStatus() async {
    try {
      final isFavorite =
          await context.read<AppState>().profile.favoriteStatus(widget.mediaId, widget.source);
      if (!mounted) return;
      setState(() => _isFavorite = isFavorite);
    } catch (_) {
      // Leave it unfilled — nothing else on this screen depends on it.
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final next = !_isFavorite;
    // Free tier: 5 favorite films (see PremiumService) — only checked
    // when turning a favorite ON, so un-favoriting is never blocked.
    if (next && !context.read<PremiumService>().canAddFavorite) {
      showPremiumUpsellSheet(
        context,
        triggerSource: 'favorites_limit',
        icon: Icons.favorite_outline,
        title: 'favorites limit reached'.tr,
        message: 'the free tier holds up to 5 favorite films — premium removes the limit'.tr,
      );
      return;
    }
    setState(() {
      _isFavorite = next; // optimistic — this is a one-tap heart, not a form submit
      _favoriteBusy = true;
    });
    HapticFeedback.selectionClick();
    try {
      final confirmed = await context.read<AppState>().profile.toggleFavorite(_item, next);
      if (!mounted) return;
      setState(() {
        _isFavorite = confirmed;
        _favoriteBusy = false;
      });
      if (confirmed) {
        context.read<PremiumService>().noteFavoriteAdded();
      } else {
        context.read<PremiumService>().noteFavoriteRemoved();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFavorite = !next; // revert the optimistic flip
        _favoriteBusy = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't save that just now — try again".tr)));
    }
  }

  /// Whether there's someone to suggest this to at all — used only to
  /// decide if the suggest strip below the header shows up. A failed
  /// lookup just leaves it hidden rather than surfacing an error on a
  /// screen that isn't primarily about partner status.
  Future<void> _loadPartnerStatus() async {
    try {
      final status = await context.read<AppState>().partner.status();
      if (!mounted) return;
      setState(() => _partnerUsername = status.linked ? status.partnerUsername : null);
    } catch (_) {
      // Leave it hidden — nothing else on this screen depends on it.
    }
  }

  MediaItem _fallbackItem() => MediaItem(
        id: widget.mediaId,
        mediaType: widget.mediaType,
        externalIds: const ExternalIds(),
        title: LocalizedText(en: widget.seedTitle),
        description: const LocalizedText(),
        posterUrl: widget.seedPosterUrl,
        source: widget.source,
      );

  /// Pulls runtime/certification/status, ratings, and similar titles from
  /// GET /media/detail — for TMDB titles and IGDB games alike (games just
  /// get empty ratings/similar back). Returns null for an id the source
  /// couldn't resolve, in which case we fall back to a plain title search
  /// just to backfill a synopsis/genres (the backend has no "get by id"
  /// for that case; see mobile/README.md).
  Future<void> _loadDetail() async {
    try {
      final detail = await context.read<AppState>().media.detail(
            mediaId: widget.mediaId,
            mediaType: widget.mediaType,
            source: widget.source,
          );
      if (!mounted) return;
      if (detail != null) {
        setState(() {
          _item = detail.item;
          _ratings = detail.ratings;
          _similar = detail.similar;
          _trailers = detail.trailers;
          _tmdbAttribution = detail.tmdbAttribution;
        });
        _loadWatchProviders();
        _loadPosterTint();
        return;
      }
    } catch (_) {
      // fall through to the search-based backfill below
    }
    if (widget.seedItem == null) await _tryBackfill();
    _loadWatchProviders();
  }

  /// A movie/series/anime's streaming availability — quietly does nothing
  /// for games/books/manga, or a title with no matched tmdb_id (no
  /// tmdb_id). See backend/app/routers/watch.py for the full picture.
  Future<void> _loadWatchProviders() async {
    final tmdbId = _item.externalIds.tmdb;
    const supported = {'movie', 'series', 'anime'};
    if (!supported.contains(_item.mediaType)) return;
    if (tmdbId == null) {
      if (!mounted) return;
      setState(() => _watchChecked = true);
      return;
    }
    if (!mounted) return;
    setState(() => _watchLoading = true);
    try {
      final result = await context.read<AppState>().media.watchProviders(
            mediaId: _item.id,
            source: _item.source,
            mediaType: _item.mediaType,
            title: _item.title.display,
            tmdbId: tmdbId,
            country: _watchRegion(),
          );
      if (!mounted) return;
      setState(() {
        _watchProviders = result.providers;
        _watchLoading = false;
        _watchChecked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _watchLoading = false;
        _watchChecked = true;
      });
    }
  }

  /// The region "where to watch" resolves against: someone's own explicit
  /// pick (LocaleService.region — set via the region picker, see
  /// widgets/region_picker_sheet.dart) when they've made one, otherwise a
  /// best-effort guess from the device's own locale, falling back to "US"
  /// (TMDB's own default) rather than blocking the section on anything
  /// fancier. A manual pick matters because device locale often doesn't
  /// match where someone actually streams from — an en-US phone can still
  /// want Russia's Kinopoisk/ivi/Okko/Wink listings, say.
  String _watchRegion() {
    final manual = context.read<LocaleService>().region;
    if (manual != null) return manual;
    // Platform.localeName (dart:io) doesn't exist on Flutter Web at all
    // — it throws "Unsupported operation" the instant this runs there.
    // PlatformDispatcher's locale works identically everywhere (web,
    // mobile, desktop) and hands back a proper Locale instead of a raw
    // string to parse.
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    return locale.countryCode?.toUpperCase() ?? 'US';
  }

  /// Human label for whatever [_watchRegion] resolves to right now — "Russia"
  /// for a manual RU pick, or "your region (US)" for an auto-guessed one,
  /// so the where-to-watch header can say which catalog it's showing
  /// without the reader needing to know a country code.
  String _regionLabel() {
    final resolved = _watchRegion();
    final manual = context.read<LocaleService>().region;
    final match = kRegionOptions.firstWhere(
      (o) => o.code == resolved,
      orElse: () => RegionOption(resolved, resolved),
    );
    return manual != null ? match.label.tr : '${'your region'.tr} ($resolved)';
  }

  Future<void> _changeRegion() async {
    await showRegionPickerSheet(context);
    if (!mounted) return;
    _loadWatchProviders();
  }

  Future<void> _openProvider(WatchProvider provider) async {
    try {
      await launchUrl(Uri.parse(provider.outUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't open that link just now".tr)));
    }
  }

  Future<void> _tryBackfill() async {
    try {
      final results =
          await context.read<AppState>().media.search(widget.seedTitle);
      final match = results.firstWhere(
        (r) => r.id == widget.mediaId && r.source == widget.source,
        orElse: () => results.isNotEmpty ? results.first : _item,
      );
      if (mounted) setState(() => _item = match);
    } catch (_) {
      // Keep the minimal fallback — still fully usable for logging.
    }
  }

  Future<void> _refreshHistory() async {
    setState(() {
      _historyFuture =
          context.read<AppState>().diary.mediaHistory(widget.mediaId, widget.source);
    });
  }

  /// For a series/anime, the first not-yet-watched episode in order —
  /// what "log another evening" should default to instead of logging the
  /// title as a whole again. Returns null for movies/games/books, for a
  /// title with no episode catalog data, or once every episode is
  /// already watched (falls back to the old whole-title log in all
  /// those cases).
  Future<Episode?> _nextUnwatchedEpisode() async {
    if (_item.mediaType != 'series' && _item.mediaType != 'anime') return null;
    try {
      final app = context.read<AppState>();
      final results = await Future.wait([
        app.media.episodes(mediaId: widget.mediaId, source: widget.source),
        app.progress.series(mediaId: widget.mediaId, source: widget.source),
      ]);
      final seriesEpisodes = results[0] as SeriesEpisodes;
      final progress = results[1] as SeriesProgress;
      final all = [for (final s in seriesEpisodes.seasons) ...s.episodes]
        ..sort((a, b) =>
            a.season != b.season ? a.season - b.season : a.episode - b.episode);
      for (final e in all) {
        if (!progress.isWatched(e.season, e.episode)) return e;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// One-tap "plan to watch" — `/feed/react` with action "like", same call
  /// the Search screen's quick-add uses. Kept separate from "log another
  /// evening": this just queues the title, no rating/note/date needed.
  Future<void> _addToPlan() async {
    setState(() => _addingToPlan = true);
    try {
      await context.read<AppState>().feed.react(_item, 'like');
      if (!mounted) return;
      setState(() {
        _addingToPlan = false;
        _addedToPlan = true;
      });
      showSavedCelebration(
        context,
        kind: SavedKind.planned,
        title: _item.title.display,
        posterUrl: _item.posterUrl,
        mediaType: _item.mediaType,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingToPlan = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('couldn\'t add that just now — try again'.tr)),
      );
    }
  }

  /// The one-tap "suggest this for tonight" — sends a snapshot of this
  /// title straight to the linked partner (see backend/app/routers/
  /// partner.py). Only ever wired up while `_partnerUsername != null`, so
  /// the "no partner linked" case shouldn't normally happen here — the
  /// generic fallback below covers it anyway, just in case they unlinked
  /// in another tab while this screen was open.
  Future<void> _suggestForTonight() async {
    if (_suggesting || _justSuggested) return;
    setState(() => _suggesting = true);
    try {
      await context.read<AppState>().partner.suggest(_item);
      if (!mounted) return;
      setState(() {
        _suggesting = false;
        _justSuggested = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _justSuggested = false);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _suggesting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't send that just now — try again".tr)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same band height the backdrop banner always had — stretching on
    // a pull doesn't mean blowing the same image up over the whole
    // screen (that crops it into something unrecognizable); it keeps
    // the original crop, just taller for as long as the finger's down.
    const bandHeight = 260.0;

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  // The poster-derived wash (see theme/poster_palette.dart
                  // and _loadPosterTint above) — sits behind everything
                  // else in this Stack, so it's exactly what shows through
                  // once _PosterBanner's own ShaderMask dissolves it to
                  // transparent near the bottom of the band, instead of
                  // the flat paper background this screen always fell
                  // back to before. AnimatedContainer rather than a plain
                  // Container so the very first frame (before extraction
                  // resolves) and any later change both cross-fade rather
                  // than popping in.
                  Positioned.fill(
                    child: Container(
                      color: SeenlyPalette.background,
                    ),
                  ),
                  // Deliberately NOT a Sliver header (SliverAppBar or
                  // SliverPersistentHeader both went through revisions
                  // here that still weren't reliable about keeping the
                  // banner pinned to the top of the *screen*). This
                  // NotificationListener just tracks scroll for the
                  // pull-to-zoom below; the content itself scrolls in a
                  // plain SingleChildScrollView with a spacer reserving
                  // the banner's full-height space at its top — the
                  // banner is a separate fixed layer painted *after*
                  // (on top of) this whole scroll view (see the
                  // AnimatedBuilder right after it closes), so it can
                  // never be covered no matter how far the page scrolls,
                  // and its height is driven directly off the same
                  // ScrollController for a 1:1 shrink as the page moves.
                  NotificationListener<ScrollNotification>(
                    // Same pull-to-zoom pattern as Profile's cover
                    // banner (see _StoriesBanner / _pullExtent there):
                    // tracks how far past the top the list has actually
                    // been dragged and feeds it to the banner as a zoom
                    // amount.
                    onNotification: (notification) {
                      final pixels = notification.metrics.pixels;
                      final pull = pixels < 0 ? -pixels : 0.0;
                      if (_pullExtent.value != pull) _pullExtent.value = pull;
                      return false;
                    },
                    child: SingleChildScrollView(
                    controller: _scrollController,
                    // Android's default scroll physics clamps at the
                    // top — it never reports a negative offset on
                    // overscroll, it just shows an edge glow, so a
                    // pull down there has nothing to react to.
                    // [BouncingScrollPhysics] restores the rubber-band
                    // overscroll on every platform, which is what
                    // feeds the pull-to-zoom above.
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reserves the banner's full-height space at the
                        // top of the actual scrolling content — the
                        // banner itself isn't drawn here at all; it's a
                        // separate fixed layer below (see the
                        // AnimatedBuilder right after this
                        // SingleChildScrollView in the Stack), painted
                        // on top of this content so scrolling can never
                        // cover it.
                        const SizedBox(height: bandHeight),
                        _ContentSheet(
                          tint: _posterTint,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ScrollReveal(
                                riseBy: 14,
                                child: _HeaderTitleBlock(
                                  item: _item,
                                  ratings: _ratings,
                                  heroTag: widget.heroTag,
                                ),
                              ),
                              // No hardcoded background color here anymore —
                              // this used to paint flat SeenlyPalette.background
                              // over everything below the header, which is
                              // exactly what was cutting the poster tint off
                              // right after the title block instead of letting
                              // it carry through to the rest of the card (see
                              // _ContentSheet, which now owns the tint for the
                              // sheet's *entire* height, not just a short band).
                              Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                            if (_partnerUsername != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                                child: _SuggestTonightStrip(
                                  partnerUsername: _partnerUsername!,
                                  busy: _suggesting,
                                  sent: _justSuggested,
                                  onTap: _suggestForTonight,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                        if (isSourceVideo(widget.source)) ...[
                          WatchOnSourceButton(source: widget.source, mediaId: widget.mediaId),
                          const SizedBox(height: 20),
                        ],
                        if (_item.genres.isNotEmpty) ...[
                          GenreTagsFlow(genres: _item.genres),
                          const SizedBox(height: 18),
                        ],
                        if (_ExtraFactsSection.hasContent(_item)) ...[
                          _ExtraFactsSection(item: _item),
                          const SizedBox(height: 18),
                        ],
                        if (_item.description.display != '—') ...[
                          SpoilerVeil(
                            active: context.watch<SpoilerPrefsService>().blurDescriptions,
                            label: 'the synopsis might give things away'.tr,
                            child: Text(_item.description.display, style: SeenlyText.bodyText),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_item.cast.isNotEmpty || _item.director != null) ...[
                          ScrollReveal(
                            riseBy: 12,
                            child: _CastSection(
                              cast: _item.cast,
                              director: _item.director,
                              directorId: _item.directorId,
                              attribution: _tmdbAttribution,
                              titleName: _item.title.display,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        ScrollReveal(
                          riseBy: 12,
                          child: _WhereToWatchSection(
                            providers: _watchProviders,
                            loading: _watchLoading || !_watchChecked,
                            onTapProvider: _openProvider,
                            regionLabel: _regionLabel(),
                            onChangeRegion: _changeRegion,
                            applicable: const {'movie', 'series', 'anime'}.contains(_item.mediaType),
                          ),
                        ),
                        if (_ratings != null && !_ratings!.isEmpty) ...[
                          ScrollReveal(
                            riseBy: 12,
                            child: _RatingsRow(
                              ratings: _ratings!,
                              onTapReviews: _item.externalIds.tmdb != null
                                  ? () => showReviewsSheet(
                                        context,
                                        mediaType: _item.mediaType,
                                        tmdbId: _item.externalIds.tmdb!,
                                        title: _item.title.display,
                                      )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_trailers.isNotEmpty) ...[
                          ScrollReveal(
                            riseBy: 12,
                            child: _TrailersSection(trailers: _trailers),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_similar.isNotEmpty) ...[
                          ScrollReveal(
                            riseBy: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('if you liked this'.tr,
                                    style: SeenlyText.serif(
                                        italic: true, size: 14, color: SeenlyPalette.accent)),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 150,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _similar.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                                    itemBuilder: (context, i) {
                                      final s = _similar[i];
                                      return SizedBox(
                                        width: 92,
                                        child: ThemedPosterTile(
                                          title: s.title.display,
                                          posterUrl: s.posterUrl,
                                          mediaType: s.mediaType,
                                          fallbackColor: SeenlyPalette.gridColorFor(i),
                                          onTap: () => Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                              builder: (_) => TitleDetailScreen(
                                                mediaId: s.id,
                                                source: s.source,
                                                mediaType: s.mediaType,
                                                seedTitle: s.title.display,
                                                seedPosterUrl: s.posterUrl,
                                                seedItem: s,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_item.mediaType == 'series' || _item.mediaType == 'anime') ...[
                          ScrollReveal(
                            riseBy: 12,
                            child: SeasonTracker(mediaId: widget.mediaId, source: widget.source, item: _item),
                          ),
                          const SizedBox(height: 20),
                        ],
                        Container(
                          padding: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            border: Border(
                                top: BorderSide(
                                    color: SeenlyPalette.dashedBorder, width: 1)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ScrollReveal(
                          riseBy: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('your evenings with this title'.tr,
                                  style: SeenlyText.serif(
                                      italic: true, size: 14, color: SeenlyPalette.accent)),
                              const SizedBox(height: 14),
                              FutureBuilder<List<DiaryEntry>>(
                          future: _historyFuture,
                          builder: (context, snapshot) {
                            Widget child;
                            if (!snapshot.hasData && !snapshot.hasError) {
                              child = Column(
                                key: const ValueKey('history-loading'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      ShimmerBlock(
                                          width: 90, height: 18, borderRadius: BorderRadius.circular(9)),
                                      ShimmerBlock(
                                          width: 100, height: 12, borderRadius: BorderRadius.circular(6)),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  ShimmerBlock(height: 46, borderRadius: BorderRadius.circular(14)),
                                ],
                              );
                            } else if (snapshot.hasError) {
                              child = Text(
                                'couldn\'t load your history for this title'.tr,
                                key: const ValueKey('history-error'),
                                style: SeenlyText.serif(italic: true, color: SeenlyPalette.inkMuted),
                              );
                            } else {
                              final history = snapshot.data!;
                              if (history.isEmpty) {
                                child = Text(
                                  'not logged yet — save an evening below'.tr,
                                  key: const ValueKey('history-empty'),
                                  style: SeenlyText.emptyState(),
                                );
                              } else {
                                final latestRated = history.reversed
                                    .cast<DiaryEntry?>()
                                    .firstWhere((e) => e?.rating != null, orElse: () => null);
                                child = Column(
                                  key: const ValueKey('history-content'),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        if (latestRated != null)
                                          HeartRating(value: latestRated.rating!),
                                        Text(
                                          history.length == 1
                                              ? 'watched once'
                                              : 'watched ${history.length} times',
                                          style: SeenlyText.metaLabel,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    RewatchTimeline(entries: history, onEntryChanged: _refreshHistory),
                                  ],
                                );
                              }
                            }
                            // Same soft cross-fade every other loading→content
                            // handoff in the app uses, rather than the
                            // spinner just vanishing and the timeline
                            // popping in underneath it.
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 320),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeIn,
                              child: child,
                            );
                          },
                              ),
                            ],
                          ),
                        ),
                                ],
                              ),
                          ),
                              ],
                        ),
                      ],
                    ),
                        ),
                      ],
                    ),
                    ),
                  ),
                  // The banner itself — a separate fixed layer, painted
                  // *after* (so: on top of) the scrolling content above,
                  // which is what actually keeps it pinned to the top of
                  // the screen rather than scrolling away with the page.
                  // Its height and position stay fixed at bandHeight —
                  // it does NOT shrink or move as the page scrolls, so it
                  // reads as a backdrop sitting still at the top of the
                  // *screen*, not a collapsing header riding along with
                  // the *page*. Only its opacity responds to scroll (see
                  // fadeDistance below): fully opaque at rest, easing to
                  // fully transparent as the content scrolls up and
                  // reveals it was there the whole time.
                  AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, child) {
                      final offset =
                          _scrollController.hasClients ? _scrollController.offset : 0.0;
                      // Fully opaque at rest (offset 0); eases toward
                      // transparent as the page scrolls, over this many
                      // pixels of scroll.
                      const fadeDistance = 450.0;
                      final opacity = (1.0 - offset / fadeDistance).clamp(0.0, 1.0);
                      return Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: bandHeight,
                        child: Opacity(opacity: opacity, child: child!),
                      );
                    },
                    child: ValueListenableBuilder<double>(
                      valueListenable: _pullExtent,
                      builder: (context, pull, child) {
                        final scale = 1.0 + (pull / 320).clamp(0.0, 0.15);
                        return ClipRect(
                          child: Transform.scale(scale: scale, child: child),
                        );
                      },
                      child: _PosterBanner(item: _item),
                    ),
                  ),
                  // Pinned above the backdrop and the scrolling sheet
                  // — navigation and actions live in this fixed layer
                  // too, so they never scroll away with the page.
                  Positioned(
                    top: 12,
                    left: 16,
                    child: _RoundIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 16,
                    child: Row(
                      children: [
                        if ((_item.trailerYoutubeId ?? '').isNotEmpty) ...[
                          _RoundIconButton(
                            icon: Icons.play_arrow_rounded,
                            onTap: () => _openTrailer(context, _item.trailerYoutubeId!),
                          ),
                          const SizedBox(width: 8),
                        ],
                        HeartBurst(
                          isFavorite: _isFavorite,
                          child: _RoundIconButton(
                            icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                            iconColor: _isFavorite ? SeenlyPalette.pink : null,
                            onTap: _toggleFavorite,
                            loading: _favoriteBusy,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RoundIconButton(
                          icon: Icons.recommend_outlined,
                          onTap: () => RecommendSheet.show(
                            context,
                            source: _item.source,
                            mediaId: _item.id,
                            title: _item.title.display,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RoundIconButton(
                          icon: Icons.playlist_add,
                          onTap: () => showAddToListSheet(context, _item),
                        ),
                        const SizedBox(width: 8),
                        _RoundIconButton(
                          icon: Icons.ios_share_rounded,
                          onTap: () => shareTitle(
                            context,
                            item: _item,
                            fallbackColor: SeenlyPalette.mediaColor(_item.mediaType),
                            ratings: _ratings,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Same poster tint as the card above, so the bottom action
            // bar reads as a continuation of that surface instead of a
            // visible seam back to flat paper — it used to have no
            // background of its own, so it just fell through to
            // Scaffold.backgroundColor and cut the color off dead right
            // where the card ends.
            Container(
              color: SeenlyPalette.background,
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
                  child: Row(
                    children: [
                      _PlanToWatchButton(
                        added: _addedToPlan,
                        loading: _addingToPlan,
                        onTap: _addToPlan,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LogSubmitButton(
                          label: switch (context.watch<LogThemeService>().theme) {
                            LogTheme.coach => 'board another evening'.tr,
                            LogTheme.ticket => 'log another evening'.tr,
                            LogTheme.garden => 'plant another evening'.tr,
                            LogTheme.shuttle => 'launch another evening'.tr,
                          },
                          onTap: () async {
                            final next = await _nextUnwatchedEpisode();
                            if (!mounted) return;
                            final saved = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                fullscreenDialog: true,
                                builder: (_) => WatchingChoiceScreen(
                                  item: _item,
                                  season: next?.season,
                                  episode: next?.episode,
                                ),
                              ),
                            );
                            if (saved == true) _refreshHistory();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
  }
}

/// Opens a trailer's YouTube page/app externally. Kept as a free function
/// (rather than on [_TitleDetailScreenState]) because the trailer button
/// lives on [_Header], a stateless widget one level further down — it only
/// needs the tapped [BuildContext] to show a snackbar on failure, not any
/// screen state.
Future<void> _openTrailer(BuildContext context, String videoId) async {
  try {
    final opened = await launchUrl(
      Uri.parse('https://www.youtube.com/watch?v=$videoId'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't open that link just now".tr)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't open that link just now".tr)));
    }
  }
}

/// The horizontal backdrop image itself — the [FlexibleSpaceBar]
/// background of the fixed, always-on-top banner layer in
/// [_TitleDetailScreenState.build]. It genuinely fades to transparent
/// toward the bottom (not just tinted with an opaque color band), via
/// a [ShaderMask], so it reads as the poster art itself dissolving
/// into whatever scrolls up underneath it — the same "melts into the
/// page" look as the picture-behind-headline layouts this screen is
/// modeled on — rather than a color patch pasted over a hard-edged
/// photo.
///
/// The dissolve is a single continuous ramp across the banner's whole
/// height (top fully opaque, bottom fully transparent) — see
/// that field's own doc comment for the ramp itself.
///
/// The fade has to live here, inside the image layer, rather than as
/// an overlay on the scrolling content below (which is how it used to
/// work): Flutter always paints a pinned sliver header *above*
/// whatever scrolls underneath it, so a transparent gradient on the
/// content side would never actually be visible — the pinned header
/// would just hide it regardless of its alpha. Keeping the fade on
/// the layer that's guaranteed to be on top is what makes it show up
/// at all.
class _PosterBanner extends StatelessWidget {
  final MediaItem item;
  const _PosterBanner({required this.item});

  @override
  Widget build(BuildContext context) {
    // Only the bottom sliver of the banner eases into transparency —
    // most of the poster stays fully visible; this just softens the
    // hard edge where the banner hands off to the card below instead
    // of dissolving the poster itself away.
    const fadeStart = 0.82;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _maskColors,
        stops: [
          0.0,
          ..._fadeStops.map((t) => fadeStart + t * (1.0 - fadeStart)),
        ],
      ).createShader(rect),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.backdropUrl != null || item.posterUrl != null)
            _ResilientPoster(
              primaryUrl: item.backdropUrl ?? item.posterUrl,
              fallbackUrl: item.backdropUrl ?? item.posterUrlFallback,
              placeholderColor: SeenlyPalette.mediaColor(item.mediaType),
            )
          else
            Container(color: SeenlyPalette.mediaColor(item.mediaType)),
          // A short vignette just at the very top so the
          // back/heart/list icons stay legible over bright art.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x40000000), Color(0x00000000)],
                stops: [0.0, 0.2],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Alpha-only mask colors (white = keep, transparent = dissolve).
  static const List<Color> _maskColors = [
    Colors.white,
    Colors.white,
    Color(0xF8FFFFFF),
    Color(0xE5FFFFFF),
    Color(0xC8FFFFFF),
    Color(0xA5FFFFFF),
    Color(0x80FFFFFF),
    Color(0x5AFFFFFF),
    Color(0x37FFFFFF),
    Color(0x1BFFFFFF),
    Color(0x07FFFFFF),
    Color(0x00FFFFFF),
  ];
  static const List<double> _fadeStops = [
    0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0,
  ];
}

/// The rounded sheet that carries the actual page content — clipped
/// to a rounded top so it reads as a card sitting just below the
/// backdrop. No fade of its own anymore; [_PosterBanner] above now
/// owns the entire hand-off (see its doc comment for why). A soft
/// shadow rides just above the rounded corners so the card reads as
/// something gently lifted off the backdrop — a deliberate seam —
/// rather than the photo simply getting cut off by a flat rectangle.
class _ContentSheet extends StatelessWidget {
  final Widget child;
  // Same poster-derived tint the Scaffold-level wash behind the banner
  // uses (see _TitleDetailScreenState._posterTint) — now the sheet's
  // *entire* fill color, not just a short fading band at the top. It
  // used to be a 260px gradient down to transparent, on the idea that
  // the tint should hand off to flat paper before body content sat
  // under it — but that's what made the color read as "a highlight
  // near the title" instead of "this card's tone", and it visibly died
  // out a few lines into the page. The tint is already softened enough
  // (see poster_palette.dart's _soften) to sit safely under body text
  // for the whole card, so there's no longer a reason to fade it out.
  final Color? tint;
  const _ContentSheet({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        // Two layered shadows instead of one — a soft, wide, faint
        // wash plus a slightly tighter one right at the seam — so the
        // falloff itself feels graduated rather than a single flat
        // band of shadow with a visible inner/outer edge.
        boxShadow: [
          BoxShadow(
            color: SeenlyPalette.ink.withOpacity(0.05),
            blurRadius: 40,
            offset: const Offset(0, -14),
          ),
          BoxShadow(
            color: SeenlyPalette.ink.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: SeenlyPalette.background,
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}


/// The vertical poster + title row. Lives at the very top of
/// [_ContentSheet]'s content, right where the backdrop's own fade (see
/// [_PosterBanner]) settles into the sheet's background color.
class _HeaderTitleBlock extends StatelessWidget {
  final MediaItem item;
  final MediaRatings? ratings;
  // See TitleDetailScreen.heroTag — whatever tag the poster arrived
  // under (or the plain item-id tag, opened from somewhere that didn't
  // set one) is what both this tile and the lightbox it opens must use,
  // so the whole poster-lightbox-poster chain reads as one Hero.
  final String? heroTag;
  const _HeaderTitleBlock({required this.item, this.ratings, this.heroTag});

  @override
  Widget build(BuildContext context) {
    final tag = heroTag ?? posterHeroTag(item.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4, width: double.infinity),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 24, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // The vertical poster, its own small tile riding up over
              // the pinned backdrop band above. Tapping it opens the
              // same artwork full-screen (poster_lightbox.dart) — the
              // Hero tag below is what lets it visibly grow into place
              // instead of the two screens just swapping.
              GestureDetector(
                onTap: () => showPosterLightbox(context, item: item, ratings: ratings, heroTag: tag),
                child: Hero(
                  tag: tag,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: ClayBoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: SeenlyPalette.softShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 124,
                          height: 186,
                          decoration: BoxDecoration(
                            border: Border.all(color: SeenlyPalette.background, width: 2),
                          ),
                          child: item.posterUrl != null
                              ? _ResilientPoster(
                                  primaryUrl: item.posterUrl,
                                  fallbackUrl: item.posterUrlFallback,
                                  placeholderColor: SeenlyPalette.mediaColor(item.mediaType),
                                )
                              : Container(color: SeenlyPalette.mediaColor(item.mediaType)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShrinkToFitText(
                        item.title.display,
                        maxLines: 3,
                        minFontSize: 15,
                        style: SeenlyText.serif(
                            size: 22, weight: FontWeight.w700, color: SeenlyPalette.ink),
                      ),
                      // "By <author>" for books, "Published by <publisher>"
                      // for manga — see backend app/adapters/google_books.py
                      // / app/adapters/shikimori.py. Left out for
                      // movies/series/anime/games, which either don't set
                      // this field or (games) have no natural one-line
                      // attribution to show here.
                      if (item.tagline != null && item.tagline!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.tagline!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(
                              size: 13, italic: true, color: SeenlyPalette.inkFaint),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (item.year != null)
                        MetaLine(icon: Icons.calendar_today_outlined, label: '${item.year}'),
                      // Books' runtimeMinutes is a reading-time estimate used
                      // for Wrapped hour totals, not a real duration — "196
                      // min" reads as nonsense next to a book, so it's left
                      // out here.
                      if (item.runtimeMinutes != null && item.mediaType != 'book')
                        MetaLine(icon: Icons.schedule_outlined, label: '${item.runtimeMinutes} ${'min'.tr}'),
                      // certification doubles as an age rating (ESRB/PEGI,
                      // games) or a page-count badge (books/manga) — see
                      // backend app/schemas.py::MediaItem.certification.
                      if (item.certification != null && item.certification!.trim().isNotEmpty)
                        MetaLine(
                          icon: item.mediaType == 'game'
                              ? Icons.shield_outlined
                              : Icons.menu_book_outlined,
                          label: item.certification!,
                        ),
                      if (item.rating != null)
                        MetaLine(
                          icon: Icons.star_rounded,
                          label: item.rating!.toStringAsFixed(1),
                          iconColor: SeenlyPalette.accent,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Everything on MediaItem that's specific to games/books/manga and
/// doesn't fit the header's compact meta line (year/runtime/rating) —
/// developer/publisher/platforms/game modes for games, publisher/isbn
/// for books, status/volumes/chapters for manga. Each row only shows up
/// when its source actually set the field (see backend
/// app/schemas.py::MediaItem's own "empty rather than fabricated"
/// convention), so a game with no age-rated platforms data, say, just
/// shows fewer rows instead of a placeholder.
class _ExtraFactsSection extends StatelessWidget {
  final MediaItem item;
  const _ExtraFactsSection({required this.item});

  static bool hasContent(MediaItem item) {
    return item.developer != null ||
        item.publisher != null ||
        item.platforms.isNotEmpty ||
        item.gameModes.isNotEmpty ||
        item.status != null ||
        item.volumes != null ||
        item.chapters != null ||
        item.isbn != null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    if (item.developer != null) {
      rows.add(_FactRow(label: 'Developer'.tr, value: item.developer!));
    }
    // Books already show the publisher via the tagline ("Published by
    // ..." isn't set there — see _normalize in google_books.py, which
    // uses tagline for authors instead) so a game/manga publisher still
    // gets its own row here; a book's publisher shows here too since its
    // tagline is authors, not publisher.
    if (item.publisher != null) {
      rows.add(_FactRow(label: 'Publisher'.tr, value: item.publisher!));
    }
    if (item.mediaType == 'manga' && item.status != null) {
      rows.add(_FactRow(label: 'Status'.tr, value: item.status!));
    }
    if (item.mediaType == 'manga' && (item.volumes != null || item.chapters != null)) {
      final parts = <String>[
        if (item.volumes != null) '${item.volumes} ${'vol.'.tr}',
        if (item.chapters != null) '${item.chapters} ${'ch.'.tr}',
      ];
      rows.add(_FactRow(label: 'Length'.tr, value: parts.join(' · ')));
    }
    if (item.mediaType == 'book' && item.isbn != null) {
      rows.add(_FactRow(label: 'ISBN'.tr, value: item.isbn!));
    }
    if (item.platforms.isNotEmpty) {
      rows.add(_FactRow(label: 'Platforms'.tr, value: item.platforms.join(', ')));
    }
    if (item.gameModes.isNotEmpty) {
      rows.add(_FactRow(label: 'Modes'.tr, value: item.gameModes.join(', ')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

class _FactRow extends StatelessWidget {
  final String label;
  final String value;
  const _FactRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: SeenlyText.serif(
                  size: 13, weight: FontWeight.w600, color: SeenlyPalette.inkFaint),
            ),
            TextSpan(
              text: value,
              style: SeenlyText.serif(size: 13, color: SeenlyPalette.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// TMDB's own community rating, plus the merged TMDB+Trakt review count.
/// This is the critic/community layer — distinct from the hearts in
/// "your evenings with this title" below, which are the user's own
/// reaction.
class _RatingsRow extends StatelessWidget {
  final MediaRatings ratings;
  final VoidCallback? onTapReviews;
  const _RatingsRow({required this.ratings, this.onTapReviews});

  @override
  Widget build(BuildContext context) {
    final stats = <Widget>[
      if (ratings.tmdbRating != null)
        _RatingStat(
          label: 'tmdb',
          value: ratings.tmdbRating!.toStringAsFixed(1),
          votes: ratings.tmdbVotes,
          showStar: true,
        ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SeenlyPalette.border),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0)
                    VerticalDivider(width: 1, thickness: 1, color: SeenlyPalette.border,
                        indent: 2, endIndent: 2),
                  Expanded(child: stats[i]),
                ],
              ],
            ),
          ),
          if (ratings.reviewsCount != null) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: SeenlyPalette.border),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onTapReviews,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 11, color: SeenlyPalette.inkFaint),
                    const SizedBox(width: 6),
                    Text(
                      nCount('nReviews', ratings.reviewsCount!),
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                    ),
                    if (onTapReviews != null) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 12, color: SeenlyPalette.inkFaint),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RatingStat extends StatelessWidget {
  final String label;
  final String value;
  final int? votes;
  final bool showStar;
  const _RatingStat({
    required this.label,
    required this.value,
    this.votes,
    this.showStar = false,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = double.tryParse(value);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HandDrawnCircle(
          child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showStar) ...[
              Icon(Icons.star_rounded, size: 15, color: SeenlyPalette.mustard),
              const SizedBox(width: 3),
            ],
            parsed != null
                ? CountUpNumber(
                    value: parsed,
                    style: SeenlyText.serif(size: 18, weight: FontWeight.w600),
                  )
                : Text(value, style: SeenlyText.serif(size: 18, weight: FontWeight.w600)),
          ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint),
        ),
        if (votes != null) ...[
          const SizedBox(height: 2),
          Text(
            _formatVotes(votes!),
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint),
          ),
        ],
      ],
    );
  }

  String _formatVotes(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}m votes';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k votes';
    return '$v votes';
  }
}

/// The single, legible way to suggest a title for tonight — replaces the
/// unlabeled heart that used to sit on the header photo (too easy to read
/// as a favorite/rating heart, which this app already uses elsewhere for
/// something else entirely). Only ever shown once a partner's linked, and
/// says exactly who it's going to. Uses the app's existing "not yet"
/// dashed-outline language (see [DashedBox]) while idle, and fills in
/// solid once it's actually sent — the same visual switch the bookmark
/// button and co-viewing's "watched" button use for "done".
class _SuggestTonightStrip extends StatelessWidget {
  final String partnerUsername;
  final bool busy;
  final bool sent;
  final VoidCallback onTap;

  const _SuggestTonightStrip({
    required this.partnerUsername,
    required this.busy,
    required this.sent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: sent ? SeenlyPalette.accent : SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            sent ? Icons.check_rounded : Icons.nights_stay_outlined,
            size: 15,
            color: sent ? SeenlyPalette.accentOnAccent : SeenlyPalette.accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              sent ? 'sent — $partnerUsername will see it' : 'suggest for tonight — $partnerUsername',
              style: SeenlyText.serif(
                italic: true,
                size: 12,
                color: sent ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted,
              ),
            ),
          ),
          if (busy)
            SizedBox(
              width: 13,
              height: 13,
              child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
            )
          else if (!sent)
            Icon(Icons.chevron_right, size: 14, color: SeenlyPalette.inkFaint),
        ],
      ),
    );

    return GestureDetector(
      onTap: (busy || sent) ? null : onTap,
      child: sent ? row : DashedBox(radius: 12, child: row),
    );
  }
}

/// Top cast + director, from TMDB (backend app/adapters/tmdb.py::
/// full_detail) — a title without a resolved tmdb id never gets this
/// populated at all. Renders nothing when there's neither (a title TMDB
/// has nothing for, or a game/book). Same "logos/photos are the whole
/// visual, no chrome" feel as _WhereToWatchSection below, and the same
/// attribution line — required wherever TMDB data is shown. The director
/// name and every cast tile are tappable (see person_detail_screen.dart)
/// when TMDB gave a person id for them — a row cached from before that
/// field existed just isn't tappable until the next re-fetch.
class _CastSection extends StatelessWidget {
  final List<CastMember> cast;
  final String? director;
  final String? directorId;
  final String? attribution;
  final String titleName;

  const _CastSection({
    required this.cast,
    this.director,
    this.directorId,
    this.attribution,
    required this.titleName,
  });

  void _openPerson(BuildContext context, String personId, String name, String? photoUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonDetailScreen(personId: personId, seedName: name, seedPhotoUrl: photoUrl),
      ),
    );
  }

  void _openFullCast(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullCastScreen(titleName: titleName, cast: cast),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty && director == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('cast'.tr,
                style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accent)),
            const Spacer(),
            if (cast.length > 5)
              GestureDetector(
                onTap: () => _openFullCast(context),
                child: Text('see all'.tr,
                    style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (director != null) ...[
          GestureDetector(
            onTap: directorId != null ? () => _openPerson(context, directorId!, director!, null) : null,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${'directed by'.tr}  ', style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
                  TextSpan(
                    text: director,
                    style: directorId != null
                        ? SeenlyText.serif(size: 13).copyWith(decoration: TextDecoration.underline)
                        : SeenlyText.serif(size: 13),
                  ),
                ],
              ),
            ),
          ),
          if (cast.isNotEmpty) const SizedBox(height: 12),
        ],
        if (cast.isNotEmpty)
          SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => HorizontalReveal(
                delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
                child: _CastMemberTile(member: cast[i]),
              ),
            ),
          ),
        if (attribution != null) ...[
          const SizedBox(height: 8),
          Text(attribution!, style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
        ],
      ],
    );
  }
}

class _CastMemberTile extends StatelessWidget {
  final CastMember member;
  const _CastMemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: member.personId != null
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PersonDetailScreen(
                    personId: member.personId!,
                    seedName: member.name,
                    seedPhotoUrl: member.photoUrl,
                  ),
                ),
              )
          : null,
      scaleTo: 0.94,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: (member.photoUrl != null)
                    ? FadeInNetworkImage(
                        url: member.photoUrl!,
                        fit: BoxFit.cover,
                        placeholder: Container(color: SeenlyPalette.accent),
                      )
                    : Container(color: SeenlyPalette.accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(member.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 11)),
            if ((member.character?.display.isNotEmpty ?? false) && member.character!.display != '—')
              Text(member.character!.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
          ],
        ),
      ),
    );
  }
}

/// This title's own "trailers" shelf — official trailers, teasers, and
/// clips from TMDB (see app/adapters/tmdb.py::TmdbAdapter._extract_trailers),
/// sitting between the ratings row and "if you liked this". Each card is a
/// YouTube-hosted still with a soft veil and the video's own name, the same
/// cozy-card language [ThemedPosterTile]/[TrailerPreviewCard] already use
/// elsewhere — tapping one opens the real YouTube app/tab, same as the
/// header's play button and the Home trailer feed.
class _TrailersSection extends StatelessWidget {
  final List<TitleTrailer> trailers;
  const _TrailersSection({required this.trailers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('trailers'.tr,
            style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accent)),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: trailers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => HorizontalReveal(
              delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
              child: _TrailerTile(trailer: trailers[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrailerTile extends StatelessWidget {
  final TitleTrailer trailer;
  const _TrailerTile({required this.trailer});

  // A true 16:9 frame, not the near-square shape used elsewhere for
  // poster tiles — this matters beyond just "looks like a trailer card".
  // YouTube's hqdefault/mqdefault stills are rendered on a 4:3 canvas, so
  // a modern 16:9 trailer comes back letterboxed with black bars baked
  // into the image itself, top and bottom. A near-square target crops
  // left/right on cover-fit and leaves those bars sitting right in the
  // middle of the card (the "границы" in the screenshot). Cropping into a
  // matching 16:9 frame instead makes BoxFit.cover crop top/bottom first,
  // which — for a centered letterbox — trims off exactly the bars rather
  // than the sides of the actual shot, so the card reads edge-to-edge
  // like a real cover with no visible borders.
  static const double _width = 168;
  static const double _aspectRatio = 16 / 9;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => _openTrailer(context, trailer.videoId),
      scaleTo: 0.96,
      child: SizedBox(
        width: _width,
        child: DecoratedBox(
          decoration: ClayBoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: SeenlyPalette.softShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: _aspectRatio,
              child: Container(
                color: SeenlyPalette.cork,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (trailer.thumbnailUrl != null)
                      FadeInNetworkImage(
                        url: trailer.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: Container(color: SeenlyPalette.cork),
                      ),
                    // Same soft warm veil as TrailerPreviewCard — keeps
                    // the play chip and caption readable over any still.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.35, 1],
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.65),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: SeenlyPalette.paper.withOpacity(0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 8),
                          ],
                        ),
                        child: Icon(Icons.play_arrow_rounded,
                            size: 17, color: SeenlyPalette.accent),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: Text(
                        trailer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SeenlyText.serif(italic: true, size: 11.5, color: SeenlyPalette.paperOnDark),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The whole "where to watch" section. Logos are the whole visual: no
/// bordered pills, no button chrome, just brand marks in a soft row,
/// matching the same quiet, uncluttered feel as the rest of this screen.
/// Tapping one opens the app's own /media/watch-out redirect (see
/// backend/app/routers/watch.py) in the device's own browser.
///
/// Used to hide itself completely whenever there was nothing to show.
/// Now that the region is a visible, changeable choice (see
/// widgets/region_picker_sheet.dart) rather than a silent device-locale
/// guess, an empty result says so and offers the fix instead of just
/// disappearing — someone on an en-US phone whose title is only on
/// Russian services (Kinopoisk/ivi/Okko/Wink/...) would otherwise never
/// learn a region switch is the reason nothing showed up.
class _WhereToWatchSection extends StatelessWidget {
  final List<WatchProvider> providers;
  final bool loading;
  final ValueChanged<WatchProvider> onTapProvider;
  final String regionLabel;
  final VoidCallback onChangeRegion;
  final bool applicable;

  const _WhereToWatchSection({
    required this.providers,
    required this.loading,
    required this.onTapProvider,
    required this.regionLabel,
    required this.onChangeRegion,
    required this.applicable,
  });

  @override
  Widget build(BuildContext context) {
    // Games/books/manga never have streaming availability at all — hide
    // completely rather than inviting someone to switch regions for
    // something no region will ever have.
    if (!applicable) return const SizedBox.shrink();
    if (!loading && providers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: GestureDetector(
          onTap: onChangeRegion,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: ClayBoxDecoration(
              boxShadow: SeenlyPalette.flatCardShadow,
              color: SeenlyPalette.paper,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.public, size: 15, color: SeenlyPalette.inkFaint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "${'nothing streaming for'.tr} $regionLabel ${'— try a different region'.tr}",
                    style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: SeenlyPalette.inkFaint),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('where to watch'.tr,
                  style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accent)),
              const Spacer(),
              GestureDetector(
                onTap: onChangeRegion,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text(regionLabel, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more, size: 14, color: SeenlyPalette.inkFaint),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Cross-fades between the shimmer row and the real chips —
          // same soft settle as every other loading→content handoff in
          // the app, instead of a spinner just vanishing and the chips
          // popping in underneath it.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            child: loading
                ? SizedBox(
                    key: const ValueKey('providers-loading'),
                    height: 68,
                    child: Row(
                      children: [
                        for (var i = 0; i < 4; i++) ...[
                          if (i > 0) const SizedBox(width: 14),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ShimmerBlock(
                                  width: 44, height: 44, borderRadius: BorderRadius.circular(13)),
                              const SizedBox(height: 5),
                              ShimmerBlock(
                                  width: 36, height: 8, borderRadius: BorderRadius.circular(4)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  )
                : Column(
                    key: const ValueKey('providers-content'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 68,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: providers.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 14),
                          itemBuilder: (context, i) => HorizontalReveal(
                            delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
                            child: _ProviderChip(
                              provider: providers[i],
                              onTap: () => onTapProvider(providers[i]),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('streaming data provided by JustWatch'.tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  final WatchProvider provider;
  final VoidCallback onTap;
  const _ProviderChip({required this.provider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.92,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: 44,
                height: 44,
                color: SeenlyPalette.paper,
                child: provider.logoUrl != null
                    ? FadeInNetworkImage(
                        url: provider.logoUrl!,
                        fit: BoxFit.cover,
                        placeholder: Center(
                          child: Icon(Icons.live_tv_outlined, size: 18, color: SeenlyPalette.inkFaint),
                        ),
                      )
                    : Icon(Icons.live_tv_outlined, size: 18, color: SeenlyPalette.inkFaint),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              provider.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 8, color: SeenlyPalette.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small poster thumbnail in the header. Tries [primaryUrl] first
/// (which may be TMDB's Russian-localized poster — see
/// MediaItem.posterUrl); if that specific URL fails to load (expired,
/// malformed, or TMDB just doesn't actually have the file at that path),
/// falls back to [fallbackUrl] — the poster that was already working
/// before Russian-poster support existed — before giving up to a flat
/// color. Without this, a single bad TMDB poster path would silently
/// blank out a poster that used to display fine.
class _ResilientPoster extends StatefulWidget {
  final String? primaryUrl;
  final String? fallbackUrl;
  final Color placeholderColor;

  const _ResilientPoster({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.placeholderColor,
  });

  @override
  State<_ResilientPoster> createState() => _ResilientPosterState();
}

class _ResilientPosterState extends State<_ResilientPoster> {
  bool _primaryFailed = false;

  @override
  void didUpdateWidget(covariant _ResilientPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryUrl != widget.primaryUrl) _primaryFailed = false;
  }

  @override
  Widget build(BuildContext context) {
    final usePrimary = !_primaryFailed && (widget.primaryUrl?.isNotEmpty ?? false);
    final url = usePrimary ? widget.primaryUrl : widget.fallbackUrl;
    if (url == null || url.isEmpty) {
      return Container(color: widget.placeholderColor);
    }
    // Same fade-up-from-placeholder as FadeInNetworkImage elsewhere in
    // the app — this is the very first thing anyone sees on the screen,
    // so a hard pop here undercuts the soft-loading feel everywhere
    // else. Kept as a bespoke frameBuilder rather than swapping in
    // FadeInNetworkImage itself, since this one also needs the
    // primary→fallback→flat-color chain below.
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        if (usePrimary && (widget.fallbackUrl?.isNotEmpty ?? false)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_primaryFailed) setState(() => _primaryFailed = true);
          });
        }
        return Container(color: widget.placeholderColor);
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (frame == null) Container(color: widget.placeholderColor),
            AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              child: child,
            ),
          ],
        );
      },
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  final Color? iconColor;
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: loading ? null : onTap,
      scaleTo: 0.88,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: SeenlyPalette.paper.withOpacity(0.9),
          shape: BoxShape.circle,
        ),
        child: loading
            ? Padding(
                padding: EdgeInsets.all(8),
                child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
              )
            : Icon(icon, size: 16, color: iconColor ?? SeenlyPalette.ink),
      ),
    );
  }
}

/// The secondary action next to "log another evening": queues the title
/// under Profile's "plan to watch" shelf without opening the log form.
/// Turns into a filled, non-tappable bookmark once it's been added this
/// session — no need to add the same title twice.
class _PlanToWatchButton extends StatelessWidget {
  final bool added;
  final bool loading;
  final VoidCallback onTap;
  const _PlanToWatchButton({
    required this.added,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: added || loading ? null : onTap,
      scaleTo: 0.9,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: ThemedLoadingIndicator(
                    strokeWidth: 2, color: SeenlyPalette.accent),
              )
            : Icon(
                added ? Icons.bookmark : Icons.bookmark_add_outlined,
                size: 19,
                color: SeenlyPalette.accent,
              ),
      ),
    );
  }
}


