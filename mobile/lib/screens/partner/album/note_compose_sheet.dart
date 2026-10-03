import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/media_item.dart';
import '../../../models/pair_album.dart';
import '../../../services/api_client.dart';
import '../../../services/error_text.dart';
import '../../../services/pair_album_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/wow_motion.dart';
import 'album_paywall.dart';
import 'album_strings.dart';
import 'album_widgets.dart';

/// What the compose sheet hands back: the page as the server now has it, or
/// [deleted] when the person took their note back.
class NoteComposeResult {
  final AlbumPage? page;
  final bool deleted;
  const NoteComposeResult.saved(AlbumPage this.page) : deleted = false;
  const NoteComposeResult.deleted()
      : page = null,
        deleted = true;
}

/// Opens the sheet for writing (or rewriting) *my* note on [item] — the
/// note the partner will read once the evening is marked watched.
///
/// Notes are written before the evening, so this is called from the plan
/// sheet and from the planned card, not after watching.
///
/// A free circle can start a few notes (see [AlbumStatus.canWriteNote]);
/// once they're spent it gets the album paywall instead of the sheet.
/// Rewriting a note I already left is always open — it costs no slot. A
/// null [status] (not loaded yet, or the fetch failed) opens the sheet and
/// lets the server decide: a 402 from it lands on the same paywall.
Future<NoteComposeResult?> showNoteComposeSheet(
  BuildContext context, {
  required MediaItem item,
  required String partnerName,
  required AlbumStatus? status,
  AlbumPage? existing,
}) async {
  final rewriting = existing?.mine != null;
  if (!rewriting && status != null && !status.canWriteNote) {
    await showAlbumPaywall(
      context,
      kind: AlbumPaywallKind.notes,
      source: 'pair_album_note_limit',
    );
    return null;
  }
  return showAlbumSheet<NoteComposeResult>(
    context,
    builder: (_) => _NoteComposer(
      item: item,
      partnerName: partnerName,
      existing: existing,
      status: status,
    ),
  );
}

class _NoteComposer extends StatefulWidget {
  final MediaItem item;
  final String partnerName;
  final AlbumPage? existing;
  final AlbumStatus? status;
  const _NoteComposer({
    required this.item,
    required this.partnerName,
    this.existing,
    this.status,
  });

