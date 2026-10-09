import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/achievement.dart';
import '../../models/co_view_entry.dart';
import '../../models/friend.dart';
import '../../models/partner_status.dart';
import '../../models/shared_diary.dart';
import '../../models/suggestion.dart';
import '../../services/api_client.dart';
import '../../services/app_translations.dart';
import '../../services/error_text.dart';
import '../../services/friends_service.dart';
import '../../services/locale_service.dart';
import '../../services/partner_service.dart';
import '../../services/pair_album_service.dart';
import '../../models/pair_album.dart';
import 'album/album_home_screen.dart';
import 'room/room_entry_card.dart';
import 'album/album_reveal_coordinator.dart';
import 'album/album_strings.dart' as album_strings;
import 'album/note_compose_sheet.dart';
import '../../services/log_theme_service.dart';
import '../../services/premium_service.dart';
import '../../services/shared_diary_service.dart';
import '../../theme/palette.dart';
import '../../theme/seenly_skin.dart';
import '../../theme/text_styles.dart';
import '../../widgets/achievement_badge.dart';
import '../../widgets/challenge_card.dart' show SoftProgressBar;
import '../../widgets/couple_achievement_unlock.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/evening_plan_card.dart';
import '../../widgets/how_it_works_sheet.dart';
import '../../widgets/log_timeline.dart';
import '../../widgets/plan_evening_sheet.dart';
import '../../widgets/plan_outgrown_sheet.dart';
import '../../widgets/premium_upsell_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/spend_confirm_sheet.dart';
import '../../widgets/taste_match_card.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/themed_pull_to_refresh.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/watched_preview_sheet.dart';
import '../../widgets/wow_motion.dart';
import '../add_entry/watching_choice_screen.dart';
import '../premium/evenings_book_screen.dart' show EveningsBookEntryCard;
import '../profile/wrapped_screen.dart';
import '../search/search_screen.dart';
import '../title/title_detail_screen.dart';
import 'co_view_decide_method_screen.dart';
import '../../theme/clay_kit.dart';

// Mirrors backend/app/sincerity.py::SPOILER_UNLOCK_COST — small and
// stable enough that duplicating it here (rather than a round trip
// just to read it) is the simpler tradeoff; the backend is still the
// one source of truth that actually charges it. Top-level so both
// _CoViewHubScreenState (the confirm sheet) and _PersonChipState (the
// chip label) can read the same value.
const _spoilerUnlockCost = 2;

/// The co-viewing *mode* — everything a pair does together, on one screen.
///
/// This exists because co-viewing used to be a card on Home plus a
/// scattering of separate screens (suggest, vote, poll, plan), and the one
/// thing it never had was the thing a couple actually accumulates: a
/// shared history. Three tabs, in the order a couple moves through them:
///
///   вместе    — tonight: anything suggested and waiting on you, "не можем
///               выбрать", "запланировать вечер", and the planned queue
///               (with a quick "watched" tap right on each poster)
///   дневник   — everything you've watched together, or shared with each
///               other; two people's ratings on one card
///   мы        — "наш год": hours, genres, where your tastes diverge
///
/// This used to be two different screens — this one, plus a separate
/// full-screen CoViewingScreen reachable from the Home card — that had
/// drifted apart: suggestions, "plan an evening" and settings only lived
/// on the other one. They're merged now: this screen is the single,
/// complete co-viewing surface, and CoViewingScreen (see
/// co_viewing_screen.dart) is just a thin pushed-route wrapper around this
/// same content for the entry points that need a back button instead of
/// a tab.
///
/// Normally reached from the You/Co-viewing switch at the top of Home (see
/// screens/shell/home_mode_shell.dart) rather than pushed as a route, so
/// switching back and forth keeps scroll position and doesn't stack. Pass
/// [onBack] to instead render a small back-arrow row above the header —
/// that's what CoViewingScreen does when it wraps this for a pushed route.
class CoViewHubScreen extends StatefulWidget {
  final VoidCallback? onBack;

  /// Called once the person has left the circle from this screen's own
  /// settings. Whoever hosts the screen needs to hear it: the "вы и .."
  /// switch has to hide itself and drop back to plain Home, and the pushed
  /// route (CoViewingScreen) has to close — otherwise both would keep
  /// showing a co-viewing screen for a circle that's gone.
  final VoidCallback? onUnlinked;

  const CoViewHubScreen({super.key, this.onBack, this.onUnlinked});

  @override
  State<CoViewHubScreen> createState() => _CoViewHubScreenState();
}

class _CoViewHubScreenState extends State<CoViewHubScreen> {
  late final SharedDiaryService _shared = SharedDiaryService(ApiClient.instance);
  late final PartnerService _partner = PartnerService(ApiClient.instance);
  late final PairAlbumService _album = PairAlbumService(ApiClient.instance);

  int _tab = 0;

  // Sealed album notes by "source:mediaId" — what the planned cards dress
  // themselves with ("you left one" / "they left one"). Best-effort: an
  // album that fails to load just means plain cards.
  Map<String, AlbumPage> _notes = const {};
  // The album's status as last fetched — null until it loads (or if it
  // can't), in which case the note sheet lets the server decide.
  AlbumStatus? _albumStatus;

  PartnerStatus? _status;
  SharedDiaryPage? _diary;
  SharedPlanned? _planned;
  SharedStats? _stats;
  List<Suggestion> _suggestions = const [];
  List<CircleCompatibility> _compatibility = const [];
  List<Achievement> _coupleAchievements = const [];

  bool _loading = true;
  bool _loadingMore = false;
  final Set<String> _markingWatched = {};
  final Set<String> _nudging = {};  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final status = await _partner.status();
      if (!mounted) return;
      if (!status.linked) {
        // No circle yet — nothing else is fetchable, and every /shared
        // endpoint would 409. Bail out to the invite state rather than
        // firing four doomed requests.
        setState(() {
          _status = status;
          _loading = false;
          _error = null;
        });
        return;
      }
      final results = await Future.wait([
        _shared.diary(),
        _shared.planned(),
        _shared.stats(),
        _partner.suggestions(),
        _partner.compatibility(),
        _shared.achievements(),
      ]);
      if (!mounted) return;
      setState(() {
        _status = status;
        _diary = results[0] as SharedDiaryPage;
        _planned = results[1] as SharedPlanned;
        _stats = results[2] as SharedStats;
        _suggestions = results[3] as List<Suggestion>;
        _compatibility = results[4] as List<CircleCompatibility>;
        _coupleAchievements = (results[5] as AchievementsResponse).achievements;
        _loading = false;
        _error = null;
      });
      // Best-effort, fire-and-forget — never blocks this screen's own
      // loading state on a second network round trip; see the
      // function's own doc for why a fresh-badge celebration belongs
      // here rather than only after logging an evening.
      unawaited(checkAndCelebrateNewCoupleAchievements(context));
      unawaited(_loadAlbumNotes());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  /// Sealed album notes for the planned cards. A circle of three or more
  /// has no album, so nothing is asked of the server for one.
  Future<void> _loadAlbumNotes() async {
    if (_isCompany) {
      if (mounted && _notes.isNotEmpty) setState(() => _notes = const {});
      return;
    }
    try {
      final results = await Future.wait<Object>([_album.waitingNotes(), _album.status()]);
      if (!mounted) return;
      final pages = results[0] as List<AlbumPage>;
      setState(() {
        _notes = {for (final p in pages) p.key: p};
        _albumStatus = results[1] as AlbumStatus;
      });
    } catch (_) {
      // Plain cards are a fine fallback.
    }
  }

