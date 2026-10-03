import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/co_view_room.dart';
import '../../../../theme/clay_kit.dart';
import '../../../../theme/palette.dart';
import '../../../../theme/text_styles.dart';
import '../../../../widgets/wow_motion.dart';
import '../room_strings.dart';
import 'book_source.dart';
import 'comic_source.dart';
import 'reading_library.dart';
import 'reading_strings.dart';

/// What the start sheet needs to open a reading room.
class ReadingStart {
  final String mediaType; // book | manga
  final String title;
  final ReadKind kind;
  final String? contentHash;
  final int? units;
  final String mode; // own | together
  const ReadingStart({
    required this.mediaType,
    required this.title,
    required this.kind,
    required this.contentHash,
    required this.units,
    required this.mode,
  });
}

/// "что читаем?" — the reading half of the start sheet. Three ways in:
/// your own EPUB, your own comic archive, or something you read somewhere else.
/// A file is opened here, on this device, to learn its title, length and
/// fingerprint; it is never uploaded.
class ReadingStartPanel extends StatefulWidget {
  final ValueChanged<ReadingStart> onStart;
  const ReadingStartPanel({super.key, required this.onStart});

  @override
  State<ReadingStartPanel> createState() => _ReadingStartPanelState();
}

enum _Way { none, epub, cbz, elsewhere }

class _ReadingStartPanelState extends State<ReadingStartPanel> {
  _Way _way = _Way.none;
  bool _busy = false;
  String? _error;

  final _title = TextEditingController();
  final _chapters = TextEditingController();

  // A file that was opened here:
  String? _hash;
  int? _units;
  String? _path;
  LocalBook? _book;
  ComicArchive? _comic;
  bool _handedOff = false;

  String _mediaType = 'book';
  String _mode = 'own';

  @override
  void dispose() {
    _title.dispose();
    _chapters.dispose();
    // A file opened here but never used is let go (a handed-off one now
    // belongs to the room screen).
    if (!_handedOff) _comic?.dispose();
    super.dispose();
  }

  void _choose(_Way way) {
    if (way == _way) return;
    if (!_handedOff) _comic?.dispose();
    setState(() {
      _way = way;
      _error = null;
      _hash = null;
      _units = null;
      _path = null;
      _book = null;
      _comic = null;
      _title.clear();
      _mediaType = way == _Way.cbz ? 'manga' : 'book';
      // Only a book drawn from text can be read aloud.
      if (way != _Way.epub && _mode == 'aloud') _mode = 'own';
    });
  }

  static String _stem(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final epub = _way == _Way.epub;
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: epub ? const ['epub'] : const ['cbz', 'zip'],
        withData: false,
      );
      final path = res?.files.single.path;
      if (path == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (epub) {
        final b = await openEpubFile(path);
        if (!mounted) return;
        setState(() {
          _book = b;
          _hash = b.hash;
          _units = b.content.chapters.length;
          _path = path;
          _title.text = b.content.title.isNotEmpty ? b.content.title : _stem(path);
        });
      } else {
        final c = await ComicArchive.open(path);
        if (!mounted) {
          await c.dispose();
          return;
        }
        await _comic?.dispose();
        setState(() {
          _comic = c;
          _hash = c.hash;
          _units = c.pageCount;
          _path = path;
          _title.text = _stem(path);
        });
      }
    } on BookOpenException catch (e) {
      if (mounted) setState(() => _error = openErrorText(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = openErrorText('broken'));
    }
    if (mounted) setState(() => _busy = false);
  }

  bool get _canStart {
    if (_busy) return false;
    switch (_way) {
      case _Way.none:
        return false;
      case _Way.epub:
      case _Way.cbz:
        return _hash != null;
      case _Way.elsewhere:
        return _title.text.trim().isNotEmpty;
    }
  }

