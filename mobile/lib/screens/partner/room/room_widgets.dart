import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/co_view_room.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/wow_motion.dart';
import 'room_controller.dart';
import 'room_strings.dart';
import 'voice_controller.dart';

bool _reduce(BuildContext c) => MediaQuery.maybeOf(c)?.disableAnimations ?? false;

/// "вместе | дзен" — the same soft two-halves pill as the home screen's
/// "вы | вы и …" switch, so moving between the two ways of watching feels
/// like the gesture the app already taught.
class RoomModeSwitch extends StatelessWidget {
  final int mode; // 0 together, 1 zen
  final ValueChanged<int> onChanged;
  final bool zenLocked; // premium: shows a tiny lock until unlocked
  const RoomModeSwitch({super.key, required this.mode, required this.onChanged, this.zenLocked = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeHalf(
              label: at('вместе', 'together'),
              icon: Icons.chat_bubble_rounded,
              active: mode == 0,
              color: SeenlyPalette.accent,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _ModeHalf(
              label: at('дзен', 'zen'),
              icon: zenLocked ? Icons.lock_outline_rounded : Icons.spa_rounded,
              active: mode == 1,
              color: SeenlyPalette.sage,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeHalf extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _ModeHalf({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => PressScale(
        haptics: true,
        onTap: onTap,
        scaleTo: 0.96,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? color : SeenlyPalette.inkFaint),
              const SizedBox(width: 7),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                style: SeenlyText.serif(
                  size: 13.5,
                  italic: true,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? color : SeenlyPalette.inkMuted,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      );
}

/// One person: their avatar, a soft ring that swells with their voice, and a
/// dimmed look when they aren't in the room yet.
class PresenceBubble extends StatelessWidget {
  final RoomParticipant person;
  final double level; // 0..1 speaking loudness
  final double size;
  final bool showName;
  const PresenceBubble({
    super.key,
    required this.person,
    this.level = 0,
    this.size = 44,
    this.showName = true,
  });

  @override
  Widget build(BuildContext context) {
    final speaking = level > 0.02;
    final glow = speaking ? (0.25 + level * 0.75) : 0.0;
    final reduce = _reduce(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: Duration(milliseconds: reduce ? 1 : 140),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: speaking ? SeenlyPalette.sage.withOpacity(0.55 + glow * 0.4) : Colors.transparent,
              width: 2.2,
            ),
            boxShadow: speaking
                ? [BoxShadow(color: SeenlyPalette.sage.withOpacity(0.35 * glow), blurRadius: 10 + 14 * glow, spreadRadius: 1 + 3 * glow)]
                : const [],
          ),
          child: Opacity(
            opacity: person.present ? 1 : 0.42,
            child: UserAvatar(
              avatarUrl: person.avatarUrl,
              avatarPreset: person.avatarPreset,
              fallbackLetter: person.letter,
              size: size,
            ),
          ),
        ),
        if (showName) ...[
          const SizedBox(height: 4),
          Text(
            person.isYou
                ? at('вы', 'you')
                : person.isGuest
                    ? at('${person.name.toLowerCase()} · гость', '${person.name.toLowerCase()} · guest')
                    : person.name.toLowerCase(),
            style: SeenlyText.serif(size: 11.5, italic: true, color: SeenlyPalette.inkMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// Up to four people in a soft row, voice rings included.
class PresenceStrip extends StatelessWidget {
  final RoomController room;
  final VoiceController? voice;
  const PresenceStrip({super.key, required this.room, this.voice});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([room, if (voice != null) voice!]),
      builder: (context, _) {
        final people = room.state.participants;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 10,
          children: [
            for (final p in people) PresenceBubble(person: p, level: voice?.levelOf(p.userId) ?? 0),
          ],
        );
      },
    );
  }
}

/// Emoji drifting up from the bottom of the picture — one per reaction, from
/// whoever sent it. A quiet wobble and fade; with "reduce motion" on they
/// simply appear and fade in place.
class FloatingReactions extends StatefulWidget {
  final RoomController room;
  const FloatingReactions({super.key, required this.room});

  @override
  State<FloatingReactions> createState() => _FloatingReactionsState();
}

class _Floater {
  final int id;
  final String emoji;
  final double x; // 0..1
  final double wobble;
  _Floater(this.id, this.emoji, this.x, this.wobble);
}

class _FloatingReactionsState extends State<FloatingReactions> {
  final _rng = math.Random();
  final List<_Floater> _live = [];
  int _next = 0;
  late final StreamSubscription<RoomHappening> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.room.happenings.listen(_on);
  }

  void _on(RoomHappening h) {
    if (!h.event.isReaction || h.event.key == null) return;
    setState(() {
      _live.add(_Floater(_next++, h.event.key!, 0.12 + _rng.nextDouble() * 0.76, _rng.nextDouble() * 2 * math.pi));
      if (_live.length > 14) _live.removeAt(0);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = _reduce(context);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final f in _live)
              _Rising(
                key: ValueKey(f.id),
                floater: f,
                width: box.maxWidth,
                height: box.maxHeight,
                reduce: reduce,
                onDone: () {
                  if (mounted) setState(() => _live.removeWhere((x) => x.id == f.id));
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Rising extends StatefulWidget {
  final _Floater floater;
  final double width;
  final double height;
  final bool reduce;
  final VoidCallback onDone;
  const _Rising({super.key, required this.floater, required this.width, required this.height, required this.reduce, required this.onDone});

  @override
  State<_Rising> createState() => _RisingState();
}

class _RisingState extends State<_Rising> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reduce ? 900 : 2600),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_c.value);
        final rise = widget.reduce ? 0.0 : t * widget.height * 0.78;
        final sway = widget.reduce ? 0.0 : math.sin(widget.floater.wobble + _c.value * 5) * 14;
        final opacity = _c.value < 0.12 ? _c.value / 0.12 : (1 - ((_c.value - 0.55) / 0.45)).clamp(0.0, 1.0);
        final scale = widget.reduce ? 1.0 : 0.7 + 0.5 * Curves.easeOutBack.transform(math.min(1, _c.value * 3));
        return Positioned(
          left: widget.width * widget.floater.x + sway,
          bottom: 6 + rise,
          child: Opacity(
            opacity: opacity.toDouble(),
            child: Transform.scale(scale: scale, child: Text(widget.floater.emoji, style: const TextStyle(fontSize: 30))),
          ),
        );
      },
    );
  }
}

/// A gentle banner for signals ("аня: давай на паузу?") and the room's own
/// small news ("макс зашёл"). One at a time, each gone after a few seconds.
/// A "pulse" also buzzes the phone once.
class RoomToasts extends StatefulWidget {
  final RoomController room;
  const RoomToasts({super.key, required this.room});

  @override
  State<RoomToasts> createState() => _RoomToastsState();
}

class _RoomToastsState extends State<RoomToasts> {
  String? _text;
  String? _emoji;
  int _token = 0;
  late final StreamSubscription<RoomHappening> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.room.happenings.listen(_on);
  }

  String _who(RoomEvent e) => (e.username ?? at('кто-то', 'someone')).toLowerCase();

  void _on(RoomHappening h) {
    final e = h.event;
    String? text;
    String? emoji;
    if (e.isSignal && e.key != null && !h.mine) {
      text = '${_who(e)}: ${signalLabel(e.key!)}';
      emoji = signalEmoji(e.key!);
      if (e.key == 'pulse') {
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 140), HapticFeedback.lightImpact);
      } else if (e.key == 'hold') {
        HapticFeedback.selectionClick();
      }
    } else if (e.kind == 'join' && !h.mine) {
      text = at('${_who(e)} зашёл(ла)', '${_who(e)} joined');
      emoji = '👋';
    } else if (e.kind == 'leave' && !h.mine) {
      text = at('${_who(e)} вышел(ла)', '${_who(e)} stepped out');
      emoji = '🌙';
    } else if (e.kind == 'round' && !h.mine && e.key != null) {
      text = '${_who(e)}: ${roundLabel(e.key!)}';
      emoji = roundEmoji(e.key!);
    } else if (e.isMargin && !h.mine) {
      text = at('${_who(e)} оставил(а) заметку на полях', '${_who(e)} left a note in the margin');
      emoji = '📝';
    } else if (e.kind == 'system' && !h.mine && (e.body == 'read_together' || e.body == 'read_own' || e.body == 'read_aloud')) {
      text = switch (e.body) {
        'read_together' => at('${_who(e)}: давайте листать вместе', '${_who(e)}: let’s turn the pages together'),
        'read_aloud' => at('${_who(e)} читает вслух — включите голос', '${_who(e)} is reading aloud — turn the voice on'),
        _ => at('${_who(e)}: теперь каждый в своём темпе', '${_who(e)}: now each at your own pace'),
      };
      emoji = switch (e.body) { 'read_together' => '📖', 'read_aloud' => '🎙', _ => '🔖' };
    } else if (e.kind == 'control' && !h.mine && (e.body == 'pause' || e.body == 'play')) {
      text = e.body == 'pause'
          ? at('${_who(e)} поставил(а) на паузу', '${_who(e)} paused')
          : at('${_who(e)} продолжил(а)', '${_who(e)} pressed play');
      emoji = e.body == 'pause' ? '⏸️' : '▶️';
    }
    if (text == null) return;
    final mine = ++_token;
    setState(() {
      _text = text;
      _emoji = emoji;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _token == mine) setState(() => _text = null);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = _reduce(context);
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: reduce ? 1 : 300),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: _text == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : Container(
                key: ValueKey(_text),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: ClayBoxDecoration(
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SeenlyPalette.border),
                  boxShadow: SeenlyPalette.softShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_emoji != null) Text(_emoji!, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(_text!, style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.ink)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The row of one-tap reactions under the picture.
class ReactionBar extends StatelessWidget {
  final ValueChanged<String> onReact;
  const ReactionBar({super.key, required this.onReact});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: RoomKeys.reactions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final key = RoomKeys.reactions[i];
          return PressScale(
            haptics: true,
            scaleTo: 0.86,
            onTap: () => onReact(key),
            child: Container(
              width: 46,
              alignment: Alignment.center,
              decoration: ClayBoxDecoration(
                color: SeenlyPalette.paper,
                shape: BoxShape.circle,
                border: Border.all(color: SeenlyPalette.border),
                boxShadow: SeenlyPalette.flatCardShadow,
              ),
              child: Text(key, style: const TextStyle(fontSize: 22)),
            ),
          );
        },
      ),
    );
  }
}

