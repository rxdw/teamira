import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/co_view_room.dart';
import '../../../../services/error_text.dart';
import '../../../../theme/clay_kit.dart';
import '../../../../theme/palette.dart';
import '../../../../theme/text_styles.dart';
import '../../../../widgets/wow_motion.dart';
import '../room_controller.dart';
import '../room_strings.dart';
import 'reader_handle.dart';
import 'reading_locator.dart';
import 'reading_strings.dart';

/// For something read somewhere else — an official site, a paper book, a file
/// on another app. The room keeps the one thing it can: which chapter each of
/// you is on. Nothing is shown of the text, because there isn't any here.
class ParallelReader extends StatefulWidget {
  final RoomController room;
  final ReadLocator start;
  final ReaderHandle handle;
  final ReaderMoved onMoved;
  final void Function(ReadLocator at, double fraction) onPin;
  final VoidCallback? onFinish;
  const ParallelReader({
    super.key,
    required this.room,
    required this.start,
    required this.handle,
    required this.onMoved,
    required this.onPin,
    this.onFinish,
  });

  @override
  State<ParallelReader> createState() => _ParallelReaderState();
}

class _ParallelReaderState extends State<ParallelReader> {
  late int _chapter;
  late bool _started;

  int? get _units => widget.room.state.readUnits;

  /// How far through, 0..1. With the length known it is exact; without it the
  /// chapter count stands in at half a per cent a chapter, which only has to
  /// spread the evening's reactions along the timeline.
  double get _fraction {
    final u = _units;
    if (u != null && u > 0) return ((_chapter + 1) / u).clamp(0.0, 1.0);
    return (_chapter * 0.005).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _chapter = widget.start.major;
    final s = widget.room.state;
    _started = s.isLive || (s.me?.locator != null);
    widget.handle.attach(go: _goTo);
  }

  @override
  void dispose() {
    widget.handle.detach();
    super.dispose();
  }

  void _goTo(ReadLocator at) {
    if (!mounted) return;
    setState(() {
      _chapter = at.major;
      _started = true;
    });
    widget.onMoved(ReadLocator(ReadKind.parallel, _chapter), _fraction, byUser: false);
  }

  void _step(int delta) {
    final max = (_units != null && _units! > 0) ? _units! - 1 : ReadLocator.maxChapter;
    final next = (_chapter + delta).clamp(0, max);
    if (next == _chapter && _started) return;
    HapticFeedback.selectionClick();
    setState(() {
      _chapter = next;
      _started = true;
    });
    widget.onMoved(ReadLocator(ReadKind.parallel, _chapter), _fraction, byUser: true);
  }

  Future<void> _askUnits() async {
    final c = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SeenlyPalette.background,
        title: Text(at('сколько всего глав?', 'how many chapters in all?'), style: SeenlyText.serif(size: 17, weight: FontWeight.w600)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: SeenlyText.serif(size: 16),
          decoration: InputDecoration(hintText: '24', hintStyle: SeenlyText.serif(size: 16, color: SeenlyPalette.placeholder)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(at('позже', 'later'))),
          TextButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)), child: Text(at('готово', 'done'))),
        ],
      ),
    );
    c.dispose();
    if (n == null || n <= 0) return;
    try {
      await widget.room.learnUnits(n);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.room,
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final units = _units;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 8, 26, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Breathe(
            period: const Duration(milliseconds: 4600),
            minScale: 0.96,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeenlyPalette.sage.withOpacity(0.14),
                border: Border.all(color: SeenlyPalette.sage.withOpacity(0.4)),
              ),
              child: Icon(Icons.auto_stories_rounded, size: 40, color: SeenlyPalette.sage),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            at('читайте у себя — а здесь отмечайтесь', 'read on your own — and check in here'),
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 22),
          if (!_started)
            PressScale(
              haptics: true,
              onTap: () => _step(0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                decoration: ClayBoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(22)),
                child: Text(at('начинаем читать', 'we’re starting'),
                    style: SeenlyText.serif(size: 16, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
              ),
            )
          else ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              RoomStepButton(icon: Icons.remove_rounded, onTap: _chapter > 0 ? () => _step(-1) : null),
              const SizedBox(width: 22),
              Column(children: [
                Text('${_chapter + 1}', style: SeenlyText.serif(size: 54, weight: FontWeight.w700)),
                Text(at('глава', 'chapter'), style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkFaint)),
              ]),
              const SizedBox(width: 22),
              RoomStepButton(icon: Icons.add_rounded, onTap: () => _step(1)),
            ]),
            const SizedBox(height: 10),
            if (units != null && units > 0)
              Text(at('из $units', 'of $units'), style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted))
            else
              GestureDetector(
                onTap: _askUnits,
                child: Text(at('указать, сколько всего глав', 'say how many chapters there are'),
                    style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.accent)),
              ),
            const SizedBox(height: 18),
            PressScale(
              onTap: () => widget.onPin(ReadLocator(ReadKind.parallel, _chapter), _fraction),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: ClayBoxDecoration(
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: SeenlyPalette.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_note_rounded, size: 18, color: SeenlyPalette.sage),
                  const SizedBox(width: 6),
                  Text(at('заметка или реакция', 'a note or a reaction'),
                      style: SeenlyText.serif(size: 14, weight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// A round "−" / "+" for the chapter counter.
class RoomStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const RoomStepButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: PressScale(
        haptics: true,
        scaleTo: 0.9,
        onTap: onTap,
        child: Container(
          width: 54,
          height: 54,
          decoration: ClayBoxDecoration(
            color: SeenlyPalette.paper,
            shape: BoxShape.circle,
            border: Border.all(color: SeenlyPalette.border),
            boxShadow: SeenlyPalette.flatCardShadow,
          ),
          child: Icon(icon, size: 26, color: SeenlyPalette.ink),
        ),
      ),
    );
  }
}