  Future<void> _start() async {
    if (!_canStart) return;
    final kind = switch (_way) {
      _Way.epub => ReadKind.epub,
      _Way.cbz => ReadKind.cbz,
      _ => ReadKind.parallel,
    };
    int? units = _units;
    if (kind == ReadKind.parallel) {
      final n = int.tryParse(_chapters.text.trim());
      units = (n != null && n > 0) ? n : null;
    }
    if (_hash != null && _path != null) {
      final lib = ReadingLibrary.instance;
      await lib.rememberPath(_hash!, _path!);
      lib.prepare(book: _book, comic: _comic);
      _handedOff = true;
    }
    widget.onStart(ReadingStart(
      mediaType: kind == ReadKind.cbz ? 'manga' : _mediaType,
      title: _title.text,
      kind: kind,
      contentHash: _hash,
      units: units,
      mode: _mode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final files = !kIsWeb;
    return ListView(
      key: const ValueKey('read'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          at('читайте книгу или мангу вместе. текст у каждого свой: файл никуда не загружается, мы только показываем, кто на какой странице.',
              'read a book or a manga together. the text stays your own: files are never uploaded — we only show who’s on which page.'),
          style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted),
        ),
        const SizedBox(height: 12),
        if (files) ...[
          _WayCard(
            icon: Icons.menu_book_rounded,
            title: at('моя книга', 'my book'),
            sub: at('файл epub без защиты — откроется прямо здесь', 'a drm-free epub — opens right here'),
            selected: _way == _Way.epub,
            onTap: () => _choose(_Way.epub),
          ),
          const SizedBox(height: 8),
          _WayCard(
            icon: Icons.collections_bookmark_rounded,
            title: at('мой том манги или комикса', 'my manga or comic'),
            sub: at('файл cbz (или zip с картинками)', 'a cbz file (or a zip of images)'),
            selected: _way == _Way.cbz,
            onTap: () => _choose(_Way.cbz),
          ),
          const SizedBox(height: 8),
        ],
        _WayCard(
          icon: Icons.auto_stories_rounded,
          title: at('читаем где-то ещё', 'we read it elsewhere'),
          sub: at('на сайте, в другом приложении или на бумаге — отмечаем главы', 'on a site, in another app or on paper — we check chapters in'),
          selected: _way == _Way.elsewhere,
          onTap: () => _choose(_Way.elsewhere),
        ),
        if (_way == _Way.epub || _way == _Way.cbz) ...[
          const SizedBox(height: 14),
          if (_hash == null)
            _action(
              busy: _busy,
              label: at('выбрать файл', 'choose the file'),
              onTap: _pick,
              filled: false,
            )
          else ...[
            _field(_title, at('название', 'title')),
            const SizedBox(height: 6),
            Text(
              _way == _Way.epub
                  ? at('${_units ?? 0} глав · файл остаётся у вас', '${_units ?? 0} chapters · the file stays with you')
                  : at('${_units ?? 0} страниц · файл остаётся у вас', '${_units ?? 0} pages · the file stays with you'),
              style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkFaint),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _busy ? null : _pick,
              child: Text(at('выбрать другой файл', 'choose another file'),
                  style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.accent)),
            ),
          ],
        ],
        if (_way == _Way.elsewhere) ...[
          const SizedBox(height: 14),
          Row(children: [
            for (final (i, v) in const ['book', 'manga'].indexed)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 0 ? 8 : 0),
                  child: _chip(
                    v == 'book' ? at('книга', 'book') : at('манга', 'manga'),
                    _mediaType == v,
                    () => setState(() => _mediaType = v),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          _field(_title, at('название', 'title'), onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          _field(
            _chapters,
            at('сколько всего глав — по желанию', 'how many chapters in all — optional'),
            number: true,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.coral)),
        ],
        if (_way != _Way.none) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _chip(at('каждый в своём темпе', 'each at your own pace'), _mode == 'own', () => setState(() => _mode = 'own')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _chip(at('листаем вместе', 'turn pages together'), _mode == 'together', () => setState(() => _mode = 'together')),
            ),
          ]),
          if (_way == _Way.epub) ...[
            const SizedBox(height: 8),
            _chip(at('читаем вслух — один читает, остальные слушают', 'read aloud — one reads, the others listen'),
                _mode == 'aloud', () => setState(() => _mode = 'aloud')),
          ],
          const SizedBox(height: 16),
          Opacity(
            opacity: _canStart ? 1 : 0.45,
            child: _action(busy: false, label: at('открыть комнату', 'open the room'), onTap: _canStart ? _start : null, filled: true),
          ),
        ],
      ],
    );
  }

  Widget _field(TextEditingController c, String hint, {bool number = false, ValueChanged<String>? onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: clayWellDecoration(radius: 22),
      child: TextField(
        controller: c,
        onChanged: onChanged,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
        style: SeenlyText.serif(size: 15),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: SeenlyText.serif(size: 15, italic: true, color: SeenlyPalette.placeholder),
        ),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? SeenlyPalette.accent.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? SeenlyPalette.accent.withOpacity(0.5) : SeenlyPalette.border),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(
                size: 13,
                italic: true,
                weight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? SeenlyPalette.accent : SeenlyPalette.inkMuted)),
      ),
    );
  }

  Widget _action({required bool busy, required String label, required VoidCallback? onTap, required bool filled}) {
    return PressScale(
      haptics: true,
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: filled
            ? ClayBoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(22))
            : ClayBoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: SeenlyPalette.accent.withOpacity(0.5)),
              ),
        child: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label,
                style: SeenlyText.serif(
                    size: 16,
                    weight: FontWeight.w600,
                    color: filled ? SeenlyPalette.accentOnAccent : SeenlyPalette.accent)),
      ),
    );
  }
}

class _WayCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  const _WayCard({required this.icon, required this.title, required this.sub, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scaleTo: 0.98,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.all(12),
        decoration: ClayBoxDecoration(
          color: selected ? SeenlyPalette.accent.withOpacity(0.1) : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? SeenlyPalette.accent.withOpacity(0.55) : SeenlyPalette.border),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.accent.withOpacity(0.12)),
            child: Icon(icon, size: 22, color: SeenlyPalette.accent),
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
