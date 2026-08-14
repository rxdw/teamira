import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/co_view_entry.dart';
import '../../models/friend.dart';
import '../../models/partner_status.dart';
import '../../models/suggestion.dart';
import '../../services/api_client.dart';
import '../../services/rabbit_mascot_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/how_it_works_sheet.dart';
import '../../widgets/coview_bunnies_corner.dart';
import '../../widgets/co_view_decide_card.dart';
import '../../widgets/evening_plan_card.dart';
import '../../widgets/planned_preview_sheet.dart';
import '../../widgets/scroll_reveal.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/watched_preview_sheet.dart';
import '../../widgets/wow_motion.dart' show Entrance, PressScale;
import '../title/title_detail_screen.dart';

/// The linked pair's own screen: everything hearted for tonight or matched
/// through Watch Together (either mode) lives here as "planned together"
/// until someone taps "watched" — at which point it moves to "watched
/// together" and lands in both people's personal diaries. Unlinking (which
/// used to sit on the Home card) lives in this screen's settings instead,
/// since it's a more deliberate action than the card's quick-glance state.
class CoViewingScreen extends StatefulWidget {
  const CoViewingScreen({super.key});

  @override
  State<CoViewingScreen> createState() => _CoViewingScreenState();
}

class _CoViewingScreenState extends State<CoViewingScreen> {
  CoViewList? _data;
  List<Suggestion> _suggestions = const [];
  bool _loading = true;
  String _tab = 'planned'; // 'planned' | 'watched' | 'suggested'
  final Set<String> _markingWatched = {};
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final app = context.read<AppState>();
      // Suggestions are per-account (whatever the partner has sent this
      // account that hasn't been dismissed/accepted yet) — fetched
      // alongside the shared planned/watched split so this screen is the
      // one place to both see and act on everything co-viewing related,
      // instead of only from the Home card's popup.
      final results = await Future.wait([
        app.partner.coViewing(),
        app.partner.suggestions(),
      ]);
      if (!mounted) return;
      setState(() {
        _data = results[0] as CoViewList;
        _suggestions = results[1] as List<Suggestion>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _acceptSuggestion(Suggestion s) async {
    if (_accepting) return;
    setState(() => _accepting = true);
    try {
      await context.read<AppState>().partner.acceptSuggestion(s.id);
      if (!mounted) return;
      setState(() {
        _suggestions = _suggestions.where((x) => x.id != s.id).toList();
        _accepting = false;
      });
      // The accepted title is now planned together — refresh so it
      // shows up on the planned tab right away instead of on next visit.
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isCompany
            ? 'planned together — watch it whenever everyone\'s ready'
            : 'planned together — watch it whenever you\'re both ready')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't agree to that just now — try again")),
      );
    }
  }

  void _declineSuggestion(Suggestion s) {
    setState(() => _suggestions = _suggestions.where((x) => x.id != s.id).toList());
    context.read<AppState>().partner.dismiss(s.id).catchError((_) {
      // Best-effort — worst case it reappears on the next poll/visit.
    });
  }

