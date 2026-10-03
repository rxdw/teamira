import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/profile_stats.dart';
import '../../services/log_theme_service.dart';
import '../../state/app_state.dart';
import '../../theme/log_theme_copy.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/achievement_badge.dart';
import '../../widgets/level_hero_effects.dart';
import '../../widgets/small_pieces.dart' show DashedBox;
import '../../widgets/soft_motion.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/together_motion.dart' show HeartbeatIcon;
import '../../widgets/user_avatar.dart';
import '../../widgets/wow_motion.dart';
import '../../services/app_translations.dart';
import '../../services/locale_service.dart';
import '../../theme/clay_kit.dart';

const _kMonthNames = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
// Genitive case ("since ___") — a different form from the nominative
// month names used e.g. on _MiniCalendar's header, so this stays its
// own array rather than going through the generic word-for-word .tr
// table, which has no notion of grammatical case.
const _kMonthNamesRuGenitive = [
  '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

const double _kBackdropHeight = 400;
const double _kAvatarSize = 132;

/// "12 400" / "12,400" — thousands grouped the way the interface language
/// expects, for the big points counter.
String _groupThousands(int n) {
  final s = n.abs().toString();
  final sep = LocaleService.appIsRussian ? '\u00A0' : ',';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(sep);
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

// Two short phrases whose word order differs between the languages, so they
// can't be built by gluing a translated fragment onto a number.
String _pointsToGo(int n) => LocaleService.appIsRussian ? 'ещё $n' : '$n to go';
String _reachedAt(int points) => LocaleService.appIsRussian ? 'достигнут на $points' : 'reached at $points';

/// The person's own profile — identity (avatar, nickname, status, all
/// editable right here by tapping) up top, then everything that used to
/// be the whole screen (level ring, activity breakdown, level path) moved
/// down below it. Opened by tapping the streak+level card on Profile. Same
/// real numbers as before (level, points, progress — see
/// ProfileService.level / backend/app/routers/profile.py::get_level),
/// plus a raw-count breakdown of what's actually been logged (see
/// LogThemeCopy.levelPointsNote for the themed prose version of the same
/// idea). For exactly how those add up to `points`, see the Sincerity
/// screen's own transaction history instead — see
/// backend/app/sincerity.py's module docstring for why that ledger, not a
/// second formula here, is the one honest source for that now. The
/// breakdown also lists evenings watched together, collected challenges
/// and share cards — see backend/app/routers/profile.py::
/// compute_level_for_user.
///
/// Motion (all of it collapses to a still picture under "reduce motion"):
/// the blurred avatar backdrop drifts slower than the page and swells when
/// the list is pulled past the top; the avatar settles into a dial-like level
/// ring whose arc sweeps to the real progress; each card below settles in as
/// it scrolls into view and only then plays its own moment (the points bar
/// fills, the counter tallies, the flame lights, the level-path rail draws
/// down).
/// See widgets/level_hero_effects.dart for the shared pieces.
class LevelDetailScreen extends StatefulWidget {
  final ProfileYearStats stats;
  final WrappedStat? wrapped;
  final ProfileLevel? initial;
  const LevelDetailScreen({super.key, required this.stats, this.wrapped, this.initial});

  @override
  State<LevelDetailScreen> createState() => _LevelDetailScreenState();
}

class _LevelDetailScreenState extends State<LevelDetailScreen> {
  late Future<ProfileLevel> _future;

  // The list's scroll offset — negative while it is pulled past the top. Feeds
  // the backdrop's parallax / swell. A ValueNotifier rather than setState so a
  // scroll frame redraws only the backdrop, not this whole page.
  final ValueNotifier<double> _scrollY = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _future = widget.initial != null ? Future.value(widget.initial) : _load();
  }

  @override
  void dispose() {
    _scrollY.dispose();
    super.dispose();
  }

  Future<ProfileLevel> _load() => context.read<AppState>().profile.level();

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    final user = context.watch<AppState>().currentUser;

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: Stack(
        children: [
          // A soft, blurred blow-up of the person's own avatar (with a little
          // dust drifting through it) instead of flat background. It moves
          // at under half the page's speed as the list scrolls and swells
          // when the list is pulled past the top; fades back into
          // SeenlyPalette.background so everything below is untouched.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _scrollY,
              child: RepaintBoundary(
                child: SizedBox(
                  height: _kBackdropHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AvatarBackdrop(
                        avatarUrl: user?.avatarUrl,
                        avatarPreset: user?.avatarPreset,
                        height: _kBackdropHeight,
                      ),
                      DriftingMotes(seed: 'level-detail', color: SeenlyPalette.accent),
                    ],
                  ),
                ),
              ),
              builder: (context, y, child) {
                final pull = y < 0 ? -y : 0.0;
                final scale = 1.0 + (pull / 900).clamp(0.0, 0.25);
                final drift = y > 0 ? -y * 0.42 : 0.0;
                final fade = y > 0 ? (1 - y / 420).clamp(0.0, 1.0) : 1.0;
                return Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(0, drift),
                    child: Transform.scale(scale: scale, alignment: Alignment.topCenter, child: child),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 20, 4),
                  child: Entrance(
                    duration: const Duration(milliseconds: 420),
                    riseBy: 8,
                    child: Row(
                      children: [
                        PressScale(
                          onTap: () => Navigator.of(context).pop(),
                          scaleTo: 0.88,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: ClayBoxDecoration(
                                color: SeenlyPalette.paper.withOpacity(0.88),
                                shape: BoxShape.circle,
                                boxShadow: SeenlyPalette.softShadow,
                              ),
                              child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('your profile'.tr, style: SeenlyText.screenTitle),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<ProfileLevel>(
                    future: _future,
                    builder: (context, snapshot) {
                      final String stateKey;
                      final Widget body;
                      if (!snapshot.hasData && !snapshot.hasError) {
                        stateKey = 'loading';
                        body = const Center(child: ThemedLoadingIndicator());
                      } else if (snapshot.hasError) {
                        stateKey = 'error';
                        body = RefreshIndicator(
                          onRefresh: _refresh,
                          color: SeenlyPalette.accent,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 60),
                            children: [
                              Text("couldn't load your level".tr,
                                  textAlign: TextAlign.center,
                                  style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted)),
                            ],
                          ),
                        );
                      } else {
                        stateKey = 'content';
                        body = _buildContent(context, snapshot.data!, theme);
                      }
                      // Loading → content (or error) cross-fades instead of cutting.
                      return SoftSwap(
                        expand: true,
                        alignment: Alignment.topCenter,
                        rise: 0.015,
                        duration: const Duration(milliseconds: 280),
                        child: KeyedSubtree(key: ValueKey<String>(stateKey), child: body),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ProfileLevel level, LogTheme theme) {
    final best = widget.wrapped?.longestStreak;
    final streakHeadline = LogThemeCopy.streakHeadline(theme, widget.stats.streakDays);
    final streakSubline = (best != null && best > 0) ? LogThemeCopy.streakBest(theme, best) : null;

    // Same capped cascade as Profile's own sections: only what is visible on
    // first paint needs to stagger; anything further down is revealed by
    // scrolling to it, on its own.
    var slot = 0;
    Duration nextDelay() {
      final d = Duration(milliseconds: math.min(slot, 3) * 70);
      slot++;
      return d;
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: SeenlyPalette.accent,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
            final y = n.metrics.pixels;
            if (_scrollY.value != y) _scrollY.value = y;
          }
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
          children: [
            _ProfileIdentitySection(level: level),
            const SizedBox(height: 26),
            ScrollReveal(
              delay: nextDelay(),
              child: _LevelCard(level: level, theme: theme),
            ),
            const SizedBox(height: 14),
            ScrollReveal(
              delay: nextDelay(),
              child: _StreakCard(
                headline: streakHeadline,
                subline: streakSubline,
                active: widget.stats.streakDays > 0,
              ),
            ),
            const SizedBox(height: 32),
            ScrollReveal(child: _BreakdownSection(level: level, theme: theme)),
            const SizedBox(height: 32),
            _LevelPathSection(level: level),
            const SizedBox(height: 24),
            ScrollReveal(child: _XpNote(theme: theme)),
          ],
        ),
      ),
    );
  }
}

/// A soft, oversized, blurred blow-up of the user's own avatar (photo or
/// preset), used as a backdrop so the wide-open space above the nickname
/// isn't just flat background. Fades into [SeenlyPalette.background] toward
/// the bottom so it reads as an accent, not a poster. With no picture at all
/// it is a soft plum glow rather than nothing. A new picture cross-fades in.
class _AvatarBackdrop extends StatefulWidget {
  final String? avatarUrl;
  final String? avatarPreset;
  final double height;

  const _AvatarBackdrop({required this.avatarUrl, required this.avatarPreset, required this.height});

  @override
  State<_AvatarBackdrop> createState() => _AvatarBackdropState();
}

class _AvatarBackdropState extends State<_AvatarBackdrop> {
  // Resolved once per url — building a fresh Future in build() made the image
  // blink back to "loading" on every rebuild of the page.
  Future<String>? _resolved;
  String? _resolvedFor;

  Future<String>? _urlFuture() {
    final url = widget.avatarUrl;
    if (url == null || url.isEmpty) return null;
    if (_resolved == null || _resolvedFor != url) {
      _resolvedFor = url;
      _resolved = url.startsWith('http')
          ? Future<String>.value(url)
          : context.read<AppState>().client.resolveBaseUrl().then((base) => '$base$url');
    }
    return _resolved;
  }

  @override
  Widget build(BuildContext context) {
    Widget? image;
    final future = _urlFuture();
    if (future != null) {
      image = FutureBuilder<String>(
        future: future,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return Image.network(
            snap.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        },
      );
    } else if (widget.avatarPreset != null) {
      final preset = kAvatarPresets.where((p) => p.id == widget.avatarPreset).toList();
      if (preset.isNotEmpty) {
        image = Image.asset(preset.first.assetPath, fit: BoxFit.cover);
      }
    }

    final identity = '${widget.avatarUrl ?? ''}|${widget.avatarPreset ?? ''}';
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 520),
        child: KeyedSubtree(
          key: ValueKey<String>(identity),
          child: image == null ? _glow() : _photo(image),
        ),
      ),
    );
  }

  Widget _glow() {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.25),
            radius: 0.8,
            colors: [
              SeenlyPalette.accent.withOpacity(0.20),
              SeenlyPalette.accent.withOpacity(0.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photo(Widget image) {
    return ClipRect(
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Scaled up just enough that the soft edges never peek in from
            // the sides. Only a light softening blur — the point is for
            // this to read as the actual avatar photo sitting behind the
            // profile, not a heavily blurred, unrecognizable smear.
            Transform.scale(
              scale: 1.1,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8, tileMode: TileMode.decal),
                child: image,
              ),
            ),
            // Mutes the colors so the photo stays a soft accent rather than
            // a dark, saturated slab — text sitting anywhere near it (name,
            // status) needs to stay legible even before the gradient below
            // has fully dissolved it away.
            Container(color: SeenlyPalette.background.withOpacity(0.55)),
            // Stays visible behind the avatar itself, then dissolves
            // gradually over a wide band that finishes right as the nickname
            // starts — so the fade is long and soft rather than a hard
            // cropped edge, and the name/status below always land on solid
            // background.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, SeenlyPalette.background],
                  stops: const [0.4, 0.78],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Identity — the avatar in its level ring, nickname, status. Every one of the
// three is editable right where it sits: tap the avatar for a quick picker
// sheet (bundled presets or an uploaded photo), tap the name or status to turn
// it into a text field in place. No separate edit screen — same fields,
// same endpoints (ProfileService.updateMe / uploadAvatar) EditProfileScreen
// already used, just reached without leaving this page.
// ---------------------------------------------------------------------------

class _ProfileIdentitySection extends StatefulWidget {
  final ProfileLevel level;
  const _ProfileIdentitySection({required this.level});

  @override
  State<_ProfileIdentitySection> createState() => _ProfileIdentitySectionState();
}

class _ProfileIdentitySectionState extends State<_ProfileIdentitySection> {
  bool _uploadingAvatar = false;

  bool _editingName = false;
  late final TextEditingController _nameController;
  final FocusNode _nameFocus = FocusNode();

  bool _editingStatus = false;
  late final TextEditingController _statusController;
  final FocusNode _statusFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    _nameController = TextEditingController(text: user?.nameForDisplay ?? '');
    _statusController = TextEditingController(text: user?.statusText ?? '');
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _editingName) _saveName();
    });
    _statusFocus.addListener(() {
      if (!_statusFocus.hasFocus && _editingStatus) _saveStatus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    _nameFocus.dispose();
    _statusFocus.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    if (!mounted) return;
    setState(() => _editingName = false);
    final app = context.read<AppState>();
    final text = _nameController.text.trim();
    if (text == (app.currentUser?.nameForDisplay ?? '')) return;
    try {
      await app.profile.updateMe(displayName: text);
      await app.refreshCurrentUser();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't save name".tr)));
    }
  }

  Future<void> _saveStatus([String? overrideText]) async {
    if (!mounted) return;
    final text = (overrideText ?? _statusController.text).trim();
    setState(() {
      _editingStatus = false;
      _statusController.text = text;
    });
    final app = context.read<AppState>();
    if (text == (app.currentUser?.statusText ?? '')) return;
    try {
      await app.profile.updateMe(statusText: text);
      await app.refreshCurrentUser();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't save status".tr)));
    }
  }

  Future<void> _pickAvatarPreset(String presetId) async {
    setState(() => _uploadingAvatar = true);
    final app = context.read<AppState>();
    try {
      await app.profile.updateMe(avatarPreset: presetId);
      await app.refreshCurrentUser();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't save avatar".tr)));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _pickAvatarPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploadingAvatar = true);
    final app = context.read<AppState>();
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.path.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      await app.profile.uploadAvatar(bytes, filename: picked.name, contentType: contentType);
      await app.refreshCurrentUser();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("${"couldn't upload photo".tr}: $e")));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  // Same soft, blurred-backdrop centered card language as the rest of the
  // app's popups (see HowItWorksSheet) — was a bottom sheet before, which
  // stood out as the one popup on this screen that didn't match.
  void _openAvatarSheet() {
    final app = context.read<AppState>();
    showGeneralDialog(
      context: context,
      barrierLabel: 'change avatar',
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, __) {
        return _AvatarSheet(
          currentAvatarUrl: app.currentUser?.avatarUrl,
          currentAvatarPreset: app.currentUser?.avatarPreset,
          onPickPreset: _pickAvatarPreset,
          onUploadPhoto: _pickAvatarPhoto,
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _editGlyph() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.9),
        shape: BoxShape.circle,
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Icon(Icons.edit_outlined, size: 12, color: SeenlyPalette.inkFaint),
    );
  }

  Widget _nameView(String name) {
    if (_editingName) {
      return SizedBox(
        key: const ValueKey('name-edit'),
        width: 240,
        child: TextField(
          controller: _nameController,
          focusNode: _nameFocus,
          autofocus: true,
          maxLength: 40,
          textAlign: TextAlign.center,
          style: SeenlyText.serif(size: 20, weight: FontWeight.w600),
          decoration: const InputDecoration(counterText: '', isDense: true, border: UnderlineInputBorder()),
          onSubmitted: (_) => _saveName(),
        ),
      );
    }
    return PressScale(
      key: const ValueKey('name-view'),
      onTap: () => setState(() => _editingName = true),
      scaleTo: 0.97,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              name,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.serif(size: 20, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          _editGlyph(),
        ],
      ),
    );
  }

  Widget _statusView(String? status) {
    if (_editingStatus) {
      return Column(
        key: const ValueKey('status-edit'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < kStatusPresets.length; i++)
                Entrance(
                  delay: Duration(milliseconds: 40 * i),
                  duration: const Duration(milliseconds: 360),
                  riseBy: 8,
                  child: _StatusChip(label: kStatusPresets[i], onTap: () => _saveStatus(kStatusPresets[i])),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _statusController,
              focusNode: _statusFocus,
              autofocus: true,
              maxLength: 120,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'your own status'.tr,
                border: const UnderlineInputBorder(),
              ),
              onSubmitted: (_) => _saveStatus(),
            ),
          ),
        ],
      );
    }
    final String? shown = (status != null && status.isNotEmpty) ? status : null;
    return PressScale(
      key: const ValueKey('status-view'),
      onTap: () => setState(() => _editingStatus = true),
      scaleTo: 0.97,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: SeenlyPalette.paper.withOpacity(0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SeenlyPalette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('“', style: SeenlyText.serif(size: 18, color: SeenlyPalette.accent.withOpacity(0.55))),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  shown ?? 'add a status'.tr,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.mono(
                    size: 12,
                    color: shown != null ? SeenlyPalette.inkMuted : SeenlyPalette.inkFaint,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text('”', style: SeenlyText.serif(size: 18, color: SeenlyPalette.accent.withOpacity(0.55))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.currentUser;
    final letter = (user?.username.isNotEmpty ?? false) ? user!.username.substring(0, 1).toLowerCase() : '?';

    if (!_editingName) _nameController.text = user?.nameForDisplay ?? '';
    if (!_editingStatus) _statusController.text = user?.statusText ?? '';

    final sinceText = user?.createdAt == null
        ? null
        // Was a plain string with escaped `\$` in it, so the month/year
        // never actually interpolated — it just printed the template
        // literally. Built from real interpolation now, with the month name
        // picked from whichever array matches the current interface
        // language (the Russian one needs the genitive "since ___" form,
        // not a word-for-word swap).
        : 'on tanè since '.tr +
            (LocaleService.appIsRussian
                ? _kMonthNamesRuGenitive[user!.createdAt!.month]
                : _kMonthNames[user!.createdAt!.month]) +
            ' ${user.createdAt!.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        LevelRingAvatar(
          level: widget.level.level,
          progress: widget.level.progress,
          avatarSize: _kAvatarSize,
          busy: _uploadingAvatar,
          onAvatarTap: _openAvatarSheet,
          avatar: UserAvatar(
            key: ValueKey('${user?.avatarUrl ?? ''}|${user?.avatarPreset ?? ''}'),
            avatarUrl: user?.avatarUrl,
            avatarPreset: user?.avatarPreset,
            fallbackLetter: letter,
            size: _kAvatarSize,
          ),
        ),
        const SizedBox(height: 12),
        Entrance(
          delay: const Duration(milliseconds: 420),
          duration: const Duration(milliseconds: 520),
          riseBy: 12,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                SoftSwap(
                  alignment: Alignment.center,
                  child: _nameView(user?.nameForDisplay ?? ''),
                ),
                const SizedBox(height: 10),
                SoftSwap(
                  alignment: Alignment.center,
                  child: _statusView(user?.statusText),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Seenly's social graph is mutual-only (an accepted FriendRequest
        // row *is* the friendship — see backend/app/routers/friends.py).
        // There's no directional follow/follower concept in the data
        // model, so this only ever shows the one number that's real.
        Entrance(
          delay: const Duration(milliseconds: 520),
          duration: const Duration(milliseconds: 520),
          riseBy: 10,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const _RealFriendsChip(),
              if (sinceText != null)
                _MetaChip(
                  icon: Icons.local_florist_outlined,
                  child: Text(sinceText, style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.94,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SeenlyPalette.border),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Text(label, style: SeenlyText.mono(size: 12, color: SeenlyPalette.ink)),
      ),
    );
  }
}

/// A small paper pill with an icon — the identity block's quiet facts
/// (friends, member since).
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final Widget child;
  const _MetaChip({required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: SeenlyPalette.accent),
          const SizedBox(width: 7),
          child,
        ],
      ),
    );
  }
}

