import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/co_view_room.dart';
import '../../../../services/error_text.dart';
import '../../../../theme/clay_kit.dart';
import '../../../../theme/palette.dart';
import '../../../../theme/text_styles.dart';
import '../../../../widgets/user_avatar.dart';
import '../../../../widgets/wow_motion.dart';
import '../room_controller.dart';
import '../room_strings.dart';
import 'reading_locator.dart';
import 'reading_overlay.dart';
import 'reading_strings.dart';

bool _reduce(BuildContext c) => MediaQuery.maybeOf(c)?.disableAnimations ?? false;

/// A thin bar under the page: how far *you* are, a tiny face where each other
/// person is, and a soft tick wherever somebody left a note in the margin.
class ReadingProgressBar extends StatelessWidget {
  final RoomController room;

  /// My own place in the whole book, a permille.
  final ValueListenable<int> mine;
  const ReadingProgressBar({super.key, required this.room, required this.mine});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([room, mine]),
      builder: (context, _) {
        final s = room.state;
        final me = mine.value.clamp(0, 1000);
        final others = [for (final p in s.participants) if (!p.isYou && p.present && p.locator != null) p];
        // A tick for every note in the margin (sage) and highlight (accent).
        final ticks = [
          for (final m in s.marks)
            if (m.positionMs != null) (m.positionMs! ~/ 1000, m.isHighlight),
        ];
        return Column(
          children: [
            SizedBox(
              height: 26,
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: SeenlyPalette.border.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      AnimatedContainer(
                        duration: Duration(milliseconds: _reduce(context) ? 1 : 260),
                        curve: Curves.easeOutCubic,
                        height: 4,
                        width: w * me / 1000,
                        decoration: BoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(2)),
                      ),
                      for (final (n, light) in ticks)
                        Positioned(
                          left: (w * (n.clamp(0, 1000) / 1000)) - 1.5,
                          child: Container(
                            width: 3,
                            height: light ? 7 : 9,
                            decoration: BoxDecoration(
                              color: (light ? SeenlyPalette.accent : SeenlyPalette.sage).withOpacity(light ? 0.5 : 0.75),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      for (final p in others)
                        Positioned(
                          left: (w * (p.progress.clamp(0, 1000) / 1000)) - 10,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: SeenlyPalette.paper, width: 2),
                            ),
                            child: UserAvatar(
                              avatarUrl: p.avatarUrl,
                              avatarPreset: p.avatarPreset,
                              fallbackLetter: p.letter,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${percentOf(me)}%', style: SeenlyText.mono(size: 12)),
                Text('100%', style: SeenlyText.mono(size: 12)),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// "аня · глава 4 · 31%" — where each other person is, and a tap to go there.
class ReadingPeers extends StatelessWidget {
  final RoomController room;
  final bool comic;
  final void Function(ReadLocator at) onGo;
  const ReadingPeers({super.key, required this.room, required this.comic, required this.onGo});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final s = room.state;
        final kind = s.readKind;
        final peers = [for (final p in s.participants) if (!p.isYou && p.present && p.locator != null) p];
        if (kind == null || peers.isEmpty) return const SizedBox.shrink();
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in peers)
              Builder(builder: (context) {
                final at0 = ReadLocator.tryParse(kind, p.locator);
                if (at0 == null) return const SizedBox.shrink();
                return PressScale(
                  scaleTo: 0.97,
                  haptics: true,
                  onTap: () => onGo(at0),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.paper,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: SeenlyPalette.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      UserAvatar(
                        avatarUrl: p.avatarUrl,
                        avatarPreset: p.avatarPreset,
                        fallbackLetter: p.letter,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${p.name.toLowerCase()} · ${peerPlace(comic: comic, major: at0.major, progress: p.progress, units: s.readUnits)}',
                        style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkMuted),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.north_east_rounded, size: 13, color: SeenlyPalette.inkFaint),
                    ]),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

/// Shown while you haven't opened your own copy yet.
class OpenCopyCard extends StatelessWidget {
  final ReadKind kind;
  final String title;
  final bool busy;
  final String? error;
  final VoidCallback onPick;
  const OpenCopyCard({
    super.key,
    required this.kind,
    required this.title,
    required this.busy,
    required this.error,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final comic = kind == ReadKind.cbz;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 12, 26, 26),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Breathe(
            period: const Duration(milliseconds: 4200),
            minScale: 0.95,
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeenlyPalette.accent.withOpacity(0.12),
                border: Border.all(color: SeenlyPalette.accent.withOpacity(0.35)),
              ),
              child: Icon(comic ? Icons.collections_bookmark_rounded : Icons.menu_book_rounded,
                  size: 38, color: SeenlyPalette.accent),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            comic ? at('откройте свой том', 'open your volume') : at('откройте свою книгу', 'open your copy'),
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 20, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            at('«$title» — выберите тот же файл, что и у остальных. он остаётся на вашем телефоне: мы его никуда не отправляем и не храним, а в комнате видно только, на какой вы странице.',
                '“$title” — pick the same file the others have. it stays on your phone: we never upload or keep it, and the room only sees which page you’re on.'),
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.coral)),
          ],
          const SizedBox(height: 20),
          PressScale(
            haptics: true,
            onTap: busy ? null : onPick,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
              decoration: ClayBoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(22)),
              child: busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                    )
                  : Text(at('выбрать файл', 'choose the file'),
                      style: SeenlyText.serif(size: 16, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A small pill: an icon and a short line, optionally tinted.
class ReadingPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  const ReadingPill({super.key, required this.icon, required this.label, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? SeenlyPalette.inkMuted;
    return PressScale(
      scaleTo: 0.96,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withOpacity(0.38)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: c),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(size: 12.5, italic: true, color: c)),
          ),
        ]),
      ),
    );
  }
}

/// Everything you can leave at one place: a reaction, a note in the margin
/// (with the line it's about, if you want to attach it) — and, for text, a
/// highlight on the paragraph and a quote set aside for the pair album.
Future<void> showReadingPinSheet(
  BuildContext context, {
  required RoomController room,
  required ReadLocator at,
  required int progress,
  required String placeText,
  String? quote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PinSheet(room: room, at: at, progress: progress, placeText: placeText, quote: quote),
  );
}

class _PinSheet extends StatefulWidget {
  final RoomController room;
  final ReadLocator at;
  final int progress;
  final String placeText;
  final String? quote;
  const _PinSheet({
    required this.room,
    required this.at,
    required this.progress,
    required this.placeText,
    required this.quote,
  });

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final _text = TextEditingController();
  bool _withQuote = true;
  bool _sending = false;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _react(String key) async {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    try {
      await widget.room.reactAt(key, widget.at.wire, widget.progress);
    } catch (_) {}
  }

