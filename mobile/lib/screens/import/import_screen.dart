import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/import_row.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/interest_picker.dart' show kInterests;
import '../../widgets/poster_tile.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/soft_motion.dart';
import '../../widgets/tane_thinking.dart' show paintSparkle;
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart'
    show Entrance, PressScale, CountUpNumber, FadeInNetworkImage;
import '../../services/app_translations.dart';
import '../../services/log_theme_service.dart';

enum _Phase { input, loading, review, importing, done }


/// Bring-your-history-over: paste a plain title list (one per line,
/// optionally "Title (Year)") or a CSV export from Letterboxd or a similar
/// service, review what got matched, and commit each row as either
/// watched or plan-to-watch. Reachable from Settings on its own — regular
/// paper theme there — and as a step inside onboarding, where [embedded]
/// both swaps the back arrow for a "skip for now" / calls [onDone]
/// instead of popping, and switches the whole screen to the same dark,
/// star-scattered evening world the rest of onboarding uses, so this
/// doesn't read as a sudden drop back into a form.
class ImportScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onDone;

  const ImportScreen({super.key, this.embedded = false, this.onDone});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _controller = TextEditingController();
  _Phase _phase = _Phase.input;
  String _defaultStatus = 'watched'; // "watched" | "watch_later"
  ImportPreviewResult? _preview;
  ImportCommitResult? _committed;
  String? _error;

  bool get _dark => widget.embedded;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _findMatches() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final result = await context
          .read<AppState>()
          .import_
          .preview(text, defaultStatus: _defaultStatus);
      if (!mounted) return;
      setState(() {
        _preview = result;
        _phase = _Phase.review;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.input;
        _error = "couldn't match those just now — try again in a moment".tr;
      });
    }
  }

  Future<void> _commit() async {
    final rows = _preview?.rows ?? [];
    setState(() => _phase = _Phase.importing);
    try {
      final result = await context.read<AppState>().import_.commit(rows);
      if (!mounted) return;
      setState(() {
        _committed = result;
        _phase = _Phase.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.review;
        _error = "couldn't save those just now — try again".tr;
      });
    }
  }

  int get _selectedCount =>
      _preview?.rows.where((r) => r.selected && r.chosen != null).length ?? 0;

  /// The pasted list, one entry per non-empty line — what the "matching"
  /// screen plays back to you while it works.
  List<String> get _typedLines => _splitLines(_controller.text);

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 18, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!widget.embedded)
                  IconButton(
                    icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                if (!widget.embedded) const SizedBox(width: 4),
                // No maxLines/overflow tricks needed anymore: "skip for
                // now" moved from a default TextButton (which claims a
                // wide 48dp tap target regardless of its text) to a
                // compact pill the same size as its label — that alone
                // was what freed up enough room for the title to
                // always fit on one line.
                Expanded(
                  child: Text(
                    'import your history'.tr,
                    style: SeenlyText.screenTitle.copyWith(
                      // SeenlyPalette.paper is ambient — it flips to a dark
                      // espresso-brown in dark app theme, which made this
                      // title nearly invisible against onboarding's always-
                      // dark backdrop. paperOnDark is the fixed light tone
                      // this screen actually needs here (see the same fix
                      // in onboarding_screen.dart's _onboardingPaper).
                      color: _dark ? SeenlyPalette.paperOnDark : null,
                    ),
                    maxLines: 2,
                  ),
                ),
                // The "skip for now" pill is only there on the first step;
                // it eases in and out (and the title makes way for it)
                // instead of blinking.
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerRight,
                  child: SoftSwap(
                    alignment: Alignment.centerRight,
                    child: widget.embedded && _phase == _Phase.input
                        ? Padding(
                            key: const ValueKey<String>('skip'),
                            padding: const EdgeInsets.only(left: 10),
                            child: PillChip(label: 'skip for now'.tr, dashed: true, onTap: widget.onDone),
                          )
                        : const SizedBox(key: ValueKey<String>('no-skip'), height: 1),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            // Paste → matching → review → adding → done glide into one
            // another rather than cutting.
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
    );

    // Embedded inside onboarding, this step owns none of its own
    // background — the parent OnboardingScreen already paints one
    // continuous aurora + starfield + constellation sky behind every
    // step (see onboarding_screen.dart), and this used to paint a flat
    // _kNight Scaffold with its own separate, plainer starfield on top
    // of it, which completely hid that shared sky and made this one
    // step look like a different, flatter screen bolted onto the flow.
    // Just returning the content transparently lets the same sky show
    // through here too.
    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: content,
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.input:
        return _InputStep(
          controller: _controller,
          defaultStatus: _defaultStatus,
          error: _error,
          dark: _dark,
          onStatusChanged: (v) => setState(() => _defaultStatus = v),
          onSubmit: _findMatches,
        );
      case _Phase.loading:
        return _MatchingStep(
          lines: _typedLines,
          message: 'looking these up in the catalog…'.tr,
          dark: _dark,
        );
      case _Phase.review:
        return _ReviewStep(
          preview: _preview!,
          selectedCount: _selectedCount,
          error: _error,
          dark: _dark,
          onChanged: () => setState(() {}),
          onBack: () => setState(() => _phase = _Phase.input),
          onImport: _commit,
        );
      case _Phase.importing:
        return _AddingStep(
          rows: [
            for (final r in _preview?.rows ?? const <ImportRow>[])
              if (r.selected && r.chosen != null) r,
          ],
          message: 'adding these to your diary…'.tr,
          dark: _dark,
        );
      case _Phase.done:
        return _DoneStep(result: _committed!, embedded: widget.embedded, onDone: widget.onDone);
    }
  }
}

