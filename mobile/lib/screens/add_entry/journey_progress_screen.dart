import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/active_journey.dart';
import '../../models/media_item.dart';
import '../../models/series_route_state.dart';
import '../../services/episode_continuation.dart';
import '../../services/log_theme_service.dart';
import '../../services/map_style_service.dart';
import '../../services/series_route_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/journey_real_map.dart';
import '../../widgets/tear_ticket_confirm.dart';
import 'cinema_log_screen.dart';
import 'coach_log_screen.dart';
import 'episode_log_followup.dart';
import 'garden_log_screen.dart';
import '../../services/app_translations.dart';

String _fmtDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

const Map<String, int> _runtimeFallback = {
  'movie': 105, 'series': 45, 'anime': 24, 'game': 150, 'book': 240, 'manga': 30,
};

/// "In progress" screen for the "watching now" flow — a marker rides a
/// path in real wall-clock time against [routeMinutes], and the person
/// taps back in whenever they actually finish, into the same rating
/// card the rest of logging already uses. For the coach theme, when
/// both endpoints resolve to real coordinates, that path is an actual
/// OpenStreetMap between the two cities (see `JourneyRealMap`) — a
/// straight line between them, not a routed road, since there's no
/// routing engine behind it. Garden and ticket have no real place on
/// a map, so they keep the decorative curve below.
///
/// The progress here is honest about what it is: a timer started the
/// moment this screen opened, not a read of the film actually playing
/// (Seenly has no player integration to know that) — so the pause
/// button is a deliberate, person-initiated "I'm stepping away", not
/// something that fires automatically when the film itself pauses.
/// It's a companion for the evening, not a tracker of it. The pause
/// state lives on [ActiveJourney] (see that model's `elapsedAt`), not
/// just locally here, so backing out mid-pause and returning via
/// [ActiveJourneyBadge] keeps it paused rather than silently resuming
/// — and so a future "watched now" screen can read the same state.
class JourneyProgressScreen extends StatefulWidget {
  final MediaItem item;
  final LogTheme theme;
  final String routeLabel;
  final String routeDetail;
  final int routeMinutes;
  // Real coordinates for the two endpoints of tonight's journey — coach
  // (city to city), ticket (departure city to a real cinema), and
  // garden (a garden's own gate to a point inside its grounds) all set
  // these now (see journey_select_screen.dart). Null only if a curated
  // pair's coordinates ever genuinely failed to resolve, in which case
  // the screen falls back to its old decorative curve.
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  // Set together only when this leg is one episode of a series — see
  // ActiveJourney's own doc comment. Both null logs the title the old
  // way (a movie, or a series watched as one whole session).
  final int? season;
  final int? episode;
  // Theme-specific "where this leg arrives" key — the destination
  // city's name (coach), the cinema's own code (ticket), or the
  // garden's own name (garden). Only meaningful alongside season/
  // episode: it's what gets saved as the next episode's transfer point
  // once this leg finishes (see _imBack and SeriesRouteState).
  final String? destMatchKey;
  const JourneyProgressScreen({
    super.key,
    required this.item,
    required this.theme,
    required this.routeLabel,
    required this.routeDetail,
    required this.routeMinutes,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    this.season,
    this.episode,
    this.destMatchKey,
  });

  @override
  State<JourneyProgressScreen> createState() => _JourneyProgressScreenState();
}

