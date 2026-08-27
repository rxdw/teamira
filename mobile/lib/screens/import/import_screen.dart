import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/import_row.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/interest_picker.dart' show kInterests;
import '../../widgets/poster_tile.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
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
        _error = "couldn't match those just now — try again in a moment";
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
        _error = "couldn't save those just now — try again";
      });
    }
  }

  int get _selectedCount =>
      _preview?.rows.where((r) => r.selected && r.chosen != null).length ?? 0;

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
                      color: _dark ? SeenlyPalette.paper : null,
                    ),
                    maxLines: 2,
                  ),
                ),
                if (widget.embedded && _phase == _Phase.input) ...[
                  const SizedBox(width: 10),
                  PillChip(label: 'skip for now'.tr, dashed: true, onTap: widget.onDone),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
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
        return _LoadingStep(message: 'looking these up in the catalog…'.tr, dark: _dark);
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
        return _LoadingStep(message: 'adding these to your diary…'.tr, dark: _dark);
      case _Phase.done:
        return _DoneStep(result: _committed!, embedded: widget.embedded, onDone: widget.onDone);
    }
  }
}

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
    final textColor = dark ? SeenlyPalette.paper : SeenlyPalette.ink;
    final mutedColor = dark ? Colors.white.withOpacity(0.62) : SeenlyPalette.inkMuted;
    final faintColor = dark ? Colors.white.withOpacity(0.42) : SeenlyPalette.placeholder;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
      children: [
        Text(
          'already keeping track somewhere else? bring it over — paste a plain list of titles, or an export from any of the services below, and teamira will match each one against the right shelf on its own.'.tr,
          style: SeenlyText.serif(italic: true, size: 12, color: mutedColor),
        ),
        const SizedBox(height: 14),
        // The one thing people skimming this screen tend to miss: typing
        // titles in yourself is a first-class option here, not a
        // fallback for when you don't have an account to match — and it
        // isn't movies-only. Given its own heading (same weight as
        // "import from" below) and a row of the same categorical colors
        // the rest of the app already uses for media type, so it reads
        // as a real option at a glance rather than fine print.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.edit_note, size: 20, color: SeenlyPalette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('or just type it in'.tr,
                  style: SeenlyText.sectionTitle.copyWith(color: SeenlyPalette.accent)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final interest in kInterests)
              Container(
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
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "type or paste any mix of them below, one per line — teamira sorts out what's what and matches each to the right shelf.".tr,
          style: SeenlyText.mono(size: 10, color: mutedColor),
        ),
        const SizedBox(height: 18),
        Text('these titles are'.tr, style: SeenlyText.metaLabel.copyWith(color: dark ? Colors.white.withOpacity(0.7) : null)),
        const SizedBox(height: 8),
        Row(
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
        ),
        const SizedBox(height: 22),
        Text('import from'.tr, style: SeenlyText.metaLabel.copyWith(color: dark ? Colors.white.withOpacity(0.7) : null)),
        const SizedBox(height: 10),
        _SourcePicker(
          selectedId: _sourceId,
          dark: dark,
          onSelected: (id) => setState(() => _sourceId = _sourceId == id ? null : id),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
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
                          '${'from'.tr} ${source.label}: ${source.instructions.tr}',
                          style: SeenlyText.mono(size: 10, color: mutedColor),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: dark ? Colors.white.withOpacity(0.08) : SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(12),
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
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 12),
          Text(widget.error!, style: SeenlyText.mono(size: 10, color: SeenlyPalette.coral)),
        ],
        const SizedBox(height: 20),
        PrimaryButton(label: 'find matches'.tr, onTap: widget.onSubmit),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
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
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // the service's real mark, fetched by domain; falls back to a
            // generic category icon if it can't be loaded (offline, or no
            // logo on file for that domain)
            Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              padding: const EdgeInsets.all(3),
              child: ClipOval(
                child: Image.network(
                  source.logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Icon(source.icon, size: 11, color: SeenlyPalette.inkMuted),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                source.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(
                  size: 11,
                  color: selected
                      ? SeenlyPalette.accentOnAccent
                      : (dark ? SeenlyPalette.paper : SeenlyPalette.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
          child: Row(
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
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: preview.rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _ImportRowCard(row: preview.rows[i], dark: dark, onChanged: onChanged),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(error!, style: SeenlyText.mono(size: 10, color: SeenlyPalette.coral)),
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
                child: PrimaryButton(
                  label: selectedCount == 0 ? 'nothing selected'.tr : '${'import'.tr} ${ruCount(selectedCount, one: 'тайтл', few: 'тайтла', many: 'тайтлов', englishOne: 'title', englishOther: 'titles')}',
                  onTap: selectedCount == 0 ? null : onImport,
                ),
              ),
            ],
          ),
        ),
      ],
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
                      style: SeenlyText.serif(size: 12, color: dark ? SeenlyPalette.paper : SeenlyPalette.ink)),
                  Text('no match — will be skipped'.tr, style: SeenlyText.mono(size: 9, color: faintColor)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(0.08) : SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(10),
        border: row.selected ? Border.all(color: SeenlyPalette.accent, width: 1.2) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              row.selected = !row.selected;
              onChanged();
            },
            child: Container(
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
              child: row.selected
                  ? Icon(Icons.check, size: 14, color: SeenlyPalette.accentOnAccent)
                  : null,
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
                    style: SeenlyText.cardTitle.copyWith(color: dark ? SeenlyPalette.paper : null)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? SeenlyPalette.accent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? SeenlyPalette.accent : (dark ? Colors.white.withOpacity(0.3) : SeenlyPalette.dashedBorder),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: SeenlyText.mono(size: 9, color: active ? SeenlyPalette.accent : faintColor),
        ),
      ),
    );
  }
}

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
    final parts = <String>[
      if (result.watchedCount > 0) '${result.watchedCount} watched',
      if (result.watchLaterCount > 0) '${result.watchLaterCount} to plan to watch',
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_doneIcon(theme), size: 30, color: SeenlyPalette.accent),
            const SizedBox(height: 14),
            Text(
              parts.isEmpty ? 'nothing was added' : 'added ${parts.join(' and ')}',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(italic: true, size: 15, color: embedded ? SeenlyPalette.paper : SeenlyPalette.ink),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
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
          ],
        ),
      ),
    );
  }
}
