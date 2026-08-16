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
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/how_it_works_sheet.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_poster_tile.dart';
import '../lists/list_detail_screen.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../services/app_translations.dart';

/// Every match — from any session, any device this account has logged in
/// on — lands in the one list with this name. Looked up by name each time
/// rather than an id stashed somewhere, so it behaves exactly like any
/// other list the person could have made by hand (renameable, deletable,
/// nothing schema-special about it). The backend uses the same name for
/// network sessions, so both modes end up in the same place.
const kTogetherListName = 'watch together';

const _pollInterval = Duration(seconds: 2);

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
  // Bumped on every local "together" decision so _MatchPulse knows to play
  // — a one-phone yes is already the both-of-you decision (see
  // how_it_works_sheet.dart, step 3), so this is just a warm little beat
  // confirming it landed, never a second question asking if it's real.
  int _matchPulseTick = 0;

  // --- network state ---
  TogetherSession? _session;
  Timer? _pollTimer;
  int _netIndex = 0;
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
    _pollTimer?.cancel();
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
              title: 'nothing to shuffle right now',
              subtitle: 'try a different category, or check back later',
              buttonLabel: 'back',
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
            title: "couldn't gather any cards",
            subtitle: 'check the connection and try again',
            buttonLabel: 'try again',
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
    _pollTimer?.cancel();
    _pollTimer = null;
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
      _startPolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _showMessage(
            title: "couldn't start a session",
            subtitle: e.message,
            buttonLabel: 'back',
            onTap: _backToSetup,
            phase: _Phase.error,
          ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _showMessage(
            title: "couldn't start a session",
            subtitle: 'check the connection and try again',
            buttonLabel: 'try again',
            onTap: _createNetworkSession,
            phase: _Phase.error,
          ));
    }
  }

  Future<void> _joinNetworkSession() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _joinError = 'codes are 6 characters');
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
      _startPolling();
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
        _joinError = 'check the connection and try again';
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollSession());
  }

  Future<void> _pollSession() async {
    final session = _session;
    if (session == null || !mounted) return;
    try {
      final updated = await context.read<AppState>().together.poll(session.id);
      if (!mounted) return;
      setState(() {
        _session = updated;
        // The host's screen advances from "waiting for a partner" to
        // swiping the moment someone actually joins.
        if (_phase == _Phase.netHostWaiting && updated.partnerJoined) {
          _phase = _Phase.netSwiping;
        }
      });
    } catch (_) {
      // A missed poll just tries again on the next tick — no need to
      // interrupt the person over one dropped request.
    }
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
        _session = updated;
        if (_netIndex >= updated.deck.length) _phase = _Phase.netRecap;
      });
    } catch (_) {
      // Keep the deck moving even if one swipe failed to save — the
      // person can't easily go back to a card anyway, and the poll loop
      // will keep the match list itself accurate regardless.
      if (!mounted) return;
      setState(() {
        if (_netIndex >= (_session?.deck.length ?? 0)) _phase = _Phase.netRecap;
      });
    }
  }

  Future<void> _endNetworkSession() async {
    final session = _session;
    _pollTimer?.cancel();
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
                    icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: _handleBack,
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text('watch together'.tr, style: SeenlyText.screenTitle)),
                  IconButton(
                    icon: const Icon(Icons.help_outline, size: 18, color: SeenlyPalette.inkMuted),
                    tooltip: 'how this works'.tr,
                    onPressed: () => showHowItWorksSheet(context),
                  ),
                  if (_showMatchBadge)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.favorite, size: 13, color: SeenlyPalette.accent),
                          const SizedBox(width: 4),
                          Text('$_liveMatchCount',
                              style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
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
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
              const SizedBox(height: 14),
              Text(
                _phase == _Phase.netStarting ? 'setting up a session…' : 'gathering cards…',
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
              ),
            ],
          ),
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
            IgnorePointer(child: _MatchPulse(tick: _matchPulseTick)),
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
          return const Center(
            child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
          );
        }
        return _NetSwipeDeck(
          deck: session.deck,
          index: _netIndex,
          partnerSwiped: session.partnerSwiped,
          partnerUsername: session.partnerUsername,
          onDecide: _netDecide,
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: SeenlyPalette.accent.withOpacity(0.14),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.favorite, size: 26, color: SeenlyPalette.accent),
        ),
        const SizedBox(height: 18),
        Text('decide together, one card at a time'.tr, style: SeenlyText.screenTitle),
        const SizedBox(height: 8),
        Text(
          isNetwork
              ? 'each on your own phone — whatever you both say yes to '
                  'gets tucked into your "watch together" list, ready for movie night.'
              : 'pass the phone, or just lean in — whatever you both say yes to '
                  'gets tucked into your "watch together" list, ready for movie night.',
          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
        ),
        const SizedBox(height: 26),
        Text('how are you swiping?'.tr, style: SeenlyText.metaLabel),
        const SizedBox(height: 10),
        Row(
          children: [
            PillChip(
              label: 'one phone',
              active: mode == 'local',
              onTap: () => onModeChange('local'),
            ),
            const SizedBox(width: 8),
            PillChip(
              label: 'over the network',
              active: isNetwork,
              onTap: () => onModeChange('network'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('what are we in the mood for?'.tr, style: SeenlyText.metaLabel),
        const SizedBox(height: 10),
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
        const SizedBox(height: 22),
        Row(
          children: [
            Text('any particular genre?'.tr, style: SeenlyText.metaLabel),
            const SizedBox(width: 8),
            if (selectedGenres.isNotEmpty)
              Text('${selectedGenres.length} picked',
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'leave this alone for anything — pick a few to narrow the deck down to just those'.tr,
          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in kTogetherGenreChoices)
              PillChip(
                label: g.toLowerCase(),
                active: selectedGenres.contains(g),
                onTap: () => onGenreToggle(g),
              ),
          ],
        ),
        const SizedBox(height: 30),
        if (!isNetwork)
          PrimaryButton(label: 'start swiping', onTap: onStartLocal)
        else ...[
          PrimaryButton(label: 'start a session', onTap: onCreateNetworkSession),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: onJoinNetworkSession,
              child: Text('have a code already? join instead'.tr,
                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
            ),
          ),
        ],
      ],
    );
  }
}

