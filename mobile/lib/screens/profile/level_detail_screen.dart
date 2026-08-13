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
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/user_avatar.dart';

const _kMonthNames = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];


/// The person's own profile — identity (avatar, nickname, status, all
/// editable right here by tapping) up top, then everything that used to
/// be the whole screen (level ring, xp breakdown, level path) moved down
/// below it. Opened by tapping the streak+level card on Profile. Same real
/// numbers as before (level, xp, progress — see ProfileService.level /
/// backend/app/routers/profile.py::get_level), plus a breakdown of where
/// that xp actually came from, which the card only ever gestured at in
/// prose (see LogThemeCopy.levelXpNote).
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

  @override
  void initState() {
    super.initState();
    _future = widget.initial != null ? Future.value(widget.initial) : _load();
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
    final best = widget.wrapped?.longestStreak;
    final streakHeadline = LogThemeCopy.streakHeadline(theme, widget.stats.streakDays);
    final streakSubline = (best != null && best > 0) ? LogThemeCopy.streakBest(theme, best) : null;

    final user = context.watch<AppState>().currentUser;

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: Stack(
        children: [
          // Fills the empty space above the nickname with a soft, blurred
          // blow-up of the person's own avatar instead of flat background —
          // fades back into SeenlyPalette.background so everything below
          // (level ring, xp breakdown) is untouched.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _AvatarBackdrop(
              avatarUrl: user?.avatarUrl,
              avatarPreset: user?.avatarPreset,
              height: 360,
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      Text('your profile', style: SeenlyText.screenTitle),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<ProfileLevel>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData && !snapshot.hasError) {
                        return const Center(child: ThemedLoadingIndicator());
                      }
                      if (snapshot.hasError) {
                        return RefreshIndicator(
                          onRefresh: _refresh,
                          color: SeenlyPalette.accent,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 60),
                            children: [
                              Text("couldn't load your level",
                                  textAlign: TextAlign.center,
                                  style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted)),
                            ],
                          ),
                        );
                      }
                      final level = snapshot.data!;
                      return RefreshIndicator(
                        onRefresh: _refresh,
                        color: SeenlyPalette.accent,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                          children: [
                        const _ProfileIdentitySection(),
                        const SizedBox(height: 26),
                        Text(
                          LogThemeCopy.levelHeadline(theme, level.level),
                          textAlign: TextAlign.center,
                          style: SeenlyText.serif(italic: true, size: 17, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${level.xpIntoLevel} / ${level.xpForNextLevel} xp to level ${level.level + 1}',
                          textAlign: TextAlign.center,
                          style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: level.progress.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: SeenlyPalette.border,
                            valueColor: const AlwaysStoppedAnimation(SeenlyPalette.accent),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.paper,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: SeenlyPalette.softShadow,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.local_fire_department_outlined,
                                  size: 15, color: SeenlyPalette.accent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(streakHeadline, style: SeenlyText.serif(size: 13, weight: FontWeight.w600)),
                                    if (streakSubline != null) ...[
                                      const SizedBox(height: 2),
                                      Text(streakSubline,
                                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkMuted)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text('where your xp comes from', style: SeenlyText.sectionTitle),
                        const SizedBox(height: 10),
                        _BreakdownRow(
                          icon: Icons.local_movies_outlined,
                          label: LogThemeCopy.levelBreakdownLabel(theme, 'watched'),
                          count: level.watchedCount,
                          xp: level.xpFromWatched,
                        ),
                        _BreakdownRow(
                          icon: Icons.edit_note,
                          label: LogThemeCopy.levelBreakdownLabel(theme, 'reviews'),
                          count: level.reviewsCount,
                          xp: level.xpFromReviews,
                        ),
                        _BreakdownRow(
                          icon: Icons.replay,
                          label: LogThemeCopy.levelBreakdownLabel(theme, 'rewatches'),
                          count: level.rewatchCount,
                          xp: level.xpFromRewatches,
                        ),
                        _BreakdownRow(
                          icon: Icons.explore_outlined,
                          label: LogThemeCopy.levelBreakdownLabel(theme, 'genres'),
                          count: level.genresCount,
                          xp: level.xpFromGenres,
                        ),
                        _BreakdownRow(
                          icon: Icons.local_fire_department_outlined,
                          label: LogThemeCopy.levelBreakdownLabel(theme, 'streak'),
                          count: level.longestStreakEver,
                          xp: level.xpFromStreak,
                          isLast: true,
                        ),
                        const SizedBox(height: 28),
                        _LevelPathSection(level: level),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.accent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.favorite_border, size: 15, color: SeenlyPalette.accent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  LogThemeCopy.levelXpNote(theme),
                                  style: SeenlyText.serif(italic: true, size: 11.5, color: SeenlyPalette.accent),
                                ),
                              ),
                            ],
                          ),
                        ),
                          ],
                        ),
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
}

