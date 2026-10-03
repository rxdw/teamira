import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../models/co_view_room.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/wow_motion.dart';
import 'room_controller.dart';
import 'room_strings.dart';
import 'voice_controller.dart';

/// The glow colour of a film, taken once from its poster and remembered, so
/// the backdrop and the orbs always agree and the poster is read only once.
class ZenTint {
  static final Map<String, Color> _cache = {};

  static Color? cached(String? url) => url == null ? null : _cache[url];

  static Future<Color?> load(String? url) async {
    if (url == null) return null;
    final hit = _cache[url];
    if (hit != null) return hit;
    try {
      final gen = await PaletteGenerator.fromImageProvider(
        ResizeImage(NetworkImage(url), width: 96),
        maximumColorCount: 8,
      );
      final c = gen.vibrantColor?.color ?? gen.dominantColor?.color;
      if (c != null) _cache[url] = c;
      return c;
    } catch (_) {
      return null; // the accent colour is a perfectly good room
    }
  }
}

/// The soft glow that fills the whole screen behind a film in "дзен".
class ZenBackdrop extends StatefulWidget {
  final String? posterUrl;
  final bool visible;
  const ZenBackdrop({super.key, required this.posterUrl, required this.visible});

  @override
  State<ZenBackdrop> createState() => _ZenBackdropState();
}

class _ZenBackdropState extends State<ZenBackdrop> {
  Color? _tint;