class _JourneyProgressScreenState extends State<JourneyProgressScreen> {
  late final DateTime _startedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final existing = appState.journeyFor(widget.item.id);
    // If this same title already has a journey running (the person
    // backed out earlier and is now returning via the badge, or the
    // screen simply got rebuilt), pick up its original start time
    // instead of resetting the clock to zero.
    if (existing != null && existing.item.id == widget.item.id) {
      _startedAt = existing.startedAt;
    } else {
      _startedAt = DateTime.now();
      appState.startJourney(ActiveJourney(
        item: widget.item,
        theme: widget.theme,
        routeLabel: widget.routeLabel,
        routeDetail: widget.routeDetail,
        routeMinutes: widget.routeMinutes,
        originLat: widget.originLat,
        originLng: widget.originLng,
        destLat: widget.destLat,
        destLng: widget.destLng,
        startedAt: _startedAt,
        season: widget.season,
        episode: widget.episode,
      ));
    }
    _startTicker();
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_progress >= 1) _ticker?.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration get _elapsed {
    // Falls back to a raw diff only if the journey was somehow already
    // cleared out from under this screen (shouldn't happen — this
    // screen is the one thing that starts it) rather than crashing.
    final journey = context.read<AppState>().journeyFor(widget.item.id);
    if (journey == null) return DateTime.now().difference(_startedAt);
    return journey.elapsedAt(DateTime.now());
  }

  bool get _isPaused => context.read<AppState>().journeyFor(widget.item.id)?.isPaused ?? false;

  void _togglePause() {
    final appState = context.read<AppState>();
    if (_isPaused) {
      appState.resumeJourney(widget.item.id);
    } else {
      appState.pauseJourney(widget.item.id);
    }
    setState(() {});
  }

  double get _progress =>
      (_elapsed.inSeconds / (widget.routeMinutes * 60)).clamp(0, 1).toDouble();

  int get _filmMinutes => widget.item.runtimeMinutes ?? _runtimeFallback[widget.item.mediaType] ?? 100;

  // All three themes can have two real places to draw a map between now
  // (coach: city to city, ticket: city to cinema, garden: gate to a
  // point inside the grounds) — see journey_select_screen.dart. This
  // only ever comes back false if a coordinate genuinely failed to
  // resolve somewhere upstream.
  bool get _hasRealMap =>
      widget.originLat != null && widget.originLng != null && widget.destLat != null && widget.destLng != null;

  (String, String) get _endpoints => switch (widget.theme) {
        LogTheme.coach => () {
            final parts = widget.routeLabel.split(' → ');
            return (parts.first, parts.length > 1 ? parts.last : parts.first);
          }(),
        LogTheme.ticket => _hasRealMap
            ? () {
                final parts = widget.routeLabel.split(' → ');
                return (parts.first, parts.length > 1 ? parts.last : parts.first);
              }()
            : ('opening', 'credits'),
        LogTheme.garden => _hasRealMap ? ('main gate', widget.routeLabel) : ('planted', 'in bloom'),
      };

  IconData get _markerIcon => switch (widget.theme) {
        LogTheme.coach => Icons.train,
        LogTheme.garden => Icons.directions_walk,
        LogTheme.ticket => Icons.flight,
      };

  JourneyVehicle get _vehicle => switch (widget.theme) {
        LogTheme.coach => JourneyVehicle.train,
        LogTheme.garden => JourneyVehicle.walk,
        LogTheme.ticket => JourneyVehicle.plane,
      };

  Color get _accent => switch (widget.theme) {
        LogTheme.coach => SeenlyPalette.periwinkle,
        LogTheme.garden => SeenlyPalette.sage,
        LogTheme.ticket => SeenlyPalette.coral,
      };

  String get _headline => switch (widget.theme) {
        LogTheme.coach => 'on the rails'.tr,
        LogTheme.garden => 'out in the garden'.tr,
        LogTheme.ticket => 'in the air'.tr,
      };

  String get _routeNoun => switch (widget.theme) {
        LogTheme.coach => 'the train'.tr,
        LogTheme.garden => 'the walk'.tr,
        LogTheme.ticket => 'the flight'.tr,
      };

  String get _comparisonTail {
    final diff = widget.routeMinutes - _filmMinutes;
    final diffText = diff.abs() < 2 ? 'right about the same time'.tr : _fmtDuration(diff.abs());
    if (diff.abs() < 2) return diffText;
    return diff < 0 ? '$diffText ${'shorter'.tr}' : '$diffText ${'longer'.tr}';
  }

  Widget _ratingScreen() => switch (widget.theme) {
        LogTheme.coach => CoachLogScreen(item: widget.item, season: widget.season, episode: widget.episode),
        LogTheme.ticket => CinemaLogScreen(item: widget.item, season: widget.season, episode: widget.episode),
        LogTheme.garden => GardenLogScreen(item: widget.item, season: widget.season, episode: widget.episode),
      };

  String get _cancelPrompt => switch (widget.theme) {
        LogTheme.coach => 'cancel the trip?',
        LogTheme.garden => 'turn back at the gate?',
        LogTheme.ticket => 'cancel the flight?',
      };

  // A small "cancel route" tap only opens this sheet — the actual
  // cancellation needs a full slide across the track below, so a stray
  // tap (or a tap meant for something else) can never abandon the
  // journey by accident. Popping this screen with `false` reuses the
  // same chain the rating flow already pops with, so it cascades all
  // the way back out of the whole add-entry flow, not just one screen.
  Future<void> _confirmCancelRoute() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Text(_cancelPrompt, style: SeenlyText.serif(italic: true, size: 18)),
              const SizedBox(height: 6),
              Text(
                "${widget.item.title.display}${" won't be logged this way — this can't be undone.".tr}",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 124,
                child: TearTicketConfirm(
                  label: 'pull apart to tear it up'.tr,
                  confirmedLabel: 'torn'.tr,
                  accent: SeenlyPalette.coral,
                  onConfirmed: () {
                    Navigator.of(sheetContext).pop();
                    _ticker?.cancel();
                    context.read<AppState>().clearJourney(widget.item.id);
                    Navigator.of(context).pop(false);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text('keep going'.tr, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // For a movie/whole-title journey, the rating screen's seat/spot step
  // returns three distinct results: `true` means an entry actually got
  // saved, so the whole flow is done and this screen closes right along
  // with it. `false` means the person chose to end the route outright
  // from that screen's own leave-confirmation sheet — same intent as
  // this screen's own cancel control, so it cascades the same way.
  // `null` means "back to the route" — they backed out on purpose to
  // keep riding a bit longer, so this screen stays open and picks its
  // own ticker back up instead of closing along with the rating flow.
  Future<void> _imBack() async {
    _ticker?.cancel();

    if (widget.season != null && widget.episode != null) {
      await _imBackFromEpisodeLeg();
      return;
    }

    // Movie / whole-title journey — unchanged: always straight into the
    // rating screen, same as before.
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ratingScreen()),
    );
    if (!mounted) return;
    if (saved == null) {
      if (_progress < 1) _startTicker();
      setState(() {});
      return;
    }
    context.read<AppState>().clearJourney(widget.item.id);
    Navigator.of(context).pop(saved);
  }

  // One leg of a series journey finishing. This episode's own rating
  // happens separately, from the episode list's star tap — not here —
  // so "I'm back" just marks it watched (see markEpisodeWatched, which
  // also logs the season's one diary row if this was the episode that
  // completed it). It still runs the same seat/venue + ticket-tear
  // ritual as "already watched" does for a single episode's evening
  // (see WatchingChoiceScreen._alreadyWatched) — arriving via a live
  // route shouldn't skip that just because the "I watched it" mark
  // already went out above. Once the ritual's done, offers to keep the
  // evening going straight into the next episode: with the stop just
  // saved below and `finishedAt` just now, [startEpisodeJourney] reads
  // this as its "immediate" case, asks the same "watch the next
  // episode?" question, and — on yes — boards the transfer leg it
  // already knows how to build directly, straight back onto the map
  // from where this route left off, skipping the picker entirely. On
  // "not now" (or no next episode left), this just closes back out,
  // same as before.
  Future<void> _imBackFromEpisodeLeg() async {
    await markEpisodeWatched(
      context: context,
      item: widget.item,
      season: widget.season!,
      episode: widget.episode!,
    );
    if (!mounted) return;
    if (widget.destMatchKey != null) {
      await SeriesRoutePrefsService().save(
        widget.item.source,
        widget.item.id,
        SeriesRouteState(
          theme: widget.theme,
          season: widget.season!,
          episode: widget.episode!,
          finishedAt: DateTime.now(),
          stopLabel: widget.destMatchKey!,
          matchKey: widget.destMatchKey!,
          lat: widget.destLat,
          lng: widget.destLng,
        ),
      );
    }
    context.read<AppState>().clearJourney(widget.item.id);

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ratingScreen()),
    );
    if (!mounted) return;

    final next = await nextUnwatchedEpisode(context: context, item: widget.item);
    if (mounted && next != null) {
      final chained = await startEpisodeJourney(
        context,
        item: widget.item,
        theme: widget.theme,
        season: next.$1,
        episode: next.$2,
      );
      if (mounted) Navigator.of(context).pop(chained ?? true);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      // Real map: full-bleed, edge to edge, with everything else
      // floating on top of it. Garden/ticket keep the older layout
      // below, where the decorative curve sits inside the page rather
      // than behind it.
      body: _hasRealMap ? _buildFullscreenMap(context) : _buildCardLayout(context),
    );
  }

  // A soft, warm-toned shadow pair used on every bit of text that floats
  // straight on the map — no card behind it, just enough of a dark halo
  // to keep it legible over whatever tile color happens to sit
  // underneath. Same idea as a turn-by-turn nav app's on-map labels.
  static List<Shadow> get _floatingTextShadow => [
        Shadow(color: SeenlyPalette.ink.withOpacity(0.45), blurRadius: 6, offset: const Offset(0, 1)),
        Shadow(color: SeenlyPalette.ink.withOpacity(0.28), blurRadius: 16),
      ];

  Future<void> _showMapStylePicker(BuildContext context, MapStyleService mapStyle) async {
    final chosen = await showModalBottomSheet<MapStyle>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MapStyleSheet(current: mapStyle.style),
    );
    if (chosen != null) {
      await mapStyle.setStyle(chosen);
    }
  }

  Widget _buildFullscreenMap(BuildContext context) {
    final (originLabel, destLabel) = _endpoints;
    final remaining = Duration(minutes: widget.routeMinutes) - _elapsed;
    final remainingText = remaining.isNegative ? 'any moment now' : _fmtDuration(remaining.inMinutes);
    final mapStyle = context.watch<MapStyleService>();

    return Stack(
      children: [
        Positioned.fill(
          child: JourneyRealMap(
            originLat: widget.originLat!,
            originLng: widget.originLng!,
            destLat: widget.destLat!,
            destLng: widget.destLng!,
            originLabel: originLabel,
            destLabel: destLabel,
            progress: _progress,
            accent: _accent,
            markerIcon: _markerIcon,
            vehicle: _vehicle,
            borderRadius: 0,
            showLegendBar: false,
            style: mapStyle.style,
          ),
        ),
        // A quiet vignette top and bottom — never a box, just enough of
        // a fade behind the floating text so it reads over any tile
        // color underneath. This is what does the "visible without a
        // frame" work instead of a card outline.
        const Positioned(left: 0, right: 0, top: 0, height: 140, child: IgnorePointer(child: _MapScrim(fromTop: true))),
        const Positioned(left: 0, right: 0, bottom: 0, height: 230, child: IgnorePointer(child: _MapScrim(fromTop: false))),
        // Top: the collapse button on its own at the left, the
        // headline/route/attribution as loose right-aligned text —
        // three separate things sharing the top edge rather than one
        // panel.
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GhostButton(icon: Icons.expand_more, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
                _GhostButton(
                  icon: _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  onTap: _togglePause,
                ),
                const SizedBox(width: 8),
                _GhostButton(icon: Icons.close_rounded, onTap: _confirmCancelRoute),
                const SizedBox(width: 8),
                _GhostButton(
                  icon: Icons.layers_outlined,
                  onTap: () => _showMapStylePicker(context, mapStyle),
                ),
                const Spacer(),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_headline,
                          textAlign: TextAlign.end,
                          style: SeenlyText.serif(italic: true, size: 18, color: SeenlyPalette.paper)
                              .copyWith(shadows: _floatingTextShadow)),
                      const SizedBox(height: 3),
                      Text('$originLabel  →  $destLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper, weight: FontWeight.w600)
                              .copyWith(letterSpacing: 0.3, shadows: _floatingTextShadow)),
                      const SizedBox(height: 4),
                      Text(MapStyleCatalog.infoFor(mapStyle.style).attribution,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: SeenlyText.mono(size: 7.5, color: SeenlyPalette.paper.withOpacity(0.8))
                              .copyWith(shadows: _floatingTextShadow)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bottom: a caption, the elapsed/remaining pair as two loose
        // stat blocks (mirroring how a nav app lays out "time
        // remaining" / "distance remaining" side by side with nothing
        // boxing either of them), a bare progress hairline, and the
        // "i'm back" button floating on its own beneath — spread out
        // rather than bundled into one card.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      _isPaused
                          ? 'paused — tap ▶ up top to keep going'
                          : '${widget.item.title.display} is playing somewhere behind you',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper)
                          .copyWith(shadows: _floatingTextShadow)),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _StatBlock(label: 'elapsed'.tr, value: _fmtDuration(_elapsed.inMinutes), shadows: _floatingTextShadow),
                      const Spacer(),
                      _StatBlock(
                          label: 'remaining'.tr,
                          value: remainingText,
                          alignEnd: true,
                          shadows: _floatingTextShadow),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 3,
                      backgroundColor: SeenlyPalette.paper.withOpacity(0.28),
                      valueColor: AlwaysStoppedAnimation(_accent),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    '${'film runs'.tr} ${_fmtDuration(_filmMinutes)} · $_routeNoun ${'runs'.tr} '
                    '${_fmtDuration(widget.routeMinutes)} — $_comparisonTail',
                    textAlign: TextAlign.center,
                    style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.paper.withOpacity(0.9))
                        .copyWith(shadows: _floatingTextShadow),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: _imBack,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(color: _accent.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 7)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text("i'm back — rate it".tr,
                          style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.paper)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardLayout(BuildContext context) {
    final (originLabel, destLabel) = _endpoints;
    final remaining = Duration(minutes: widget.routeMinutes) - _elapsed;
    final remainingText = remaining.isNegative ? 'any moment now' : _fmtDuration(remaining.inMinutes);

    return SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.expand_more, size: 20, color: SeenlyPalette.inkMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  IconButton(
                    icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        size: 18, color: SeenlyPalette.inkMuted),
                    onPressed: _togglePause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: SeenlyPalette.inkMuted),
                    onPressed: _confirmCancelRoute,
                  ),
                  const Spacer(),
                  Text(widget.routeLabel.toLowerCase(),
                      style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint).copyWith(letterSpacing: 0.4)),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_headline, style: SeenlyText.serif(italic: true, size: 18)),
                  const SizedBox(height: 4),
                  Text(
                      _isPaused
                          ? 'paused — tap ▶ to keep going'
                          : '${widget.item.title.display} is playing somewhere behind you',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: CustomPaint(
                  size: const Size(300, 220),
                  painter: _JourneyPathPainter(
                    progress: _progress,
                    accent: _accent,
                    trackColor: SeenlyPalette.border,
                    markerIcon: _markerIcon,
                    originLabel: originLabel,
                    destLabel: destLabel,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.paper,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${_fmtDuration(_elapsed.inMinutes)} ${'elapsed'.tr}',
                                style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                            Text('$remainingText ${'left'.tr}',
                                style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 5,
                            backgroundColor: SeenlyPalette.background,
                            valueColor: AlwaysStoppedAnimation(_accent),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${'film runs'.tr} ${_fmtDuration(_filmMinutes)} · $_routeNoun ${'runs'.tr} '
                          '${_fmtDuration(widget.routeMinutes)} — $_comparisonTail',
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: _imBack,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: Text("i'm back — rate it".tr,
                          style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.paper)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

/// A soft gradient fade — ink at one edge, transparent at the other —
/// standing in for a card outline behind the floating map text. No
/// stroke, no corner radius, no edge to notice; it just quietly darkens
/// the tile behind it enough that paper-colored text stays legible.
/// The style picker opened from the layers button atop the fullscreen
/// route map — four swatches (classic/paper/night/terrain, see
/// services/map_style_service.dart), tap one to apply immediately and
/// close. Same choice Settings' own "map style" row offers — this is
/// just the closer-at-hand version, for whoever notices the tile look
/// mid-route rather than digging into Settings for it.
class _MapStyleSheet extends StatelessWidget {
  final MapStyle current;
  const _MapStyleSheet({required this.current});

  static const _swatchColors = {
    MapStyle.classic: Color(0xFFAAD3DF),
    MapStyle.paper: Color(0xFFE8E0D0),
    MapStyle.night: Color(0xFF1B1F2A),
    MapStyle.terrain: Color(0xFFC9DCA8),
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('map style'.tr, style: SeenlyText.metaLabel),
            const SizedBox(height: 14),
            for (final info in MapStyleCatalog.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MapStyleRow(
                  info: info,
                  swatchColor: _swatchColors[info.style]!,
                  selected: info.style == current,
                  onTap: () => Navigator.of(context).pop(info.style),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapStyleRow extends StatelessWidget {
  final MapStyleInfo info;
  final Color swatchColor;
  final bool selected;
  final VoidCallback onTap;
  const _MapStyleRow({
    required this.info,
    required this.swatchColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? SeenlyPalette.accent.withOpacity(0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: swatchColor,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: SeenlyPalette.border),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(info.label.tr,
                    style: SeenlyText.serif(
                        size: 14,
                        color: SeenlyPalette.ink,
                        weight: selected ? FontWeight.w700 : FontWeight.w400)),
              ),
              if (selected) const Icon(Icons.check_circle, size: 18, color: SeenlyPalette.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapScrim extends StatelessWidget {
  final bool fromTop;
  const _MapScrim({required this.fromTop});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
          end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
          // Darkened from the original 0.38→0 fade, which read fine on
          // the dark "night" map style but left white overlay text
          // nearly invisible on the light "paper"/"classic" styles —
          // the near-white base tile under a near-transparent scrim is
          // still near-white. The far edge also no longer fades all the
          // way to 0: it holds a faint floor so text sitting close to
          // that edge (the bottom caption, the top attribution line)
          // still has *some* wash behind it instead of none.
          colors: [
            SeenlyPalette.ink.withOpacity(0.6),
            SeenlyPalette.ink.withOpacity(0.16),
          ],
        ),
      ),
    );
  }
}

/// The collapse button, restyled for sitting directly on the map: a
/// soft translucent disc with no border and no hard drop shadow — just
/// enough of a dark wash behind the glyph to keep it findable, the same
/// gentle touch as the rest of the app rather than a boxed icon button.
class _GhostButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GhostButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SeenlyPalette.ink.withOpacity(0.3),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: SeenlyPalette.paper),
        ),
      ),
    );
  }
}

/// One loose "label above value" block, no card underneath — used for
/// both elapsed and remaining so the pair reads like a nav app's "time
/// remaining" / "distance remaining" side by side, plain text carrying
/// all of it.
class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;
  final List<Shadow> shadows;
  const _StatBlock({
    required this.label,
    required this.value,
    required this.shadows,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.paper, weight: FontWeight.w600)
                .copyWith(letterSpacing: 1.2, shadows: shadows)),
        const SizedBox(height: 2),
        Text(value,
            style: SeenlyText.serif(size: 22, weight: FontWeight.w600, color: SeenlyPalette.paper)
                .copyWith(shadows: shadows)),
      ],
    );
  }
}