/// The soft "nudge" buttons: pause?, rewind, a heartbeat, holding hands.
class SignalRow extends StatelessWidget {
  final ValueChanged<String> onSignal;

  /// Which signals to offer: a film's by default, a game's for a game room.
  final List<String> keys;
  const SignalRow({super.key, required this.onSignal, this.keys = RoomKeys.signals});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final key in keys)
          PressScale(
            haptics: true,
            scaleTo: 0.93,
            onTap: () => onSignal(key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: ClayBoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: SeenlyPalette.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(signalEmoji(key), style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(signalLabel(key), style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkMuted)),
              ]),
            ),
          ),
      ],
    );
  }
}

/// A round soft transport button (play/pause, mic, chat…).
class RoomRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;
  final double size;
  final String? badge;
  const RoomRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.color,
    this.size = 52,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? SeenlyPalette.accent;
    final fill = active ? base : SeenlyPalette.paper;
    final fg = active ? SeenlyPalette.accentOnAccent : SeenlyPalette.ink;
    return PressScale(
      haptics: true,
      scaleTo: 0.9,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: size,
            height: size,
            decoration: ClayBoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: active ? base : SeenlyPalette.border),
              boxShadow: SeenlyPalette.flatCardShadow,
            ),
            child: Icon(icon, size: size * 0.44, color: fg),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: SeenlyPalette.coral,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: SeenlyPalette.paper, width: 1.5),
                ),
                child: Text(badge!, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// The thin progress bar under the picture; a soft row of dots marks where
/// people reacted so far.
class RoomProgress extends StatelessWidget {
  final RoomController room;
  const RoomProgress({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final s = room.state;
        final d = s.durationMs ?? 0;
        return Column(
          children: [
            SizedBox(
              height: 14,
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: SeenlyPalette.border.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Container(
                        height: 4,
                        width: w * s.progress,
                        decoration: BoxDecoration(
                          color: SeenlyPalette.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (d > 0)
                        for (final e in room.events.where((e) => (e.isReaction || e.isEmotion) && e.positionMs != null))
                          Positioned(
                            left: (w * (e.positionMs! / d).clamp(0.0, 1.0)) - 2,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(color: SeenlyPalette.pink.withOpacity(0.85), shape: BoxShape.circle),
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
                Text(clockLabel(s.positionNowMs()), style: SeenlyText.mono(size: 12)),
                Text(d > 0 ? clockLabel(d) : '', style: SeenlyText.mono(size: 12)),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A single chat line, in a soft bubble tinted by whether it's mine.
class ChatBubble extends StatelessWidget {
  final RoomEvent event;
  final bool mine;
  const ChatBubble({super.key, required this.event, required this.mine});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: ClayBoxDecoration(
          color: mine ? SeenlyPalette.accent.withOpacity(0.16) : SeenlyPalette.paper,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 5),
            bottomRight: Radius.circular(mine ? 5 : 18),
          ),
          border: Border.all(color: mine ? SeenlyPalette.accent.withOpacity(0.3) : SeenlyPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine)
              Text((event.username ?? '').toLowerCase(),
                  style: SeenlyText.serif(size: 11.5, italic: true, color: SeenlyPalette.inkFaint)),
            Text(event.body ?? '', style: SeenlyText.serif(size: 14.5, color: SeenlyPalette.ink)),
          ],
        ),
      ),
    );
  }
}

/// The last few chat lines floating under the picture, fading as they age.
class ChatPeek extends StatelessWidget {
  final RoomController room;
  final VoidCallback onOpen;
  const ChatPeek({super.key, required this.room, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final lines = room.events.where((e) => e.isChat).toList();
        final recent = lines.length <= 3 ? lines : lines.sublist(lines.length - 3);
        return PressScale(
          onTap: onOpen,
          scaleTo: 0.99,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: ClayBoxDecoration(
              color: SeenlyPalette.cork.withOpacity(0.55),
              clayInset: true,
              borderRadius: BorderRadius.circular(20),
            ),
            child: recent.isEmpty
                ? Text(at('напишите что-нибудь друг другу…', 'say something to each other…'),
                    style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.placeholder))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < recent.length; i++)
                        Opacity(
                          opacity: 0.45 + 0.55 * ((i + 1) / recent.length),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: '${(recent[i].username ?? '').toLowerCase()}  ',
                                  style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkFaint),
                                ),
                                TextSpan(text: recent[i].body ?? '', style: SeenlyText.serif(size: 14, color: SeenlyPalette.ink)),
                              ]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// Full chat as a bottom sheet: history, and a soft input.
Future<void> showRoomChatSheet(BuildContext context, RoomController room) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ChatSheet(room: room),
  );
}

class _ChatSheet extends StatefulWidget {
  final RoomController room;
  const _ChatSheet({required this.room});

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    widget.room.addListener(_toEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
  }

  void _toEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.room.sendChat(body);
      _text.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(at('не отправилось — попробуйте ещё раз', 'didn’t send — try again'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    widget.room.removeListener(_toEnd);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final myId = widget.room.myId;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.62,
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Text(at('чат комнаты', 'room chat'), style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.room,
                builder: (context, _) {
                  final lines = widget.room.events.where((e) => e.isChat).toList();
                  if (lines.isEmpty) {
                    return Center(
                      child: Text(at('пока тихо', 'quiet so far'),
                          style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.placeholder)),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    itemCount: lines.length,
                    itemBuilder: (_, i) => ChatBubble(event: lines[i], mine: lines[i].userId == myId),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: clayWellDecoration(radius: 22),
                      child: TextField(
                        controller: _text,
                        maxLength: 400,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: SeenlyText.serif(size: 15),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          hintText: at('сообщение…', 'message…'),
                          hintStyle: SeenlyText.serif(size: 15, italic: true, color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  RoomRoundButton(icon: Icons.arrow_upward_rounded, active: true, size: 46, onTap: _send),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chip that shows — and flips — "save to our shared list". Tapping
/// opens a small sheet that explains it, so nobody switches it off by
/// accident; the choice is shared by everyone in the room.
class SaveToSharedChip extends StatelessWidget {
  final RoomController room;
  const SaveToSharedChip({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final on = room.state.saveToShared;
        final color = on ? SeenlyPalette.sage : SeenlyPalette.inkFaint;
        return PressScale(
          onTap: () => _openSheet(context),
          scaleTo: 0.96,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(on ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(on ? Icons.bookmark_added_rounded : Icons.bookmark_border_rounded, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                on ? at('сохраним в наш список', 'saving to our list') : at('не сохраняем', 'not saving'),
                style: SeenlyText.serif(size: 12.5, italic: true, color: color),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ListenableBuilder(
        listenable: room,
        builder: (ctx, _) {
          final on = room.state.saveToShared;
          return Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            decoration: ClayBoxDecoration(
              color: SeenlyPalette.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: SeenlyPalette.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(at('сохранить в наш список', 'save to our list'),
                    style: SeenlyText.serif(size: 18, weight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  at(
                    'когда досмотрите, вечер попадёт в общий список и общий дневник, а у каждого — в личный дневник. '
                        'выключите, если это просто фон и вспоминать не хочется. переключатель общий: его видят все в комнате.',
                    'when you finish, the evening lands on your shared list and diary, and on each of your own diaries. '
                        'switch it off if it was just background. it’s shared — everyone in the room sees it.',
                  ),
                  style: SeenlyText.serif(size: 14, color: SeenlyPalette.inkMuted),
                ),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  activeColor: SeenlyPalette.sage,
                  title: Text(at('сохранить', 'save it'), style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
                  onChanged: (v) async {
                    HapticFeedback.selectionClick();
                    try {
                      await room.setSaveToShared(v);
                    } catch (_) {}
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
