import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/import_row.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/poster_tile.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../services/app_translations.dart';

enum _Phase { input, loading, review, importing, done }

/// Paste a public YouTube/Twitch link — a single video, a playlist, a
/// channel's uploads, or a Twitch channel's past broadcasts — and bring
/// it into "your sources" (see sources_screen.dart). Same preview ->
/// review -> commit shape as Settings > Import (screens/import/
/// import_screen.dart), just resolved by URL instead of catalog search;
/// see backend/app/routers/sources.py for why this is its own screen
/// rather than a third mode inside that one.
class AddSourceScreen extends StatefulWidget {
  const AddSourceScreen({super.key});

  @override
  State<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends State<AddSourceScreen> {
  final _controller = TextEditingController();
  _Phase _phase = _Phase.input;
  String _defaultStatus = 'watch_later'; // "watched" | "watching" | "watch_later"
  ImportPreviewResult? _preview;
  ImportCommitResult? _committed;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final result = await context
          .read<AppState>()
          .sources
          .preview(url, defaultStatus: _defaultStatus);
      if (!mounted) return;
      setState(() {
        _preview = result;
        _phase = _Phase.review;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.input;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final message = e.toString();
    if (message.contains('404')) {
      return "couldn't find anything there — check it's public and try again".tr;
    }
    if (message.contains('503')) {
      return "this server isn't set up for that platform yet".tr;
    }
    return "couldn't resolve that link just now — try again in a moment".tr;
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
                    onPressed: () => Navigator.of(context).pop(_committed != null),
                  ),
                  const SizedBox(width: 4),
                  Text('add a source'.tr, style: SeenlyText.screenTitle),
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
      case _Phase.input:
        return _InputStep(
          controller: _controller,
          defaultStatus: _defaultStatus,
          error: _error,
          onStatusChanged: (v) => setState(() => _defaultStatus = v),
          onSubmit: _resolve,
        );
      case _Phase.loading:
        return _LoadingStep(message: 'fetching what\'s at that link…'.tr);
      case _Phase.review:
        return _ReviewStep(
          preview: _preview!,
          selectedCount: _selectedCount,
          error: _error,
          onChanged: () => setState(() {}),
          onBack: () => setState(() => _phase = _Phase.input),
          onImport: _commit,
        );
      case _Phase.importing:
        return _LoadingStep(message: 'adding these to your sources…'.tr);
      case _Phase.done:
        return _DoneStep(
          result: _committed!,
          onDone: () => Navigator.of(context).pop(true),
        );
    }
  }
}

class _InputStep extends StatelessWidget {
  final TextEditingController controller;
  final String defaultStatus;
  final String? error;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onSubmit;

  const _InputStep({
    required this.controller,
    required this.defaultStatus,
    required this.error,
    required this.onStatusChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
      children: [
        Text(
          "paste a public YouTube or Twitch link — a single video, a whole playlist, a channel's uploads, or a Twitch channel's past broadcasts — and teamira will pull in what's there.".tr,
          style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
        ),
        const SizedBox(height: 6),
        Text(
          "private lists like YouTube's Watch Later or Liked videos can't be reached this way — only things the link itself can actually see.".tr,
          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
        ),
        const SizedBox(height: 18),
        Text('these are'.tr, style: SeenlyText.metaLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillChip(
              label: 'plan to watch'.tr,
              active: defaultStatus == 'watch_later',
              onTap: () => onStatusChanged('watch_later'),
            ),
            PillChip(
              label: 'watching now'.tr,
              active: defaultStatus == 'watching',
              onTap: () => onStatusChanged('watching'),
            ),
            PillChip(
              label: 'already watched'.tr,
              active: defaultStatus == 'watched',
              onTap: () => onStatusChanged('watched'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            maxLines: 3,
            minLines: 1,
            style: SeenlyText.mono(size: 12, color: SeenlyPalette.ink),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(14),
              border: InputBorder.none,
              hintText: 'https://youtube.com/playlist?list=…\nor https://twitch.tv/…'.tr,
              hintStyle: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: SeenlyText.mono(size: 10, color: SeenlyPalette.coral)),
        ],
        const SizedBox(height: 20),
        PrimaryButton(label: 'fetch link'.tr, onTap: onSubmit),
      ],
    );
  }
}

class _LoadingStep extends StatelessWidget {
  final String message;
  const _LoadingStep({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
          const SizedBox(height: 14),
          Text(message, style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted)),
        ],
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  final ImportPreviewResult preview;
  final int selectedCount;
  final String? error;
  final VoidCallback onChanged;
  final VoidCallback onBack;
  final VoidCallback onImport;

