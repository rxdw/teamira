import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../models/profile_stats.dart';
import '../../models/watchlist_entry.dart';
import '../../services/api_client.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/watched_preview_sheet.dart';
import 'favorite_add_screen.dart';

/// Every favorite film on one account's profile — reached from the
/// "favorite" row on the profile screen (see FavoritesShowcaseRow in
/// profile_screen.dart) and from the same spot on another account's
/// profile (FriendProfileScreen).
///
/// [userId] null means "the signed-in account's own favorites" — editable,
/// with an "add" button that opens [FavoriteAddScreen]. A non-null
/// [userId] means someone else's, fetched through the same
/// GET /friends/{user_id}/profile call the friend-profile screen uses
/// (see FriendsService.friendProfile) and filtered server-side by that
/// account's own privacy_favorites setting — read-only, no add button,
/// and a quiet "keeps this private" message instead of an empty deck
/// when they've dialed it down (same "hidden vs merely empty" rule as
/// every other shelf — see FriendCollections' own docstring).
class FavoriteFilmsScreen extends StatefulWidget {
  final String? userId;
  final String? seedDisplayName;
  final String? seedUsername;
  final String? seedAvatarPreset;
  final String? seedAvatarUrl;

  const FavoriteFilmsScreen({
    super.key,
    this.userId,
    this.seedDisplayName,
    this.seedUsername,
    this.seedAvatarPreset,
    this.seedAvatarUrl,
  });

  bool get isOwn => userId == null;

  @override
  State<FavoriteFilmsScreen> createState() => _FavoriteFilmsScreenState();
}

class _FavoriteFilmsScreenState extends State<FavoriteFilmsScreen> {
  bool _loading = true;
  bool _failed = false;

  // Own-profile path.
  ProfileCollections? _collections;
  ProfileMe? _me;
  // Other-account path.
  FriendProfile? _friendData;

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
      if (widget.isOwn) {
        final app = context.read<AppState>();
        final results = await Future.wait([app.profile.collections(), app.profile.me()]);
        if (!mounted) return;
        setState(() {
          _collections = results[0] as ProfileCollections;
          _me = results[1] as ProfileMe;
          _loading = false;
        });
      } else {
        final data = await context.read<AppState>().friends.friendProfile(widget.userId!);
        if (!mounted) return;
        setState(() {
          _friendData = data;
          _loading = false;
        });
      }
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

  String _key(String source, String mediaId) => '$source:$mediaId';

  // The account's own ordered stories deck among their favorites — see
  // ProfileMe.topFavoritePicks's own docstring. Own-profile only;
  // FriendCollections carries the same idea for someone else's, shown
  // read-only via _FavoritesList.topKeys below. Index in this list is
  // the deck order (1-based when shown as a badge).
  List<String> get _ownTopKeys =>
      (_me?.topFavoritePicks ?? const []).map((p) => p.key).toList();

  static const int _maxTopPicks = 5;

