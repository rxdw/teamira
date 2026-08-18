import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../models/profile_stats.dart';
import '../../services/api_client.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/invite_friends_sheet.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/wow_motion.dart';
import 'friend_profile_screen.dart';
import '../../services/app_translations.dart';

/// The friends system's home screen — reached from the profile's own
/// friends block ("see all"). Everything here reads from `/friends` (see
/// backend/app/routers/friends.py): the accepted list with live levels,
/// pending requests in both directions, a username search to start a new
/// one, and the invite sheet for people who aren't on teamira yet.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  FriendsData? _data;
  bool _loading = true;
  List<SuggestedFriend> _suggested = const [];

  final _searchController = TextEditingController();
  List<FriendSearchResult> _searchResults = const [];
  bool _searching = false;
  Timer? _debounce;

  // Request ids / user ids with an action in flight, so a slow tap can't
  // be double-fired and each row can show its own tiny spinner.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<AppState>().friends.list();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
    // Best-effort, separate from the main load above — a slow or failed
    // suggestions fetch shouldn't hold up (or fail) the friends list
    // itself, which is the whole point of this screen.
    try {
      final suggested = await context.read<AppState>().friends.suggested();
      if (!mounted) return;
      setState(() => _suggested = suggested);
    } catch (_) {
      // leave whatever was there (or nothing) rather than surface an error
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await context.read<AppState>().friends.search(query);
        if (!mounted || _searchController.text.trim() != query) return;
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _searching = false);
      }
    });
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("that didn't go through — try again".tr)));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _sendRequest(String username) => _run(username, () async {
        await context.read<AppState>().friends.sendRequest(username);
        await Future.wait([_load(), _refreshSearch()]);
      });

  Future<void> _accept(String requestId) => _run(requestId, () async {
        await context.read<AppState>().friends.acceptRequest(requestId);
        await _load();
      });

  Future<void> _decline(String requestId) => _run(requestId, () async {
        await context.read<AppState>().friends.declineRequest(requestId);
        await _load();
      });

  Future<void> _cancel(String requestId) => _run(requestId, () async {
        await context.read<AppState>().friends.cancelRequest(requestId);
        await _load();
      });

  Future<void> _remove(String userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SeenlyPalette.paper,
        title: Text('${'remove'.tr} $username?', style: SeenlyText.serif(size: 16)),
        content: Text(
          "you'll stop seeing each other's activity — either of you can send a new request later.".tr,
          style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr, style: SeenlyText.mono(size: 11)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('remove'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(userId, () async {
      await context.read<AppState>().friends.removeFriend(userId);
      await _load();
    });
  }

  Future<void> _refreshSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    try {
      final results = await context.read<AppState>().friends.search(query);
      if (!mounted) return;
      setState(() => _searchResults = results);
    } catch (_) {
      // leave the stale results up rather than clearing them over one miss
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final showingSearch = _searchController.text.trim().isNotEmpty;

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
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('friends'.tr, style: SeenlyText.screenTitle),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(hintText: 'find someone by username'.tr),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: ThemedLoadingIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: SeenlyPalette.accent,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: ListView(
                          key: ValueKey(showingSearch),
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                          children: showingSearch
                              ? _searchSection()
                              : _mainSections(data),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _searchSection() {
    if (_searching) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: ThemedLoadingIndicator()),
        ),
      ];
    }
    if (_searchResults.isEmpty) {
      return [
        Entrance(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('no one on teamira has that username'.tr,
                style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted)),
          ),
        ),
      ];
    }
    return _searchResults.asMap().entries.map((entry) => Entrance(
          delay: Duration(milliseconds: 30 * entry.key.clamp(0, 8)),
          riseBy: 10,
          child: _SearchResultRow(
            result: entry.value,
            busy: _busy.contains(entry.value.username),
            onAdd: () => _sendRequest(entry.value.username),
          ),
        )).toList();
  }

  List<Widget> _mainSections(FriendsData? data) {
    final friends = data?.friends ?? const [];
    final incoming = data?.incomingRequests ?? const [];
    final outgoing = data?.outgoingRequests ?? const [];

    var revealIndex = 0;
    Widget reveal(Widget child) => ScrollReveal(delay: Duration(milliseconds: 35 * (revealIndex++).clamp(0, 10)), child: child);

    // Lays cards two to a row instead of one long single-file column —
    // width is computed from whatever space is actually available (list
    // padding already applied by the caller) so the pair always fills
    // the row edge-to-edge instead of leaving the old dead space on the
    // right, on any screen size.
    const gridSpacing = 14.0;
    Widget grid(List<Widget Function(double cardWidth)> items) {
      return LayoutBuilder(builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - gridSpacing) / 2;
        // A lone leftover card (odd count, most often just one) sitting
        // pinned to the left under a full two-up grid reads like a
        // mistake — center it on its own row instead.
        if (items.length == 1) {
          return Center(child: items.first(cardWidth));
        }
        return Wrap(
          spacing: gridSpacing,
          runSpacing: 16,
          children: items.map((build) => build(cardWidth)).toList(),
        );
      });
    }

    return [
      _InviteRow(onTap: () => showInviteFriendsSheet(context)),
      const SizedBox(height: 18),
      if (incoming.isNotEmpty) ...[
        Text('requests'.tr, style: SeenlyText.serif(size: 16, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        grid(incoming.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          final busy = _busy.contains(r.id);
          return (double cardWidth) => reveal(_PolaroidCard(
                avatarUrl: r.avatarUrl,
                avatarPreset: r.avatarPreset,
                fallbackLetter: r.username.isNotEmpty ? r.username[0].toUpperCase() : '?',
                index: i,
                title: r.nameForDisplay,
                subtitle: 'wants to be friends'.tr,
                cardWidth: cardWidth,
                corner: _cornerStamp(
                  onTap: () => _accept(r.id),
                  icon: Icons.check,
                  bg: SeenlyPalette.accent,
                  fg: SeenlyPalette.accentOnAccent,
                  busy: busy,
                ),
                secondaryCorner: busy
                    ? null
                    : _cornerStamp(onTap: () => _decline(r.id), icon: Icons.close, bg: SeenlyPalette.paper, fg: SeenlyPalette.inkMuted),
              ));
        }).toList()),
        const SizedBox(height: 8),
      ],
      if (outgoing.isNotEmpty) ...[
        Text('sent'.tr, style: SeenlyText.serif(size: 16, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        grid(outgoing.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          return (double cardWidth) => reveal(_PolaroidCard(
                avatarUrl: r.avatarUrl,
                avatarPreset: r.avatarPreset,
                fallbackLetter: r.username.isNotEmpty ? r.username[0].toUpperCase() : '?',
                index: i,
                title: r.nameForDisplay,
                subtitle: 'request sent'.tr,
                cardWidth: cardWidth,
                corner: _cornerStamp(
                  onTap: () => _cancel(r.id),
                  icon: Icons.close,
                  bg: SeenlyPalette.paper,
                  fg: SeenlyPalette.inkMuted,
                  busy: _busy.contains(r.id),
                ),
              ));
        }).toList()),
        const SizedBox(height: 8),
      ],
      Text('${'friends'.tr} · ${friends.length}',
          style: SeenlyText.serif(size: 16, weight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (friends.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'search a username above, or invite someone who isn\'t on teamira yet'.tr,
            style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
          ),
        )
      else
        grid(friends.asMap().entries.map((entry) {
          final i = entry.key;
          final f = entry.value;
          final recent = f.recentActivity;
          final subtitle = (recent != null && recent.mediaTitle != null)
              ? 'watched "${recent.mediaTitle}"'
              : ((f.statusText?.isNotEmpty ?? false) ? f.statusText! : 'level ${f.level}');
          return (double cardWidth) => reveal(_PolaroidCard(
                avatarUrl: f.avatarUrl,
                avatarPreset: f.avatarPreset,
                fallbackLetter: f.username.isNotEmpty ? f.username[0].toUpperCase() : '?',
                index: i,
                title: f.nameForDisplay,
                subtitle: subtitle,
                cardWidth: cardWidth,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FriendProfileScreen(
                    userId: f.userId,
                    seedUsername: f.username,
                    seedDisplayName: f.displayName,
                    seedAvatarPreset: f.avatarPreset,
                    seedAvatarUrl: f.avatarUrl,
                  ),
                )),
                corner: _busy.contains(f.userId)
                    ? _cornerStamp(onTap: null, icon: Icons.more_horiz, bg: SeenlyPalette.paper, fg: SeenlyPalette.inkFaint, busy: true)
                    : PressScale(
                        onTap: () => _remove(f.userId, f.username),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: SeenlyPalette.paper,
                            shape: BoxShape.circle,
                            border: Border.all(color: SeenlyPalette.paper, width: 2),
                            boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.2), blurRadius: 5, offset: const Offset(0, 2))],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.more_horiz, size: 16, color: SeenlyPalette.inkMuted),
                        ),
                      ),
              ));
        }).toList()),
      if (_suggested.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('people you may know'.tr, style: SeenlyText.serif(size: 16, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        grid(_suggested.asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          final preview = s.recentActivity.isNotEmpty ? s.recentActivity.first : null;
          final subtitle = preview?.mediaTitle != null ? 'watched "${preview!.mediaTitle}"' : 'level ${s.level}';
          return (double cardWidth) => reveal(_PolaroidCard(
                avatarUrl: s.avatarUrl,
                avatarPreset: s.avatarPreset,
                fallbackLetter: s.username.isNotEmpty ? s.username[0].toUpperCase() : '?',
                index: i,
                title: s.nameForDisplay,
                subtitle: subtitle,
                cardWidth: cardWidth,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FriendProfileScreen(
                    userId: s.userId,
                    seedUsername: s.username,
                    seedDisplayName: s.displayName,
                    seedAvatarPreset: s.avatarPreset,
                    seedAvatarUrl: s.avatarUrl,
                  ),
                )),
                corner: _cornerStamp(
                  onTap: () => _sendRequest(s.username),
                  icon: Icons.add,
                  bg: SeenlyPalette.accent,
                  fg: SeenlyPalette.accentOnAccent,
                  busy: _busy.contains(s.username),
                ),
              ));
        }).toList()),
      ],
    ];
  }
}

