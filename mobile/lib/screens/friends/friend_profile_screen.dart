import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/activity_item.dart';
import '../../models/friend.dart';
import '../../models/watchlist_entry.dart';
import '../../services/api_client.dart';
import '../../services/log_theme_service.dart';
import '../../services/premium_service.dart';
import '../../state/app_state.dart';
import '../../widgets/report_sheet.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../utils/server_time.dart';
import '../../widgets/achievement_badge.dart';
import '../../widgets/activity_preview.dart';
import '../../widgets/favorites_showcase_row.dart';
import '../../widgets/mosaic_poster_grid.dart';
import '../../widgets/plan_outgrown_sheet.dart';
import '../../widgets/premium_upsell_sheet.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/taste_match_card.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/watched_preview_sheet.dart';
import '../../widgets/wow_motion.dart';
import '../profile/favorite_films_screen.dart';
import '../../services/app_translations.dart';
import '../../theme/clay_kit.dart';
import '../../services/locale_service.dart';

/// A friend's own profile — reached by tapping their row on the friends
/// screen, a card in the friends activity feed, or a "people you may
/// know" preview. Shows their avatar/name/status/level plus the three
/// shelves (watched / watching now / plan to watch), each one only if
/// they've left it visible to a friend (see
/// backend/app/routers/friends.py::get_friend_profile) — a shelf they've
/// set to "nobody" shows a quiet note instead of an empty grid, so it
/// never reads as "they have nothing planned" when the truth is just
/// "they'd rather not say".
class FriendProfileScreen extends StatefulWidget {
  final String userId;
  final String? seedUsername;
  final String? seedDisplayName;
  final String? seedAvatarPreset;
  final String? seedAvatarUrl;