  bool get _iHighlighted => ReadingOverlay.of(widget.room.state).iHighlighted(widget.at);

  /// Only text has a paragraph to highlight, and only a couple has an album.
  bool get _canHighlight => widget.quote != null;
  bool get _canAlbum {
    final s = widget.room.state;
    return widget.quote != null && !s.meIsGuest && s.participants.where((p) => !p.isGuest).length == 2;
  }

  Future<void> _highlight() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    final turnOn = !_iHighlighted;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await widget.room.highlight(widget.at.wire, turnOn, widget.progress, quote: widget.quote);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _album() async {
    if (_busy || widget.quote == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await widget.room.albumQuote(widget.quote!);
      HapticFeedback.mediumImpact();
      final msg = !r.added
          ? at('эта цитата уже лежит в вашей записке', 'this quote is already in your note')
          : r.created
              ? at('отложили в альбом — вы увидите цитаты, когда дочитаете', 'set aside for the album — you’ll both see the quotes when you finish')
              : at('добавили в вашу записку для альбома', 'added to your album note');
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.room.margin(
        body,
        widget.at.wire,
        widget.progress,
        quote: (_withQuote && widget.quote != null) ? widget.quote : null,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast(describeError(e));
      if (mounted) setState(() => _sending = false);
    }
  }

  String _who(String? userId) {
    for (final p in widget.room.state.participants) {
      if (p.userId == userId) return p.isYou ? at('вы', 'you') : p.name.toLowerCase();
    }
    return at('кто-то', 'someone');
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, {bool on = false, Color? color}) {
    final c = color ?? SeenlyPalette.inkMuted;
    return PressScale(
      scaleTo: 0.96,
      onTap: _busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on ? c.withOpacity(0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? c.withOpacity(0.55) : SeenlyPalette.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Text(label, style: SeenlyText.serif(size: 13, italic: true, color: c)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final here = [
      for (final m in widget.room.state.marks)
        if (m.isMargin && m.locator == widget.at.wire) m,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(at('на полях', 'in the margin'), style: SeenlyText.serif(size: 18, weight: FontWeight.w600)),
              Text(widget.placeText, style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkFaint)),
              if (widget.quote != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: SeenlyPalette.accent.withOpacity(0.5), width: 3)),
                  ),
                  child: Text(widget.quote!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted)),
                ),
              ],
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final k in RoomKeys.reactions)
                    PressScale(
                      scaleTo: 0.88,
                      onTap: () => _react(k),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        child: Text(k, style: const TextStyle(fontSize: 27)),
                      ),
                    ),
                ]),
              ),
              if (_canHighlight || _canAlbum) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (_canHighlight)
                    _action(
                      Icons.brush_rounded,
                      _iHighlighted ? at('снять подсветку', 'remove highlight') : at('подсветить абзац', 'highlight the paragraph'),
                      _highlight,
                      on: _iHighlighted,
                      color: SeenlyPalette.accent,
                    ),
                  if (_canAlbum)
                    _action(Icons.photo_album_rounded, at('в наш альбом', 'to our album'), _album, color: SeenlyPalette.sage),
                ]),
              ],
              if (here.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final m in here)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.edit_note_rounded, size: 18, color: SeenlyPalette.sage),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                            text: '${_who(m.userId)}: ',
                            style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.inkFaint),
                          ),
                          TextSpan(text: m.body ?? '', style: SeenlyText.serif(size: 14.5)),
                        ])),
                      ),
                    ]),
                  ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
                decoration: clayWellDecoration(radius: 22),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      style: SeenlyText.serif(size: 15),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                        hintText: at('что вы об этом думаете?', 'what do you think?'),
                        hintStyle: SeenlyText.serif(size: 15, italic: true, color: SeenlyPalette.placeholder),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: Icon(Icons.arrow_upward_rounded, color: SeenlyPalette.accent),
                  ),
                ]),
              ),
              if (widget.quote != null)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _withQuote,
                  activeColor: SeenlyPalette.sage,
                  title: Text(at('приложить строчку', 'attach the line'),
                      style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted)),
                  onChanged: (v) => setState(() => _withQuote = v),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "как читаем?" — the three ways to be in a reading room. Resolves to the