  const _ReviewStep({
    required this.preview,
    required this.selectedCount,
    required this.error,
    required this.onChanged,
    required this.onBack,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${preview.sourceDetected} ${'— review below, then bring in what looks right'.tr}',
                  style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
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
            itemBuilder: (context, i) => _SourceRowCard(row: preview.rows[i], onChanged: onChanged),
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
                child: Text('back'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  label: selectedCount == 0
                      ? 'nothing selected'.tr
                      : '${'add'.tr} ${ruCount(selectedCount, one: 'тайтл', few: 'тайтла', many: 'тайтлов', englishOne: 'item', englishOther: 'items')}',
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

class _SourceRowCard extends StatelessWidget {
  final ImportRow row;
  final VoidCallback onChanged;
  const _SourceRowCard({required this.row, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final chosen = row.chosen;
    if (chosen == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper.withOpacity(0.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(row.raw, maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 12)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
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
                    color: row.selected ? SeenlyPalette.accent : SeenlyPalette.dashedBorder, width: 1.4),
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
              fallbackColor: SeenlyPalette.mediaColor('video'),
              showLabel: false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chosen.title.display,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: SeenlyText.cardTitle),
                if (chosen.runtimeMinutes != null) ...[
                  const SizedBox(height: 2),
                  Text('${chosen.runtimeMinutes} ${'min'.tr}', style: SeenlyText.metaLabel),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _StatusPill(
                      label: 'plan to watch'.tr,
                      active: row.status == 'watch_later',
                      onTap: () {
                        row.status = 'watch_later';
                        onChanged();
                      },
                    ),
                    _StatusPill(
                      label: 'watching'.tr,
                      active: row.status == 'watching',
                      onTap: () {
                        row.status = 'watching';
                        onChanged();
                      },
                    ),
                    _StatusPill(
                      label: 'watched'.tr,
                      active: row.status == 'watched',
                      onTap: () {
                        row.status = 'watched';
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
  final VoidCallback onTap;
  const _StatusPill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? SeenlyPalette.accent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? SeenlyPalette.accent : SeenlyPalette.dashedBorder, width: 1),
        ),
        child: Text(
          label,
          style: SeenlyText.mono(size: 9, color: active ? SeenlyPalette.accent : SeenlyPalette.placeholder),
        ),
      ),
    );
  }
}

class _DoneStep extends StatelessWidget {
  final ImportCommitResult result;
  final VoidCallback onDone;

  const _DoneStep({required this.result, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (result.watchedCount > 0) '${result.watchedCount} ${'watched'.tr}',
      if (result.watchLaterCount > 0) '${result.watchLaterCount} ${'to your list'.tr}',
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_display_outlined, size: 30, color: SeenlyPalette.accent),
            const SizedBox(height: 14),
            Text(
              parts.isEmpty
                  ? 'nothing was added'.tr
                  : '${'added'.tr} ' + parts.join(' ${'and'.tr} '),
              textAlign: TextAlign.center,
              style: SeenlyText.serif(italic: true, size: 15),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'done'.tr, onTap: onDone, expand: false),
          ],
        ),
      ),
    );
  }
}