/// Fixed decorative S-curve, walked by [progress] using
/// `PathMetric.getTangentForOffset` for an exact point-and-heading on the
/// line — the fallback for garden and ticket (see the screen's own
/// note above; the coach theme gets a real map instead), just one
/// consistent, pleasant curve dressed per theme.
class _JourneyPathPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final Color trackColor;
  final IconData markerIcon;
  final String originLabel;
  final String destLabel;
  const _JourneyPathPainter({
    required this.progress,
    required this.accent,
    required this.trackColor,
    required this.markerIcon,
    required this.originLabel,
    required this.destLabel,
  });

  Path _curve(Size size) {
    final w = size.width, h = size.height;
    return Path()
      ..moveTo(w * 0.08, h * 0.86)
      ..cubicTo(w * 0.32, h * 0.86, w * 0.22, h * 0.5, w * 0.46, h * 0.42)
      ..cubicTo(w * 0.7, h * 0.34, w * 0.62, h * 0.14, w * 0.92, h * 0.06);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _curve(size);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, trackPaint);

    final metrics = path.computeMetrics().toList();
    final totalLength = metrics.fold<double>(0, (sum, m) => sum + m.length);
    final travelled = totalLength * progress;

    final travelledPath = Path();
    var consumed = 0.0;
    for (final metric in metrics) {
      if (consumed >= travelled) break;
      final take = math.min(metric.length, travelled - consumed);
      travelledPath.addPath(metric.extractPath(0, take), Offset.zero);
      consumed += metric.length;
    }
    final progressPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(travelledPath, progressPaint);

    // Endpoint dots + labels.
    final start = metrics.first.getTangentForOffset(0)!.position;
    final endMetric = metrics.last;
    final end = endMetric.getTangentForOffset(endMetric.length)!.position;
    final dotPaint = Paint()..color = SeenlyPalette.placeholder;
    canvas.drawCircle(start, 4, dotPaint);
    canvas.drawCircle(end, 4, dotPaint);
    _drawLabel(canvas, originLabel, start + const Offset(0, 16), TextAlign.center);
    _drawLabel(canvas, destLabel, end + const Offset(0, -22), TextAlign.center);

    // Marker at current progress.
    var remaining = travelled.clamp(0, totalLength);
    Offset markerPos = start;
    for (final metric in metrics) {
      if (remaining <= metric.length) {
        markerPos = metric.getTangentForOffset(remaining.toDouble())?.position ?? markerPos;
        break;
      }
      remaining -= metric.length;
    }
    canvas.drawCircle(markerPos, 11, Paint()..color = SeenlyPalette.paper);
    canvas.drawCircle(markerPos, 11, Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(markerIcon.codePoint),
        style: TextStyle(fontSize: 12, fontFamily: markerIcon.fontFamily, color: accent, package: markerIcon.fontPackage),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(canvas, markerPos - Offset(iconPainter.width / 2, iconPainter.height / 2));
  }

  void _drawLabel(Canvas canvas, String text, Offset center, TextAlign align) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 12, color: SeenlyPalette.inkFaint)),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 90);
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _JourneyPathPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}