/// A soft, oversized, blurred blow-up of the user's own avatar (photo or
/// preset), used as a backdrop so the wide-open space above the nickname
/// isn't just flat background. Fades into [SeenlyPalette.background] toward
/// the bottom so it reads as an accent, not a poster.
class _AvatarBackdrop extends StatelessWidget {
  final String? avatarUrl;
  final String? avatarPreset;
  final double height;

  const _AvatarBackdrop({required this.avatarUrl, required this.avatarPreset, required this.height});

  @override
  Widget build(BuildContext context) {
    Widget? image;
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      final resolved = avatarUrl!.startsWith('http')
          ? Future.value(avatarUrl!)
          : context.read<AppState>().client.resolveBaseUrl().then((base) => '$base$avatarUrl');
      image = FutureBuilder<String>(
        future: resolved,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return Image.network(
            snap.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        },
      );
    } else if (avatarPreset != null) {
      final preset = kAvatarPresets.where((p) => p.id == avatarPreset).toList();
      if (preset.isNotEmpty) {
        image = Image.asset(preset.first.assetPath, fit: BoxFit.cover);
      }
    }

    if (image == null) return SizedBox(height: height, width: double.infinity);

    return ClipRect(
      child: SizedBox(
        width: double.infinity,
        height: height,
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
            // Stays visible behind the avatar itself (that's the point —
            // it should read as the photo sitting behind the profile, not
            // vanish before it even gets there), then dissolves gradually
            // over a wide band that finishes right as the nickname starts —
            // so the fade is long and soft rather than a hard cropped edge,
            // and the name/status below always land on solid background.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, SeenlyPalette.background],
                  stops: [0.4, 0.75],
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
// Identity — big centered avatar, nickname, status. Every one of the three
// is editable right where it sits: tap the avatar for a quick picker sheet
// (bundled presets or an uploaded photo), tap the name or status to turn
// it into a text field in place. No separate edit screen — same fields,
// same endpoints (ProfileService.updateMe / uploadAvatar) EditProfileScreen
// already used, just reached without leaving this page.
// ---------------------------------------------------------------------------

class _ProfileIdentitySection extends StatefulWidget {
  const _ProfileIdentitySection();

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
          .showSnackBar(const SnackBar(content: Text("couldn't save name")));
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
          .showSnackBar(const SnackBar(content: Text("couldn't save status")));
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
          .showSnackBar(const SnackBar(content: Text("couldn't save avatar")));
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
          .showSnackBar(SnackBar(content: Text("couldn't upload photo: $e")));
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
      transitionDuration: const Duration(milliseconds: 220),
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
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.currentUser;
    final letter = (user?.username.isNotEmpty ?? false) ? user!.username.substring(0, 1).toLowerCase() : '?';

    if (!_editingName) _nameController.text = user?.nameForDisplay ?? '';
    if (!_editingStatus) _statusController.text = user?.statusText ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _uploadingAvatar ? null : _openAvatarSheet,
          child: Stack(
            alignment: Alignment.center,
            children: [
              UserAvatar(
                avatarUrl: user?.avatarUrl,
                avatarPreset: user?.avatarPreset,
                fallbackLetter: letter,
                size: 140,
              ),
              if (_uploadingAvatar)
                const Positioned.fill(child: Center(child: ThemedLoadingIndicator(size: 26))),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: SeenlyPalette.background, width: 2.5),
                  ),
                  child: const Icon(Icons.camera_alt_outlined, size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _editingName
            ? SizedBox(
                width: 220,
                child: TextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  autofocus: true,
                  maxLength: 40,
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(size: 19, weight: FontWeight.w600),
                  decoration: const InputDecoration(
                      counterText: '', isDense: true, border: UnderlineInputBorder()),
                  onSubmitted: (_) => _saveName(),
                ),
              )
            : GestureDetector(
                onTap: () => setState(() => _editingName = true),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(user?.nameForDisplay ?? '',
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 13, color: SeenlyPalette.inkFaint),
                  ],
                ),
              ),
        const SizedBox(height: 8),
        _editingStatus
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: kStatusPresets.map((preset) {
                      return ActionChip(
                        label: Text(preset, style: SeenlyText.mono(size: 10.5)),
                        onPressed: () => _saveStatus(preset),
                      );
                    }).toList(),
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
                      style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: 'your own status',
                        border: UnderlineInputBorder(),
                      ),
                      onSubmitted: (_) => _saveStatus(),
                    ),
                  ),
                ],
              )
            : GestureDetector(
                onTap: () => setState(() => _editingStatus = true),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        (user?.statusText?.isNotEmpty ?? false) ? user!.statusText! : 'add a status',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 11, color: SeenlyPalette.inkFaint),
                  ],
                ),
              ),
        const SizedBox(height: 10),
        // Seenly's social graph is mutual-only (an accepted FriendRequest
        // row *is* the friendship — see backend/app/routers/friends.py).
        // There's no directional follow/follower concept in the data
        // model, so this only ever shows the one number that's real.
        const _RealFriendsCount(),
        if (user?.createdAt != null) ...[
          const SizedBox(height: 6),
          Text(
            'on teamira since '
            '${_kMonthNames[user!.createdAt!.month]} ${user.createdAt!.year}',
            style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
          ),
        ],
      ],
    );
  }
}