  String get _partnerLabel => _status?.partnerUsername ?? album_strings.at('партнёр', 'partner');

  /// Opens the note sheet for a planned title — write, rewrite or take back
  /// *my* note; the partner's side is only ever a sealed envelope here.
  Future<void> _openNote(CoViewEntry entry) async {
    final existing = _notes['${entry.source}:${entry.mediaId}'];
    final result = await showNoteComposeSheet(
      context,
      item: entry.toMediaItem(),
      partnerName: _partnerLabel,
      status: _albumStatus,
      existing: existing,
    );
    if (result != null && mounted) await _loadAlbumNotes();
  }

  Future<void> _loadMore() async {
    final page = _diary;
    if (page == null || !page.hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _shared.diary(before: page.nextBefore);
      if (!mounted) return;
      setState(() {
        _diary = SharedDiaryPage(
          items: [...page.items, ...next.items],
          nextBefore: next.nextBefore,
          memberUsernames: page.memberUsernames,
        );
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _unshare(SharedDiaryItem item) async {
    final mine = item.me;
    if (mine == null) return;
    try {
      final page = await _shared.setShared(mine.entryId, false);
      if (!mounted) return;
      setState(() => _diary = page);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _revealRating(SharedDiaryPerson person) async {
    final confirmed = await SpendConfirmSheet.show(
      context,
      title: 'открыть оценку?'.tr,
      body: '${person.name} ${'уже оценил(а) этот тайтл. посмотреть сейчас — или оценить сначала самому и получить очки за собственное мнение?'.tr}',
      cost: _spoilerUnlockCost,
      confirmLabel: 'открыть'.tr,
    );
    if (!confirmed || !mounted) return;
    try {
      final page = await _shared.revealRating(person.entryId);
      if (!mounted) return;
      setState(() => _diary = page);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  // Mirrors backend/app/sincerity.py::NUDGE_COST/NUDGE_STALE_THRESHOLD —
  // same tradeoff as _spoilerUnlockCost above. _isNudgeable decides
  // whether the tile even shows the nudge affordance; the backend is
  // still the one that actually enforces the threshold and cooldown.
  static const _nudgeCost = 1;
  static const _nudgeStaleThreshold = Duration(days: 21);

  bool _isNudgeable(CoViewEntry entry) {
    if (entry.scheduledDate != null) return false; // already has a plan — nothing to nudge about
    return DateTime.now().toUtc().difference(entry.createdAt.toUtc()) >= _nudgeStaleThreshold;
  }

  Future<void> _nudge(CoViewEntry entry) async {
    if (_nudging.contains(entry.id)) return;
    final confirmed = await SpendConfirmSheet.show(
      context,
      title: 'напомнить о плане?'.tr,
      body: '«${entry.displayTitle}» ${'висит в общих планах без движения. отправить остальным один пуш с напоминанием?'.tr}',
      cost: _nudgeCost,
      confirmLabel: 'напомнить'.tr,
    );
    if (!confirmed || !mounted) return;
    setState(() => _nudging.add(entry.id));
    try {
      final page = await _shared.nudge(entry.id);
      if (!mounted) return;
      setState(() => _planned = page);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _nudging.remove(entry.id));
    }
  }

  // --- suggestions ------------------------------------------------------

  bool get _isCompany => _status?.isCompany ?? false;

  /// Everyone else in the circle besides this account, in display order.
  List<PartnerMember> _otherMembers() =>
      (_status?.members ?? const []).where((m) => !m.isYou).toList();

  /// Approving a suggestion opens the exact same "plan an evening" ritual
  /// as anywhere else (see showPlanEveningSheet's approvingSuggestion
  /// mode) instead of silently adding it to "запланировано" with no
  /// date — agreeing to watch it together *is* planning that evening,
  /// so it gets the same "when?" step. Refreshes both suggestions and
  /// the planned queue from the server once the sheet closes, rather
  /// than trusting a return value, since that's true either way: nothing
  /// changed if they backed out, and both lists reflect it either way if
  /// they actually confirmed.
  Future<void> _acceptSuggestion(Suggestion s) async {
    await showPlanEveningSheet(context, approvingSuggestion: s);
    if (!mounted) return;
    try {
      final fresh = await _partner.suggestions();
      if (!mounted) return;
      setState(() => _suggestions = fresh);
    } catch (_) {
      // Best-effort — the next natural refresh picks it up.
    }
    await _load(silent: true);
  }

  void _declineSuggestion(Suggestion s) {
    setState(() => _suggestions = _suggestions.where((x) => x.id != s.id).toList());
    _partner.dismiss(s.id).catchError((_) {
      // Best-effort — worst case it reappears on the next refresh.
    });
  }

  void _openPlannedTitle(CoViewEntry e) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TitleDetailScreen(
          mediaId: e.mediaId,
          source: e.source,
          mediaType: e.mediaType,
          seedTitle: (LocaleService.appIsRussian ? e.titleRu : e.titleEn) ??
              e.titleEn ??
              e.titleRu ??
              '—',
          seedPosterUrl: e.posterUrl,
        ),
      ),
    );
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

  /// The planned card's "смотрю" button — sends the person through the
  /// exact same logging ritual as everywhere else in the app (see
  /// WatchingChoiceScreen: already-watched vs watching-now, then the
  /// themed rating screen), pre-checking its "watched with partner"
  /// toggle since a title on *this* list is demonstrably a shared one.
  /// Only once that ritual actually saves something (`saved == true`)
  /// does this drop the entry off "запланировано" — via
  /// `already_logged: true`, so the rating screen's own diary write
  /// isn't duplicated (see PartnerService.markCoViewWatched's own doc
  /// comment).
  Future<void> _openPlannedLogging(CoViewEntry entry) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WatchingChoiceScreen(item: entry.toMediaItem(), initialWatchedWithPartner: true),
      ),
    );
    if (saved != true) return;
    if (!mounted) return;
    setState(() => _markingWatched.add(entry.id));
    try {
      final watched = await _partner.markCoViewWatched(entry.id, alreadyLogged: true);
      // No celebration here: the logging ritual that just saved already
      // ended with one (see the themed log screens' closing flourish),
      // with the partner's name on it — a second would be a repeat. The
      // one exception is a sealed album note that this very call just
      // unsealed: that's its own moment, and it plays now.
      await _load(silent: true);
      if (mounted) {
        await playRevealIfAny(context, watched: watched, partnerName: _partnerLabel);
        if (mounted) await _loadAlbumNotes();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('логировали, но не получилось убрать из «запланировано» — попробуйте ещё раз'.tr)),
      );
    } finally {
      if (mounted) setState(() => _markingWatched.remove(entry.id));
    }
  }

  // --- header actions: how it works / add to circle / settings ----------

  Future<void> _openHowItWorks() async {
    await showHowItWorksSheet(context);
  }

  /// Grows the pair into (or adds another seat to) the circle. A couple —
  /// two people — stays free forever; growing past that is premium (see
  /// PremiumService.canGrowCoViewCircle).
  Future<void> _openAddToCircle() async {
    final currentSize = _otherMembers().length + 1; // + self
    if (!context.read<PremiumService>().canGrowCoViewCircle(currentSize)) {
      await showPremiumUpsellSheet(
        context,
        triggerSource: 'co_view_circle_size',
        initialKind: PremiumPlanKind.family,
        icon: Icons.people_outline,
        title: 'круг побольше — это премиум'.tr,
        message: ('пара всегда бесплатно — с премиумом можно смотреть вместе '
            'компанией, втроём и больше').tr,
      );
      return;
    }
    final premium = context.read<PremiumService>();
    if (premium.circleOutgrowsPlan(currentSize)) {
      final proceed = await confirmCircleOutgrowsPlan(context, premium: premium);
      if (!proceed || !mounted) return;
    }
    await showModalBottomSheet(
      context: context,
      backgroundColor: SeenlyPalette.paper,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddToCircleSheet(
        excludeUsernames: _otherMembers().map((m) => m.username).toList(),
      ),
    );
  }

  Future<void> _openSettings() async {
    final isCompany = _isCompany;
    await showModalBottomSheet(
      context: context,
      backgroundColor: SeenlyPalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _CoViewSettingsSheet(
        isCompany: isCompany,
        partnerUsername: _status?.partnerUsername,
        onUnlink: () async {
          Navigator.of(sheetContext).pop();
          // The album goes with the link — say so, and only when there is
          // something in it to lose. A failed lookup just means the plain
          // warning.
          var albumHasContent = false;
          if (!isCompany) {
            try {
              albumHasContent = (await _album.status()).hasContent;
            } catch (_) {}
          }
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: SeenlyPalette.paper,
              title: Text(
                isCompany
                    ? 'покинуть этот круг совместного просмотра?'.tr
                    : album_strings.at(
                        'разорвать связь с ${_status?.partnerUsername ?? "партнёром"}?',
                        'end the link with ${_status?.partnerUsername ?? "your partner"}?',
                      ),
                style: SeenlyText.serif(size: 16),
              ),
              content: Text(
                isCompany
                    ? ('вы покинете круг — остальные продолжат, а то, что уже '
                        'в вашем собственном дневнике, останется на месте.').tr
                    : ('это закроет совместный просмотр между вами — то, что уже '
                            'есть в дневниках у каждого, останется на месте.')
                        .tr +
                        (albumHasContent
                            ? '\n\n${('а вот альбом пары — записки, капсулы и дата годовщины — '
                                    'исчезнет у вас обоих, и вернуть его будет нельзя.')
                                .tr}'
                            : ''),
                style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text('отмена'.tr, style: SeenlyText.mono(size: 11)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(isCompany ? 'покинуть'.tr : 'разорвать'.tr,
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
          try {
            await _partner.unlink();
            if (!mounted) return;
            await _load();
            widget.onUnlinked?.call();
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('не получилось разорвать связь — попробуйте ещё раз'.tr)),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: ThemedLoadingIndicator());
    }
    if (_error != null) {
      return _Retry(message: _error!, onRetry: _load);
    }
    final status = _status;
    if (status == null || !status.linked) {
      return _NotLinkedState(onLinked: _load, onBack: widget.onBack);
    }

    return ThemedPullToRefresh(
      onRefresh: () => _load(silent: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.onBack != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: PressScale(
                  onTap: widget.onBack,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _Header(
              status: status,
              stats: _stats,
              onAdd: _openAddToCircle,
              onHelp: _openHowItWorks,
              onSettings: _openSettings,
            ),
          ),
          // The room, on top of every tab and bigger than anything else
          // here: watching together is the point of the screen.
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: RoomHeroSection(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: UnderlineTabRow(
                labels: ['вместе'.tr, 'дневник'.tr, 'мы'.tr],
                activeIndex: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
          ),
          ..._tabSlivers(),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  List<Widget> _tabSlivers() {
    switch (_tab) {
      case 1:
        return _diarySlivers();
      case 2:
        return _statsSlivers();
      default:
        return _tonightSlivers();
    }
  }

  // --- вместе ---------------------------------------------------------

  List<Widget> _tonightSlivers() {
    final planned = _planned;
    return [
      // Whatever the other side has sent over with "suggest this for
      // tonight" and this account hasn't answered yet — sits right at
      // the top since it's the one thing here that's actually waiting
      // on you. Nothing rendered at all when there's nothing pending,
      // so an empty inbox doesn't clutter the tab.
      if (_suggestions.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SectionHeader(
              title: _suggestions.length == 1
                  ? 'вам предложили'.tr
                  : '${'вам предложили'.tr} (${_suggestions.length})',
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _SuggestionCard(
                suggestion: _suggestions[i],
                busy: false,
                onOpen: () => _openSuggestionTitle(_suggestions[i]),
                onAccept: () => _acceptSuggestion(_suggestions[i]),
                onDecline: () => _declineSuggestion(_suggestions[i]),
              ),
            ),
            childCount: _suggestions.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
      ],
      // Plain search over everything (films, series, games, ...) — the same
      // SearchScreen as Home's and the diary's, so a pair can find the title
      // they have in mind without leaving this tab first.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _SearchPill(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: _DecideCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CoViewDecideMethodScreen()),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: EveningPlanCard(coViewingByDefault: true, onlyCoViewing: true),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: SectionHeader(title: 'запланировано'.tr),
        ),
      ),
      if (planned != null && planned.limit != null)
        SliverToBoxAdapter(child: _QueueMeter(planned: planned)),
      if (planned == null || planned.planned.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'пока пусто — добавьте что-нибудь сердечком на странице фильма'.tr,
              style: SeenlyText.emptyState(),
            ),
          ),
        )
      else
        // The same big two-across poster grid the rest of the app uses
        // (lists, profile, friends): posters first, the title card one
        // tap away, and a "смотрю" button along the bottom to run the
        // normal logging ritual (see WatchingChoiceScreen) without
        // going there first.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 2 / 3,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final entry = planned.planned[i];
                return Entrance(
                  key: ValueKey<String>('planned-${entry.id}'),
                  delay: Duration(milliseconds: 45 * (i % 6)),
                  duration: const Duration(milliseconds: 440),
                  riseBy: 14,
                  child: _PlannedTile(
                    entry: entry,
                    index: i,
                    busy: _markingWatched.contains(entry.id),
                    onOpen: () => _openPlannedTitle(entry),
                    onLog: () => _openPlannedLogging(entry),
                    onNudge: _isNudgeable(entry) ? () => _nudge(entry) : null,
                    nudging: _nudging.contains(entry.id),
                    note: _isCompany ? null : _notes['${entry.source}:${entry.mediaId}'],
                    onNote: _isCompany ? null : () => _openNote(entry),
                  ),
                );
              },
              childCount: planned.planned.length,
            ),
          ),
        ),
    ];
  }

  // --- дневник --------------------------------------------------------

  List<Widget> _diarySlivers() {
    final page = _diary;
    if (page == null || page.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 10),
            child: Column(
              children: [
                Icon(Icons.auto_stories_outlined,
                    size: 28, color: SeenlyPalette.inkFaint),
                const SizedBox(height: 12),
                Text(
                  'здесь будут ваши общие вечера'.tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(
                      size: 15, italic: true, color: SeenlyPalette.inkMuted),
                ),
                const SizedBox(height: 6),
                Text(
                  ('отметьте что-нибудь просмотренным вместе — или включите '
                  '«записывать мои вечера в общий дневник» в настройках').tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    // Grouped by day and threaded onto the same dashed timeline the
    // personal diary uses (see LogDayGroup/ScrapbookEntry in
    // log_timeline.dart) — this tab is a diary too, just a shared one,
    // so it gets the same scrapbook feel (tilt, washi tape, scroll-in
    // reveal) rather than a plain list of cards.
    final grouped = <String, List<SharedDiaryItem>>{};
    for (final item in page.items) {
      grouped.putIfAbsent(_sharedDayLabel(item.watchedAt), () => []).add(item);
    }
    final logTheme = context.watch<LogThemeService>().theme;
    var tapeCursor = 0;
    final dayGroups = <Widget>[];
    for (final key in grouped.keys) {
      final dayItems = grouped[key]!;
      dayGroups.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: LogDayGroup(
            theme: logTheme,
            dayLabel: key,
            tapeStartIndex: tapeCursor,
            entries: [
              for (final item in dayItems)
                _SharedEntryCard(
                  item: item,
                  onOpen: () => _openSharedEntry(item),
                  onUnshare: item.me != null && !item.watchedTogether
                      ? () => _unshare(item)
                      : null,
                  onReveal: (p) => _revealRating(p),
                ),
            ],
          ),
        ),
      ));
      tapeCursor += dayItems.length;
    }

    return [
      ...dayGroups,
      if (page.hasMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Center(
              child: _loadingMore
                  ? const ThemedLoadingIndicator(size: 26)
                  : PressScale(
                      onTap: _loadMore,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        child: Text('показать ещё'.tr,
                            style: SeenlyText.mono(
                                size: 12, color: SeenlyPalette.accent)),
                      ),
                    ),
            ),
          ),
        ),
    ];
  }

  void _openTitle(SharedDiaryItem item) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TitleDetailScreen(
        mediaId: item.mediaId,
        source: item.source,
        mediaType: item.mediaType,
        seedTitle: item.title(LocaleService.appIsRussian),
        seedPosterUrl: item.posterUrl,
      ),
    ));
  }

  /// Tapping a card on the "дневник" tab — same stop the personal
  /// diary's own rows open on tap (see showWatchedPreview): a quiet
  /// look back at the evening with a way to edit this account's own
  /// rating/note or share it, rather than jumping straight to the
  /// title page the way this tab used to (that's still one tap away,
  /// via the poster inside the sheet).
  Future<void> _openSharedEntry(SharedDiaryItem item) async {
    await showWatchedPreview(
      context,
      WatchedPreviewData.fromSharedDiaryItem(item, ru: LocaleService.appIsRussian),
    );
    // An edit inside the sheet writes straight to this account's own
    // diary entry — refresh so the card behind it picks up the new
    // rating/note once the sheet closes.
    if (mounted) _load(silent: true);
  }

  String _sharedDayLabel(DateTime? d) {
    if (d == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'сегодня'.tr;
    if (diff == 1) return 'вчера'.tr;
    final months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ].map((m) => m.tr).toList();
    return '${d.day} ${months[d.month - 1]}';
  }

  // --- мы -------------------------------------------------------------

  List<Widget> _statsSlivers() {
    final stats = _stats;
    final hasStats = stats != null && !stats.isEmpty;
    final hasCompatibility = _compatibility.any((m) => m.tasteMatch != null);
    return [
      // The pair album — draws nothing for a company (an album is for
      // exactly two) and nothing until its own status has loaded.
      if (!_isCompany)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: AlbumEntryCard(),
          ),
        ),
      // The book of your evenings — for any circle, a pair or a company.
      // It loads nothing itself; the screen it opens does the work.
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: EveningsBookEntryCard(),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: const _CoupleWrappedEntry(),
        ),
      ),
      // Shown even before this circle has logged a single evening
      // together — unlike the shared-diary stats below, this reads
      // from each person's *own* watched/watching/wishlist history
      // (see backend/app/similarity.py), so a couple who just linked
      // and hasn't watched anything together yet still gets something
      // here on day one rather than a bare "no stats yet" message.
      if (hasCompatibility)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _CompatibilitySection(members: _compatibility),
          ),
        ),
      // Same "shown from day one" reasoning as compatibility above —
      // scored off the link's all-time rows (see
      // compute_couple_achievements_for_link server-side), not the
      // possibly-empty [stats] below, so a couple who just linked
      // still sees their very first badge's progress at 0 / 1.
      if (_coupleAchievements.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _CoupleBadgesSection(achievements: _coupleAchievements),
          ),
        ),
      if (hasStats)
        SliverToBoxAdapter(
          child: _StatsBody(
            stats: stats,
            onOpen: _openTitle,
            members: _status?.members ?? const [],
          ),
        )
      else
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              (hasCompatibility || _coupleAchievements.isNotEmpty) ? 10 : 34,
              24,
              10,
            ),
            child: Text(
              'статистика появится после первого общего вечера'.tr,
              textAlign: TextAlign.center,
              style: SeenlyText.emptyState(),
            ),
          ),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// "мы" tab — compatibility. One TasteMatchDetail card per circle member
