import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/partner_status.dart';
import '../models/planned_evening.dart';
import '../models/watchlist_entry.dart';
import '../services/api_client.dart';
import '../services/evening_plan_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'tear_ticket_confirm.dart';
import 'themed_loading_indicator.dart';
import 'themed_poster_tile.dart';
import '../services/app_translations.dart';
import '../services/locale_service.dart';

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
Future<void> showPlanEveningSheet(
  BuildContext context, {
  bool coViewingByDefault = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _PlanEveningSheet(coViewingByDefault: coViewingByDefault),
    ),
  );
}

class _PlanEveningSheet extends StatefulWidget {
  final bool coViewingByDefault;
  const _PlanEveningSheet({required this.coViewingByDefault});

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

  @override
  void initState() {
    super.initState();
    _coViewing = widget.coViewingByDefault;
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

  Future<void> _confirm() async {
    final picked = _picked;
    if (picked == null) return;
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
      coViewing: _coViewing,
      partnerUsername: _coViewing ? _partnerStatus?.partnerUsername : null,
      createdAt: DateTime.now(),
    );
    await context.read<EveningPlanService>().planEvening(evening);
    // Co-viewing + actually linked: mirror this onto the shared
    // co-viewing list so the partner sees the same scheduled evening on
    // their own side too, not just as a ticket sitting on this device
    // (see PartnerService.planCoViewing). Best-effort — the personal
    // ticket above is already saved either way, so a sync hiccup here
    // shouldn't block "get a ticket" from finishing.
    if (_coViewing && (_partnerStatus?.linked ?? false)) {
      try {
        await context.read<AppState>().partner.planCoViewing(
              picked,
              date: DateTime(_date.year, _date.month, _date.day),
              hour: _time?.hour,
              minute: _time?.minute,
            );
      } catch (_) {}
    }
    if (!mounted) return;
    // A short beat so "ticket's yours" actually gets read before the
    // sheet closes out from under it.
    await Future.delayed(const Duration(milliseconds: 650));
    if (mounted) Navigator.of(context).pop();
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
                      // (below) always goes.
                      onPressed: () => _step > 0
                          ? setState(() => _step -= 1)
                          : Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        _step == 0
                            ? 'plan an evening'
                            : _step == 1
                                ? 'when?'
                                : 'get your ticket',
                        style: SeenlyText.serif(italic: true, size: 17),
                      ),
                    ),
                    GestureDetector(
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: _step == 0
                      ? _titleStep()
                      : _step == 1
                          ? _dateStep()
                          : _confirmStep(),
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
        Expanded(child: hasQuery ? _searchResultsGrid() : _shelfGrid()),
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
      return GestureDetector(
        onTap: _openInvitePartnerSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: SeenlyPalette.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SeenlyPalette.border),
          ),
          child: Row(
            children: [
              Icon(Icons.favorite_border, size: 17, color: SeenlyPalette.inkFaint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'no partner linked yet — invite one to plan evenings together'.tr,
                  style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: SeenlyPalette.inkFaint),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _coViewing = !_coViewing),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _coViewing ? SeenlyPalette.accent.withOpacity(0.12) : SeenlyPalette.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _coViewing ? SeenlyPalette.accent : SeenlyPalette.border),
        ),
        child: Row(
          children: [
            Icon(
              _coViewing ? Icons.favorite : Icons.favorite_border,
              size: 17,
              color: _coViewing ? SeenlyPalette.accent : SeenlyPalette.inkFaint,
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
    if (_loadingShelf) {
      return Center(child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent));
    }
    final shelf = _shelf ?? const [];
    if (shelf.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'nothing on your plan-to-watch shelf yet — search for a title above, or add a few to that shelf first.'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
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
        return ThemedPosterTile(
          title: e.displayTitle,
          posterUrl: e.posterUrl,
          mediaType: e.mediaType,
          fallbackColor: SeenlyPalette.gridColorFor(i),
          onTap: () => _pick(e),
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
    if (_searching) {
      return Center(child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent));
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'nothing found'.tr,
          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
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
        return ThemedPosterTile(
          title: item.title.display,
          posterUrl: item.posterUrl,
          mediaType: item.mediaType,
          fallbackColor: SeenlyPalette.gridColorFor(i),
          onTap: () => _pickMedia(item),
        );
      },
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The pick, front and center — this step is about committing
          // to a date for *this*, so it gets the same "hero poster"
          // treatment the title detail screen gives a title, not the
          // small identifier chip a form field would use.
          Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: SeenlyPalette.softShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  width: 220,
                  height: 320,
                  child: picked.posterUrl != null && picked.posterUrl!.isNotEmpty
                      ? Image.network(
                          picked.posterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: SeenlyPalette.mediaColor(picked.mediaType),
                            alignment: Alignment.center,
                            child: Icon(Icons.movie_creation_outlined,
                                color: SeenlyPalette.paper, size: 40),
                          ),
                        )
                      : Container(
                          color: SeenlyPalette.mediaColor(picked.mediaType),
                          alignment: Alignment.center,
                          child: Icon(Icons.movie_creation_outlined,
                              color: SeenlyPalette.paper, size: 40),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              picked.title.display,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.serif(italic: true, size: 19, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 28),
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
          const SizedBox(height: 16),
          _MiniCalendar(
            selected: _date,
            onSelected: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: 22),
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
          GestureDetector(
            onTap: _pickCustomTime,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: SeenlyPalette.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _time != null && !_isAnyTimePreset() ? SeenlyPalette.accent : SeenlyPalette.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: SeenlyPalette.inkFaint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _time == null ? 'no exact time — tap to pick one' : _time!.format(context),
                      style: SeenlyText.serif(size: 13),
                    ),
                  ),
                  if (_time != null)
                    GestureDetector(
                      onTap: () => setState(() => _time = null),
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 14, color: SeenlyPalette.inkFaint),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (linked) ...[
            const SizedBox(height: 20),
            _coViewingToggle(),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => setState(() => _step = 2),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Text('continue'.tr,
                    style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmStep() {
    final picked = _picked!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${picked.title.display} · ${_formatDate(_date)}'
            '${_time != null ? ' · ${_time!.format(context)}' : ''}'
            '${_coViewing ? ' · with ${_partnerStatus?.partnerUsername ?? 'your partner'}' : ''}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
          ),
          const SizedBox(height: 22),
          TearTicketConfirm(
            label: 'pull apart to get your ticket'.tr,
            confirmedLabel: 'it\'s yours'.tr,
            accent: SeenlyPalette.accent,
            onConfirmed: _confirm,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';
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
        _error = "couldn't get a code just now — try again";
      });
    }
  }

  Future<void> _submitJoin() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'codes are 6 characters');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await context.read<AppState>().partner.join(code);
      if (!mounted) return;
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
        _error = 'check the connection and try again';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
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
            if (!_entering) ...[
              if (_pendingCode != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _pendingCode!,
                    style: SeenlyText.mono(size: 22, weight: FontWeight.w700, color: SeenlyPalette.accent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'send this to your partner — it\'s waiting for them to enter it.'.tr,
                  style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _busy ? null : _generateCode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.accent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      alignment: Alignment.center,
                      child: _busy
                          ? ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent)
                          : Text('get a code'.tr,
                              style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent)),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Center(
                child: GestureDetector(
                  onTap: () => setState(() => _entering = true),
                  child: Text(
                    'have a code instead?'.tr,
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint, weight: FontWeight.w600),
                  ),
                ),
              ),
            ] else ...[
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
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _busy ? null : _submitJoin,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.accent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    alignment: Alignment.center,
                    child: _busy
                        ? ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent)
                        : Text('link up'.tr,
                            style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent)),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DateChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent : SeenlyPalette.background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SeenlyText.mono(
            size: 11.5,
            color: selected ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted,
            weight: FontWeight.w600,
          ),
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
                  child: Text(
                    '${(LocaleService.appIsRussian ? _monthNamesRu : _monthNames)[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                    style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600),
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
          GridView.builder(
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
                  onTap: disabled ? null : () => widget.onSelected(date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      color: isSelected ? SeenlyPalette.accent : Colors.transparent,
                      shape: BoxShape.circle,
                      border: isToday && !isSelected
                          ? Border.all(color: SeenlyPalette.accent, width: 1.2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$day',
                      style: SeenlyText.mono(
                        size: 12,
                        weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: disabled
                            ? SeenlyPalette.placeholder
                            : isSelected
                                ? SeenlyPalette.accentOnAccent
                                : SeenlyPalette.ink,
                      ),
                    ),
                  ),
                ),
              );
            },
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
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: enabled ? SeenlyPalette.ink : SeenlyPalette.placeholder),
      ),
    );
  }
}