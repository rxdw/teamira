import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cinema_showtimes.dart';
import '../../data/coach_routes.dart';
import '../../data/garden_tasks.dart';
import '../../data/launch_sites.dart';
import '../../data/world_cities.dart';
import '../../models/media_item.dart';
import '../../services/geo_city_service.dart';
import '../../services/journey_prefs_service.dart';
import '../../services/log_theme_service.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/journey_real_map.dart';
import 'journey_progress_screen.dart';
import '../../services/app_translations.dart';
import '../../theme/clay_kit.dart';
import '../../services/locale_service.dart';

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

class _JourneyOption {
  final String title;
  final int minutes;
  // How the leg's caption reads for a given duration ("1h 45m on the
  // rails", ...). A function rather than a fixed string so the same
  // option can be re-stamped with a different duration (see [withMinutes])
  // without its caption going stale.
  final String Function(int minutes) _detailFor;
  String get detail => _detailFor(minutes);
  // Real destination coordinates — coach and ticket land here (a city,
  // a cinema); garden lands here too (the inner point of its walk).
  final double? destLat;
  final double? destLng;
  // Only ever set for the garden theme — each garden option carries
  // its own gate coordinates, since garden's "from" isn't a single
  // shared city the way coach/ticket's is (see _JourneySelectScreenState._origin).
  final double? originLat;
  final double? originLng;
  // Theme-specific "where this leg arrives" key — destination city
  // name (coach), cinema code (ticket), or garden name (garden). Saved
  // as the next episode's transfer point once this leg finishes; see
  // series_route_state.dart and journey_transfer_service.dart.
  final String matchKey;
  const _JourneyOption({
    required this.title,
    required String Function(int minutes) detailFor,
    required this.minutes,
    required this.matchKey,
    this.destLat,
    this.destLng,
    this.originLat,
    this.originLng,
  }) : _detailFor = detailFor;

  /// The same place, but with [minutes] as its duration — the caption
  /// follows. Used to make sure one option always lasts exactly as long
  /// as the title (see _JourneySelectScreenState._withExactRuntimeOption).
  _JourneyOption withMinutes(int minutes) => _JourneyOption(
        title: title,
        detailFor: _detailFor,
        minutes: minutes,
        matchKey: matchKey,
        destLat: destLat,
        destLng: destLng,
        originLat: originLat,
        originLng: originLng,
      );
}

/// Which of the from/to panel's two rows is currently expanded inline
/// (see _buildFromToPanel) — an accordion, so opening one smoothly
/// closes the other rather than letting both sprawl open at once.
enum _Panel { none, from, to }

/// The new "watching now" step between [WatchingChoiceScreen] and
/// [JourneyProgressScreen] — pick something whose own length to measure
/// tonight's runtime against. A live map up top always shows the
/// currently-selected route (see _buildMap), and the from/to card below
/// it expands each of its two rows in place — a search field for
/// "from" (coach/ticket only), the route list for "to" — rather than
/// pushing a separate full-screen picker, the way a ride-hailing app's
/// route sheet behaves rather than a classic form.
class JourneySelectScreen extends StatefulWidget {
  final MediaItem item;
  final LogTheme theme;
  // Set together only when picking a route for one specific episode of
  // a series (see ActiveJourney's own doc comment) — both null picks a
  // route for the title as a whole, same as before this existed.
  final int? season;
  final int? episode;
  // See WatchingChoiceScreen's own doc comment — carried through to
  // JourneyProgressScreen so the rating screen at the end of this leg
  // starts with the same pre-checked toggle.
  final bool initialWatchedWithPartner;
  const JourneySelectScreen({
    super.key,
    required this.item,
    required this.theme,
    this.season,
    this.episode,
    this.initialWatchedWithPartner = false,
  });

  @override
  State<JourneySelectScreen> createState() => _JourneySelectScreenState();
}

class _JourneySelectScreenState extends State<JourneySelectScreen> {
  final _prefs = JourneyPrefsService();

  // Inline "from" search — replaces a separate CityPickerScreen push
  // with the same live Nominatim search + offline worldCities fallback,
  // just expanded in place under the "from" row (see
  // _buildInlineCitySearch).
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<GeoCity> _searchResults = const [];
  bool _searching = false;