// with an actual match to show (see similarity.compare's own docstring
// for what "no match yet" means) — a plain couple gets exactly one card,
// a company one per other seat, each labeled with who it's about.
// ---------------------------------------------------------------------------

class _CompatibilitySection extends StatelessWidget {
  final List<CircleCompatibility> members;
  const _CompatibilitySection({required this.members});

  @override
  Widget build(BuildContext context) {
    final withMatch = members.where((m) => m.tasteMatch != null).toList();
    if (withMatch.isEmpty) return const SizedBox.shrink();
    final single = withMatch.length == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in withMatch) ...[
          if (!single)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 2),
              child: Text(m.nameForDisplay, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
            ),
          TasteMatchDetail(match: m.tasteMatch!, compact: true),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final PartnerStatus status;
  final SharedStats? stats;
  final VoidCallback onAdd;
  final VoidCallback onHelp;
  final VoidCallback onSettings;
  const _Header({
    required this.status,
    this.stats,
    required this.onAdd,
    required this.onHelp,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final names = status.partnerUsername ?? 'вы вдвоём'.tr;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BreathingGlow(
            color: SeenlyPalette.pink,
            size: 30,
            period: const Duration(milliseconds: 5600),
            maxOpacity: 0.20,
            child: Icon(Icons.favorite_rounded, size: 16, color: SeenlyPalette.pink),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album_strings.at('вы и $names', 'you and $names'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.serif(size: 18, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  stats == null || stats!.eveningsTogether == 0
                      ? 'ваш общий дневник'.tr
                      : '${stats!.eveningsTogether} ${nOnly('nEvenings', stats!.eveningsTogether)} ${'вместе'.tr}',
                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
                ),
              ],
            ),
          ),
          // Who's in the circle — you first (matching "вы и .."), then the
          // others. Sits between the title and the buttons so the title
          // is what gives way (ellipsis) on a narrow screen, not the faces.
          if (status.members.isNotEmpty) ...[
            const SizedBox(width: 8),
            _MemberAvatarStack(members: status.members),
            const SizedBox(width: 6),
          ],
          // Circle management moved here from the old standalone screen —
          // reachable no matter how this screen is being shown, embedded
          // in Home's switch or pushed as its own route.
          _HeaderIconButton(icon: Icons.add, onTap: onAdd),
          const SizedBox(width: 2),
          _HeaderIconButton(icon: Icons.help_outline, onTap: onHelp),
          const SizedBox(width: 2),
          _HeaderIconButton(icon: Icons.tune, onTap: onSettings),
        ],
      ),
    );
  }
}

