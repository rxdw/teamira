import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/departure_scenes.dart';
import '../../widgets/light_bloom.dart';
import '../../widgets/log_flow_kit.dart';
import '../../widgets/mood_tag_picker.dart' show vibePresetTags, vibePromptTitle;
import '../../widgets/review_composer.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/ticket.dart';
import '../../widgets/ticket_drop_overlay.dart';
import '../../widgets/ticket_submit_button.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../services/log_theme_service.dart';
import '../../services/rabbit_mascot_prefs_service.dart';
import '../../widgets/favorite_toggle.dart';
import '../../widgets/rabbit_mascot.dart';
import '../../widgets/verdict_rating.dart';
import '../../widgets/wow_motion.dart' show PressScale;
import '../../services/app_translations.dart';

/// A quiet aside for the confirm step — the kind of small thing you'd
/// notice from your seat while the trailers are still running. One is
/// picked per title (see pickAmbientLine) so it stays put on rebuilds.
const List<String> _cinemaAmbientLines = [
  'trailers are still running — plenty of time',
  'someone two rows back just settled in with popcorn',
  'the curtain hasn\'t pulled back yet',
  'house lights are only half down so far',
  'a few seats are still filling in around you',
  'it\'s that hush right before the reel starts',
];

/// The cinema theme's real logging flow — same shape as
/// [CoachLogScreen], dressed for a little private screening instead of
/// an evening coach ride: pick a seat in the room, settle how the
/// showing went, confirm, then watch the stub actually print and tear
/// free.
class CinemaLogScreen extends StatefulWidget {
  final MediaItem item;
  final int? season;
  final int? episode;
  final int? episodeCount;
  const CinemaLogScreen({super.key, required this.item, this.season, this.episode, this.episodeCount});

  @override
  State<CinemaLogScreen> createState() => _CinemaLogScreenState();
}

enum _Step { seat, details, vibe, castPick, confirm, igniting, pass }

enum _When { today, yesterday, custom }

class _CinemaLogScreenState extends State<CinemaLogScreen> with TickerProviderStateMixin {
  static const int _rows = 9;
  static const int _cols = 8; // two blocks of 4, aisle in the middle
  static const List<String> _rowLetters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'];

  late final Set<int> _taken;
  late final AnimationController _dust;
  late final AnimationController _breathe;
  late final AnimationController _preshow;
  late final List<LightMote> _motes;
  // Seeded once per title, same spirit as the coach route match: a
  // plausible hall and a small timetable of tonight's showings, standing
  // in for the route plaque so the confirm step has its own house board.
  late final int _hallNumber;
  late final List<String> _showtimes; // three showings, evenly spaced by tonight's runtime
  late final int _showtimeIndex; // which of the three is "yours"

