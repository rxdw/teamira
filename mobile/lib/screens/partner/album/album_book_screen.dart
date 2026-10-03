import 'package:flutter/material.dart';

import '../../../models/pair_album.dart';
import '../../../services/api_client.dart';
import '../../../services/error_text.dart';
import '../../../services/locale_service.dart';
import '../../../services/pair_album_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../utils/album_dates.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/themed_loading_indicator.dart';
import '../../../widgets/themed_pull_to_refresh.dart';
import '../../../widgets/wow_motion.dart';
import 'album_strings.dart';
import 'album_widgets.dart';
import 'note_compose_sheet.dart';
import 'note_reveal_screen.dart';

/// "Общая книга" — the shared book of notes.
///
/// Two lists, mirroring the two states a note can be in:
///  * **ждут вечера** — titles where somebody has left a sealed note. You
///    see your own words; the partner's side is only ever an envelope.
///  * **страницы** — evenings that have been watched, with both notes
///    unsealed side by side, newest first.
///
/// Nothing on this screen is premium-gated to *read*; writing a note from
/// here goes through the compose sheet, which sends a circle whose free
/// notes are spent to the paywall (rewriting a note already left is free).
class AlbumBookScreen extends StatefulWidget {
  final AlbumStatus status;
  const AlbumBookScreen({super.key, required this.status});

  @override
  State<AlbumBookScreen> createState() => _AlbumBookScreenState();
}

class _AlbumBookScreenState extends State<AlbumBookScreen> {
  late final PairAlbumService _service = PairAlbumService(ApiClient.instance);