/// Overlapping avatars of everyone in the co-viewing circle, drawn in the
/// header. A couple shows both faces; a company of more than three shows
/// the first two plus a "+N" chip so the row never grows past three slots.
/// Each avatar gets a ring in the page-background colour so the overlap
/// reads as a clean cut rather than two borders fighting.
class _MemberAvatarStack extends StatelessWidget {
  final List<PartnerMember> members;
  const _MemberAvatarStack({required this.members});

  static const double _size = 26;
  static const double _ring = 1.5;
  static const double _step = 17; // horizontal advance per slot (overlap)
  static const int _maxSlots = 3;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();

    // "You" first, so the order matches the "вы и .." label beside it.
    final ordered = [
      ...members.where((m) => m.isYou),
      ...members.where((m) => !m.isYou),
    ];
    final overflow = ordered.length > _maxSlots ? ordered.length - (_maxSlots - 1) : 0;
    final shown = overflow > 0 ? ordered.take(_maxSlots - 1).toList() : ordered;

    const outer = _size + _ring * 2;
    final slots = shown.length + (overflow > 0 ? 1 : 0);
    final width = outer + (slots - 1) * _step;

    Widget ringed(Widget child) => Container(
          width: outer,
          height: outer,
          padding: const EdgeInsets.all(_ring),
          decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
          child: child,
        );

