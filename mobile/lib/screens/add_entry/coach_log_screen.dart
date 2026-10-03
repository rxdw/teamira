import '../partner/room/together_verdict_card.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/coach_routes.dart';
import '../../models/diary_entry.dart';
import '../../models/media_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/together_wrapped_teaser.dart';
import '../../widgets/boarding_drop_overlay.dart';
import '../../widgets/boarding_pass.dart';
import '../../widgets/coach_submit_button.dart';
import '../../widgets/departure_scenes.dart';
import '../../widgets/light_bloom.dart';
import '../../widgets/log_flow_kit.dart';
import '../../widgets/mood_tag_picker.dart' show vibePresetTags, vibePromptTitle;
import '../../widgets/review_composer.dart';
import '../../widgets/sincerity_toast.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../services/log_theme_service.dart';
import '../../widgets/achievement_unlock_overlay.dart';
import '../../widgets/level_up_celebration.dart';
import '../../widgets/favorite_toggle.dart';
import '../../widgets/verdict_rating.dart';
import '../../widgets/wow_motion.dart' show PressScale;
import '../../services/app_translations.dart';
import '../../theme/notebook_paper.dart';
import '../../widgets/saved_celebration.dart';
import '../../widgets/share_card.dart';
import '../../widgets/share_sheet.dart';
import '../../widgets/decide_motion.dart' show SecondaryActionButton;
import '../../theme/clay_kit.dart';

// This route's own verdict words — same shape VerdictRating expects
// from the cinema flow (10 entries, low to high), just spoken the way
// you'd describe an evening ride rather than a screening.
const List<String> _coachVerdictLabels = [
  'rough ride',
  'bumpy going',
  "glad that's over",
  'fine ride',
  'decent trip',
  'smooth going',
  'really good ride',
  'loved this route',
  'one for the regulars',
  'perfect journey',
];

// A quiet aside for the confirm step — the kind of small thing you'd
// notice out the window while waiting for the doors to close. One is
// picked per title (see pickAmbientLine) so it stays put on rebuilds.
const List<String> _coachAmbientLines = [
  "driver just topped off their coffee — no rush yet",
  'someone up front is already half asleep',
  'the window seat is warm from the last bit of sun',
  "radio's down low, just enough to notice",
  'a few stragglers still finding their row',
  'the road ahead looks quiet tonight',
];

/// The "Evening Route" theme's real logging flow, replacing the plain
/// form: pick a seat first, then settle the details of the ride, then
/// confirm, then watch the pass actually print itself — one continuous
/// full-screen ritual instead of a form with a decorative animation
/// bolted on after the fact. Same data as the old form (rating, mood,
/// date, note, watched-with-partner) — just gathered in the order and
/// mood of an evening coach trip rather than a settings sheet.
class CoachLogScreen extends StatefulWidget {
  final MediaItem item;
  // Set together only when this evening is one episode of a series (see
  // DiaryEntry's own doc comment on the backend) — both null logs the
  // whole title the old way. `season` alone (episode null) logs a
  // completed season instead — see finishEpisode.
  final int? season;
  final int? episode;
  // Only meaningful alongside a season-only log — how many episodes that
  // season has, so the diary row's runtime reflects the whole season
  // rather than one episode (see DiaryService.logEntry).
  final int? episodeCount;
  // Pre-checks the "watched with partner" toggle below — see
  // WatchingChoiceScreen's own doc comment for why (the co-viewing
  // planned grid's "смотрю" button opens this already knowing the
  // evening was shared).
  final bool initialWatchedWithPartner;
  const CoachLogScreen({
    super.key,
    required this.item,
    this.season,
    this.episode,
    this.episodeCount,
    this.initialWatchedWithPartner = false,
  });

  @override
  State<CoachLogScreen> createState() => _CoachLogScreenState();
}

enum _Step { seat, details, vibe, castPick, confirm, departing, pass }

enum _When { today, yesterday, custom }

class _CoachLogScreenState extends State<CoachLogScreen> with TickerProviderStateMixin {
  static const int _rows = 12;
  static const int _cols = 4; // 2-and-2, aisle down the middle
  static const List<String> _seatLetters = ['A', 'B', 'C', 'D'];
  static const int _firstRowNumber = 8;

  late final CoachRoute _route;
  late final Set<int> _taken;
  late final AnimationController _dust;
  late final AnimationController _breathe;
  late final AnimationController _preshow;
  late final List<LightMote> _motes;

  _Step _step = _Step.seat;
  int? _selectedSeat;
  int _rating = 0;
  bool _isFavorite = false;
  List<String> _moodTags = [];
  // Up to 3 cast members picked as tonight's standouts — same optional
  // aside as the cinema flow's own castPick step, just riding along
  // with the "Evening Route" theme. See cinema_log_screen.dart's
  // _buildCastPickStep for the fuller doc comment on the pattern.
  List<CastMember> _favoriteCast = [];
  _When _when = _When.today;
  DateTime? _customDate;
  final _noteController = TextEditingController();
  final _customTagController = TextEditingController();
  bool _watchedWithPartner = false;
  String? _partnerUsername;
  bool _saving = false;
  String? _error;
  // Stashed the moment `_confirmAndSave` succeeds, purely so the pass
  // step's share button (below) has a real logged entry to build an
  // [EveningShareCard] from — nothing before that point needs it. Named
  // distinctly from the local `_loggedEntry` used inside
  // `_confirmAndSave` itself, so that local declaration doesn't shadow
  // this field.
  DiaryEntry? _savedDiaryEntry;
  // widget.item only carries cast when it came straight off a detail
  // fetch (title screen's own GET /media/detail) — an item handed in
  // from a lighter source like the home feed or a search result never
  // has it (see MediaItem's own doc comment on the field). Rather than
  // let the cast step quietly vanish depending on which screen this
  // flow was opened from, fetch it here too whenever it's missing —
  // same best-effort fetch edit_review_sheet.dart does for a logged
  // entry, just run once up front instead of on demand.
  List<CastMember>? _fetchedCast;
  List<CastMember> get _cast => widget.item.cast.isNotEmpty ? widget.item.cast : (_fetchedCast ?? const []);

