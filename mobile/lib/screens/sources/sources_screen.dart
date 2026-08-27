import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/watchlist_entry.dart';
import '../../services/sources_display_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import 'add_source_screen.dart';
import '../../services/app_translations.dart';

/// "Your sources" — Settings > your sources. The same watched / watching
/// / plan-to-watch shelves Profile shows for movies/series, but scoped to
/// whatever's come in from YouTube/Twitch links (see backend/app/routers/
/// sources.py) and kept off the main Profile tab entirely, so a big
/// playlist import never skews the "movies watched" stat.
///
/// Items here never open the title detail screen — there's no catalog
/// entry behind a media_type == "video" row — tapping one opens the
/// original video/VOD in the YouTube/Twitch app or browser instead (see
/// _openExternally below).
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  late Future<ProfileCollections> _future;
  int _tab = 0; // 0 = watched, 1 = watching, 2 = plan to watch

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ProfileCollections> _load() => context.read<AppState>().sources.collections();

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _addSource() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddSourceScreen()),
    );
    if (added == true) _refresh();
  }

  Future<void> _openExternally(WatchlistEntry e) async {
    final uri = e.source == 'twitch'
        ? Uri.parse('https://www.twitch.tv/videos/${e.mediaId}')
        : Uri.parse('https://www.youtube.com/watch?v=${e.mediaId}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  IconData _platformIcon(String source) =>
      source == 'twitch' ? Icons.videocam_rounded : Icons.smart_display_rounded;

  @override
  Widget build(BuildContext context) {
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
                  IconButton(
                    icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Text('your sources'.tr, style: SeenlyText.screenTitle),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline, size: 20, color: SeenlyPalette.accent),
                    onPressed: _addSource,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
              child: Text(
                'YouTube and Twitch, brought in by link — kept separate from your movies and shows so it never skews those stats.'.tr,
                style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
              child: Builder(builder: (context) {
                final sourcesPrefs = context.watch<SourcesDisplayPrefsService>();
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dashboard_customize_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('mix these into your main list?'.tr,
                                style: SeenlyText.serif(size: 13)),
                          ),
                          Switch(
                            value: sourcesPrefs.mergeIntoMainList,
                            activeColor: SeenlyPalette.accent,
                            onChanged: (value) =>
                                context.read<SourcesDisplayPrefsService>().setMergeIntoMainList(value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'shows these alongside movies and shows in watched, watching, and plan to watch — heads up, they can look a little off there, since a source opens the video itself instead of a title page'.tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            Expanded(
              child: FutureBuilder<ProfileCollections>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return Center(
                      child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
                    );
                  }
                  if (snapshot.hasError) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: SeenlyPalette.accent,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 60),
                        children: [
                          Text("couldn't load your sources".tr,
                              textAlign: TextAlign.center,
                              style: SeenlyText.serif(italic: true, color: SeenlyPalette.inkMuted)),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _refresh,
                            child: Text('pull down, or tap here, to try again'.tr,
                                textAlign: TextAlign.center,
                                style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
                          ),
                        ],
                      ),
                    );
                  }
                  final data = snapshot.data!;
                  final shelf = _tab == 0
                      ? data.watched
                      : _tab == 1
                          ? data.watching
                          : data.watchLater;
                  final isEmptyOverall =
                      data.watched.isEmpty && data.watching.isEmpty && data.watchLater.isEmpty;

                  if (isEmptyOverall) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: SeenlyPalette.accent,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
                        children: [
                          Icon(Icons.smart_display_outlined, size: 30, color: SeenlyPalette.placeholder),
                          const SizedBox(height: 14),
                          Text(
                            'nothing here yet — paste a YouTube or Twitch link to bring something over'.tr,
                            textAlign: TextAlign.center,
                            style: SeenlyText.serif(italic: true, color: SeenlyPalette.placeholder),
                          ),
                          const SizedBox(height: 18),
                          PrimaryButton(label: 'add a source'.tr, onTap: _addSource, expand: false),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: SeenlyPalette.accent,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: SeenlyPalette.border)),
                            ),
                            child: _SourcesTabBar(
                              selected: _tab,
                              onSelected: (i) => setState(() => _tab = i),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(21, 14, 21, 6),
                          sliver: SliverToBoxAdapter(
                            child: Text(ruCount(shelf.length, one: 'тайтл', few: 'тайтла', many: 'тайтлов', englishOne: 'item', englishOther: 'items'),
                                style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(21, 4, 21, 28),
                          sliver: shelf.isEmpty
                              ? SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 24),
                                    child: Text(
                                      _tab == 0
                                          ? 'nothing marked watched yet'
                                          : _tab == 1
                                              ? 'nothing in progress right now'
                                              : 'nothing queued yet',
                                      style: SeenlyText.serif(italic: true, color: SeenlyPalette.placeholder),
                                    ),
                                  ),
                                )
                              : SliverGrid(
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 14,
                                    childAspectRatio: 16 / 10,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, i) {
                                      final e = shelf[i];
                                      return _VideoThumbTile(
                                        title: e.displayTitle,
                                        thumbnailUrl: e.posterUrl,
                                        platformIcon: _platformIcon(e.source),
                                        onTap: () => _openExternally(e),
                                      );
                                    },
                                    childCount: shelf.length,
                                  ),
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
    );
  }
}