    return Semantics(
      label: ordered.map((m) => m.nameForDisplay).join(', '),
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: outer,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * _step,
                child: ringed(
                  UserAvatar(
                    avatarUrl: shown[i].avatarUrl,
                    avatarPreset: shown[i].avatarPreset,
                    fallbackLetter: shown[i].nameForDisplay.isNotEmpty
                        ? shown[i].nameForDisplay[0].toUpperCase()
                        : '?',
                    size: _size,
                    borderColor: Colors.transparent,
                  ),
                ),
              ),
            if (overflow > 0)
              Positioned(
                left: shown.length * _step,
                child: ringed(
                  Container(
                    decoration: BoxDecoration(color: SeenlyPalette.cork, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      '+$overflow',
                      style: SeenlyText.mono(
                          size: 11, weight: FontWeight.w500, color: SeenlyPalette.inkMuted, enforceFloor: false),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => PressScale(
        onTap: onTap,
        haptics: true,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 17, color: SeenlyPalette.inkMuted),
        ),
      );
}

// ---------------------------------------------------------------------------
// вместе
// ---------------------------------------------------------------------------

/// A pending suggestion from the other side, drawn as a row (it needs
/// room for the title, who suggested it and the accept/decline buttons
/// that a poster-grid tile has none of). Tapping the poster/title opens
/// the title card; accept/decline sit in their own row underneath since
/// both need their own tap target.
class _SuggestionCard extends StatelessWidget {
  final Suggestion suggestion;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _SuggestionCard({
    required this.suggestion,
    required this.busy,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: SeenlyPalette.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SeenlyPalette.accent.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onOpen,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: suggestion.posterUrl == null
                      ? Container(width: 38, height: 54, color: SeenlyPalette.cork)
                      : Image.network(
                          suggestion.posterUrl!,
                          width: 38,
                          height: 54,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(width: 38, height: 54, color: SeenlyPalette.cork),
                        ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${'предложил'.tr}${_gender(suggestion.senderUsername)} ${suggestion.senderUsername}',
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                      const SizedBox(height: 3),
                      Text(suggestion.displayTitle,
                          style: SeenlyText.cardTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  onTap: busy ? null : onAccept,
                  haptics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.accent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: busy
                          ? SizedBox(
                              key: const ValueKey('busy'),
                              width: 12,
                              height: 12,
                              child: ThemedLoadingIndicator(
                                  strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                            )
                          : Text(
                              'смотрим вместе'.tr,
                              key: const ValueKey('label'),
                              style: SeenlyText.mono(
                                  size: 10.5, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PressScale(
                onTap: busy ? null : onDecline,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.background,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: SeenlyPalette.border),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.close, size: 15, color: SeenlyPalette.inkFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Can't know anyone's gender from a username, so this stays neutral
  // rather than guessing.
  static String _gender(String _) => '';
}

/// A small, quiet search bar — tapping it opens the app's normal search
/// screen. Same look as the one at the top of the diary: a paper pill in
/// the standard skin, a squarer index card with a dashed edge in cozy.
class _SearchPill extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(SeenlySkin.isCozy ? 12 : 24),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: SeenlyPalette.inkFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'search a film, show, or game'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
            ),
          ),
        ],
      ),
    );
    return PressScale(
      onTap: onTap,
      haptics: true,
      child: SeenlySkin.isCozy
          ? DashedRoundedBorder(
              color: SeenlyPalette.dashedBorder,
              radius: 12,
              margin: const EdgeInsets.all(3),
              child: bar,
            )
          : bar,
    );
  }
}

class _DecideCard extends StatelessWidget {
  final VoidCallback onTap;
  const _DecideCard({required this.onTap});

  @override
  Widget build(BuildContext context) => PressScale(
        haptics: true,
        onTap: onTap,
        scaleTo: 0.98,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
          decoration: BoxDecoration(
            color: SeenlyPalette.accent.withOpacity(0.09),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: SeenlyPalette.accent.withOpacity(0.22)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('не можем выбрать'.tr,
                        style: SeenlyText.serif(
                            size: 17, italic: true, weight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('голосование, рулетка или спросить tanè'.tr,
                        style: SeenlyText.mono(
                            size: 11, color: SeenlyPalette.inkMuted)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded,
                  size: 17, color: SeenlyPalette.accent),
            ],
          ),
        ),
      );
}

/// "3 из 5" for the free tier's queue depth.
///
/// Framed as *how much room is left*, never as a locked feature: the limit
/// is a queue depth, not a paywall on co-watching (see
/// backend/app/routers/partner.py::CO_VIEW_FREE_LIMIT), and copy that
/// implied otherwise would be dishonest. The upsell only appears once the
/// queue is actually full, which is the only moment it's relevant.
class _QueueMeter extends StatelessWidget {
  final SharedPlanned planned;
  const _QueueMeter({required this.planned});

  @override
  Widget build(BuildContext context) {
    final full = planned.isFull;
    final limit = planned.limit ?? 5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SoftProgressBar(
                  value: limit == 0 ? 0 : planned.used / limit,
                  color: full ? SeenlyPalette.mustard : SeenlyPalette.sage,
                  height: 5,
                ),
              ),
              const SizedBox(width: 10),
              Text(album_strings.at('${planned.used} из $limit', '${planned.used} of $limit'),
                  style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  full
                      ? 'список полон — отметьте что-нибудь просмотренным, чтобы освободить место'.tr
                      : album_strings.at(
                          'в общем списке помещается $limit фильмов одновременно',
                          'the shared list holds $limit movies at a time',
                        ),
                  style: SeenlyText.mono(
                    size: 10.5,
                    color: full ? SeenlyPalette.mustard : SeenlyPalette.inkFaint,
                  ),
                ),
              ),
              if (full) ...[
                const SizedBox(width: 8),
                PressScale(
                  onTap: () => showPremiumUpsellSheet(
                    context,
                    triggerSource: 'co_view_list_limit',
                    icon: Icons.favorite_rounded,
                    title: 'безлимитный совместный список'.tr,
                    message: album_strings.at(
                      'бесплатно в общем списке помещается $limit фильмов '
                          'одновременно — этого хватает на пару вечеров вперёд. '
                          'с премиумом список не ограничен, а всё, что вы уже '
                          'посмотрели вместе, остаётся в общем дневнике навсегда '
                          'в любом случае.',
                      'for free the shared list holds $limit movies at a time — '
                          'enough for a couple of evenings ahead. with premium the '
                          'list is unlimited, and everything you\'ve already watched '
                          'together stays in the shared diary forever either way.',
                    ),
                  ),
                  child: Text('безлимит'.tr,
                      style: SeenlyText.mono(
                          size: 11,
                          weight: FontWeight.w700,
                          color: SeenlyPalette.accent)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One planned title as a big poster in the two-across grid. Tapping it
/// opens the title card; the "смотрю" button along the bottom runs the
/// normal logging ritual (see WatchingChoiceScreen) right from here,
/// pre-checked as watched together; and an evening planned for a
/// specific day carries that date on the poster itself, so it's visible
/// without opening anything.
class _PlannedTile extends StatelessWidget {
  final CoViewEntry entry;
  final int index;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onLog;
  final VoidCallback? onNudge;
  final bool nudging;
  // The sealed album note state for this title (null = no note either way)
  // and the handler that opens the note sheet. Both null for a company.
  final AlbumPage? note;
  final VoidCallback? onNote;

  const _PlannedTile({
    required this.entry,
    required this.index,
    required this.busy,
    required this.onOpen,
    required this.onLog,
    this.onNudge,
    this.nudging = false,
    this.note,
    this.onNote,
  });

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final title = (ru ? entry.titleRu : entry.titleEn) ?? entry.titleEn ?? entry.titleRu ?? '—';
    return Stack(
      children: [
        ThemedPosterTile(
          title: title,
          posterUrl: entry.posterUrl,
          mediaType: entry.mediaType,
          fallbackColor: SeenlyPalette.gridColorFor(index),
          onTap: onOpen,
        ),
        if (entry.scheduledDate != null)
          Positioned(
            left: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SeenlyPalette.ink.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _scheduledLabel(entry),
                  style: SeenlyText.mono(size: 9.5, weight: FontWeight.w600, color: SeenlyPalette.paper),
                ),
              ),
            ),
          ),
        if (onNudge != null)
          Positioned(
            right: 6,
            top: 6,
            child: PressScale(
              onTap: nudging ? null : onNudge,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SeenlyPalette.ink.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: nudging
                    ? SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.4, color: SeenlyPalette.paper),
                      )
                    : Icon(Icons.notifications_none_rounded, size: 14, color: SeenlyPalette.paper),
              ),
            ),
          ),
        if (onNote != null)
          Positioned(
            left: 6,
            bottom: 44,
            child: _NoteChip(note: note, onTap: onNote!),
          ),
        Positioned(
          left: 6,
          right: 6,
          bottom: 6,
          child: _LogButton(busy: busy, onTap: onLog),
        ),
      ],
    );
  }

  static List<String> get _months => [
        'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
      ].map((m) => m.tr).toList();

  String _scheduledLabel(CoViewEntry e) {
    final date = e.scheduledDate!;
    final label = '${date.day} ${_months[date.month - 1]}';
    final time = e.scheduledTimeLabel;
    return time != null ? '$label · $time' : label;
  }
}

