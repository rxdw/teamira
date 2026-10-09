import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/reading_progress.dart';
import '../screens/add_entry/watching_choice_screen.dart';
import '../services/app_translations.dart';
import '../services/progress_service.dart';
import '../state/app_state.dart';
import '../theme/clay_kit.dart';
import '../theme/notebook_paper.dart';
import '../theme/palette.dart';
import '../theme/seenly_skin.dart';
import '../theme/text_styles.dart';
import '../widgets/wow_motion.dart' show PressScale;

/// The book / manga title screen's bookmark: "volume 7 of 42", "page 212 of
/// 592". The reading counterpart of [SeasonTracker] — same place on the
/// screen, same card, same rule that it keeps quiet instead of showing a dead
/// state — but one bookmark per title instead of a checklist, because a book
/// has no per-page "seen" state worth keeping.
///
/// What it deliberately does NOT do: touch the title's shelf status or the
/// diary. Moving a bookmark is not logging an evening (the sincerity rules
/// hang off those). When the end is reached it only *offers* to log it.
///
/// Saving is optimistic and debounced: the number changes under the thumb at
/// once, and one PUT goes out half a second after the last tap (with the
/// whole state, so it is idempotent). Leaving the screen flushes whatever is
/// still waiting.
class ReadingTracker extends StatefulWidget {
  final MediaItem item;

  /// Called after the person logs the finished title from the banner, so the
  /// screen can refresh its own history.
  final VoidCallback? onLogged;
  const ReadingTracker({super.key, required this.item, this.onLogged});

  /// Only books and manga keep a bookmark.
  static bool appliesTo(MediaItem item) => item.mediaType == 'book' || item.mediaType == 'manga';

  @override
  State<ReadingTracker> createState() => _ReadingTrackerState();
}

class _ReadingTrackerState extends State<ReadingTracker> {
  static const _saveDelay = Duration(milliseconds: 500);
  static const _maxCounter = 99999;

  late final ProgressService _service;
  ReadingBookmark _bookmark = ReadingBookmark.empty;
  bool _loading = true;
  bool _dirty = false;
  Timer? _saveTimer;

  bool get _isManga => widget.item.mediaType == 'manga';

  int? get _totalVolumes => _positive(widget.item.volumes);
  int? get _totalChapters => _positive(widget.item.chapters);
  int? get _totalPages => _positive(widget.item.extras?.pages);

  static int? _positive(int? v) => (v != null && v > 0) ? v : null;