  void _openSuggestionTitle(Suggestion s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TitleDetailScreen(
          mediaId: s.mediaId,
          source: s.source,
          mediaType: s.mediaType,
          seedTitle: s.displayTitle,
          seedPosterUrl: s.posterUrl,
        ),
      ),
    );
  }

  Future<void> _markWatched(CoViewEntry entry) async {
    setState(() => _markingWatched.add(entry.id));
    try {
      await context.read<AppState>().partner.markCoViewWatched(entry.id);
      await _load(silent: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't mark that watched — try again")),
      );
    } finally {
      if (mounted) setState(() => _markingWatched.remove(entry.id));
    }
  }

  /// Everyone else in the circle besides this account — prefer this
  /// over [CoViewList.partnerUsername] anywhere that needs to show or
  /// count who's actually in it, since that field only ever names the
  /// first of them. Falls back to it anyway if a stale/older payload
  /// ever comes back without `other_usernames` populated.
  List<String> _otherUsernames() {
    final data = _data;
    if (data == null) return const [];
    if (data.otherUsernames.isNotEmpty) return data.otherUsernames;
    return data.partnerUsername != null ? [data.partnerUsername!] : const [];
  }

  bool get _isCompany => _otherUsernames().length > 1;

  Future<void> _openHowItWorks() async {
    await showHowItWorksSheet(context);
  }

  /// Grows the existing pair into (or adds another seat to) the circle —
  /// the same [PartnerService.sendInvite] a friend's own profile already
  /// exposes, just reachable straight from here so growing the circle
  /// doesn't require first hunting down that friend's profile. Doesn't
  /// refresh `_data` on success since the new person only actually joins
  /// once they accept, same as any other pending invite.
  Future<void> _openAddToCircle() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: SeenlyPalette.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddToCircleSheet(excludeUsernames: _otherUsernames()),
    );
  }

  Future<void> _openSettings() async {
    final others = _otherUsernames();
    final isCompany = others.length > 1;
    await showModalBottomSheet(
      context: context,
      backgroundColor: SeenlyPalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _SettingsSheet(
        isCompany: isCompany,
        partnerUsername: _data?.partnerUsername,
        onUnlink: () async {
          Navigator.of(sheetContext).pop();
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: SeenlyPalette.paper,
              title: Text(
                isCompany
                    ? 'leave this co-viewing circle?'
                    : 'unlink from ${_data?.partnerUsername ?? 'your partner'}?',
                style: SeenlyText.serif(size: 16),
              ),
              content: Text(
                isCompany
                    ? "you'll leave the circle — everyone else keeps it going, and "
                        "what's already in your own diary stays put."
                    : 'this closes co-viewing between you two — what\'s already in '
                        'each of your diaries stays put.',
                style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text('cancel', style: SeenlyText.mono(size: 11)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(isCompany ? 'leave' : 'unlink', style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
          try {
            await context.read<AppState>().partner.unlink();
            if (!mounted) return;
            Navigator.of(context).pop();
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("couldn't unlink just now — try again")),
            );
          }
        },
      ),
    );
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
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    ),
                  ),
                  const Spacer(),
                  PressScale(
                    onTap: _openHowItWorks,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.help_outline, size: 18, color: SeenlyPalette.inkMuted),
                    ),
                  ),
                  PressScale(
                    onTap: _openSettings,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.tune, size: 18, color: SeenlyPalette.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Expanded(
                child: Center(
                  child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
                ),
              )
            else if (_data == null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Entrance(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("couldn't load co-viewing",
                              style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.inkMuted)),
                          const SizedBox(height: 14),
                          PrimaryButton(label: 'try again', onTap: _load, expand: false),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  color: SeenlyPalette.accent,
                  onRefresh: () => _load(silent: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Entrance(
                          child: _CozyHeader(
                            myUsername: _data!.myUsername,
                            otherUsernames: _otherUsernames(),
                            onAdd: _openAddToCircle,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 22),
                        child: EveningPlanCard(coViewingByDefault: true),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: CoViewDecideCard(onChanged: () => _load(silent: true)),
                      ),
                      const SizedBox(height: 18),
                      // Same full-width underline tabs as Profile's own
                      // watched / plan to watch switch — this screen's
                      // "planned" is that same idea (things you've both
                      // said yes to but haven't watched), just shared.
                      UnderlineTabRow(
                        labels: [
                          'planned',
                          'watched',
                          _suggestions.isEmpty ? 'suggested' : 'suggested (${_suggestions.length})',
                        ],
                        activeIndex: _tab == 'planned' ? 0 : (_tab == 'watched' ? 1 : 2),
                        onChanged: (i) => setState(
                          () => _tab = i == 0 ? 'planned' : (i == 1 ? 'watched' : 'suggested'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _tab == 'planned'
                                ? '${_data!.planned.length} titles'
                                : _tab == 'watched'
                                    ? '${_data!.watched.length} titles'
                                    : '${_suggestions.length} waiting on you',
                            key: ValueKey(_tab),
                            style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
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
                          child: KeyedSubtree(
                            key: ValueKey(_tab),
                            child: _tab == 'planned'
                                ? _plannedGrid()
                                : _tab == 'watched'
                                    ? _watchedGrid()
                                    : _suggestedList(),
                          ),
                        ),
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

  Widget _plannedGrid() {
    final items = _data!.planned;
    if (items.isEmpty) {
      return _EmptyNote(
        text: _isCompany
            ? 'nothing planned yet — heart a title for tonight, or shuffle '
                'through Watch Together and whatever everyone says yes to shows up here.'
            : 'nothing planned yet — heart a title for tonight, or shuffle '
                'through Watch Together and whatever you both say yes to shows up here.',
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 2 / 3,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        return ScrollRevealEntrance(
          index: i,
          child: Stack(
            children: [
              ThemedPosterTile(
                title: e.displayTitle,
                posterUrl: e.posterUrl,
                mediaType: e.mediaType,
                fallbackColor: SeenlyPalette.gridColorFor(i),
                onTap: () => showPlannedPreview(
                  context,
                  PlannedPreviewData.fromCoViewEntry(e),
                  onMarkedWatched: () => _load(silent: true),
                  onMarkWatched: () => context.read<AppState>().partner.markCoViewWatched(e.id),
                  actionLabel: 'mark as watched together',
                  placeholderText: _isCompany
                      ? "planned together — mark it once everyone's watched it."
                      : 'planned together — mark it once you both watch it.',
                ),
                badge: _MarkWatchedBadge(
                  busy: _markingWatched.contains(e.id),
                  onTap: () => _markWatched(e),
                ),
              ),
              // A scheduled evening (from the co-viewing toggle in "plan
              // an evening") gets its date shown right on the tile — the
              // whole point of syncing the schedule over is so the
              // partner sees *when*, not just *that*, without opening
              // each poster to check.
              if (e.scheduledDate != null)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.ink.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _scheduledChipLabel(e),
                        style: SeenlyText.mono(size: 9.5, weight: FontWeight.w600, color: SeenlyPalette.paper),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static const _plannedChipMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _scheduledChipLabel(CoViewEntry e) {
    final date = e.scheduledDate!;
    final label = '${_plannedChipMonths[date.month - 1]} ${date.day}';
    final time = e.scheduledTimeLabel;
    return time != null ? '$label · $time' : label;
  }

  Widget _watchedGrid() {
    final items = _data!.watched;
    if (items.isEmpty) {
      return _EmptyNote(
        text: _isCompany
            ? "nothing marked watched together yet — it'll collect here, "
                "and in everyone's diary, once you do."
            : 'nothing marked watched together yet — it\'ll collect here, '
                'and in both your diaries, once you do.',
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 2 / 3,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => ScrollRevealEntrance(
        index: i,
        child: ThemedPosterTile(
          title: items[i].displayTitle,
          posterUrl: items[i].posterUrl,
          mediaType: items[i].mediaType,
          fallbackColor: SeenlyPalette.gridColorFor(i),
          onTap: () {
            final watchedWith = _CozyHeader._joinNames(_otherUsernames());
            showWatchedPreview(
              context,
              WatchedPreviewData.fromCoViewEntry(
                items[i],
                watchedWith: watchedWith.isEmpty ? null : watchedWith,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Whatever the partner has sent over with "suggest this for tonight"
  /// and this account hasn't answered yet — same list the Home card's
  /// popup already showed, just living here too so it doesn't need a
  /// trip back to Home to accept or decline one. Same 2-up poster grid
  /// as planned/watched (tap a poster to open its title card); accept/
  /// decline sit as a small button row under each poster instead of on
  /// the tile itself, since both need their own tap target next to
  /// the poster's.
  Widget _suggestedList() {
    if (_suggestions.isEmpty) {
      final others = _otherUsernames();
      final who = others.length > 1
          ? 'someone in your circle'
          : (others.isNotEmpty ? others.first : 'your partner');
      return _EmptyNote(
        text: 'nothing suggested yet — when $who '
            'suggests a title from any title page, it shows up here.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        final posterHeight = tileWidth * 3 / 2;
        const actionsHeight = 34.0;
        const actionsGap = 8.0;
        final aspectRatio = tileWidth / (posterHeight + actionsGap + actionsHeight);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemCount: _suggestions.length,
          itemBuilder: (context, i) {
            final s = _suggestions[i];
            return ScrollRevealEntrance(
              index: i,
              child: _SuggestedGridTile(
                suggestion: s,
                index: i,
                busy: _accepting,
                onOpen: () => _openSuggestionTitle(s),
                onAccept: () => _acceptSuggestion(s),
                onDecline: () => _declineSuggestion(s),
              ),
            );
          },
        );
      },
    );
  }
}

/// A pending suggestion shown as a poster tile — same look as the planned/
/// watched grids, so "suggested" doesn't read as a different kind of
/// screen. Tapping the poster opens the title card (`onOpen`); the accept
/// ("agree — watch it together") / decline pair sits in its own row right
/// under the poster, each with its own tap target so they don't fight
/// the poster's.
class _SuggestedGridTile extends StatelessWidget {
  final Suggestion suggestion;
  final int index;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _SuggestedGridTile({
    required this.suggestion,
    required this.index,
    required this.busy,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ThemedPosterTile(
            title: suggestion.displayTitle,
            posterUrl: suggestion.posterUrl,
            mediaType: suggestion.mediaType,
            fallbackColor: SeenlyPalette.gridColorFor(index),
            onTap: onOpen,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: Row(
            children: [
              Expanded(
                child: PressScale(
                  onTap: busy ? null : onAccept,
                  haptics: true,
                  child: Container(
                    decoration: BoxDecoration(
                      color: SeenlyPalette.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: busy
                          ? const SizedBox(
                              key: ValueKey('busy'),
                              width: 12,
                              height: 12,
                              child: ThemedLoadingIndicator(
                                  strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                            )
                          : const Icon(Icons.check, key: ValueKey('check'), size: 16, color: SeenlyPalette.accentOnAccent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: PressScale(
                  onTap: busy ? null : onDecline,
                  child: Container(
                    decoration: BoxDecoration(
                      color: SeenlyPalette.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SeenlyPalette.border),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, size: 16, color: SeenlyPalette.inkFaint),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A quiet, personal-feeling header — everyone's initial in a row, so
/// the screen reads as "ours" rather than another settings panel. A
/// couple is the common case (one heart between two initials, same as
/// always); once a third person's joined the circle, this fans out
/// into a small chain of initials-and-hearts and the names underneath
/// join into a list instead of a single "&".
class _CozyHeader extends StatelessWidget {
  final String myUsername;
  final List<String> otherUsernames;
  final VoidCallback onAdd;

  const _CozyHeader({
    required this.myUsername,
    required this.otherUsernames,
    required this.onAdd,
  });

  static String _joinNames(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    return '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
  }

  @override
  Widget build(BuildContext context) {
    final names = [myUsername, ...otherUsernames];
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: const BoxDecoration(color: SeenlyPalette.paper),
        child: Stack(
          children: [
            if (context.watch<RabbitMascotPrefsService>().enabled)
              Positioned(
                right: -10,
                bottom: -8,
                child: Opacity(
                  opacity: 0.9,
                  child: CoViewingBunniesCorner(size: 72),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              child: Column(
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < names.length; i++) ...[
                        if (i > 0) const Icon(Icons.favorite, size: 13, color: SeenlyPalette.accent),
                        _Initial(name: names[i]),
                      ],
                      // Sits right where "who's in this" is already shown,
                      // so growing the circle reads as an extension of that
                      // row rather than a separate settings-y action.
                      _AddSeatButton(onTap: onAdd),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _joinNames(names),
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(italic: true, size: 17),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    otherUsernames.length > 1 ? 'co-viewing circle' : 'co-viewing',
                    style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
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

/// The header row's "+" seat — a dashed circle so it reads as an empty,
/// inviting slot rather than another solid avatar, matching the same
/// dashed language [DashedBox] already uses elsewhere for "add
/// something here" affordances.
class _AddSeatButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSeatButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      haptics: true,
      child: DashedBox(
        radius: 20,
        color: SeenlyPalette.inkFaint,
        child: const SizedBox(
          width: 37,
          height: 37,
          child: Icon(Icons.add, size: 18, color: SeenlyPalette.inkFaint),
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String name;
  const _Initial({required this.name});

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: SeenlyPalette.accent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(letter,
          style: SeenlyText.serif(size: 16, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent)),
    );
  }
}

/// The "planned" grid's corner badge — same corner-badge language as the
/// active-journey tile on Profile (see `_WatchingNowTile`'s `badge:`
/// there), just doing a different job: a tap here calls `_markWatched`
/// directly, without opening the title first. Sits inside the poster
/// tile's own tap target, so its own GestureDetector needs to win the
/// gesture arena over the tile's — which, being the more deeply nested
/// one, it does.
class _MarkWatchedBadge extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _MarkWatchedBadge({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: busy ? null : onTap,
      haptics: true,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: SeenlyPalette.accent,
          shape: BoxShape.circle,
          border: Border.all(color: SeenlyPalette.paper, width: 1.5),
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: busy
              ? const SizedBox(
                  key: ValueKey('busy'),
                  width: 11,
                  height: 11,
                  child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                )
              : const Icon(Icons.check, key: ValueKey('check'), size: 13, color: SeenlyPalette.accentOnAccent),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Entrance(
        child: Text(text, style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkFaint)),
      ),
    );
  }
}

/// Picks a friend to invite straight into this circle — the same
/// [PartnerService.sendInvite] the "invite to co-viewing" pill on a
/// friend's own profile already uses, just reachable from the circle's
/// own screen instead of requiring a trip to that friend's profile
/// first. Friends already sharing this circle are left off the list
/// (matched by username — the only thing [CoViewList] exposes about
/// the others); friends with a pending outgoing invite already sent
/// show that instead of a live button, mirroring the friend-profile
/// screen's own "invite sent" state.
class _AddToCircleSheet extends StatefulWidget {
  final List<String> excludeUsernames;
  const _AddToCircleSheet({required this.excludeUsernames});

  @override
  State<_AddToCircleSheet> createState() => _AddToCircleSheetState();
}

class _AddToCircleSheetState extends State<_AddToCircleSheet> {
  bool _loading = true;
  List<Friend> _friends = const [];
  Set<String> _pendingUserIds = const {};
  final Set<String> _justSentUserIds = {};
  final Set<String> _busyUserIds = {};
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final app = context.read<AppState>();
      final results = await Future.wait([
        app.friends.list(),
        app.partner.invites(),
      ]);
      if (!mounted) return;
      final friendsData = results[0] as FriendsData;
      final invites = results[1] as PartnerInvites;
      final excluded = widget.excludeUsernames.toSet();
      setState(() {
        _friends = friendsData.friends.where((f) => !excluded.contains(f.username)).toList();
        _pendingUserIds = invites.outgoing.map((i) => i.userId).toSet();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = "couldn't load your friends — try again";
        _loading = false;
      });
    }
  }

  Future<void> _invite(Friend friend) async {
    setState(() => _busyUserIds.add(friend.userId));
    try {
      await context.read<AppState>().partner.sendInvite(friend.userId);
      if (!mounted) return;
      setState(() {
        _justSentUserIds.add(friend.userId);
        _busyUserIds.remove(friend.userId);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyUserIds.remove(friend.userId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyUserIds.remove(friend.userId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't send that invite — try again")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: SeenlyPalette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Entrance(
              child: Text('add to your circle', style: SeenlyText.sectionTitle),
            ),
            const SizedBox(height: 4),
            Entrance(
              delay: const Duration(milliseconds: 50),
              child: Text(
                "they'll join once they accept — same as any co-viewing invite.",
                style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
                ),
              )
            else if (_loadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_loadError!, style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted)),
                    const SizedBox(height: 10),
                    PrimaryButton(label: 'try again', onTap: _load, expand: false),
                  ],
                ),
              )
            else if (_friends.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  "everyone you're friends with is already here — add more "
                  "friends first, then invite them from here.",
                  style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _friends.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final f = _friends[i];
                    final sent = _justSentUserIds.contains(f.userId) || _pendingUserIds.contains(f.userId);
                    final busy = _busyUserIds.contains(f.userId);
                    return Entrance(
                      delay: Duration(milliseconds: 40 * i),
                      riseBy: 14,
                      child: Row(
                        children: [
                          UserAvatar(
                            avatarUrl: f.avatarUrl,
                            avatarPreset: f.avatarPreset,
                            fallbackLetter: f.username.isNotEmpty ? f.username[0].toUpperCase() : '?',
                            size: 40,
                            borderColor: Colors.transparent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(f.nameForDisplay, style: SeenlyText.serif(size: 14)),
                          ),
                          PressScale(
                            onTap: (sent || busy) ? null : () => _invite(f),
                            haptics: true,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: sent ? SeenlyPalette.background : SeenlyPalette.accent,
                                borderRadius: BorderRadius.circular(10),
                                border: sent ? Border.all(color: SeenlyPalette.border) : null,
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: busy
                                    ? const SizedBox(
                                        key: ValueKey('busy'),
                                        width: 12,
                                        height: 12,
                                        child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                                      )
                                    : Text(
                                        sent ? 'invite sent' : 'invite',
                                        key: ValueKey(sent),
                                        style: SeenlyText.mono(
                                          size: 11,
                                          color: sent ? SeenlyPalette.inkFaint : SeenlyPalette.accentOnAccent,
                                        ),
                                      ),
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

class _SettingsSheet extends StatelessWidget {
  final bool isCompany;
  final String? partnerUsername;
  final VoidCallback onUnlink;
  const _SettingsSheet({required this.isCompany, this.partnerUsername, required this.onUnlink});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: SeenlyPalette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Entrance(
              child: Text('co-viewing settings', style: SeenlyText.sectionTitle),
            ),
            const SizedBox(height: 16),
            Entrance(
              delay: const Duration(milliseconds: 60),
              riseBy: 12,
              child: PressScale(
                onTap: onUnlink,
                child: Row(
                  children: [
                    Icon(isCompany ? Icons.logout : Icons.link_off, size: 16, color: SeenlyPalette.coral),
                    const SizedBox(width: 10),
                    Text(
                      isCompany ? 'leave this circle' : 'unlink from ${partnerUsername ?? 'partner'}',
                      style: SeenlyText.serif(size: 14, color: SeenlyPalette.coral),
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