/// The little envelope on a planned poster: tap to write (or reopen) *my*
/// note for this evening. Three looks — nothing yet (a pencil), mine is
/// written (a check, plus a pulsing envelope if the partner left one too),
/// and only the partner's is waiting (a pulsing envelope, nudging you to
/// answer with your own).
class _NoteChip extends StatelessWidget {
  final AlbumPage? note;
  final VoidCallback onTap;
  const _NoteChip({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final mine = note?.mine != null;
    final theirs = note?.partnerSealed ?? false;
    final Color bg = mine ? SeenlyPalette.sage : (theirs ? SeenlyPalette.coral : SeenlyPalette.ink.withOpacity(0.72));
    final IconData icon =
        mine ? Icons.mark_email_read_rounded : (theirs ? Icons.mail_rounded : Icons.edit_note_rounded);
    final chip = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: SeenlyPalette.paper, width: 1.2),
      ),
      child: Icon(icon, size: 16, color: Colors.white),
    );
    return PressScale(
      onTap: onTap,
      haptics: true,
      child: theirs ? BreathingGlow(color: SeenlyPalette.coral, size: 46, maxOpacity: 0.5, child: chip) : chip,
    );
  }
}

/// The "смотрю" button along the bottom of a planned poster — opens the
/// same logging ritual as everywhere else in the app (see
/// WatchingChoiceScreen) instead of marking it watched with no rating
/// attached; it sits inside the poster's own tap target, so its own
/// gesture (the more deeply nested one) wins over onOpen.
class _LogButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _LogButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: busy ? null : onTap,
      haptics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.accent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SeenlyPalette.paper, width: 1.2),
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: busy
              ? SizedBox(
                  key: const ValueKey('busy'),
                  width: 13,
                  height: 13,
                  child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                )
              : Row(
                  key: const ValueKey('label'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_rounded, size: 13, color: SeenlyPalette.accentOnAccent),
                    const SizedBox(width: 5),
                    Text(
                      'смотрю'.tr,
                      style: SeenlyText.mono(size: 10.5, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// дневник
// ---------------------------------------------------------------------------

/// One shared evening. The whole point of this card is the row of *two*
/// ratings — that side-by-side is the thing a couple can't get from
/// looking at each other's separate diaries.
class _SharedEntryCard extends StatelessWidget {
  final SharedDiaryItem item;
  final VoidCallback onOpen;
  final VoidCallback? onUnshare;
  final Future<void> Function(SharedDiaryPerson)? onReveal;

  const _SharedEntryCard({
    required this.item,
    required this.onOpen,
    this.onUnshare,
    this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    return PressScale(
      onTap: onOpen,
      scaleTo: 0.99,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: item.watchedTogether
                ? SeenlyPalette.pink.withOpacity(0.35)
                : SeenlyPalette.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: item.posterUrl == null
                      ? Container(width: 46, height: 66, color: SeenlyPalette.cork)
                      : Image.network(
                          item.posterUrl!,
                          width: 46,
                          height: 66,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              width: 46, height: 66, color: SeenlyPalette.cork),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title(ru),
                          style: SeenlyText.cardTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            item.watchedTogether
                                ? Icons.favorite_rounded
                                : Icons.person_outline_rounded,
                            size: 12,
                            color: item.watchedTogether
                                ? SeenlyPalette.pink
                                : SeenlyPalette.inkFaint,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            item.watchedTogether ? 'смотрели вместе'.tr : 'смотрел один'.tr,
                            style: SeenlyText.mono(
                              size: 10.5,
                              color: item.watchedTogether
                                  ? SeenlyPalette.pink
                                  : SeenlyPalette.inkFaint,
                            ),
                          ),
                          if (item.year != null) ...[
                            const SizedBox(width: 8),
                            Text('${item.year}',
                                style: SeenlyText.mono(
                                    size: 10.5, color: SeenlyPalette.inkFaint)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (onUnshare != null)
                  PressScale(
                    onTap: onUnshare,
                    scaleTo: 0.85,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.visibility_off_outlined,
                          size: 15, color: SeenlyPalette.inkFaint),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in item.people)
                  _PersonChip(
                    person: p,
                    onReveal: (p.ratingHidden && onReveal != null) ? () => onReveal!(p) : null,
                  ),
              ],
            ),
            if (item.ratingGap != null && item.ratingGap! >= 3) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: SeenlyPalette.mustard.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  album_strings.at(
                    'разошлись на ${item.ratingGap} ${nOnly('nPoints', item.ratingGap!)}',
                    'rated ${item.ratingGap} ${nOnly('nPoints', item.ratingGap!)} apart',
                  ),
                  style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.mustard),
                ),
              ),
            ],
            for (final p in item.people)
              if ((p.note ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name.toLowerCase(),
                          style: SeenlyText.mono(
                              size: 9.5, color: SeenlyPalette.inkFaint)),
                      const SizedBox(height: 3),
                      Text(p.note!.trim(),
                          style: SeenlyText.handwrittenNote(size: 13)),
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

class _PersonChip extends StatefulWidget {
  final SharedDiaryPerson person;
  final Future<void> Function()? onReveal;
  const _PersonChip({required this.person, this.onReveal});

  @override
  State<_PersonChip> createState() => _PersonChipState();
}

class _PersonChipState extends State<_PersonChip> {
  bool _busy = false;

  Future<void> _handleTap() async {
    final onReveal = widget.onReveal;
    if (onReveal == null || _busy) return;
    setState(() => _busy = true);
    try {
      await onReveal();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final hasRating = person.rating != null;
    final color = person.isMe ? SeenlyPalette.accent : SeenlyPalette.periwinkle;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            person.isMe ? 'вы'.tr : person.name.toLowerCase(),
            style: SeenlyText.mono(size: 10.5, color: color),
          ),
          const SizedBox(width: 6),
          if (hasRating) ...[
            Icon(Icons.favorite_rounded, size: 10, color: color),
            const SizedBox(width: 3),
            Text('${person.rating}',
                style: SeenlyText.mono(
                    size: 11, weight: FontWeight.w700, color: color)),
          ] else if (person.ratingHidden) ...[
            _busy
                ? SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.4, color: SeenlyPalette.mustard),
                  )
                : Icon(Icons.lock_outline_rounded, size: 10, color: SeenlyPalette.mustard),
            const SizedBox(width: 3),
            // The cost sits right on the chip, not just inside the
            // confirm sheet that opens after tapping — the whole point
            // is that a person sees what revealing this costs *before*
            // they commit to anything, not after.
            Text(
              '${'открыть'.tr} · −$_spoilerUnlockCost',
              style: SeenlyText.mono(size: 10, weight: FontWeight.w600, color: SeenlyPalette.mustard),
            ),
          ] else
            Text('без оценки'.tr,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
        ],
      ),
    );
    // Only a hidden rating with somewhere to send the tap is interactive
    // — everyone else's chip stays a plain, unpressable label, same as
    // before this feature existed.
    if (!person.ratingHidden || widget.onReveal == null) return chip;
    return PressScale(onTap: _handleTap, child: chip);
  }
}

