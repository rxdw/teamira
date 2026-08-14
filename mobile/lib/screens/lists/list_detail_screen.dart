import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_list.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/themed_poster_tile.dart';
import '../title/title_detail_screen.dart';
import '../../widgets/scroll_reveal.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart' show Entrance, PressScale;

class ListDetailScreen extends StatefulWidget {
  final String listId;
  const ListDetailScreen({super.key, required this.listId});

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  late Future<UserListDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().lists.detail(widget.listId);
  }

  Future<void> _removeItem(UserListItem item) async {
    setState(() => _busy = true);
    try {
      final updated =
          await context.read<AppState>().lists.removeItem(widget.listId, item.id);
      if (!mounted) return;
      setState(() {
        _future = Future.value(updated);
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't remove that — try again")),
      );
    }
  }

  Future<void> _confirmDeleteList(UserListDetail list) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Entrance(
              child: Text('delete "${list.name}"?',
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(italic: true, size: 16)),
            ),
            const SizedBox(height: 6),
            Entrance(
              delay: const Duration(milliseconds: 50),
              child: Text(
                'the titles themselves stay in your diary — only the list goes away',
                textAlign: TextAlign.center,
                style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
              ),
            ),
            const SizedBox(height: 20),
            Entrance(
              delay: const Duration(milliseconds: 100),
              riseBy: 14,
              child: PressScale(
                onTap: () => Navigator.of(context).pop(true),
                haptics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.coral,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Text('delete',
                      style: SeenlyText.serif(
                          italic: true, color: SeenlyPalette.accentOnAccent)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            PressScale(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                child: Text('keep it',
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AppState>().lists.delete(widget.listId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't delete that list — try again")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: FutureBuilder<UserListDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) {
              return const Center(child: ThemedLoadingIndicator());
            }
            if (snapshot.hasError) {
              return Column(
                children: [
                  _Header(title: '', onBack: () => Navigator.of(context).pop()),
                  Expanded(
                    child: Center(
                      child: Text("couldn't load this list",
                          style: SeenlyText.serif(
                              italic: true, color: SeenlyPalette.inkMuted)),
                    ),
                  ),
                ],
              );
            }
            final list = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  title: list.name,
                  onBack: () => Navigator.of(context).pop(),
                  onDelete: () => _confirmDeleteList(list),
                ),
                if (list.description != null && list.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                    child: Text(list.description!,
                        style: SeenlyText.serif(
                            italic: true, size: 12, color: SeenlyPalette.inkFaint)),
                  ),
                Expanded(
                  child: list.items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Entrance(
                              child: Text(
                                'empty for now — add titles here from any title\'s page',
                                textAlign: TextAlign.center,
                                style: SeenlyText.serif(
                                    italic: true, color: SeenlyPalette.placeholder),
                              ),
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.6,
                          ),
                          itemCount: list.items.length,
                          itemBuilder: (context, i) {
                            final item = list.items[i];
                            return ScrollRevealEntrance(
                              index: i,
                              child: _ListItemTile(
                                item: item,
                                busy: _busy,
                                onRemove: () => _removeItem(item),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TitleDetailScreen(
                                      mediaId: item.mediaId,
                                      source: item.source,
                                      mediaType: item.mediaType,
                                      seedTitle: item.displayTitle,
                                      seedPosterUrl: item.posterUrl,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback? onDelete;
  const _Header({required this.title, required this.onBack, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: [
          PressScale(
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.screenTitle),
          ),
          if (onDelete != null)
            PressScale(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.delete_outline, size: 19, color: SeenlyPalette.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

class _ListItemTile extends StatelessWidget {
  final UserListItem item;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ListItemTile({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ThemedPosterTile(
                    title: item.displayTitle,
                    posterUrl: item.posterUrl,
                    fallbackColor: SeenlyPalette.mediaColor(item.mediaType),
                    mediaType: item.mediaType,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: PressScale(
                    onTap: busy ? null : onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(item.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkMuted)),
        ],
      ),
    );
  }
}
