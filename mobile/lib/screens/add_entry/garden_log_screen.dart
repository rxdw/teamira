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
import '../../widgets/garden_submit_button.dart';
import '../../widgets/light_bloom.dart';
import '../../widgets/log_flow_kit.dart';
import '../../widgets/mood_tag_picker.dart' show vibePresetTags, vibePromptTitle;
import '../../widgets/review_composer.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../services/log_theme_service.dart';
import '../../widgets/favorite_toggle.dart';
import '../../widgets/achievement_unlock_overlay.dart';
import '../../widgets/level_up_celebration.dart';
import '../../widgets/verdict_rating.dart';
import '../../widgets/wow_motion.dart' show PressScale;
import '../../services/app_translations.dart';
import '../../services/locale_service.dart';

// This bed's own verdict words — same shape VerdictRating expects from
// the cinema flow (10 entries, low to high), spoken the way you'd
// describe how something grew rather than how a show played.
const List<String> _gardenVerdictLabels = [
  "didn't take root",
  'wilted early',
  "glad that's done",
  'grew okay',
  'decent little sprout',
  'grew well',
  'thriving',
  'in full bloom',
  'one for the garden',
  'perfect bloom',
];

// A quiet aside for the confirm step — the kind of small thing you'd
// notice crouched by the bed while the light's still going. One is
// picked per title (see pickAmbientLine) so it stays put on rebuilds.
const List<String> _gardenAmbientLines = [
  'the soil here still holds a bit of the day\'s warmth',
  "a moth's been circling the porch light all evening",
  'dew hasn\'t settled on the leaves yet — still early',
  'something nearby just started up its evening hum',
  'the air smells like it rained not long ago',
  'the last bit of dusk is caught in the leaves',
];

/// The garden theme's real logging flow — same shape as the coach and
/// cinema flows, dressed for a little window box instead of a ride or
/// a screening: choose an empty spot, settle how tonight went, confirm,
/// then watch the seed actually take root and bloom.
class GardenLogScreen extends StatefulWidget {
  final MediaItem item;
  final int? season;
  final int? episode;
  final int? episodeCount;
  const GardenLogScreen({super.key, required this.item, this.season, this.episode, this.episodeCount});

  @override
  State<GardenLogScreen> createState() => _GardenLogScreenState();
}

enum _Step { spot, details, vibe, castPick, confirm, dusk, bloom }

enum _When { today, yesterday, custom }

class _GardenLogScreenState extends State<GardenLogScreen> with TickerProviderStateMixin {
  static const int _slots = 8;

  late final Set<int> _taken;
  late final AnimationController _dust;
  late final AnimationController _sway; // loops: a gentle breeze over the box
  late final AnimationController _preshow;
  late final List<LightMote> _motes;

  _Step _step = _Step.spot;
  int? _selectedSpot;
  int _rating = 0;
  bool _isFavorite = false;
  List<String> _moodTags = [];
  // Up to 3 cast members picked as tonight's standouts — same optional
  // aside as the cinema flow's own castPick step, just riding along
  // with the garden theme. See cinema_log_screen.dart's
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
    _taken = seededTakenSeats(seed, _slots, salt: 0x67726f77, minTaken: 1, extraRange: 3); // 'grow'
    _motes = seededMotes(seed, 10, salt: 0x67726f77);
    _dust = AnimationController(vsync: this, duration: const Duration(seconds: 11))..repeat();
    _sway = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    // The quiet little notice that flickers up once while you're still
    // choosing a spot, then dims itself back out.
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

  String get _spotLabel => _selectedSpot == null ? '—' : 'spot ${_selectedSpot! + 1}';

  // The middle of the box catches the most afternoon sun, away from
  // the shade the window frame throws over either end — marked with
  // the same small glow the other themes give their best spots.
  bool _isSunnySpot(int index) => index >= 2 && index <= 5;

  bool get _selectedIsSunny => _selectedSpot != null && _isSunnySpot(_selectedSpot!);