  const FriendProfileScreen({
    super.key,
    required this.userId,
    this.seedUsername,
    this.seedDisplayName,
    this.seedAvatarPreset,
    this.seedAvatarUrl,
  });

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  FriendProfile? _data;
  bool _loading = true;
  bool _failed = false;
  int _tab = 0; // 0 = watched, 1 = watching now, 2 = plan to watch

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final data = await context.read<AppState>().friends.friendProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final displayName = data?.nameForDisplay ??
        (widget.seedDisplayName?.trim().isNotEmpty == true ? widget.seedDisplayName! : widget.seedUsername) ??
        '';

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
              child: Row(
                children: [
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(displayName, style: SeenlyText.screenTitle, overflow: TextOverflow.ellipsis),
                  ),
                  // The two things App Store guideline 1.2 asks for, on
                  // the one screen where somebody would actually look for
                  // them: block and report, on every profile that isn't
                  // your own. An overflow menu rather than two visible
                  // buttons — a profile is usually a friend's, and a
                  // permanent "report" button next to their name sets a
                  // tone this app isn't for. One tap away is the right
                  // distance: findable when needed, invisible otherwise.
                  if (data != null)
                    _ProfileOverflowMenu(
                      userId: widget.userId,
                      name: displayName,
                      onChanged: () {
                        // Blocking makes this profile a 404 server-side,
                        // so there is nothing left to show — leave rather
                        // than reload into an error.
                        if (mounted) Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: ThemedLoadingIndicator())
                  : _failed || data == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Entrance(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text("couldn't load this profile".tr,
                                      textAlign: TextAlign.center,
                                      style: SeenlyText.serif(italic: true, color: SeenlyPalette.inkMuted)),
                                  const SizedBox(height: 10),
                                  PressScale(
                                    onTap: _load,
                                    child: Text('tap to try again'.tr,
                                        style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: SeenlyPalette.accent,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                            children: [
                              _Header(data: data, onRefresh: _load),
                              if (data.tasteMatch != null) ...[
                                const SizedBox(height: 14),
                                TasteMatchDetail(match: data.tasteMatch!, compact: true),
                              ],
                              const SizedBox(height: 18),
                              FavoritesShowcaseRow(
                                entries: data.collections.favorites,
                                visible: data.collections.favoritesVisible,
                                topKeys: data.collections.topFavoritePicks.map((p) => p.key).toList(),
                                trailingEmpty: 'none yet ›',
                                bodyEmptyText:
                                    '${data.nameForDisplay} ${"hasn't pinned any favorite films yet".tr}',
                                bodyPrivateText:
                                    '${data.nameForDisplay} ${'keeps their favorites private'.tr}',
                                onSeeAll: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => FavoriteFilmsScreen(
                                      userId: widget.userId,
                                      seedDisplayName: data.nameForDisplay,
                                      seedAvatarPreset: data.avatarPreset,
                                      seedAvatarUrl: data.avatarUrl,
                                    ),
                                  ),
                                ),
                                onTapEntry: (e) => showWatchedPreview(
                                  context,
                                  WatchedPreviewData.fromFriendEntry(
                                    e,
                                    friendLabel: LocaleService.pick('избранное: ${data.nameForDisplay}', "${data.nameForDisplay}'s favorites"),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (data.pinnedAchievements.isNotEmpty) ...[
                                Text('badges'.tr,
                                    style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)
                                        .copyWith(letterSpacing: 0.6)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    for (int i = 0; i < data.pinnedAchievements.length; i++) ...[
                                      if (i > 0) const SizedBox(width: 14),
                                      AchievementBadge(
                                        theme: context.watch<LogThemeService>().theme,
                                        iconKey: data.pinnedAchievements[i].iconKey,
                                        label: data.pinnedAchievements[i].title,
                                        unlocked: true,
                                        size: AchievementBadgeSize.large,
                                        rarity: data.pinnedAchievements[i].rarity,
                                        pinned: true,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],
                              UnderlineTabRow(
                                labels: ['watched'.tr, 'watching now'.tr, 'plan to watch'.tr],
                                activeIndex: _tab,
                                onChanged: (i) => setState(() => _tab = i),
                              ),
                              const SizedBox(height: 16),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) => FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
                                        .animate(animation),
                                    child: child,
                                  ),
                                ),
                                child: _Shelf(
                                  key: ValueKey(_tab),
                                  friendName: data.nameForDisplay,
                                  entries: _tab == 0
                                      ? data.collections.watched
                                      : _tab == 1
                                          ? data.collections.watching
                                          : data.collections.watchLater,
                                  visible: _tab == 0
                                      ? data.collections.watchedVisible
                                      : _tab == 1
                                          ? data.collections.watchingVisible
                                          : data.collections.watchLaterVisible,
                                ),
                              ),
                              const SizedBox(height: 22),
                              _ActivitySection(
                                friendName: data.nameForDisplay,
                                items: data.recentActivity,
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final FriendProfile data;
  final VoidCallback onRefresh;
  const _Header({required this.data, required this.onRefresh});

  static const double _bannerHeight = 128;
  static const double _avatarSize = 84;
  static const double _avatarOverlap = 30;

  @override
  Widget build(BuildContext context) {
    final isOwnProfile = context.watch<AppState>().currentUser?.id == data.userId;
    final tint = SeenlyPalette.gridColorFor(data.username.hashCode);
    final stackHeight = _bannerHeight + (_avatarSize - _avatarOverlap) + 8;
    // A cover photo pulled from the same favorite that already headlines
    // their favorites row on this screen — same "cover banner + avatar
    // overlapping its bottom edge" language the person's own profile
    // uses, so a friend's page finally reads as the same app instead of
    // a plain generic contact card. Falls back to a soft tinted wash
    // (still dressed with a washi-tape corner, same accent every
    // polaroid card on the friends list already wears) when they don't
    // have a favorite to show, or keep favorites private.
    final cover = data.collections.favoritesVisible && data.collections.favorites.isNotEmpty
        ? (data.collections.favorites.first.backdropUrl ?? data.collections.favorites.first.posterUrl)
        : null;

    return Column(
      children: [
        SizedBox(
          height: stackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: _bannerHeight,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover != null)
                          FadeInNetworkImage(
                            url: cover,
                            fit: BoxFit.cover,
                            placeholder: Container(color: tint.withOpacity(0.35)),
                          )
                        else
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [tint.withOpacity(0.5), tint.withOpacity(0.22)],
                              ),
                            ),
                          ),
                        // scrim so the avatar's ring and any text over the
                        // bottom edge stay readable over a busy photo
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, SeenlyPalette.ink.withOpacity(0.25)],
                            ),
                          ),
                        ),
                        Positioned(
                          top: -9,
                          left: 30,
                          child: Transform.rotate(
                            angle: -0.11,
                            child: Container(width: 50, height: 17, color: SeenlyPalette.tapeMustard.withOpacity(0.85)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: _bannerHeight - _avatarOverlap,
                left: 18,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SeenlyPalette.paper,
                    boxShadow: [
                      BoxShadow(color: SeenlyPalette.ink.withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: UserAvatar(
                    avatarUrl: data.avatarUrl,
                    avatarPreset: data.avatarPreset,
                    fallbackLetter: data.nameForDisplay.isNotEmpty ? data.nameForDisplay[0].toUpperCase() : '?',
                    size: _avatarSize,
                  ),
                ),
              ),
              Positioned(
                top: _bannerHeight + 8,
                left: 18 + _avatarSize + 14,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(data.nameForDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SeenlyText.serif(size: 18, weight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        _LevelBadge(level: data.level),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('@${data.username}', style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if ((data.statusText ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('"'.tr, style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.accent.withOpacity(0.55))),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    data.statusText!,
                    style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!isOwnProfile) ...[
          const SizedBox(height: 16),
          _ActionRow(data: data, onRefresh: onRefresh),
        ],
      ],
    );
  }
}

/// The small floating level disc worn next to a name everywhere in the
/// app (see _LevelRing on the person's own profile) — same paper disc
/// with a soft shadow and an accent ring, just without the fill
/// animation, since a friend's profile only ever gets the flat level
/// number (see FriendProfile.level), never the points fraction the ring on
/// one's own profile animates in from.
class _LevelBadge extends StatelessWidget {
  final int level;
  final double size;
  const _LevelBadge({required this.level, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        shape: BoxShape.circle,
        border: Border.all(color: SeenlyPalette.accent, width: 2),
        boxShadow: [
          BoxShadow(color: SeenlyPalette.ink.withOpacity(0.10), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text('$level', style: SeenlyText.serif(size: 12, weight: FontWeight.w700, color: SeenlyPalette.accent)),
        ),
      ),
    );
  }
}

/// The two relationship actions on someone else's profile — "friends"
/// and "co-viewing", each its own soft pill that reads whichever state
/// the two accounts are actually in (see FriendProfile.friendshipStatus
/// / coviewStatus) rather than just always saying "add". Kept side by
/// side rather than stacked so the header doesn't grow taller than it
/// needs to on the common case (nothing pending either way).
class _ActionRow extends StatefulWidget {
  final FriendProfile data;
  final VoidCallback onRefresh;
  const _ActionRow({required this.data, required this.onRefresh});

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _friendBusy = false;
  bool _coviewBusy = false;

  Future<void> _sendFriendRequest() async {
    setState(() => _friendBusy = true);
    try {
      await context.read<AppState>().friends.sendRequest(widget.data.username);
      widget.onRefresh();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _acceptFriendRequest() async {
    final id = widget.data.friendRequestId;
    if (id == null) return;
    setState(() => _friendBusy = true);
    try {
      await context.read<AppState>().friends.acceptRequest(id);
      widget.onRefresh();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _cancelFriendRequest() async {
    final id = widget.data.friendRequestId;
    if (id == null) return;
    setState(() => _friendBusy = true);
    try {
      await context.read<AppState>().friends.cancelRequest(id);
      widget.onRefresh();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _confirmUnfriend() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SeenlyPalette.paper,
        title: Text('${'remove'.tr} ${widget.data.nameForDisplay}?', style: SeenlyText.serif(weight: FontWeight.w700)),
        content: Text("you'll need a new request to be friends again.".tr,
            style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('remove'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _friendBusy = true);
    try {
      await context.read<AppState>().friends.removeFriend(widget.data.userId);
      widget.onRefresh();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  /// A couple stays free forever; growing past that into a company is
  /// premium (see PremiumService.canGrowCoViewCircle) — same rule
  /// CoViewingScreen's own "add to circle" button enforces, just
  /// checked here too since this button is the other way to reach
  /// PartnerService.sendInvite. Needs a fresh look at this account's
  /// own circle size first, since that isn't part of a friend's profile
  /// data.
  Future<void> _sendCoviewInvite() async {
    setState(() => _coviewBusy = true);
    try {
      final app = context.read<AppState>();
      final myStatus = await app.partner.status();
      final currentSize = myStatus.linked ? myStatus.members.length : 1;
      if (!mounted) return;
      if (!context.read<PremiumService>().canGrowCoViewCircle(currentSize)) {
        setState(() => _coviewBusy = false);
        await showPremiumUpsellSheet(
          context,
          triggerSource: 'co_view_circle_size',
          // Someone growing a pair into a company is exactly who the
          // family plan is for.
          initialKind: PremiumPlanKind.family,
          icon: Icons.people_outline,
          title: 'a bigger circle is premium'.tr,
          message: 'a couple stays free forever — premium lets you watch together as a company, three and up'.tr,
        );
        return;
      }
      final premium = context.read<PremiumService>();
      if (premium.circleOutgrowsPlan(currentSize)) {
        setState(() => _coviewBusy = false);
        final proceed = await confirmCircleOutgrowsPlan(context, premium: premium);
        if (!proceed || !mounted) return;
        setState(() => _coviewBusy = true);
      }
      await app.partner.sendInvite(widget.data.userId);
      widget.onRefresh();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _coviewBusy = false);
    }
  }

  Future<void> _acceptCoviewInvite() async {
    final id = widget.data.coviewInviteId;
    if (id == null) return;
    setState(() => _coviewBusy = true);
    try {
      final status = await context.read<AppState>().partner.acceptInvite(id);
      // Fresh couple, just formed — see AppState.notePartnerJustLinked's
      // own doc comment on why exactly-two is enough to mean that
      // without extra bookkeeping.
      if (status.linked &&
          status.members.length == 2 &&
          mounted &&
          !context.read<PremiumService>().isPremium) {
        context.read<AppState>().notePartnerJustLinked();
      }
      widget.onRefresh();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _coviewBusy = false);
    }
  }

  Future<void> _declineCoviewInvite() async {
    final id = widget.data.coviewInviteId;
    if (id == null) return;
    setState(() => _coviewBusy = true);
    try {
      await context.read<AppState>().partner.declineInvite(id);
      widget.onRefresh();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _coviewBusy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: SeenlyText.mono(size: 11, color: SeenlyPalette.accentOnAccent))),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Wrap rather than Row — "invite to co-viewing" next to something
    // like "accept request" can run past a narrow phone's width, and a
    // pill wrapping onto its own line beats it getting clipped or
    // forcing the header to scroll sideways.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        _friendPill(),
        _coviewPill(),
      ],
    );
  }

  Widget _friendPill() {
    if (_friendBusy) return const _PillSpinner();
    switch (widget.data.friendshipStatus) {
      case 'friends':
        return _SoftPill(
          icon: Icons.people_alt_rounded,
          label: 'friends'.tr,
          filled: false,
          tint: SeenlyPalette.sage,
          onTap: _confirmUnfriend,
        );
      case 'pending_outgoing':
        return _SoftPill(
          icon: Icons.hourglass_top_rounded,
          label: 'requested'.tr,
          filled: false,
          tint: SeenlyPalette.mustard,
          onTap: _cancelFriendRequest,
        );
      case 'pending_incoming':
        return _SoftPill(
          icon: Icons.person_add,
          label: 'accept request'.tr,
          filled: true,
          onTap: _acceptFriendRequest,
        );
      default:
        return _SoftPill(
          icon: Icons.person_add_alt,
          label: 'add friend'.tr,
          filled: true,
          onTap: _sendFriendRequest,
        );
    }
  }

  Widget _coviewPill() {
    if (_coviewBusy) return const _PillSpinner();
    switch (widget.data.coviewStatus) {
      case 'same_circle':
        return _SoftPill(
          icon: Icons.favorite_rounded,
          label: 'in your circle'.tr,
          filled: false,
          tint: SeenlyPalette.pink,
          onTap: null,
        );
      case 'pending_outgoing':
        return _SoftPill(
          icon: Icons.hourglass_top_rounded,
          label: 'invite sent'.tr,
          filled: false,
          tint: SeenlyPalette.periwinkle,
          onTap: _sendCoviewInvite, // tapping again just re-sends (idempotent server-side)
        );
      case 'pending_incoming':
        return _SoftPill(
          icon: Icons.favorite,
          label: 'accept invite'.tr,
          filled: true,
          onTap: _acceptCoviewInvite,
          onLongPress: _declineCoviewInvite,
        );
      default:
        return _SoftPill(
          icon: Icons.tv_rounded,
          label: 'invite to co-viewing'.tr,
          filled: false,
          tint: SeenlyPalette.periwinkle,
          onTap: _sendCoviewInvite,
        );
    }
  }
}

/// One rounded pill action — solid accent for the primary "do this"
/// state (add / accept), or, for a passive/secondary state (already
/// friends, waiting on a reply, in the same co-viewing circle), a soft
/// wash of whichever categorical color that state means elsewhere in
/// the app (sage for a settled friendship, mustard for "waiting",
/// periwinkle for co-viewing, pink for "in your circle") — the same
/// tinted-chip language already used for genre/status chips across the
/// app, instead of a flat, meaning-free white oval.
class _SoftPill extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool filled;
  Color get tint => _tint ?? SeenlyPalette.accent;
  final Color? _tint;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  _SoftPill({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
    Color? tint,
    this.onLongPress,
  }) : _tint = tint;

  @override
  State<_SoftPill> createState() => _SoftPillState();
}

class _SoftPillState extends State<_SoftPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.96 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
          decoration: BoxDecoration(
            color: widget.filled ? SeenlyPalette.accent : widget.tint.withOpacity(0.16),
            borderRadius: BorderRadius.circular(20),
            border: widget.filled ? null : Border.all(color: widget.tint.withOpacity(0.35), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: widget.filled ? SeenlyPalette.accentOnAccent : widget.tint),
              const SizedBox(width: 6),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: SeenlyText.mono(
                  size: 10,
                  weight: FontWeight.w700,
                  color: widget.filled ? SeenlyPalette.accentOnAccent : widget.tint,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillSpinner extends StatelessWidget {
  const _PillSpinner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 13,
        height: 13,
        child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
      ),
    );
  }
}



class _Shelf extends StatelessWidget {
  final String friendName;
  final List<WatchlistEntry> entries;
  final bool visible;
  const _Shelf({super.key, required this.friendName, required this.entries, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Entrance(
            child: Text(
              '$friendName ${'keeps this shelf private'.tr}',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
            ),
          ),
        ),
      );
    }
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Entrance(
            child: Text('nothing here yet'.tr,
                style: SeenlyText.emptyState()),
          ),
        ),
      );
    }
    return MosaicPosterGrid(
      itemCount: entries.length,
      order: List.generate(entries.length, (i) => i),
      revealGen: 0,
      spacing: 12,
      keyOf: (i) => entries[i].id,
      tileBuilder: (context, i, gridIndex, aspect) {
        final e = entries[i];
        return TiltPosterTile(
          onTap: () => showWatchedPreview(
            context,
            WatchedPreviewData.fromFriendEntry(e, friendLabel: LocaleService.pick('активность: $friendName', "$friendName's activity")),
          ),
          onLongPress: () => _shareEntry(e),
          child: MosaicParallaxPoster(
            builder: (parallax) => ThemedPosterTile(
              title: e.displayTitle,
              posterUrl: e.posterUrl,
              mediaType: e.mediaType,
              fallbackColor: SeenlyPalette.gridColorFor(i),
              aspectRatio: aspect,
              parallax: parallax,
            ),
          ),
        );
      },
    );
  }
}

/// Recent activity block below the shelves — same privacy gating as
/// everything else on this screen (see
/// backend/app/routers/friends.py::get_friend_profile): a stranger only
/// sees events left at "everyone", an accepted friend sees "friends" too,
/// "nobody" never shows here regardless of who's looking. Quietly hides
/// itself rather than showing an empty-state note, since "no activity"
/// here is a common, unremarkable case (a brand new account, or someone
/// who's kept every shelf private) rather than something worth calling
/// out the way an empty shelf tab is.
///
/// A grid, like the watched/watching/plan-to-watch shelves right above
/// it (see [_Shelf]) — but 2-up instead of 3, and each poster keeps its
/// caption underneath (title, what happened, when) instead of standing
/// alone, since this row is telling a little story per item rather than
/// just displaying a collection.
class _ActivitySection extends StatelessWidget {
  final String friendName;
  final List<ActivityItem> items;
  const _ActivitySection({required this.friendName, required this.items});

  String _relativeTime(String iso) {
    final parsed = tryParseServerUtc(iso);
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'just now'.tr;
    if (diff.inMinutes < 60) {
      return '${nCount('nMinutes', diff.inMinutes)} ${'ago'.tr}';
    }
    if (diff.inHours < 24) {
      return '${nCount('nHours', diff.inHours)} ${'ago'.tr}';
    }
    if (diff.inDays < 7) {
      return '${nCount('nDays', diff.inDays)} ${'ago'.tr}';
    }
    return '${nCount('nWeeks', (diff.inDays / 7).floor())} ${'ago'.tr}';
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('activity'.tr,
            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint).copyWith(letterSpacing: 0.6)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 18,
            crossAxisSpacing: 14,
            childAspectRatio: 0.54,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => Entrance(
            // Staggered so the grid arrives as a small held-breath
            // cascade rather than popping in flat — capped so a long
            // history doesn't leave the last few tiles waiting on it.
            delay: Duration(milliseconds: 55 * i.clamp(0, 6)),
            riseBy: 16,
            child: _ActivityCard(
              item: items[i],
              friendName: friendName,
              relativeTime: _relativeTime(items[i].createdAt),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final ActivityItem item;
  final String friendName;
  final String relativeTime;
  const _ActivityCard({required this.item, required this.friendName, required this.relativeTime});

  @override
  Widget build(BuildContext context) {
    // Same categorical color the shelves/grid already use for this media
    // type — a grid of mixed activity (a film here, a show there) reads
    // as color-coded at a glance, and it's the accent the verb line
    // below borrows too, so each tile feels like one considered piece.
    final accent = SeenlyPalette.mediaColor(item.mediaType ?? 'movie');
    final tappable = item.hasPoster;

    return PressScale(
      haptics: tappable,
      onTap: tappable ? () => showWatchedPreview(context, watchedPreviewFromActivity(item)) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: accent.withOpacity(0.24), blurRadius: 12, offset: const Offset(0, 5)),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ThemedPosterTile(
                      title: item.mediaTitle ?? item.text,
                      posterUrl: item.posterUrl,
                      fallbackColor: accent,
                      mediaType: item.mediaType,
                    ),
                  ),
                  if (item.rating != null && item.rating! > 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: PosterRatingBadge(rating: item.rating!),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.mediaTitle ?? item.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.serif(size: 12.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            item.verb ?? item.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 9.5, color: accent).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(relativeTime, style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
        ],
      ),
    );
  }
}

/// Long-press action for a shelf tile (see [_Shelf]'s mosaic grid above)
/// — same title + year fallback as collection_full_screen.dart's own
/// `_shareMediaItem`, since a [WatchlistEntry] carries no external ids
/// to link out to.
void _shareEntry(WatchlistEntry e) {
  final bits = [
    e.displayTitle,
    if (e.year != null) '(${e.year})',
  ].join(' ');
  Share.share(bits);
}


/// Block / report, on any profile that isn't your own.
///
/// Blocking is confirmed first and reporting is not: a block is
/// immediate, consequential, and easy to hit by accident in a menu, while
/// the report sheet is itself the confirmation step (pick a reason, add
/// detail, send). Asking twice for a report would just be a second thing
/// to dismiss.
class _ProfileOverflowMenu extends StatelessWidget {
  final String userId;
  final String name;
  final VoidCallback onChanged;

  const _ProfileOverflowMenu({
    required this.userId,
    required this.name,
    required this.onChanged,
  });

  Future<void> _confirmBlock(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SeenlyPalette.paper,
        title: Text('${'block'.tr} $name?',
            style: SeenlyText.serif(weight: FontWeight.w700)),
        content: Text(
          "they won't be able to see your profile or your evenings, or reach you — and you won't see them anywhere. they're never told."
              .tr,
          style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('block'.tr,
                style: SeenlyText.mono(
                    size: 11, color: SeenlyPalette.coral, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<AppState>().moderation.block(userId);
      onChanged();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _report(BuildContext context) async {
    final blocked = await showReportSheet(
      context,
      reportedUserId: userId,
      reportedName: name,
    );
    // The report sheet offers "also block them" — if it was taken, this
    // profile no longer exists for us either.
    if (blocked) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: SeenlyPalette.paper,
      icon: Icon(Icons.more_horiz, size: 19, color: SeenlyPalette.inkMuted),
      onSelected: (value) {
        if (value == 'block') _confirmBlock(context);
        if (value == 'report') _report(context);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: 16, color: SeenlyPalette.inkMuted),
              const SizedBox(width: 10),
              Text('report'.tr, style: SeenlyText.serif(size: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'block',
          child: Row(
            children: [
              Icon(Icons.block_outlined, size: 16, color: SeenlyPalette.coral),
              const SizedBox(width: 10),
              Text('block'.tr,
                  style: SeenlyText.serif(size: 13, color: SeenlyPalette.coral)),
            ],
          ),
        ),
      ],
    );
  }
}