  _Step _step = _Step.seat;
  int? _selectedSeat;
  int _rating = 0;
  bool _isFavorite = false;
  List<String> _moodTags = [];
  _When _when = _When.today;
  DateTime? _customDate;
  final _noteController = TextEditingController();
  final _customTagController = TextEditingController();
  bool _watchedWithPartner = false;
  String? _partnerUsername;
  // Up to 3 cast members picked as tonight's standouts — see
  // _buildCastPickStep. Purely a nice-to-have, so an empty list here
  // just means the step was skipped (or this title has no cast data).
  List<CastMember> _favoriteCast = [];
  bool _saving = false;
  String? _error;
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
    final seed = widget.item.title.display;
    _taken = seededTakenSeats(seed, _rows * _cols, salt: 0x7469636b, minTaken: 6, extraRange: 12); // 'tick'
    _motes = seededMotes(seed, 12, salt: 0x7469636b);
    final houseSeed = math.Random(seed.hashCode ^ 0x68616c6c); // 'hall'
    _hallNumber = 1 + houseSeed.nextInt(9);
    final startHour = 16 + houseSeed.nextInt(2); // first showing 16:00–17:45
    final startMinute = houseSeed.nextInt(4) * 15;
    final gapMinutes = (widget.item.runtimeMinutes ?? 105) + 25; // a real house needs time to clear and reset
    final base = DateTime(2000, 1, 1, startHour, startMinute);
    _showtimes = List.generate(3, (i) {
      final d = base.add(Duration(minutes: i * gapMinutes));
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    });
    _showtimeIndex = 1; // the evening showing — tonight's, not the matinee or the late one
    _dust = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100))..repeat(reverse: true);
    // The little house-announcement that flickers up once while you're
    // still picking a seat, then dims itself back out — same beat as
    // the real "please silence your phones" slide before a showing.
    _preshow = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _preshow.forward();
    });
    _loadPartnerStatus();
    if (_cast.isEmpty) _loadCast();
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
    final row = _rowLetters[seat ~/ _cols];
    final number = seat % _cols + 1;
    return '$row$number';
  }

  // The classic "sweet spot" — center-back rows, the two columns
  // nearest the aisle on each side — marked with a small glow on the
  // grid so choosing a seat carries a bit of real theater-going
  // knowledge instead of just being a grid of identical squares.
  bool _isPrimeSeat(int index) {
    final row = index ~/ _cols;
    final col = index % _cols;
    final primeRow = row >= 3 && row <= 5; // D, E, F
    final primeCol = col == 2 || col == 3 || col == 4 || col == 5; // inner four, either side of the aisle
    return primeRow && primeCol;
  }

  bool get _selectedIsPrime => _selectedSeat != null && _isPrimeSeat(_selectedSeat!);

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

  // Caps out at 3 — tapping a 4th while three are already picked just
  // does nothing (the tile itself dims instead of being disabled
  // outright, so it's still obvious tonight's cast is bigger than 3,
  // just that the pick is full). Tapping an already-picked face always
  // un-picks it, even while at the cap.
  void _toggleCastPick(CastMember member) {
    final already = _favoriteCast.any((m) => m.personId == member.personId && m.name == member.name);
    if (!already && _favoriteCast.length >= 3) return;
    HapticFeedback.selectionClick();
    setState(() {
      _favoriteCast = already
          ? _favoriteCast.where((m) => !(m.personId == member.personId && m.name == member.name)).toList()
          : [..._favoriteCast, member];
    });
  }

  void _addCustomTag() {
    final raw = _customTagController.text.trim();
    if (raw.isEmpty) return;
    if (!_moodTags.contains(raw)) setState(() => _moodTags = [..._moodTags, raw]);
    _customTagController.clear();
  }

  Future<void> _confirmAndSave() async {
    // The house lights actually go down and the screen switches on the
    // instant the button's tapped — the save happens underneath that,
    // so it never reads as a blank wait.
    setState(() { _saving = true; _error = null; _step = _Step.igniting; });
    bool failed = false;
    try {
      await Future.wait([
        context.read<AppState>().diary.logEntry(
              item: widget.item,
              rating: _rating > 0 ? _rating : null,
              note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
              moodTags: _moodTags.isEmpty ? null : _moodTags,
              favoriteCast: _favoriteCast.isEmpty ? null : _favoriteCast,
              watchedAt: _resolvedDate,
              watchedWithPartner: _watchedWithPartner,
              isFavorite: _isFavorite,
              season: widget.season,
              episode: widget.episode,
              episodeCount: widget.episodeCount,
            ),
        Future.delayed(const Duration(milliseconds: 1500)),
      ]);
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    if (failed) {
      setState(() { _saving = false; _step = _Step.confirm; _error = "couldn't save that just now — try again"; });
      return;
    }
    HapticFeedback.mediumImpact();
    // A save is exactly the moment a level-up (and possibly a new
    // badge unlocking) could just have happened — refresh the cached
    // level so the thank-you mascot right below reflects it instead of
    // waiting for the next profile visit. Best-effort, never blocks.
    unawaited(context.read<AppState>().refreshLevel());
    setState(() => _saving = false);
    // Drag or tap to tear the stub free, same ritual wow-effects already
    // worked out for this theme.
    await showTicketDrop(
      context,
      title: widget.item.title.display,
      mediaType: widget.item.mediaType,
      rating: _rating > 0 ? _rating : null,
      watchedAt: _resolvedDate,
    );
    if (!mounted) return;
    setState(() => _step = _Step.pass);
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

  void _confirmLeaveSeatStep() {
    showLeaveRouteDialog(
      context,
      routeNoun: 'showing',
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
            Positioned.fill(child: LogFlowBackdrop(dust: _dust, motes: _motes, tint: SeenlyPalette.accent)),
            // A dark pool at the top and bottom edges — the room stays
            // darkest where a real auditorium's ceiling and floor would
            // swallow the light, so every step reads as sitting inside
            // the theatre rather than on a themed page.
            const Positioned.fill(child: IgnorePointer(child: _CinemaVignette())),
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
            // A sliver of velvet at either edge, held for every step of
            // the actual ritual (not just the ignite scene) so the room
            // never fully disappears behind the paper cards.
            if (_step == _Step.seat || _step == _Step.details || _step == _Step.vibe || _step == _Step.castPick || _step == _Step.confirm)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _breathe,
                    builder: (_, __) => _AmbientCurtainFringes(shimmer: _breathe.value),
                  ),
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
        _Step.igniting => _buildIgnitingStep(),
        _Step.pass => _buildPassStep(),
      };

  // ---------------------------------------------------------------
  // Step 3.5 — the screen switches on while the evening saves
  // underneath it.
  // ---------------------------------------------------------------
  Widget _buildIgnitingStep() {
    return const ScreenIgniteScene(key: ValueKey('igniting-step'));
  }

  // ---------------------------------------------------------------
  // Step 1 — choose your seat in tonight's little private screening.
  // Same seat glyph the modal picker drew, just given a whole screen
  // and a proper theater-sized room instead of a cramped dialog.
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
          text: 'please silence your phone — the show is about to start'.tr,
          glow: SeenlyPalette.coral,
        ),
        const SizedBox(height: 6),
        Text('choose your seat'.tr,
            style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
        const SizedBox(height: 5),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _selectedSeat == null
                ? "tonight's little screening"
                : _selectedIsPrime
                    ? 'settled in — seat $_seatLabel, right in the sweet spot'
                    : 'settled in — seat $_seatLabel',
            key: ValueKey('$_selectedSeat-$_selectedIsPrime'),
            style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.68)),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _breathe,
          builder: (_, __) => GlowPlaque(
            text: widget.item.title.display.toUpperCase(),
            breathe: _breathe.value,
            glow: SeenlyPalette.accent,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: 230,
          height: 8,
          decoration: BoxDecoration(
            color: SeenlyPalette.paper.withOpacity(0.92),
            borderRadius: BorderRadius.circular(5),
            boxShadow: [BoxShadow(color: SeenlyPalette.paper.withOpacity(0.4), blurRadius: 30, spreadRadius: 6)],
          ),
        ),
        const SizedBox(height: 10),
        Text('amber seats are the good ones'.tr, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.mustard.withOpacity(0.8))),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: _rows,
            itemBuilder: (_, row) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        _rowLetters[row],
                        textAlign: TextAlign.center,
                        style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.4)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    for (int col = 0; col < _cols; col++) ...[
                      if (col == _cols ~/ 2) const SizedBox(width: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: BigSeatButton(
                          taken: _taken.contains(row * _cols + col),
                          selected: _selectedSeat == row * _cols + col,
                          prime: _isPrimeSeat(row * _cols + col),
                          onTap: () => _chooseSeat(row * _cols + col),
                          size: 24,
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
              label: _selectedSeat == null ? 'pick a seat' : 'confirm seat $_seatLabel',
              onTap: _selectedSeat == null ? null : () => _goTo(_Step.details),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Step 2 — how was the show? Same picker language as the seat grid.
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
            child: _FilmReelCard(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: const BoxDecoration(color: SeenlyPalette.paper),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('the lights are still down'.tr, style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.accent)),
                  const SizedBox(height: 4),
                  Text('before anything else — what did tonight leave you with?'.tr,
                      style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _breathe,
                    builder: (_, child) => _ScreenFrame(breathe: _breathe.value, child: child!),
                    child: VerdictRating(
                      value: _rating,
                      breathe: _breathe,
                      onChanged: (v) => setState(() => _rating = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FavoriteToggle(
                    theme: LogTheme.ticket,
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
                          label: _when == _When.custom && _customDate != null ? '${_customDate!.month}/${_customDate!.day}' : 'pick date',
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

  // The small note box's "write more, full page" link — a roomier
  // full-page view onto the exact same text (see review_composer.dart's
  // own docstring), so there's nothing to lose by opening it and
  // nothing extra to confirm before leaving it.
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
            child: _FilmReelCard(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: const BoxDecoration(color: SeenlyPalette.paper),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vibePromptTitle(_rating), style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.accent)),
                    const SizedBox(height: 4),
                    Text('pick what\'s still with you as the lights come up'.tr,
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
                            decoration: const BoxDecoration(color: SeenlyPalette.accent, shape: BoxShape.circle),
                            child: const Icon(Icons.add, size: 17, color: SeenlyPalette.accentOnAccent),
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
  // Step 2.5 — a soft, optional aside: who stole the show tonight?
  // Purely a nice-to-have (same "skip" affordance as every other step
  // here) — up to 3 faces from this title's own cast, snapshotted onto
  // the diary entry alongside the rating/mood tags (see
  // DiaryEntry.favoriteCast). Only reachable when the title actually
  // has cast data — see the continue button above and the "skip to
  // confirm" fallback in _skipToConfirm/PopScope.
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
            child: _FilmReelCard(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                decoration: const BoxDecoration(color: SeenlyPalette.paper),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('who stole the show?'.tr,
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
                          _CastPickTile(
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
  // Step 3 — confirm.
  // ---------------------------------------------------------------
  Widget _buildConfirmStep() {
    final item = widget.item;
    return Column(
      key: const ValueKey('confirm-step'),
      children: [
        LogFlowTopBar(onBack: () => _goTo(_Step.details)),
        const SizedBox(height: 4),
        Text('ready for the show?'.tr, style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
        const SizedBox(height: 4),
        Text("one more look before it's official".tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.65))),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              children: [
                _FilmReelCard(
                  child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(16), boxShadow: SeenlyPalette.softShadow),
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
                            Text('${'seat'.tr} $_seatLabel · ${mediaTypeLabel(item.mediaType)}', style: SeenlyText.metaLabel),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 28, color: SeenlyPalette.border),
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
                  builder: (_, __) => _ScreenStrip(
                    hall: _hallNumber,
                    showtimes: _showtimes,
                    selectedIndex: _showtimeIndex,
                    runtimeMinutes: widget.item.runtimeMinutes,
                    glow: _breathe.value,
                  ),
                ),
                AnimatedBuilder(
                  animation: _breathe,
                  builder: (_, __) => AmbientNote(
                    icon: Icons.local_movies_outlined,
                    tint: SeenlyPalette.coral,
                    text: pickAmbientLine(item.title.display, _cinemaAmbientLines, salt: 0x63696e65),
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
          child: TicketSubmitButton(label: 'confirm ticket'.tr, loading: _saving, onTap: _saving ? null : _confirmAndSave),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Step 4 — the ticket prints itself, sliding up and settling with a
  // soft overshoot, date already stamped on its stub.
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
        Text('lights down'.tr, style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
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
        _TicketReveal(
          title: widget.item.title.display,
          mediaType: widget.item.mediaType,
          rating: _rating > 0 ? _rating : null,
          watchedAt: _resolvedDate,
        ),
        const _PassStepMascot(),
        const Spacer(flex: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: PrimaryButton(
            label: 'keep the stub'.tr,
            onTap: () => Navigator.of(context).pop(true),
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

  // Same lookup VerdictRating uses internally — kept here too so the
  // confirm card can echo the exact word already chosen, instead of
  // just repeating the bare number a second time.
  String _verdictFor(int rating) {
    final idx = ((rating - 1) * kDefaultVerdictLabels.length / 10).floor().clamp(0, kDefaultVerdictLabels.length - 1);
    return kDefaultVerdictLabels[idx];
  }
}

/// A quiet dark pool at the top and bottom of the screen, the way a
/// real auditorium's ceiling and floor eat the light — kept subtle
/// enough that it never competes with the paper cards sitting on top
/// of it, just enough that the room never reads as flat.
class _CinemaVignette extends StatelessWidget {
  const _CinemaVignette();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.16, 0.84, 1.0],
          colors: [
            SeenlyPalette.ink.withOpacity(0.55),
            SeenlyPalette.ink.withOpacity(0.0),
            SeenlyPalette.ink.withOpacity(0.0),
            SeenlyPalette.ink.withOpacity(0.6),
          ],
        ),
      ),
    );
  }
}

/// Two narrow slivers of velvet pinned to either edge of the screen —
/// just enough curtain left in view through the seat, details, and
/// confirm steps that the room never fully disappears behind the
/// paper cards, the way the seats at the very edge of a real theatre
/// stay half-hidden behind the drapes all night. Shimmers very
/// gently on the same breathing rhythm as the rest of the scene.
class _AmbientCurtainFringes extends StatelessWidget {
  final double shimmer; // 0..1, from the shared breathing controller
  const _AmbientCurtainFringes({required this.shimmer});

  @override
  Widget build(BuildContext context) {
    final t = 0.4 + 0.6 * ((math.sin(shimmer * 2 * math.pi) + 1) / 2);
    Widget fringe({required bool right}) {
      return Positioned(
        top: 0,
        bottom: 0,
        left: right ? null : 0,
        right: right ? 0 : null,
        width: 14,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: right ? Alignment.centerRight : Alignment.centerLeft,
              end: right ? Alignment.centerLeft : Alignment.centerRight,
              colors: [
                SeenlyPalette.accent.withOpacity(0.5 * t),
                SeenlyPalette.accent.withOpacity(0.0),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(children: [fringe(right: false), fringe(right: true)]);
  }
}

/// Wraps the whole details card in an actual filmstrip instead of a
/// plain rounded rectangle — a dark ink edge down each side with a
/// column of pale sprocket holes, the paper card itself sitting in
/// the middle like a single frame. This is the one unmistakable "this
/// is a reel of film" shape, so it does the heavy lifting for making
/// the whole screen read as the cinema rather than any other form.
/// One selectable face on the cast-pick step — a plain circular photo
/// (no card chrome, so a row of these reads like a cozy little gallery
/// rather than another grid of tiles) with a warm ring and small
/// checkmark badge once picked, and a gentle dim (not a hard disable)
/// once 3 are already picked so it stays clear more exist without
/// looking broken.
class _CastPickTile extends StatelessWidget {
  final CastMember member;
  final bool selected;
  final bool atCap;
  final VoidCallback onTap;

  const _CastPickTile({
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
                          child: const Icon(Icons.favorite, size: 10, color: SeenlyPalette.accentOnAccent),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Fixed-height reserved for the name (2 lines) and the
              // character line (1 line) — regardless of whether *this*
              // particular name or character happens to be short, so
              // every tile ends up the same total height and the grid
              // reads as even rows instead of jumping up and down with
              // however many lines each name wrapped to.
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

class _FilmReelCard extends StatelessWidget {
  final Widget child;
  const _FilmReelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SeenlyPalette.ink,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      // NOTE: previously this used IntrinsicHeight(Row(...)) to stretch the
      // two perforation strips to match the card's content height. That
      // forces Flutter to run an intrinsic-height layout pass over the
      // whole content subtree (which contains TextFields, Wrap, etc.), and
      // intrinsic passes don't support LayoutBuilder (used inside
      // _PerforationStrip) or several of the widgets TextField builds
      // internally — it would throw/skip laying out render objects like
      // RenderAnimatedOpacity, leaving the details step stuck mid-layout
      // (blank screen, repeated "NEEDS-PAINT" errors) right after picking
      // a seat. A Stack sizes itself to the already-laid-out content, then
      // stretches the strips to match via Positioned(top: 0, bottom: 0) —
      // same visual result, no intrinsic pass required.
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: child,
            ),
          ),
          const Positioned(left: 0, top: 0, bottom: 0, child: _PerforationStrip()),
          const Positioned(right: 0, top: 0, bottom: 0, child: _PerforationStrip()),
        ],
      ),
    );
  }
}

/// One column of small sprocket holes, spaced evenly along whatever
/// height it's stretched to — the perforated edge of an actual strip
/// of film, not just a decorative stripe.
class _PerforationStrip extends StatelessWidget {
  const _PerforationStrip();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 420.0;
          final count = (h / 22).floor().clamp(4, 60);
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              count,
              (_) => Container(
                width: 6,
                height: 8,
                decoration: BoxDecoration(color: SeenlyPalette.paper.withOpacity(0.8), borderRadius: BorderRadius.circular(2)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A small house board below the confirm card standing in for the
/// cinema's own marquee — a row of marquee bulbs chasing each other,
/// hall number and tonight's own showing, a dashed aisle with a small
/// film reel breathing on it, and the two showings either side of
/// tonight's for a bit of real house-timetable texture. The cinema
/// theme's answer to the coach flow's [_RouteStrip]: framed in its own
/// soft board so the space under the card reads as "still waiting for
/// the lights to dim" rather than empty page.
class _ScreenStrip extends StatelessWidget {
  final int hall;
  final List<String> showtimes;
  final int selectedIndex;
  final int? runtimeMinutes;
  final double glow; // 0..1, shared breathing pulse

  const _ScreenStrip({
    required this.hall,
    required this.showtimes,
    required this.selectedIndex,
    required this.runtimeMinutes,
    required this.glow,
  });

  @override
  Widget build(BuildContext context) {
    final t = 0.35 + 0.65 * ((math.sin(glow * 2 * math.pi) + 1) / 2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: SeenlyPalette.ink.withOpacity(0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SeenlyPalette.paper.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          _MarqueeBulbs(t: t),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${'HALL'.tr} $hall', style: SeenlyText.mono(size: 13, color: SeenlyPalette.paper, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('tonight\'s screen'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper.withOpacity(0.55))),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(showtimes[selectedIndex], style: SeenlyText.mono(size: 13, color: SeenlyPalette.paper, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('showtime'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper.withOpacity(0.55))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 18,
            width: double.infinity,
            child: CustomPaint(painter: _ScreenBeamPainter(t: t)),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int i = 0; i < showtimes.length; i++) _ShowtimeChip(label: showtimes[i], active: i == selectedIndex),
            ],
          ),
          const SizedBox(height: 12),
          Text('${runtimeMinutes ?? 105} ${'min on screen · tonight'.tr}', style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.paper.withOpacity(0.45))),
        ],
      ),
    );
  }
}

/// A row of small marquee bulbs chasing each other, on and off in
/// alternation, tied to the same breathing pulse as the reel below —
/// the little bit of "the house lights are still on" glow every real
/// marquee has running along its edge.
class _MarqueeBulbs extends StatelessWidget {
  final double t; // 0..1 breathing intensity
  const _MarqueeBulbs({required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(9, (i) {
        final lit = i.isEven;
        final o = lit ? (0.3 + 0.7 * t) : (0.3 + 0.7 * (1 - t));
        return Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SeenlyPalette.mustard.withOpacity(o),
            boxShadow: [BoxShadow(color: SeenlyPalette.mustard.withOpacity(o * 0.6), blurRadius: 5, spreadRadius: 0.5)],
          ),
        );
      }),
    );
  }
}

/// One showing on the little house timetable — tonight's own showtime
/// picked out in the accent, the two either side left plain, same
/// "here's the wider board, not just your one line" texture the coach
/// flow's route strip gets from its origin/destination pair.
class _ShowtimeChip extends StatelessWidget {
  final String label;
  final bool active;
  const _ShowtimeChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: active ? SeenlyPalette.accent : SeenlyPalette.paper.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: SeenlyText.mono(
          size: 10.5,
          color: active ? SeenlyPalette.accentOnAccent : SeenlyPalette.paper.withOpacity(0.6),
          weight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// The dashed aisle carpet plus the little reel glyph sitting on it —
/// drawn with a soft glow that breathes in sync with the rest of the
/// scene, the cinema's stand-in for the coach's idling bus on its
/// road.
class _ScreenBeamPainter extends CustomPainter {
  final double t; // 0..1 breathing intensity

  const _ScreenBeamPainter({required this.t});

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
    // The reel itself, parked at the midpoint of tonight's showing,
    // with a soft glow that pulses on the same breathing rhythm as the
    // rest of the ritual — its three sprocket holes turn slowly rather
    // than the coach's wheels ever actually rolling anywhere.
    final reelCenter = Offset(size.width / 2, midY);
    canvas.drawCircle(reelCenter, 9 + 1.5 * t, Paint()..color = SeenlyPalette.mustard.withOpacity(0.18 * t));
    canvas.drawCircle(reelCenter, 6, Paint()..color = SeenlyPalette.mustard.withOpacity(0.85));
    final holePaint = Paint()..color = SeenlyPalette.ink;
    for (int i = 0; i < 3; i++) {
      final angle = (i * 2 * math.pi / 3) + t * math.pi * 0.5;
      final hx = reelCenter.dx + math.cos(angle) * 3.2;
      final hy = reelCenter.dy + math.sin(angle) * 3.2;
      canvas.drawCircle(Offset(hx, hy), 1.3, holePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenBeamPainter oldDelegate) => oldDelegate.t != t;
}

/// Dresses the rating step's box like an actual little screen instead
/// of a plain rounded card — a dark bezel (the same ink as the room
/// outside), a warm screen-glow gradient inside that brightens with
/// the same breathing pulse as the hearts, and a row of small grille
/// holes along the bottom bezel, the way a real screen's housing
/// always has *something* below the picture.
class _ScreenFrame extends StatelessWidget {
  final Widget child;
  final double breathe;
  const _ScreenFrame({required this.child, required this.breathe});

  @override
  Widget build(BuildContext context) {
    final glow = 0.35 + 0.65 * ((math.sin(breathe * 2 * math.pi) + 1) / 2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
      decoration: BoxDecoration(
        color: SeenlyPalette.ink,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(SeenlyPalette.background, SeenlyPalette.mustard, 0.16 * glow)!,
                  SeenlyPalette.background,
                ],
              ),
              boxShadow: [BoxShadow(color: SeenlyPalette.mustard.withOpacity(0.16 * glow), blurRadius: 22, spreadRadius: 1)],
            ),
            child: child,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(width: 3, height: 3, decoration: BoxDecoration(color: SeenlyPalette.paper.withOpacity(0.18), shape: BoxShape.circle)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The final reveal: the ticket eases up from below like it's just
/// been printed at the little box office, settling with a soft
/// overshoot — same beat as the coach theme's boarding pass.
/// The poster leads the reveal — the one picture in the whole flow that's
/// actually *of* the thing you watched, rather than a stylized stub.
/// Settles in a beat before [_TicketReveal], the same soft
/// overshoot-and-fade every other landing in this ritual uses, so the
/// two read as one small sequence — poster first, then the ticket
/// printing itself underneath — instead of everything arriving at once.
/// Quietly absent (no gap left behind) for an old/imported title that
/// never got a poster on file.
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

class _TicketReveal extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;

  const _TicketReveal({
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
  });

  @override
  State<_TicketReveal> createState() => _TicketRevealState();
}

class _TicketRevealState extends State<_TicketReveal> with SingleTickerProviderStateMixin {
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
              child: TicketWidget(
                title: widget.title,
                mediaType: widget.mediaType,
                rating: widget.rating,
                watchedAt: widget.watchedAt,
                width: 280,
                height: 120,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A quiet little "thank you" that settles in just under the stub once
/// it's landed — the same ordinary rabbit companion used everywhere
/// else in the app, already holding its own little ticket, giving one
/// happy hop before easing to a stop. Reads as the room itself
/// noticing tonight went well, not a separate congratulations screen.
///
/// Held back a beat behind [_TicketReveal] so it plays like a reaction
/// to the stub arriving rather than two things happening at once, and
/// left out entirely (no gap in the layout) when the rabbit companion
/// is turned off in Settings.
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
    if (!context.watch<RabbitMascotPrefsService>().enabled) {
      return const SizedBox(height: 4);
    }
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
                    const RabbitMascot(mood: RabbitMood.celebrating, size: 88),
                    const SizedBox(height: 8),
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
