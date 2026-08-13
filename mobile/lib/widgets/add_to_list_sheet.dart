import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/user_list.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';
import '../widgets/themed_loading_indicator.dart';

/// Opened from the title screen's "add to list" button. Shows every list
/// the user has, checked if this title is already in it; tapping toggles
/// membership immediately (no separate "save" step). A "new list" row at
/// the bottom skips straight to creating one with this title already in it.
Future<void> showAddToListSheet(BuildContext context, MediaItem item) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _AddToListSheet(item: item),
  );
}

class _AddToListSheet extends StatefulWidget {
  final MediaItem item;
  const _AddToListSheet({required this.item});

  @override
  State<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends State<_AddToListSheet> {
  List<UserList>? _lists;
  Set<String> _memberOf = {};
  final Set<String> _pending = {};
  bool _loading = true;
  bool _creatingNew = false;
  final _newListController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newListController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final results = await Future.wait([
        app.lists.all(),
        app.lists.membership(mediaId: widget.item.id, source: widget.item.source),
      ]);
      if (!mounted) return;
      setState(() {
        _lists = results[0] as List<UserList>;
        _memberOf = results[1] as Set<String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(UserList list) async {
    final app = context.read<AppState>();
    final isMember = _memberOf.contains(list.id);
    setState(() => _pending.add(list.id));
    try {
      if (isMember) {
        final detail = await app.lists.detail(list.id);
        final match = detail.items.where(
          (it) => it.mediaId == widget.item.id && it.source == widget.item.source,
        );
        if (match.isNotEmpty) {
          await app.lists.removeItem(list.id, match.first.id);
        }
        if (!mounted) return;
        setState(() => _memberOf.remove(list.id));
      } else {
        await app.lists.addItem(list.id, widget.item);
        if (!mounted) return;
        setState(() => _memberOf.add(list.id));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't update that list — try again")),
      );
    } finally {
      if (mounted) setState(() => _pending.remove(list.id));
    }
  }

  Future<void> _createAndAdd() async {
    final name = _newListController.text.trim();
    if (name.isEmpty) return;
    final app = context.read<AppState>();
    setState(() => _loading = true);
    try {
      final created = await app.lists.create(name: name);
      await app.lists.addItem(created.id, widget.item);
      if (!mounted) return;
      setState(() {
        _lists = [created, ...?_lists];
        _memberOf.add(created.id);
        _creatingNew = false;
        _loading = false;
        _newListController.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't create that list — try again")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('add to a list',
                style: SeenlyText.serif(italic: true, size: 16)),
            const SizedBox(height: 4),
            Text(widget.item.title.display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: SizedBox(
                    width: 20, height: 20,
                    child: ThemedLoadingIndicator(
                        strokeWidth: 2, color: SeenlyPalette.accent),
                  ),
                ),
              )
            else ...[
              if (_lists != null && _lists!.isNotEmpty)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _lists!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final list = _lists![i];
                      final checked = _memberOf.contains(list.id);
                      final busy = _pending.contains(list.id);
                      return GestureDetector(
                        onTap: busy ? null : () => _toggle(list),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                checked ? Icons.check_circle : Icons.circle_outlined,
                                size: 18,
                                color: checked
                                    ? SeenlyPalette.accent
                                    : SeenlyPalette.dashedBorder,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(list.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SeenlyText.serif(size: 13)),
                              ),
                              if (busy)
                                const SizedBox(
                                  width: 14, height: 14,
                                  child: ThemedLoadingIndicator(
                                      strokeWidth: 2, color: SeenlyPalette.accent),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              if (_creatingNew)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: SeenlyPalette.background,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TextField(
                          controller: _newListController,
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _createAndAdd(),
                          style: SeenlyText.serif(size: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'list name…',
                            hintStyle: SeenlyText.mono(
                                size: 11, color: SeenlyPalette.placeholder),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _createAndAdd,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: SeenlyPalette.accent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.check,
                            size: 18, color: SeenlyPalette.accentOnAccent),
                      ),
                    ),
                  ],
                )
              else
                GestureDetector(
                  onTap: () => setState(() => _creatingNew = true),
                  child: Row(
                    children: [
                      const Icon(Icons.add, size: 16, color: SeenlyPalette.accent),
                      const SizedBox(width: 8),
                      Text('new list',
                          style: SeenlyText.serif(
                              italic: true, size: 13, color: SeenlyPalette.accent)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