// Small self-contained fetch (independent of the rest of this screen's
// FutureBuilder, same reasoning as profile_screen.dart's own friends
// block) so a slow friends fetch never holds up the level/xp content
// below it, and vice versa.
class _RealFriendsCount extends StatefulWidget {
  const _RealFriendsCount();

  @override
  State<_RealFriendsCount> createState() => _RealFriendsCountState();
}

class _RealFriendsCountState extends State<_RealFriendsCount> {
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
    if (_count == null) return const SizedBox(height: 15);
    return _FollowCount(value: _count!, label: _count == 1 ? 'friend' : 'friends');
  }
}

class _FollowCount extends StatelessWidget {
  final int value;
  final String label;
  const _FollowCount({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: '$value', style: SeenlyText.mono(size: 11, color: SeenlyPalette.ink, weight: FontWeight.w600)),
          TextSpan(text: ' $label', style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
        ],
      ),
    );
  }
}

/// The "change avatar" popup — centered card over a blurred backdrop,
/// tap outside to dismiss. Matches HowItWorksSheet's card language rather
/// than a bottom sheet, so every popup reachable from this screen reads
/// the same way.
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(24),
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
                            child: Text('change avatar', style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 13, color: SeenlyPalette.inkMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onUploadPhoto();
                        },
                        icon: const Icon(Icons.photo_camera_outlined, size: 16),
                        label: Text('upload your own photo', style: SeenlyText.mono(size: 12)),
                      ),
                      const SizedBox(height: 10),
                      Text('or pick a ready-made avatar',
                          style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: kAvatarPresets.map((preset) {
                          final selected = currentAvatarUrl == null && currentAvatarPreset == preset.id;
                          return GestureDetector(
                            onTap: () {
                              Navigator.of(context).pop();
                              onPickPreset(preset.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected ? SeenlyPalette.accent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.asset(preset.assetPath, width: 52, height: 52, fit: BoxFit.cover),
                              ),
                            ),
                          );
                        }).toList(),
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

/// One line of the xp breakdown: icon, themed label, the raw count that
/// earned it, and how much xp it contributed — e.g. "42 evenings planted
/// · +420 xp".
class _BreakdownRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final int xp;
  final bool isLast;
  const _BreakdownRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.xp,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: SeenlyPalette.border, width: 1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: SeenlyPalette.inkMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SeenlyText.serif(size: 13.5)),
                const SizedBox(height: 1),
                Text('$count logged', style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
              ],
            ),
          ),
          Text('+$xp xp', style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.accent, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Level path — where the same xp curve the ring/progress bar above already
// uses (see ProfileLevel.progress / backend/app/routers/profile.py::
// _compute_level, base 100 xp + 40 xp more per level) turns into a short,
// honest look at what's just ahead: how much more xp each nearby level
// takes, and — for every fifth level, the milestones — a bigger card with
// the badge that level actually unlocks (see achievementIcon's 'level'
// case and backend's _LEVEL_MILESTONES, which is what the badges screen
// shows once that level is actually reached).
// ---------------------------------------------------------------------------

int _levelPathXpStep(int level) => 100 + 40 * (level - 1);

int _levelPathCumulativeXp(int level) {
  var total = 0;
  for (var k = 1; k < level; k++) {
    total += _levelPathXpStep(k);
  }
  return total;
}

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
      final isMilestone = n % 5 == 0;
      final isCurrent = n == cur;
      final isPast = n < cur;
      final cumXp = _levelPathCumulativeXp(n);
      final remaining = cumXp - level.xp;

      rows.add(
        isMilestone
            ? _LevelMilestoneCard(
                levelNumber: n,
                cumulativeXp: cumXp,
                remainingXp: remaining,
                isCurrent: isCurrent,
                isPast: isPast,
              )
            : _LevelPathRow(
                levelNumber: n,
                remainingXp: remaining,
                isCurrent: isCurrent,
                isPast: isPast,
              ),
      );
      if (n != end) rows.add(const SizedBox(height: 8));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('level path', style: SeenlyText.sectionTitle),
        const SizedBox(height: 3),
        Text(
          'a peek at what\'s just ahead',
          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
        ),
        const SizedBox(height: 12),
        ...rows,
      ],
    );
  }
}

