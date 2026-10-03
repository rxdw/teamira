import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/collection.dart';
import '../../models/diary_entry.dart';
import '../../models/media_item.dart' show CastMember;
import '../../models/watchlist_entry.dart';
import '../../state/app_state.dart';
import '../../state/diary_store.dart';
import '../../state/watchlist_store.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/heart_rating.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/section_header.dart';
import '../../widgets/share_card.dart';
import '../../widgets/share_sheet.dart';
import '../../widgets/series_episodes_sheet.dart';
import '../../widgets/watched_preview_sheet.dart';
import '../../services/log_theme_service.dart';
import '../../services/premium_service.dart';
import '../../widgets/premium_upsell_sheet.dart';
import '../premium/keepsake_export_screen.dart';
import '../../theme/log_theme_copy.dart';
import '../../widgets/log_ritual.dart';
import '../../widgets/log_timeline.dart';
import '../collections/collection_full_screen.dart';
import '../search/search_screen.dart';
import '../shell/root_shell.dart';
import '../title/title_detail_screen.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart';
import '../../services/app_translations.dart';
import '../../theme/notebook_paper.dart';
import '../../theme/seenly_skin.dart';
import '../../widgets/dashed_border.dart';
import '../../theme/clay_kit.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  // Diary entries themselves now live in DiaryStore (see Фаза 2.15 in
  // the launch plan) — this screen reads them reactively with
  // `context.watch<DiaryStore>()` in build() instead of holding its own
  // Future for them. _pickedFuture/_shelvesFuture stay as they were;
  // they're unrelated bonus strips, not core diary content.
  late Future<SeenlyCollection?> _pickedFuture;
  late Future<ProfileCollections?> _shelvesFuture;
  bool _refreshing = false;

  // "watching now" and "picked for you" are just the first two things in
  // the diary log's own ListView (see build below) — regular top-of-page
  // content, not a pinned/sticky header. They scroll away with the rest
  // of the page like everything below them once the person actually
  // scrolls, instead of staying glued to the top of the screen forever.
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Idempotent — if another screen already triggered this (or is in
    // the middle of it), this just shares that result. See DiaryStore's
    // own doc comment.
    context.read<DiaryStore>().ensureLoaded();
    _pickedFuture = _loadPicked();
    _shelvesFuture = _loadShelves();
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  Future<SeenlyCollection?> _loadPicked() async {
    // Best-effort — this strip is a discovery nudge, not core diary data,
    // so it just quietly disappears rather than showing an error block if
    // the catalog isn't reachable.
    try {
      final collections = await context.read<AppState>().feed.collections();
      final withItems = collections.where((c) => c.items.isNotEmpty).toList();
      if (withItems.isEmpty) return null;
      // Prefer the second shelf over the first when there is one, purely
      // so this doesn't just mirror Home's "picked for tonight" banner.
      return withItems.length > 1 ? withItems[1] : withItems.first;
    } catch (_) {
      return null;
    }
  }

  Future<ProfileCollections?> _loadShelves() async {
    // Same "best-effort" reasoning as _loadPicked above — "watching now"
    // (see _ShelvesStrip) is a nudge back to what's already in motion,
    // not core diary content, so a failed fetch just quietly collapses
    // the strip rather than showing an error block. Now shares
    // WatchlistStore's cache with profile_screen.dart instead of
    // fetching its own independent copy.
    try {
      return await context.read<WatchlistStore>().ensureLoaded();
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final next = context.read<DiaryStore>().refresh();
    final nextPicked = _loadPicked();
    final nextShelves = context.read<WatchlistStore>().refresh();
    setState(() {
      _pickedFuture = nextPicked;
      _shelvesFuture = nextShelves;
    });
    try {
      await next;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// The diary's own doorway into the keepsake PDF export (see
  /// screens/premium/keepsake_export_screen.dart) — a full card in the
  /// log itself now (see _KeepsakeCard below) rather than a small icon
  /// in the header, since that used to be too easy to miss. Reachable
  /// from the diary rather than only through Settings, since that's
  /// where someone would actually think to ask "can I keep this?"
  /// Premium opens the export screen directly; everyone else gets the
  /// same soft upsell sheet used elsewhere in the app (see
  /// widgets/premium_upsell_sheet.dart) instead of a hard wall — the
  /// card itself already says what's behind it either way (see
  /// _KeepsakeCard's own doc comment), so tapping never surprises
  /// anyone with a paywall they didn't see coming.
  void _openKeepsake() {
    if (context.read<PremiumService>().isPremium) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const KeepsakeExportScreen()));
      return;
    }
    showPremiumUpsellSheet(
      context,
      triggerSource: 'diary_pdf_export',
      icon: Icons.auto_stories_outlined,
      title: 'turn your diary into a keepsake'.tr,
      message:
          'premium can export your whole diary — or a wrapped recap of any period — as a soft, paper-styled pdf to save, print, or send'
              .tr,
    );
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'today'.tr;
    if (diff == 1) return 'yesterday'.tr;
    final months = [
      'jan'.tr, 'feb'.tr, 'mar'.tr, 'apr'.tr, 'may'.tr, 'jun'.tr,
      'jul'.tr, 'aug'.tr, 'sep'.tr, 'oct'.tr, 'nov'.tr, 'dec'.tr,
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  Map<String, List<DiaryEntry>> _grouped(List<DiaryEntry> entries) {
    final map = <String, List<DiaryEntry>>{};
    for (final e in entries) {
      final key = _dayLabel(e.watchedAt);
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    // DiaryScreen is only ever shown as a RootShell tab now —
    // RootShell.switchTab (see root_shell.dart) replaced the old
    // standalone `Navigator.push(DiaryScreen())` everywhere (Home's
    // "fresh in your diary — all" link, Profile's "diary ›" link, and
    // this screen's own back-to-profile action all go through it), so
    // there's no longer a case where this screen has to stand on its
    // own Scaffold. RootShell already supplies one Scaffold + SafeArea
    // shared by every tab, and already paints the looping video backdrop
    // and the ruled-paper texture once, underneath the whole IndexedStack
    // (see widgets/app_video_background.dart, theme/notebook_paper.dart)
    // — this screen used to paint its *own* second copy of both on top,
    // which sounds harmless ("VideoPlayer accepts the same controller
    // in more than one place at once") but isn't: IndexedStack keeps
    // every tab's widget tree alive and rebuilding regardless of which
    // one is active, so that second copy was never actually gated on
    // Diary being the visible tab — it was a second live VideoPlayer
    // bound to the same singleton controller sitting right on top of
    // RootShell's own, which is what made the video freeze/misbehave.
    // One shared background, painted once by RootShell, is enough.
    return SafeArea(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  HandDrawnUnderline(
                    child: Text('diary'.tr, style: SeenlyText.screenTitle),
                  ),
                  Row(
                    children: [
                      PressScale(
                        onTap: _refreshing ? null : _refresh,
                        haptics: true,
                        child: WobblyCircle(
                          size: 32,
                          color: SeenlyPalette.paper,
                          margin: const EdgeInsets.only(right: 8),
                          child: _refreshing
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: ThemedLoadingIndicator(
                                      strokeWidth: 2, color: SeenlyPalette.accent),
                                )
                              : Icon(Icons.refresh, size: 17, color: SeenlyPalette.ink),
                        ),
                      ),
                      PressScale(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SearchScreen()),
                        ),
                        haptics: true,
                        child: WobblyCircle(
                          size: 32,
                          color: SeenlyPalette.accent,
                          child: Icon(Icons.add,
                              size: 16, color: SeenlyPalette.accentOnAccent),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
              child: PressScale(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                ),
                // Cozy skin: a squarer, hand-stitched index-card look
                // (tighter corners, a dashed rule traced around the
                // edge) instead of the standard skin's plain rounded
                // search pill — reads as a card tucked into the diary
                // rather than a generic search field.
                child: Builder(builder: (context) {
                  final bar = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: ClayBoxDecoration(
                      boxShadow: SeenlyPalette.flatCardShadow,
                      color: SeenlyPalette.paper,
                      borderRadius:
                          BorderRadius.circular(SeenlySkin.isCozy ? 12 : 24),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 16, color: SeenlyPalette.inkFaint),
                        const SizedBox(width: 8),
                        Text('search a film, show, or game'.tr,
                            style: SeenlyText.serif(
                                italic: true, size: 13, color: SeenlyPalette.placeholder)),
                      ],
                    ),
                  );
                  if (!SeenlySkin.isCozy) return bar;
                  return DashedRoundedBorder(
                    color: SeenlyPalette.dashedBorder,
                    radius: 12,
                    margin: const EdgeInsets.all(3),
                    child: bar,
                  );
                }),
              ),
            ),
            Expanded(
              child: Consumer<DiaryStore>(
                builder: (context, diaryStore, _) {
                  if (diaryStore.entries.isEmpty && diaryStore.isLoading) {
                    return _fadeSwitch(const _DiarySkeleton(key: ValueKey('diary-skeleton')));
                  }
                  // Only the full-page error state when there's nothing
                  // cached to fall back to — a failed refresh with
                  // existing entries just quietly keeps showing them
                  // (see DiaryStore._load), which is the actual point of
                  // having a cache at all.
                  if (diaryStore.entries.isEmpty && diaryStore.error != null) {
                    return _fadeSwitch(RefreshIndicator(
                      key: const ValueKey('diary-error'),
                      onRefresh: _refresh,
                      color: SeenlyPalette.accent,
                      child: ListView(
                        controller: _logScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 60),
                        children: [
                          _ShelvesStrip(future: _shelvesFuture),
                          _PickedForYouStrip(future: _pickedFuture),
                          _ShelfPickStrip(future: _shelvesFuture),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 40, 22, 0),
                            child: Column(
                              children: [
                                Text('couldn\'t load the diary'.tr,
                                    textAlign: TextAlign.center,
                                    style: SeenlyText.serif(
                                        italic: true, color: SeenlyPalette.inkMuted)),
                                const SizedBox(height: 10),
                                Text('pull down, or tap the refresh icon above, to try again'.tr,
                                    textAlign: TextAlign.center,
                                    style: SeenlyText.mono(
                                        size: 10, color: SeenlyPalette.placeholder)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ));
                  }
                  final entries = diaryStore.entries;
                  // Claims one stagger slot per top-level section, capped the
                  // same way Home's own `nextStagger` is — a section far down
                  // the page has nothing to cascade alongside by the time
                  // anyone actually scrolls to it, so the stagger only needs
                  // to read nicely for what's visible on first paint.
                  var revealSlot = 0;
                  Duration nextReveal({int step = 60, int maxSlots = 4}) {
                    final slot = revealSlot < maxSlots ? revealSlot : maxSlots;
                    final d = Duration(milliseconds: slot * step);
                    revealSlot++;
                    return d;
                  }
                  if (entries.isEmpty) {
                    return _fadeSwitch(RefreshIndicator(
                      key: const ValueKey('diary-empty'),
                      onRefresh: _refresh,
                      color: SeenlyPalette.accent,
                      child: ListView(
                        controller: _logScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 60),
                        children: [
                          ScrollReveal(delay: nextReveal(), child: _ShelvesStrip(future: _shelvesFuture)),
                          ScrollReveal(
                              delay: nextReveal(), child: _PickedForYouStrip(future: _pickedFuture)),
                          ScrollReveal(
                              delay: nextReveal(), child: _ShelfPickStrip(future: _shelvesFuture)),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ScrollReveal(
                                  delay: nextReveal(),
                                  child: DiaryCenterpiece(entries: entries),
                                ),
                                const SizedBox(height: 40),
                                Text(
                                  LogThemeCopy.emptyDiary(
                                      context.watch<LogThemeService>().theme),
                                  textAlign: TextAlign.center,
                                  style: SeenlyText.emptyState(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ));
                  }
                  final grouped = _grouped(entries);
                  final logTheme = context.watch<LogThemeService>().theme;
                  // Built imperatively (rather than inline in the ListView's
                  // children list) so the washi-tape corner's color cursor
                  // can keep running across day groups — every day picks up
                  // the cycle where the previous one left off, instead of
                  // every group restarting on the same tape color.
                  var tapeCursor = 0;
                  final dayGroups = <Widget>[];
                  for (final key in grouped.keys) {
                    final dayEntries = grouped[key]!;
                    dayGroups.add(ScrollReveal(
                      // Each day group gets its own scroll-triggered reveal
                      // (rather than one shared delay for the whole log) so
                      // scrolling down the diary keeps unveiling fresh
                      // groups one at a time, at whatever pace someone
                      // actually scrolls — the same "settle in on the way
                      // down" feeling Home's own feed rows have.
                      riseBy: 16,
                      child: LogDayGroup(
                        theme: logTheme,
                        dayLabel: key,
                        tapeStartIndex: tapeCursor,
                        entries: [
                          for (final entry in dayEntries)
                            // A series row (season != null) is always one
                            // persistent card for the whole watch, not one
                            // evening — tap opens the season/episode sheet
                            // instead of the usual rating/note row.
                            entry.season != null
                                ? _SeriesEntryRow(entry: entry)
                                : _DiaryRow(entry: entry, onChanged: _refresh),
                        ],
                      ),
                    ));
                    tapeCursor += dayEntries.length;
                  }
                  return _fadeSwitch(RefreshIndicator(
                    key: const ValueKey('diary-content'),
                    onRefresh: _refresh,
                    color: SeenlyPalette.accent,
                    child: ListView(
                      controller: _logScrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        ScrollReveal(delay: nextReveal(), child: _ShelvesStrip(future: _shelvesFuture)),
                        ScrollReveal(
                            delay: nextReveal(), child: _PickedForYouStrip(future: _pickedFuture)),
                        ScrollReveal(
                            delay: nextReveal(), child: _ShelfPickStrip(future: _shelvesFuture)),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                          child: ScrollReveal(
                            delay: nextReveal(),
                            child: _KeepsakeCard(onTap: _openKeepsake),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ScrollReveal(
                                delay: nextReveal(),
                                child: DiaryCenterpiece(entries: entries),
                              ),
                              const SizedBox(height: 22),
                              ScrollReveal(
                                delay: nextReveal(),
                                riseBy: 10,
                                // In the cozy skin the label trails off into a
                                // torn-paper dashed rule running to the page
                                // edge, like a section break scored into a
                                // notebook page — plain label everywhere else,
                                // since CozyDivider itself becomes a real
                                // Divider outside cozy and we don't want a new
                                // line appearing in the standard skin.
                                child: Row(
                                  children: [
                                    Text('the log'.tr, style: SeenlyText.metaLabel),
                                    if (SeenlySkin.isCozy) ...[
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: CozyDivider(
                                          height: 1,
                                          thickness: 1,
                                          color: SeenlyPalette.dashedBorder,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              ...dayGroups,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ));
                },
              ),
            ),
          ],
        ),
    );
  }

  /// Shared cross-fade for the diary body's top-level states (skeleton /
  /// error / empty / real content) — one [AnimatedSwitcher] keyed off
  /// each child's own [Key] so swapping between any two of them dissolves
  /// rather than cuts, matching Home's own [_fadeSwitch]. A rebuild that
  /// keeps the same state (fresh data landing under the same content key
  /// during pull-to-refresh) is a no-op here, not a re-triggered fade.
  Widget _fadeSwitch(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

/// A proper card for the keepsake PDF export, sitting right in the log
/// itself — this used to be a small icon in the header (easy to miss,
/// see _DiaryScreenState._openKeepsake's own doc comment) and is now
/// something you actually scroll past. Shown to every account, premium
/// or not: the point is that people should know this exists even
/// before they've paid for it, so the "premium" badge and blurb below
/// only appear for non-premium accounts — everyone else already knows,
/// so their card just says what it does. Tapping goes through
/// _openKeepsake either way, which is what decides whether that's the
/// real export screen or the upsell sheet.
class _KeepsakeCard extends StatelessWidget {
  final VoidCallback onTap;
  const _KeepsakeCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<PremiumService>().isPremium;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.clay,
          borderRadius: BorderRadius.circular(16),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: SeenlyPalette.accentOnAccent.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.auto_stories_outlined,
                  size: 17, color: SeenlyPalette.accentOnAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isPremium) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.accentOnAccent.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('premium'.tr,
                          style: SeenlyText.mono(
                              size: 8, color: SeenlyPalette.accentOnAccent)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text('turn your diary into a keepsake'.tr,
                      style: SeenlyText.serif(
                          italic: true, size: 15, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
                  const SizedBox(height: 3),
                  Text(
                    'premium can export your whole diary — or a wrapped recap of any period — as a soft, paper-styled pdf to save, print, or send'
                        .tr,
                    style: SeenlyText.mono(
                        size: 9.5, color: SeenlyPalette.accentOnAccent.withOpacity(0.85)),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 17, color: SeenlyPalette.accentOnAccent),
          ],
        ),
      ),
    );
  }
}

/// A quiet stand-in for the diary body while the first load is in flight
/// — rough bones of the real layout (a shelf strip, the picked-for-you
/// strip, the centerpiece, a couple of log rows) in the same soft
/// shimmering paper tones [ShimmerBlock] uses everywhere else, so the
/// very first frame already reads as *this* screen instead of a bare
/// spinner. The cross-fade into real content (see
/// [_DiaryScreenState._fadeSwitch]) then feels like a settle, not a
/// swap — same reasoning as Home's own `_HomeSkeleton`.
class _DiarySkeleton extends StatelessWidget {
  const _DiarySkeleton({super.key});

  static Widget _bone({double? w, double h = 16, double r = 8}) => ShimmerBlock(
        width: w,
        height: h,
        borderRadius: BorderRadius.circular(r),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
      children: [
        _bone(w: 110, h: 12, r: 6),
        const SizedBox(height: 10),
        SizedBox(
          height: 74,
          child: Row(
            children: [
              Expanded(child: _bone(h: 74, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 74, r: 14)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _bone(w: 140, h: 12, r: 6),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: Row(
            children: [
              Expanded(child: _bone(h: 150, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 150, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 150, r: 14)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _bone(w: 170, h: 12, r: 6),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: Row(
            children: [
              Expanded(child: _bone(h: 150, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 150, r: 14)),
              const SizedBox(width: 10),
              Expanded(child: _bone(h: 150, r: 14)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _bone(h: 140, r: 20),
        const SizedBox(height: 24),
        _bone(w: 70, h: 12, r: 6),
        const SizedBox(height: 14),
        _bone(h: 100, r: 14),
        const SizedBox(height: 12),
        _bone(h: 100, r: 14),
      ],
    );
  }
}

/// "watching now" — a quiet nudge back to what's already in motion,
/// sitting right above "picked for you" so the diary opens on the
/// person's own shelf before it opens on a recommendation. A single
/// horizontally-scrolling row of landscape info-chips (poster thumb +
/// title + a small status pill) rather than another vertical-poster
/// carousel like Collections or "picked for you" below use — same warm
/// paper-and-shadow language as the rest of the app, just built as a
/// little index-card shelf instead of a wall of posters, so the tab
/// doesn't read as three copies of the same strip in a row. Quietly
/// collapses to nothing while loading, on a failed fetch, or once the
/// shelf is actually empty — same reasoning as _PickedForYouStrip.
class _ShelvesStrip extends StatelessWidget {
  final Future<ProfileCollections?> future;
  const _ShelvesStrip({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileCollections?>(
      future: future,
      builder: (context, snapshot) {
        final collections = snapshot.data;
        if (collections == null) return const SizedBox.shrink();
        final watching = collections.watching;
        if (watching.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: _ShelfRow(
            label: 'watching now'.tr,
            icon: Icons.play_circle_outline,
            tint: SeenlyPalette.sage,
            entries: watching,
          ),
        );
      },
    );
  }
}

class _ShelfRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final List<WatchlistEntry> entries;

  const _ShelfRow({
    required this.label,
    required this.icon,
    required this.tint,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    // Two or fewer entries never fills a scrollable strip — it just
    // sits stranded on the left with a lot of empty space to its
    // right. Give those cards the full row width instead (split evenly
    // for two) so the shelf reads as deliberately laid out rather than
    // a horizontal list that happens to be short. Three or more keeps
    // the original scrollable strip of fixed-width chips.
    final fullWidth = entries.length <= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: tint),
              const SizedBox(width: 5),
              Text(label, style: SeenlyText.metaLabel),
              const SizedBox(width: 6),
              Text('${entries.length}', style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            ],
          ),
        ),
        if (fullWidth)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: HorizontalReveal(
                      delay: Duration(milliseconds: 40 + i.clamp(0, 3) * 70),
                      child: _ShelfChip(entry: entries[i], tint: tint, label: label, fullWidth: true),
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => HorizontalReveal(
                delay: Duration(milliseconds: 40 + i.clamp(0, 3) * 70),
                child: _ShelfChip(entry: entries[i], tint: tint, label: label),
              ),
            ),
          ),
      ],
    );
  }
}

class _ShelfChip extends StatelessWidget {
  final WatchlistEntry entry;
  final Color tint;
  final String label;
  final bool fullWidth;
  const _ShelfChip({required this.entry, required this.tint, required this.label, this.fullWidth = false});

  bool get _isSeries => entry.mediaType == 'series' || entry.mediaType == 'anime';

  @override
  Widget build(BuildContext context) {
    final posterW = fullWidth ? 52.0 : 40.0;
    final posterH = fullWidth ? 76.0 : 58.0;
    return PressScale(
      onTap: () => _isSeries
          ? showSeriesEpisodesSheet(
              context,
              mediaId: entry.mediaId,
              source: entry.source,
              title: entry.displayTitle,
              mediaType: entry.mediaType,
              posterUrl: entry.posterUrl,
            )
          : Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TitleDetailScreen(
                  mediaId: entry.mediaId,
                  source: entry.source,
                  mediaType: entry.mediaType,
                  seedTitle: entry.displayTitle,
                  seedPosterUrl: entry.posterUrl,
                ),
              ),
            ),
      child: Container(
        width: fullWidth ? null : 172,
        height: fullWidth ? 96 : null,
        padding: EdgeInsets.all(fullWidth ? 10 : 8),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: posterW,
                height: posterH,
                child: entry.posterUrl != null
                    ? FadeInNetworkImage(
                        url: entry.posterUrl!,
                        fit: BoxFit.cover,
                        placeholder: Container(color: SeenlyPalette.mediaColor(entry.mediaType)),
                      )
                    : Container(color: SeenlyPalette.mediaColor(entry.mediaType)),
              ),
            ),
            SizedBox(width: fullWidth ? 10 : 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: fullWidth ? 13 : 11.5, color: SeenlyPalette.ink),
                  ),
                  SizedBox(height: fullWidth ? 6 : 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tint.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(label, style: SeenlyText.mono(size: 8, color: tint)),
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

/// "picked for you" — a thin editorial strip sitting between the shelves
/// strip above and the diary list itself, so there's always something to
/// reach for even on a day you're not adding anything. Quietly collapses
/// to nothing while loading or if the catalog isn't reachable — this is a
/// bonus, not core diary content, so it shouldn't compete for attention
/// with a spinner or an error block the way the diary list itself does.
class _PickedForYouStrip extends StatelessWidget {
  final Future<SeenlyCollection?> future;
  const _PickedForYouStrip({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SeenlyCollection?>(
      future: future,
      builder: (context, snapshot) {
        final collection = snapshot.data;
        if (collection == null || collection.items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: SectionHeader(
                  title: 'picked for you'.tr,
                  trailing: 'all →',
                  centerTitle: true,
                  onTrailingTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CollectionFullScreen(collection: collection),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  itemCount: collection.items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final item = collection.items[i];
                  return HorizontalReveal(
                    delay: Duration(milliseconds: 40 + i.clamp(0, 3) * 70),
                    child: SizedBox(
                      width: 92,
                      child: ThemedPosterTile(
                          title: item.title.display,
                          posterUrl: item.posterUrl,
                          mediaType: item.mediaType,
                          fallbackColor: SeenlyPalette.gridColorFor(i),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TitleDetailScreen(
                                mediaId: item.id,
                                source: item.source,
                                mediaType: item.mediaType,
                                seedTitle: item.title.display,
                                seedPosterUrl: item.posterUrl,
                                seedItem: item,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "pick something from your shelf" — sits right under "picked for
/// you" so the diary opens on a nudge back into the person's *own*
/// pile before it opens on the log itself: three random draws from the
/// "plan to watch" shelf (see [ProfileCollections.watchLater]), a quiet
/// way to surface something that's already been sitting there instead
/// of leaving it to be rediscovered by scrolling Profile. Reuses the
/// same [ProfileCollections] future [_ShelvesStrip] already fetches —
/// this is the second reader of it, not a second network call.
///
/// The draw is picked once per fresh fetch and then held in state, so
/// scrolling past it and back (or an unrelated rebuild higher up the
/// tree) doesn't silently swap the three titles out from under
/// someone mid-glance — only a genuine reroll tap, or new data landing
/// after pull-to-refresh, picks again. Quietly collapses to nothing
/// while loading, on a failed fetch, or once the shelf is empty — same
/// "bonus, not core diary content" reasoning as [_PickedForYouStrip].
class _ShelfPickStrip extends StatefulWidget {
  final Future<ProfileCollections?> future;
  const _ShelfPickStrip({required this.future});

  @override
  State<_ShelfPickStrip> createState() => _ShelfPickStripState();
}

class _ShelfPickStripState extends State<_ShelfPickStrip> with SingleTickerProviderStateMixin {
  List<WatchlistEntry>? _sourceShelf;
  List<WatchlistEntry> _picks = const [];
  // Bumped per-tile, per-reroll — folded into that tile's ValueKey below
  // so AnimatedSwitcher always sees a genuinely new key for the tile
  // that just changed, even on the rare shuffle that happens to land
  // the same title back in the same spot.
  List<int> _tileNonce = const [];
  bool _rerolling = false;

  late final AnimationController _spinController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 480));

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  List<WatchlistEntry> _draw(List<WatchlistEntry> shelf) {
    final pool = [...shelf]..shuffle();
    return pool.take(3).toList();
  }

  /// Reshuffles one tile at a time, left to right, instead of swapping
  /// all three the instant the button is tapped — the same staggered
  /// feel [HorizontalReveal] gives this row on first load, just
  /// replayed for a reroll. Each tile pops in with a small overshoot
  /// (see the AnimatedSwitcher below) and the "↻" itself spins once, so
  /// tapping it actually reads as *something happening* rather than the
  /// picks silently swapping in place.
  Future<void> _reroll(List<WatchlistEntry> shelf) async {
    if (_rerolling) return;
    _rerolling = true;
    _spinController.forward(from: 0);
    final next = _draw(shelf);
    for (var i = 0; i < next.length; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() {
        final picks = [..._picks];
        final nonce = [..._tileNonce];
        picks[i] = next[i];
        nonce[i] = nonce[i] + 1;
        _picks = picks;
        _tileNonce = nonce;
      });
    }
    _rerolling = false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileCollections?>(
      future: widget.future,
      builder: (context, snapshot) {
        final collections = snapshot.data;
        if (collections == null || collections.watchLater.isEmpty) {
          return const SizedBox.shrink();
        }
        final shelf = collections.watchLater;
        // A genuinely new list instance means fresh data (first load,
        // or a pull-to-refresh landed) — reshuffle. Same list instance
        // on a rebuild just re-renders the standing draw.
        if (!identical(_sourceShelf, shelf)) {
          _sourceShelf = shelf;
          _picks = _draw(shelf);
          _tileNonce = List.filled(_picks.length, 0);
        }
        final canReroll = shelf.length > 3;
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: SectionHeader(
                  title: 'pick something from your shelf'.tr,
                  trailing: canReroll ? '↻' : null,
                  trailingChild: canReroll
                      ? RotationTransition(
                          turns: _spinController,
                          child: Text('↻',
                              style: SeenlyText.mono(
                                  size: 15, weight: FontWeight.w700, color: SeenlyPalette.inkFaint)),
                        )
                      : null,
                  centerTitle: true,
                  onTrailingTap: canReroll ? () => _reroll(shelf) : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _picks.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      SizedBox(
                        width: 92,
                        child: HorizontalReveal(
                          delay: Duration(milliseconds: 40 + i.clamp(0, 3) * 70),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 360),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.86, end: 1).animate(
                                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                                ),
                                child: child,
                              ),
                            ),
                            child: ThemedPosterTile(
                              key: ValueKey(
                                  '${_picks[i].mediaId}-${i < _tileNonce.length ? _tileNonce[i] : 0}'),
                              title: _picks[i].displayTitle,
                              posterUrl: _picks[i].posterUrl,
                              mediaType: _picks[i].mediaType,
                              fallbackColor: SeenlyPalette.mediaColor(_picks[i].mediaType),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TitleDetailScreen(
                                    mediaId: _picks[i].mediaId,
                                    source: _picks[i].source,
                                    mediaType: _picks[i].mediaType,
                                    seedTitle: _picks[i].displayTitle,
                                    seedPosterUrl: _picks[i].posterUrl,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _ShelfPickCta(count: shelf.length),
            ],
          ),
        );
      },
    );
  }
}

/// The "to plan to watch" jump under [_ShelfPickStrip] — a soft,
/// tinted pill rather than a solid [PrimaryButton], so it reads as a
/// quiet way back to the shelf rather than competing with the "+" log
/// button up in the header for the one loud action on the page.
/// Requests Profile's "plan to watch" tab specifically (not just the
/// tab itself) before switching, via [AppState.requestProfileTab], so
/// landing there always shows the shelf this strip was drawn from.
class _ShelfPickCta extends StatelessWidget {
  final int count;
  const _ShelfPickCta({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      child: PressScale(
        haptics: true,
        onTap: () {
          context.read<AppState>().requestProfileTab(1); // plan to watch
          RootShell.switchTab(context, RootShell.profileTab);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: SeenlyPalette.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SeenlyPalette.accent.withOpacity(0.22)),
          ),
          child: Row(
            children: [
              WobblyCircle(
                size: 26,
                color: SeenlyPalette.accent,
                child: Icon(Icons.bookmark, size: 12, color: SeenlyPalette.accentOnAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('to plan to watch'.tr,
                    style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.accent)),
              ),
              Text('$count', style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 16, color: SeenlyPalette.accent),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _diaryMediaIcon(String mediaType) {
  switch (mediaType) {
    case 'movie':
      return Icons.movie_outlined;
    case 'series':
      return Icons.tv_outlined;
    case 'game':
      return Icons.videogame_asset_outlined;
    case 'anime':
      return Icons.auto_awesome_outlined;
    case 'book':
      return Icons.menu_book_outlined;
    case 'manga':
      return Icons.import_contacts_outlined;
    default:
      return Icons.local_movies_outlined;
  }
}

/// The poster + its little media-type badge, shared between
/// [_SeriesEntryRow] and [_DiaryRow] — bigger than the old bare 50×70
/// Image.network (64×92, closer to a real poster) with a soft shadow of
/// its own so it reads as a small object sitting on the card rather than
/// a flat thumbnail, plus the media-type badge overlapping its corner so
/// a glance down the log tells movies from series from games without
/// reading the subtitle line.
class _DiaryPoster extends StatelessWidget {
  final String? posterUrl;
  final String mediaType;
  const _DiaryPoster({required this.posterUrl, required this.mediaType});

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.mediaColor(mediaType);
    final image = posterUrl != null && posterUrl!.isNotEmpty
        ? FadeInNetworkImage(
            url: posterUrl!,
            fit: BoxFit.cover,
            placeholder: Container(color: color),
          )
        : Container(color: color);
    // Cozy skin: a little pinned photo (PolaroidFrame — same widget the
    // poster grids already use) instead of a plain rounded thumbnail,
    // so a logged evening reads as a snapshot tucked onto the page.
    // Renders [image] unframed outside the cozy skin, so this is a
    // no-op there.
    final poster = PolaroidFrame(
      tiltSeed: (posterUrl ?? mediaType).hashCode,
      child: image,
    );
    final plainPoster = Container(
      decoration: ClayBoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: 64, height: 92, child: image),
      ),
    );
    return SizedBox(
      width: 64,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SeenlySkin.isCozy ? poster : plainPoster,
          Positioned(
            bottom: -6,
            left: -6,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: SeenlyPalette.paper, width: 2),
              ),
              child: Icon(_diaryMediaIcon(mediaType), size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// A series' one diary row — the running "N episodes watched" count
/// this row's own [DiaryEntry.episodesWatched] already carries, updated
/// in place on every log rather than accumulated from a run of separate
/// rows (see models.DiaryEntry's own doc comment on the backend). Tap
/// opens the full season/episode sheet the Watched shelf uses too (see
/// showSeriesEpisodesSheet), which fetches its own up-to-date progress —
/// this card doesn't need to.
class _SeriesEntryRow extends StatelessWidget {
  final DiaryEntry entry;
  const _SeriesEntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final watched = entry.episodesWatched;
    final progressLabel = watched == null || watched == 0
        ? 'S${entry.season}${entry.episode != null ? "E${entry.episode}" : ""}'
        : '$watched ${nOnly('nEpisodes', watched)} ${"watched".tr} · S${entry.season}'
            '${entry.episode != null ? "E${entry.episode}" : ""}';
    // A folded-down page corner (cozy skin only — DogEarCorner is a
    // no-op outside it) so a series entry reads as its own dog-eared
    // page in the diary, matching the treatment Collections cards
    // already get.
    return DogEarCorner(
      child: PressScale(
      onTap: () => showSeriesEpisodesSheet(
        context,
        mediaId: entry.mediaId,
        source: entry.source,
        title: entry.displayTitle,
        mediaType: entry.mediaType,
        posterUrl: entry.posterUrl,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          // .start now that a rating/note preview can push this
          // column taller than the poster — .center would leave the
          // poster and chevron visibly low against a two-line note.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DiaryPoster(posterUrl: entry.posterUrl, mediaType: entry.mediaType),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SeenlySkin.isCozy
                      ? StampBadge(
                          color: SeenlyPalette.sage,
                          child: Text('watching · series'.tr,
                              style: SeenlyText.mono(
                                  size: 8.5, weight: FontWeight.w700, color: SeenlyPalette.sage)),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.sage.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('watching · series'.tr,
                              style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.sage)),
                        ),
                  const SizedBox(height: 6),
                  Text(entry.displayTitle, style: SeenlyText.cardTitle),
                  const SizedBox(height: 4),
                  Text(
                    entry.isRewatch ? 'rewatch · $progressLabel' : progressLabel,
                    style: SeenlyText.metaLabel,
                  ),
                  // The series' one rating/review, once it's logged one
                  // — see _SeriesReviewCard for where it's actually
                  // written/edited (this sheet just opens straight to
                  // it on tap). Same "rating then a quoted note preview"
                  // order _DiaryRow uses for a movie, so a series entry
                  // reads as the same kind of card at a glance.
                  if (entry.rating != null) ...[
                    const SizedBox(height: 7),
                    HeartRating(value: entry.rating!, size: 13),
                  ],
                  if (entry.note != null && entry.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      entry.note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
      ),
    );
  }
}

/// A quiet little overlapping-avatar row for the "who stole the show"
/// picks from the log flow (see DiaryEntry.favoriteCast) — small
/// enough to sit under the mood tags without competing with them, but
/// still a real "these were the faces you loved that night" touch
/// rather than a bare text list. A tiny heart badge on the lead avatar
/// mirrors the same glyph the pick step and confirm card use, so it
/// reads as the same gesture rather than a new icon language.
class _FavoriteCastRow extends StatelessWidget {
  final List<CastMember> cast;
  const _FavoriteCastRow({required this.cast});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          // Just wide enough for up to 3 overlapping 20px circles —
          // each new one only adds 14px since they overlap by 6.
          width: 20 + (cast.length - 1).clamp(0, 2) * 14,
          height: 22,
          child: Stack(
            children: [
              for (int i = 0; i < cast.length; i++)
                Positioned(
                  left: i * 14.0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: SeenlyPalette.paper, width: 1.5),
                    ),
                    child: ClipOval(
                      child: (cast[i].photoUrl != null)
                          ? FadeInNetworkImage(
                              url: cast[i].photoUrl!,
                              fit: BoxFit.cover,
                              placeholder: Container(color: SeenlyPalette.accent),
                            )
                          : Container(color: SeenlyPalette.accent),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            cast.map((m) => m.name).join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
          ),
        ),
      ],
    );
  }
}

class _DiaryRow extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback? onChanged;
  const _DiaryRow({required this.entry, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final mediaTypeTag = SeenlySkin.isCozy
        ? StampBadge(
            color: SeenlyPalette.mediaColor(entry.mediaType),
            angle: -0.1,
            child: Text(entry.mediaType,
                style: SeenlyText.mono(
                    size: 8.5,
                    weight: FontWeight.w700,
                    color: SeenlyPalette.mediaColor(entry.mediaType))),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: SeenlyPalette.mediaColor(entry.mediaType).withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(entry.mediaType,
                style: SeenlyText.mono(
                    size: 8.5, color: SeenlyPalette.mediaColor(entry.mediaType))),
          );
    // A folded-down page corner, matching the treatment [_SeriesEntryRow]
    // and Collections cards already get — cozy skin only.
    return DogEarCorner(
      child: PressScale(
      onTap: () async {
        await showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry));
        onChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DiaryPoster(posterUrl: entry.posterUrl, mediaType: entry.mediaType),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      mediaTypeTag,
                      if (entry.isRewatch) ...[
                        const SizedBox(width: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.replay, size: 11, color: SeenlyPalette.inkFaint),
                            const SizedBox(width: 2),
                            Text('rewatch'.tr,
                                style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.inkFaint)),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(entry.displayTitle, style: SeenlyText.cardTitle),
                  if (entry.watchedWithUsername != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite, size: 10, color: SeenlyPalette.accent),
                        const SizedBox(width: 4),
                        Text('${'watched with'.tr} ${entry.watchedWithUsername}',
                            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.accent)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 7),
                  if (entry.rating != null) HeartRating(value: entry.rating!, size: 13),
                  if (entry.moodTags.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // In the cozy skin each tag cycles through the
                        // same three washi-tape tones the log's tape
                        // corners use, and reads as a little paper tag
                        // (small radius) rather than a plain pill.
                        for (final (i, tag) in entry.moodTags.indexed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: SeenlySkin.isCozy
                                  ? [
                                      SeenlyPalette.tapeRose,
                                      SeenlyPalette.tapeSage,
                                      SeenlyPalette.tapeMustard,
                                    ][i % 3]
                                      .withOpacity(0.55)
                                  : SeenlyPalette.background,
                              borderRadius:
                                  BorderRadius.circular(SeenlySkin.isCozy ? 5 : 10),
                            ),
                            child: Text(tag,
                                style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkMuted)),
                          ),
                      ],
                    ),
                  ],
                  if (entry.favoriteCast.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _FavoriteCastRow(cast: entry.favoriteCast),
                  ],
                  if (entry.note != null && entry.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    // Cozy skin: a small hand-drawn quote mark ahead of
                    // the note, so it reads as a scribble in the margin
                    // rather than plain body text — a no-op decoration
                    // outside cozy, where the italic serif already did
                    // that job on its own.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (SeenlySkin.isCozy) ...[
                          Icon(Icons.format_quote, size: 13, color: SeenlyPalette.accent),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            entry.note!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.serif(
                                italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            PressScale(
              onTap: () => showShareCardSheet(
                context,
                card: EveningShareCard(
                  entry: entry,
                  fallbackColor: SeenlyPalette.mediaColor(entry.mediaType),
                ),
                fileName: 'seenly-${entry.id}',
                shareText: 'watched "${entry.displayTitle}" — logged in seenly',
                rewardKey: 'seenly-${entry.id}',
              ),
              // Was a faint, background-colored circle with a
              // barely-there icon — easy to read as pure decoration
              // rather than a tap target. Tinting it with the accent
              // color (same language as the share buttons elsewhere —
              // see watched_preview_sheet.dart) makes it legible at a
              // glance as "you can share this row" without needing to
              // grow the row itself.
              child: WobblyCircle(
                size: 30,
                color: SeenlyPalette.accent.withOpacity(0.12),
                margin: const EdgeInsets.only(left: 6),
                child: Icon(Icons.ios_share_rounded, size: 15, color: SeenlyPalette.accent),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
