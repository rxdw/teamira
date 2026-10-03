import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../models/together_session.dart';
import '../../models/user_list.dart';
import '../../services/api_client.dart';
import '../../services/coview_prefs_service.dart';
import '../../services/realtime_socket.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/how_it_works_sheet.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/soft_motion.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/together_motion.dart';
import '../../widgets/wow_motion.dart' show Entrance, Breathe;
import '../lists/list_detail_screen.dart';
import '../../services/app_translations.dart';

/// Every match — from any session, any device this account has logged in
/// on — lands in the one list with this name. Looked up by name each time
/// rather than an id stashed somewhere, so it behaves exactly like any
/// other list the person could have made by hand (renameable, deletable,
/// nothing schema-special about it). The backend uses the same name for
/// network sessions, so both modes end up in the same place.
const kTogetherListName = 'watch together';


/// TMDB's own genre vocabulary (see the id->name tables in
/// backend/app/adapters/tmdb.py) — every MediaItem.genres entry the deck
/// can carry is one of these names, so picking from this fixed list (vs.
/// scanning whatever happens to be in the current pool) means the chips
/// don't jump around between sessions and match what the backend's
/// _matches_genre_filter checks against. Lowercased for display only;
/// the canonical (capitalized) name is what's actually sent/matched.
const List<String> kTogetherGenreChoices = [
  'Action',
  'Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Fantasy',
  'History',
  'Horror',
  'Music',
  'Mystery',
  'Romance',
  'Science Fiction',
  'Thriller',
  'War',
  'Western',
];

enum _Phase {
  setup,
  loadingDeck,
  swiping,
  empty,
  recap,
  error,
  // Network ("over the network") phases — a session lives on the server,
  // each phone polls it, no shared screen required.
  netStarting,
  netHostWaiting,
  netJoinEntry,
  netSwiping,
  netRecap,
}

/// Decide on titles together, one card at a time — either passing one
/// phone back and forth, or each on your own phone over the network via a
/// short code. Anything you both say yes to is tucked into a shared
/// "watch together" list, ready to open on movie night.
class TogetherScreen extends StatefulWidget {
  const TogetherScreen({super.key});

  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen> {
  _Phase _phase = _Phase.setup;
  String _mode = 'local'; // 'local' | 'network'
  String _typeFilter = 'all'; // all | movie | series | game
  final Set<String> _selectedGenres = {}; // empty = no genre narrowing

  // --- local (one-phone) state ---
  List<MediaItem> _deck = [];
  int _index = 0;
  final List<MediaItem> _matches = [];
  String? _listId;
  // Bumped on every local "together" decision so the MatchBeat knows to play
  // — a one-phone yes is already the both-of-you decision (see
  // how_it_works_sheet.dart, step 3), so this is just a warm little beat
  // confirming it landed, never a second question asking if it's real.
  int _matchPulseTick = 0;

  // --- network state ---
  TogetherSession? _session;
  RealtimeSocket<TogetherSession>? _socket;
  StreamSubscription<TogetherSession>? _socketSub;
  int _netIndex = 0;
  // Bumped when the person you sent a code to turns up, and when a title
  // becomes a match while you're both swiping — each plays a short beat
  // over the deck (see MatchBeat). Both are otherwise silent: the only
  // other sign is a badge count ticking up.
  int _partnerJoinedTick = 0;
  int _netMatchTick = 0;
  String? _netMatchTitle;
  final TextEditingController _codeController = TextEditingController();
  String? _joinError;
  bool _joining = false;

  // generic message-phase content (used for both empty/error states)
  String _msgTitle = '';
  String _msgSubtitle = '';
  String _msgButtonLabel = '';
  VoidCallback? _msgAction;

  static const _filters = [
    ('all', 'all'),
    ('movie', 'movies'),
    ('series', 'series & anime'),
    ('game', 'games'),
  ];

  // The 'series' tab is labeled "series & anime" (see _filters above) — a
  // deliberate grouping for this one feature, so matching must treat the
  // two as one bucket instead of the plain equality every other filtered
  // list in the app uses. Mirrors _matches_type_filter in
  // app/routers/together.py so a network session's server-built deck
  // matches what the host saw locally.
  bool _matchesTypeFilter(String mediaType) {
    if (_typeFilter == 'all') return true;
    if (_typeFilter == 'series') return mediaType == 'series' || mediaType == 'anime';
    return mediaType == _typeFilter;
  }

  /// Empty selection means no genre narrowing. Otherwise a card only
  /// needs to share ONE picked genre — requiring all of them would empty
  /// the deck almost every time more than one is picked. Mirrors
  /// _matches_genre_filter in app/routers/together.py.
  bool _matchesGenreFilter(List<String> itemGenres) {
    if (_selectedGenres.isEmpty) return true;
    final wanted = _selectedGenres.map((g) => g.toLowerCase()).toSet();
    return itemGenres.any((g) => wanted.contains(g.toLowerCase()));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prefs = context.read<CoViewPrefsService>();
      if (!prefs.hasSeenGuide) {
        prefs.markGuideSeen();
        showHowItWorksSheet(context);
      }
    });
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _socket?.close();
    _codeController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Local, one-phone mode — unchanged from before.
  // ---------------------------------------------------------------------