  late AlbumStatus _status = widget.status;
  List<AlbumPage> _waiting = const [];
  List<AlbumPage> _pages = const [];
  DateTime? _nextBefore;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  String get _partnerName => _status.partner?.name ?? at('партнёр', 'partner');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait<Object>([
        _service.status(),
        _service.waitingNotes(),
        _service.pages(),
      ]);
      if (!mounted) return;
      final pages = results[2] as AlbumPages;
      setState(() {
        _status = results[0] as AlbumStatus;
        _waiting = results[1] as List<AlbumPage>;
        _pages = pages.items;
        _nextBefore = pages.nextBefore;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(e);
      });
    }
  }

  Future<void> _loadMore() async {
    final before = _nextBefore;
    if (before == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _service.pages(before: before);
      if (!mounted) return;
      setState(() {
        _pages = [..._pages, ...more.items];
        _nextBefore = more.nextBefore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _writeFor(AlbumPage page) async {
    final result = await showNoteComposeSheet(
      context,
      item: page.toMediaItem(),
      partnerName: _partnerName,
      status: _status,
      existing: page,
    );
    if (result != null && mounted) await _load(silent: true);
  }

  Future<void> _openPage(AlbumPage page) async {
    if (!page.unread) return;
    await showPageReveal(context, page: page, partnerName: _partnerName);
    if (mounted) await _load(silent: true);
  }

  Future<void> _react(AlbumPage page, String? emoji) async {
    final note = page.partner;
    if (note == null) return;
    try {
      await _service.react(note.id, emoji);
      if (mounted) await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: ThemedPullToRefresh(
          onRefresh: () => _load(silent: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: ThemedLoadingIndicator()),
                )
              else if (_error != null)
                SliverFillRemaining(hasScrollBody: false, child: _errorState())
              else ...[
                if (_waiting.isEmpty && _pages.isEmpty)
                  SliverToBoxAdapter(child: _emptyState())
                else ...[
                  if (_waiting.isNotEmpty) ..._waitingSlivers(),
                  if (_pages.isNotEmpty) ..._pageSlivers(),
                ],
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back, size: 20, color: SeenlyPalette.ink),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Entrance(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(at('общая книга', 'our book'), style: SeenlyText.screenTitle),
                  const SizedBox(height: 4),
                  Text(
                    at(
                      'записки друг другу: до вечера запечатаны, после — открываются',
                      'notes for each other: sealed until the evening, open after',
                    ),
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
                  ),
                  if (!_loading && _error == null && (_pages.isNotEmpty || _waiting.isNotEmpty)) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _StatPill(
                          icon: Icons.auto_stories_rounded,
                          label: at('страниц: ${_status.pagesCount}', 'pages: ${_status.pagesCount}'),
                          color: SeenlyPalette.accent,
                        ),
                        const SizedBox(width: 8),
                        if (_waiting.isNotEmpty)
                          _StatPill(
                            icon: Icons.mail_outline_rounded,
                            label: at('ждут вечера: ${_waiting.length}', 'waiting: ${_waiting.length}'),
                            color: SeenlyPalette.coral,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
      child: Entrance(
        delay: const Duration(milliseconds: 120),
        child: Column(
          children: [
            BreathingGlow(
              color: SeenlyPalette.coral,
              size: 280,
              child: const EnvelopeView(progress: 0, width: 200),
            ),
            const SizedBox(height: 20),
            Text(
              at('здесь будут ваши записки друг другу', 'your notes to each other will live here'),
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 17, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              at(
                'напишите первую перед вечером: откройте запланированный фильм на вкладке «вместе» '
                    'и оставьте записку — партнёр прочтёт её, когда вы досмотрите',
                'write the first one before an evening: open a planned film on the "together" tab '
                    'and leave a note — your partner reads it once you\'ve watched',
              ),
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? '', textAlign: TextAlign.center, style: SeenlyText.emptyState()),
            const SizedBox(height: 16),
            ClayButton(
              label: at('повторить', 'retry'),
              expand: false,
              onTap: _load,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _waitingSlivers() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: SectionHeader(title: at('ждут вечера', 'waiting for their evening')),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final page = _waiting[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Entrance(
                key: ValueKey('waiting-${page.key}'),
                delay: Duration(milliseconds: 60 * (i % 5)),
                riseBy: 16,
                child: _WaitingCard(
                  page: page,
                  partnerName: _partnerName,
                  onTap: () => _writeFor(page),
                ),
              ),
            );
          },
          childCount: _waiting.length,
        ),
      ),
    ];
  }

  List<Widget> _pageSlivers() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: SectionHeader(title: at('страницы', 'pages')),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final page = _pages[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Entrance(
                key: ValueKey('page-${page.key}-${page.round}'),
                delay: Duration(milliseconds: 60 * (i % 5)),
                riseBy: 18,
                child: _PageCard(
                  page: page,
                  partnerName: _partnerName,
                  tiltSeed: i,
                  onOpen: () => _openPage(page),
                  onReact: (emoji) => _react(page, emoji),
                ),
              ),
            );
          },
          childCount: _pages.length,
        ),
      ),
      if (_nextBefore != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              child: ClayButton(
                label: at('показать ещё', 'show more'),
                expand: false,
                loading: _loadingMore,
                onTap: _loadMore,
              ),
            ),
          ),
        ),
    ];
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: SeenlyText.mono(size: 11.5, weight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// A title with a sealed note on it, from either side.
class _WaitingCard extends StatelessWidget {
  final AlbumPage page;
  final String partnerName;
  final VoidCallback onTap;
  const _WaitingCard({required this.page, required this.partnerName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final hasMine = page.mine != null;
    return PressScale(
      onTap: onTap,
      scaleTo: 0.98,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AlbumPoster(url: page.posterUrl, width: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title(ru: ru),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: 15.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _StatusLine(
                    icon: hasMine ? Icons.mark_email_read_outlined : Icons.edit_outlined,
                    color: hasMine ? SeenlyPalette.sage : SeenlyPalette.accent,
                    text: hasMine
                        ? at('ваша записка готова', 'your note is ready')
                        : at('написать записку', 'write a note'),
                  ),
                  const SizedBox(height: 6),
                  _StatusLine(
                    icon: page.partnerSealed ? Icons.mail_rounded : Icons.hourglass_empty_rounded,
                    color: page.partnerSealed ? SeenlyPalette.coral : SeenlyPalette.inkFaint,
                    pulse: page.partnerSealed,
                    text: page.partnerSealed
                        ? at('записка от $partnerName запечатана', 'a sealed note from $partnerName')
                        : at('$partnerName пока ничего не оставил(а)', '$partnerName hasn\'t left one yet'),
                  ),
                  if (hasMine) ...[
                    const SizedBox(height: 10),
                    Text(
                      '«${page.mine!.body}»',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.handwrittenNote(size: 15, color: SeenlyPalette.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool pulse;
  const _StatusLine({required this.icon, required this.color, required this.text, this.pulse = false});

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 15, color: color);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        pulse ? BreathingGlow(color: color, size: 26, child: iconWidget) : iconWidget,
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted)),
        ),
      ],
    );
  }
}

/// One watched evening: both notes unsealed, or — if the partner's hasn't
/// been opened yet by this person — an envelope waiting to be tapped.
class _PageCard extends StatelessWidget {
  final AlbumPage page;
  final String partnerName;
  final int tiltSeed;
  final VoidCallback onOpen;
  final ValueChanged<String?> onReact;
  const _PageCard({
    required this.page,
    required this.partnerName,
    required this.tiltSeed,
    required this.onOpen,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final date = page.eveningOn ?? page.revealedAt;
    final theirs = page.partner;
    final mine = page.mine;
    // Alternate the lean so a column of pages reads as pinned, not ruled.
    final lean = (tiltSeed.isEven ? 1 : -1) * 0.012;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AlbumPoster(url: page.posterUrl, width: 34, radius: 6),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title(ru: ru),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: 15, weight: FontWeight.w600),
                  ),
                  if (date != null)
                    Text(
                      albumDateLabel(date, ru: ru),
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
                    ),
                ],
              ),
            ),
            if (page.unread)
              BreathingGlow(
                color: SeenlyPalette.coral,
                size: 56,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.coral,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    at('новое', 'new'),
                    style: SeenlyText.mono(size: 10.5, weight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (theirs != null)
          page.unread
              ? GestureDetector(
                  onTap: onOpen,
                  behavior: HitTestBehavior.opaque,
                  child: SealedNotePaper(
                    label: at(
                      'записка от $partnerName — нажмите, чтобы открыть',
                      'a note from $partnerName — tap to open',
                    ),
                    tint: SeenlyPalette.coral,
                    tilt: lean,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NotePaper(
                      body: theirs.body,
                      mood: theirs.mood,
                      byline: albumByline(mine: false, name: partnerName),
                      reaction: theirs.reaction,
                      tilt: lean,
                      fontSize: 17,
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: EmojiChoiceRow(
                        options: kAlbumReactions,
                        selected: theirs.reaction,
                        onChanged: onReact,
                        size: 15,
                      ),
                    ),
                  ],
                ),
        if (theirs != null && mine != null) const SizedBox(height: 12),
        if (mine != null)
          NotePaper(
            body: mine.body,
            mood: mine.mood,
            byline: albumByline(mine: true, name: partnerName),
            reaction: mine.reaction,
            tint: SeenlyPalette.periwinkle,
            tilt: -lean,
            fontSize: 16,
          ),
      ],
    );
  }
}