/// Shown to whoever started the session — a code to send to the other
/// person, and a quiet wait while polling for them to type it in.
class _HostWaitingView extends StatelessWidget {
  final String code;
  final VoidCallback onCancel;

  const _HostWaitingView({required this.code, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('send them this code'.tr, style: SeenlyText.serif(italic: true, size: 15)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              decoration: BoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SeenlyPalette.border),
              ),
              child: Text(
                code,
                style: SeenlyText.mono(size: 26, color: SeenlyPalette.ink, weight: FontWeight.w700)
                    .copyWith(letterSpacing: 6),
              ),
            ),
            const SizedBox(height: 22),
            const SizedBox(
              width: 18,
              height: 18,
              child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
            ),
            const SizedBox(height: 10),
            Text('waiting for them to join…'.tr,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
            const SizedBox(height: 24),
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
        Text('got a code?'.tr, style: SeenlyText.screenTitle),
        const SizedBox(height: 8),
        Text(
          'type in the 6-character code the other person sent you.'.tr,
          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
        ),
        const SizedBox(height: 22),
        TextField(
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
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
        ],
        const SizedBox(height: 22),
        PrimaryButton(label: 'join', onTap: onJoin, loading: busy),
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

class _SwipeDeck extends StatelessWidget {
  final List<MediaItem> deck;
  final int index;
  final void Function(MediaItem item, bool together) onDecide;

  const _SwipeDeck({required this.deck, required this.index, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    final remaining = deck.length - index;
    final current = deck[index];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
          child: _CountPill(remaining == 1 ? 'one left' : '$remaining left'),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxIndex = min(index + 2, deck.length - 1);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = maxIndex; i >= index; i--)
                      Transform.translate(
                        offset: Offset(
                          (i - index) * ((i - index).isOdd ? 9.0 : -9.0),
                          (i - index) * 9.0,
                        ),
                        child: Transform.scale(
                          scale: 1 - (i - index) * 0.045,
                          child: i == index
                              ? _SwipeCard(
                                  key: ValueKey('${deck[i].source}:${deck[i].id}'),
                                  item: deck[i],
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight,
                                  onDecide: (together) => onDecide(deck[i], together),
                                )
                              : _CardFace(
                                  item: deck[i],
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight,
                                  rotation: (i - index).isOdd ? 0.035 : -0.035,
                                ),
                        ),
                      ),
                  ],
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
              _DecisionButton(
                icon: Icons.close,
                label: 'not tonight',
                iconColor: SeenlyPalette.inkMuted,
                background: SeenlyPalette.paper,
                bordered: true,
                onTap: () => onDecide(current, false),
              ),
              _DecisionButton(
                icon: Icons.favorite,
                label: 'together',
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

/// A quiet little beat that plays over the deck right after a one-phone
/// "together" swipe — a soft pop-and-fade, gone in under a second. In
/// this mode the decision is already final the moment it's made (see
/// how_it_works_sheet.dart, step 3: one shared decision, nobody's
/// waiting on anybody), so this is never a question — no "does your
/// partner agree too?" — just a warm little acknowledgment that it
/// landed, the same way a heart might catch someone's eye and neither
/// of you needs to say anything out loud about it.
class _MatchPulse extends StatefulWidget {
  final int tick;
  const _MatchPulse({required this.tick});

  @override
  State<_MatchPulse> createState() => _MatchPulseState();
}

class _MatchPulseState extends State<_MatchPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.72, end: 1.08).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 40,
    ),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95), weight: 20),
  ]).animate(_controller);
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 33),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant _MatchPulse old) {
    super.didUpdateWidget(old);
    if (widget.tick != old.tick && widget.tick > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.isDismissed) return const SizedBox.shrink();
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(scale: _scale.value, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: SeenlyPalette.ink.withOpacity(0.16), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite, size: 22, color: SeenlyPalette.accent),
            const SizedBox(height: 6),
            Text('settled, together'.tr,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// The small "N left" readout at the top of a deck — a soft pill instead
/// of bare mono text, so it reads as a gentle status rather than a counter
/// ticking down.
class _CountPill extends StatelessWidget {
  final String label;

  const _CountPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Text(label, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
    );
  }
}

/// Same swiping surface as [_SwipeDeck], with a quiet line showing how far
/// along the other person is — the only sense of "togetherness" possible
/// when the two of you aren't looking at the same screen.
class _NetSwipeDeck extends StatelessWidget {
  final List<MediaItem> deck;
  final int index;
  final int partnerSwiped;
  final String? partnerUsername;
  final void Function(MediaItem item, bool together) onDecide;

  const _NetSwipeDeck({
    required this.deck,
    required this.index,
    required this.partnerSwiped,
    required this.partnerUsername,
    required this.onDecide,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = deck.length - index;
    final current = deck[index];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CountPill(remaining == 1 ? 'one left' : '$remaining left'),
              _CountPill('${partnerUsername ?? 'they'}: $partnerSwiped of ${deck.length}'),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxIndex = min(index + 2, deck.length - 1);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = maxIndex; i >= index; i--)
                      Transform.translate(
                        offset: Offset(
                          (i - index) * ((i - index).isOdd ? 9.0 : -9.0),
                          (i - index) * 9.0,
                        ),
                        child: Transform.scale(
                          scale: 1 - (i - index) * 0.045,
                          child: i == index
                              ? _SwipeCard(
                                  key: ValueKey('${deck[i].source}:${deck[i].id}'),
                                  item: deck[i],
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight,
                                  onDecide: (together) => onDecide(deck[i], together),
                                )
                              : _CardFace(
                                  item: deck[i],
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight,
                                  rotation: (i - index).isOdd ? 0.035 : -0.035,
                                ),
                        ),
                      ),
                  ],
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
              _DecisionButton(
                icon: Icons.close,
                label: 'not tonight',
                iconColor: SeenlyPalette.inkMuted,
                background: SeenlyPalette.paper,
                bordered: true,
                onTap: () => onDecide(current, false),
              ),
              _DecisionButton(
                icon: Icons.favorite,
                label: 'together',
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

/// The top card in the stack — draggable horizontally; releasing far
/// enough either commits the same decision as tapping a button below.
class _SwipeCard extends StatelessWidget {
  final MediaItem item;
  final double maxWidth;
  final double maxHeight;
  final ValueChanged<bool> onDecide;

  const _SwipeCard({
    super.key,
    required this.item,
    required this.maxWidth,
    required this.maxHeight,
    required this.onDecide,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.horizontal,
      onDismissed: (direction) => onDecide(direction == DismissDirection.startToEnd),
      background: _SwipeHint(
        alignment: Alignment.centerLeft,
        icon: Icons.favorite,
        label: 'together',
        color: SeenlyPalette.accent,
      ),
      secondaryBackground: _SwipeHint(
        alignment: Alignment.centerRight,
        icon: Icons.close,
        label: 'not tonight',
        color: SeenlyPalette.inkMuted,
      ),
      child: _CardFace(item: item, maxWidth: maxWidth, maxHeight: maxHeight, elevated: true),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;
  final Color color;

  const _SwipeHint({
    required this.alignment,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: SeenlyPalette.ink.withOpacity(0.14), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: SeenlyPalette.paper, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper, weight: FontWeight.w600)),
        ],
      ),
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

  static const _colors = [
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

/// One decision button — a soft circle with a warm, ink-toned shadow
/// (never the flat black kind) and a small mono label underneath so the
/// two choices are legible on their own, without a caption line elsewhere
/// on the screen doing the explaining for them.
class _DecisionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color background;
  final bool large;
  final bool bordered;
  final VoidCallback onTap;

  const _DecisionButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.background,
    required this.onTap,
    this.large = false,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 52.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: bordered ? Border.all(color: SeenlyPalette.border) : null,
              boxShadow: [
                BoxShadow(
                  color: SeenlyPalette.ink.withOpacity(large ? 0.16 : 0.08),
                  blurRadius: large ? 18 : 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: large ? 26 : 20, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(label, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
        ],
      ),
    );
  }
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
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      children: [
        Icon(hasMatches ? Icons.favorite : Icons.nights_stay_outlined,
            size: 30, color: SeenlyPalette.accent),
        const SizedBox(height: 14),
        Text(
          hasMatches
              ? (matches.length == 1 ? 'one match!' : '${matches.length} matches!')
              : 'no matches this round',
          style: SeenlyText.screenTitle,
        ),
        const SizedBox(height: 8),
        Text(
          hasMatches
              ? 'tucked into your "watch together" list — pick tonight\'s from there.'
              : 'happens sometimes — try a different mood, or shuffle again.',
          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
        ),
        if (hasMatches) ...[
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2 / 3,
            children: [
              for (final m in matches)
                ThemedPosterTile(
                  title: m.title.display,
                  posterUrl: m.posterUrl,
                  fallbackColor: SeenlyPalette.mediaColor(m.mediaType),
                  mediaType: m.mediaType,
                ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        if (onOpenList != null) ...[
          PrimaryButton(label: 'open the list', onTap: onOpenList),
          const SizedBox(height: 10),
        ],
        Center(
          child: TextButton(
            onPressed: onSwipeAgain,
            child: Text('shuffle again'.tr,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
          ),
        ),
      ],
    );
  }
}

/// Recap for a network session — you've reached the end of your own deck,
/// but the other person might still be swiping, so this keeps refreshing
/// (via the same poll loop) rather than treating the session as final.
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      children: [
        Icon(hasMatches ? Icons.favorite : Icons.nights_stay_outlined,
            size: 30, color: SeenlyPalette.accent),
        const SizedBox(height: 14),
        Text(
          hasMatches
              ? (matches.length == 1 ? 'one match so far!' : '${matches.length} matches so far!')
              : "you're through the deck",
          style: SeenlyText.screenTitle,
        ),
        const SizedBox(height: 8),
        Text(
          partnerDone
              ? (hasMatches
                  ? 'tucked into your "watch together" list — pick tonight\'s from there.'
                  : 'no matches this round — try again with a different mood.')
              : '${partnerUsername ?? 'they'} is still swiping ($partnerSwiped of $deckSize) — '
                  'this updates as soon as they catch up.',
          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
        ),
        if (hasMatches) ...[
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2 / 3,
            children: [
              for (final m in matches)
                ThemedPosterTile(
                  title: m.title.display,
                  posterUrl: m.posterUrl,
                  fallbackColor: SeenlyPalette.mediaColor(m.mediaType),
                  mediaType: m.mediaType,
                ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        if (onOpenList != null) ...[
          PrimaryButton(label: 'open the list', onTap: onOpenList),
          const SizedBox(height: 10),
        ],
        Center(
          child: TextButton(
            onPressed: onEnd,
            child: Text('end session'.tr,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
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
    );
  }
}
