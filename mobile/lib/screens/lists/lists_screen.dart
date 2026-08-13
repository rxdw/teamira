import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_list.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import 'list_detail_screen.dart';
import '../../widgets/themed_loading_indicator.dart';

/// Profile → "your lists": the user's own made-up collections, distinct
/// from the editorial shelves on the Collections tab. "Cozy rainy-day
/// picks", "games to play with my brother" — whatever grouping makes
/// sense to them, not to TMDB/IGDB.
class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  late Future<List<UserList>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().lists.all();
  }

  Future<void> _refresh() async {
    setState(() => _future = context.read<AppState>().lists.all());
    await _future;
  }

  Future<void> _createList() async {
    final result = await showModalBottomSheet<_NewListResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _NewListSheet(),
    );
    if (result == null || !mounted) return;
    try {
      final created =
          await context.read<AppState>().lists.create(name: result.name);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ListDetailScreen(listId: created.id)),
      );
      _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't create that list — try again")),
      );
    }
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
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text('your lists', style: SeenlyText.screenTitle)),
                  IconButton(
                    icon: const Icon(Icons.add, size: 22, color: SeenlyPalette.accent),
                    onPressed: _createList,
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<UserList>>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return const Center(child: ThemedLoadingIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text("couldn't load your lists",
                          style: SeenlyText.serif(
                              italic: true, color: SeenlyPalette.inkMuted)),
                    );
                  }
                  final lists = snapshot.data!;
                  if (lists.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: SeenlyPalette.accent,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
                        children: [
                          Text('no lists yet',
                              textAlign: TextAlign.center,
                              style: SeenlyText.serif(italic: true, size: 15)),
                          const SizedBox(height: 8),
                          Text(
                            'group whatever you like together — a mood, a marathon, favorites you keep coming back to',
                            textAlign: TextAlign.center,
                            style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder),
                          ),
                          const SizedBox(height: 20),
                          PrimaryButton(label: 'new list', onTap: _createList),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: SeenlyPalette.accent,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                      itemCount: lists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _ListRow(
                        list: lists[i],
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => ListDetailScreen(listId: lists[i].id)),
                          );
                          _refresh();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  final UserList list;
  final VoidCallback onTap;
  const _ListRow({required this.list, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _Collage(posters: list.previewPosters),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.cardTitle),
                  const SizedBox(height: 4),
                  Text(
                    list.itemCount == 1 ? '1 title' : '${list.itemCount} titles',
                    style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _Collage extends StatelessWidget {
  final List<String> posters;
  const _Collage({required this.posters});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 52,
        child: posters.isEmpty
            ? Container(color: SeenlyPalette.background)
            : GridView.count(
                crossAxisCount: 2,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 1,
                crossAxisSpacing: 1,
                children: [
                  for (var i = 0; i < 4; i++)
                    i < posters.length
                        ? Image.network(posters[i], fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: SeenlyPalette.background))
                        : Container(color: SeenlyPalette.background),
                ],
              ),
      ),
    );
  }
}

class _NewListResult {
  final String name;
  const _NewListResult(this.name);
}

class _NewListSheet extends StatefulWidget {
  const _NewListSheet();

  @override
  State<_NewListSheet> createState() => _NewListSheetState();
}

class _NewListSheetState extends State<_NewListSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(_NewListResult(name));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('new list',
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 16)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: SeenlyPalette.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _submit(),
                style: SeenlyText.serif(size: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'cozy rainy-day picks…',
                  hintStyle: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder),
                ),
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(label: 'create', onTap: _submit),
          ],
        ),
      ),
    );
  }
}