  Future<void> _setTop(WatchlistEntry e) async {
    final key = _key(e.source, e.mediaId);
    final current = _ownTopKeys;
    List<FavoritePick> updatedPicks;
    if (current.contains(key)) {
      updatedPicks = (_me?.topFavoritePicks ?? const [])
          .where((p) => p.key != key)
          .toList();
    } else {
      if (current.length >= _maxTopPicks) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('можно выбрать не больше 5')),
        );
        return;
      }
      updatedPicks = [
        ...(_me?.topFavoritePicks ?? const []),
        FavoritePick(mediaId: e.mediaId, source: e.source),
      ];
    }
    try {
      final updated = await context.read<AppState>().profile.setTopFavorites(updatedPicks);
      if (!mounted) return;
      setState(() => _me = updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("that didn't save — try again")));
    }
  }

  // Favorite films are a status-independent flag (see
  // WatchlistEntry.is_favorite's own docstring) — someone can pin a movie
  // they've only planned or are mid-way through, not only ones already
  // watched, so this looks across all three shelves rather than just
  // `watched`. Restricted to movies, same as the backend's own
  // get_friend_profile filter and the "favorite films" row on Profile —
  // series get their own "watching now" progress, not a favorites pin.
  List<WatchlistEntry> get _ownFavorites {
    final c = _collections;
    if (c == null) return const [];
    return [...c.watchLater, ...c.watching, ...c.watched]
        .where((e) => e.isFavorite && e.mediaType == 'movie')
        .toList();
  }

  String get _title => widget.isOwn
      ? 'favorite'
      : (_friendData?.nameForDisplay ??
              (widget.seedDisplayName?.trim().isNotEmpty == true
                  ? widget.seedDisplayName!
                  : widget.seedUsername) ??
              '') +
          "'s favorites";

  Future<void> _openAdd() async {
    final collections = _collections;
    if (collections == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FavoriteAddScreen(collections: collections)),
    );
    if (changed == true) _load();
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
              padding: const EdgeInsets.fromLTRB(10, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  if (!widget.isOwn) ...[
                    UserAvatar(
                      avatarUrl: _friendData?.avatarUrl ?? widget.seedAvatarUrl,
                      avatarPreset: _friendData?.avatarPreset ?? widget.seedAvatarPreset,
                      fallbackLetter: _title.isNotEmpty ? _title.substring(0, 1).toLowerCase() : '?',
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(_title, style: SeenlyText.screenTitle, overflow: TextOverflow.ellipsis),
                  ),
                  if (widget.isOwn && _collections != null)
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 21, color: SeenlyPalette.accent),
                      tooltip: 'add a favorite',
                      onPressed: _openAdd,
                    ),
                ],
              ),
            ),
            if (widget.isOwn && !_loading && !_failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  _ownFavorites.isEmpty
                      ? ''
                      : (_ownTopKeys.isEmpty
                          ? 'tap the star on up to 5 to build your profile banner'
                          : 'tap a star to add or remove it from your profile banner'),
                  style: SeenlyText.serif(size: 11.5, italic: true, color: SeenlyPalette.inkMuted),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: ThemedLoadingIndicator())
                  : _failed
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("couldn't load favorites",
                                    textAlign: TextAlign.center,
                                    style: SeenlyText.serif(italic: true, color: SeenlyPalette.inkMuted)),
                                const SizedBox(height: 10),
                                GestureDetector(
                                  onTap: _load,
                                  child: Text('tap to try again',
                                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: SeenlyPalette.accent,
                          child: _buildBody(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.isOwn) {
      return _FavoritesList(
        entries: _ownFavorites,
        visible: true,
        emptyLabel: "nothing pinned yet — tap add, or the heart on a film's page",
        privateLabel: '',
        onTapEntry: (e) => showWatchedPreview(context, WatchedPreviewData.fromWatchlistEntry(e)),
        topKeys: _ownTopKeys,
        onSetTop: _setTop,
      );
    }
    final data = _friendData;
    if (data == null) {
      return const SizedBox.shrink();
    }
    final name = data.nameForDisplay;
    final topKeys = data.collections.topFavoritePicks.map((p) => p.key).toList();
    return _FavoritesList(
      entries: data.collections.favorites,
      visible: data.collections.favoritesVisible,
      emptyLabel: '$name hasn\'t pinned any favorite films yet',
      privateLabel: '$name keeps their favorites private',
      onTapEntry: (e) => showWatchedPreview(
        context,
        WatchedPreviewData.fromFriendEntry(e, friendLabel: "$name's favorites"),
      ),
      topKeys: topKeys,
    );
  }
}

/// A vertical, one-per-row list of the account's favorite films —
/// replaces the old dense 3-column grid. Each row is a wide poster+
/// detail card rather than a bare thumbnail, and softly fades/slides
/// upward into place the first time it scrolls into view (see
/// _StaggeredEntry below), so scrolling down the list feels like each
/// card is settling into place rather than just appearing. Cards carry
/// a bit more than a poster+heart: title, year/genre, and — when the
/// account rated it — their own 1-5 heart score, so the person's own
/// hand is visible on each pick, not just the film's.
///
/// Same own-vs-friend split as before: [onSetTop] is only supplied on
/// the signed-in account's own list (see FavoriteFilmsScreen's own
/// docstring) — that's what turns the star from a static "this is the
/// pick" marker into a tappable one.
class _FavoritesList extends StatelessWidget {
  final List<WatchlistEntry> entries;
  final bool visible;
  final String emptyLabel;
  final String privateLabel;
  final ValueChanged<WatchlistEntry> onTapEntry;
  // "source:mediaId" keys of the picks currently in the stories deck —
  // see ProfileMe.topFavoritePicks. onSetTop null (friend's read-only
  // list) means the star only ever appears, static, on already-picked
  // cards — see _FavoriteListCard.
  final List<String> topKeys;
  final ValueChanged<WatchlistEntry>? onSetTop;