  @override
  void initState() {
    super.initState();
    _watchedWithPartner = widget.initialWatchedWithPartner;
    final item = widget.item;
    final seed = item.title.display;
    _route = routeForRuntime(runtimeMinutes: item.runtimeMinutes, mediaType: item.mediaType, seed: seed);
    _taken = seededTakenSeats(seed, _rows * _cols, salt: 0x636f6163); // 'coac'
    _motes = seededMotes(seed, 12, salt: 0x636f6163);
    _dust = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100))..repeat(reverse: true);
    // The little "please take your seat" chime that flickers up once
    // while you're still finding a spot, then dims itself back out.
    _preshow = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _preshow.forward();
    });
    _loadPartnerStatus();
    if (widget.item.cast.isEmpty) _loadCast();
  }

  Future<void> _loadCast() async {
    try {
      final detail = await context.read<AppState>().media.detail(
            mediaId: widget.item.id,
            mediaType: widget.item.mediaType,
            source: widget.item.source,
          );
      if (!mounted) return;
      setState(() => _fetchedCast = detail?.item.cast ?? []);
    } catch (_) {
      // Best-effort, same "quietly absent" degrade as everywhere else
      // optional supplementary data is fetched in this app.
      if (mounted) setState(() => _fetchedCast = []);
    }
  }

  Future<void> _loadPartnerStatus() async {
    try {
      final status = await context.read<AppState>().partner.status();
      if (!mounted) return;
      if (status.linked) setState(() => _partnerUsername = status.partnerUsername);
    } catch (_) {
      // Best-effort — just stays hidden.
    }
  }

  DateTime get _resolvedDate => switch (_when) {
        _When.today => DateTime.now(),
        _When.yesterday => DateTime.now().subtract(const Duration(days: 1)),
        _When.custom => _customDate ?? DateTime.now(),
      };

  String get _seatLabel {
    final seat = _selectedSeat;
    if (seat == null) return '—';
    final row = _firstRowNumber + seat ~/ _cols;
    final letter = _seatLetters[seat % _cols];
    return '$row$letter';
  }

  // The two outer columns (A and D) sit against the window — marked
  // with the same small glow the cinema flow gives its best seats, so
  // picking a spot on the bus carries a bit of real bus-riding
  // knowledge too.
  bool _isWindowSeat(int index) => index % _cols == 0 || index % _cols == _cols - 1;

  bool get _selectedIsWindow => _selectedSeat != null && _isWindowSeat(_selectedSeat!);

  void _chooseSeat(int index) {
    if (_taken.contains(index)) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedSeat = index);
  }

  void _goTo(_Step step) {
    HapticFeedback.selectionClick();
    setState(() => _step = step);
  }

  void _skipToConfirm() {
    if (_selectedSeat == null) {
      final total = _rows * _cols;
      final free = List.generate(total, (i) => i).where((i) => !_taken.contains(i)).toList();
      if (free.isNotEmpty) _selectedSeat = free[math.Random().nextInt(free.length)];
    }
    _goTo(_Step.confirm);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() { _when = _When.custom; _customDate = picked; });
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_moodTags.contains(tag)) {
        _moodTags = [..._moodTags]..remove(tag);
      } else {
        _moodTags = [..._moodTags, tag];
      }
    });
  }

  void _addCustomTag() {
    final raw = _customTagController.text.trim();
    if (raw.isEmpty) return;
    if (!_moodTags.contains(raw)) setState(() => _moodTags = [..._moodTags, raw]);
    _customTagController.clear();
  }

  void _toggleCastPick(CastMember member) {
    final already = _favoriteCast.any((m) => m.personId == member.personId && m.name == member.name);
    if (!already && _favoriteCast.length >= 3) return;
    setState(() {
      _favoriteCast = already
          ? _favoriteCast.where((m) => !(m.personId == member.personId && m.name == member.name)).toList()
          : [..._favoriteCast, member];
    });
  }

  Future<void> _confirmAndSave() async {
    // The train pulls out of the station the instant the button's
    // tapped — the save happens underneath it, not after it, so the
    // trip and the request finish together instead of the screen
    // sitting on a blank spinner.
    setState(() { _saving = true; _error = null; _step = _Step.departing; });
    bool failed = false;
    DiaryEntry? _loggedEntry;
    try {
      final results = await Future.wait([
        context.read<AppState>().diary.logEntry(
              item: widget.item,
              rating: _rating > 0 ? _rating : null,
              note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
              moodTags: _moodTags.isEmpty ? null : _moodTags,
              watchedAt: _resolvedDate,
              watchedWithPartner: _watchedWithPartner,
              isFavorite: _isFavorite,
              favoriteCast: _favoriteCast.isEmpty ? null : _favoriteCast,
              season: widget.season,
              episode: widget.episode,
              episodeCount: widget.episodeCount,
            ),
        Future.delayed(const Duration(milliseconds: 1500)),
      ]);
      _loggedEntry = results[0] as DiaryEntry;
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    if (failed) {
      setState(() { _saving = false; _step = _Step.confirm; _error = "couldn't save that just now — try again"; });
      return;
    }
    if (_loggedEntry != null) showSincerityToasts(context, _loggedEntry.sincerityAwarded);
    _savedDiaryEntry = _loggedEntry;
    HapticFeedback.mediumImpact();
    // A save is exactly the moment a level-up (and possibly a new
    // badge unlocking) could just have happened — refresh the cached
    // level so the thank-you mascot right below reflects it instead of
    // waiting for the next profile visit. Best-effort, never blocks.
    unawaited(context.read<AppState>().refreshLevel());
    setState(() => _saving = false);
    // The gate ritual: drag or tap to tear the pass, same physicality
    // wow-effects already worked out — the seat step's route comes
    // along so the pass matches what was shown while choosing a seat.
    await showBoardingDrop(
      context,
      title: widget.item.title.display,
      mediaType: widget.item.mediaType,
      rating: _rating > 0 ? _rating : null,
      watchedAt: _resolvedDate,
      runtimeMinutes: widget.item.runtimeMinutes,
      routeOverride: _route,
    );
    if (!mounted) return;
    setState(() => _step = _Step.pass);
  }

  // Opens the same share-card sheet as everywhere else in the app (see
  // widgets/watched_preview_sheet.dart), built straight from the entry
  // that was just logged — so "share" on this last screen isn't a
  // separate, lesser path, it's the exact same card someone would get
  // to later from the diary.
  void _shareLoggedEntry() {
    final entry = _savedDiaryEntry;
    if (entry == null) return;
    showShareCardSheet(
      context,
      card: EveningShareCard(entry: entry, fallbackColor: SeenlyPalette.mediaColor(entry.mediaType)),
      fileName: 'seenly-${entry.id}',
      shareText: 'watched "${entry.displayTitle}" — logged in seenly',
      rewardKey: 'seenly-${entry.id}',
    );
  }

  @override
  void dispose() {
    _dust.dispose();
    _breathe.dispose();
    _preshow.dispose();
    _noteController.dispose();
    _customTagController.dispose();
    super.dispose();
  }

  // Only reachable from the seat step (back chevron or system back) —
  // details/confirm still just step back internally via onPopInvoked
  // below. "Return to route" pops with null (the existing implicit
  // meaning of a plain pop here); JourneyProgressScreen now reads that
  // as "stay open, pick the ticker back up" rather than closing too.
  // "End route" pops with false, which JourneyProgressScreen still
  // reads as a real cancellation and cascades all the way out.
  void _confirmLeaveSeatStep() {
    showLeaveRouteDialog(
      context,
      routeNoun: 'route',
      onReturnToRoute: () => Navigator.of(context).pop(),
      onEndRoute: () => Navigator.of(context).pop(false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _step == _Step.pass;
    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_step == _Step.seat) {
          _confirmLeaveSeatStep();
          return;
        }
        _goTo(switch (_step) {
          _Step.details => _Step.seat,
          _Step.vibe => _Step.details,
          _Step.castPick => _Step.vibe,
          _Step.confirm => _cast.isNotEmpty ? _Step.castPick : _Step.vibe,
          _ => _Step.details,
        });
      },
      child: Scaffold(
        backgroundColor: SeenlyPalette.ink,
        body: Stack(
          children: [
            Positioned.fill(child: LogFlowBackdrop(dust: _dust, motes: _motes, tint: SeenlyPalette.mustard)),
            const Positioned.fill(child: IgnorePointer(child: EveningVignette())),
            SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(_step), child: _buildStep()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
        _Step.seat => _buildSeatStep(),
        _Step.details => _buildDetailsStep(),
        _Step.vibe => _buildVibeStep(),
        _Step.castPick => _buildCastPickStep(),
        _Step.confirm => _buildConfirmStep(),
        _Step.departing => _buildDepartingStep(),
        _Step.pass => _buildPassStep(),
      };

  // ---------------------------------------------------------------
  // Step 3.5 — the train actually pulls out of the station while the
  // evening saves underneath it.
  // ---------------------------------------------------------------
  Widget _buildDepartingStep() {
    return TrainDepartureScene(
      key: const ValueKey('departing-step'),
      routeLabel: '${_route.originCode} → ${_route.destCode}',
    );
  }

  // ---------------------------------------------------------------
  // Step 1 — find your seat. Same seat glyph the modal ritual used to
  // draw, just scaled up and given real room to breathe on a full
  // screen instead of squeezed into a 4x4 dialog.
  // ---------------------------------------------------------------
  Widget _buildSeatStep() {
    return Column(
      key: const ValueKey('seat-step'),
      children: [
        LogFlowTopBar(
          onBack: _confirmLeaveSeatStep,
          trailingLabel: 'skip'.tr,
          onTrailing: _skipToConfirm,
        ),
        CollapsingAnnouncement(
          preshow: _preshow,
          breathe: _breathe,
          text: "please fasten your seatbelt — we're pulling out shortly".tr,
          glow: SeenlyPalette.mustard,
        ),
        const SizedBox(height: 6),
        Text('find your seat'.tr,
            style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
        const SizedBox(height: 5),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _selectedSeat == null
                ? "tonight's ride"
                : _selectedIsWindow
                    ? 'cozy — seat $_seatLabel, right by the window'
                    : 'cozy — seat $_seatLabel is yours',
            key: ValueKey('$_selectedSeat-$_selectedIsWindow'),
            style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.68)),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _breathe,
          builder: (_, __) => GlowPlaque(
            text: '${_route.originCity.toUpperCase()} → ${_route.destCity.toUpperCase()}',
            breathe: _breathe.value,
            glow: SeenlyPalette.mustard,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: 210,
          height: 8,
          decoration: BoxDecoration(
            color: SeenlyPalette.paper.withOpacity(0.9),
            borderRadius: BorderRadius.circular(5),
            boxShadow: [BoxShadow(color: SeenlyPalette.paper.withOpacity(0.34), blurRadius: 26, spreadRadius: 5)],
          ),
        ),
        const SizedBox(height: 10),
        Text('amber seats are by the window'.tr, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.mustard.withOpacity(0.8))),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: _rows,
            itemBuilder: (_, row) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int col = 0; col < _cols; col++) ...[
                      if (col == 2)
                        SizedBox(
                          width: 30,
                          child: Text(
                            '${_firstRowNumber + row}'.padLeft(2, '0'),
                            textAlign: TextAlign.center,
                            style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.4)),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: BigSeatButton(
                          taken: _taken.contains(row * _cols + col),
                          selected: _selectedSeat == row * _cols + col,
                          prime: _isWindowSeat(row * _cols + col),
                          onTap: () => _chooseSeat(row * _cols + col),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
          child: Opacity(
            opacity: _selectedSeat == null ? 0.45 : 1.0,
            child: PrimaryButton(
              label: _selectedSeat == null ? 'pick a seat'.tr : '${'confirm seat'.tr} $_seatLabel',
              onTap: _selectedSeat == null ? null : () => _goTo(_Step.details),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Step 2 — the ride itself: rating, vibe, when, note. Same picker
  // language as the seat grid (soft paper card, warm dusk behind it)
  // instead of a plain settings-style form.
  // ---------------------------------------------------------------
  Widget _buildDetailsStep() {
    return Column(
      key: const ValueKey('details-step'),
      children: [
        LogFlowTopBar(onBack: () => _goTo(_Step.seat), trailingLabel: 'skip'.tr, onTrailing: () => _goTo(_Step.confirm)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: SeatPill(label: '${'seat'.tr} $_seatLabel'),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: _BusWindowFrame(
              child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: ClayBoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(18),
                boxShadow: SeenlyPalette.softShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('still rolling through the dark'.tr, style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.accent)),
                  const SizedBox(height: 4),
                  Text('before you check your stop — what did tonight leave you with?'.tr,
                      style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _breathe,
                    builder: (_, child) => _WindowFrame(glow: _breathe.value, child: child!),
                    child: VerdictRating(
                      value: _rating,
                      breathe: _breathe,
                      labels: _coachVerdictLabels,
                      idleLabel: 'tap to rate the ride',
                      onChanged: (v) => setState(() => _rating = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FavoriteToggle(
                    theme: LogTheme.coach,
                    value: _isFavorite,
                    onChanged: (v) => setState(() => _isFavorite = v),
                  ),
                  const SizedBox(height: 22),
                  Text('when'.tr, style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.accent)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: PillChip(label: 'today'.tr, active: _when == _When.today, dashed: true, fullWidth: true, onTap: () => setState(() => _when = _When.today))),
                      const SizedBox(width: 8),
                      Expanded(child: PillChip(label: 'yesterday'.tr, active: _when == _When.yesterday, dashed: true, fullWidth: true, onTap: () => setState(() => _when = _When.yesterday))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PillChip(
                          label: _when == _When.custom && _customDate != null
                              ? '${_customDate!.month}/${_customDate!.day}'
                              : 'pick date'.tr,
                          active: _when == _When.custom,
                          dashed: true,
                          fullWidth: true,
                          onTap: _pickDate,
                        ),
                      ),
                    ],
                  ),
                  if (_partnerUsername != null) ...[
                    const SizedBox(height: 22),
                    Text('together'.tr, style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.accent)),
                    const SizedBox(height: 10),
                    PillChip(
                      label: "${'watched with'.tr} $_partnerUsername",
                      active: _watchedWithPartner,
                      onTap: () => setState(() => _watchedWithPartner = !_watchedWithPartner),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text('a note to your future self'.tr, style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.accent)),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(color: SeenlyPalette.background, borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.all(4),
                    child: TextField(
                      controller: _noteController,
                      minLines: 2,
                      maxLines: 5,
                      style: SeenlyText.bodyText,
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        hintText: 'watched it with... felt like...'.tr,
                        hintStyle: SeenlyText.serif(color: SeenlyPalette.placeholder),
                      ),
                    ),
                  ),
                  ExpandReviewLink(onTap: _expandReview),
                ],
              ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: PrimaryButton(
            label: 'continue'.tr,
            onTap: () => _goTo(_Step.vibe),
          ),
        ),
      ],
    );
  }

  // The small note box's "write more, full page" link — same
  // roomier-view-onto-the-same-text reasoning as review_composer.dart's
  // own docstring.
  Future<void> _expandReview() async {
    final result = await showReviewComposer(
      context,
      initialText: _noteController.text,
      forTitle: widget.item.title.display,
    );
    if (result != null) setState(() => _noteController.text = result);
  }

  // ---------------------------------------------------------------
  // Step 2.25 — why did it land (or not)? Its own beat between settling
  // the rating and picking a standout from the cast — see
  // mood_tag_picker.dart's vibePromptTitle/vibePresetTags for how the
  // headline and preset chips flip once the rating drops below 5.
  // ---------------------------------------------------------------
  Widget _buildVibeStep() {
    return Column(
      key: const ValueKey('vibe-step'),
      children: [
        LogFlowTopBar(onBack: () => _goTo(_Step.details), trailingLabel: 'skip'.tr, onTrailing: () => _goTo(_Step.confirm)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: SeatPill(label: '${'seat'.tr} $_seatLabel'),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: _BusWindowFrame(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: ClayBoxDecoration(
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: SeenlyPalette.softShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vibePromptTitle(_rating), style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.accent)),
                    const SizedBox(height: 4),
                    Text('before the next stop — what made the ride?'.tr,
                        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                    const SizedBox(height: 14),
                    VibeChipGrid(
                      tags: [
                        ...vibePresetTags(_rating),
                        ..._moodTags.where((t) => !vibePresetTags(_rating).contains(t)),
                      ],
                      isActive: (tag) => _moodTags.contains(tag),
                      onToggle: _toggleTag,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(color: SeenlyPalette.background, borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: TextField(
                              controller: _customTagController,
                              style: SeenlyText.bodyText,
                              onSubmitted: (_) => _addCustomTag(),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                hintText: 'your own tag...'.tr,
                                hintStyle: SeenlyText.serif(color: SeenlyPalette.placeholder),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _addCustomTag,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(color: SeenlyPalette.accent, shape: BoxShape.circle),
                            child: Icon(Icons.add, size: 17, color: SeenlyPalette.accentOnAccent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: PrimaryButton(
            label: 'continue'.tr,
            onTap: () => _goTo(_cast.isNotEmpty ? _Step.castPick : _Step.confirm),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Step 2.5 — same soft, optional aside as the cinema flow: who stood
  // out tonight? Up to 3 faces from this title's own cast, snapshotted
  // onto the diary entry alongside the rating/mood tags. Only reachable
  // when the title actually has cast data.
  // ---------------------------------------------------------------
  Widget _buildCastPickStep() {
    return Column(
      key: const ValueKey('cast-pick-step'),
      children: [
        LogFlowTopBar(onBack: () => _goTo(_Step.vibe), trailingLabel: 'skip'.tr, onTrailing: () => _goTo(_Step.confirm)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: SeatPill(label: '${'seat'.tr} $_seatLabel'),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: _BusWindowFrame(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                decoration: ClayBoxDecoration(color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(18), boxShadow: SeenlyPalette.softShadow),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('who stood out tonight?'.tr,
                        style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.accent)),
                    const SizedBox(height: 4),
                    Text(
                      _favoriteCast.isEmpty
                          ? 'pick up to 3 — totally optional'
                          : '${_favoriteCast.length}/3 picked',
                      style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 20,
                      children: [
                        for (final member in _cast)
                          _CoachCastPickTile(
                            member: member,
                            selected: _favoriteCast.any(
                                (m) => m.personId == member.personId && m.name == member.name),
                            atCap: _favoriteCast.length >= 3,
                            onTap: () => _toggleCastPick(member),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: PrimaryButton(label: 'continue'.tr, onTap: () => _goTo(_Step.confirm)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Step 3 — confirm. A calm summary before anything's actually saved.
  // ---------------------------------------------------------------
  Widget _buildConfirmStep() {
    final item = widget.item;
    return Column(
      key: const ValueKey('confirm-step'),
      children: [
        LogFlowTopBar(onBack: () => _goTo(_Step.details)),
        const SizedBox(height: 4),
        Text('ready to board?'.tr, style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
        const SizedBox(height: 4),
        Text("one more look before it's official".tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.65))),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              children: [
                _BusWindowFrame(
                  child: Container(
              padding: const EdgeInsets.all(18),
              decoration: ClayBoxDecoration(color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(16), boxShadow: SeenlyPalette.softShadow),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: SizedBox(
                          width: 46,
                          height: 66,
                          child: item.posterUrl != null
                              ? Image.network(item.posterUrl!, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.mediaColor(item.mediaType)))
                              : Container(color: SeenlyPalette.mediaColor(item.mediaType)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title.display, style: SeenlyText.cardTitle),
                            const SizedBox(height: 3),
                            Text('${'seat'.tr} $_seatLabel · ${_route.originCode} → ${_route.destCode}', style: SeenlyText.metaLabel),
                          ],
                        ),
                      ),
                    ],
                  ),
                  CozyDivider(height: 28, color: SeenlyPalette.border),
                  ConfirmRow(label: 'when'.tr, value: _friendlyDate(_resolvedDate)),
                  const SizedBox(height: 10),
                  ConfirmRow(
                    label: 'rating'.tr,
                    value: _rating > 0 ? '$_rating/10 · ${_verdictFor(_rating)}' : 'not rated'.tr,
                    valueColor: _rating > 0 ? SeenlyPalette.ratingColor(_rating) : SeenlyPalette.inkFaint,
                  ),
                  if (_moodTags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final t in _moodTags) PillChip(label: t, active: true)]),
                  ],
                  if (_favoriteCast.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('favorites tonight'.tr, style: SeenlyText.metaLabel),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final member in _favoriteCast) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: (member.photoUrl != null)
                                  ? Image.network(member.photoUrl!, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.accent))
                                  : Container(color: SeenlyPalette.accent),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            _favoriteCast.map((m) => m.name).join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_noteController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('"${_noteController.text.trim()}"', style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted)),
                  ],
                  if (_watchedWithPartner && _partnerUsername != null) ...[
                    const SizedBox(height: 12),
                    ConfirmRow(label: 'together'.tr, value: "${'with'.tr} $_partnerUsername"),
                  ],
                ],
              ),
                  ),
                ),
                const SizedBox(height: 26),
                AnimatedBuilder(
                  animation: _breathe,
                  builder: (_, __) => _RouteStrip(route: _route, glow: _breathe.value),
                ),
                AnimatedBuilder(
                  animation: _breathe,
                  builder: (_, __) => AmbientNote(
                    icon: Icons.nightlight_round,
                    tint: SeenlyPalette.mustard,
                    text: pickAmbientLine(item.title.display, _coachAmbientLines, salt: 0x636f6163),
                    breathe: _breathe.value,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: CoachSubmitButton(label: 'confirm boarding'.tr, loading: _saving, onTap: _saving ? null : _confirmAndSave),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Step 4 — the pass prints itself. A real slide-and-settle entrance
  // rather than a cut, with tonight's date right on it.
  // ---------------------------------------------------------------
  Widget _buildPassStep() {
    return Column(
      key: const ValueKey('pass-step'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        _PassStepPoster(
          posterUrl: widget.item.posterUrl,
          title: widget.item.title.display,
          mediaType: widget.item.mediaType,
        ),
        const SizedBox(height: 18),
        Text('all boarded'.tr, style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
        const SizedBox(height: 6),
        Text('tonight, safely logged'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.68))),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            "we'll bring it back around — a month from now, and again next year".tr,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: SeenlyText.serif(italic: true, size: 10.5, color: SeenlyPalette.paper.withOpacity(0.5)),
          ),
        ),
        const SizedBox(height: 26),
        _PassReveal(
          title: widget.item.title.display,
          mediaType: widget.item.mediaType,
          rating: _rating > 0 ? _rating : null,
          watchedAt: _resolvedDate,
          route: _route,
        ),
        const _PassStepMascot(),
        const Spacer(flex: 2),
        if (_watchedWithPartner && _partnerUsername != null)
          TogetherWrappedTeaser(partnerName: _partnerUsername!),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: Row(
            children: [
              Expanded(
                child: SecondaryActionButton(
                  icon: Icons.ios_share_rounded,
                  label: 'share'.tr,
                  onTap: _shareLoggedEntry,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: PrimaryButton(
                  label: 'check in'.tr,
                  onTap: () async {
                    // Right as the person is about to leave the boarding
                    // ritual behind — one more beat (or two), if this save
                    // leveled them up and/or a badge just came with it,
                    // before actually stepping away.
                    final leveledUp = context.read<AppState>().consumePendingLevelUp();
                    if (leveledUp != null && context.mounted) {
                      await showLevelUpCelebration(context, leveledUp);
                    }
                    if (context.mounted) {
                      await checkAndCelebrateNewAchievements(context);
                    }
                    if (context.mounted && _watchedWithPartner) {
                      // The shared rating, in its own soft sheet: sealed with
                      // yours, or opening right now if the others have rated.
                      await showTogetherVerdictSheet(context, widget.item);
                    }
                    if (context.mounted) {
                      // The closing flourish: it lives in the root overlay, so it
                      // carries on over the screen this one is about to reveal.
                      showSavedCelebration(
                        context,
                        kind: SavedKind.logged,
                        title: widget.item.title.display,
                        posterUrl: widget.item.posterUrl,
                        mediaType: widget.item.mediaType,
                        rating: _rating > 0 ? _rating : null,
                        partnerName: _watchedWithPartner ? _partnerUsername : null,
                        compact: true,
                        haptics: false,
                      );
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],

    );
  }

  String _friendlyDate(DateTime d) {
    final now = DateTime.now();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
    if (isToday) return 'today'.tr;
    if (isYesterday) return 'yesterday'.tr;
    return '${d.month}/${d.day}/${d.year}';
  }

  // Same lookup VerdictRating uses internally, against this theme's own
  // words, so the confirm card echoes the exact one already chosen.
  String _verdictFor(int rating) {
    final idx = ((rating - 1) * _coachVerdictLabels.length / 10).floor().clamp(0, _coachVerdictLabels.length - 1);
    return _coachVerdictLabels[idx];
  }
}

/// One selectable face on the coach theme's cast-pick step — mirrors
/// cinema_log_screen.dart's own _CastPickTile (same fixed-width tile,
/// full name allowed to wrap rather than being clipped, and the
/// character name shown underneath when TMDB has one) just re-skinned
/// with this theme's palette.
class _CoachCastPickTile extends StatelessWidget {
  final CastMember member;
  final bool selected;
  final bool atCap;
  final VoidCallback onTap;

  const _CoachCastPickTile({
    required this.member,
    required this.selected,
    required this.atCap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = atCap && !selected;
    return PressScale(
      onTap: onTap,
      scaleTo: 0.93,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: dimmed ? 0.4 : 1.0,
        child: SizedBox(
          width: 84,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? SeenlyPalette.accent : Colors.transparent,
                    width: 2.5,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: SeenlyPalette.accent.withOpacity(0.35), blurRadius: 10, spreadRadius: 1)]
                      : null,
                ),
                padding: const EdgeInsets.all(2),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: (member.photoUrl != null)
                          ? Image.network(
                              member.photoUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.accent),
                            )
                          : Container(color: SeenlyPalette.accent),
                    ),
                    if (selected)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SeenlyPalette.accent,
                            border: Border.all(color: SeenlyPalette.paper, width: 2),
                          ),
                          child: Icon(Icons.favorite, size: 10, color: SeenlyPalette.accentOnAccent),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                // Sized for the real rendered size, not the requested
                // 10.5/9 — small serif/mono text gets floored up to
                // 13px/12px (see text_styles' enforceFloor), and at
                // that size 2 lines of serif needs ~34px. Undersizing
                // this clips letters rather than showing "..." .
                height: 36,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(member.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(size: 10.5)),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 18,
                child: (member.character?.display != null && member.character!.display != '—')
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: Text(member.character!.display,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps the *whole* details card in a real bus-window frame instead
/// of a plain rounded card sitting on the page — a dark bezel with an
/// actual sliver of dusk sky and rolling rooftops above the card, cut
/// by a center post the way a real coach window's two panes are, the
/// paper card itself sitting inside like the tray below the glass.
/// Mirrors what the cinema theme's filmstrip card does for its own
/// details step, just dressed for a bus window instead of a reel.
///
/// Deliberately a plain Container + Column/Stack (no IntrinsicHeight,
/// no LayoutBuilder around the content) — the content underneath has
/// TextFields in it, and running an intrinsic-size layout pass over a
/// TextField subtree is what caused the cinema screen's blank-screen
/// layout crash before that got fixed. This widget just sizes to its
/// already-laid-out child, no extra pass needed.
class _BusWindowFrame extends StatelessWidget {
  final Widget child;
  const _BusWindowFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.ink,
        borderRadius: BorderRadius.circular(24),
        boxShadow: SeenlyPalette.softShadow,
      ),
      padding: const EdgeInsets.all(9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A sliver of actual dusk sky and passing rooftops above the
          // card — the view out the glass, not just a painted border —
          // split by a center post the way a real coach window's two
          // panes are, with a rivet bolted through it top and bottom.
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 36,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color.lerp(SeenlyPalette.ink, SeenlyPalette.mustard, 0.32)!, SeenlyPalette.background],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: CustomPaint(size: const Size(double.infinity, 18), painter: _RollingSkylinePainter()),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Container(width: 4, height: 36, color: SeenlyPalette.ink.withOpacity(0.9)),
                  ),
                  const Align(alignment: Alignment(0, -0.55), child: _WindowLatch()),
                  const Align(alignment: Alignment(0, 0.75), child: _WindowLatch()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// One small round latch, the kind bolted to the corners of an actual
/// bus window frame — purely decorative, just enough hardware that the
/// bezel reads as a window rather than a plain painted border.
class _WindowLatch extends StatelessWidget {
  const _WindowLatch();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SeenlyPalette.mustard.withOpacity(0.6),
        boxShadow: [BoxShadow(color: SeenlyPalette.mustard.withOpacity(0.35), blurRadius: 4)],
      ),
    );
  }
}

/// Dresses the rating step's box like the view out a bus window at
/// dusk instead of a plain rounded card — a dark window-frame bezel,
/// a sky gradient inside that warms with the same breathing pulse as
/// the hearts, and a thin strip of passing rooftops along the bottom,
/// so the box reads as something glimpsed through glass rather than a
/// setting on a screen.
class _WindowFrame extends StatelessWidget {
  final Widget child;
  final double glow;
  const _WindowFrame({required this.child, required this.glow});

  @override
  Widget build(BuildContext context) {
    final t = 0.35 + 0.65 * ((math.sin(glow * 2 * math.pi) + 1) / 2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 9),
      decoration: BoxDecoration(
        color: SeenlyPalette.ink.withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26), bottom: Radius.circular(18)),
        boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(12)),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(SeenlyPalette.ink, SeenlyPalette.mustard, 0.24 + 0.1 * t)!,
                    SeenlyPalette.background,
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CustomPaint(size: const Size(double.infinity, 22), painter: _RollingSkylinePainter()),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18), child: child),
          ],
        ),
      ),
    );
  }
}

/// A handful of low, uneven silhouettes — the rooftops and one lamp
/// post you'd catch out a window at night — never meant to read as
/// any specific skyline, just enough shape that the strip beneath the
/// hearts isn't a flat line.
class _RollingSkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SeenlyPalette.ink.withOpacity(0.55);
    final w = size.width;
    final path = Path()..moveTo(0, size.height);
    const heights = [0.3, 0.6, 0.4, 0.85, 0.5, 0.25, 0.7, 0.45, 0.3, 0.6, 0.35];
    final step = w / (heights.length - 1);
    for (int i = 0; i < heights.length; i++) {
      path.lineTo(i * step, size.height * (1 - heights[i]));
      path.lineTo((i + 0.5) * step, size.height * (1 - heights[i]));
    }
    path.lineTo(w, size.height);
    path.close();
    canvas.drawPath(path, paint);
    // One small lamp post glow among the rooftops.
    canvas.drawCircle(Offset(w * 0.72, size.height * 0.32), 2.2, Paint()..color = SeenlyPalette.mustard.withOpacity(0.7));
  }

  @override
  bool shouldRepaint(covariant _RollingSkylinePainter oldDelegate) => false;
}

/// A small strip below the confirm card showing tonight's route as an
/// actual line on a map instead of just the codes already printed on
/// the card — origin and destination cities at either end, a dashed
/// road between them with the coach itself sitting on it, breathing
/// with the same pulse as everything else in this ritual. Mostly here
/// so the dark space under the card reads as "still out on the road"
/// rather than empty page.
class _RouteStrip extends StatelessWidget {
  final CoachRoute route;
  final double glow; // 0..1, shared breathing pulse

  const _RouteStrip({required this.route, required this.glow});

  @override
  Widget build(BuildContext context) {
    final t = 0.35 + 0.65 * ((math.sin(glow * 2 * math.pi) + 1) / 2);
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(route.originCode, style: SeenlyText.mono(size: 13, color: SeenlyPalette.paper, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(route.originCity, style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper.withOpacity(0.55))),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(route.destCode, style: SeenlyText.mono(size: 13, color: SeenlyPalette.paper, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(route.destCity, style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper.withOpacity(0.55))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 18,
          width: double.infinity,
          child: CustomPaint(painter: _RouteDashPainter(t: t)),
        ),
        const SizedBox(height: 10),
        Text('${route.minutes} ${'min on the rails · tonight'.tr}', style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.paper.withOpacity(0.45))),
      ],
    );
  }
}

/// The dashed track itself plus the train glyph parked along it — drawn
/// with a soft glow that breathes in sync with the rest of the scene,
/// so it never reads as a static diagram.
class _RouteDashPainter extends CustomPainter {
  final double t; // 0..1 breathing intensity

  const _RouteDashPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final dash = Paint()
      ..color = SeenlyPalette.paper.withOpacity(0.3)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const dashWidth = 5.0;
    const gapWidth = 5.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, midY), Offset((x + dashWidth).clamp(0, size.width), midY), dash);
      x += dashWidth + gapWidth;
    }
    // The train itself, parked at the midpoint of tonight's track, with
    // a soft glow that pulses on the same breathing rhythm as the rest
    // of the ritual — never actually travels, just idles in place. A
    // small rounded carriage with a lit window band reads as train even
    // at this size, rather than the wheel-dots a bus silhouette needs.
    final trainCenter = Offset(size.width / 2, midY);
    canvas.drawCircle(trainCenter, 9 + 1.5 * t, Paint()..color = SeenlyPalette.mustard.withOpacity(0.18 * t));
    final trainPaint = Paint()..color = SeenlyPalette.mustard.withOpacity(0.85);
    final trainRect = Rect.fromCenter(center: trainCenter, width: 16, height: 8);
    canvas.drawRRect(RRect.fromRectAndRadius(trainRect, const Radius.circular(2.5)), trainPaint);
    canvas.drawRect(
      Rect.fromCenter(center: trainCenter, width: 11, height: 2.6),
      Paint()..color = const Color(0xFFFFE9C2).withOpacity(0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _RouteDashPainter oldDelegate) => oldDelegate.t != t;
}

/// The final reveal: the boarding pass eases up from below like it's
/// just been printed, settling into place with a soft overshoot. Given
/// the same [CoachRoute] the seat step already showed, so the cities on
/// the pass always match the plaque shown while choosing a seat.
/// The poster leads the reveal — the one picture in the whole flow that's
/// actually *of* the thing you watched, rather than a stylized pass.
/// Settles in a beat before [_PassReveal], the same soft
/// overshoot-and-fade every other landing in this ritual uses, so the
/// two read as one small sequence — poster first, then the pass printing
/// itself underneath — instead of everything arriving at once. Quietly
/// absent (no gap left behind) for an old/imported title that never got
/// a poster on file.
class _PassStepPoster extends StatefulWidget {
  final String? posterUrl;
  final String title;
  final String mediaType;

  const _PassStepPoster({required this.posterUrl, required this.title, required this.mediaType});

  @override
  State<_PassStepPoster> createState() => _PassStepPosterState();
}

class _PassStepPosterState extends State<_PassStepPoster> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posterUrl == null || widget.posterUrl!.isEmpty) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOutBack.transform(_c.value.clamp(0.0, 1.0));
        final fade = Curves.easeOut.transform(_c.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 26),
            child: Transform.scale(
              scale: 0.9 + 0.1 * t.clamp(0.0, 1.0),
              child: Container(
                width: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: SeenlyPalette.ink.withOpacity(0.28),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ThemedPosterTile(
                    title: widget.title,
                    posterUrl: widget.posterUrl,
                    mediaType: widget.mediaType,
                    fallbackColor: SeenlyPalette.mediaColor(widget.mediaType),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PassReveal extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  final CoachRoute route;

  const _PassReveal({
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
    required this.route,
  });

  @override
  State<_PassReveal> createState() => _PassRevealState();
}

class _PassRevealState extends State<_PassReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 780))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOutBack.transform(_c.value.clamp(0.0, 1.0));
        final fade = Curves.easeOut.transform(_c.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 90),
            child: Transform.scale(
              scale: 0.88 + 0.12 * t.clamp(0.0, 1.0),
              child: BoardingPassWidget(
                title: widget.title,
                mediaType: widget.mediaType,
                rating: widget.rating,
                watchedAt: widget.watchedAt,
                routeOverride: widget.route,
                width: 290,
                height: 128,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A quiet little "thank you" that settles in just under the pass once
/// it's landed, giving the pass a beat to breathe before the screen's
/// primary action appears.
///
/// Held back a beat behind [_PassReveal] so it plays like a reaction to
/// the pass arriving rather than two things happening at once.
class _PassStepMascot extends StatefulWidget {
  const _PassStepMascot();

  @override
  State<_PassStepMascot> createState() => _PassStepMascotState();
}

class _PassStepMascotState extends State<_PassStepMascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
    _delay = Timer(const Duration(milliseconds: 480), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOutBack.transform(_c.value.clamp(0.0, 1.0));
        final fade = Curves.easeOut.transform(_c.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 22),
            child: Transform.scale(
              scale: 0.85 + 0.15 * t.clamp(0.0, 1.0),
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'thank you for tonight'.tr,
                      style: SeenlyText.serif(
                          italic: true, size: 13, color: SeenlyPalette.paper.withOpacity(0.82)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
