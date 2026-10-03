import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_list.dart';
import '../../services/locale_service.dart';
import '../../services/premium_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../premium/premium_screen.dart';
import '../../widgets/premium_upsell_sheet.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/soft_limit_meter.dart';
import '../together/together_screen.dart' show kTogetherListName;
import 'list_detail_screen.dart';
import '../../widgets/scroll_reveal.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart' show Entrance, FadeInNetworkImage, PressScale;
import '../../services/app_translations.dart';
import '../../theme/clay_kit.dart';

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

  /// Free accounts keep up to [PremiumService.freeListsLimit] custom
  /// lists; premium removes the cap entirely — same "count what's
  /// already there, gate right before creating" shape as
  /// PremiumService.canAddFavorite. Reads off whatever [_future]'s
  /// already resolved to rather than a fresh fetch, since the screen
  /// showing this button already has the current count on screen.
  ///
  /// The auto-created "watch together" list (see kTogetherListName,
  /// together_screen.dart) doesn't count toward the limit — nobody
  /// spent a slot choosing to make it, the app made it for them the
  /// first time they matched on something. Matched by name, same as
  /// together_screen.dart's own lookup for it — if it's ever renamed
  /// it just quietly starts counting like any other list rather than
  /// breaking anything.
  Future<void> _createList() async {
    // Fails open on a bad count (network hiccup, etc.) — better to let
    // someone through than to block list creation over a failed check
    // that has nothing to do with the thing they're actually trying to
    // do.
    List<UserList> currentLists = const [];
    try {
      currentLists = await _future;
    } catch (_) {
      // ignore — see comment above
    }
    if (!mounted) return;
    final billableCount = currentLists.where((l) => l.name != kTogetherListName).length;
    if (!context.read<PremiumService>().canAddList(billableCount)) {
      await showPremiumUpsellSheet(
        context,
        triggerSource: 'lists_limit',
        icon: Icons.playlist_add_outlined,
        title: 'lists limit reached'.tr,
        message: 'the free tier holds up to 5 lists — premium removes the limit'.tr,
      );
      return;
    }
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
        SnackBar(content: Text("couldn't create that list — try again".tr)),
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
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text('your lists'.tr, style: SeenlyText.screenTitle)),
                  PressScale(
                    onTap: _createList,
                    haptics: true,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.add, size: 22, color: SeenlyPalette.accent),
                    ),
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
                      child: Text("couldn't load your lists".tr,
                          style: SeenlyText.serif(
                              italic: true, color: SeenlyPalette.inkMuted)),
                    );
                  }
                  final lists = snapshot.data!;
                  // Billable count only (see [_createList]'s own doc
                  // comment on why the auto-created "watch together"
                  // list doesn't count toward the free ceiling) — the
                  // soft meter below should read exactly like the hard
                  // check it's warning about ahead of time, not a
                  // slightly different number that would only confuse
                  // someone comparing the two.
                  final billableCount =
                      lists.where((l) => l.name != kTogetherListName).length;
                  final meter = context.watch<PremiumService>().isPremium
                      ? null
                      : SoftLimitMeter(
                          used: billableCount,
                          limit: PremiumService.freeListsLimit,
                          label: LocaleService.appIsRussian
                              ? '$billableCount из ${PremiumService.freeListsLimit} списков'
                              : '$billableCount of ${PremiumService.freeListsLimit} lists',
                          onTapUpgrade: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PremiumScreen(triggerSource: 'lists_limit_soft'),
                            ),
                          ),
                        );
                  if (lists.isEmpty) {
                    return Column(
                      children: [
                        if (meter != null) Padding(padding: const EdgeInsets.only(top: 6), child: meter),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refresh,
                            color: SeenlyPalette.accent,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
                              children: [
                                Entrance(
                                  child: Text('no lists yet'.tr,
                                      textAlign: TextAlign.center,
                                      style: SeenlyText.serif(italic: true, size: 15)),
                                ),
                                const SizedBox(height: 8),
                                Entrance(
                                  delay: const Duration(milliseconds: 60),
                                  child: Text(
                                    'group whatever you like together — a mood, a marathon, favorites you keep coming back to'.tr,
                                    textAlign: TextAlign.center,
                                    style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Entrance(
                                  delay: const Duration(milliseconds: 110),
                                  riseBy: 14,
                                  child: PrimaryButton(label: 'new list'.tr, onTap: _createList),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      if (meter != null) Padding(padding: const EdgeInsets.only(top: 6), child: meter),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refresh,
                          color: SeenlyPalette.accent,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                            itemCount: lists.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) => ScrollRevealEntrance(
                              index: i,
                              child: _ListRow(
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
                          ),
                        ),
                      ),
                    ],
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
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
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
                    nCount('nTitles', list.itemCount),
                    style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
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
                        ? FadeInNetworkImage(
                            url: posters[i],
                            fit: BoxFit.cover,
                            placeholder: Container(color: SeenlyPalette.background),
                          )
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
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Entrance(
              child: Text('new list'.tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(italic: true, size: 16)),
            ),
            const SizedBox(height: 14),
            Entrance(
              delay: const Duration(milliseconds: 60),
              riseBy: 14,
              child: Container(
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
                    hintText: 'cozy rainy-day picks…'.tr,
                    hintStyle: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Entrance(
              delay: const Duration(milliseconds: 110),
              riseBy: 14,
              child: PrimaryButton(label: 'create'.tr, onTap: _submit),
            ),
          ],
        ),
      ),
    );
  }
}