  Future<void> _startSession() async {
    setState(() => _phase = _Phase.loadingDeck);
    try {
      final collections = await context.read<AppState>().feed.collections();
      final seen = <String>{};
      final pool = <MediaItem>[];
      for (final c in collections) {
        for (final item in c.items) {
          if (!_matchesTypeFilter(item.mediaType)) continue;
          if (!_matchesGenreFilter(item.genres)) continue;
          if (seen.add('${item.source}:${item.id}')) pool.add(item);
        }
      }
      pool.shuffle(Random());
      if (!mounted) return;
      if (pool.isEmpty) {
        setState(() => _showMessage(
              title: 'nothing to shuffle right now'.tr,
              subtitle: 'try a different category, or check back later'.tr,
              buttonLabel: 'back'.tr,
              onTap: () => setState(() => _phase = _Phase.setup),
              phase: _Phase.empty,
            ));
        return;
      }
      setState(() {
        _deck = pool;
        _index = 0;
        _matches.clear();
        _phase = _Phase.swiping;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _showMessage(
            title: "couldn't gather any cards".tr,
            subtitle: 'check the connection and try again'.tr,
            buttonLabel: 'try again'.tr,
            onTap: _startSession,
            phase: _Phase.error,
          ));
    }
  }

  /// Finds this account's "watch together" list, making one the first
  /// time it's ever needed — same list every session, just like any list
  /// someone names themselves.
  Future<String> _ensureListId() async {
    if (_listId != null) return _listId!;
    final app = context.read<AppState>();
    final lists = await app.lists.all();
    UserList? existing;
    for (final l in lists) {
      if (l.name == kTogetherListName) {
        existing = l;
        break;
      }
    }
    final id = existing?.id ??
        (await app.lists.create(
          name: kTogetherListName,
          description: 'titles you both said yes to',
        ))
            .id;
    _listId = id;
    return id;
  }

  Future<void> _decide(MediaItem item, bool together) async {
    if (together) {
      _matches.add(item);
      // A match here should land on the *shared* co-viewing screen
      // unconditionally, right now — not batched until the deck runs out.
      // The deck is every title across all collections shuffled together,
      // so nobody actually swipes through the whole thing in one sitting;
      // waiting for reachedEnd (see below) meant a match could sit only
      // in this widget's in-memory _matches list and vanish the moment
      // someone backed out mid-session, without ever reaching the server.
      // Fire this per-swipe instead so a "yes" is safe the instant it
      // happens. Server-side dedupe (see add_coview_entries) makes it
      // harmless to also re-send the same item in the end-of-round sync
      // below.
      context.read<AppState>().partner.syncLocalMatches([item]).catchError((_) {
        // Best-effort — the match still shows up in the recap either way,
        // and the end-of-round sync below gets another shot at it.
      });
      // Whether it ALSO lands on this account's own "plan to watch" shelf
      // and its named "watch together" list is a separate question,
      // governed entirely by the "add matches to my own list too" toggle
      // — so both writes stay gated behind it together, rather than the
      // profile write firing unconditionally while only the named list
      // respected the toggle.
      final addToOwnList = context.read<CoViewPrefsService>().addMatchesToOwnList;
      if (addToOwnList) {
        context.read<AppState>().feed.react(item, 'like').catchError((_) {
          // Best-effort — the match still shows up in the recap either way.
        });
        try {
          final listId = await _ensureListId();
          await context.read<AppState>().lists.addItem(listId, item);
        } catch (_) {
          // The match still shows up in the recap even if saving it
          // hiccuped — worst case it can be re-added from the title page.
        }
      }
    }
    if (!mounted) return;
    final reachedEnd = _index + 1 >= _deck.length;
    setState(() {
      _index++;
      if (together) _matchPulseTick++;
      if (reachedEnd) _phase = _Phase.recap;
    });
    if (reachedEnd && _matches.isNotEmpty) {
      // Kept as a backstop in case any per-swipe call above dropped —
      // idempotent server-side, so re-sending the whole round here is safe.
      context.read<AppState>().partner.syncLocalMatches(_matches).catchError((_) {});
    }
  }

  // ---------------------------------------------------------------------
  // Network mode — a session lives on the server; each phone polls it.
  // ---------------------------------------------------------------------

  void _showMessage({
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onTap,
    required _Phase phase,
  }) {
    _msgTitle = title;
    _msgSubtitle = subtitle;
    _msgButtonLabel = buttonLabel;
    _msgAction = onTap;
    _phase = phase;
  }

  void _backToSetup() {
    _socketSub?.cancel();
    _socket?.close();
    _socket = null;
    _session = null;
    _netIndex = 0;
    _joinError = null;
    _codeController.clear();
    setState(() => _phase = _Phase.setup);
  }

  Future<void> _createNetworkSession() async {
    setState(() => _phase = _Phase.netStarting);
    try {
      final session = await context.read<AppState>().together.create(
            typeFilter: _typeFilter,
            genres: _selectedGenres.toList(),
            syncToOwnList: context.read<CoViewPrefsService>().addMatchesToOwnList,
          );
      if (!mounted) return;
      setState(() {
        _session = session;
        _netIndex = 0;
        _phase = _Phase.netHostWaiting;
      });
      _startWatching();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _showMessage(
            title: "couldn't start a session".tr,
            subtitle: e.message,
            buttonLabel: 'back'.tr,
            onTap: _backToSetup,
            phase: _Phase.error,
          ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _showMessage(
            title: "couldn't start a session".tr,
            subtitle: 'check the connection and try again'.tr,
            buttonLabel: 'try again'.tr,
            onTap: _createNetworkSession,
            phase: _Phase.error,
          ));
    }
  }

  Future<void> _joinNetworkSession() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _joinError = 'codes are 6 characters'.tr);
      return;
    }
    setState(() {
      _joining = true;
      _joinError = null;
    });
    try {
      final session = await context.read<AppState>().together.join(
            code,
            syncToOwnList: context.read<CoViewPrefsService>().addMatchesToOwnList,
          );
      if (!mounted) return;
      setState(() {
        _session = session;
        _netIndex = 0;
        _joining = false;
        _phase = _Phase.netSwiping;
      });
      _startWatching();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joinError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joinError = 'check the connection and try again'.tr;
      });
    }
  }

  void _startWatching() {
    _socketSub?.cancel();
    _socket?.close();
    final session = _session;
    if (session == null) return;
    _socket = context.read<AppState>().together.watch(session.id);
    _socketSub = _socket!.updates.listen(_onSessionUpdate);
  }

  void _onSessionUpdate(TogetherSession updated) {
    if (!mounted) return;
    setState(() {
      // A title that just became a match (from this push, or from the
      // response to your own swipe — whichever arrives first announces it).
      _noteNetMatches(updated);
      _session = updated;
      // The host's screen advances from "waiting for a partner" to
      // swiping the moment someone actually joins.
      if (_phase == _Phase.netHostWaiting && updated.partnerJoined) {
        _phase = _Phase.netSwiping;
        _partnerJoinedTick++;
      }
    });
  }

  /// Compares [updated] with the session as it currently stands and, if it
  /// has a match the screen hasn't shown yet, arms the "it's a match" beat
  /// (with the title that matched). Run right before `_session = updated`,
  /// from both the live socket's push and a swipe's own response, so
  /// whichever one sees the match first is the one that announces it —
  /// never both.
  void _noteNetMatches(TogetherSession updated) {
    final before = _session;
    if (before == null) return;
    final known = {for (final m in before.matches) '${m.source}:${m.id}'};
    final fresh = updated.matches.where((m) => !known.contains('${m.source}:${m.id}')).toList();
    if (fresh.isEmpty) return;
    _netMatchTick++;
    _netMatchTitle = fresh.length > 1
        ? nCount('nMatches', fresh.length)
        : fresh.first.title.display;
  }

  Future<void> _netDecide(MediaItem item, bool together) async {
    final session = _session;
    if (session == null) return;
    setState(() => _netIndex++);
    try {
      final updated = await context.read<AppState>().together.swipe(
            session.id,
            mediaId: item.id,
            source: item.source,
            decision: together,
          );
      if (!mounted) return;
      setState(() {
        _noteNetMatches(updated);
        _session = updated;
        if (_netIndex >= updated.deck.length) _phase = _Phase.netRecap;
      });
    } catch (_) {
      // Keep the deck moving even if one swipe failed to save — the
      // person can't easily go back to a card anyway, and the live socket
      // will keep the match list itself accurate regardless.
      if (!mounted) return;
      setState(() {
        if (_netIndex >= (_session?.deck.length ?? 0)) _phase = _Phase.netRecap;
      });
    }
  }

  Future<void> _endNetworkSession() async {
    final session = _session;
    _socketSub?.cancel();
    _socket?.close();
    if (session != null) {
      try {
        await context.read<AppState>().together.end(session.id);
      } catch (_) {
        // Ending is best-effort — an abandoned session simply ages out.
      }
    }
  }

  Future<void> _handleBack() async {
    if (_phase == _Phase.netHostWaiting ||
        _phase == _Phase.netSwiping ||
        _phase == _Phase.netRecap) {
      await _endNetworkSession();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------

  int get _liveMatchCount =>
      _mode == 'network' ? (_session?.matches.length ?? 0) : _matches.length;

  bool get _showMatchBadge =>
      _liveMatchCount > 0 &&
      (_phase == _Phase.swiping || _phase == _Phase.netSwiping || _phase == _Phase.netHostWaiting);

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
                    icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: _handleBack,
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text('watch together'.tr, style: SeenlyText.screenTitle)),
                  IconButton(
                    icon: Icon(Icons.help_outline, size: 18, color: SeenlyPalette.inkMuted),
                    tooltip: 'how this works'.tr,
                    onPressed: () => showHowItWorksSheet(context),
                  ),
                  MatchCounter(count: _liveMatchCount, visible: _showMatchBadge),
                ],
              ),
            ),
            Expanded(
              // Setup → loading → deck → recap glide into one another
              // instead of cutting. Keyed on the phase only, so the deck
              // itself (which changes every swipe) updates in place.
              child: SoftSwap(
                expand: true,
                alignment: Alignment.topCenter,
                rise: 0.02,
                child: KeyedSubtree(
                  key: ValueKey<_Phase>(_phase),
                  child: _buildBody(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.setup:
        return _SetupView(
          filter: _typeFilter,
          filters: _filters,
          mode: _mode,
          selectedGenres: _selectedGenres,
          onGenreToggle: (g) => setState(() {
            if (!_selectedGenres.remove(g)) _selectedGenres.add(g);
          }),
          onFilterChange: (f) => setState(() => _typeFilter = f),
          onModeChange: (m) => setState(() => _mode = m),
          onStartLocal: _startSession,
          onCreateNetworkSession: _createNetworkSession,
          onJoinNetworkSession: () => setState(() => _phase = _Phase.netJoinEntry),
        );
      case _Phase.loadingDeck:
      case _Phase.netStarting:
        return CardShuffleLoader(
          caption: _phase == _Phase.netStarting ? 'setting up a session…'.tr : 'gathering cards…'.tr,
        );
      case _Phase.error:
      case _Phase.empty:
        return _MessageView(
          title: _msgTitle,
          subtitle: _msgSubtitle,
          buttonLabel: _msgButtonLabel,
          onButtonTap: _msgAction ?? _backToSetup,
        );
      case _Phase.swiping:
        return Stack(
          alignment: Alignment.center,
          children: [
            _SwipeDeck(deck: _deck, index: _index, onDecide: _decide),
            IgnorePointer(
              child: MatchBeat(tick: _matchPulseTick, headline: 'settled, together'.tr),
            ),
          ],
        );
      case _Phase.recap:
        return _RecapView(
          matches: _matches,
          onSwipeAgain: () => setState(() => _phase = _Phase.setup),
          onOpenList: _matches.isEmpty || _listId == null
              ? null
              : () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => ListDetailScreen(listId: _listId!)),
                  ),
        );
      case _Phase.netJoinEntry:
        return _JoinCodeView(
          controller: _codeController,
          error: _joinError,
          busy: _joining,
          onBack: () => setState(() => _phase = _Phase.setup),
          onJoin: _joinNetworkSession,
        );
      case _Phase.netHostWaiting:
        return _HostWaitingView(code: _session?.code ?? '', onCancel: () async {
          await _endNetworkSession();
          _backToSetup();
        });
      case _Phase.netSwiping:
        final session = _session;
        if (session == null || _netIndex >= session.deck.length) {
          return CardShuffleLoader(caption: 'gathering cards…'.tr);
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            _SwipeDeck(
              deck: session.deck,
              index: _netIndex,
              partnerSwiped: session.partnerSwiped,
              partnerUsername: session.partnerUsername,
              onDecide: _netDecide,
            ),
            // Someone you sent a code to has just shown up…
            IgnorePointer(
              child: MatchBeat(
                tick: _partnerJoinedTick,
                headline: '${session.partnerUsername ?? 'they'.tr} ${'is here'.tr}',
                subtitle: "let's swipe together".tr,
              ),
            ),
            // …and one of you has said yes to something the other already had.
            IgnorePointer(
              child: MatchBeat(
                tick: _netMatchTick,
                headline: "it's a match!".tr,
                subtitle: _netMatchTitle,
              ),
            ),
          ],
        );
      case _Phase.netRecap:
        final session = _session;
        return _NetRecapView(
          matches: session?.matches ?? const [],
          partnerUsername: session?.partnerUsername,
          partnerSwiped: session?.partnerSwiped ?? 0,
          deckSize: session?.deck.length ?? 0,
          onEnd: () async {
            await _endNetworkSession();
            _backToSetup();
          },
          onOpenList: (session?.matches.isEmpty ?? true)
              ? null
              : () async {
                  // The network match list is the same account-owned
                  // "watch together" list the local mode uses, so it's
                  // found the normal way rather than carrying an id.
                  final app = context.read<AppState>();
                  final lists = await app.lists.all();
                  UserList? existing;
                  for (final l in lists) {
                    if (l.name == kTogetherListName) {
                      existing = l;
                      break;
                    }
                  }
                  if (existing == null || !mounted) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => ListDetailScreen(listId: existing!.id)),
                  );
                },
        );
    }
  }
}

