import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ai_response.dart';
import '../../models/media_item.dart';
import '../../services/api_client.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/scroll_reveal.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/wow_motion.dart' show Entrance, PressScale;
import '../decide/decide_ask_teamira_screen.dart';
import '../decide/decide_filters_screen.dart';
import '../title/title_detail_screen.dart';
import 'co_view_vote_screen.dart' show proposeToCircle;

/// "Ask teamira" as a can't-decide method for the whole circle — the
/// exact same composer as the solo version on Home
/// ([DecideAskTeamiraScreen]: shimmering hero, editable starting
/// sentence, tappable example prompts), just pointed at
/// [CoViewAskTeamiraResultsScreen] instead of Home's own results screen
/// via [DecideAskTeamiraScreen.resultsBuilder] — that's the one thing
/// that has to differ, since proposing a pick to the whole circle isn't
/// something the solo results screen's "tap to open" cards do.
///
/// No filters step first (unlike Home's own entry into this screen) —
/// co-viewing doesn't have a type/genre/decade filter concept, just the
/// personal/coview/both/catalog pool the *other* methods ask about — so
/// this passes a neutral, nothing-narrowed-down [DecideFilters] as the
/// starting point for teamira's suggested opening line and examples.
class CoViewAskTeamiraScreen extends StatelessWidget {
  const CoViewAskTeamiraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DecideAskTeamiraScreen(
      filters: const DecideFilters(types: kDecidePickableTypes, genres: {}, decade: null),
      resultsBuilder: (query) => CoViewAskTeamiraResultsScreen(query: query),
    );
  }
}


/// Teamira's shortlist for [query] — same ranked results as Home's own
/// [AskTeamiraResultsScreen], just rendered as a plain proposable list
/// instead of a hero+grid you tap into a title from: each row's "propose"
/// action puts that one pick up for the whole circle via [proposeToCircle]
/// rather than opening [TitleDetailScreen] to add it to a personal shelf.
class CoViewAskTeamiraResultsScreen extends StatefulWidget {
  final String query;
  const CoViewAskTeamiraResultsScreen({super.key, required this.query});

  @override
  State<CoViewAskTeamiraResultsScreen> createState() => _CoViewAskTeamiraResultsScreenState();
}

class _CoViewAskTeamiraResultsScreenState extends State<CoViewAskTeamiraResultsScreen> {
  late Future<List<AiMatch>> _future;
  final Set<String> _proposing = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AiMatch>> _load() async {
    final app = context.read<AppState>();
    final response = await app.ai.ask(widget.query);
    return response.results;
  }

  Future<void> _retry() async {
    setState(() => _future = _load());
  }

  Future<void> _propose(MediaItem item) async {
    final key = '${item.source}:${item.id}';
    setState(() => _proposing.add(key));
    final winner = await proposeToCircle(
      context,
      item,
      onRetry: () => Navigator.of(context).pop(),
    );
    if (!mounted) return;
    setState(() => _proposing.remove(key));
    if (winner != null) {
      Navigator.of(context).pop(winner);
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
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
              child: Row(
                children: [
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Entrance(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('teamira picked these', style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            '"${widget.query}"',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Entrance(
                delay: const Duration(milliseconds: 70),
                riseBy: 10,
                child: Text(
                  'tap propose on any of these to put it up for a vote',
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<AiMatch>>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return const Center(child: ThemedLoadingIndicator());
                  }
                  if (snapshot.hasError) {
                    final message = snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : "couldn't reach teamira's catalog just now";
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Entrance(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_awesome_outlined, size: 26, color: SeenlyPalette.placeholder),
                              const SizedBox(height: 10),
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
                              ),
                              const SizedBox(height: 14),
                              PressScale(
                                onTap: _retry,
                                child: Text('tap to try again', style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  final matches = snapshot.data!;
                  if (matches.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Entrance(
                          child: Text(
                            "nothing matched that — try describing it differently",
                            textAlign: TextAlign.center,
                            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                    itemCount: matches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final match = matches[i];
                      final key = '${match.item.source}:${match.item.id}';
                      return ScrollRevealEntrance(
                        index: i,
                        child: _MatchRow(
                          match: match,
                          busy: _proposing.contains(key),
                          onPropose: () => _propose(match.item),
                        ),
                      );
                    },
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

class _MatchRow extends StatelessWidget {
  final AiMatch match;
  final bool busy;
  final VoidCallback onPropose;
  const _MatchRow({required this.match, required this.busy, required this.onPropose});

  @override
  Widget build(BuildContext context) {
    final item = match.item;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: ThemedPosterTile(
              title: item.title.display,
              posterUrl: item.posterUrl,
              mediaType: item.mediaType,
              fallbackColor: SeenlyPalette.mediaColor(item.mediaType),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TitleDetailScreen(
                    mediaId: item.id,
                    source: item.source,
                    mediaType: item.mediaType,
                    seedTitle: item.title.display,
                    seedPosterUrl: item.posterUrl,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title.display, style: SeenlyText.serif(size: 14.5, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('${match.match}% match', style: SeenlyText.mono(size: 10, color: SeenlyPalette.periwinkle)),
                if (match.reasoning != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    match.reasoning!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(italic: true, size: 11.5, color: SeenlyPalette.inkMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          PressScale(
            onTap: busy ? null : onPropose,
            haptics: true,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: SeenlyPalette.accent,
                borderRadius: BorderRadius.circular(10),
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
                        'propose',
                        key: const ValueKey('label'),
                        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.accentOnAccent),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
