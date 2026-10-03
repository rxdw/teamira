import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/partner_status.dart';
import '../models/planned_evening.dart';
import '../models/suggestion.dart';
import '../models/watchlist_entry.dart';
import '../services/api_client.dart';
import '../services/evening_plan_service.dart';
import '../services/premium_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'empty_state.dart';
import 'tear_ticket_confirm.dart';
import 'themed_loading_indicator.dart';
import 'themed_poster_tile.dart';
import 'heart_burst.dart';
import 'soft_motion.dart';
import 'wow_motion.dart'
    show Entrance, BreathingGlow, PressScale, ShimmerBlock, FadeInNetworkImage;
import '../services/app_translations.dart';
import '../services/locale_service.dart';
import 'saved_celebration.dart';
import '../theme/clay_kit.dart';
import '../models/pair_album.dart';
import '../screens/partner/album/album_strings.dart' as album_strings;
import '../screens/partner/album/note_compose_sheet.dart';
import '../services/pair_album_service.dart';

/// The whole "plan an evening" ritual, full screen: pick something off
/// the plan-to-watch shelf, say when, say whether it's a co-viewing
/// evening, then pull the ticket apart to make it official. Three small
/// steps rather than one busy form, so each screen only ever asks one
/// question — same reasoning as the add-entry flow's own step screens.
/// Can be opened again even when an evening's already planned — this
/// adds a new ticket alongside it rather than replacing it (see
/// [EveningPlanService]).
///
/// [coViewingByDefault] pre-checks the co-viewing toggle (CoViewingScreen
/// opens it this way, since planning *from* the co-viewing screen is
/// almost always about watching together) — it's still just a starting
/// point, not a lock, since a linked pair can just as easily plan a solo
/// night from that same screen.
///
/// [approvingSuggestion] turns this into "approve a suggestion" rather
/// than a fresh plan: agreeing to a suggested evening *is* planning one
/// (same title, same "when", same co-viewing toggle — it's just already
/// halfway filled in), so it's the same ritual starting one step in
/// (title already picked, co-viewing locked on) rather than a separate,
/// dateless "just add it" shortcut. Confirming calls
/// [PartnerService.acceptSuggestion] — with whatever date/time got
/// picked — instead of [PartnerService.planCoViewing].
Future<void> showPlanEveningSheet(
  BuildContext context, {
  bool coViewingByDefault = false,
  Suggestion? approvingSuggestion,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _PlanEveningSheet(
        coViewingByDefault: coViewingByDefault,
        approvingSuggestion: approvingSuggestion,
      ),
    ),
  );
}

class _PlanEveningSheet extends StatefulWidget {
  final bool coViewingByDefault;
  final Suggestion? approvingSuggestion;
  const _PlanEveningSheet({required this.coViewingByDefault, this.approvingSuggestion});

  @override
  State<_PlanEveningSheet> createState() => _PlanEveningSheetState();
}

class _PlanEveningSheetState extends State<_PlanEveningSheet> {
  int _step = 0; // 0 = pick title, 1 = pick date & co-viewing, 2 = tear to confirm

  List<WatchlistEntry>? _shelf;
  bool _loadingShelf = true;

  // Type-ahead search across all of teamira's catalog (see
  // FavoriteAddScreen's own search tab, same debounce pattern) — an
  // evening isn't limited to whatever's already sitting on the
  // plan-to-watch shelf, so a typed query looks everywhere rather than
  // just filtering that shelf down.
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<MediaItem> _searchResults = const [];
  String _lastQuery = '';

  MediaItem? _picked;
  DateTime _date = DateTime.now();
  TimeOfDay? _time; // optional — no time set reads as "just an evening"
  bool _coViewing = false;
  PartnerStatus? _partnerStatus;

  // The album note for the picked title, written *before* the evening is
  // planned (the server keys notes by title, not by planned entry, so none
  // of this depends on the ticket being torn). Loaded lazily when the
  // confirm step opens; null = none yet.
  AlbumPage? _albumNote;
  AlbumStatus? _albumStatus;
  bool _albumLoaded = false;