class _SetupView extends StatelessWidget {
  final String filter;
  final List<(String, String)> filters;
  final String mode;
  final Set<String> selectedGenres;
  final ValueChanged<String> onGenreToggle;
  final ValueChanged<String> onFilterChange;
  final ValueChanged<String> onModeChange;
  final VoidCallback onStartLocal;
  final VoidCallback onCreateNetworkSession;
  final VoidCallback onJoinNetworkSession;

  const _SetupView({
    required this.filter,
    required this.filters,
    required this.mode,
    required this.selectedGenres,
    required this.onGenreToggle,
    required this.onFilterChange,
    required this.onModeChange,
    required this.onStartLocal,
    required this.onCreateNetworkSession,
    required this.onJoinNetworkSession,
  });

  @override
  Widget build(BuildContext context) {
    final isNetwork = mode == 'network';

    // The page settles in from the top: each block a beat after the one
    // above it.
    Widget settle(int n, Widget child) => Entrance(
          delay: Duration(milliseconds: 60 * n),
          duration: const Duration(milliseconds: 460),
          riseBy: 12,
          child: child,
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      children: [
        settle(
          0,
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            // A slow, resting heartbeat — this whole feature is about two
            // people, and the heart at the top says so.
            child: const HeartbeatIcon(size: 26),
          ),
        ),
        const SizedBox(height: 18),
        settle(1, Text('decide together, one card at a time'.tr, style: SeenlyText.screenTitle)),
        const SizedBox(height: 8),
        settle(
          2,
          // The line under the title follows the chosen mode.
          SoftSwap(
            child: Text(
              isNetwork
                  ? 'each on your own phone — whatever you both say yes to '
                      'gets tucked into your "watch together" list, ready for movie night.'
                  : 'pass the phone, or just lean in — whatever you both say yes to '
                      'gets tucked into your "watch together" list, ready for movie night.',
              key: ValueKey<bool>(isNetwork),
              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
            ),
          ),
        ),
        const SizedBox(height: 26),
        settle(3, Text('how are you swiping?'.tr, style: SeenlyText.metaLabel)),
        const SizedBox(height: 10),
        settle(
          3,
          Row(
            children: [
              PillChip(
                label: 'one phone'.tr,
                active: mode == 'local',
                onTap: () => onModeChange('local'),
              ),
              const SizedBox(width: 8),
              PillChip(
                label: 'over the network'.tr,
                active: isNetwork,
                onTap: () => onModeChange('network'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        settle(4, Text('what are we in the mood for?'.tr, style: SeenlyText.metaLabel)),
        const SizedBox(height: 10),
        settle(
          4,
          Row(
            children: [
              for (final f in filters) ...[
                PillChip(
                  label: f.$2,
                  active: filter == f.$1,
                  onTap: () => onFilterChange(f.$1),
                ),
                if (f != filters.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        settle(
          5,
          Row(
            children: [
              Text('any particular genre?'.tr, style: SeenlyText.metaLabel),
              const SizedBox(width: 8),
              // How many are picked: the number swaps with a little pop,
              // and the whole label is simply absent at zero.
              SoftSwap(
                pop: true,
                child: selectedGenres.isEmpty
                    ? const SizedBox(key: ValueKey<int>(0), height: 1)
                    : Text(
                        '${selectedGenres.length} ${'picked'.tr}',
                        key: ValueKey<int>(selectedGenres.length),
                        style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        settle(
          5,
          Text(
            'leave this alone for anything — pick a few to narrow the deck down to just those'.tr,
            style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // The genres drift in one after another, left to right.
            for (int i = 0; i < kTogetherGenreChoices.length; i++)
              Entrance(
                delay: Duration(milliseconds: 320 + 24 * i),
                duration: const Duration(milliseconds: 380),
                riseBy: 8,
                child: PillChip(
                  label: kTogetherGenreChoices[i].toLowerCase(),
                  active: selectedGenres.contains(kTogetherGenreChoices[i]),
                  onTap: () => onGenreToggle(kTogetherGenreChoices[i]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 30),
        settle(
          6,
          // Switching mode swaps the buttons under it, and the page eases
          // to the new height rather than jumping.
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: SoftSwap(
              alignment: Alignment.topCenter,
              rise: 0.05,
              child: KeyedSubtree(
                key: ValueKey<bool>(isNetwork),
                child: !isNetwork
                    ? PrimaryButton(label: 'start swiping'.tr, onTap: onStartLocal)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PrimaryButton(label: 'start a session'.tr, onTap: onCreateNetworkSession),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: onJoinNetworkSession,
                            child: Text('have a code already? join instead'.tr,
                                style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown to whoever started the session — a code to send to the other
/// person, and a quiet wait while polling for them to type it in. The
/// code's characters are stamped in one by one, and the wait is a heart
/// with rings spreading from it, like a signal sent out and not yet
/// answered.
class _HostWaitingView extends StatelessWidget {
  final String code;
  final VoidCallback onCancel;

  const _HostWaitingView({required this.code, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Entrance(
              riseBy: 10,
              child: Text('send them this code'.tr, style: SeenlyText.serif(italic: true, size: 15)),
            ),
            const SizedBox(height: 20),
            CodeTiles(code: code),
            const SizedBox(height: 26),
            Entrance(
              delay: const Duration(milliseconds: 500),
              duration: const Duration(milliseconds: 700),
              riseBy: 6,
              child: const WaitingRipples(size: 124),
            ),
            const SizedBox(height: 6),
            Entrance(
              delay: const Duration(milliseconds: 650),
              riseBy: 6,
              child: Text('waiting for them to join…'.tr,
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            ),
            const SizedBox(height: 22),
            TextButton(
              onPressed: onCancel,
              child: Text('cancel'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the other person types the code they were sent.
class _JoinCodeView extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onJoin;

  const _JoinCodeView({
    required this.controller,
    required this.error,
    required this.busy,
    required this.onBack,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      children: [
        Entrance(riseBy: 12, child: Text('got a code?'.tr, style: SeenlyText.screenTitle)),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 70),
          riseBy: 12,
          child: Text(
            'type in the 6-character code the other person sent you.'.tr,
            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
          ),
        ),
        const SizedBox(height: 22),
        Entrance(
          delay: const Duration(milliseconds: 140),
          riseBy: 12,
          // A wrong code makes the field shake its head, briefly.
          child: ShakeOnChange(
            trigger: error,
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              ],
              style: SeenlyText.mono(size: 22, color: SeenlyPalette.ink, weight: FontWeight.w700)
                  .copyWith(letterSpacing: 6),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: SeenlyPalette.paper,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: SeenlyPalette.border),
                ),
              ),
            ),
          ),
        ),
        SoftSwap(
          rise: 0.3,
          child: error == null
              ? const SizedBox(key: ValueKey<String>('no-error'), width: double.infinity)
              : Padding(
                  key: ValueKey<String>(error!),
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
                ),
        ),
        const SizedBox(height: 22),
        Entrance(
          delay: const Duration(milliseconds: 210),
          riseBy: 12,
          child: PrimaryButton(label: 'join'.tr, onTap: onJoin, loading: busy),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: onBack,
            child: Text('back'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder)),
          ),
        ),
      ],
    );
  }
}

/// The swiping surface — for both modes (one phone, or over the network).
/// With [partnerSwiped] set it also shows how far the other person has got:
/// two pills, each filling like a tide as its owner works through the same
/// deck — the only sense of "togetherness" possible when the two of you
/// aren't looking at the same screen.
class _SwipeDeck extends StatelessWidget {
  final List<MediaItem> deck;
  final int index;
  final int? partnerSwiped;
  final String? partnerUsername;
  final void Function(MediaItem item, bool together) onDecide;

  const _SwipeDeck({
    required this.deck,
    required this.index,
    required this.onDecide,
    this.partnerSwiped,
    this.partnerUsername,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = deck.length - index;
    final current = deck[index];
    final partner = partnerSwiped;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DeckPill('$remaining ${'left'.tr}', progress: index / deck.length),
              if (partner != null)
                DeckPill(
                  '${partnerUsername ?? 'they'.tr}: $partner ${'of'.tr} ${deck.length}',
                  progress: partner / deck.length,
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                String keyOf(int i) => '${deck[i].source}:${deck[i].id}';
                return DeckStack(
                  index: index,
                  count: deck.length,
                  keyOf: keyOf,
                  topBuilder: (i) => SwipeableCard(
                    key: ValueKey<String>(keyOf(i)),
                    yes: SwipeSide(
                      icon: Icons.favorite,
                      label: 'together'.tr,
                      color: SeenlyPalette.accent,
                    ),
                    no: SwipeSide(
                      icon: Icons.close,
                      label: 'not tonight'.tr,
                      color: SeenlyPalette.inkMuted,
                    ),
                    onDecide: (together) => onDecide(deck[i], together),
                    child: _CardFace(
                      item: deck[i],
                      maxWidth: constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                      elevated: true,
                    ),
                  ),
                  backBuilder: (i) => _CardFace(
                    item: deck[i],
                    maxWidth: constraints.maxWidth,
                    maxHeight: constraints.maxHeight,
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              DecisionButton(
                icon: Icons.close,
                label: 'not tonight'.tr,
                iconColor: SeenlyPalette.inkMuted,
                background: SeenlyPalette.paper,
                bordered: true,
                onTap: () => onDecide(current, false),
              ),
              DecisionButton(
                icon: Icons.favorite,
                label: 'together'.tr,
                iconColor: SeenlyPalette.accentOnAccent,
                background: SeenlyPalette.accent,
                large: true,
                onTap: () => onDecide(current, true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The visible face of a card — poster on top, title + meta below, framed
/// like a little instant photo rather than a bare rectangle: a warm paper
/// mat, a soft ink-toned shadow instead of a flat black one, and — on the
/// interactive top card — a strip of washi tape pinning it in place.
class _CardFace extends StatelessWidget {
  final MediaItem item;
  final double maxWidth;
  final double maxHeight;
  final bool elevated;
  final double rotation;

  const _CardFace({
    required this.item,
    required this.maxWidth,
    required this.maxHeight,
    this.elevated = false,
    this.rotation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.mediaColor(item.mediaType);
    final meta = [
      item.mediaType,
      if (item.year != null) '${item.year}',
    ].join(' · ');

    final card = Container(
      width: maxWidth,
      height: maxHeight,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: SeenlyPalette.border),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: SeenlyPalette.ink.withOpacity(0.16),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: SeenlyPalette.ink.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: SeenlyPalette.ink.withOpacity(0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: item.posterUrl != null && item.posterUrl!.isNotEmpty
                  ? Image.network(
                      item.posterUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: color),
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : Container(color: color),
                    )
                  : Container(
                      color: color,
                      alignment: Alignment.center,
                      child: Icon(_iconFor(item.mediaType), size: 40,
                          color: SeenlyPalette.paper.withOpacity(0.7)),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(item.title.display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.serif(italic: true, size: 17)),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Text(meta, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            ],
          ),
        ],
      ),
    );

    final rotated = rotation == 0 ? card : Transform.rotate(angle: rotation, child: card);

    if (!elevated) return rotated;

    // Only the top, interactive card gets its little piece of tape — a
    // quiet cue that this is the one you're currently holding.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        rotated,
        Positioned(top: -9, left: maxWidth / 2 - 27, child: _TapeAccent(seed: item.title.display)),
      ],
    );
  }

  IconData _iconFor(String mediaType) {
    switch (mediaType) {
      case 'movie':
        return Icons.local_movies_outlined;
      case 'series':
        return Icons.tv_outlined;
      case 'anime':
        return Icons.auto_awesome_outlined;
      case 'game':
        return Icons.sports_esports_outlined;
      default:
        return Icons.movie_filter_outlined;
    }
  }
}

/// A small strip of washi tape, the same touch used on photo-style
/// moments elsewhere in the app — picked from a fixed rotation of muted
/// tones so it never clashes, and stable per-title so a card doesn't
/// flicker between colors as the deck rebuilds.
class _TapeAccent extends StatelessWidget {
  final String seed;

  const _TapeAccent({required this.seed});

  static final _colors = [
    SeenlyPalette.tapeRose,
    SeenlyPalette.tapeSage,
    SeenlyPalette.tapeMustard,
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[seed.hashCode.abs() % _colors.length];
    return Transform.rotate(
      angle: -0.08,
      child: Container(
        width: 54,
        height: 20,
        decoration: BoxDecoration(
          color: color.withOpacity(0.88),
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(color: SeenlyPalette.ink.withOpacity(0.10), blurRadius: 5, offset: const Offset(0, 2)),
          ],
        ),
      ),
    );
  }
}

/// How a recap's matched posters arrive: one after another, each rising
/// into place a beat after the last. Keyed by the title, so a match that
/// turns up later (a network session keeps updating) animates in on its own
/// instead of the whole grid replaying.
Widget _matchGrid(List<MediaItem> matches) {
  return GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 2 / 3,
    children: [
      for (int i = 0; i < matches.length; i++)
        Entrance(
          key: ValueKey<String>('${matches[i].source}:${matches[i].id}'),
          delay: Duration(milliseconds: 260 + 90 * (i > 8 ? 8 : i)),
          duration: const Duration(milliseconds: 480),
          riseBy: 16,
          child: ThemedPosterTile(
            title: matches[i].title.display,
            posterUrl: matches[i].posterUrl,
            fallbackColor: SeenlyPalette.mediaColor(matches[i].mediaType),
            mediaType: matches[i].mediaType,
          ),
        ),
    ],
  );
}

/// The picture at the top of a recap: with matches, a beating heart that
/// opens with a little shower of hearts; without, a moon that slowly
/// breathes — a quiet round, not a failed one.
Widget _recapHeader(bool hasMatches) {
  return SizedBox(
    height: 96,
    child: Center(
      child: hasMatches
          ? const HeartsBurst(reach: 0.55, child: HeartbeatIcon(size: 32))
          : Breathe(child: Icon(Icons.nights_stay_outlined, size: 30, color: SeenlyPalette.accent)),
    ),
  );
}

class _RecapView extends StatelessWidget {
  final List<MediaItem> matches;
  final VoidCallback onSwipeAgain;
  final VoidCallback? onOpenList;

  const _RecapView({required this.matches, required this.onSwipeAgain, this.onOpenList});

  @override
  Widget build(BuildContext context) {
    final hasMatches = matches.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      children: [
        _recapHeader(hasMatches),
        Entrance(
          delay: const Duration(milliseconds: 120),
          riseBy: 12,
          child: Text(
            hasMatches
                ? '${nCount('nMatches', matches.length)}!'
                : 'no matches this round'.tr,
            style: SeenlyText.screenTitle,
          ),
        ),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 180),
          riseBy: 12,
          child: Text(
            hasMatches
                ? 'tucked into your "watch together" list — pick tonight\'s from there.'
                : 'happens sometimes — try a different mood, or shuffle again.',
            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
          ),
        ),
        if (hasMatches) ...[
          const SizedBox(height: 20),
          _matchGrid(matches),
        ],
        const SizedBox(height: 26),
        Entrance(
          delay: Duration(milliseconds: hasMatches ? 500 + 60 * (matches.length > 6 ? 6 : matches.length) : 260),
          riseBy: 12,
          child: Column(
            children: [
              if (onOpenList != null) ...[
                PrimaryButton(label: 'open the list'.tr, onTap: onOpenList),
                const SizedBox(height: 10),
              ],
              TextButton(
                onPressed: onSwipeAgain,
                child: Text('shuffle again'.tr,
                    style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Recap for a network session — you've reached the end of your own deck,
/// but the other person might still be swiping, so this keeps refreshing
/// (via the same live updates) rather than treating the session as final. The
/// other person's progress is a pill you can watch fill, the sentence under
/// the title changes softly as it does, and a match that lands while you're
/// looking arrives on its own.
class _NetRecapView extends StatelessWidget {
  final List<MediaItem> matches;
  final String? partnerUsername;
  final int partnerSwiped;
  final int deckSize;
  final VoidCallback onEnd;
  final VoidCallback? onOpenList;

  const _NetRecapView({
    required this.matches,
    required this.partnerUsername,
    required this.partnerSwiped,
    required this.deckSize,
    required this.onEnd,
    this.onOpenList,
  });

  @override
  Widget build(BuildContext context) {
    final hasMatches = matches.isNotEmpty;
    final partnerDone = deckSize > 0 && partnerSwiped >= deckSize;
    final title = hasMatches
        ? '${nCount('nMatches', matches.length)} ${'so far'.tr}!'
        : "you're through the deck".tr;
    final status = partnerDone
        ? (hasMatches
            ? 'tucked into your "watch together" list — pick tonight\'s from there.'
            : 'no matches this round — try again with a different mood.')
        : '${partnerUsername ?? 'they'} is still swiping ($partnerSwiped of $deckSize) — '
            'this updates as soon as they catch up.';
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      children: [
        _recapHeader(hasMatches),
        Entrance(
          delay: const Duration(milliseconds: 120),
          riseBy: 12,
          child: SoftSwap(
            child: Text(title, key: ValueKey<String>(title), style: SeenlyText.screenTitle),
          ),
        ),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 180),
          riseBy: 12,
          child: SoftSwap(
            child: Text(
              status,
              key: ValueKey<String>(status),
              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
            ),
          ),
        ),
        if (!partnerDone && deckSize > 0) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: DeckPill(
              '${partnerUsername ?? 'they'.tr}: $partnerSwiped ${'of'.tr} $deckSize',
              progress: partnerSwiped / deckSize,
            ),
          ),
        ],
        if (hasMatches) ...[
          const SizedBox(height: 20),
          _matchGrid(matches),
        ],
        const SizedBox(height: 26),
        Entrance(
          delay: const Duration(milliseconds: 300),
          riseBy: 12,
          child: Column(
            children: [
              if (onOpenList != null) ...[
                PrimaryButton(label: 'open the list'.tr, onTap: onOpenList),
                const SizedBox(height: 10),
              ],
              TextButton(
                onPressed: onEnd,
                child: Text('end session'.tr,
                    style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onButtonTap;

  const _MessageView({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onButtonTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Entrance(
          riseBy: 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(italic: true, size: 15, color: SeenlyPalette.inkMuted)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
              const SizedBox(height: 20),
              PrimaryButton(label: buttonLabel, onTap: onButtonTap, expand: false),
            ],
          ),
        ),
      ),
    );
  }
}