/// A landscape thumbnail tile for one YouTube/Twitch item — deliberately
/// not [ThemedPosterTile]/[PosterTile]: those are built around a 2:3
/// movie-poster shape (plus filmstrip/boarding-pass/plant-tag dressing
/// meant for artwork, not a screenshot), and forcing a 16:9 YouTube/
/// Twitch thumbnail into that frame just crops off both sides. This
/// keeps the thumbnail's own proportions and adds only what a video
/// tile actually needs: a platform icon and the title.
class _VideoThumbTile extends StatelessWidget {
  final String title;
  final String? thumbnailUrl;
  final IconData platformIcon;
  final VoidCallback onTap;

  const _VideoThumbTile({
    required this.title,
    required this.thumbnailUrl,
    required this.platformIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = thumbnailUrl != null && thumbnailUrl!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Image.network(
                thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.mediaColor('video')),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : Container(color: SeenlyPalette.mediaColor('video')),
              )
            else
              Container(color: SeenlyPalette.mediaColor('video')),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: Icon(platformIcon, size: 12, color: SeenlyPalette.paper),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// This screen's own watched/watching/plan-to-watch switch — content-
/// sized and packed to the left (mono caption style) rather than the
/// full-width italic-serif [UnderlineTabRow] Profile and the friend
/// screen use, so it keeps its own look here. Same "liquid" underline
/// as the full-width version: it stretches toward whichever label was
/// just tapped and settles once it arrives, rather than sliding at a
/// constant width or jumping — and the label color crossfades on the
/// same clock.
class _SourcesTabBar extends StatefulWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const _SourcesTabBar({required this.selected, required this.onSelected});

  @override
  State<_SourcesTabBar> createState() => _SourcesTabBarState();
}

class _SourcesTabBarState extends State<_SourcesTabBar> with SingleTickerProviderStateMixin {
  static const _labels = ['watched', 'watching', 'plan to watch'];
  static const _gap = 18.0;

  static TextStyle _style(bool active) =>
      SeenlyText.mono(size: 11, color: active ? SeenlyPalette.accent : SeenlyPalette.inkFaint);

  late final AnimationController _controller;
  late int _fromIndex;
  late int _toIndex;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selected;
    _toIndex = widget.selected;
    _controller = AnimationController(vsync: this, duration: kTabTransitionDuration, value: 1);
  }

  @override
  void didUpdateWidget(covariant _SourcesTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != _toIndex) {
      _fromIndex = _toIndex;
      _toIndex = widget.selected;
      _controller
        ..stop()
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Precompute each label's rendered width so the indicator can slide
    // to a content-sized offset/width per tab, not an equal-width slot.
    final widths = <double>[
      for (final label in _labels)
        (TextPainter(
          text: TextSpan(text: label, style: _style(false)),
          textDirection: TextDirection.ltr,
        )..layout())
            .width,
    ];
    final offsets = <double>[];
    var running = 0.0;
    for (final w in widths) {
      offsets.add(running);
      running += w + _gap;
    }

    final fromLeft = offsets[_fromIndex];
    final fromRight = fromLeft + widths[_fromIndex];
    final toLeft = offsets[_toIndex];
    final toRight = toLeft + widths[_toIndex];
    final movingForward = toLeft >= fromLeft;

    return Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < _labels.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSelected(i),
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == _labels.length - 1 ? 0 : _gap,
                    top: 10,
                    bottom: 10,
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: kTabTextDuration,
                    curve: Curves.easeOutCubic,
                    style: _style(widget.selected == i),
                    child: Text(_labels[i]),
                  ),
                ),
              ),
          ],
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final lead = kTabLeadCurve.transform(_controller.value);
            final lag = kTabLagCurve.transform(_controller.value);
            final left = movingForward
                ? fromLeft + (toLeft - fromLeft) * lag
                : fromLeft + (toLeft - fromLeft) * lead;
            final right = movingForward
                ? fromRight + (toRight - fromRight) * lead
                : fromRight + (toRight - fromRight) * lag;
            return Positioned(
              left: left,
              bottom: 0,
              width: right - left,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(color: SeenlyPalette.accent),
              ),
            );
          },
        ),
      ],
    );
  }
}