  @override
  State<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<_NoteComposer> {
  late final PairAlbumService _service = PairAlbumService(ApiClient.instance);
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _mood;
  bool _saving = false;
  bool _sealed = false;
  String? _error;
  Timer? _draftTimer;
  NoteComposeResult? _result;

  AlbumNote? get _mine => widget.existing?.mine;
  bool get _editing => _mine != null;

  String get _draftKey => 'album_note_draft_${widget.item.source}_${widget.item.id}';

  @override
  void initState() {
    super.initState();
    final mine = _mine;
    if (mine != null) {
      _text.text = mine.body;
      _mood = mine.mood;
    } else {
      _loadDraft();
    }
  }

  /// A half-written note survives closing the sheet or the app — it's
  /// kept on the device under the title, and cleared the moment the note
  /// is sealed (or the person empties it).
  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_draftKey);
      if (!mounted || saved == null || saved.isEmpty || _text.text.isNotEmpty) return;
      setState(() => _text.text = saved);
    } catch (_) {
      // A draft is a convenience; never let it break the sheet.
    }
  }

  void _scheduleDraftSave() {
    if (_editing) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final value = _text.text;
        if (value.trim().isEmpty) {
          await prefs.remove(_draftKey);
        } else {
          await prefs.setString(_draftKey, value);
        }
      } catch (_) {}
    });
  }

  Future<void> _clearDraft() async {
    _draftTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSave {
    final n = _text.text.trim().length;
    return !_saving && n > 0 && n <= kAlbumNoteMaxChars;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final page = await _service.putNote(widget.item, _text.text.trim(), mood: _mood);
      await _clearDraft();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _result = NoteComposeResult.saved(page);
      setState(() {
        _saving = false;
        _sealed = true;
      });
      final wait = albumReduceMotion(context) ? 500 : 1500;
      Future.delayed(Duration(milliseconds: wait), () {
        if (mounted) Navigator.of(context).pop(_result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (PairAlbumService.isPaywall(e)) {
        await showAlbumPaywall(
          context,
          kind: AlbumPaywallKind.notes,
          source: 'pair_album_note_limit',
        );
        return;
      }
      setState(() => _error = describeError(e));
    }
  }

  /// What's left of the free allowance, said once and gently — only for a
  /// free circle starting a *new* note (a rewrite costs nothing, and a
  /// circle with a plan has no allowance to speak of).
  String? get _allowanceText {
    final s = widget.status;
    if (_editing || s == null || s.isPremium) return null;
    final left = s.notesLeft;
    final limit = s.notesLimit;
    if (left == null || limit == null || left <= 0) return null;
    if (left == 1) {
      return at(
        'это ваша последняя бесплатная записка. дальше — с подпиской на двоих',
        'this is your last free note. after that it\'s a plan for two',
      );
    }
    return at(
      'бесплатных записок осталось: $left из $limit',
      'free notes left: $left of $limit',
    );
  }

  Future<void> _takeBack() async {
    final mine = _mine;
    if (mine == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.deleteNote(mine.id);
      await _clearDraft();
      if (!mounted) return;
      Navigator.of(context).pop(const NoteComposeResult.deleted());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftSizeSwitch(
      child: _sealed ? _sealedView(context) : _formView(context),
    );
  }

  Widget _sealedView(BuildContext context) {
    final still = albumReduceMotion(context);
    return Padding(
      key: const ValueKey('sealed'),
      padding: const EdgeInsets.fromLTRB(22, 34, 22, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: still ? 0.0 : 1.0, end: 0.0),
            duration: still ? Duration.zero : const Duration(milliseconds: 1000),
            curve: Curves.easeInOutCubic,
            builder: (_, v, __) => EnvelopeView(
              progress: v,
              width: 240,
              letter: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: double.infinity,
                  child: NotePaper(
                    body: _text.text.trim(),
                    mood: _mood,
                    fontSize: 12,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Entrance(
            delay: const Duration(milliseconds: 500),
            riseBy: 10,
            child: Text(
              at('запечатано', 'sealed'),
              style: SeenlyText.serif(size: 20, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          Entrance(
            delay: const Duration(milliseconds: 650),
            riseBy: 8,
            child: Text(
              at(
                '${widget.partnerName} прочтёт её после вашего вечера',
                '${widget.partnerName} will read it after your evening',
              ),
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formView(BuildContext context) {
    final title = widget.item.title.display;
    final count = _text.text.trim().length;
    final over = count > kAlbumNoteMaxChars;
    return SingleChildScrollView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AlbumPoster(url: widget.item.posterUrl, width: 42, radius: 7),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editing
                          ? at('ваша записка', 'your note')
                          : at('записка для ${widget.partnerName}', 'a note for ${widget.partnerName}'),
                      style: SeenlyText.serif(size: 18, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: SeenlyPalette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    at(
                      'напишите сейчас, пока вечер ещё впереди. ${widget.partnerName} увидит только '
                          'запечатанный конверт — текст откроется, когда вы отметите фильм '
                          'просмотренным. у каждого из вас своя записка',
                      'write it now, while the evening is still ahead. ${widget.partnerName} '
                          'will only see a sealed envelope — the text opens once you mark the '
                          'film watched. you each get your own note',
                    ),
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                decoration: BoxDecoration(
                  color: Color.lerp(SeenlyPalette.paper, SeenlyPalette.mustard, 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: over ? SeenlyPalette.coral : SeenlyPalette.mustard.withOpacity(0.35),
                  ),
                ),
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) {
                    _scheduleDraftSave();
                    setState(() => _error = null);
                  },
                  style: SeenlyText.handwrittenNote(size: 19, color: SeenlyPalette.ink)
                      .copyWith(height: 1.4),
                  cursorColor: SeenlyPalette.accent,
                  decoration: InputDecoration.collapsed(
                    hintText: at(
                      'например: «купи попкорн, а я выберу плед»…',
                      'like: "grab popcorn, I\'ll pick the blanket"…',
                    ),
                    hintStyle: SeenlyText.handwrittenNote(size: 18, color: SeenlyPalette.inkFaint),
                  ),
                ),
              ),
              Positioned(
                top: -7,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.rotate(
                    angle: -0.04,
                    child: Container(
                      width: 54,
                      height: 15,
                      decoration: BoxDecoration(
                        color: SeenlyPalette.mustard.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '$count/$kAlbumNoteMaxChars',
                style: SeenlyText.mono(
                  size: 11,
                  color: over ? SeenlyPalette.coral : SeenlyPalette.inkFaint,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(at('настроение', 'mood'), style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted)),
          const SizedBox(height: 8),
          EmojiChoiceRow(
            options: kAlbumMoods,
            selected: _mood,
            onChanged: (v) => setState(() => _mood = v),
            size: 20,
          ),
          if (_allowanceText != null) ...[
            const SizedBox(height: 14),
            FreeAllowanceNote(text: _allowanceText!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: SeenlyText.mono(size: 12, color: SeenlyPalette.coral)),
          ],
          const SizedBox(height: 18),
          ClayButton(
            label: _editing ? at('переписать записку', 'save changes') : at('запечатать записку', 'seal the note'),
            icon: Icons.mail_outline_rounded,
            loading: _saving,
            onTap: _canSave ? _save : null,
          ),
          if (_editing) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: _saving ? null : _takeBack,
                child: Text(
                  at('забрать записку', 'take it back'),
                  style: SeenlyText.mono(size: 12.5, color: SeenlyPalette.inkMuted),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Animates the sheet's height when its content swaps between the form
/// and the sealed view, so the sheet glides instead of jumping.
class SoftSizeSwitch extends StatelessWidget {
  final Widget child;
  const SoftSizeSwitch({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: child,
      ),
    );
  }
}