/// The pasted text as one entry per non-empty line.
List<String> _splitLines(String text) => [
      for (final line in text.split(RegExp(r'\r?\n')))
        if (line.trim().isNotEmpty) line.trim(),
    ];

/// One place someone might already be tracking their history, grouped by
/// what it mainly covers. Picking one just swaps the instructions and the
/// paste-box hint — the actual import still works off whatever text ends
/// up in the box, so any export (or a hand-typed list) works regardless
/// of which card is selected.
class _ImportSource {
  final String id;
  final String label;
  final IconData icon;
  final String logoDomain;
  final String instructions;
  final String hint;

  const _ImportSource({
    required this.id,
    required this.label,
    required this.icon,
    required this.logoDomain,
    required this.instructions,
    required this.hint,
  });

  /// The service's real, current logo — fetched by domain rather than
  /// bundled, so it's never a hand-drawn stand-in. [_SourceCard] falls
  /// back to [icon] if the network is unavailable or the mark can't
  /// be found for that domain.
  String get logoUrl => 'https://logo.clearbit.com/$logoDomain?size=64';
}

class _ImportSourceGroup {
  final String label;
  final List<_ImportSource> sources;
  const _ImportSourceGroup({required this.label, required this.sources});
}

const _plainListHint =
    'Amélie (2001)\nParasite (2019)\nThe Bear\nElden Ring\nChainsaw Man\n…one title per line, any kind';

const _importGroups = <_ImportSourceGroup>[
  _ImportSourceGroup(
    label: 'movies & TV',
    sources: [
      _ImportSource(
        id: 'letterboxd',
        label: 'Letterboxd',
        icon: Icons.local_movies_outlined,
        logoDomain: 'letterboxd.com',
        instructions: 'Settings → Import & Export → Export, then open watched.csv '
            '(or watchlist.csv) and paste its contents below.',
        hint: 'Amélie (2001)\nParasite (2019)\n…or paste a Letterboxd export here',
      ),
      _ImportSource(
        id: 'imdb',
        label: 'IMDb',
        icon: Icons.movie_outlined,
        logoDomain: 'imdb.com',
        instructions: 'Your Ratings page → Export (or a watchlist → the ⋯ menu → Export), '
            'then open the CSV and paste the Title column below.',
        hint: 'Amélie\nParasite\n…or paste an IMDb export here',
      ),
      _ImportSource(
        id: 'trakt',
        label: 'Trakt',
        icon: Icons.tv_outlined,
        logoDomain: 'trakt.tv',
        instructions: 'Open a list → the ⋯ menu → Export as CSV, then paste the '
            'titles column below.',
        hint: 'Amélie\nParasite\n…or paste a Trakt export here',
      ),
    ],
  ),
  _ImportSourceGroup(
    label: 'books',
    sources: [
      _ImportSource(
        id: 'goodreads',
        label: 'Goodreads',
        icon: Icons.menu_book_outlined,
        logoDomain: 'goodreads.com',
        instructions: 'My Books → Import/Export → Export Library, then open the CSV '
            'and paste the Title column below.',
        hint: 'Piranesi\nThe Bell Jar\n…or paste a Goodreads export here',
      ),
      _ImportSource(
        id: 'storygraph',
        label: 'The StoryGraph',
        icon: Icons.auto_stories_outlined,
        logoDomain: 'thestorygraph.com',
        instructions: 'Settings → Manage Your Account → Export StoryGraph Data, '
            'then paste the titles from the CSV below.',
        hint: 'Piranesi\nThe Bell Jar\n…or paste a StoryGraph export here',
      ),
    ],
  ),
  _ImportSourceGroup(
    label: 'games',
    sources: [
      _ImportSource(
        id: 'backloggd',
        label: 'Backloggd',
        icon: Icons.videogame_asset_outlined,
        logoDomain: 'backloggd.com',
        instructions: 'Your profile → the games list → Export, then paste the '
            'game titles below.',
        hint: 'Hades\nOuter Wilds\n…or paste a Backloggd export here',
      ),
      _ImportSource(
        id: 'hltb',
        label: 'HowLongToBeat',
        icon: Icons.sports_esports_outlined,
        logoDomain: 'howlongtobeat.com',
        instructions: "Your profile → Games, then just type or paste the titles "
            "you see there below — HLTB doesn't offer a CSV export.",
        hint: 'Hades\nOuter Wilds\n…paste titles from your list here',
      ),
    ],
  ),
  _ImportSourceGroup(
    label: 'anime & manga',
    sources: [
      _ImportSource(
        id: 'mal',
        label: 'MyAnimeList',
        icon: Icons.animation_outlined,
        logoDomain: 'myanimelist.net',
        instructions: 'Panel → List → Export List, then open the file and paste '
            'the titles below.',
        hint: 'Frieren\nVinland Saga\n…or paste a MAL export here',
      ),
      _ImportSource(
        id: 'anilist',
        label: 'AniList',
        icon: Icons.auto_awesome_outlined,
        logoDomain: 'anilist.co',
        instructions: 'Settings → Import/Export → Export Data, then paste the '
            'titles from your list below.',
        hint: 'Frieren\nVinland Saga\n…or paste an AniList export here',
      ),
    ],
  ),
];