  void _chooseSpot(int index) {
    if (_taken.contains(index)) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedSpot = index);
  }

  void _goTo(_Step step) {
    HapticFeedback.selectionClick();
    setState(() => _step = step);
  }

  void _skipToConfirm() {
    if (_selectedSpot == null) {
      final free = List.generate(_slots, (i) => i).where((i) => !_taken.contains(i)).toList();
      if (free.isNotEmpty) _selectedSpot = free[math.Random().nextInt(free.length)];
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
    // Dusk settles over the window box the instant the button's tapped
    // — the save happens underneath that quiet beat, so the bloom that
    // follows never lands on a blank wait.
    setState(() { _saving = true; _error = null; _step = _Step.dusk; });
    bool failed = false;
    try {
      await Future.wait([
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
    setState(() { _saving = false; _step = _Step.bloom; });
  }

  @override
  void dispose() {
    _dust.dispose();
    _sway.dispose();
    _preshow.dispose();
    _noteController.dispose();
    _customTagController.dispose();
    super.dispose();
  }

  void _confirmLeaveSpotStep() {
    showLeaveRouteDialog(
      context,
      routeNoun: 'planting',
      onReturnToRoute: () => Navigator.of(context).pop(),
      onEndRoute: () => Navigator.of(context).pop(false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _step == _Step.bloom;
    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_step == _Step.spot) {
          _confirmLeaveSpotStep();
          return;
        }
        _goTo(switch (_step) {
          _Step.details => _Step.spot,
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
            Positioned.fill(child: LogFlowBackdrop(dust: _dust, motes: _motes, tint: SeenlyPalette.sage)),
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
        _Step.spot => _buildSpotStep(),
        _Step.details => _buildDetailsStep(),
        _Step.vibe => _buildVibeStep(),
        _Step.castPick => _buildCastPickStep(),
        _Step.confirm => _buildConfirmStep(),
        _Step.dusk => _buildDuskStep(),
        _Step.bloom => _buildBloomStep(),
      };

  // ---------------------------------------------------------------
  // Step 3.5 — dusk settles over the window box while tonight's entry
  // saves underneath it, right before the seed takes root.
  // ---------------------------------------------------------------
  Widget _buildDuskStep() {
    return GardenDuskScene(key: const ValueKey('dusk-step'), spotLabel: _spotLabel);
  }

  // ---------------------------------------------------------------
  // Step 1 — choose a spot in the window box. Same soil-mound glyph
  // the modal picker drew, just bigger and with a fuller box, since
  // this is the whole screen's centerpiece now.
  // ---------------------------------------------------------------
  Widget _buildSpotStep() {
    return Column(
      key: const ValueKey('spot-step'),
      children: [
        LogFlowTopBar(
          onBack: _confirmLeaveSpotStep,
          trailingLabel: 'skip'.tr,
          onTrailing: _skipToConfirm,
        ),
        CollapsingAnnouncement(
          preshow: _preshow,
          breathe: _sway,
          text: 'the birds have gone quiet for the night'.tr,
          glow: SeenlyPalette.sage,
        ),
        const SizedBox(height: 6),
        Text('choose a spot'.tr,
            style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
        const SizedBox(height: 5),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _selectedSpot == null
                ? "tonight's little planting"
                : _selectedIsSunny
                    ? 'settled — $_spotLabel, right where the sun lands'
                    : 'settled — $_spotLabel is tonight\'s',
            key: ValueKey('$_selectedSpot-$_selectedIsSunny'),
            style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.68)),
          ),
        ),
        const SizedBox(height: 16),
        GlowPlaque(text: widget.item.title.display.toUpperCase(), breathe: 0.5, glow: SeenlyPalette.sage),
        const SizedBox(height: 8),
        Text('golden mounds catch the most sun'.tr, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.mustard.withOpacity(0.8))),
        const Spacer(),
        AnimatedBuilder(
          animation: _sway,
          builder: (_, __) => _WindowBox(
            slots: _slots,
            taken: _taken,
            selected: _selectedSpot,
            sway: _sway.value,
            isSunny: _isSunnySpot,
            onTap: _chooseSpot,
          ),
        ),
        const Spacer(flex: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
          child: Opacity(
            opacity: _selectedSpot == null ? 0.45 : 1.0,
            child: PrimaryButton(
              label: _selectedSpot == null ? 'pick a spot'.tr : '${'plant it at'.tr} $_spotLabel',
              onTap: _selectedSpot == null ? null : () => _goTo(_Step.details),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Step 2 — how did tonight grow? Same picker language as the box.
  // ---------------------------------------------------------------
  Widget _buildDetailsStep() {
    return Column(
      key: const ValueKey('details-step'),
      children: [
        LogFlowTopBar(onBack: () => _goTo(_Step.spot), trailingLabel: 'skip'.tr, onTrailing: () => _goTo(_Step.confirm)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: SeatPill(label: _spotLabel),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: _PlanterBoxFrame(
              child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: BoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(18),
                boxShadow: SeenlyPalette.softShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('the dew hasn\'t settled yet'.tr, style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.accent)),
                  const SizedBox(height: 4),
                  Text('before you head back inside — what did tonight leave you with?'.tr,
                      style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _sway,
                    builder: (_, child) => _SoilFrame(sway: _sway.value, child: child!),
                    child: VerdictRating(
                      value: _rating,
                      breathe: _sway,
                      labels: _gardenVerdictLabels,
                      idleLabel: 'tap a bud to rate it',
                      onChanged: (v) => setState(() => _rating = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FavoriteToggle(
                    theme: LogTheme.garden,
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
          child: SeatPill(label: _spotLabel),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: _PlanterBoxFrame(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: BoxDecoration(
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: SeenlyPalette.softShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vibePromptTitle(_rating), style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.accent)),
                    const SizedBox(height: 4),
                    Text('before it goes back in the ground — what took root?'.tr,
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
          child: SeatPill(label: _spotLabel),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: _PlanterBoxFrame(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                decoration: BoxDecoration(color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(18), boxShadow: SeenlyPalette.softShadow),
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
                          _GardenCastPickTile(
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
        Text('ready to plant it?'.tr, style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
        const SizedBox(height: 4),
        Text("one more look before it's official".tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.65))),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              children: [
                _PlanterBoxFrame(
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
                            Text('$_spotLabel · ${item.mediaType}', style: SeenlyText.metaLabel),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 28, color: SeenlyPalette.border),
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
                  animation: _sway,
                  builder: (_, __) => _BedStrip(
                    selectedSpot: _selectedSpot ?? -1,
                    slots: _slots,
                    spotLabel: _spotLabel,
                    sway: _sway.value,
                  ),
                ),
                AnimatedBuilder(
                  animation: _sway,
                  builder: (_, __) => AmbientNote(
                    icon: Icons.eco_outlined,
                    tint: SeenlyPalette.sage,
                    text: pickAmbientLine(item.title.display, _gardenAmbientLines, salt: 0x67726f77),
                    breathe: _sway.value,
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
          child: GardenSubmitButton(label: 'confirm planting'.tr, loading: _saving, onTap: _saving ? null : _confirmAndSave),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Step 4 — the seed takes root: it prints itself into bloom rather
  // than needing a drag, since by now the choice is already made and
  // saved — a little pollen lifts free, then the keepsake card settles
  // in underneath, date and all.
  // ---------------------------------------------------------------
  Widget _buildBloomStep() {
    return Column(
      key: const ValueKey('bloom-step'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        _PassStepPoster(
          posterUrl: widget.item.posterUrl,
          title: widget.item.title.display,
          mediaType: widget.item.mediaType,
        ),
        const SizedBox(height: 18),
        Text('tucked in'.tr, style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.paper)),
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
        const SizedBox(height: 16),
        _BloomReveal(
          title: widget.item.title.display,
          mediaType: widget.item.mediaType,
          rating: _rating > 0 ? _rating : null,
          watchedAt: _resolvedDate,
        ),
        const _BloomStepMascot(),
        const Spacer(flex: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: PrimaryButton(
            label: 'leave it growing'.tr,
            onTap: () async {
              // Right as the person is about to leave the planting
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
              if (context.mounted) Navigator.of(context).pop(true);
            },
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

  // Same lookup VerdictRating uses internally, against this bed's own
  // words, so the confirm card echoes the exact one already chosen.
  String _verdictFor(int rating) {
    final idx = ((rating - 1) * _gardenVerdictLabels.length / 10).floor().clamp(0, _gardenVerdictLabels.length - 1);
    return _gardenVerdictLabels[idx];
  }
}

/// The full window box of planting spots — a wide soil trough with a
/// row of mounds, most empty and tappable, a couple already grown in.
/// Same shapes the modal picker drew, just given a whole shelf's worth
/// of room instead of five spots squeezed into a dialog.
class _WindowBox extends StatelessWidget {
  final int slots;
  final Set<int> taken;
  final int? selected;
  final double sway; // 0..1..0, a gentle loop
  final bool Function(int) isSunny;
  final ValueChanged<int> onTap;

  const _WindowBox({required this.slots, required this.taken, required this.selected, required this.sway, required this.isSunny, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final swayDeg = (sway - 0.5) * 3;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(14, 26, 14, 14),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.97),
        borderRadius: BorderRadius.circular(24),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < slots; i++)
                  _Spot(
                    isTaken: taken.contains(i),
                    isSelected: selected == i,
                    isChosenElsewhere: selected != null && selected != i,
                    isSunny: isSunny(i),
                    swayDeg: swayDeg,
                    onTap: () => onTap(i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 16,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SeenlyPalette.mustard, Color(0xFFB9863C)],
              ),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ],
      ),
    );
  }
}

class _Spot extends StatelessWidget {
  final bool isTaken;
  final bool isSelected;
  final bool isChosenElsewhere;
  final bool isSunny;
  final double swayDeg;
  final VoidCallback onTap;

  const _Spot({
    required this.isTaken,
    required this.isSelected,
    required this.isChosenElsewhere,
    required this.isSunny,
    required this.swayDeg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (isTaken || isChosenElsewhere) ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: isChosenElsewhere ? 0.35 : 1,
        duration: const Duration(milliseconds: 220),
        child: SizedBox(
          width: 34,
          child: (isTaken || isSelected)
              ? _grownStem()
              : Transform.rotate(
                  angle: swayDeg * math.pi / 180 * 0.5,
                  alignment: Alignment.bottomCenter,
                  child: _emptyMound(),
                ),
        ),
      ),
    );
  }

  Widget _emptyMound() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(Icons.add, size: 16, color: SeenlyPalette.inkFaint.withOpacity(0.5)),
        const SizedBox(height: 5),
        Container(
          width: 28,
          height: 10,
          decoration: BoxDecoration(
            color: isSunny ? SeenlyPalette.mustard.withOpacity(0.55) : SeenlyPalette.cork,
            borderRadius: BorderRadius.circular(5),
            boxShadow: isSunny
                ? [BoxShadow(color: SeenlyPalette.mustard.withOpacity(0.35), blurRadius: 8, spreadRadius: 0.5)]
                : null,
          ),
        ),
      ],
    );
  }

  Widget _grownStem() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: isSelected ? SeenlyPalette.accent : SeenlyPalette.sage, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(Icons.eco, size: 12, color: SeenlyPalette.paper),
        ),
        const SizedBox(height: 3),
        Container(width: 3, height: 32, color: (isSelected ? SeenlyPalette.accent : SeenlyPalette.sage).withOpacity(0.8)),
        const SizedBox(height: 3),
        Container(width: 28, height: 10, decoration: BoxDecoration(color: SeenlyPalette.cork, borderRadius: BorderRadius.circular(5))),
      ],
    );
  }
}

/// One selectable face on the garden theme's cast-pick step — mirrors
/// cinema_log_screen.dart's own _CastPickTile (same fixed-width tile,
/// full name allowed to wrap rather than being clipped, and the
/// character name shown underneath when TMDB has one) just re-skinned
/// with this theme's palette.
class _GardenCastPickTile extends StatelessWidget {
  final CastMember member;
  final bool selected;
  final bool atCap;
  final VoidCallback onTap;

  const _GardenCastPickTile({
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

/// Wraps the *whole* details card in a real planter box instead of a
/// plain rounded card sitting on the page — a clay-toned trough all
/// the way round with a soil-mound lip peeking along the bottom edge,
/// the paper card itself sitting inside like a seed tray set down in
/// the box. Mirrors what the cinema theme's filmstrip card does for
/// its own details step, just dressed for a window box instead of a
/// reel.
///
/// Deliberately a plain Container + Stack (no IntrinsicHeight, no
/// LayoutBuilder around the content) — the content underneath has
/// TextFields in it, and running an intrinsic-size layout pass over a
/// TextField subtree is what caused the cinema screen's blank-screen
/// layout crash before that got fixed. This widget just sizes to its
/// already-laid-out child, no extra pass needed.
class _PlanterBoxFrame extends StatelessWidget {
  final Widget child;
  const _PlanterBoxFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SeenlyPalette.clay,
        borderRadius: BorderRadius.circular(22),
        boxShadow: SeenlyPalette.softShadow,
      ),
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 15),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: child,
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: -1,
            child: IgnorePointer(
              child: CustomPaint(size: const Size(double.infinity, 16), painter: _SoilMoundsPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small bed board below the confirm card showing the rest of
/// tonight's window box as a handful of already-grown stems instead of
/// just the single spot already printed on the card — a few soft
/// glimmers drifting above them like fireflies settling in for the
/// evening, the chosen spot picked out in the same accent the picker
/// uses, all of it swaying on the same gentle breeze as everywhere
/// else in this ritual. The garden theme's answer to the coach flow's
/// route strip and the cinema's house board: framed in its own soft
/// panel so the space under the card reads as "still out in the
/// garden" rather than empty page.
class _BedStrip extends StatelessWidget {
  final int selectedSpot;
  final int slots;
  final String spotLabel;
  final double sway; // 0..1..0, a gentle loop

  const _BedStrip({required this.selectedSpot, required this.slots, required this.spotLabel, required this.sway});

  @override
  Widget build(BuildContext context) {
    final swayDeg = (sway - 0.5) * 5;
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
          SizedBox(height: 16, width: double.infinity, child: _NightGlimmers(t: sway)),
          const SizedBox(height: 6),
          SizedBox(
            height: 62,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < slots; i++)
                  Transform.rotate(
                    angle: (swayDeg + (i.isEven ? 1 : -1) * 1.6) * math.pi / 180,
                    alignment: Alignment.bottomCenter,
                    child: _BedSprout(height: 18.0 + (i % 3) * 10, isSelected: i == selectedSpot),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [SeenlyPalette.mustard, Color(0xFFB9863C)]),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 12),
          Text('$spotLabel${', tucked in among the rest · tonight'.tr}', style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.paper.withOpacity(0.45))),
        ],
      ),
    );
  }
}

/// A few soft, unevenly-placed glimmers drifting above the bed — the
/// garden theme's answer to the cinema's marquee bulbs, standing in
/// for a couple of fireflies settling in over the box as the evening
/// deepens rather than a chasing string of lights.
class _NightGlimmers extends StatelessWidget {
  final double t; // 0..1..0, a gentle loop
  const _NightGlimmers({required this.t});

  static const List<double> _lefts = [0.08, 0.24, 0.42, 0.58, 0.74, 0.9];
  static const List<double> _phases = [0.0, 0.4, 0.15, 0.65, 0.3, 0.8];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Stack(
          children: [
            for (int i = 0; i < _lefts.length; i++)
              Positioned(
                left: _lefts[i] * w,
                top: i.isEven ? 0 : 6,
                child: Opacity(
                  opacity: (0.25 + 0.6 * ((math.sin((t + _phases[i]) * 2 * math.pi) + 1) / 2)).clamp(0.0, 1.0),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SeenlyPalette.mustard,
                      boxShadow: [BoxShadow(color: SeenlyPalette.mustard.withOpacity(0.5), blurRadius: 5, spreadRadius: 0.5)],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A single small grown stem — a leaf-circle head on a short stalk,
/// same shape language the spot picker uses for an already-taken spot,
/// just small enough to sit in a row.
class _BedSprout extends StatelessWidget {
  final double height;
  final bool isSelected;

  const _BedSprout({required this.height, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? SeenlyPalette.accent : SeenlyPalette.sage;
    return SizedBox(
      width: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(Icons.eco, size: 9, color: SeenlyPalette.paper),
          ),
          const SizedBox(height: 3),
          Container(width: 2.4, height: height, color: color.withOpacity(0.8)),
        ],
      ),
    );
  }
}

/// Dresses the rating step's box like a little slice of the window box
/// itself instead of a plain rounded card — pale evening sky above,
/// a soil-toned strip along the bottom that sways very slightly with
/// the same breeze as the spot picker, and a couple of small mounds
/// breaking the line so it never reads as a flat bar.
class _SoilFrame extends StatelessWidget {
  final Widget child;
  final double sway;
  const _SoilFrame({required this.child, required this.sway});

  @override
  Widget build(BuildContext context) {
    final swayDeg = (sway - 0.5) * 2;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [SeenlyPalette.background, Color.lerp(SeenlyPalette.background, SeenlyPalette.sage, 0.16)!],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Transform.rotate(
                angle: swayDeg * math.pi / 180 * 0.3,
                child: CustomPaint(size: const Size(double.infinity, 20), painter: _SoilMoundsPainter()),
              ),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18), child: child),
          ],
        ),
      ),
    );
  }
}

/// A soft, uneven soil line with two small mounds — the same trough
/// tone the window box uses — just enough shape that the ground under
/// the hearts isn't a straight bar.
class _SoilMoundsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [SeenlyPalette.mustard, Color(0xFFB9863C)],
      ).createShader(Rect.fromLTWH(0, 0, w, size.height));
    final path = Path()..moveTo(0, size.height * 0.55);
    path.quadraticBezierTo(w * 0.18, size.height * 0.15, w * 0.34, size.height * 0.5);
    path.quadraticBezierTo(w * 0.5, size.height * 0.85, w * 0.66, size.height * 0.45);
    path.quadraticBezierTo(w * 0.82, size.height * 0.1, w, size.height * 0.5);
    path.lineTo(w, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SoilMoundsPainter oldDelegate) => false;
}

/// The final reveal: the seed opens into full bloom on its own — a
/// ring of petals unfurling around the media's icon with a lift of
/// golden pollen — then the keepsake card eases in beneath it with
/// tonight's date, the garden's answer to the coach's pass sliding
/// out or the cinema's stub tearing free.
/// The poster leads the reveal — the one picture in the whole flow that's
/// actually *of* the thing you watched, rather than a stylized marker.
/// Settles in a beat before [_BloomReveal], the same soft
/// overshoot-and-fade every other landing in this ritual uses, so the
/// two read as one small sequence — poster first, then the marker
/// blooming in underneath — instead of everything arriving at once.
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

class _BloomReveal extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;

  const _BloomReveal({required this.title, required this.mediaType, required this.rating, required this.watchedAt});

  @override
  State<_BloomReveal> createState() => _BloomRevealState();
}

class _BloomRevealState extends State<_BloomReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _open;
  late final List<_PollenMote> _pollen;

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];
  // Short Russian month abbreviations for the same date line — not a 
  // literal word-for-word .tr swap (that table has no per-word case 
  // handling), just a parallel three-letter list in the same slot order.
  static const _monthsRu = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  @override
  void initState() {
    super.initState();
    _pollen = _makePollen(widget.title, widget.watchedAt);
    _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 950))..forward();
  }

  static List<_PollenMote> _makePollen(String title, DateTime watchedAt) {
    final r = math.Random(Object.hash(title, watchedAt, 'pollen'));
    return List.generate(10, (i) {
      final angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.3;
      return _PollenMote(angle: angle, distance: 24 + r.nextDouble() * 56, lift: 40 + r.nextDouble() * 70, size: 2.6 + r.nextDouble() * 2.6);
    });
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glowColor = SeenlyPalette.ratingColor(widget.rating);
    return AnimatedBuilder(
      animation: _open,
      builder: (_, __) {
        final openV = _open.value;
        final spread = Curves.elasticOut.transform(openV.clamp(0.0, 1.0).toDouble());
        final cardT = Curves.easeOutCubic.transform(((openV - 0.35) / 0.45).clamp(0.0, 1.0).toDouble());
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _PollenBurst(t: openV, motes: _pollen, color: glowColor),
                  _OpenBud(spread: spread, color: glowColor, mediaType: widget.mediaType),
                ],
              ),
            ),
            Transform.translate(
              offset: Offset(0, (1 - cardT) * 16),
              child: Opacity(
                opacity: cardT.clamp(0.0, 1.0).toDouble(),
                child: Container(
                  width: 240,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  decoration: BoxDecoration(color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(20), boxShadow: SeenlyPalette.softShadow),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(italic: true, size: 15.5, weight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      Text('${widget.watchedAt.day} ${(LocaleService.appIsRussian ? _monthsRu : _months)[widget.watchedAt.month - 1]} ${'· bloomed in the bed'.tr}',
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A quiet little "thank you" that settles in just under the keepsake
/// once it's bloomed.
///
/// Held back a beat behind [_BloomReveal]'s longer bloom animation so
/// it plays like a reaction to the bud settling rather than two things
/// happening at once.
class _BloomStepMascot extends StatefulWidget {
  const _BloomStepMascot();

  @override
  State<_BloomStepMascot> createState() => _BloomStepMascotState();
}

class _BloomStepMascotState extends State<_BloomStepMascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
    _delay = Timer(const Duration(milliseconds: 650), () {
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

class _OpenBud extends StatelessWidget {
  final double spread;
  final Color color;
  final String mediaType;
  const _OpenBud({required this.spread, required this.color, required this.mediaType});

  @override
  Widget build(BuildContext context) {
    final s = spread.clamp(0.0, 1.15).toDouble();
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        for (int p = 0; p < 8; p++)
          Transform.rotate(
            angle: p * (math.pi * 2 / 8),
            child: Transform.translate(
              offset: Offset(0, -30 * s),
              child: Opacity(
                opacity: s.clamp(0.0, 1.0).toDouble(),
                child: Container(
                  width: 18 + 12 * s,
                  height: 22 + 16 * s,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(color, Colors.white, 0.35)!, color]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
        Opacity(
          opacity: (1 - s * 1.6).clamp(0.0, 1.0).toDouble(),
          child: Container(width: 26, height: 40, decoration: BoxDecoration(color: SeenlyPalette.sage, borderRadius: BorderRadius.circular(14))),
        ),
        Transform.scale(
          scale: 0.7 + 0.3 * s.clamp(0.0, 1.0).toDouble(),
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(color: Color(0xFFF0DFA0), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(_mediaIcon(mediaType), size: 15, color: SeenlyPalette.ink.withOpacity(0.65)),
          ),
        ),
      ],
    );
  }

  IconData _mediaIcon(String mediaType) {
    switch (mediaType) {
      case 'movie':
        return Icons.local_movies_outlined;
      case 'series':
      case 'anime':
        return Icons.live_tv_outlined;
      case 'game':
        return Icons.sports_esports_outlined;
      case 'book':
      case 'manga':
        return Icons.menu_book_outlined;
      default:
        return Icons.movie_creation_outlined;
    }
  }
}

class _PollenMote {
  final double angle;
  final double distance;
  final double lift;
  final double size;
  const _PollenMote({required this.angle, required this.distance, required this.lift, required this.size});
}

class _PollenBurst extends StatelessWidget {
  final double t;
  final List<_PollenMote> motes;
  final Color color;
  const _PollenBurst({required this.t, required this.motes, required this.color});

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final burstT = Curves.easeOut.transform((t / 0.4).clamp(0.0, 1.0).toDouble());
    final riseT = Curves.easeOut.transform(((t - 0.1) / 0.9).clamp(0.0, 1.0).toDouble());
    final opacity = 1 - Curves.easeIn.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0).toDouble());
    if (opacity <= 0) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: motes.map((m) {
        final dx = math.cos(m.angle) * m.distance * burstT;
        final dy = math.sin(m.angle) * m.distance * burstT - riseT * m.lift;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0).toDouble(),
            child: Container(width: m.size, height: m.size, decoration: BoxDecoration(shape: BoxShape.circle, color: Color.lerp(color, const Color(0xFFF0DFA0), 0.6)!)),
          ),
        );
      }).toList(),
    );
  }
}