// ---------------------------------------------------------------------------
// мы
// ---------------------------------------------------------------------------

class _StatsBody extends StatelessWidget {
  final SharedStats stats;
  final void Function(SharedDiaryItem) onOpen;
  final List<PartnerMember> members;
  const _StatsBody({required this.stats, required this.onOpen, this.members = const []});

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: '${stats.eveningsTogether}',
                  label: 'вечеров вместе'.tr,
                  color: SeenlyPalette.pink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  value: stats.hoursTogether >= 10
                      ? '${stats.hoursTogether.round()}'
                      : stats.hoursTogether.toStringAsFixed(1),
                  label: 'часов рядом'.tr,
                  color: SeenlyPalette.sage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: '${stats.eveningsSharedTotal}',
                  label: 'записей в общем'.tr,
                  color: SeenlyPalette.periwinkle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  value: '${stats.longestStreakDays}',
                  label: 'дней подряд'.tr,
                  color: SeenlyPalette.mustard,
                ),
              ),
            ],
          ),
          if (stats.averageRatings.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionHeader(title: 'кто щедрее на оценки'.tr),
            const SizedBox(height: 10),
            for (final e in stats.averageRatings.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(e.key.toLowerCase(),
                          style: SeenlyText.mono(
                              size: 11.5, color: SeenlyPalette.inkMuted),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: SoftProgressBar(
                        value: e.value / 10,
                        color: SeenlyPalette.accent,
                        height: 7,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(e.value.toStringAsFixed(1),
                        style: SeenlyText.mono(
                            size: 12,
                            weight: FontWeight.w700,
                            color: SeenlyPalette.accent)),
                  ],
                ),
              ),
          ],
          if (stats.addedByCounts.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionHeader(title: 'кто чаще предлагает'.tr),
            const SizedBox(height: 10),
            _ProposerSplitBar(counts: stats.addedByCounts, members: members),
          ],
          if (stats.topGenres.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionHeader(title: 'ваши жанры'.tr),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final g in stats.topGenres) PillChip(label: g, dashed: true),
              ],
            ),
          ],
          if (stats.bestSharedPick != null) ...[
            const SizedBox(height: 20),
            SectionHeader(title: 'общая любовь'.tr),
            const SizedBox(height: 10),
            _HighlightTile(
              item: stats.bestSharedPick!,
              caption: 'понравилось обоим'.tr,
              color: SeenlyPalette.sage,
              onTap: () => onOpen(stats.bestSharedPick!),
              ru: ru,
            ),
          ],
          if (stats.biggestDisagreement != null) ...[
            const SizedBox(height: 14),
            SectionHeader(title: 'здесь вы не сошлись'.tr),
            const SizedBox(height: 10),
            _HighlightTile(
              item: stats.biggestDisagreement!,
              caption:
                  album_strings.at(
                'разница в ${stats.biggestDisagreement!.ratingGap} — есть о чём поспорить',
                'a gap of ${stats.biggestDisagreement!.ratingGap} — something to argue about',
              ),
              color: SeenlyPalette.coral,
              onTap: () => onOpen(stats.biggestDisagreement!),
              ru: ru,
            ),
          ],
        ],
      ),
    );
  }
}

/// "кто чаще предлагает" (SharedStats.addedByCounts) as a single stacked
/// bar, segments sized by count — plus a legend with the raw numbers
/// underneath, since a bare 70/30 split invites the question "of what?"
/// that the caption answers directly ("ты — 12 · партнёр — 5").
class _ProposerSplitBar extends StatelessWidget {
  final Map<String, int> counts;
  final List<PartnerMember> members;
  const _ProposerSplitBar({required this.counts, required this.members});

  // A getter, not a const list: SeenlyPalette colors are theme-backed
  // getters (see theme/palette.dart), so they can't sit in a const.
  static List<Color> get _colors => [
        SeenlyPalette.pink,
        SeenlyPalette.periwinkle,
        SeenlyPalette.sage,
        SeenlyPalette.mustard,
      ];

