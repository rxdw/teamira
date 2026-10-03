import '../partner/room/together_verdict_card.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/diary_entry.dart';
import '../../models/media_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/together_wrapped_teaser.dart';
import '../../widgets/departure_scenes.dart';
import '../../widgets/launch_drop_overlay.dart';
import '../../widgets/light_bloom.dart';
import '../../widgets/log_flow_kit.dart';
import '../../widgets/mood_tag_picker.dart' show vibePresetTags, vibePromptTitle;
import '../../widgets/review_composer.dart';
import '../../widgets/sincerity_toast.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/shuttle_submit_button.dart';
import '../../services/log_theme_service.dart';
import '../../widgets/achievement_unlock_overlay.dart';
import '../../widgets/level_up_celebration.dart';
import '../../widgets/favorite_toggle.dart';
import '../../widgets/verdict_rating.dart';
import '../../services/app_translations.dart';
import '../../theme/notebook_paper.dart';
import '../../widgets/saved_celebration.dart';
import '../../widgets/share_card.dart';
import '../../widgets/share_sheet.dart';
import '../../widgets/decide_motion.dart' show SecondaryActionButton;
import '../../theme/clay_kit.dart';

// A handful of deep-space waypoints — same "plausible, seeded, never
// reshuffles" trick as the train theme's route match: a title always
// lands the same one, standing in for the route plaque so the confirm
// step has its own destination board.
const List<String> _shuttleDestinations = [
  'Kepler Reach',
  'the Vela Cluster',
  'Proxima Dock',
  'the Lyra Belt',
  'Aurora Station',
  'the Coalsack Gate',
  'Halcyon Orbit',
  'the Perseus Rim',
];

// A quiet aside for the confirm step — the kind of small thing you'd
// notice from your berth while the pad's still lit up outside the
// window. One is picked per title (see pickAmbientLine) so it stays
// put on rebuilds.
const List<String> _shuttleAmbientLines = [
  "ground crew's still doing one last check outside",
  'someone in the next berth is already half asleep',
  'the porthole is warm from the launch lights',
  "comms are down low, just enough to notice",
  'a few late arrivals still finding their berth',
  'the sky outside looks quiet tonight',
];

/// The shuttle theme's real logging flow — same shape as
/// [CinemaLogScreen] and [CoachLogScreen], dressed for a berth on a
/// shuttle bound for orbit instead of a screening or a road trip: pick
/// a berth first, then settle how the evening went, confirm, then
/// watch the capsule actually ignite and lift off.
class ShuttleLogScreen extends StatefulWidget {
  final MediaItem item;
  final int? season;
  final int? episode;
  final int? episodeCount;
  // Pre-checks the "watched with partner" toggle below — see
  // WatchingChoiceScreen's own doc comment for why (the co-viewing
  // planned grid's "смотрю" button opens this already knowing the
  // evening was shared).
  final bool initialWatchedWithPartner;
  const ShuttleLogScreen({
    super.key,
    required this.item,
    this.season,
    this.episode,
    this.episodeCount,
    this.initialWatchedWithPartner = false,
  });

  @override
  State<ShuttleLogScreen> createState() => _ShuttleLogScreenState();
}

enum _Step { berth, details, vibe, confirm, igniting, pass }

enum _When { today, yesterday, custom }

class _ShuttleLogScreenState extends State<ShuttleLogScreen> with TickerProviderStateMixin {
  static const int _rows = 6;
  static const int _cols = 6;
  static const List<String> _rowLetters = ['A', 'B', 'C', 'D', 'E', 'F'];

  late final Set<int> _taken;
  late final AnimationController _dust;
  late final AnimationController _breathe;
  late final AnimationController _preshow;
  late final List<LightMote> _motes;
  // Seeded once per title — a plausible destination and berth gate, the
  // shuttle theme's answer to the coach's route plaque and the
  // cinema's hall number.
  late final String _destination;
  late final int _gateNumber;

  _Step _step = _Step.berth;
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
  bool _saving = false;
  String? _error;
  // Stashed the moment `_confirmAndSave` succeeds, purely so the pass
  // step's share button (below) has a real logged entry to build an
  // [EveningShareCard] from — nothing before that point needs it.
  DiaryEntry? _savedDiaryEntry;