class _InputStep extends StatefulWidget {
  final TextEditingController controller;
  final String defaultStatus;
  final String? error;
  final bool dark;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onSubmit;

  const _InputStep({
    required this.controller,
    required this.defaultStatus,
    required this.error,
    required this.dark,
    required this.onStatusChanged,
    required this.onSubmit,
  });

  @override
  State<_InputStep> createState() => _InputStepState();
}

class _InputStepState extends State<_InputStep> {
  // null = "just paste a plain list", no particular service in mind.
  String? _sourceId;

  _ImportSource? get _source {
    if (_sourceId == null) return null;
    for (final group in _importGroups) {
      for (final s in group.sources) {
        if (s.id == _sourceId) return s;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final dark = widget.dark;
    // Fixed light tone when embedded in onboarding, not the ambient
    // SeenlyPalette.paper — that one turns dark-brown in dark app theme
    // and made the pasted text (and everything else below keyed off
    // `dark`) unreadable against onboarding's permanently dark backdrop.
    final textColor = dark ? SeenlyPalette.paperOnDark : SeenlyPalette.ink;
    final mutedColor = dark ? Colors.white.withOpacity(0.62) : SeenlyPalette.inkMuted;
    final faintColor = dark ? Colors.white.withOpacity(0.42) : SeenlyPalette.placeholder;
    // The page settles in from the top: each block a beat after the one
    // above it.
    Widget settle(int n, Widget child) => Entrance(
          delay: Duration(milliseconds: 55 * n),
          duration: const Duration(milliseconds: 460),
          riseBy: 12,
          child: child,
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
      children: [
        settle(0, Text(
          'already keeping track somewhere else? bring it over — paste a plain list of titles, or an export from any of the services below, and tanè will match each one against the right shelf on its own.'.tr,
          style: SeenlyText.serif(italic: true, size: 12, color: mutedColor),
        )),
        const SizedBox(height: 14),
        // The one thing people skimming this screen tend to miss: typing
        // titles in yourself is a first-class option here, not a
        // fallback for when you don't have an account to match — and it
        // isn't movies-only. Given its own heading (same weight as
        // "import from" below) and a row of the same categorical colors
        // the rest of the app already uses for media type, so it reads
        // as a real option at a glance rather than fine print.
        settle(1, Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.edit_note, size: 20, color: SeenlyPalette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('or just type it in'.tr,
                  style: SeenlyText.sectionTitle.copyWith(color: SeenlyPalette.accent)),
            ),
          ],
        )),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // The kinds of thing it takes, one chip after another.
            for (final (ci, interest) in kInterests.indexed)
              Entrance(
                delay: Duration(milliseconds: 160 + 40 * ci),
                duration: const Duration(milliseconds: 380),
                riseBy: 8,
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: SeenlyPalette.mediaColor(interest.value).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SeenlyPalette.mediaColor(interest.value).withOpacity(0.4)),
                ),
                child: Text(
                  interest.label.tr,
                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.mediaColor(interest.value))
                      .copyWith(fontWeight: FontWeight.w800),
                ),
              )),
          ],
        ),
        const SizedBox(height: 8),
        settle(3, Text(
          "type or paste any mix of them below, one per line — tanè sorts out what's what and matches each to the right shelf.".tr,
          style: SeenlyText.mono(size: 10, color: mutedColor),
        )),
        const SizedBox(height: 18),
        settle(4, Text('these titles are'.tr, style: SeenlyText.metaLabel.copyWith(color: dark ? Colors.white.withOpacity(0.7) : null))),
        const SizedBox(height: 8),
        settle(4, Row(
          children: [
            Expanded(
              child: PillChip(
                label: 'already watched'.tr,
                fullWidth: true,
                active: widget.defaultStatus == 'watched',
                onTap: () => widget.onStatusChanged('watched'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PillChip(
                label: 'plan to watch'.tr,
                fullWidth: true,
                active: widget.defaultStatus == 'watch_later',
                onTap: () => widget.onStatusChanged('watch_later'),
              ),
            ),
          ],
        )),
        const SizedBox(height: 22),
        settle(5, Text('import from'.tr, style: SeenlyText.metaLabel.copyWith(color: dark ? Colors.white.withOpacity(0.7) : null))),
        const SizedBox(height: 10),
        settle(5, _SourcePicker(
          selectedId: _sourceId,
          dark: dark,
          onSelected: (id) => setState(() => _sourceId = _sourceId == id ? null : id),
        )),
        const SizedBox(height: 14),
        // The hint under the cards follows the pick — and the page eases
        // to its new height rather than jumping.
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SoftSwap(
          alignment: Alignment.topLeft,
          rise: 0.08,
          child: source == null
              ? Text(
                  'no account to match? no problem — the box below is exactly what "or just type it in" above is talking about.'.tr,
                  key: const ValueKey('plain'),
                  style: SeenlyText.mono(size: 10, color: faintColor),
                )
              : Container(
                  key: ValueKey(source.id),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dark ? Colors.white.withOpacity(0.07) : SeenlyPalette.cork.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(source.icon, size: 16, color: SeenlyPalette.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${'from'.tr} ${source.label.toLowerCase()}: ${source.instructions.tr}',
                          style: SeenlyText.mono(size: 10, color: mutedColor),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
        ),
        const SizedBox(height: 14),
        // The box glows softly while you're in it.
        settle(6, Focus(canRequestFocus: false, skipTraversal: true, child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: dark ? Colors.white.withOpacity(0.08) : SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused ? SeenlyPalette.accent.withOpacity(0.55) : Colors.transparent,
              width: 1.2,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: SeenlyPalette.accent.withOpacity(0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: TextField(
            controller: widget.controller,
            maxLines: 10,
            minLines: 6,
            style: SeenlyText.mono(size: 12, color: textColor),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(14),
              border: InputBorder.none,
              hintText: source?.hint.tr ?? _plainListHint.tr,
              hintStyle: SeenlyText.mono(size: 12, color: faintColor),
            ),
          ),
        );
        }))),
        SoftSwap(
          rise: 0.3,
          child: widget.error == null
              ? const SizedBox(key: ValueKey<String>('no-error'), width: double.infinity)
              : Padding(
                  key: ValueKey<String>(widget.error!),
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(widget.error!, style: SeenlyText.mono(size: 10, color: SeenlyPalette.coral)),
                ),
        ),
        const SizedBox(height: 8),
        // A running count of what's been typed or pasted, and the button
        // wakes up (from a dimmed, waiting look) as soon as there's
        // something to look up.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final count = _splitLines(value.text).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: SoftSwap(
                    pop: true,
                    alignment: Alignment.centerRight,
                    child: count == 0
                        ? const SizedBox(key: ValueKey<int>(0), height: 14)
                        : Text(
                            nCount('nTitles', count),
                            key: ValueKey<int>(count),
                            style: SeenlyText.mono(size: 10, color: faintColor),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                settle(
                  7,
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    opacity: count == 0 ? 0.5 : 1.0,
                    child: PrimaryButton(label: 'find matches'.tr, onTap: widget.onSubmit),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Source cards grouped under a small category label. Each group is one
/// row that stretches edge to edge — every card in it gets an equal share
/// of the width rather than sizing to its own label.
class _SourcePicker extends StatelessWidget {
  final String? selectedId;
  final bool dark;
  final ValueChanged<String> onSelected;
  const _SourcePicker({required this.selectedId, required this.dark, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in _importGroups) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              group.label.tr,
              style: SeenlyText.mono(size: 9, color: dark ? Colors.white.withOpacity(0.42) : SeenlyPalette.placeholder),
            ),
          ),
          Row(
            children: [
              for (final source in group.sources) ...[
                if (source != group.sources.first) const SizedBox(width: 8),
                Expanded(
                  child: _SourceCard(
                    source: source,
                    selected: selectedId == source.id,
                    dark: dark,
                    onTap: () => onSelected(source.id),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  final _ImportSource source;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  const _SourceCard({required this.source, required this.selected, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Picking a card: it dips under the finger, fades to the accent colour
    // and lifts with a soft glow.
    return PressScale(
      onTap: onTap,
      scaleTo: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? SeenlyPalette.accent
              : (dark ? Colors.white.withOpacity(0.07) : SeenlyPalette.paper),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? SeenlyPalette.accent
                : (dark ? Colors.white.withOpacity(0.18) : SeenlyPalette.dashedBorder),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: SeenlyPalette.accent.withOpacity(0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // the service's real mark, fetched by domain; falls back to a
            // generic category icon if it can't be loaded (offline, or no
            // logo on file for that domain) — and fades in over that icon
            // once it has
            Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              padding: const EdgeInsets.all(3),
              child: ClipOval(
                child: FadeInNetworkImage(
                  url: source.logoUrl,
                  fit: BoxFit.contain,
                  placeholder: Center(
                    child: Icon(source.icon, size: 11, color: SeenlyPalette.inkMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 240),
                style: SeenlyText.mono(
                  size: 11,
                  color: selected
                      ? SeenlyPalette.accentOnAccent
                      : (dark ? SeenlyPalette.paperOnDark : SeenlyPalette.ink),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: Text(source.label.toLowerCase()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The plain version of a waiting screen — a spinner and one line. Kept as
/// the stand-in for [_MatchingStep] and [_AddingStep] when the system asks
/// for reduced motion (or there's nothing to show them with).
class _LoadingStep extends StatelessWidget {
  final String message;
  final bool dark;
  const _LoadingStep({required this.message, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
          const SizedBox(height: 14),
          Text(
            message,
            style: SeenlyText.serif(
              italic: true,
              size: 13,
              color: dark ? Colors.white.withOpacity(0.62) : SeenlyPalette.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// While the list is being looked up: the person's *own* lines, played back
/// as a column of slips that scroll past — the one being read is lit and
/// searching, the ones already read get ticked and drift up and away, the
/// next ones wait below, faint. It never claims to know how far along the
/// server is (it doesn't), so there's no percentage and no "42 of 600" —
/// just the true count of what was pasted, and a line of words that moves
/// on through the steps, then settles into "big lists take a moment" for as
/// long as it takes.
class _MatchingStep extends StatefulWidget {
  final List<String> lines;
  final String message;
  final bool dark;

  const _MatchingStep({required this.lines, required this.message, required this.dark});

  @override
  State<_MatchingStep> createState() => _MatchingStepState();
}

class _MatchingStepState extends State<_MatchingStep> {
  /// How fast the slips scroll.
  static const _tick = Duration(milliseconds: 640);

  /// How long each line of words stays.
  static const _phraseEvery = Duration(milliseconds: 2500);

  /// One slip's height including the gap under it.
  static const _slot = 46.0;

  late final List<String> _phrases = [
    'reading your list'.tr,
    widget.message,
    'matching each title'.tr,
    'sorting them onto the right shelves'.tr,
    'big lists take a moment'.tr, // ← the last two trade places for as long
    'still matching'.tr, //          as the wait lasts
  ];
  static const _tailStart = 4;

  Timer? _scrollTimer;
  Timer? _phraseTimer;
  int _cursor = 0;
  int _phrase = 0;

  @override
  void initState() {
    super.initState();
    _scrollTimer = Timer.periodic(_tick, (_) {
      if (mounted) setState(() => _cursor++);
    });
    _phraseTimer = Timer.periodic(_phraseEvery, (_) {
      if (!mounted) return;
      setState(() {
        _phrase = _phrase < _phrases.length - 1 ? _phrase + 1 : _tailStart;
      });
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _phraseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    if (MediaQuery.of(context).disableAnimations || lines.isEmpty) {
      return _LoadingStep(message: widget.message, dark: widget.dark);
    }
    final dark = widget.dark;
    final muted = dark ? Colors.white.withOpacity(0.62) : SeenlyPalette.inkMuted;
    final faint = dark ? Colors.white.withOpacity(0.42) : SeenlyPalette.placeholder;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(nCount('nTitles', lines.length), style: SeenlyText.mono(size: 10, color: faint)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: SizedBox(
                width: double.infinity,
                height: 5 * _slot - 8,
                child: ClipRect(
                  child: Stack(
                    children: [
                      // Seven slips are alive at once: the five you can see
                      // and one just off each end, so they slide in and out
                      // of view instead of popping in.
                      for (int o = -3; o <= 3; o++)
                        if (_cursor + o >= 0) _slip(lines, _cursor + o, o),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SoftSwap(
            alignment: Alignment.center,
            child: Text(
              _phrases[_phrase],
              key: ValueKey<int>(_phrase),
              textAlign: TextAlign.center,
              style: SeenlyText.serif(italic: true, size: 13, color: muted),
            ),
          ),
        ],
      ),
    );
  }

  /// [abs] is this slip's place in the endless scroll (its identity);
  /// [offset] is where it is relative to the one being read right now.
  Widget _slip(List<String> lines, int abs, int offset) {
    final dark = widget.dark;
    final text = lines[abs % lines.length];
    final active = offset == 0;
    final done = offset < 0;
    final opacity = switch (offset.abs()) { 0 => 1.0, 1 => 0.62, 2 => 0.28, _ => 0.0 };
    const glide = Duration(milliseconds: 460);

    return AnimatedPositioned(
      key: ValueKey<int>(abs),
      duration: glide,
      curve: Curves.easeOutCubic,
      top: (offset + 2) * _slot,
      left: 0,
      right: 0,
      height: _slot - 8,
      child: AnimatedOpacity(
        duration: glide,
        opacity: opacity,
        child: AnimatedScale(
          duration: glide,
          curve: Curves.easeOutCubic,
          scale: active ? 1.0 : 0.95,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: dark
                  ? Colors.white.withOpacity(active ? 0.12 : 0.07)
                  : SeenlyPalette.paper,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? SeenlyPalette.accent
                    : (dark ? Colors.white.withOpacity(0.18) : SeenlyPalette.dashedBorder),
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: SeenlyPalette.accent.withOpacity(0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.mono(
                      size: 11,
                      color: dark ? SeenlyPalette.paperOnDark : SeenlyPalette.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Waiting: nothing. Being read: a magnifier. Read: a tick.
                SoftSwap(
                  pop: true,
                  alignment: Alignment.center,
                  duration: const Duration(milliseconds: 240),
                  child: done
                      ? Icon(Icons.check_circle, key: const ValueKey<String>('done'), size: 16, color: SeenlyPalette.accent)
                      : active
                          ? Icon(Icons.search_rounded, key: const ValueKey<String>('active'), size: 16, color: SeenlyPalette.accent)
                          : const SizedBox(key: ValueKey<String>('waiting'), width: 16, height: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// While the matched titles are being saved: their posters fall, one after
/// another, into a diary at the bottom, which gives a little gulp each time
/// one lands. Decoration around a true count ("N titles") — the server
/// reports no progress, so nothing here pretends to be one.
class _AddingStep extends StatefulWidget {
  final List<ImportRow> rows;
  final String message;
  final bool dark;

  const _AddingStep({required this.rows, required this.message, required this.dark});

  @override
  State<_AddingStep> createState() => _AddingStepState();
}

class _AddingStepState extends State<_AddingStep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  static const _stageW = 230.0;
  static const _stageH = 200.0;
  static const _posterW = 36.0;
  static const _posterH = 54.0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (MediaQuery.of(context).disableAnimations || rows.isEmpty) {
      return _LoadingStep(message: widget.message, dark: widget.dark);
    }
    final dark = widget.dark;
    final faint = dark ? Colors.white.withOpacity(0.42) : SeenlyPalette.placeholder;
    final muted = dark ? Colors.white.withOpacity(0.62) : SeenlyPalette.inkMuted;
    // Six posters are plenty to fall: they repeat as long as it takes.
    final shown = rows.take(6).toList();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(nCount('nTitles', rows.length), style: SeenlyText.mono(size: 10, color: faint)),
          const SizedBox(height: 10),
          SizedBox(
            width: _stageW,
            height: _stageH,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => _stage(shown),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.message,
            style: SeenlyText.serif(italic: true, size: 13, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _stage(List<ImportRow> shown) {
    final k = shown.length;
    var gulp = 0.0;
    final falling = <Widget>[];
    for (int i = 0; i < k; i++) {
      final p = (_c.value + i / k) % 1.0; // this poster's own lap, 0..1
      final eased = Curves.easeIn.transform(p);
      // A little gulp from the diary as the poster reaches it.
      if (p > 0.84) gulp = math.max(gulp, math.sin((p - 0.84) / 0.16 * math.pi));
      final chosen = shown[i].chosen!;
      final spread = (i - (k - 1) / 2) * 30.0;
      final x = _stageW / 2 - _posterW / 2 + spread * (1 - 0.8 * eased);
      final y = -_posterH + (_stageH - 74 + _posterH) * eased;
      final scale = 1 - 0.62 * eased;
      final fade = p < 0.9 ? 1.0 : 1 - (p - 0.9) / 0.1;
      falling.add(
        Positioned(
          left: x,
          top: y,
          child: Opacity(
            opacity: fade.clamp(0.0, 1.0).toDouble(),
            child: Transform.rotate(
              angle: (i.isEven ? 1 : -1) * 0.18 * (1 - eased),
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: _posterW,
                  height: _posterH,
                  child: PosterTile(
                    title: chosen.title.display,
                    posterUrl: chosen.posterUrl,
                    fallbackColor: SeenlyPalette.mediaColor(chosen.mediaType),
                    showLabel: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        ...falling,
        // The diary they fall into — painted after them, so they slip
        // behind its edge.
        Positioned(
          left: 0,
          right: 0,
          bottom: 4,
          child: Center(
            child: Transform.scale(
              scale: 1 + 0.12 * gulp,
              child: Container(
                width: 70,
                height: 56,
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent.withOpacity(0.16 + 0.10 * gulp),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SeenlyPalette.accent.withOpacity(0.5)),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.menu_book_rounded, size: 30, color: SeenlyPalette.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  final ImportPreviewResult preview;
  final int selectedCount;
  final String? error;
  final bool dark;
  final VoidCallback onChanged;
  final VoidCallback onBack;
  final VoidCallback onImport;

  const _ReviewStep({
    required this.preview,
    required this.selectedCount,
    required this.error,
    required this.dark,
    required this.onChanged,
    required this.onBack,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final matchedCount = preview.rows.where((r) => r.matched != null).length;
    final mutedColor = dark ? Colors.white.withOpacity(0.62) : SeenlyPalette.inkMuted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${'matched'.tr} $matchedCount ${'of'.tr} ${preview.rows.length} ${'— review below, '.tr}'
                      '${'then import what looks right'.tr}',
                      style: SeenlyText.serif(italic: true, size: 12, color: mutedColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // How much of the list found a home, as a line that fills.
              _MatchMeter(matched: matchedCount, total: preview.rows.length, dark: dark),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: preview.rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            // The first screenful settles in one row after another; rows
            // scrolled into view later just come in without a wait.
            itemBuilder: (context, i) => Entrance(
              key: ValueKey<String>('row$i${preview.rows[i].raw}'),
              delay: Duration(milliseconds: i < 10 ? 45 * i : 0),
              duration: const Duration(milliseconds: 420),
              riseBy: 12,
              child: _ImportRowCard(row: preview.rows[i], dark: dark, onChanged: onChanged),
            ),
          ),
        ),
        SoftSwap(
          rise: 0.3,
          child: error == null
              ? const SizedBox(key: ValueKey<String>('no-error'), width: double.infinity)
              : Padding(
                  key: ValueKey<String>(error!),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(error!, style: SeenlyText.mono(size: 10, color: SeenlyPalette.coral)),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          child: Row(
            children: [
              TextButton(
                onPressed: onBack,
                child: Text(
                  'back'.tr,
                  style: SeenlyText.mono(size: 11, color: dark ? Colors.white.withOpacity(0.42) : SeenlyPalette.placeholder),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                // Dims and wakes up as rows are ticked on and off.
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 240),
                  opacity: selectedCount == 0 ? 0.5 : 1.0,
                  child: PrimaryButton(
                    label: selectedCount == 0 ? 'nothing selected'.tr : '${'import'.tr} ${nCount('nTitles', selectedCount)}',
                    onTap: selectedCount == 0 ? null : onImport,
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

/// A thin line that fills, once, to the share of the list that was matched.
class _MatchMeter extends StatelessWidget {
  final int matched;
  final int total;
  final bool dark;

  const _MatchMeter({required this.matched, required this.total, required this.dark});

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : matched / total;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: dark ? Colors.white.withOpacity(0.12) : SeenlyPalette.border),
            ),
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: ratio),
                duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: ColoredBox(color: SeenlyPalette.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportRowCard extends StatelessWidget {
  final ImportRow row;
  final bool dark;
  final VoidCallback onChanged;
  const _ImportRowCard({required this.row, required this.dark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final chosen = row.chosen;
    final faintColor = dark ? Colors.white.withOpacity(0.42) : SeenlyPalette.placeholder;
    if (chosen == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: dark ? Colors.white.withOpacity(0.06) : SeenlyPalette.paper.withOpacity(0.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.help_outline, size: 16, color: faintColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.raw,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(size: 12, color: dark ? SeenlyPalette.paperOnDark : SeenlyPalette.ink)),
                  Text('no match — will be skipped'.tr, style: SeenlyText.mono(size: 9, color: faintColor)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Ticking a row on or off: its outline draws in / fades out, the round
    // checkbox fills and the tick pops — instead of everything flipping at
    // once.
    const fade = Duration(milliseconds: 220);
    return AnimatedContainer(
      duration: fade,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(0.08) : SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: row.selected ? SeenlyPalette.accent : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressScale(
            scaleTo: 0.86,
            onTap: () {
              row.selected = !row.selected;
              onChanged();
            },
            child: AnimatedContainer(
              duration: fade,
              curve: Curves.easeOutCubic,
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: row.selected ? SeenlyPalette.accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: row.selected ? SeenlyPalette.accent : (dark ? Colors.white.withOpacity(0.3) : SeenlyPalette.dashedBorder),
                  width: 1.4,
                ),
              ),
              child: SoftSwap(
                pop: true,
                alignment: Alignment.center,
                duration: const Duration(milliseconds: 240),
                child: row.selected
                    ? Icon(Icons.check, key: const ValueKey<bool>(true), size: 14, color: SeenlyPalette.accentOnAccent)
                    : const SizedBox(key: ValueKey<bool>(false), width: 14, height: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            height: 54,
            child: PosterTile(
              title: chosen.title.display,
              posterUrl: chosen.posterUrl,
              fallbackColor: SeenlyPalette.mediaColor(chosen.mediaType),
              showLabel: false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chosen.title.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.cardTitle.copyWith(color: dark ? SeenlyPalette.paperOnDark : null)),
                const SizedBox(height: 2),
                Text('${mediaTypeLabel(chosen.mediaType)} · ${chosen.year ?? '—'}',
                    style: SeenlyText.metaLabel.copyWith(color: faintColor)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _StatusPill(
                      label: 'watched'.tr,
                      active: row.status == 'watched',
                      dark: dark,
                      onTap: () {
                        row.status = 'watched';
                        onChanged();
                      },
                    ),
                    const SizedBox(width: 6),
                    _StatusPill(
                      label: 'plan to watch'.tr,
                      active: row.status == 'watch_later',
                      dark: dark,
                      onTap: () {
                        row.status = 'watch_later';
                        onChanged();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool active;
  final bool dark;
  final VoidCallback onTap;
  const _StatusPill({required this.label, required this.active, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final faintColor = dark ? Colors.white.withOpacity(0.5) : SeenlyPalette.placeholder;
    const fade = Duration(milliseconds: 220);
    return PressScale(
      onTap: onTap,
      scaleTo: 0.92,
      child: AnimatedContainer(
        duration: fade,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? SeenlyPalette.accent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? SeenlyPalette.accent : (dark ? Colors.white.withOpacity(0.3) : SeenlyPalette.dashedBorder),
            width: 1,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: fade,
          style: SeenlyText.mono(size: 9, color: active ? SeenlyPalette.accent : faintColor),
          child: Text(label),
        ),
      ),
    );
  }
}

/// The payoff. The theme's own badge (sprout / route / ticket / rocket)
/// pops in with a ring and a burst of sparkles, then the numbers count up
/// from zero — so the size of what was just brought over is something you
/// watch arrive, not a sentence to read.
class _DoneStep extends StatelessWidget {
  final ImportCommitResult result;
  final bool embedded;
  final VoidCallback? onDone;

  const _DoneStep({required this.result, required this.embedded, this.onDone});

  static IconData _doneIcon(LogTheme theme) => switch (theme) {
        LogTheme.garden => Icons.local_florist_outlined,
        LogTheme.coach => Icons.route_outlined,
        LogTheme.ticket => Icons.confirmation_number_outlined,
        LogTheme.shuttle => Icons.rocket_launch_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    final watched = result.watchedCount;
    final later = result.watchLaterCount;
    final muted = embedded ? Colors.white.withOpacity(0.62) : SeenlyPalette.inkMuted;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DoneBadge(icon: _doneIcon(theme)),
            const SizedBox(height: 10),
            Entrance(
              delay: const Duration(milliseconds: 260),
              riseBy: 10,
              child: Text(
                watched + later == 0 ? 'nothing was added'.tr : 'added'.tr,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 15, color: embedded ? SeenlyPalette.paperOnDark : SeenlyPalette.ink),
              ),
            ),
            if (watched + later > 0) ...[
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (watched > 0) _DoneStat(value: watched, label: 'watched'.tr, muted: muted, delayMs: 380),
                  if (watched > 0 && later > 0) const SizedBox(width: 36),
                  if (later > 0) _DoneStat(value: later, label: 'plan to watch'.tr, muted: muted, delayMs: 500),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Entrance(
              delay: const Duration(milliseconds: 720),
              riseBy: 10,
              child: PrimaryButton(
                label: (embedded ? 'continue' : 'done').tr,
                onTap: () {
                  if (embedded) {
                    onDone?.call();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                expand: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneStat extends StatelessWidget {
  final int value;
  final String label;
  final Color muted;
  final int delayMs;

  const _DoneStat({required this.value, required this.label, required this.muted, required this.delayMs});

  @override
  Widget build(BuildContext context) {
    return Entrance(
      delay: Duration(milliseconds: delayMs),
      riseBy: 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountUpNumber(
            value: value.toDouble(),
            decimals: 0,
            duration: const Duration(milliseconds: 1200),
            style: SeenlyText.serif(size: 36, weight: FontWeight.w600, color: SeenlyPalette.accent),
          ),
          const SizedBox(height: 2),
          Text(label, style: SeenlyText.mono(size: 10, color: muted)),
        ],
      ),
    );
  }
}

class _DoneBadge extends StatefulWidget {
  final IconData icon;
  const _DoneBadge({required this.icon});

  @override
  State<_DoneBadge> createState() => _DoneBadgeState();
}

class _DoneBadgeState extends State<_DoneBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: 180,
      height: 140,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final pop = reduceMotion ? 1.0 : Curves.easeOutBack.transform((t / 0.4).clamp(0.0, 1.0).toDouble());
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (!reduceMotion)
                CustomPaint(size: const Size(180, 140), painter: _DoneBurstPainter(t: t)),
              Transform.scale(
                scale: pop,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.accent.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(widget.icon, size: 34, color: SeenlyPalette.accent),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One ring spreading out from the badge and ten sparkles flying off it,
/// once.
class _DoneBurstPainter extends CustomPainter {
  final double t; // 0..1

  const _DoneBurstPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);

    if (t > 0.18 && t < 0.85) {
      final p = Curves.easeOutCubic.transform(((t - 0.18) / 0.67).clamp(0.0, 1.0).toDouble());
      canvas.drawCircle(
        centre,
        40 + 46 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * (1 - p) + 0.4
          ..color = SeenlyPalette.accent.withOpacity(0.4 * (1 - p)),
      );
    }

    for (int i = 0; i < 10; i++) {
      final delay = 0.16 + ((i * 7) % 5) * 0.03;
      final local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0).toDouble();
      if (local <= 0) continue;
      final angle = i / 10 * 2 * math.pi + 0.3;
      final travel = 44 + Curves.easeOutCubic.transform(local) * (34 + 14 * (i % 3));
      final life = math.sin(math.pi * local);
      final color = i.isEven ? SeenlyPalette.accent : SeenlyPalette.mustard;
      paintSparkle(
        canvas,
        centre + Offset(math.cos(angle) * travel, math.sin(angle) * travel * 0.8),
        (3.6 + (i % 3) * 1.8) * (0.4 + 0.6 * life),
        Paint()..color = color.withOpacity(0.9 * life),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DoneBurstPainter old) => old.t != t;
}