  String _labelFor(String username) {
    for (final m in members) {
      if (m.username == username) return m.isYou ? 'ты'.tr : m.nameForDisplay;
    }
    return username.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();
    final colors = _colors;
    // Stable order (by count, ties by username) so segment colors don't
    // reshuffle between rebuilds as counts change.
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (var i = 0; i < entries.length; i++)
                  if (entries[i].value > 0)
                    Expanded(
                      flex: entries[i].value,
                      child: Container(color: colors[i % colors.length]),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (var i = 0; i < entries.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_labelFor(entries[i].key)} — ${entries[i].value}',
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// "наши вехи" — the couple's badge shelf (GET /partner/shared/achievements),
/// same visual language as the personal AchievementBadge grid. Unlocked
/// badges lead; if at least one is still locked, the single one with the
/// most progress trails the row, so there's always something to reach
/// for in view — even a couple with zero unlocked badges yet.
class _CoupleBadgesSection extends StatelessWidget {
  final List<Achievement> achievements;
  const _CoupleBadgesSection({required this.achievements});

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) return const SizedBox.shrink();
    final unlocked = achievements.where((a) => a.unlocked).toList();
    final locked = achievements.where((a) => !a.unlocked).toList()
      ..sort((a, b) => b.progressRatio.compareTo(a.progressRatio));
    final nextUp = locked.isNotEmpty ? locked.first : null;
    final theme = context.watch<LogThemeService>().theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'наши вехи'.tr,
          trailing: unlocked.isNotEmpty ? '${unlocked.length} / ${achievements.length}' : null,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 108,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final a in unlocked)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AchievementBadge(
                    theme: theme,
                    iconKey: a.iconKey,
                    // Raw English on purpose — AchievementBadge already
                    // runs the label through .tr itself, the same
                    // contract every other achievement badge relies on.
                    label: a.title,
                    unlocked: true,
                    rarity: a.rarity,
                    onTap: () => showBadgeDetailCard(context, achievement: a),
                  ),
                ),
              if (nextUp != null)
                AchievementBadge(
                  theme: theme,
                  iconKey: nextUp.iconKey,
                  label: nextUp.title,
                  unlocked: false,
                  rarity: nextUp.rarity,
                  progressLabel: '${nextUp.progressCurrent} / ${nextUp.progressTarget}',
                  onTap: () => showBadgeDetailCard(context, achievement: nextUp),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Entry point into "наш враппед" (WrappedScreen(isCouple: true)), up top
/// for the same reason the personal wrapped teaser sits at the top of the
/// profile: a highlight buried under stats doesn't get opened. Opens on
/// the all-time scope, same as TogetherWrappedTeaser, so a circle with
/// nothing logged yet *this* year doesn't land on an empty deck.
class _CoupleWrappedEntry extends StatelessWidget {
  const _CoupleWrappedEntry();

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const WrappedScreen(isCouple: true, initialScope: 'all'),
        ),
      ),
      scaleTo: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: SeenlyPalette.accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SeenlyPalette.accent.withOpacity(0.22)),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: SeenlyPalette.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('наш враппед'.tr, style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'ваши вечера в кино вдвоём'.tr,
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: SeenlyPalette.inkFaint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatTile({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          children: [
            Text(value,
                style: SeenlyText.serif(
                    size: 25, weight: FontWeight.w600, color: color)),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center,
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted)),
          ],
        ),
      );
}

class _HighlightTile extends StatelessWidget {
  final SharedDiaryItem item;
  final String caption;
  final Color color;
  final VoidCallback onTap;
  final bool ru;

  const _HighlightTile({
    required this.item,
    required this.caption,
    required this.color,
    required this.onTap,
    required this.ru,
  });

  @override
  Widget build(BuildContext context) => PressScale(
        onTap: onTap,
        scaleTo: 0.98,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.09),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: item.posterUrl == null
                    ? Container(width: 40, height: 58, color: SeenlyPalette.cork)
                    : Image.network(item.posterUrl!,
                        width: 40,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            width: 40, height: 58, color: SeenlyPalette.cork)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title(ru),
                        style: SeenlyText.cardTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(caption,
                        style: SeenlyText.mono(size: 10.5, color: color)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Circle management — add to circle / settings (unlink)
// ---------------------------------------------------------------------------

/// Picks a friend to invite straight into this circle — the same
/// PartnerService.sendInvite a friend's own profile already uses, just
/// reachable from the circle's own screen instead of requiring a trip to
/// that friend's profile first. Friends already sharing this circle are
/// left off the list (matched by username); friends with a pending
/// outgoing invite already sent show that instead of a live button.
class _AddToCircleSheet extends StatefulWidget {
  final List<String> excludeUsernames;
  const _AddToCircleSheet({required this.excludeUsernames});

  @override
  State<_AddToCircleSheet> createState() => _AddToCircleSheetState();
}

class _AddToCircleSheetState extends State<_AddToCircleSheet> {
  late final FriendsService _friendsService = FriendsService(ApiClient.instance);
  late final PartnerService _partnerService = PartnerService(ApiClient.instance);

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
      final results = await Future.wait([
        _friendsService.list(),
        _partnerService.invites(),
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
        _loadError = 'не получилось загрузить друзей — попробуйте ещё раз'.tr;
        _loading = false;
      });
    }
  }

  Future<void> _invite(Friend friend) async {
    setState(() => _busyUserIds.add(friend.userId));
    try {
      await _partnerService.sendInvite(friend.userId);
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
        SnackBar(content: Text('не получилось отправить приглашение — попробуйте ещё раз'.tr)),
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
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: SeenlyPalette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('добавить в свой круг'.tr, style: SeenlyText.sectionTitle),
            const SizedBox(height: 4),
            Text(
              ('они присоединятся, как только примут — как и любое другое '
              'приглашение к совместному просмотру.').tr,
              style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 16),
            if (_loading)
              Padding(
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
                    PrimaryButton(label: 'попробовать снова'.tr, onTap: _load, expand: false),
                  ],
                ),
              )
            else if (_friends.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  ('все ваши друзья уже здесь — сначала добавьте новых, потом '
                  'приглашайте их отсюда.').tr,
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
                    return Row(
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
                                  ? SizedBox(
                                      key: ValueKey('busy'),
                                      width: 12,
                                      height: 12,
                                      child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                                    )
                                  : Text(
                                      sent ? 'приглашение отправлено'.tr : 'пригласить'.tr,
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

class _CoViewSettingsSheet extends StatelessWidget {
  final bool isCompany;
  final String? partnerUsername;
  final VoidCallback onUnlink;
  const _CoViewSettingsSheet({required this.isCompany, this.partnerUsername, required this.onUnlink});

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
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: SeenlyPalette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('настройки совместного просмотра'.tr, style: SeenlyText.sectionTitle),
            const SizedBox(height: 16),
            PressScale(
              onTap: onUnlink,
              child: Row(
                children: [
                  Icon(isCompany ? Icons.logout : Icons.link_off, size: 16, color: SeenlyPalette.coral),
                  const SizedBox(width: 10),
                  Text(
                    isCompany
                        ? 'покинуть этот круг'.tr
                        : album_strings.at(
                            'разорвать связь с ${partnerUsername ?? "партнёром"}',
                            'end the link with ${partnerUsername ?? "your partner"}',
                          ),
                    style: SeenlyText.serif(size: 14, color: SeenlyPalette.coral),
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

// ---------------------------------------------------------------------------
// Not linked / error
// ---------------------------------------------------------------------------

class _NotLinkedState extends StatelessWidget {
  final VoidCallback onLinked;

  /// Set when this is the pushed-route version. Then the button goes back
  /// (linking up is done from Home's co-viewing card) instead of pushing
  /// another CoViewingScreen — which is this very screen, so it would just
  /// open itself over and over.
  final VoidCallback? onBack;
  const _NotLinkedState({required this.onLinked, this.onBack});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BreathingGlow(
                color: SeenlyPalette.pink,
                size: 52,
                period: const Duration(milliseconds: 5200),
                maxOpacity: 0.20,
                child: Icon(Icons.favorite_border_rounded,
                    size: 26, color: SeenlyPalette.pink),
              ),
              const SizedBox(height: 16),
              Text('здесь будет ваш общий дневник'.tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(size: 17, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                ('свяжитесь с тем, с кем смотрите вместе — и вечера, оценки '
                'и статистика станут общими').tr,
                textAlign: TextAlign.center,
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'связаться'.tr,
                expand: false,
                onTap: () {
                  final back = onBack;
                  if (back != null) {
                    back();
                  } else {
                    onLinked(); // embedded: just look again
                  }
                },
              ),
            ],
          ),
        ),
      );
}

class _Retry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Retry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message,
                  textAlign: TextAlign.center, style: SeenlyText.emptyState()),
              const SizedBox(height: 14),
              PressScale(
                onTap: onRetry,
                child: Text('попробовать снова'.tr,
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.accent)),
              ),
            ],
          ),
        ),
      );
}