/// The original polaroid, brought back: a real photo-sized card — tape,
/// tilt, a stamped button in the corner — just stacked one under another
/// instead of side by side, and the photo itself is always the avatar
/// (scaled up to fill the frame), never a poster.
class _PolaroidCard extends StatelessWidget {
  final String? avatarUrl;
  final String? avatarPreset;
  final String fallbackLetter;
  final int index;
  final String title;
  final String subtitle;
  final Widget corner;
  final Widget? secondaryCorner;
  final VoidCallback? onTap;
  final double cardWidth;

  const _PolaroidCard({
    required this.avatarUrl,
    required this.avatarPreset,
    required this.fallbackLetter,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.corner,
    this.secondaryCorner,
    this.onTap,
    this.cardWidth = 164,
  });

  static const _tapeColors = [SeenlyPalette.tapeRose, SeenlyPalette.tapeSage, SeenlyPalette.tapeMustard];
  // Original photo was 148x168 inside a 164-wide card (16px of horizontal
  // padding either side of it). Kept as a ratio so the two-up grid can
  // hand this card whatever width fits the screen and the photo scales
  // with it instead of overflowing or leaving gaps.
  static const double _photoAspect = 168 / 148;

  @override
  Widget build(BuildContext context) {
    final tapeColor = _tapeColors[index % _tapeColors.length];
    final tint = SeenlyPalette.gridColorFor(index);
    final angle = (index.isEven ? -1 : 1) * 0.03;
    final photoWidth = cardWidth - 16;
    final photoHeight = photoWidth * _photoAspect;

    final card = Container(
      width: cardWidth,
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 11),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: SeenlyPalette.ink.withOpacity(0.13), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // washi tape pinning the photo down
          Positioned(
            top: -13,
            left: (cardWidth - 48) / 2,
            child: Transform.rotate(
              angle: -0.09,
              child: Container(width: 48, height: 17, color: tapeColor.withOpacity(0.85)),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _BigAvatarPhoto(
                      avatarUrl: avatarUrl,
                      avatarPreset: avatarPreset,
                      fallbackLetter: fallbackLetter,
                      tint: tint,
                      width: photoWidth,
                      height: photoHeight,
                    ),
                  ),
                  Positioned(top: -8, right: -8, child: corner),
                  if (secondaryCorner != null) Positioned(top: -8, left: -8, child: secondaryCorner!),
                ],
              ),
              const SizedBox(height: 19),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
            ],
          ),
        ],
      ),
    );

    final rotated = Transform.rotate(angle: angle, child: card);
    if (onTap == null) return rotated;
    return PressScale(onTap: onTap, child: rotated);
  }
}