  const _FavoritesList({
    required this.entries,
    required this.visible,
    required this.emptyLabel,
    required this.privateLabel,
    required this.onTapEntry,
    this.topKeys = const [],
    this.onSetTop,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return _centeredMessage(privateLabel, color: SeenlyPalette.inkMuted);
    }
    if (entries.isEmpty) {
      return _centeredMessage(emptyLabel, color: SeenlyPalette.placeholder);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final key = '${e.source}:${e.mediaId}';
        final topIndex = topKeys.indexOf(key);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _StaggeredEntry(
            index: i,
            child: _FavoriteListCard(
              entry: e,
              index: i,
              isTop: topIndex != -1,
              topOrder: topIndex == -1 ? null : topIndex + 1,
              onTap: () => onTapEntry(e),
              onSetTop: onSetTop == null ? null : () => onSetTop!(e),
            ),
          ),
        );
      },
    );
  }

  Widget _centeredMessage(String text, {required Color color}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
      children: [
        Center(
          child: Text(text, textAlign: TextAlign.center, style: SeenlyText.serif(italic: true, size: 13, color: color)),
        ),
      ],
    );
  }
}

/// Fades + slides its child up into place once, the first time it's
/// built — which, inside a lazy ListView.builder, means the first time
/// it actually scrolls into view. A short, index-based stagger (capped
/// so a long list doesn't leave the last few cards waiting) is what
/// turns a plain "ListView.builder" into something that reads as
/// composed rather than dumped on screen.
class _StaggeredEntry extends StatefulWidget {
  final int index;
  final Widget child;
  const _StaggeredEntry({required this.index, required this.child});

  @override
  State<_StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<_StaggeredEntry> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    final delayMs = (widget.index * 55).clamp(0, 300);
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// One row in [_FavoritesList] — a portrait poster on the left, a paper
/// detail panel on the right carrying the title, year/genre, and (when
/// set) the account's own 1-5 heart rating, with the star/heart
/// controls tucked into the panel's own top corner rather than
/// overlaid on the poster (too narrow here to hold them legibly).
/// [isTop] adds a gold ring around the whole card, a matching glow in
/// its shadow, and a small "top pick" line, so the one pick that
/// matters most reads as clearly a level above the rest, not just
/// another row in the list.
class _FavoriteListCard extends StatelessWidget {
  final WatchlistEntry entry;
  final int index;
  final bool isTop;
  final int? topOrder;
  final VoidCallback onTap;
  final VoidCallback? onSetTop;

  const _FavoriteListCard({
    required this.entry,
    required this.index,
    required this.isTop,
    this.topOrder,
    required this.onTap,
    this.onSetTop,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = SeenlyPalette.gridColorFor(index);
    final meta = [
      if (entry.year != null) '${entry.year}',
      if (entry.genres.isNotEmpty) entry.genres.first,
    ].join(' · ');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: isTop ? Border.all(color: SeenlyPalette.mustard, width: 2.5) : null,
          boxShadow: [
            BoxShadow(
              color: (isTop ? SeenlyPalette.mustard : SeenlyPalette.ink)
                  .withOpacity(isTop ? 0.26 : 0.08),
              blurRadius: isTop ? 20 : 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 138,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 96,
                  child: (entry.posterUrl != null && entry.posterUrl!.isNotEmpty)
                      ? Image.network(
                          entry.posterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _PosterFallback(color: fallback, title: entry.displayTitle),
                          loadingBuilder: (context, child, progress) =>
                              progress == null ? child : _PosterFallback(color: fallback, title: entry.displayTitle),
                        )
                      : _PosterFallback(color: fallback, title: entry.displayTitle),
                ),
                Expanded(
                  child: Container(
                    color: SeenlyPalette.paper,
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                entry.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: SeenlyText.serif(size: 15, weight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.favorite, size: 14, color: SeenlyPalette.pink),
                            if (isTop || onSetTop != null) ...[
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: onSetTop,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: isTop ? SeenlyPalette.mustard : SeenlyPalette.border,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isTop ? Icons.star : Icons.star_border,
                                    size: 13,
                                    color: isTop ? Colors.white : SeenlyPalette.inkMuted,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(meta, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                        ],
                        const Spacer(),
                        if (entry.userRating != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int h = 0; h < 5; h++) ...[
                                if (h > 0) const SizedBox(width: 2),
                                Icon(
                                  h < entry.userRating! ? Icons.favorite : Icons.favorite_border,
                                  size: 11,
                                  color: SeenlyPalette.pink,
                                ),
                              ],
                            ],
                          ),
                        if (isTop) ...[
                          if (entry.userRating != null) const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 11, color: SeenlyPalette.mustard),
                              const SizedBox(width: 4),
                              Text(
                                topOrder == null ? 'in banner' : 'banner · #$topOrder',
                                style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.mustard, weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain-color placeholder for a poster that hasn't loaded (or doesn't
/// have one) — the title centered on the fallback color, same idea as
/// ThemedPosterTile's own fallback fill but sized for this card's row.
class _PosterFallback extends StatelessWidget {
  final Color color;
  final String title;
  const _PosterFallback({required this.color, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: SeenlyText.serif(size: 11, weight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}