/// One ordinary level in the path — a small pill, no artwork. Past levels
/// get a filled check disc, the current one an accent outline, everything
/// ahead just its number and the real xp still needed to get there.
class _LevelPathRow extends StatelessWidget {
  final int levelNumber;
  final int remainingXp;
  final bool isCurrent;
  final bool isPast;
  const _LevelPathRow({
    required this.levelNumber,
    required this.remainingXp,
    required this.isCurrent,
    required this.isPast,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent ? SeenlyPalette.accent.withOpacity(0.08) : SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(12),
        border: isCurrent ? Border.all(color: SeenlyPalette.accent, width: 1.2) : null,
        boxShadow: isCurrent ? null : SeenlyPalette.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPast ? SeenlyPalette.accent : SeenlyPalette.border,
            ),
            alignment: Alignment.center,
            child: isPast
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Text(
                    '$levelNumber',
                    style: SeenlyText.mono(
                      size: 10,
                      weight: FontWeight.w700,
                      color: isCurrent ? SeenlyPalette.accent : SeenlyPalette.inkMuted,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'level $levelNumber',
              style: SeenlyText.serif(size: 13.5, weight: isCurrent ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
          Text(
            isPast || remainingXp <= 0 ? 'reached' : '$remainingXp xp to go',
            style: SeenlyText.mono(size: 10, color: isCurrent ? SeenlyPalette.accent : SeenlyPalette.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// A milestone level (every 5th) — bigger, with the badge that level
/// unlocks (see achievementIcon's 'level' case, shared with the badges
/// screen so the two never draw a different icon for the same level).
/// Settles in with a gentle overshoot pop rather than appearing flat.
class _LevelMilestoneCard extends StatelessWidget {
  final int levelNumber;
  final int cumulativeXp;
  final int remainingXp;
  final bool isCurrent;
  final bool isPast;
  const _LevelMilestoneCard({
    required this.levelNumber,
    required this.cumulativeXp,
    required this.remainingXp,
    required this.isCurrent,
    required this.isPast,
  });

  @override
  Widget build(BuildContext context) {
    final reached = isCurrent || isPast;
    final subtitle = reached ? 'badge unlocked' : 'unlocks a badge';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1.0),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent ? SeenlyPalette.accent.withOpacity(0.10) : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isCurrent ? SeenlyPalette.accent : SeenlyPalette.border,
            width: isCurrent ? 1.4 : 1,
          ),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            RoundBadgeMedallion(
              iconKey: 'level',
              title: 'level $levelNumber',
              rarity: levelBadgeRarityKey(levelNumber),
              unlocked: reached,
              diameter: 44,
              showLabel: false,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('level $levelNumber', style: SeenlyText.serif(size: 16.5, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkMuted)),
                  const SizedBox(height: 6),
                  Text(
                    isPast || remainingXp <= 0 ? 'reached at $cumulativeXp xp' : '$remainingXp xp to go',
                    style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.accent, weight: FontWeight.w600),
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