  @override
  void initState() {
    super.initState();
    _tint = ZenTint.cached(widget.posterUrl);
    ZenTint.load(widget.posterUrl).then((c) {
      if (mounted && c != null) setState(() => _tint = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final glow = _tint ?? SeenlyPalette.accent;
    final reduce = MediaQuery.of(context).disableAnimations;
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: Duration(milliseconds: reduce ? 1 : 700),
        opacity: widget.visible ? 1 : 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, 0.35),
              radius: 1.05,
              colors: [glow.withOpacity(0.26), glow.withOpacity(0.08), SeenlyPalette.background],
              stops: const [0, 0.55, 1],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// "дзен": the same room with the interface stepped back. The picture stays
/// (smaller, a window rather than a stage), the chat and progress bar go
/// quiet, and what's left is the two-to-four of you as soft glowing orbs
/// that breathe on their own and swell when somebody talks, joined by
/// threads that brighten when you talk together. Feelings are one tap each
/// — "тепло", "смешно", "трогательно" — stamped with the moment in the film,
/// which is what the joint review and the moments timeline are built from.
/// No recording, no analysis of anyone's voice: the orbs only follow loudness.
///
/// The glow takes its colour from the poster, so every film has its own room.
class ZenView extends StatefulWidget {
  final RoomController room;
  final VoiceController voice;
  const ZenView({super.key, required this.room, required this.voice});

  @override
  State<ZenView> createState() => _ZenViewState();
}

class _ZenViewState extends State<ZenView> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  Color? _tint;
  String? _tintFor;
  String? _lastEmotion;
  final List<_Ripple> _ripples = [];
  int _rippleId = 0;

  @override
  void initState() {
    super.initState();
    _loadTint();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  Future<void> _loadTint() async {
    final url = widget.room.state.posterUrl;
    if (url == null || url == _tintFor) return;
    _tintFor = url;
    _tint = ZenTint.cached(url);
    final c = await ZenTint.load(url);
    if (mounted && c != null) setState(() => _tint = c);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  Future<void> _feel(String key) async {
    HapticFeedback.selectionClick();
    setState(() {
      _lastEmotion = key;
      _ripples.add(_Ripple(_rippleId++));
      if (_ripples.length > 4) _ripples.removeAt(0);
    });
    try {
      await widget.room.emotion(key);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(at('не получилось отметить — попробуйте ещё раз', 'couldn’t mark that — try again'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final glow = _tint ?? SeenlyPalette.accent;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Column(
          children: [
            const SizedBox(height: 6),
            Expanded(
              child: Center(
                child: ListenableBuilder(
                  listenable: Listenable.merge([widget.room, widget.voice, _breath]),
                  builder: (context, _) {
                    final people = widget.room.state.participants;
                    return _Orbs(
                      people: people,
                      levelOf: widget.voice.levelOf,
                      breath: reduce ? 0.5 : Curves.easeInOut.transform(_breath.value),
                      glow: glow,
                      ripples: _ripples,
                      onRippleDone: (id) {
                        if (mounted) setState(() => _ripples.removeWhere((r) => r.id == id));
                      },
                      reduce: reduce,
                    );
                  },
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: Duration(milliseconds: reduce ? 1 : 300),
              child: Text(
                _lastEmotion == null
                    ? at('как вам сейчас? коснитесь', 'how does it feel? tap')
                    : '${emotionEmoji(_lastEmotion!)}  ${emotionLabel(_lastEmotion!)}',
                key: ValueKey(_lastEmotion),
                style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.inkMuted),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: RoomKeys.emotions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final key = RoomKeys.emotions[i];
                  return PressScale(
                    scaleTo: 0.9,
                    onTap: () => _feel(key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: ClayBoxDecoration(
                        color: SeenlyPalette.paper.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: glow.withOpacity(0.35)),
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
            const SizedBox(height: 14),
          ],
        );
  }
}

class _Ripple {
  final int id;
  _Ripple(this.id);
}

/// The glowing orbs and the threads between them.
class _Orbs extends StatelessWidget {
  final List<RoomParticipant> people;
  final double Function(String userId) levelOf;
  final double breath; // 0..1
  final Color glow;
  final List<_Ripple> ripples;
  final ValueChanged<int> onRippleDone;
  final bool reduce;
  const _Orbs({
    required this.people,
    required this.levelOf,
    required this.breath,
    required this.glow,
    required this.ripples,
    required this.onRippleDone,
    required this.reduce,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = math.min(box.maxHeight, 240.0);
        final n = math.max(people.length, 1);
        final orb = math.min(84.0, (w - 40) / n - 16);
        final positions = <Offset>[
          for (var i = 0; i < n; i++)
            Offset(
              w * (i + 1) / (n + 1),
              h / 2 + (n > 2 ? math.sin(i * 1.7) * 26 : (i.isEven ? -10 : 10)),
            ),
        ];
        final levels = [for (final p in people) levelOf(p.userId)];
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ThreadPainter(
                    points: positions,
                    levels: levels,
                    color: glow,
                    breath: breath,
                  ),
                ),
              ),
              for (final r in ripples)
                Positioned.fill(
                  child: _RippleWave(key: ValueKey(r.id), color: glow, reduce: reduce, onDone: () => onRippleDone(r.id)),
                ),
              for (var i = 0; i < people.length; i++)
                Positioned(
                  left: positions[i].dx - orb / 2 - 14,
                  top: positions[i].dy - orb / 2 - 14,
                  child: _Orb(
                    person: people[i],
                    size: orb,
                    level: levels[i],
                    breath: breath,
                    color: glow,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Orb extends StatelessWidget {
  final RoomParticipant person;
  final double size;
  final double level;
  final double breath;
  final Color color;
  const _Orb({required this.person, required this.size, required this.level, required this.breath, required this.color});

  @override
  Widget build(BuildContext context) {
    final speaking = level > 0.02;
    final swell = 1 + 0.04 * breath + (speaking ? 0.12 * level : 0);
    final halo = 10 + 10 * breath + (speaking ? 26 * level : 0);
    return Opacity(
      opacity: person.present ? 1 : 0.4,
      child: Container(
        padding: const EdgeInsets.all(14),
        child: Transform.scale(
          scale: swell,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.30 + (speaking ? 0.3 * level : 0)), blurRadius: halo, spreadRadius: 2),
              ],
            ),
            child: ClipOval(
              child: UserAvatar(
                avatarUrl: person.avatarUrl,
                avatarPreset: person.avatarPreset,
                fallbackLetter: person.letter,
                size: size,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadPainter extends CustomPainter {
  final List<Offset> points;
  final List<double> levels;
  final Color color;
  final double breath;
  _ThreadPainter({required this.points, required this.levels, required this.color, required this.breath});

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final together = math.min(levels[i], levels[i + 1]);
      final any = math.max(levels[i], levels[i + 1]);
      final o = 0.16 + 0.10 * breath + 0.45 * together + 0.15 * any;
      final paint = Paint()
        ..color = color.withOpacity(o.clamp(0.0, 0.85).toDouble())
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2 + 3 * together;
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2 - 18 - 8 * breath);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) =>
      old.breath != breath || old.color != color || !_same(old.levels, levels) || !_samePts(old.points, points);

  bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _samePts(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A wide soft ring that expands from the middle when somebody taps a feeling.
class _RippleWave extends StatefulWidget {
  final Color color;
  final bool reduce;
  final VoidCallback onDone;
  const _RippleWave({super.key, required this.color, required this.reduce, required this.onDone});

  @override
  State<_RippleWave> createState() => _RippleWaveState();
}

class _RippleWaveState extends State<_RippleWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reduce ? 500 : 1800),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _RipplePainter(t: Curves.easeOut.transform(_c.value), color: widget.color, still: widget.reduce),
          ),
        ),
      );
}

class _RipplePainter extends CustomPainter {
  final double t;
  final Color color;
  final bool still;
  _RipplePainter({required this.t, required this.color, required this.still});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = still ? size.width * 0.2 : 20 + t * size.width * 0.5;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withOpacity((0.5 * (1 - t)).clamp(0.0, 1.0).toDouble());
    canvas.drawCircle(c, r, p);
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t;
}