  @override
  void initState() {
    super.initState();
    _watchedWithPartner = widget.initialWatchedWithPartner;
    final seed = widget.item.title.display;
    _taken = seededTakenSeats(seed, _rows * _cols, salt: 0x6c61756e, minTaken: 6, extraRange: 10); // 'laun'
    _motes = seededMotes(seed, 12, salt: 0x6c61756e);
    final destSeed = math.Random(seed.hashCode ^ 0x64657374); // 'dest'
    _destination = _shuttleDestinations[destSeed.nextInt(_shuttleDestinations.length)];
    _gateNumber = 1 + destSeed.nextInt(24);
    _dust = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100))..repeat(reverse: true);
    // The little pad-announcement that flickers up once while you're
    // still picking a berth, then dims itself back out — same beat as
    // the cinema's "please silence your phones" and the coach's
    // "please fasten your seatbelt".
    _preshow = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _preshow.forward();
    });
    _loadPartnerStatus();
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

  // The forward berths, nearest the viewport — marked with a small
  // glow on the grid, this theme's answer to the cinema's center-back
  // sweet spot.
  bool _isPrimeSeat(int index) {
    final row = index ~/ _cols;
    final col = index % _cols;
    return row <= 1 && col >= 1 && col <= 4;
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

  void _addCustomTag() {
    final raw = _customTagController.text.trim();
    if (raw.isEmpty) return;
    if (!_moodTags.contains(raw)) setState(() => _moodTags = [..._moodTags, raw]);
    _customTagController.clear();
  }

  Future<void> _expandReview() async {
    final result = await showReviewComposer(
      context,
      initialText: _noteController.text,
      forTitle: widget.item.title.display,
    );
    if (result != null) setState(() => _noteController.text = result);
  }

  Future<void> _confirmAndSave() async {
    // The launch actually starts the instant the button's tapped — the
    // save happens underneath that, so it never reads as a blank wait.
    setState(() { _saving = true; _error = null; _step = _Step.igniting; });
    bool failed = false;
    DiaryEntry? loggedEntry;
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
              season: widget.season,
              episode: widget.episode,
              episodeCount: widget.episodeCount,
            ),
        Future.delayed(const Duration(milliseconds: 1500)),
      ]);
      loggedEntry = results[0] as DiaryEntry;
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    if (failed) {
      setState(() { _saving = false; _step = _Step.confirm; _error = "couldn't save that just now — try again".tr; });
      return;
    }
    if (loggedEntry != null) showSincerityToasts(context, loggedEntry.sincerityAwarded);
    _savedDiaryEntry = loggedEntry;
    HapticFeedback.mediumImpact();
    unawaited(context.read<AppState>().refreshLevel());
    setState(() => _saving = false);
    await showLaunchDrop(
      context,
      title: widget.item.title.display,
      mediaType: widget.item.mediaType,
      rating: _rating > 0 ? _rating : null,
      watchedAt: _resolvedDate,
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

  void _confirmLeaveSeatStep() {
    showLeaveRouteDialog(
      context,
      routeNoun: 'launch'.tr,
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
        if (_step == _Step.berth) {
          _confirmLeaveSeatStep();
          return;
        }
        _goTo(switch (_step) {
          _Step.details => _Step.berth,
          _Step.vibe => _Step.details,
          _Step.confirm => _Step.vibe,
          _ => _Step.details,
        });
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF171A2E),
        body: Stack(
          children: [
            Positioned.fill(child: LogFlowBackdrop(dust: _dust, motes: _motes, tint: SeenlyPalette.periwinkle)),
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
        _Step.berth => _buildBerthStep(),
        _Step.details => _buildDetailsStep(),
        _Step.vibe => _buildVibeStep(),
        _Step.confirm => _buildConfirmStep(),
        _Step.igniting => _buildIgnitingStep(),
        _Step.pass => _buildPassStep(),
      };

  Widget _buildIgnitingStep() {
    return RocketLaunchScene(key: const ValueKey('igniting-step'), routeLabel: _destination);
  }

  Widget _buildBerthStep() {
    return Column(
      key: const ValueKey('berth-step'),
      children: [
        LogFlowTopBar(
          onBack: _confirmLeaveSeatStep,
          trailingLabel: 'skip'.tr,
          onTrailing: _skipToConfirm,
        ),
        CollapsingAnnouncement(
          preshow: _preshow,
          breathe: _breathe,
          text: 'please stow your things — launch is coming up'.tr,
          glow: SeenlyPalette.periwinkle,
        ),
        const SizedBox(height: 6),
        Text('choose your berth'.tr,
            style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
        const SizedBox(height: 5),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _selectedSeat == null
                ? "tonight's launch".tr
                : _selectedIsPrime
                    ? '${'settled in — berth'.tr} $_seatLabel, ${'right by the viewport'.tr}'
                    : '${'settled in — berth'.tr} $_seatLabel',
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
        Text('berths near the viewport are the good ones'.tr,
            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.periwinkle.withOpacity(0.85))),
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
                    for (int col = 0; col < _cols; col++)
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
              label: _selectedSeat == null ? 'pick a berth'.tr : '${'confirm berth'.tr} $_seatLabel',
              onTap: _selectedSeat == null ? null : () => _goTo(_Step.details),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsStep() {
    return Column(
      key: const ValueKey('details-step'),
      children: [
        LogFlowTopBar(onBack: () => _goTo(_Step.berth), trailingLabel: 'skip'.tr, onTrailing: () => _goTo(_Step.confirm)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: SeatPill(label: '${'berth'.tr} $_seatLabel'),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: ClayBoxDecoration(
                boxShadow: SeenlyPalette.flatCardShadow,color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('the pad lights are still up'.tr,
                      style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.periwinkle)),
                  const SizedBox(height: 4),
                  Text('before anything else — what did tonight leave you with?'.tr,
                      style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                  const SizedBox(height: 14),
                  VerdictRating(
                    value: _rating,
                    breathe: _breathe,
                    onChanged: (v) => setState(() => _rating = v),
                  ),
                  const SizedBox(height: 16),
                  FavoriteToggle(
                    theme: LogTheme.shuttle,
                    value: _isFavorite,
                    onChanged: (v) => setState(() => _isFavorite = v),
                  ),
                  const SizedBox(height: 22),
                  Text('when'.tr, style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.periwinkle)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: PillChip(label: 'today'.tr, active: _when == _When.today, dashed: true, fullWidth: true, onTap: () => setState(() => _when = _When.today))),
                      const SizedBox(width: 8),
                      Expanded(child: PillChip(label: 'yesterday'.tr, active: _when == _When.yesterday, dashed: true, fullWidth: true, onTap: () => setState(() => _when = _When.yesterday))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PillChip(
                          label: _when == _When.custom && _customDate != null ? '${_customDate!.month}/${_customDate!.day}' : 'pick date'.tr,
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
                    Text('together'.tr, style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.periwinkle)),
                    const SizedBox(height: 10),
                    PillChip(
                      label: "${'watched with'.tr} $_partnerUsername",
                      active: _watchedWithPartner,
                      onTap: () => setState(() => _watchedWithPartner = !_watchedWithPartner),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text('a note to your future self'.tr, style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.periwinkle)),
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

  Widget _buildVibeStep() {
    return Column(
      key: const ValueKey('vibe-step'),
      children: [
        LogFlowTopBar(onBack: () => _goTo(_Step.details), trailingLabel: 'skip'.tr, onTrailing: () => _goTo(_Step.confirm)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: SeatPill(label: '${'berth'.tr} $_seatLabel'),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: ClayBoxDecoration(
                boxShadow: SeenlyPalette.flatCardShadow,color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vibePromptTitle(_rating), style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.periwinkle)),
                  const SizedBox(height: 4),
                  Text('pick what\'s still with you as the engines cool'.tr,
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
                          decoration: BoxDecoration(color: SeenlyPalette.periwinkle, shape: BoxShape.circle),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: PrimaryButton(
            label: 'continue'.tr,
            onTap: () => _goTo(_Step.confirm),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmStep() {
    final item = widget.item;
    return Column(
      key: const ValueKey('confirm-step'),
      children: [
        LogFlowTopBar(onBack: () => _goTo(_Step.details)),
        const SizedBox(height: 4),
        Text('ready for launch?'.tr, style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
        const SizedBox(height: 4),
        Text("one more look before it's official".tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.65))),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              children: [
                Container(
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
                                Text('${'berth'.tr} $_seatLabel · ${mediaTypeLabel(item.mediaType)}', style: SeenlyText.metaLabel),
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
                const SizedBox(height: 26),
                AnimatedBuilder(
                  animation: _breathe,
                  builder: (_, __) => GlowPlaque(
                    text: '${'GATE'.tr} B$_gateNumber · $_destination',
                    breathe: _breathe.value,
                    glow: SeenlyPalette.periwinkle,
                  ),
                ),
                AnimatedBuilder(
                  animation: _breathe,
                  builder: (_, __) => AmbientNote(
                    icon: Icons.rocket_launch_outlined,
                    tint: SeenlyPalette.periwinkle,
                    text: pickAmbientLine(item.title.display, _shuttleAmbientLines, salt: 0x6c61756e),
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
          child: ShuttleSubmitButton(label: 'confirm launch'.tr, loading: _saving, onTap: _saving ? null : _confirmAndSave),
        ),
      ],
    );
  }

  Widget _buildPassStep() {
    return Column(
      key: const ValueKey('pass-step'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        _PassStepPoster(posterUrl: widget.item.posterUrl, title: widget.item.title.display, mediaType: widget.item.mediaType),
        const SizedBox(height: 18),
        Text('cleared for orbit'.tr, style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
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
        _LaunchTicketReveal(
          title: widget.item.title.display,
          mediaType: widget.item.mediaType,
          rating: _rating > 0 ? _rating : null,
          watchedAt: _resolvedDate,
          destination: _destination,
          gateNumber: _gateNumber,
          berthLabel: _seatLabel,
        ),
        _PassStepThanks(),
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
                  label: 'keep the stub'.tr,
                  onTap: () async {
                    // Right as the person is about to leave the launch ritual
                    // behind — one more beat (or two), if this save leveled
                    // them up and/or a badge just came with it, before
                    // actually stepping away.
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

  String _verdictFor(int rating) {
    final idx = ((rating - 1) * kDefaultVerdictLabels.length / 10).floor().clamp(0, kDefaultVerdictLabels.length - 1);
    return kDefaultVerdictLabels[idx];
  }
}

/// The poster, floating in with a little overshoot — same beat as the
/// cinema and coach themes' own pass-step poster reveal.
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
                height: 132,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 10))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(widget.posterUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.mediaColor(widget.mediaType))),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The boarding-pass-style ticket that settles into place on the pass
/// step — departure/destination/berth stamped on it, this theme's
/// answer to the cinema's torn stub and the coach's boarding pass.
class _LaunchTicketReveal extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  final String destination;
  final int gateNumber;
  final String berthLabel;

  const _LaunchTicketReveal({
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
    required this.destination,
    required this.gateNumber,
    required this.berthLabel,
  });

  @override
  State<_LaunchTicketReveal> createState() => _LaunchTicketRevealState();
}

class _LaunchTicketRevealState extends State<_LaunchTicketReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.ratingColor(widget.rating);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOutBack.transform(_c.value.clamp(0.0, 1.0));
        final fade = Curves.easeOut.transform(_c.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 20),
            child: Container(
              width: 260,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: ClayBoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(16),
                boxShadow: SeenlyPalette.softShadow,
                border: Border(left: BorderSide(color: color, width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(Icons.rocket_launch, size: 16, color: color),
                      Text('${'GATE'.tr} B${widget.gateNumber}', style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(widget.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(italic: true, size: 15.5, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(widget.destination, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.periwinkle)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashLinePainter(color: SeenlyPalette.border)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${'berth'.tr} ${widget.berthLabel}', style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                      Text('${widget.watchedAt.day} ${_months[widget.watchedAt.month - 1]}',
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashLinePainter extends CustomPainter {
  final Color color;
  _DashLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashLinePainter oldDelegate) => false;
}

/// A quiet "thank you" that settles in below the ticket — same beat as
/// the other themes' pass-step sign-off.
class _PassStepThanks extends StatefulWidget {
  @override
  State<_PassStepThanks> createState() => _PassStepThanksState();
}

class _PassStepThanksState extends State<_PassStepThanks> with SingleTickerProviderStateMixin {
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
                child: Text(
                  'thank you for tonight'.tr,
                  style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.paper.withOpacity(0.82)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