/// Draws whichever avatar state the person is in — uploaded photo,
/// bundled preset, or a plain fallback letter — the same three cases
/// [UserAvatar] handles, but as a big rectangular fill instead of a
/// small clipped circle, since here the avatar *is* the polaroid photo.
class _BigAvatarPhoto extends StatelessWidget {
  final String? avatarUrl;
  final String? avatarPreset;
  final String fallbackLetter;
  final Color tint;
  final double width;
  final double height;

  const _BigAvatarPhoto({
    required this.avatarUrl,
    required this.avatarPreset,
    required this.fallbackLetter,
    required this.tint,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      final resolved = avatarUrl!.startsWith('http')
          ? Future.value(avatarUrl!)
          : context.read<AppState>().client.resolveBaseUrl().then((base) => '$base$avatarUrl');
      return SizedBox(
        width: width,
        height: height,
        child: FutureBuilder<String>(
          future: resolved,
          builder: (context, snap) {
            if (!snap.hasData) return Container(color: tint.withOpacity(0.2));
            return Image.network(
              snap.data!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _letterBlock(),
            );
          },
        ),
      );
    }
    if (avatarPreset != null) {
      final preset = kAvatarPresets.where((p) => p.id == avatarPreset).toList();
      if (preset.isNotEmpty) {
        return Image.asset(preset.first.assetPath, width: width, height: height, fit: BoxFit.cover);
      }
    }
    return _letterBlock();
  }

