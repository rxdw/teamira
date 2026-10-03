import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../models/co_view_room.dart';
import '../../../../theme/clay_kit.dart';
import '../../../../theme/palette.dart';
import '../../../../services/premium_service.dart';
import '../../../../theme/text_styles.dart';
import '../../../../widgets/premium_upsell_sheet.dart';
import '../../../../widgets/wow_motion.dart';
import '../room_controller.dart';
import '../room_strings.dart';
import '../room_widgets.dart';
import '../voice_controller.dart';
import '../zen_view.dart';
import 'book_source.dart';
import 'comic_reader.dart';
import 'comic_source.dart';
import 'epub_reader.dart';
import 'parallel_reader.dart';
import 'reader_handle.dart';
import 'reading_library.dart';
import 'reading_locator.dart';
import 'reading_overlay.dart';
import 'reading_strings.dart';
import 'reading_widgets.dart';

/// The inside of a reading room: the page, and under it what you do together.
///
/// It owns the jobs that make reading *together*:
///  * **opening your own copy** — the file never leaves the device; the room
///    only learns its fingerprint (see book_source.dart);
///  * **telling the room where you are** — after a pause in turning pages,
///    never on every swipe;
///  * **following the shared place** in "together" and "aloud" — and only a
///    person's own turn moves it (in "aloud" only the reader's), so two phones
///    never hand the same page back and forth;
///  * **zen** — the quiet version for a premium circle: a soft backdrop, the
///    chrome stepped back, pages that settle instead of snap, and the row of
///    feelings stamped with the place you're at.
class ReadingRoomView extends StatefulWidget {
  final RoomController room;
  final VoiceController voice;
  final VoidCallback onToggleVoice;

  /// "Дочитали" — only for people in the circle (null for a guest).
  final VoidCallback? onFinish;
  const ReadingRoomView({
    super.key,
    required this.room,
    required this.voice,
    required this.onToggleVoice,
    required this.onFinish,
  });

  @override
  State<ReadingRoomView> createState() => _ReadingRoomViewState();
}

class _ReadingRoomViewState extends State<ReadingRoomView> {
  final _lib = ReadingLibrary.instance;
  final _handle = ReaderHandle();
  late final ReadingOverlayNotifier _overlay = ReadingOverlayNotifier(widget.room);
  final ValueNotifier<int> _mine = ValueNotifier<int>(0);

  bool _ready = false;
  bool _opening = false;
  String? _error;
  LocalBook? _book;
  ComicArchive? _comic;
  String? _myHash;
  ReadLocator? _start;

  int _sizeIndex = 1;
  bool _rtl = true;
  bool _zen = false;

  ReadLocator? _at;
  int _progress = 0;
  Timer? _reportTimer;
  int _appliedSeq = -1;
  bool _disposed = false;

  ReadKind get _kind => widget.room.state.readKind ?? ReadKind.parallel;
  RoomState get _s => widget.room.state;

  @override
  void initState() {
    super.initState();
    widget.room.addListener(_onRoom);
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    _reportTimer?.cancel();
    widget.room.removeListener(_onRoom);
    _overlay.dispose();
    _mine.dispose();
    _comic?.dispose();
    super.dispose();
  }

  // --- opening ---------------------------------------------------------------

  Future<void> _init() async {
    _sizeIndex = (await _lib.textSize()).clamp(0, readingTextSizes.length - 1);
    _rtl = await _lib.mangaRtl();
    final hash = _s.contentHash;
    if (_kind != ReadKind.parallel && hash != null) {
      final book = _kind == ReadKind.epub ? _lib.takePreparedBook(hash) : null;
      final comic = _kind == ReadKind.cbz ? _lib.takePreparedComic(hash) : null;
      if (book != null) {
        _book = book;
        _myHash = book.hash;
      } else if (comic != null) {
        _comic = comic;
        _myHash = comic.hash;
      } else if (!kIsWeb) {
        final path = await _lib.pathFor(hash);
        if (path != null && await File(path).exists()) {
          await _openPath(path, remember: false);
        }
      }
    }
    await _finishSetup();
  }