/// mode picked (`own` | `together` | `aloud`), or null if it was dismissed.
Future<String?> showReadingModeSheet(
  BuildContext context, {
  required RoomState s,
  required bool canAloud,
}) {
  final meId = [for (final p in s.participants) if (p.isYou) p.userId].firstOrNull;
  String? readerName;
  if (s.isAloud && s.leadUserId != null && s.leadUserId != meId) {
    for (final p in s.participants) {
      if (p.userId == s.leadUserId) readerName = p.name.toLowerCase();
    }
    readerName ??= at('кого-то', 'someone');
  }
  final iAmReader = s.isAloud && s.leadUserId == meId;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 14),
        Text(at('как читаем?', 'how are we reading?'), style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
        const SizedBox(height: 12),
        _ModeRow(
          icon: Icons.link_off_rounded,
          title: at('каждый в своём темпе', 'each at your own pace'),
          sub: at('видно, где другие, — можно прийти к ним', 'you see where the others are — and can go to them'),
          selected: s.readMode == 'own',
          onTap: () => Navigator.of(ctx).pop('own'),
        ),
        const SizedBox(height: 8),
        _ModeRow(
          icon: Icons.link_rounded,
          title: at('листаем вместе', 'turn the pages together'),
          sub: at('страница общая: перевернул один — перевернулось у всех', 'one shared page: when one turns it, it turns for everyone'),
          selected: s.isTogether,
          onTap: () => Navigator.of(ctx).pop('together'),
        ),
        if (canAloud) ...[
          const SizedBox(height: 8),
          _ModeRow(
            icon: Icons.record_voice_over_rounded,
            title: iAmReader
                ? at('вы читаете вслух', 'you’re reading aloud')
                : readerName != null
                    ? at('читать вместо $readerName', 'read instead of $readerName')
                    : at('читаем вслух', 'read aloud'),
            sub: at('один читает по голосу, у остальных светится абзац, который он читает',
                'one reads over the voice; the paragraph being read glows for everyone else'),
            selected: iAmReader,
            onTap: () => Navigator.of(ctx).pop('aloud'),
          ),
        ],
      ]),
    ),
  );
}

class _ModeRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  const _ModeRow({required this.icon, required this.title, required this.sub, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scaleTo: 0.98,
      haptics: true,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ClayBoxDecoration(
          color: selected ? SeenlyPalette.accent.withOpacity(0.1) : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? SeenlyPalette.accent.withOpacity(0.55) : SeenlyPalette.border),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.accent.withOpacity(0.12)),
            child: Icon(icon, size: 21, color: SeenlyPalette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub, maxLines: 2, style: SeenlyText.serif(size: 12, italic: true, color: SeenlyPalette.inkFaint)),
            ]),
          ),
          if (selected) Icon(Icons.check_circle_rounded, size: 20, color: SeenlyPalette.accent),
        ]),
      ),
    );
  }
}

/// Zen for reading: the quiet row of feelings under the page — one tap each,
/// stamped with the place you're at, which is what the moments of your book
/// are made from. (The film's zen has glowing orbs; a book has the page.)
class ReadingFeelings extends StatefulWidget {
  final void Function(String key) onFeel;
  const ReadingFeelings({super.key, required this.onFeel});

  @override
  State<ReadingFeelings> createState() => _ReadingFeelingsState();
}

class _ReadingFeelingsState extends State<ReadingFeelings> {
  String? _last;

  @override
  Widget build(BuildContext context) {
    final reduce = _reduce(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedSwitcher(
        duration: Duration(milliseconds: reduce ? 1 : 300),
        child: Text(
          _last == null
              ? at('как вам сейчас? коснитесь', 'how does it feel? tap')
              : '${emotionEmoji(_last!)}  ${emotionLabel(_last!)}',
          key: ValueKey(_last),
          style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.inkMuted),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          itemCount: RoomKeys.emotions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final key = RoomKeys.emotions[i];
            return PressScale(
              scaleTo: 0.9,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _last = key);
                widget.onFeel(key);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: ClayBoxDecoration(
                  color: SeenlyPalette.paper.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: SeenlyPalette.accent.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(emotionEmoji(key), style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(emotionLabel(key), style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.ink)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