  @override
  void initState() {
    super.initState();
    _service = context.read<AppState>().progress;
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) _flush(); // best-effort: the person left mid-debounce
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await _service.reading(mediaId: widget.item.id, source: widget.item.source);
      if (!mounted) return;
      setState(() {
        _bookmark = b;
        _loading = false;
      });
    } catch (_) {
      // Degrade silently, like the season tracker: the card just starts empty.
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- saving ---------------------------------------------------------------

  void _set(ReadingBookmark next) {
    final wasFinished = _finished;
    setState(() => _bookmark = next);
    if (!wasFinished && _finished) HapticFeedback.mediumImpact();
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _flush);
  }

  Future<void> _flush() async {
    _dirty = false;
    _saveTimer?.cancel();
    final snapshot = _bookmark;
    try {
      await _service.setReading(
        mediaId: widget.item.id,
        source: widget.item.source,
        bookmark: snapshot,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't save progress just now".tr)));
    }
  }

  int _clamp(int v, int? total) => v.clamp(0, total ?? _maxCounter);

  void _setVolume(int v) => _set(_bookmark.copyWith(volume: _clamp(v, _totalVolumes), clearVolume: v <= 0));
  void _setChapter(int v) => _set(_bookmark.copyWith(chapter: _clamp(v, _totalChapters), clearChapter: v <= 0));
  void _setPage(int v) => _set(_bookmark.copyWith(page: _clamp(v, _totalPages), clearPage: v <= 0));

  void _startOver() {
    final previous = _bookmark;
    _set(ReadingBookmark.empty);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('progress cleared'.tr),
        action: SnackBarAction(label: 'undo'.tr, onPressed: () => _set(previous)),
      ));
  }

  // --- derived state ----------------------------------------------------------

  /// 0..1 for the bar, or null when there's nothing to measure against.
  double? get _fraction {
    if (_isManga) {
      if (_totalVolumes != null) return ((_bookmark.volume ?? 0) / _totalVolumes!).clamp(0.0, 1.0);
      if (_totalChapters != null) return ((_bookmark.chapter ?? 0) / _totalChapters!).clamp(0.0, 1.0);
      return null;
    }
    if (_totalPages != null) return ((_bookmark.page ?? 0) / _totalPages!).clamp(0.0, 1.0);
    return null;
  }

  bool get _finished {
    if (_isManga) {
      if (_totalVolumes != null) return (_bookmark.volume ?? 0) >= _totalVolumes!;
      if (_totalChapters != null) return (_bookmark.chapter ?? 0) >= _totalChapters!;
      return false; // an ongoing series has no end to reach
    }
    return _totalPages != null && (_bookmark.page ?? 0) >= _totalPages!;
  }

  /// "7 / 42 vols." for the heading — whichever counter drives the bar.
  String? get _summary {
    if (_isManga) {
      if (_totalVolumes != null) {
        return '${_bookmark.volume ?? 0} / $_totalVolumes ${nOnly('nVolumes', _totalVolumes!)}';
      }
      if (_totalChapters != null) {
        return '${_bookmark.chapter ?? 0} / $_totalChapters ${nOnly('nChapters', _totalChapters!)}';
      }
      return null;
    }
    if (_totalPages != null) {
      return '${_bookmark.page ?? 0} / $_totalPages ${nOnly('nPages', _totalPages!)}';
    }
    return null;
  }

  /// "≈ 3 h 20 min to go" — a book only, from the reading time we already
  /// estimate, scaled by the pages left. Null until it's meaningful.
  String? get _timeLeft {
    final minutes = widget.item.runtimeMinutes;
    final total = _totalPages;
    final page = _bookmark.page ?? 0;
    if (_isManga || minutes == null || total == null || page <= 0 || page >= total) return null;
    final left = (minutes * (total - page) / total).round();
    if (left < 5) return null;
    final h = left ~/ 60;
    final m = left % 60;
    final parts = [
      if (h > 0) '$h ${'h'.tr}',
      if (m > 0 && h < 10) '$m ${'min'.tr}',
    ];
    return '≈ ${parts.join(' ')} ${'to go'.tr}';
  }

  // --- actions ----------------------------------------------------------------

  Future<void> _editNumber({
    required String label,
    required int current,
    required int? total,
    required ValueChanged<int> onSave,
    bool quickAdds = false,
  }) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: SeenlyPalette.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _NumberSheet(
        label: label,
        initial: current,
        total: total,
        maxValue: total ?? _maxCounter,
        quickAdds: quickAdds,
      ),
    );
    if (value != null) onSave(value);
  }

  Future<void> _logFinished() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WatchingChoiceScreen(item: widget.item),
      ),
    );
    if (saved == true) widget.onLogged?.call();
  }

  // --- build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 4);
    }
    final fraction = _fraction;
    final summary = _summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('reading progress'.tr,
                style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accent)),
            const Spacer(),
            if (summary != null) Text(summary, style: SeenlyText.metaLabel),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isManga)
                Row(
                  children: [
                    Expanded(
                      child: _Counter(
                        label: 'volume'.tr,
                        value: _bookmark.volume ?? 0,
                        total: _totalVolumes,
                        onChanged: _setVolume,
                        onEdit: () => _editNumber(
                          label: 'volume you are on'.tr,
                          current: _bookmark.volume ?? 0,
                          total: _totalVolumes,
                          onSave: _setVolume,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Counter(
                        label: 'chapter'.tr,
                        value: _bookmark.chapter ?? 0,
                        total: _totalChapters,
                        onChanged: _setChapter,
                        onEdit: () => _editNumber(
                          label: 'chapter you are on'.tr,
                          current: _bookmark.chapter ?? 0,
                          total: _totalChapters,
                          onSave: _setChapter,
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                _Counter(
                  label: 'page'.tr,
                  value: _bookmark.page ?? 0,
                  total: _totalPages,
                  onChanged: _setPage,
                  onEdit: () => _editNumber(
                    label: 'page you are on'.tr,
                    current: _bookmark.page ?? 0,
                    total: _totalPages,
                    onSave: _setPage,
                    quickAdds: true,
                  ),
                  wide: true,
                ),
                const SizedBox(height: 10),
                // Reading usually moves in handfuls of pages, not one at a time.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final n in const [10, 25, 50]) ...[
                      _QuickAdd(label: '+$n', onTap: () => _setPage((_bookmark.page ?? 0) + n)),
                      if (n != 50) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ],
              if (fraction != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: RuledProgressBar(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor: SeenlyPalette.background,
                    valueColor: _finished ? SeenlyPalette.sage : SeenlyPalette.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('${(fraction * 100).round()}%',
                        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted, weight: FontWeight.w700)),
                    const Spacer(),
                    if (_timeLeft != null)
                      Text(_timeLeft!, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.placeholder)),
                  ],
                ),
              ],
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _finished ? _FinishedBanner(onLog: _logFinished) : const SizedBox(width: double.infinity),
              ),
              if (!_bookmark.isEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _startOver,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('start over'.tr,
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// The tracker's own card — same paper + soft shadow as the season pager.
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: child,
    );
  }
}

/// A counter well with − / + around a big number. The number itself is a
/// button: tap it to type an exact value.
class _Counter extends StatelessWidget {
  final String label;
  final int value;
  final int? total;
  final ValueChanged<int> onChanged;
  final VoidCallback onEdit;
  final bool wide;
  const _Counter({
    required this.label,
    required this.value,
    required this.total,
    required this.onChanged,
    required this.onEdit,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _RoundButton(icon: Icons.remove_rounded, enabled: value > 0, onTap: () => onChanged(value - 1)),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEdit,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$value', style: SeenlyText.serif(size: wide ? 34 : 28, weight: FontWeight.w600)),
                    Text(
                      total != null ? '${'of'.tr} $total' : 'tap to set'.tr,
                      style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.placeholder),
                    ),
                  ],
                ),
              ),
            ),
            _RoundButton(
              icon: Icons.add_rounded,
              enabled: total == null || value < total!,
              onTap: () => onChanged(value + 1),
              filled: true,
            ),
          ],
        ),
      ],
    );

    final padding = EdgeInsets.symmetric(horizontal: wide ? 18 : 8, vertical: 12);
    if (SeenlySkin.isClay) {
      // Pressed-in, like a well the number sits in.
      return ClaySurface(radius: 18, inset: true, elevation: 0.3, padding: padding, child: content);
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: Border.all(color: SeenlyPalette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool filled;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.enabled, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? SeenlyPalette.dashedBorder
        : (filled ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted);
    final bg = filled && enabled ? SeenlyPalette.accent : SeenlyPalette.paper;
    final glyph = Icon(icon, size: 20, color: fg);
    final button = SeenlySkin.isClay
        ? ClaySurface(
            circle: true,
            width: 38,
            height: 38,
            color: bg,
            elevation: enabled ? 0.7 : 0.1,
            child: Center(child: glyph),
          )
        : Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: filled && enabled ? SeenlyPalette.accent : null,
              shape: BoxShape.circle,
              border: Border.all(color: filled && enabled ? SeenlyPalette.accent : SeenlyPalette.border),
            ),
            child: Center(child: glyph),
          );
    return PressScale(onTap: enabled ? onTap : null, scaleTo: 0.88, child: button);
  }
}