// Small self-contained fetch (independent of the rest of this screen's
// FutureBuilder, same reasoning as profile_screen.dart's own friends
// block) so a slow friends fetch never holds up the level/points content
// below it, and vice versa. The chip holds its place while loading (fully
// transparent) and fades in once the number is known, so nothing shifts.
class _RealFriendsChip extends StatefulWidget {
  const _RealFriendsChip();

  @override
  State<_RealFriendsChip> createState() => _RealFriendsChipState();
}

class _RealFriendsChipState extends State<_RealFriendsChip> {
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppState>().friends.list();
      if (mounted) setState(() => _count = data.friends.length);
    } catch (_) {
      // Leave it blank rather than show a stale/fake number if the fetch fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count ?? 0;
    return AnimatedOpacity(
      opacity: _count == null ? 0 : 1,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
      child: _MetaChip(
        icon: Icons.people_outline,
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$count',
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.ink, weight: FontWeight.w700),
              ),
              TextSpan(
                text: ' ${nOnly('nFriends', count)}',
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "change avatar" popup — centered card over a blurred backdrop,
/// tap outside to dismiss. Matches HowItWorksSheet's card language rather
/// than a bottom sheet, so every popup reachable from this screen reads
/// the same way. The presets settle in one after another; the current one
/// wears a glowing accent ring and a check.
class _AvatarSheet extends StatelessWidget {
  final String? currentAvatarUrl;
  final String? currentAvatarPreset;
  final ValueChanged<String> onPickPreset;
  final VoidCallback onUploadPhoto;

  const _AvatarSheet({
    required this.currentAvatarUrl,
    required this.currentAvatarPreset,
    required this.onPickPreset,
    required this.onUploadPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final accent = SeenlyPalette.accent;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(color: SeenlyPalette.ink.withOpacity(0.28)),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: GestureDetector(
                onTap: () {}, // swallow — a tap on the card itself shouldn't dismiss it
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(color: SeenlyPalette.ink.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('change avatar'.tr, style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
                          ),
                          PressScale(
                            onTap: () => Navigator.of(context).pop(),
                            scaleTo: 0.86,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                              child: Icon(Icons.close, size: 14, color: SeenlyPalette.inkMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Entrance(
                        duration: const Duration(milliseconds: 380),
                        riseBy: 8,
                        child: PressScale(
                          onTap: () {
                            Navigator.of(context).pop();
                            onUploadPhoto();
                          },
                          scaleTo: 0.97,
                          child: DashedBox(
                            radius: 16,
                            color: accent.withOpacity(0.5),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.photo_camera_outlined, size: 17, color: accent),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'upload your own photo'.tr,
                                      style: SeenlyText.mono(size: 12, color: accent, weight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('or pick a ready-made avatar'.tr,
                          style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          for (var i = 0; i < kAvatarPresets.length; i++)
                            Entrance(
                              delay: Duration(milliseconds: 80 + 45 * i),
                              duration: const Duration(milliseconds: 420),
                              riseBy: 10,
                              child: _PresetTile(
                                preset: kAvatarPresets[i],
                                selected: currentAvatarUrl == null && currentAvatarPreset == kAvatarPresets[i].id,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  onPickPreset(kAvatarPresets[i].id);
                                },
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
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final AvatarPresetOption preset;
  final bool selected;
  final VoidCallback onTap;
  const _PresetTile({required this.preset, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = SeenlyPalette.accent;
    return PressScale(
      onTap: onTap,
      scaleTo: 0.92,
      haptics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? accent : SeenlyPalette.border,
                width: selected ? 2.2 : 1.2,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: accent.withOpacity(0.28), blurRadius: 12, offset: const Offset(0, 4))]
                  : const [],
            ),
            child: ClipOval(
              child: Image.asset(preset.assetPath, width: 60, height: 60, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: AnimatedScale(
              scale: selected ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: SeenlyPalette.paper, width: 2),
                ),
                child: Icon(Icons.check, size: 11, color: SeenlyPalette.accentOnAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------

BoxDecoration _cardDecoration({double radius = 22}) => ClayBoxDecoration(
      color: SeenlyPalette.paper,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: SeenlyPalette.border.withOpacity(0.6)),
      boxShadow: SeenlyPalette.softShadow,
    );

/// Where the person is on the level: the themed headline, the total points
/// tallying up on the right, and the glowing bar between this level's badge
/// and the next one's.
class _LevelCard extends StatelessWidget {
  final ProfileLevel level;
  final LogTheme theme;
  const _LevelCard({required this.level, required this.theme});

  @override
  Widget build(BuildContext context) {
    final accent = SeenlyPalette.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  LogThemeCopy.levelHeadline(theme, level.level),
                  style: SeenlyText.serif(size: 15, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 14),
              RevealProgress(
                duration: const Duration(milliseconds: 1300),
                builder: (context, t) => Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _groupThousands((level.points * t).round()),
                      style: SeenlyText.serif(size: 22, weight: FontWeight.w700, color: accent),
                    ),
                    Text('points'.tr, style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _LevelDisc(number: level.level, filled: true),
              const SizedBox(width: 8),
              Expanded(child: PointsProgressBar(value: level.progress, delay: const Duration(milliseconds: 150))),
              const SizedBox(width: 8),
              _LevelDisc(number: level.level + 1, filled: false),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${level.pointsIntoLevel} / ${level.pointsForNextLevel} ${'to level'.tr} ${level.level + 1}',
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The little numbered disc at either end of the points bar — this level filled,
/// the next one an outline.
class _LevelDisc extends StatelessWidget {
  final int number;
  final bool filled;
  const _LevelDisc({required this.number, required this.filled});

  @override
  Widget build(BuildContext context) {
    final accent = SeenlyPalette.accent;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? accent : SeenlyPalette.paper,
        border: Border.all(color: filled ? accent : accent.withOpacity(0.45), width: 1.4),
        boxShadow: filled
            ? [BoxShadow(color: accent.withOpacity(0.28), blurRadius: 8, offset: const Offset(0, 3))]
            : const [],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Text(
            '$number',
            style: SeenlyText.serif(
              size: 13,
              weight: FontWeight.w700,
              color: filled ? SeenlyPalette.accentOnAccent : accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// The streak, dressed as a card: a flame that lights when the card arrives
/// (a bounce, a small wobble, one ring of warmth spreading out). Goes dim and
/// still when there is no streak, rather than pretending there is one.
class _StreakCard extends StatelessWidget {
  final String headline;
  final String? subline;
  final bool active;
  const _StreakCard({required this.headline, required this.subline, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDecoration(radius: 20),
      child: Row(
        children: [
          RevealProgress(
            duration: const Duration(milliseconds: 1100),
            curve: Curves.linear,
            builder: (context, t) => _Flame(t: t, active: active),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: SeenlyText.serif(size: 14, weight: FontWeight.w600)),
                if (subline != null) ...[
                  const SizedBox(height: 3),
                  Text(subline!, style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Flame extends StatelessWidget {
  final double t; // 0..1
  final bool active;
  const _Flame({required this.t, required this.active});

  @override
  Widget build(BuildContext context) {
    final accent = SeenlyPalette.accent;
    final color = active ? accent : SeenlyPalette.inkFaint;
    final pop = const Interval(0.0, 0.55, curve: Curves.easeOutBack).transform(t);
    final settle = const Interval(0.0, 1.0, curve: Curves.easeOut).transform(t);
    final wobble = math.sin(t * math.pi * 3) * 0.11 * (1 - settle);
    final ring = active ? const Interval(0.3, 1.0, curve: Curves.easeOut).transform(t) : 0.0;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Grows outward past the flame's own box (negative insets, so the
          // Stack's tight size doesn't squash it).
          if (active && ring > 0 && ring < 1)
            Positioned(
              left: -13 * ring,
              top: -13 * ring,
              right: -13 * ring,
              bottom: -13 * ring,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withOpacity(0.38 * (1 - ring)), width: 2),
                ),
              ),
            ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(active ? 0.12 : 0.10),
            ),
          ),
          Transform.rotate(
            angle: wobble,
            child: Transform.scale(
              scale: 0.4 + 0.6 * pop,
              alignment: Alignment.bottomCenter,
              child: Icon(Icons.local_fire_department_rounded, size: 26, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// A section title with a short accent rule that draws itself in underneath.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SeenlyText.sectionTitle),
        const SizedBox(height: 6),
        RevealProgress(
          duration: const Duration(milliseconds: 700),
          delay: const Duration(milliseconds: 120),
          builder: (context, t) => Container(
            width: 28 * t,
            height: 3,
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Activity breakdown — one card of rows; each row's bar fills to that
// source's share of everything the breakdown lists, one row after
// the next, when the card scrolls into view.
// ---------------------------------------------------------------------------

class _BreakdownData {
  final IconData icon;
  final String label;
  final int count;
  // Word after the count under the label — "logged" for the diary-derived
  // rows, something else where that would read wrong (a challenge is
  // "collected", a card is "shared").
  final String? countLabel;
  const _BreakdownData({
    required this.icon,
    required this.label,
    required this.count,
    this.countLabel,
  });
}

class _BreakdownSection extends StatelessWidget {
  final ProfileLevel level;
  final LogTheme theme;
  const _BreakdownSection({required this.level, required this.theme});

  @override
  Widget build(BuildContext context) {
    final rows = <_BreakdownData>[
      _BreakdownData(
        icon: Icons.local_movies_outlined,
        label: LogThemeCopy.levelBreakdownLabel(theme, 'watched'),
        count: level.watchedCount,
      ),
      _BreakdownData(
        icon: Icons.edit_note,
        label: LogThemeCopy.levelBreakdownLabel(theme, 'reviews'),
        count: level.reviewsCount,
      ),
      _BreakdownData(
        icon: Icons.replay,
        label: LogThemeCopy.levelBreakdownLabel(theme, 'rewatches'),
        count: level.rewatchCount,
      ),
      _BreakdownData(
        icon: Icons.explore_outlined,
        label: LogThemeCopy.levelBreakdownLabel(theme, 'genres'),
        count: level.genresCount,
      ),
      _BreakdownData(
        icon: Icons.local_fire_department_outlined,
        label: LogThemeCopy.levelBreakdownLabel(theme, 'streak'),
        count: level.longestStreakEver,
      ),
      _BreakdownData(
        icon: Icons.people_outline,
        label: 'evenings watched together'.tr,
        count: level.watchedTogetherCount,
      ),
      _BreakdownData(
        icon: Icons.emoji_events_outlined,
        label: 'challenges collected'.tr,
        count: level.challengesClaimed,
        countLabel: 'collected'.tr,
      ),
      _BreakdownData(
        icon: Icons.ios_share,
        label: 'cards shared'.tr,
        count: level.cardSharesCount,
        countLabel: 'shared'.tr,
      ),
    ];
    final total = rows.fold<int>(0, (sum, r) => sum + r.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'your activity'.tr),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: _cardDecoration(),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                _BreakdownRow(
                  data: rows[i],
                  share: total > 0 ? rows[i].count / total : 0.0,
                  index: i,
                  isLast: i == rows.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'for exactly how your points add up, see your sincerity history'.tr,
          style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint),
        ),
      ],
    );
  }
}

/// One line of the activity breakdown: icon, themed label, the raw count
/// and its share of this account's overall activity (a thin bar), e.g.
/// "42 evenings logged · 30%". No point figure here on purpose — see
/// this section's own footer note; the per-item ledger lives on the
/// Sincerity screen, not a second formula here that could drift from it.
class _BreakdownRow extends StatelessWidget {
  final _BreakdownData data;
  final double share; // 0..1 of the breakdown's total
  final int index;
  final bool isLast;
  const _BreakdownRow({required this.data, required this.share, required this.index, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final accent = SeenlyPalette.accent;
    final pct = (share * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: SeenlyPalette.border, width: 1)),
      ),
      child: RevealProgress(
        delay: Duration(milliseconds: 90 * index),
        duration: const Duration(milliseconds: 1100),
        builder: (context, t) => Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withOpacity(0.10)),
                  child: Icon(data.icon, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.label, style: SeenlyText.serif(size: 13.5)),
                      const SizedBox(height: 1),
                      Text(
                        '${data.count} ${data.countLabel ?? 'logged'.tr} · $pct%',
                        style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(color: SeenlyPalette.border.withOpacity(0.7)),
                      FractionallySizedBox(
                        widthFactor: (share * t).clamp(0.0, 1.0).toDouble(),
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [accent.withOpacity(0.6), accent]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Level path — where the same points curve the ring/progress bar above
// already uses (see ProfileLevel.progress / backend/app/sincerity.py::
// compute_level, base 8 points + 3 more per level) turns into a short,
// honest look at what's just ahead: how many more points each nearby
// level takes, and — for every fifth level, the milestones — a bigger card with
// the badge that level actually unlocks (see achievementIcon's 'level'
// case and backend's _LEVEL_MILESTONES, which is what the badges screen
// shows once that level is actually reached).
//
// Drawn as a rail: the line down the left is lit up to the current level and
// dashed beyond it, and draws itself downward as each row scrolls into view.
// ---------------------------------------------------------------------------

// Mirrors backend/app/sincerity.py::LEVEL_BASE_POINTS (8) and
// LEVEL_STEP_POINTS (3) — see that module's docstring for why the
// old, much larger XP curve (base 100, +40/level) was pulled down to
// this scale as part of merging XP into sincerity points.
int _levelPathPointsStep(int level) => 8 + 3 * (level - 1);

int _levelPathCumulativePoints(int level) {
  var total = 0;
  for (var k = 1; k < level; k++) {
    total += _levelPathPointsStep(k);
  }
  return total;
}

const double _kRailWidth = 30;
const double _kRowGap = 10;

class _LevelPathSection extends StatelessWidget {
  final ProfileLevel level;
  const _LevelPathSection({required this.level});

  @override
  Widget build(BuildContext context) {
    final cur = level.level;
    final nextMilestone = ((cur ~/ 5) + 1) * 5;
    final start = math.max(1, cur - 1);
    // Runs all the way through level 30 — the same cap the level
    // badges stop at (see _LEVEL_MILESTONES in
    // backend/app/routers/profile.py) — rather than trimming to a
    // short window around the current level, so every upcoming badge
    // milestone is visible in one scroll. Past level 30 (no badge left
    // to earn), falls back to just a short peek ahead of the next
    // milestone, same as before.
    final end = cur < 30 ? 30 : nextMilestone + 5;

    final rows = <Widget>[];
    for (var n = start; n <= end; n++) {
      rows.add(
        _PathRow(
          levelNumber: n,
          cumulativePoints: _levelPathCumulativePoints(n),
          remainingPoints: _levelPathCumulativePoints(n) - level.points,
          isCurrent: n == cur,
          isPast: n < cur,
          isMilestone: n % 5 == 0,
          isFirst: n == start,
          isLast: n == end,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScrollReveal(
          child: _SectionHeader(
            title: 'level path'.tr,
            subtitle: 'a peek at what\'s just ahead'.tr,
          ),
        ),
        const SizedBox(height: 16),
        ...rows,
      ],
    );
  }
}

class _PathRow extends StatelessWidget {
  final int levelNumber;
  final int cumulativePoints;
  final int remainingPoints;
  final bool isCurrent;
  final bool isPast;
  final bool isMilestone;
  final bool isFirst;
  final bool isLast;
  const _PathRow({
    required this.levelNumber,
    required this.cumulativePoints,
    required this.remainingPoints,
    required this.isCurrent,
    required this.isPast,
    required this.isMilestone,
    required this.isFirst,
    required this.isLast,
  });

  bool get _reached => isCurrent || isPast;

  @override
  Widget build(BuildContext context) {
    final gap = isLast ? 0.0 : _kRowGap;
    return ScrollReveal(
      duration: const Duration(milliseconds: 520),
      riseBy: 12,
      child: RevealProgress(
        duration: const Duration(milliseconds: 800),
        curve: Curves.linear,
        builder: (context, t) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _kRailWidth,
              child: CustomPaint(
                painter: _RailPainter(
                  t: t,
                  above: !isFirst,
                  below: !isLast,
                  litAbove: _reached,
                  litBelow: isPast,
                  gap: gap,
                  nodeR: isMilestone ? 9 : (isCurrent ? 13 : 11),
                  lit: SeenlyPalette.accent,
                  dim: SeenlyPalette.dashedBorder,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: gap,
              width: _kRailWidth,
              child: Center(child: _node(t)),
            ),
            Padding(
              padding: EdgeInsets.only(left: _kRailWidth + 10, bottom: gap),
              child: isMilestone ? _milestoneCard(t) : _plainCard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _node(double t) {
    final accent = SeenlyPalette.accent;
    final pop = const Interval(0.35, 0.75, curve: Curves.easeOutBack).transform(t);
    final fade = const Interval(0.35, 0.6).transform(t);

    Widget core;
    if (isMilestone) {
      core = Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _reached ? accent : SeenlyPalette.paper,
          border: Border.all(color: _reached ? accent : SeenlyPalette.dashedBorder, width: 1.4),
        ),
        child: Icon(
          Icons.star_rounded,
          size: 11,
          color: _reached ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkFaint,
        ),
      );
    } else if (isCurrent) {
      final ripple = const Interval(0.55, 1.0, curve: Curves.easeOut).transform(t);
      core = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (ripple > 0 && ripple < 1)
            Positioned(
              left: -10 * ripple,
              top: -10 * ripple,
              right: -10 * ripple,
              bottom: -10 * ripple,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withOpacity(0.45 * (1 - ripple)), width: 2),
                ),
              ),
            ),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
              boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            alignment: Alignment.center,
            child: Text(
              '$levelNumber',
              style: SeenlyText.mono(size: 12, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent),
            ),
          ),
        ],
      );
    } else if (isPast) {
      core = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
        child: Icon(Icons.check, size: 12, color: SeenlyPalette.accentOnAccent),
      );
    } else {
      core = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SeenlyPalette.paper,
          border: Border.all(color: SeenlyPalette.dashedBorder, width: 1.2),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$levelNumber',
            style: SeenlyText.mono(size: 12, weight: FontWeight.w700, color: SeenlyPalette.inkFaint),
          ),
        ),
      );
    }
    return Opacity(opacity: fade, child: Transform.scale(scale: pop, child: core));
  }

  /// One ordinary level in the path — a small pill, no artwork. The current
  /// one gets an accent outline; everything behind is quieter, everything
  /// ahead shows just its number and the real points still needed to get there.
  Widget _plainCard() {
    final done = isPast || remainingPoints <= 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: ClayBoxDecoration(
        color: isCurrent
            ? SeenlyPalette.accent.withOpacity(0.08)
            : (isPast ? SeenlyPalette.paper.withOpacity(0.6) : SeenlyPalette.paper),
        borderRadius: BorderRadius.circular(14),
        border: isCurrent ? Border.all(color: SeenlyPalette.accent, width: 1.2) : null,
        boxShadow: (isCurrent || isPast) ? null : SeenlyPalette.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${'level'.tr} $levelNumber',
              style: SeenlyText.serif(size: 13.5, weight: isCurrent ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
          Text(
            done ? 'reached'.tr : _pointsToGo(remainingPoints),
            style: SeenlyText.mono(size: 12, color: isCurrent ? SeenlyPalette.accent : SeenlyPalette.inkFaint),
          ),
        ],
      ),
    );
  }

  /// A milestone level (every 5th) — bigger, with the badge that level
  /// unlocks (see achievementIcon's 'level' case, shared with the badges
  /// screen so the two never draw a different icon for the same level).
  /// The medallion settles in with a gentle overshoot as the row arrives.
  Widget _milestoneCard(double t) {
    final accent = SeenlyPalette.accent;
    final done = isPast || remainingPoints <= 0;
    final subtitle = _reached ? 'badge unlocked'.tr : 'unlocks a badge'.tr;
    final medallionScale = 0.78 + 0.22 * const Interval(0.3, 0.9, curve: Curves.easeOutBack).transform(t);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ClayBoxDecoration(
        gradient: _reached
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent.withOpacity(isCurrent ? 0.16 : 0.10), SeenlyPalette.paper],
              )
            : null,
        color: _reached ? null : SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent ? accent : SeenlyPalette.border,
          width: isCurrent ? 1.4 : 1,
        ),
        boxShadow: [
          if (isCurrent) BoxShadow(color: accent.withOpacity(0.20), blurRadius: 18, offset: const Offset(0, 6)),
          ...SeenlyPalette.softShadow,
        ],
      ),
      child: Row(
        children: [
          Transform.scale(
            scale: medallionScale,
            child: RoundBadgeMedallion(
              iconKey: 'level',
              title: '${'level'.tr} $levelNumber',
              rarity: levelBadgeRarityKey(levelNumber),
              unlocked: _reached,
              diameter: 46,
              showLabel: false,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${'level'.tr} $levelNumber', style: SeenlyText.serif(size: 16.5, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
                const SizedBox(height: 6),
                Text(
                  done ? _reachedAt(cumulativePoints) : _pointsToGo(remainingPoints),
                  style: SeenlyText.mono(size: 12, color: accent, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The rail's line segments (the nodes are widgets, see _PathRow._node): lit
/// and solid where the levels are reached, dashed where they aren't. The
/// segment above the node draws down first, the one below follows.
class _RailPainter extends CustomPainter {
  final double t; // 0..1 draw-in
  final bool above;
  final bool below;
  final bool litAbove;
  final bool litBelow;
  final double gap; // empty space under the card that the rail still crosses
  final double nodeR;
  final Color lit;
  final Color dim;

  const _RailPainter({
    required this.t,
    required this.above,
    required this.below,
    required this.litAbove,
    required this.litBelow,
    required this.gap,
    required this.nodeR,
    required this.lit,
    required this.dim,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final nodeY = (size.height - gap) / 2;
    final topEnd = nodeY - nodeR - 3;
    final bottomStart = nodeY + nodeR + 3;
    final aT = const Interval(0.0, 0.45, curve: Curves.easeOut).transform(t);
    final bT = const Interval(0.5, 1.0, curve: Curves.easeOut).transform(t);
    if (above && topEnd > 0) _segment(canvas, x, 0, topEnd, litAbove, aT);
    if (below && size.height > bottomStart) _segment(canvas, x, bottomStart, size.height, litBelow, bT);
  }

  void _segment(Canvas canvas, double x, double y0, double y1, bool isLit, double f) {
    if (f <= 0) return;
    if (isLit) {
      final p = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.6
        ..color = lit.withOpacity(0.9);
      canvas.drawLine(Offset(x, y0), Offset(x, y0 + (y1 - y0) * f), p);
      return;
    }
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8
      ..color = dim.withOpacity(f);
    for (var y = y0; y < y1; y += 7) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3.5, y1)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.t != t ||
      old.above != above ||
      old.below != below ||
      old.litAbove != litAbove ||
      old.litBelow != litBelow ||
      old.gap != gap ||
      old.nodeR != nodeR ||
      old.lit != lit ||
      old.dim != dim;
}

/// The honesty note at the foot of the page, with a heart that keeps a
/// quiet resting beat.
class _XpNote extends StatelessWidget {
  final LogTheme theme;
  const _XpNote({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: SeenlyPalette.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: HeartbeatIcon(size: 15, ring: false, color: SeenlyPalette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              LogThemeCopy.levelPointsNote(theme),
              style: SeenlyText.serif(size: 13, color: SeenlyPalette.accent),
            ),
          ),
        ],
      ),
    );
  }
}