  @override
  void initState() {
    super.initState();
    final suggestion = widget.approvingSuggestion;
    if (suggestion != null) {
      // Title's already decided — skip straight to "when", same as if
      // someone had just picked it off the shelf.
      _picked = suggestion.toMediaItem();
      _step = 1;
      _coViewing = true;
    } else {
      _coViewing = widget.coViewingByDefault;
    }
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final collections = await app.profile.collections();
      PartnerStatus? partnerStatus;
      try {
        partnerStatus = await app.partner.status();
      } catch (_) {
        // Not linked, or a network hiccup — co-viewing toggle just stays
        // hidden in that case (see the linked check in _dateStep).
      }
      if (!mounted) return;
      setState(() {
        _shelf = collections.watchLater;
        _partnerStatus = partnerStatus;
        _loadingShelf = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingShelf = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(value));
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed == _lastQuery) return;
    _lastQuery = trimmed;
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final found = await context.read<AppState>().media.search(trimmed);
      if (!mounted || trimmed != _lastQuery) return;
      setState(() {
        _searchResults = found;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  void _pick(WatchlistEntry entry) => _pickMedia(MediaItem.fromWatchlistEntry(entry));

  void _pickMedia(MediaItem item) {
    setState(() {
      _picked = item;
      _step = 1;
    });
  }

  bool _isTimePreset(int hour, int minute) =>
      _time != null && _time!.hour == hour && _time!.minute == minute;

  bool _isAnyTimePreset() =>
      _isTimePreset(10, 0) || _isTimePreset(14, 0) || _isTimePreset(19, 0) || _isTimePreset(21, 0);

  Future<void> _pickCustomTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 19, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: SeenlyPalette.accent,
                onPrimary: SeenlyPalette.accentOnAccent,
                surface: SeenlyPalette.paper,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  bool _confirming = false;

  int get _minStep => widget.approvingSuggestion != null ? 1 : 0;

  Future<void> _confirm() async {
    final picked = _picked;
    if (picked == null || _confirming) return;
    setState(() => _confirming = true);
    final suggestion = widget.approvingSuggestion;
    String? coViewEntryId;
    try {
      if (suggestion != null) {
        // Approving a suggestion doesn't just plan a new co-viewing
        // entry — it consumes the suggestion itself (clears it from the
        // Home inbox) and carries over who originally sent it. Unlike
        // the best-effort mirror below, this one has to actually
        // succeed: skipping it silently would leave the suggestion
        // sitting in the inbox as if nothing happened.
        final entry = await context.read<AppState>().partner.acceptSuggestion(
              suggestion.id,
              date: DateTime(_date.year, _date.month, _date.day),
              hour: _time?.hour,
              minute: _time?.minute,
            );
        coViewEntryId = entry.id;
      } else if (_coViewing && (_partnerStatus?.linked ?? false)) {
        // Co-viewing + actually linked: mirror this onto the shared
        // co-viewing list so the partner sees the same scheduled evening
        // on their own side too, not just as a ticket sitting on this
        // device (see PartnerService.planCoViewing). Best-effort — the
        // personal ticket below is saved either way, so a sync hiccup
        // here shouldn't block "get a ticket" from finishing.
        try {
          final entry = await context.read<AppState>().partner.planCoViewing(
                picked,
                date: DateTime(_date.year, _date.month, _date.day),
                hour: _time?.hour,
                minute: _time?.minute,
              );
          coViewEntryId = entry.id;
        } catch (_) {}
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't accept that just now — try again".tr)),
      );
      return;
    }
    final evening = PlannedEvening(
      mediaId: picked.id,
      source: picked.source,
      mediaType: picked.mediaType,
      title: picked.title.display,
      posterUrl: picked.posterUrl,
      year: picked.year,
      date: DateTime(_date.year, _date.month, _date.day),
      hour: _time?.hour,
      minute: _time?.minute,
      coViewing: suggestion != null || _coViewing,
      partnerUsername: (suggestion != null || _coViewing) ? _partnerStatus?.partnerUsername : null,
      coViewEntryId: coViewEntryId,
      createdAt: DateTime.now(),
    );
    await context.read<EveningPlanService>().planEvening(evening);
    if (!mounted) return;
    // A short beat so "ticket's yours" actually gets read before the
    // sheet closes out from under it.
    await Future.delayed(const Duration(milliseconds: 650));
    if (mounted) {
      // The evening is planned: the poster gets its bookmark, with the
      // date it's planned for — and, if it's a shared one, the hearts.
      showSavedCelebration(
        context,
        kind: SavedKind.planned,
        title: picked.title.display,
        posterUrl: picked.posterUrl,
        mediaType: picked.mediaType,
        partnerName: (suggestion != null || _coViewing) ? _partnerStatus?.partnerUsername : null,
        together: suggestion != null || _coViewing,
        whenLabel: [_formatDate(_date), if (_time != null) _time!.format(context)].join(' · '),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.paper,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                      // Back steps back through the ritual; on the first
                      // step there's nothing to step back to, so it just
                      // leaves the screen — same place the close button
                      // (below) always goes. Approving a suggestion
                      // starts one step in with the title already
                      // decided (see initState) — stepping back below
                      // that would land on the title picker and let the
                      // title quietly change out from under the
                      // suggestion being accepted, so that step is off
                      // limits here too.
                      onPressed: () => _step > _minStep
                          ? setState(() => _step -= 1)
                          : Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: SoftSwap(
                        child: Text(
                          _step == 0
                              ? 'plan an evening'.tr
                              : _step == 1
                                  ? 'when?'.tr
                                  : 'get your ticket'.tr,
                          key: ValueKey<int>(_step),
                          style: SeenlyText.serif(italic: true, size: 17),
                        ),
                      ),
                    ),
                    PressScale(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                        child: Icon(Icons.close, size: 14, color: SeenlyPalette.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _EveningStepper(step: _step),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  // Each step glides in from the side it's reached from
                  // (right going forward, left going back).
                  child: StepSwitcher(
                    step: _step,
                    expand: true,
                    child: _step == 0
                        ? _titleStep()
                        : _step == 1
                            ? _dateStep()
                            : _confirmStep(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _titleStep() {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: SeenlyPalette.background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (v) {
              // Rebuild right away so the shelf/search switch below
              // reacts as the field empties out, not just once the
              // debounce (in _onSearchChanged) actually fires a search.
              setState(() {});
              _onSearchChanged(v);
            },
            style: SeenlyText.serif(size: 13),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              hintText: 'search for a title…'.tr,
              hintStyle: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder),
              prefixIcon: Icon(Icons.search, size: 16, color: SeenlyPalette.inkFaint),
              prefixIconConstraints: const BoxConstraints(minWidth: 30),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _coViewingToggle(),
        const SizedBox(height: 12),
        Expanded(
          // Shelf, "searching…" and each finished search are different
          // pictures — cross-fade between them instead of cutting.
          child: SoftSwap(
            alignment: Alignment.topCenter,
            duration: const Duration(milliseconds: 240),
            rise: 0.015,
            child: KeyedSubtree(
              key: ValueKey<String>(
                hasQuery ? (_searching ? 'searching' : 'results:$_lastQuery') : 'shelf',
              ),
              child: hasQuery ? _searchResultsGrid() : _shelfGrid(),
            ),
          ),
        ),
      ],
    );
  }

  /// Say whether this is a co-viewing evening before even picking a
  /// title — moved here (from the date step) so the choice is made
  /// right at the start of the ritual, not tacked on halfway through.
  /// Three states: linked and toggled, linked and off, or not linked at
  /// all — the last of which still gets its own row rather than just
  /// disappearing, since "I don't have a partner linked yet" is exactly
  /// the moment someone might want to go fix that.
  Widget _coViewingToggle() {
    final linked = _partnerStatus?.linked ?? false;
    if (!linked) {
      return PressScale(
        onTap: _openInvitePartnerSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: SeenlyPalette.accent.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SeenlyPalette.accent.withOpacity(0.28)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SeenlyPalette.accent.withOpacity(0.14),
                ),
                child: Icon(Icons.favorite_border, size: 16, color: SeenlyPalette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'no partner linked yet — invite one to plan evenings together'.tr,
                  style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'invite'.tr,
                  style: SeenlyText.mono(
                    size: 10.5,
                    color: SeenlyPalette.accentOnAccent,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return PressScale(
      onTap: () => setState(() => _coViewing = !_coViewing),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _coViewing ? SeenlyPalette.accent.withOpacity(0.12) : SeenlyPalette.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _coViewing ? SeenlyPalette.accent : SeenlyPalette.border),
        ),
        child: Row(
          children: [
            // Turning it on: the heart fills in with a small pop and a
            // few hearts drift off it.
            HeartBurst(
              isFavorite: _coViewing,
              child: SoftSwap(
                pop: true,
                alignment: Alignment.center,
                duration: const Duration(milliseconds: 280),
                child: Icon(
                  _coViewing ? Icons.favorite : Icons.favorite_border,
                  key: ValueKey<bool>(_coViewing),
                  size: 17,
                  color: _coViewing ? SeenlyPalette.accent : SeenlyPalette.inkFaint,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${'watching with'.tr} ${_partnerStatus?.partnerUsername ?? 'your partner'.tr}',
                style: SeenlyText.serif(size: 13),
              ),
            ),
            Switch.adaptive(
              value: _coViewing,
              activeColor: SeenlyPalette.accent,
              onChanged: (v) => setState(() => _coViewing = v),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInvitePartnerSheet() async {
    final status = await showModalBottomSheet<PartnerStatus>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _InvitePartnerSheet(),
    );
    if (status != null && mounted) {
      setState(() {
        _partnerStatus = status;
        if (status.linked) _coViewing = true;
      });
    }
  }

  // Nothing typed yet — browse the plan-to-watch shelf, same as before.
  Widget _shelfGrid() {
    if (_loadingShelf) return _posterSkeleton();
    final shelf = _shelf ?? const [];
    if (shelf.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Entrance(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BreathingGlow(
                  color: SeenlyPalette.accent,
                  size: 108,
                  child: const GhostPosterRow(centerIcon: Icons.bookmark_border),
                ),
                const SizedBox(height: 22),
                Text(
                  'nothing on your plan-to-watch shelf yet — search for a title above, or add a few to that shelf first.'.tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(size: 13.5, color: SeenlyPalette.inkMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2 / 3,
      ),
      itemCount: shelf.length,
      itemBuilder: (context, i) {
        final e = shelf[i];
        // Posters settle in one after another, row by row.
        return Entrance(
          key: ValueKey<String>('shelf$i${e.displayTitle}'),
          delay: Duration(milliseconds: 32 * (i % 12)),
          duration: const Duration(milliseconds: 460),
          riseBy: 14,
          child: ThemedPosterTile(
            title: e.displayTitle,
            posterUrl: e.posterUrl,
            mediaType: e.mediaType,
            fallbackColor: SeenlyPalette.gridColorFor(i),
            onTap: () => _pick(e),
          ),
        );
      },
    );
  }

  // Something's typed — a type-ahead search across all of teamira's
  // catalog (see MediaService.search), not just what's already on the
  // plan-to-watch shelf. Picking a result here plans an evening the same
  // way picking off the shelf does; it doesn't need to already be on any
  // shelf first (same "toggling creates the row" idea as
  // ProfileService.toggleFavorite, used by FavoriteAddScreen's own
  // search tab).
  Widget _searchResultsGrid() {
    if (_searching) return _posterSkeleton();
    if (_searchResults.isEmpty) {
      return Center(
        child: Entrance(
          riseBy: 10,
          child: Text(
            'nothing found'.tr,
            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2 / 3,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, i) {
        final item = _searchResults[i];
        return Entrance(
          key: ValueKey<String>('found$i${item.source}${item.id}'),
          delay: Duration(milliseconds: 32 * (i % 12)),
          duration: const Duration(milliseconds: 460),
          riseBy: 14,
          child: ThemedPosterTile(
            title: item.title.display,
            posterUrl: item.posterUrl,
            mediaType: item.mediaType,
            fallbackColor: SeenlyPalette.gridColorFor(i),
            onTap: () => _pickMedia(item),
          ),
        );
      },
    );
  }

  /// Nine soft shimmering poster-shaped blocks — what the grid is about to
  /// look like, standing in for the shelf while it loads and for a search
  /// while it runs, so the screen never goes blank or jumps.
  Widget _posterSkeleton() {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 4),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2 / 3,
      children: [
        for (int i = 0; i < 9; i++)
          Entrance(
            key: ValueKey<int>(i),
            delay: Duration(milliseconds: 40 * i),
            duration: const Duration(milliseconds: 400),
            riseBy: 8,
            child: ShimmerBlock(borderRadius: BorderRadius.circular(14)),
          ),
      ],
    );
  }

  Widget _dateStep() {
    final picked = _picked!;
    final linked = _partnerStatus?.linked ?? false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    // Next Friday (or today, if today already is one) — the app's own
    // stand-in for "this weekend" so the chip is always one tap instead
    // of asking someone to reason about which Saturday they mean.
    var weekend = today;
    while (weekend.weekday != DateTime.friday) {
      weekend = weekend.add(const Duration(days: 1));
    }

    // Each block settles in a beat after the one above it, top to bottom —
    // the poster first, the button last.
    Widget settle(int n, Widget child) => Entrance(
          delay: Duration(milliseconds: 70 * n),
          duration: const Duration(milliseconds: 480),
          riseBy: 14,
          child: child,
        );

    final posterFallback = Container(
      color: SeenlyPalette.mediaColor(picked.mediaType),
      alignment: Alignment.center,
      child: Icon(Icons.movie_creation_outlined, color: SeenlyPalette.paper, size: 40),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The pick, front and center — this step is about committing
          // to a date for *this*, so it gets the same "hero poster"
          // treatment the title detail screen gives a title, not the
          // small identifier chip a form field would use. It lands with a
          // small settle (a touch smaller and tilted, then upright) and
          // the art fades in once it has loaded.
          Center(
            child: _PosterSettle(
              child: Container(
                decoration: ClayBoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: SeenlyPalette.softShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    width: 220,
                    height: 320,
                    child: picked.posterUrl != null && picked.posterUrl!.isNotEmpty
                        ? FadeInNetworkImage(
                            url: picked.posterUrl!,
                            placeholder: posterFallback,
                          )
                        : posterFallback,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          settle(
            1,
            Center(
              child: Text(
                picked.title.display,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(italic: true, size: 19, weight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 28),
          settle(
            2,
            Row(
              children: [
                Expanded(
                  child: _DateChip(label: 'today'.tr, selected: _sameDay(_date, today), onTap: () => setState(() => _date = today)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateChip(label: 'tomorrow'.tr, selected: _sameDay(_date, tomorrow), onTap: () => setState(() => _date = tomorrow)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateChip(label: 'this weekend'.tr, selected: _sameDay(_date, weekend), onTap: () => setState(() => _date = weekend)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          settle(
            3,
            _MiniCalendar(
              selected: _date,
              onSelected: (d) => setState(() => _date = d),
            ),
          ),
          const SizedBox(height: 22),
          settle(
            4,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'what time?'.tr,
                  style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DateChip(
                        label: 'morning'.tr,
                        selected: _isTimePreset(10, 0),
                        onTap: () => setState(() => _time = const TimeOfDay(hour: 10, minute: 0)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateChip(
                        label: 'afternoon'.tr,
                        selected: _isTimePreset(14, 0),
                        onTap: () => setState(() => _time = const TimeOfDay(hour: 14, minute: 0)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateChip(
                        label: 'evening'.tr,
                        selected: _isTimePreset(19, 0),
                        onTap: () => setState(() => _time = const TimeOfDay(hour: 19, minute: 0)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateChip(
                        label: 'night'.tr,
                        selected: _isTimePreset(21, 0),
                        onTap: () => setState(() => _time = const TimeOfDay(hour: 21, minute: 0)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _customTimeRow(),
              ],
            ),
          ),
          if (linked && widget.approvingSuggestion == null) ...[
            const SizedBox(height: 20),
            settle(5, _coViewingToggle()),
          ],
          const SizedBox(height: 22),
          settle(6, _continueButton()),
        ],
      ),
    );
  }

  /// The "pick an exact time" row: its outline warms to the accent colour
  /// once a custom time is set, the text swaps softly, and the little ✕
  /// pops in only when there's a time to clear.
  Widget _customTimeRow() {
    final custom = _time != null && !_isAnyTimePreset();
    final label = _time == null ? 'no exact time — tap to pick one'.tr : _time!.format(context);
    return PressScale(
      onTap: _pickCustomTime,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: SeenlyPalette.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: custom ? SeenlyPalette.accent : SeenlyPalette.border),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 16, color: custom ? SeenlyPalette.accent : SeenlyPalette.inkFaint),
            const SizedBox(width: 10),
            Expanded(
              child: SoftSwap(
                child: Text(
                  label,
                  key: ValueKey<String>(label),
                  style: SeenlyText.serif(size: 13),
                ),
              ),
            ),
            SoftSwap(
              pop: true,
              alignment: Alignment.center,
              child: _time != null
                  ? GestureDetector(
                      key: const ValueKey<String>('clear-time'),
                      onTap: () => setState(() => _time = null),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: _ClearIcon(),
                      ),
                    )
                  : const SizedBox(key: ValueKey<String>('no-clear'), width: 18, height: 18),
            ),
          ],
        ),
      ),
    );
  }

  /// A one-line read-back of what's been chosen (it changes softly as the
  /// choices change) above the button that moves on.
  Widget _continueButton() {
    final summary = _summary();
    return Column(
      children: [
        SoftSwap(
          alignment: Alignment.center,
          child: Text(
            summary,
            key: ValueKey<String>(summary),
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: PressScale(
            onTap: () {
              setState(() => _step = 2);
              _loadAlbumNote();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: SeenlyPalette.accent,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: SeenlyPalette.accent.withOpacity(0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text('continue'.tr,
                  style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent)),
            ),
          ),
        ),
      ],
    );
  }

  /// A couple planning an evening together can leave a sealed note for the
  /// other one. Shown only for a linked *couple* (a company has no album)
  /// and only once the co-viewing toggle is on.
  bool get _canLeaveNote {
    final st = _partnerStatus;
    return _coViewing && st != null && st.linked && !st.isCompany && _picked != null;
  }

  Future<void> _loadAlbumNote() async {
    if (!_canLeaveNote) return;
    try {
      final service = PairAlbumService(ApiClient.instance);
      final results = await Future.wait<Object>([service.waitingNotes(), service.status()]);
      if (!mounted) return;
      final pages = results[0] as List<AlbumPage>;
      final key = '${_picked!.source}:${_picked!.id}';
      AlbumPage? mine;
      for (final p in pages) {
        if (p.key == key) mine = p;
      }
      setState(() {
        _albumNote = mine;
        _albumStatus = results[1] as AlbumStatus;
        _albumLoaded = true;
      });
    } catch (_) {
      // No note row is a fine fallback; planning itself must never depend on it.
    }
  }

  Future<void> _openNoteSheet() async {
    final picked = _picked;
    if (picked == null) return;
    final result = await showNoteComposeSheet(
      context,
      item: picked,
      partnerName: _partnerStatus?.partnerUsername ?? album_strings.at('партнёр', 'partner'),
      status: _albumStatus,
      existing: _albumNote,
    );
    if (result != null && mounted) await _loadAlbumNote();
  }

  Widget _noteRow() {
    final partner = _partnerStatus?.partnerUsername ?? album_strings.at('партнёр', 'partner');
    final written = _albumNote?.mine != null;
    final theirs = _albumNote?.partnerSealed ?? false;
    final Color tone = written ? SeenlyPalette.sage : SeenlyPalette.coral;
    return PressScale(
      onTap: _openNoteSheet,
      scaleTo: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tone.withOpacity(0.09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tone.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            SoftSwap(
              pop: true,
              alignment: Alignment.center,
              child: Icon(
                written ? Icons.mark_email_read_rounded : Icons.mail_outline_rounded,
                key: ValueKey<bool>(written),
                size: 20,
                color: tone,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    written
                        ? album_strings.at('записка запечатана', 'your note is sealed')
                        : album_strings.at('записка для $partner', 'a note for $partner'),
                    style: SeenlyText.serif(size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    theirs
                        ? album_strings.at('$partner уже оставил(а) свою — прочтёте после вечера',
                            '$partner already left one — you\'ll read it after the evening')
                        : written
                            ? album_strings.at('откроется, когда вы досмотрите', 'opens once you\'ve watched')
                            : album_strings.at('прочтёт после просмотра · можно и потом',
                                'read after the film · or add it later'),
                    style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }

  Widget _confirmStep() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Entrance(
            delay: const Duration(milliseconds: 60),
            riseBy: 10,
            child: Text(
              _summary(withTitle: true),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
            ),
          ),
          if (_canLeaveNote && _albumLoaded) ...[
            const SizedBox(height: 16),
            Entrance(
              delay: const Duration(milliseconds: 120),
              riseBy: 10,
              child: _noteRow(),
            ),
          ],
          const SizedBox(height: 22),
          Entrance(
            delay: const Duration(milliseconds: 180),
            duration: const Duration(milliseconds: 640),
            riseBy: 20,
            child: TearTicketConfirm(
              label: 'pull apart to get your ticket'.tr,
              confirmedLabel: 'it\'s yours'.tr,
              accent: SeenlyPalette.accent,
              onConfirmed: _confirm,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// "Sep 22 · 7:00 PM · with Anna" — the date, the time if one's set, the
  /// partner if it's a co-viewing evening; with [withTitle] the pick's
  /// title leads. One place, so the two steps that show it can't disagree.
  String _summary({bool withTitle = false}) {
    final parts = <String>[
      if (withTitle) _picked!.title.display,
      _formatDate(_date),
      if (_time != null) _time!.format(context),
      if (_coViewing) '${'with'.tr} ${_partnerStatus?.partnerUsername ?? 'your partner'.tr}',
    ];
    return parts.join(' · ');
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  // Short genitive forms, the way a date reads in Russian ("22 сен").
  static const _monthsRu = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  String _formatDate(DateTime d) => LocaleService.appIsRussian
      ? '${d.day} ${_monthsRu[d.month - 1]}'
      : '${_months[d.month - 1]} ${d.day}';
}

/// Three little pills under the header — where you are in the ritual. The
/// current one stretches out and takes the accent colour, the ones already
/// done stay lightly tinted, the ones ahead are plain; moving between steps
/// slides the stretch along.
class _EveningStepper extends StatelessWidget {
  final int step;
  const _EveningStepper({required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            width: i == step ? 34 : 14,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i == step
                  ? SeenlyPalette.accent
                  : i < step
                      ? SeenlyPalette.accent.withOpacity(0.35)
                      : SeenlyPalette.border,
            ),
          ),
        ],
      ],
    );
  }
}

/// The picked title's poster arriving on the "when?" step: fades up from a
/// touch smaller and slightly tilted, then sits upright — as if set down on
/// the table rather than switched on. Plays once; a plain child when the
/// system asks for reduced motion.
class _PosterSettle extends StatelessWidget {
  final Widget child;
  const _PosterSettle({required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 640),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.rotate(
          angle: (1 - t) * -0.035,
          child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
        ),
      ),
    );
  }
}

class _ClearIcon extends StatelessWidget {
  const _ClearIcon();

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.close, size: 14, color: SeenlyPalette.inkFaint);
}

/// A pairing code shown as a row of little tiles that pop in one after
/// another, left to right — like numbers being stamped onto a ticket —
/// instead of the whole code appearing at once.
class _CodeReveal extends StatefulWidget {
  final String code;
  const _CodeReveal({required this.code});

  @override
  State<_CodeReveal> createState() => _CodeRevealState();
}

class _CodeRevealState extends State<_CodeReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final List<Animation<double>> _grow = _intervals(Curves.easeOutBack);
  late final List<Animation<double>> _fade = _intervals(Curves.easeOut);

  List<Animation<double>> _intervals(Curve curve) {
    final n = widget.code.length;
    return List.generate(n, (i) {
      final start = n <= 1 ? 0.0 : (i / n) * 0.55;
      final end = (start + 0.45).clamp(0.0, 1.0).toDouble();
      return CurvedAnimation(parent: _c, curve: Interval(start, end, curve: curve));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final chars = widget.code.split('');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < chars.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _tile(i, chars[i], reduceMotion),
          ],
        ],
      ),
    );
  }

  Widget _tile(int i, String char, bool reduceMotion) {
    final tile = Container(
      width: 30,
      height: 40,
      alignment: Alignment.center,
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Text(
        char,
        style: SeenlyText.mono(size: 20, weight: FontWeight.w700, color: SeenlyPalette.accent),
      ),
    );
    if (reduceMotion) return tile;
    return FadeTransition(
      opacity: _fade[i],
      child: ScaleTransition(scale: _grow[i], child: tile),
    );
  }
}

/// A compact, self-contained version of the pairing flow Home's own
/// co-viewing card offers (generate a code / enter a partner's code) —
/// just enough to link from inside the ritual, without leaving the
/// sheet. Pops with the fresh [PartnerStatus] once linking succeeds, so
/// the caller can flip the co-viewing toggle on right away; popping with
/// nothing (back/close) just leaves the toggle in its "not linked" row.
class _InvitePartnerSheet extends StatefulWidget {
  const _InvitePartnerSheet();

  @override
  State<_InvitePartnerSheet> createState() => _InvitePartnerSheetState();
}

class _InvitePartnerSheetState extends State<_InvitePartnerSheet> {
  bool _busy = false;
  bool _entering = false;
  String? _pendingCode;
  String? _error;
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _generateCode() async {
    setState(() => _busy = true);
    try {
      final status = await context.read<AppState>().partner.pair();
      if (!mounted) return;
      setState(() {
        _pendingCode = status.pendingCode;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "couldn't get a code just now — try again".tr;
      });
    }
  }

  Future<void> _submitJoin() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'codes are 6 characters'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await context.read<AppState>().partner.join(code);
      if (!mounted) return;
      // Fresh couple, just formed — see AppState.notePartnerJustLinked's
      // own doc comment on why exactly-two is enough to mean that
      // without extra bookkeeping. Queued before popping this whole
      // sheet, so RootShell (sitting underneath) picks it up once
      // control actually lands back on it.
      if (status.linked &&
          status.members.length == 2 &&
          !context.read<PremiumService>().isPremium) {
        context.read<AppState>().notePartnerJustLinked();
      }
      Navigator.of(context).pop(status);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'check the connection and try again'.tr;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Which of the three pictures the sheet is showing — each swap below
    // is keyed on it, so moving from "get a code" to the code itself (or
    // to typing one in) is a soft cross-fade with the sheet easing to its
    // new height, not a cut.
    final view = _entering ? 'enter' : (_pendingCode != null ? 'code' : 'start');

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.dashedBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('link a partner'.tr, style: SeenlyText.serif(italic: true, size: 16)),
              const SizedBox(height: 6),
              Text(
                'once linked, evenings you plan together show up on both of your co-viewing screens.'.tr,
                style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
              ),
              const SizedBox(height: 18),
              SoftSwap(
                alignment: Alignment.topCenter,
                rise: 0.03,
                child: KeyedSubtree(
                  key: ValueKey<String>(view),
                  child: switch (view) {
                    'enter' => _enterCodeView(),
                    'code' => _showCodeView(),
                    _ => _startView(),
                  },
                ),
              ),
              SoftSwap(
                rise: 0.3,
                child: _error == null
                    ? const SizedBox(key: ValueKey<String>('no-error'), width: double.infinity)
                    : Padding(
                        key: ValueKey<String>(_error!),
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_error!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The button label, or the loader while [_busy] — swapped softly.
  Widget _buttonFace(String label) => SoftSwap(
        alignment: Alignment.center,
        child: _busy
            ? ThemedLoadingIndicator(
                key: const ValueKey<String>('busy'),
                strokeWidth: 2,
                color: SeenlyPalette.accentOnAccent,
              )
            : Text(
                label,
                key: const ValueKey<String>('label'),
                style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent),
              ),
      );

  Widget _primaryButton({required String label, required VoidCallback onTap}) => SizedBox(
        width: double.infinity,
        child: PressScale(
          onTap: _busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: SeenlyPalette.accent,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: _buttonFace(label),
          ),
        ),
      );

  Widget _startView() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _primaryButton(label: 'get a code'.tr, onTap: _generateCode),
          const SizedBox(height: 10),
          Center(
            child: PressScale(
              onTap: () => setState(() => _entering = true),
              child: Text(
                'have a code instead?'.tr,
                style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      );

  Widget _showCodeView() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CodeReveal(code: _pendingCode!),
          const SizedBox(height: 8),
          Text(
            'send this to your partner — it\'s waiting for them to enter it.'.tr,
            style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 10),
          Center(
            child: PressScale(
              onTap: () => setState(() => _entering = true),
              child: Text(
                'have a code instead?'.tr,
                style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      );

  Widget _enterCodeView() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: SeenlyText.mono(size: 16, weight: FontWeight.w600),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'CODE12'.tr,
              filled: true,
              fillColor: SeenlyPalette.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _primaryButton(label: 'link up'.tr, onTap: _submitJoin),
        ],
      );
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DateChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Choosing a chip fades its fill and text colour over and lifts it
    // with a soft glow, rather than flipping instantly; the press itself
    // dips slightly (PressScale).
    const fade = Duration(milliseconds: 240);
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: fade,
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent : SeenlyPalette.background,
          borderRadius: BorderRadius.circular(18),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: SeenlyPalette.accent.withOpacity(0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: AnimatedDefaultTextStyle(
          duration: fade,
          curve: Curves.easeOutCubic,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SeenlyText.mono(
            size: 11.5,
            color: selected ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted,
            weight: FontWeight.w600,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// An always-visible inline month calendar, in place of the platform's
/// own date picker dialog — a whole extra sheet-on-a-sheet felt heavier
/// than the ritual needed, and a static "pick a date" chip gave no
/// sense of *when* things sit relative to each other the way a real
/// calendar grid does at a glance. The quick chips above stay for the
/// one-tap cases; this is for everything else, always in view rather
/// than hidden behind a tap.
class _MiniCalendar extends StatefulWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;
  const _MiniCalendar({required this.selected, required this.onSelected});

  @override
  State<_MiniCalendar> createState() => _MiniCalendarState();
}

class _MiniCalendarState extends State<_MiniCalendar> {
  late DateTime _visibleMonth;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  // Nominative form for a standalone calendar heading ("Январь 2026") —
  // a different case than the genitive month names in
  // screens/profile/level_detail_screen.dart's "since ___" line, so kept
  // separate rather than routed through the generic word-for-word .tr
  // table.
  static const _monthNamesRu = [
    'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
  ];
  static const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _weekdayLabelsRu = ['П', 'В', 'С', 'Ч', 'П', 'С', 'В'];

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(widget.selected.year, widget.selected.month);
  }

  @override
  void didUpdateWidget(covariant _MiniCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A quick chip above (today/tomorrow/weekend) can move the
    // selection into a different month than the one currently shown —
    // follow it so the highlighted day is never scrolled off-screen.
    if (widget.selected.year != oldWidget.selected.year ||
        widget.selected.month != oldWidget.selected.month) {
      _visibleMonth = DateTime(widget.selected.year, widget.selected.month);
    }
  }

  DateTime get _todayDay {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // Same 365-day horizon the old platform date picker used.
  DateTime get _maxDate => _todayDay.add(const Duration(days: 365));

  bool get _canGoBack => _visibleMonth.isAfter(DateTime(_todayDay.year, _todayDay.month));

  bool get _canGoForward {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    return !next.isAfter(DateTime(_maxDate.year, _maxDate.month));
  }

  void _changeMonth(int delta) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta));
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    // Monday-first grid (0 = Monday .. 6 = Sunday), matching the
    // weekday header below.
    final leadingBlanks = (firstOfMonth.weekday + 6) % 7;
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _CalendarNavArrow(icon: Icons.chevron_left, enabled: _canGoBack, onTap: () => _changeMonth(-1)),
              Expanded(
                child: Center(
                  // The month name changes softly as you page through.
                  child: SoftSwap(
                    alignment: Alignment.center,
                    child: Text(
                      '${(LocaleService.appIsRussian ? _monthNamesRu : _monthNames)[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                      key: ValueKey<int>(_visibleMonth.year * 12 + _visibleMonth.month),
                      style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              _CalendarNavArrow(icon: Icons.chevron_right, enabled: _canGoForward, onTap: () => _changeMonth(1)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: (LocaleService.appIsRussian ? _weekdayLabelsRu : _weekdayLabels)
                .map((l) => Expanded(
                      child: Center(
                        child: Text(
                          l,
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint, weight: FontWeight.w600),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 2),
          // Paging months slides the whole grid the way you're going
          // (later months from the right, earlier from the left), and the
          // card eases to the new height when one month has a sixth row.
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: StepSwitcher(
              step: _visibleMonth.year * 12 + _visibleMonth.month,
              shift: 0.09,
              duration: const Duration(milliseconds: 320),
              child: SizedBox(
                width: double.infinity,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 6),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
                  itemCount: leadingBlanks + daysInMonth,
                  itemBuilder: (context, i) {
                    if (i < leadingBlanks) return const SizedBox.shrink();
                    final day = i - leadingBlanks + 1;
                    final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
                    final disabled = date.isBefore(_todayDay) || date.isAfter(_maxDate);
                    final isSelected = _sameDay(date, widget.selected);
                    final isToday = _sameDay(date, _todayDay);
                    return Padding(
                      padding: const EdgeInsets.all(2),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: disabled ? null : () => widget.onSelected(date),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // "Today" ring — fades out once that day is the
                            // selected one.
                            Positioned.fill(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: isToday && !isSelected ? 1 : 0,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: SeenlyPalette.accent, width: 1.2),
                                  ),
                                ),
                              ),
                            ),
                            // The selection: a filled circle that grows out
                            // of the middle of the day with a small
                            // overshoot when picked, and shrinks back when
                            // another day takes over.
                            Positioned.fill(
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutBack,
                                scale: isSelected ? 1.0 : 0.5,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 180),
                                  opacity: isSelected ? 1 : 0,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: SeenlyPalette.accent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: SeenlyPalette.accent.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: SeenlyText.mono(
                                size: 12,
                                weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: disabled
                                    ? SeenlyPalette.placeholder
                                    : isSelected
                                        ? SeenlyPalette.accentOnAccent
                                        : SeenlyPalette.ink,
                              ),
                              child: Text('$day'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarNavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _CalendarNavArrow({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: enabled ? onTap : null,
      scaleTo: 0.85,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            icon,
            key: ValueKey<bool>(enabled),
            size: 18,
            color: enabled ? SeenlyPalette.ink : SeenlyPalette.placeholder,
          ),
        ),
      ),
    );
  }
}