class _QuickAdd extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickAdd({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(label, style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.accent, weight: FontWeight.w800)),
    );
    return PressScale(
      onTap: onTap,
      scaleTo: 0.93,
      child: SeenlySkin.isClay
          ? ClaySurface(
              radius: 16,
              elevation: 0.4,
              color: Color.alphaBlend(SeenlyPalette.accent.withOpacity(0.10), SeenlyPalette.paper),
              child: chip,
            )
          : Container(
              decoration: BoxDecoration(
                border: Border.all(color: SeenlyPalette.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: chip,
            ),
    );
  }
}

/// Shown once the end is reached: a quiet sage note and an offer — never an
/// automatic log.
class _FinishedBanner extends StatelessWidget {
  final VoidCallback onLog;
  const _FinishedBanner({required this.onLog});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: SeenlyPalette.sage.withOpacity(0.16),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 20, color: SeenlyPalette.sage),
            const SizedBox(width: 10),
            Expanded(
              child: Text('you reached the end'.tr,
                  style: SeenlyText.serif(italic: true, size: 13.5, color: SeenlyPalette.ink)),
            ),
            const SizedBox(width: 8),
            PressScale(
              onTap: onLog,
              scaleTo: 0.94,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('log it in your diary'.tr,
                    style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.accentOnAccent, weight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Type an exact number. Pops with the new value, or null if dismissed.
class _NumberSheet extends StatefulWidget {
  final String label;
  final int initial;
  final int? total;
  final int maxValue;
  final bool quickAdds;
  const _NumberSheet({
    required this.label,
    required this.initial,
    required this.total,
    required this.maxValue,
    required this.quickAdds,
  });

  @override
  State<_NumberSheet> createState() => _NumberSheetState();
}

class _NumberSheetState extends State<_NumberSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial > 0 ? '${widget.initial}' : '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim()) ?? 0;
    Navigator.of(context).pop(parsed.clamp(0, widget.maxValue));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.dashedBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(widget.label, style: SeenlyText.serif(italic: true, size: 16, color: SeenlyPalette.accent)),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: SeenlyText.serif(size: 30, weight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: SeenlyText.serif(size: 30, color: SeenlyPalette.dashedBorder),
                  suffixText: widget.total != null ? '${'of'.tr} ${widget.total}' : null,
                  suffixStyle: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: SeenlyPalette.dashedBorder)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: SeenlyPalette.accent, width: 2)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: PressScale(
                  onTap: _submit,
                  scaleTo: 0.97,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SeenlyPalette.accent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text('save'.tr,
                        style: SeenlyText.serif(size: 15, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