  // Default departure city for the coach theme — changeable by
  // expanding the "from" row. The ticket theme shares this same
  // changeable-origin idea, just defaulting to wherever the person
  // last flew from (see _init) rather than a fixed city.
  GeoCity _origin = _defaultOrigin();
  List<_JourneyOption> _options = [];
  int _selected = 0; // closest match is always index 0 — see the data files' own closeness sort
  bool _loadingOptions = true;
  // Garden theme only — purely atmospheric context for the "still just
  // past the gates of ___" row, see _GardenOriginRow.
  String? _lastGarden;
  _Panel _panel = _Panel.none;

  static GeoCity _defaultOrigin() {
    final v = findCityByName('London');
    return GeoCity(name: v.name, country: v.country, lat: v.lat, lng: v.lng);
  }

  bool get _usesChangeableOrigin => widget.theme == LogTheme.coach || widget.theme == LogTheme.ticket;

  _JourneyOption? get _current => (_selected >= 0 && _selected < _options.length) ? _options[_selected] : null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (widget.theme == LogTheme.ticket) {
      final saved = await _prefs.loadLastOrigin();
      if (saved != null && mounted) _origin = saved;
    } else if (widget.theme == LogTheme.garden) {
      _lastGarden = await _prefs.loadLastGarden();
    }
    await _loadOptions();
  }

  int get _filmMinutes => widget.item.runtimeMinutes ?? _runtimeFallback[widget.item.mediaType] ?? 100;

  void _togglePanel(_Panel p) {
    setState(() {
      _panel = _panel == p ? _Panel.none : p;
      if (_panel == _Panel.from) {
        _searchController.clear();
        _searchResults = const [];
        _searching = false;
      }
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _runCitySearch(q));
  }

  Future<void> _runCitySearch(String q) async {
    final live = await GeoCityService.search(q);
    if (!mounted) return;
    if (live.isNotEmpty) {
      setState(() {
        _searchResults = live;
        _searching = false;
      });
      return;
    }
    // No network, or nothing came back — fall back to the small
    // bundled list so the picker still works offline.
    final ql = q.toLowerCase();
    final local = worldCities
        .where((c) => c.name.toLowerCase().contains(ql) || c.country.toLowerCase().contains(ql))
        .map((c) => GeoCity(name: c.name, country: c.country, lat: c.lat, lng: c.lng))
        .toList();
    setState(() {
      _searchResults = local;
      _searching = false;
    });
  }

  Future<void> _pickOrigin(GeoCity city) async {
    setState(() {
      _origin = city;
      _panel = _Panel.none;
    });
    if (widget.theme == LogTheme.ticket) await _prefs.saveLastOrigin(city);
    await _loadOptions();
  }

  void _pickOption(int i) {
    setState(() {
      _selected = i;
      _panel = _Panel.none;
    });
  }

  Future<void> _loadOptions() async {
    setState(() => _loadingOptions = true);
    final options = _withExactRuntimeOption(await _buildOptions());
    if (!mounted) return;
    setState(() {
      _options = options;
      _selected = 0;
      _loadingOptions = false;
    });
  }

  /// Guarantees the list always has a leg that lasts *exactly* as long as
  /// the title — the whole point of the journey is that the trip and the
  /// film end together. The bundled routes / gardens / cinemas / launch
  /// sites (and the estimated train and flight times from an arbitrary
  /// "from" city) only ever come *close* to a given runtime, so when
  /// nothing already matches, the closest option (index 0 — every
  /// _buildOptions branch sorts closest-first) is re-stamped with the
  /// runtime. The place is real, its time is a little off — deliberately:
  /// a matching duration matters more here than the exact real-world
  /// travel time. Same for all four themes, since they all come through
  /// here.
  List<_JourneyOption> _withExactRuntimeOption(List<_JourneyOption> options) {
    if (options.isEmpty) return options;
    final film = _filmMinutes;
    final exact = options.indexWhere((o) => o.minutes == film);
    if (exact == 0) return options;
    if (exact > 0) {
      // Already there, just not first — bring it to the front so it's the
      // one preselected.
      return [options[exact], ...options.sublist(0, exact), ...options.sublist(exact + 1)];
    }
    return [options.first.withMinutes(film), ...options.sublist(1)];
  }

  Future<List<_JourneyOption>> _buildOptions() async {
    switch (widget.theme) {
      case LogTheme.coach:
        final routes = await closestRoutesFromCityLive(
          origin: _origin,
          runtimeMinutes: widget.item.runtimeMinutes,
          mediaType: widget.item.mediaType,
        );
        return routes
            .map((r) => _JourneyOption(
                  title: r.destCity,
                  detailFor: (m) => LocaleService.pick('${_fmtDuration(m)} на рельсах', '${_fmtDuration(m)} on the rails'),
                  minutes: r.minutes,
                  matchKey: r.destCity,
                  destLat: r.destLat,
                  destLng: r.destLng,
                ))
            .toList();
      case LogTheme.garden:
        return closestGardens(runtimeMinutes: widget.item.runtimeMinutes, mediaType: widget.item.mediaType)
            .map((g) => _JourneyOption(
                  title: g.name,
                  detailFor: (m) => '${_fmtDuration(m)} walk · ${g.city}, ${g.country}',
                  minutes: g.minutes,
                  matchKey: g.name,
                  originLat: g.gateLat,
                  originLng: g.gateLng,
                  destLat: g.innerLat,
                  destLng: g.innerLng,
                ))
            .toList();
      case LogTheme.ticket:
        return closestCinemas(
          origin: _origin,
          runtimeMinutes: widget.item.runtimeMinutes,
          mediaType: widget.item.mediaType,
        )
            .map((o) => _JourneyOption(
                  title: '${o.cinema.name}, ${o.cinema.city}',
                  detailFor: (m) => '${_fmtDuration(m)} flight · ${o.cinema.country}',
                  minutes: o.minutes,
                  matchKey: o.cinema.code,
                  destLat: o.cinema.lat,
                  destLng: o.cinema.lng,
                ))
            .toList();
      case LogTheme.shuttle:
        return closestLaunchSites(runtimeMinutes: widget.item.runtimeMinutes, mediaType: widget.item.mediaType)
            .map((s) => _JourneyOption(
                  title: s.name,
                  detailFor: (m) => LocaleService.pick('${_fmtDuration(m)} до площадки · ${s.city}, ${s.country}', '${_fmtDuration(m)} to the pad · ${s.city}, ${s.country}'),
                  minutes: s.minutes,
                  matchKey: s.name,
                  originLat: s.gateLat,
                  originLng: s.gateLng,
                  destLat: s.padLat,
                  destLng: s.padLng,
                ))
            .toList();
    }
  }

  String get _headline => switch (widget.theme) {
        LogTheme.coach => 'choose your route'.tr,
        LogTheme.garden => 'choose your garden'.tr,
        LogTheme.ticket => 'choose your cinema'.tr,
        LogTheme.shuttle => 'choose your launch site'.tr,
      };

  String get _departLabel => switch (widget.theme) {
        LogTheme.coach => 'depart'.tr,
        LogTheme.garden => 'through the gate'.tr,
        LogTheme.ticket => 'board the flight'.tr,
        LogTheme.shuttle => 'clear for launch'.tr,
      };

  Color get _accent => switch (widget.theme) {
        LogTheme.coach => SeenlyPalette.periwinkle,
        LogTheme.garden => SeenlyPalette.sage,
        LogTheme.ticket => SeenlyPalette.coral,
        LogTheme.shuttle => SeenlyPalette.periwinkle,
      };

  IconData get _markerIcon => switch (widget.theme) {
        LogTheme.coach => Icons.train,
        LogTheme.garden => Icons.directions_walk,
        LogTheme.ticket => Icons.flight,
        LogTheme.shuttle => Icons.rocket_launch,
      };

  JourneyVehicle get _vehicle => switch (widget.theme) {
        LogTheme.coach => JourneyVehicle.train,
        LogTheme.garden => JourneyVehicle.walk,
        LogTheme.ticket => JourneyVehicle.plane,
        LogTheme.shuttle => JourneyVehicle.rocket,
      };

  double? get _mapOriginLat => _usesChangeableOrigin ? _origin.lat : _current?.originLat;
  double? get _mapOriginLng => _usesChangeableOrigin ? _origin.lng : _current?.originLng;

  bool get _mapReady =>
      !_loadingOptions &&
      _current != null &&
      _mapOriginLat != null &&
      _mapOriginLng != null &&
      _current!.destLat != null &&
      _current!.destLng != null;

  Future<void> _depart() async {
    final option = _current;
    if (_loadingOptions || option == null) return;
    final label = _usesChangeableOrigin ? '${_origin.name} → ${option.title}' : option.title;
    if (widget.theme == LogTheme.garden) await _prefs.saveLastGarden(option.title);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => JourneyProgressScreen(
          item: widget.item,
          theme: widget.theme,
          routeLabel: label,
          routeDetail: option.detail,
          routeMinutes: option.minutes,
          originLat: _usesChangeableOrigin ? _origin.lat : option.originLat,
          originLng: _usesChangeableOrigin ? _origin.lng : option.originLng,
          destLat: option.destLat,
          destLng: option.destLng,
          season: widget.season,
          episode: widget.episode,
          destMatchKey: option.matchKey,
          initialWatchedWithPartner: widget.initialWatchedWithPartner,
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      '${widget.item.title.display} · ${_fmtDuration(_filmMinutes)}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)
                          .copyWith(letterSpacing: 0.4),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
                children: [
                  Text(_headline, style: SeenlyText.serif(italic: true, size: 17)),
                  const SizedBox(height: 14),
                  _buildMap(),
                  const SizedBox(height: 18),
                  _buildFromToPanel(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: GestureDetector(
                onTap: _depart,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: (_loadingOptions || _current == null) ? _accent.withOpacity(0.4) : _accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(_departLabel,
                      style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600, color: SeenlyPalette.paper)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // A real map, right where the person is choosing — not a separate
  // step after committing. It always reflects whatever's currently
  // selected: change "from" or tap a different "to" option below and
  // the route redraws immediately. The ValueKey forces a fresh map
  // state (and so a fresh camera fit) whenever the actual coordinates
  // change, rather than leaving the camera parked on the old route.
  Widget _buildMap() {
    return SizedBox(
      height: 210,
      child: _mapReady
          ? JourneyRealMap(
              key: ValueKey('${_mapOriginLat}_${_mapOriginLng}_${_current!.destLat}_${_current!.destLng}'),
              originLat: _mapOriginLat!,
              originLng: _mapOriginLng!,
              destLat: _current!.destLat!,
              destLng: _current!.destLng!,
              originLabel: _usesChangeableOrigin ? _origin.name : 'gate',
              destLabel: _current!.title,
              progress: 0,
              accent: _accent,
              markerIcon: _markerIcon,
              vehicle: _vehicle,
              borderRadius: 18,
            )
          : Container(
              decoration: ClayBoxDecoration(
                boxShadow: SeenlyPalette.flatCardShadow,color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(18)),
              alignment: Alignment.center,
              child: _loadingOptions
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                    )
                  : Text('no route yet'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            ),
    );
  }

  // The "from" / "to" card — each row is its own accordion panel:
  // tapping one smoothly opens its content in place (AnimatedSize) and
  // closes the other, rather than either navigating away or dumping
  // everything open at once.
  Widget _buildFromToPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_usesChangeableOrigin) ...[
            _PanelRow(
              icon: Icons.circle_outlined,
              iconColor: SeenlyPalette.periwinkle,
              label: 'from'.tr,
              value: _origin.name,
              expanded: _panel == _Panel.from,
              onTap: () => _togglePanel(_Panel.from),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _panel == _Panel.from ? _buildInlineCitySearch() : const SizedBox.shrink(),
            ),
            _dashedDivider(),
          ] else if (widget.theme == LogTheme.garden) ...[
            _GardenOriginRow(lastGarden: _lastGarden),
            _dashedDivider(),
          ],
          _PanelRow(
            icon: Icons.adjust,
            iconColor: SeenlyPalette.inkFaint,
            label: 'to'.tr,
            value: _loadingOptions ? 'finding routes…'.tr : (_current?.title ?? '—'),
            detail: (!_loadingOptions && _current != null) ? _fmtDuration(_current!.minutes) : null,
            expanded: _panel == _Panel.to,
            onTap: _loadingOptions ? null : () => _togglePanel(_Panel.to),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _panel == _Panel.to ? _buildOptionsList() : const SizedBox.shrink(),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _dashedDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: List.generate(
          12,
          (i) => Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              height: 1,
              color: SeenlyPalette.dashedBorder,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineCitySearch() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: SeenlyPalette.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SeenlyPalette.border),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 14, color: SeenlyPalette.inkFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    style: SeenlyText.bodyText.copyWith(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'any city in the world'.tr,
                      hintStyle: SeenlyText.bodyText.copyWith(color: SeenlyPalette.placeholder, fontSize: 13),
                    ),
                  ),
                ),
                if (_searching)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: SeenlyPalette.inkFaint),
                  ),
              ],
            ),
          ),
          if (_searchResults.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: 4),
                itemCount: _searchResults.length,
                itemBuilder: (context, i) {
                  final city = _searchResults[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(city.name, style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600)),
                    subtitle: city.country == null
                        ? null
                        : Text(city.country!, style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                    onTap: () => _pickOrigin(city),
                  );
                },
              ),
            )
          else if (_searchController.text.trim().isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('no matches'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionsList() {
    if (_loadingOptions) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
            const SizedBox(width: 10),
            Text('finding nearby routes…'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('closest matches to tonight'.tr,
                style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
          ),
          for (int i = 0; i < _options.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _OptionCard(
              option: _options[i],
              filmMinutes: _filmMinutes,
              accent: _accent,
              selected: _selected == i,
              recommended: i == 0,
              onTap: () => _pickOption(i),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single tappable row in the from/to card — "from" (coach/ticket
/// only, opens an inline city search) or "to" (opens the inline route
/// list). The chevron flips to point up while its own panel is open,
/// same convention as any collapsible section.
class _PanelRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? detail;
  final bool expanded;
  final VoidCallback? onTap;
  const _PanelRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.detail,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 3), child: Icon(icon, size: 12, color: iconColor)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                  const SizedBox(height: 2),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
                ],
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(detail!, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down, size: 16, color: SeenlyPalette.inkFaint),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The garden theme's stand-in for a changeable "from" row — there's no
/// single shared "from" to change here (each garden option carries its
/// own real gate, see data/garden_tasks.dart), so this is purely
/// atmospheric continuity: a nod to wherever the last walk left off,
/// per the spec's "default departure is the main gate of the
/// last-visited garden" — not an interactive control, no chevron.
class _GardenOriginRow extends StatelessWidget {
  final String? lastGarden;
  const _GardenOriginRow({required this.lastGarden});

  @override
  Widget build(BuildContext context) {
    final text = lastGarden != null
        ? LocaleService.pick('мы всё ещё у ворот: $lastGarden', 'still just past the gates of $lastGarden')
        : 'the gate is open — choose where to wander tonight'.tr;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.eco, size: 12, color: SeenlyPalette.sage)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: SeenlyText.serif(size: 13, italic: true))),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final _JourneyOption option;
  final int filmMinutes;
  final Color accent;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;
  const _OptionCard({
    required this.option,
    required this.filmMinutes,
    required this.accent,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final diff = option.minutes - filmMinutes;
    final closeEnough = diff <= 5; // "shorter, or close enough it barely matters" — see spec's own framing
    final badgeText = diff <= 0 ? '−${_fmtDuration(-diff)}' : '+${_fmtDuration(diff)}';
    final badgeBg = closeEnough ? SeenlyPalette.sage.withOpacity(0.16) : SeenlyPalette.pink.withOpacity(0.14);
    final badgeFg = closeEnough ? const Color(0xFF5C6E52) : const Color(0xFF8C3255);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? accent : Colors.transparent, width: 1.5),
          boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.title, style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(option.detail, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
                  child: Text(badgeText, style: SeenlyText.mono(size: 9.5, color: badgeFg)),
                ),
              ],
            ),
            if (recommended) ...[
              const SizedBox(height: 7),
              Text('closest match · recommended'.tr, style: SeenlyText.mono(size: 8, color: accent)),
            ],
          ],
        ),
      ),
    );
  }
}