  Future<void> _finishSetup() async {
    _start = await _computeStart();
    if (_disposed) return;
    _appliedSeq = _s.controlSeq;
    _syncUnits();
    setState(() => _ready = true);
  }

  Future<ReadLocator> _computeStart() async {
    final s = _s;
    final kind = _kind;
    if (s.hasSharedPlace) {
      final lead = ReadLocator.tryParse(kind, s.leadLocator);
      if (lead != null) return lead;
    }
    final mine = ReadLocator.tryParse(kind, s.me?.locator);
    if (mine != null) return mine;
    final key = _myHash ?? s.contentHash;
    if (key != null) {
      final saved = ReadLocator.tryParse(kind, await _lib.savedPlace(key));
      if (saved != null) return saved;
    }
    return ReadLocator.start(kind);
  }

  Future<void> _openPath(String path, {bool remember = true}) async {
    if (mounted) setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (_kind == ReadKind.epub) {
        final b = await openEpubFile(path);
        _book = b;
        _myHash = b.hash;
      } else {
        final c = await ComicArchive.open(path);
        await _comic?.dispose();
        _comic = c;
        _myHash = c.hash;
      }
      if (remember) {
        await _lib.rememberPath(_myHash!, path);
        final roomHash = _s.contentHash;
        if (roomHash != null && roomHash != _myHash) await _lib.rememberPath(roomHash, path);
      }
    } on BookOpenException catch (e) {
      _error = openErrorText(e.code);
    } catch (_) {
      _error = openErrorText('broken');
    }
    if (_disposed) return;
    if (_book != null || _comic != null) {
      _start = await _computeStart();
      _syncUnits();
    }
    if (mounted) setState(() => _opening = false);
  }

  Future<void> _pick() async {
    if (kIsWeb) {
      setState(() => _error = at('на веб-версии файлы открыть нельзя — зайдите с телефона', 'files can’t be opened on the web — use your phone'));
      return;
    }
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _kind == ReadKind.epub ? const ['epub'] : const ['cbz', 'zip'],
        withData: false,
      );
      final path = res?.files.single.path;
      if (path == null) return;
      await _openPath(path);
    } catch (_) {
      if (mounted) setState(() => _error = openErrorText('broken'));
    }
  }

  void _syncUnits() {
    final units = _book?.content.chapters.length ?? _comic?.pageCount;
    if (units != null && units > 0) widget.room.learnUnits(units);
  }

  // --- where we are -------------------------------------------------------------

  void _onMoved(ReadLocator at, double fraction, {required bool byUser}) {
    _at = at;
    _progress = permille(fraction);
    _mine.value = _progress;
    final key = _myHash ?? _s.contentHash;
    if (key != null) _lib.savePlace(key, at.wire);
    _reportTimer?.cancel();
    final p = _progress;
    _reportTimer = Timer(const Duration(milliseconds: 500), () => _report(at, p, byUser));
  }

  bool _differsFromLead(ReadLocator at) {
    final lead = ReadLocator.tryParse(_kind, _s.leadLocator);
    if (lead == null) return true;
    if (lead.major != at.major) return true;
    return (at.minor - lead.minor).abs() > 2;
  }

  Future<void> _report(ReadLocator at, int progress, bool byUser) async {
    if (_disposed) return;
    final s = _s;
    try {
      if (s.isTogether && s.canSteer && byUser && _differsFromLead(at)) {
        await widget.room.lead(at.wire, progress);
      } else {
        await widget.room.reportLocator(at.wire, progress, contentHash: _myHash);
      }
    } catch (_) {
      // Where you are is soft information; the next turn will say it again.
    }
  }

  /// The room moved the shared place: go there — unless I'm the one who moved it.
  void _onRoom() {
    final s = _s;
    if (_zen && !s.zenAvailable && mounted) setState(() => _zen = false);
    if (!_ready || !s.hasSharedPlace || s.leadLocator == null) return;
    if (_appliedSeq == s.controlSeq) return;
    _appliedSeq = s.controlSeq;
    if (s.leadUserId != null && s.leadUserId == s.me?.userId) return;
    final at = ReadLocator.tryParse(_kind, s.leadLocator);
    if (at != null) _handle.goTo(at);
  }

  // --- things you do ------------------------------------------------------------

  void _pin(ReadLocator at, double fraction, String? quote) {
    final s = _s;
    showReadingPinSheet(
      context,
      room: widget.room,
      at: at,
      progress: permille(fraction),
      placeText: placeLabel(comic: _kind == ReadKind.cbz, major: at.major, units: s.readUnits),
      quote: quote,
    );
  }

  void _pinHere() {
    final at = _at ?? _start ?? ReadLocator.start(_kind);
    _pin(at, _progress / 1000, _handle.quoteNow());
  }

  /// "как читаем?" — the three ways to be in the room. Reading aloud brings
  /// the voice in with it: if yours is off, it is switched on for you.
  Future<void> _pickMode() async {
    final s = _s;
    if (!s.canSteer) return;
    final picked = await showReadingModeSheet(context, s: s, canAloud: _kind == ReadKind.epub);
    if (picked == null || !mounted) return;
    final meReading = s.isAloud && s.leadUserId == s.me?.userId;
    if (picked == s.readMode && !(picked == 'aloud' && !meReading)) return;
    try {
      await widget.room.setReadMode(picked, locator: _at?.wire, progress: _progress);
      if (picked == 'aloud' && !widget.voice.isOn && _s.voiceAvailable) widget.onToggleVoice();
    } catch (_) {}
  }

  /// The reader of an aloud room moves the glowing line.
  void _moveCursor(ReadLocator at, double fraction) {
    widget.room.lead(at.wire, permille(fraction)).catchError((_) {});
  }

  Future<void> _toggleZen() async {
    if (_zen) {
      setState(() => _zen = false);
      return;
    }
    if (!_s.zenAvailable) {
      await showPremiumUpsellSheet(
        context,
        triggerSource: 'co_view_zen',
        initialKind: PremiumPlanKind.couple,
        icon: Icons.spa_rounded,
        title: at('дзен — для вас двоих', 'zen — for the two of you'),
        message: at(
          'тихий режим для чтения: мягкий фон, плавное перелистывание, тап-эмоции и таймлайн моментов вашей книги. '
              'одна подписка — на двоих, и вдвоём это дешевле',
          'a quiet mode for reading: a soft backdrop, pages that glide, one-tap feelings and a timeline of your book’s moments. '
              'one subscription covers both of you — and it costs less together',
        ),
      );
      return;
    }
    if (mounted) setState(() => _zen = true);
  }

  /// A feeling, stamped with the place you're at.
  void _feel(String key) {
    final at = _at ?? _start ?? ReadLocator.start(_kind);
    widget.room.emotionAt(key, at.wire, _progress).catchError((_) {});
  }

  void _goToLead() {
    final at = ReadLocator.tryParse(_kind, _s.leadLocator);
    if (at != null) _handle.goTo(at);
  }

  // --- build ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    final comic = _kind == ReadKind.cbz;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final soft = Duration(milliseconds: reduce ? 1 : 500);
    return Stack(
      children: [
        // Zen: the whole room takes on a soft glow behind the page.
        Positioned.fill(child: ZenBackdrop(posterUrl: _s.posterUrl, visible: _zen)),
        Column(
          children: [
            // The chrome steps back in zen instead of vanishing.
            AnimatedSize(
              duration: soft,
              curve: Curves.easeOutCubic,
              child: _zen
                  ? const SizedBox(width: double.infinity)
                  : ListenableBuilder(listenable: Listenable.merge([widget.room, widget.voice]), builder: (context, _) => _topStrip()),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: AnimatedContainer(
                          duration: soft,
                          decoration: BoxDecoration(
                            color: comic && _comic != null
                                ? Colors.black
                                : SeenlyPalette.paper.withOpacity(_zen ? 0.86 : 1),
                            border: Border.all(color: SeenlyPalette.border.withOpacity(_zen ? 0.4 : 1)),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: _reader(),
                        ),
                      ),
                    ),
                    Positioned.fill(child: FloatingReactions(room: widget.room)),
                    Positioned(left: 14, right: 14, top: 10, child: Center(child: RoomToasts(room: widget.room))),
                  ],
                ),
              ),
            ),
            _dock(),
          ],
        ),
      ],
    );
  }

  Widget _reader() {
    final room = widget.room;
    switch (_kind) {
      case ReadKind.parallel:
        return ParallelReader(
          room: room,
          start: _start ?? ReadLocator.start(ReadKind.parallel),
          handle: _handle,
          onMoved: _onMoved,
          onPin: (at, f) => _pin(at, f, null),
          onFinish: widget.onFinish,
        );
      case ReadKind.epub:
        final b = _book;
        if (b == null) {
          return OpenCopyCard(kind: _kind, title: _s.title, busy: _opening, error: _error, onPick: _pick);
        }
        return EpubReader(
          book: b,
          start: _start ?? ReadLocator.start(ReadKind.epub),
          handle: _handle,
          overlay: _overlay,
          onMoved: _onMoved,
          onPin: (at, f, quote) => _pin(at, f, quote),
          sizeIndex: _sizeIndex,
          onSizeChanged: (i) {
            setState(() => _sizeIndex = i);
            _lib.setTextSize(i);
          },
          onFinish: widget.onFinish,
          aloud: _s.isAloud,
          iAmReader: _s.isAloud && _s.leadUserId == _s.me?.userId,
          onCursor: _moveCursor,
          zen: _zen,
        );
      case ReadKind.cbz:
        final c = _comic;
        if (c == null) {
          return OpenCopyCard(kind: _kind, title: _s.title, busy: _opening, error: _error, onPick: _pick);
        }
        return ComicReader(
          archive: c,
          start: _start ?? ReadLocator.start(ReadKind.cbz),
          rtl: _rtl,
          onRtlChanged: (v) {
            setState(() => _rtl = v);
            _lib.setMangaRtl(v);
          },
          handle: _handle,
          overlay: _overlay,
          onMoved: _onMoved,
          onPin: (at, f) => _pin(at, f, null),
          onFinish: widget.onFinish,
          zen: _zen,
        );
    }
  }

  Widget _topStrip() {
    final s = _s;
    final mismatch = _myHash != null && s.contentHash != null && _myHash != s.contentHash;
    final lead = ReadLocator.tryParse(_kind, s.leadLocator);
    // Somebody who can't move the shared place (a guest — or anyone, while the
    // line being read aloud is somebody else's) sees a way back to it.
    final strayed = s.hasSharedPlace &&
        lead != null &&
        _at != null &&
        _differsFromLead(_at!) &&
        (!s.canSteer || s.isAloud);
    String leader() {
      final id = s.leadUserId;
      if (id == null) return '';
      if (id == s.me?.userId) return at('вы', 'you');
      for (final p in s.participants) {
        if (p.userId == id) return p.name.toLowerCase();
      }
      return '';
    }

    final who = leader();
    final IconData modeIcon;
    final Color modeColor;
    final String modeLabel;
    if (s.isAloud) {
      modeIcon = Icons.record_voice_over_rounded;
      modeColor = SeenlyPalette.accent;
      modeLabel = who == at('вы', 'you')
          ? at('вы читаете вслух', 'you’re reading aloud')
          : (who.isEmpty ? at('читают вслух', 'reading aloud') : at('читает вслух · $who', 'reading aloud · $who'));
    } else if (s.isTogether) {
      modeIcon = Icons.link_rounded;
      modeColor = SeenlyPalette.sage;
      modeLabel = who.isEmpty
          ? at('листаем вместе', 'reading together')
          : at('листаем вместе · $who', 'reading together · $who');
    } else {
      modeIcon = Icons.link_off_rounded;
      modeColor = SeenlyPalette.inkMuted;
      modeLabel = at('каждый в своём темпе', 'each at your own pace');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          ReadingPill(
            icon: modeIcon,
            color: modeColor,
            label: modeLabel,
            onTap: s.canSteer ? _pickMode : null,
          ),
          // Reading aloud is heard, not seen: nudge whoever isn't on the voice yet.
          if (s.isAloud && s.voiceAvailable && !widget.voice.isOn)
            ReadingPill(
              icon: Icons.mic_none_rounded,
              color: SeenlyPalette.sage,
              label: at('включить голос — чтобы слышать', 'turn the voice on to hear'),
              onTap: widget.onToggleVoice,
            ),
          if (strayed)
            ReadingPill(
              icon: Icons.keyboard_return_rounded,
              color: SeenlyPalette.accent,
              label: s.isAloud ? at('к строчке, которую читают', 'to the line being read') : at('к общей странице', 'back to the shared page'),
              onTap: _goToLead,
            ),
          if (mismatch)
            ReadingPill(
              icon: Icons.info_outline_rounded,
              color: SeenlyPalette.coral,
              label: at('у вас другое издание — места могут не совпасть', 'a different edition — places may not line up'),
            ),
        ],
      ),
    );
  }

  Widget _dock() {
    final comic = _kind == ReadKind.cbz;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: AnimatedSize(
        duration: Duration(milliseconds: reduce ? 1 : 400),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReadingProgressBar(room: widget.room, mine: _mine),
            if (_zen) ...[
              const SizedBox(height: 6),
              ReadingFeelings(onFeel: _feel),
              const SizedBox(height: 10),
            ] else
              ReadingPeers(
                room: widget.room,
                comic: comic,
                onGo: (at) => _handle.goTo(at),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ListenableBuilder(
                  listenable: widget.voice,
                  builder: (context, _) => RoomRoundButton(
                    icon: !widget.voice.isOn
                        ? Icons.mic_none_rounded
                        : (widget.voice.muted ? Icons.mic_off_rounded : Icons.mic_rounded),
                    active: widget.voice.isOn && !widget.voice.muted,
                    color: SeenlyPalette.sage,
                    size: 48,
                    onTap: widget.voice.isOn ? widget.voice.toggleMute : widget.onToggleVoice,
                  ),
                ),
                const SizedBox(width: 16),
                RoomRoundButton(icon: Icons.edit_note_rounded, size: 48, onTap: _pinHere),
                if (!_zen) ...[
                  const SizedBox(width: 16),
                  RoomRoundButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    size: 48,
                    onTap: () => showRoomChatSheet(context, widget.room),
                  ),
                ],
                const SizedBox(width: 16),
                RoomRoundButton(
                  icon: Icons.spa_rounded,
                  active: _zen,
                  color: SeenlyPalette.sage,
                  size: 48,
                  onTap: _toggleZen,
                ),
                if (widget.voice.isOn && !_zen) ...[
                  const SizedBox(width: 16),
                  RoomRoundButton(icon: Icons.call_end_rounded, size: 48, onTap: widget.onToggleVoice),
                ],
              ],
            ),
            if (widget.onFinish != null) ...[
              const SizedBox(height: 10),
              _zen
                  ? ListenableBuilder(
                      listenable: widget.room,
                      builder: (context, _) => _s.isLive
                          ? PressScale(
                              onTap: widget.onFinish,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(at('дочитали', 'we’re done'),
                                    style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkFaint)),
                              ),
                            )
                          : const SizedBox.shrink(),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SaveToSharedChip(room: widget.room),
                        ListenableBuilder(
                          listenable: widget.room,
                          builder: (context, _) => _s.isLive
                              ? PressScale(
                                  onTap: widget.onFinish,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: ClayBoxDecoration(
                                      color: SeenlyPalette.paper,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: SeenlyPalette.accent.withOpacity(0.5)),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.check_rounded, size: 16, color: SeenlyPalette.accent),
                                      const SizedBox(width: 6),
                                      Text(at('дочитали', 'we’re done'),
                                          style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600, color: SeenlyPalette.accent)),
                                    ]),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
            ],
          ],
        ),
      ),
    );
  }
}