  Widget _letterBlock() => Container(
        width: width,
        height: height,
        color: tint.withOpacity(0.22),
        alignment: Alignment.center,
        child: Text(fallbackLetter, style: SeenlyText.serif(size: height * 0.3, weight: FontWeight.w700, color: tint)),
      );
}

/// The button stamped onto a polaroid's corner — add, cancel, accept,
/// decline — or a small spinner in the same footprint while busy.
Widget _cornerStamp({required VoidCallback? onTap, required IconData icon, required Color bg, required Color fg, bool busy = false}) {
  if (busy) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle, border: Border.all(color: SeenlyPalette.paper, width: 2)),
      alignment: Alignment.center,
      child: const SizedBox(width: 12, height: 12, child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent)),
    );
  }
  return PressScale(
    onTap: onTap,
    haptics: true,
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: SeenlyPalette.paper, width: 2),
        boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.2), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 14, color: fg),
    ),
  );
}

class _InviteRow extends StatelessWidget {
  final VoidCallback onTap;
  const _InviteRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: SeenlyPalette.accent.withOpacity(0.14), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.person_add_alt_1_rounded, size: 15, color: SeenlyPalette.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('invite friends'.tr, style: SeenlyText.serif(size: 13, weight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text('not on teamira yet? send them your code'.tr,
                      style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  final FriendSearchResult result;
  final bool busy;
  final VoidCallback onAdd;
  const _SearchResultRow({required this.result, required this.busy, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          UserAvatar(
            avatarUrl: result.avatarUrl,
            avatarPreset: result.avatarPreset,
            fallbackLetter: result.username.isNotEmpty ? result.username[0].toUpperCase() : '?',
            size: 34,
            borderColor: Colors.transparent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(result.nameForDisplay, style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600)),
          ),
          if (busy)
            const SizedBox(
                width: 16, height: 16, child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent))
          else
            _statusPill(),
        ],
      ),
    );
  }

  Widget _statusPill() {
    switch (result.status) {
      case 'friends':
        return Text('friends'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint));
      case 'pending_outgoing':
        return Text('requested'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint));
      case 'pending_incoming':
        return Text('respond above'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint));
      default:
        return PressScale(
          onTap: onAdd,
          haptics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
            decoration: BoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(16)),
            child: Text('add'.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.accentOnAccent, weight: FontWeight.w700)),
          ),
        );
    }
  }
}

