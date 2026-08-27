import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../models/profile_stats.dart';
import '../../models/watchlist_entry.dart';
import '../../services/premium_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/heart_burst.dart';
import '../../widgets/premium_upsell_sheet.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../services/app_translations.dart';

enum _AddTab { search, watched, planned, watching }

extension on _AddTab {
  String get label {
    switch (this) {
      case _AddTab.search:
        return 'search'.tr;
      case _AddTab.watched:
        return 'watched'.tr;
      case _AddTab.planned:
        return 'plan to watch'.tr;
      case _AddTab.watching:
        return 'watching now'.tr;
    }
  }
}

/// Opens from the "add" button on [FavoriteFilmsScreen] (own profile
/// only). Two ways in to pin a favorite: type-ahead search across all of
/// teamira's catalog, or just tap a film already sitting on one of the
/// three shelves. Either path calls the same
/// ProfileService.toggleFavorite that the title screen's own heart
/// button uses — a title picked here doesn't need to already be on a
/// shelf; toggling it on creates one at `watch_later` the same way
/// favoriting straight from a title page does (see
/// routers/profile.py::toggle_favorite).
///
/// Movies only, same restriction as the rest of the favorites feature
/// (see routers/friends.py::get_friend_profile's own favorite_entries
/// filter) — series get their own "watching now" progress instead of a
/// favorites pin.
class FavoriteAddScreen extends StatefulWidget {
  final ProfileCollections collections;

  const FavoriteAddScreen({super.key, required this.collections});

  @override
  State<FavoriteAddScreen> createState() => _FavoriteAddScreenState();
}

class _FavoriteAddScreenState extends State<FavoriteAddScreen> {
  _AddTab _tab = _AddTab.search;
  bool _changed = false;

  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<MediaItem> _results = const [];
  String _lastQuery = '';

  // Local overrides so a toggle reflects instantly without waiting on
  // the next full collections fetch — keyed by "source:mediaId".
  final Map<String, bool> _overrides = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _key(String source, String mediaId) => '$source:$mediaId';

  bool _isFavorite(String source, String mediaId, bool serverValue) =>
      _overrides[_key(source, mediaId)] ?? serverValue;

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
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final found = await context.read<AppState>().media.search(
            trimmed,
            includeGames: false,
            includeBooks: false,
            includeManga: false,
          );
      if (!mounted || trimmed != _lastQuery) return;
      setState(() {
        _results = found.where((m) => m.mediaType == 'movie').toList();
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _toggleMedia(MediaItem item, bool nextValue) async {
    // Free tier: 5 favorite films (see PremiumService) — only checked
    // when turning a favorite ON, so removing one is never blocked.
    if (nextValue && !context.read<PremiumService>().canAddFavorite) {
      showPremiumUpsellSheet(
        context,
        icon: Icons.favorite_outline,
        title: 'достигнут лимит избранного',
        message: 'на бесплатном тарифе можно сохранить до 5 любимых фильмов — с премиумом лимита нет',
      );
      return;
    }
    setState(() => _overrides[_key(item.source, item.id)] = nextValue);
    try {
      final confirmed = await context.read<AppState>().profile.toggleFavorite(item, nextValue);
      if (!mounted) return;
      setState(() {
        _overrides[_key(item.source, item.id)] = confirmed;
        _changed = true;
      });
      if (confirmed) {
        context.read<PremiumService>().noteFavoriteAdded();
      } else {
        context.read<PremiumService>().noteFavoriteRemoved();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _overrides[_key(item.source, item.id)] = !nextValue);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("that didn't save — try again".tr)));
    }
  }

  List<WatchlistEntry> get _shelfEntries {
    switch (_tab) {
      case _AddTab.watched:
        return widget.collections.watched.where((e) => e.mediaType == 'movie').toList();
      case _AddTab.planned:
        return widget.collections.watchLater.where((e) => e.mediaType == 'movie').toList();
      case _AddTab.watching:
        return widget.collections.watching.where((e) => e.mediaType == 'movie').toList();
      case _AddTab.search:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
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
                      icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                      onPressed: () => Navigator.of(context).pop(_changed),
                    ),
                    Expanded(
                      child: Text('add a favorite'.tr,
                          style: SeenlyText.screenTitle, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _AddTab.values
                        .map((t) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _TabChip(
                                label: t.label,
                                selected: _tab == t,
                                onTap: () => setState(() => _tab = t),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_tab == _AddTab.search)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: SeenlyText.serif(size: 14, color: SeenlyPalette.ink),
                    decoration: InputDecoration(
                      hintText: 'search movies…'.tr,
                      hintStyle: SeenlyText.serif(size: 14, color: SeenlyPalette.placeholder),
                      prefixIcon: Icon(Icons.search, size: 18, color: SeenlyPalette.inkMuted),
                      filled: true,
                      fillColor: SeenlyPalette.paper,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: SeenlyPalette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: SeenlyPalette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: SeenlyPalette.accent),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_tab == _AddTab.search) {
      if (_searching) {
        return const Center(child: ThemedLoadingIndicator());
      }
      if (_searchController.text.trim().isEmpty) {
        return _emptyMessage('type a movie title to search');
      }
      if (_results.isEmpty) {
        return _emptyMessage('no movies found');
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: _results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final item = _results[i];
          final fav = _isFavorite(item.source, item.id, false);
          return _MediaRow(
            title: item.title.display,
            posterUrl: item.posterUrl,
            subtitle: item.year?.toString(),
            isFavorite: fav,
            onToggle: () => _toggleMedia(item, !fav),
          );
        },
      );
    }

    final entries = _shelfEntries;
    if (entries.isEmpty) {
      return _emptyMessage('nothing here yet');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final e = entries[i];
        final fav = _isFavorite(e.source, e.mediaId, e.isFavorite);
        return _MediaRow(
          title: e.displayTitle,
          posterUrl: e.posterUrl,
          subtitle: e.year?.toString(),
          isFavorite: fav,
          onToggle: () => _toggleMedia(MediaItem.fromWatchlistEntry(e), !fav),
        );
      },
    );
  }

  Widget _emptyMessage(String text) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
        children: [
          Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(italic: true, color: SeenlyPalette.placeholder),
            ),
          ),
        ],
      );
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? SeenlyPalette.accent : SeenlyPalette.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: SeenlyText.mono(
            size: 11,
            color: selected ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  final String title;
  final String? posterUrl;
  final String? subtitle;
  final bool isFavorite;
  final VoidCallback onToggle;

  const _MediaRow({
    required this.title,
    required this.posterUrl,
    required this.subtitle,
    required this.isFavorite,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 42,
              height: 63,
              child: (posterUrl != null && posterUrl!.isNotEmpty)
                  ? Image.network(posterUrl!, fit: BoxFit.cover)
                  : Container(color: SeenlyPalette.border),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: SeenlyText.serif(size: 13.5, color: SeenlyPalette.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkMuted)),
                ],
              ],
            ),
          ),
          HeartBurst(
            isFavorite: isFavorite,
            child: IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? SeenlyPalette.pink : SeenlyPalette.inkMuted,
              ),
              onPressed: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}
