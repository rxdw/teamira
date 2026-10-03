import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/co_view_room.dart';
import '../../../../theme/clay_kit.dart';
import '../../../../theme/palette.dart';
import '../../../../theme/text_styles.dart';
import '../../../../widgets/user_avatar.dart';
import '../../../../widgets/wow_motion.dart';
import '../room_controller.dart';
import '../room_strings.dart';
import '../room_widgets.dart';
import '../voice_controller.dart';

/// The inside of a game room: the evening around a real game that each person
/// runs on their own machine. Nothing of the game passes through here — the
/// room is the clock you play by, the "готов" everybody taps before you start,
/// the tally of rounds, the things players say to each other, the voice and
/// the chat.
///
///  * **the session clock** is the room's own clock: "поехали" starts it (the
///    first press opens the evening), "перерыв" pauses it, and anyone in the
///    circle can press either, as with a film. It can't be jumped around.
///  * **the ready check** is a courtesy, not a gate.
///  * **rounds** are one tap each — win, loss, draw, checkpoint — and make the
///    tally here and the moments of the evening in the review afterwards.
class PlayRoomView extends StatelessWidget {
  final RoomController room;
  final VoiceController voice;
  final VoidCallback onToggleVoice;

  /// "Доиграли" — only for people in the circle (null for a guest).
  final VoidCallback? onFinish;
  const PlayRoomView({
    super.key,
    required this.room,
    required this.voice,
    required this.onToggleVoice,
    required this.onFinish,
  });

  void _send(Future<void> Function() action) {
    action().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          children: [
            ListenableBuilder(listenable: room, builder: (context, _) => _gameCard()),
            const SizedBox(height: 18),
            ListenableBuilder(listenable: room, builder: (context, _) => _session(context)),
            const SizedBox(height: 18),
            ListenableBuilder(listenable: room, builder: (context, _) => _ready(context)),
            ListenableBuilder(listenable: room, builder: (context, _) => _rounds(context)),
            const SizedBox(height: 18),
            SignalRow(keys: RoomKeys.gameSignals, onSignal: (k) => _send(() => room.signal(k))),
            const SizedBox(height: 14),
            ReactionBar(onReact: (k) => _send(() => room.react(k))),
            const SizedBox(height: 18),
            _dock(context),
          ],
        ),
        Positioned.fill(child: FloatingReactions(room: room)),
        Positioned(left: 14, right: 14, top: 6, child: Center(child: RoomToasts(room: room))),
      ],
    );
  }

  // --- the game -----------------------------------------------------------------

  Widget _gameCard() {
    final s = room.state;
    final poster = s.posterUrl;
    final platform = s.platform;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 64,
            height: 64,
            child: poster != null && poster.isNotEmpty
                ? Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _posterFallback())
                : _posterFallback(),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 17, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              platform != null
                  ? at('играем на: ${platformLabel(platform)}', 'playing on: ${platformLabel(platform)}')
                  : at('каждый запускает игру у себя', 'everyone starts the game on their own'),
              style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkFaint),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _posterFallback() => ColoredBox(
        color: SeenlyPalette.cork,
        child: Icon(Icons.sports_esports_rounded, color: SeenlyPalette.inkFaint),
      );

  // --- the session clock ---------------------------------------------------------

  Widget _session(BuildContext context) {
    final s = room.state;
    final live = s.isLive;
    final running = s.isPlaying;
    final String status;
    if (!live) {
      status = s.allReady ? at('все готовы — поехали?', 'everyone’s ready — shall we?') : at('ждём всех', 'waiting for everyone');
    } else {
      status = running ? at('играем', 'playing') : at('перерыв', 'on a break');
    }
    final accent = running ? SeenlyPalette.accent : SeenlyPalette.sage;
    return Column(children: [
      Breathe(
        period: const Duration(milliseconds: 4200),
        minScale: running ? 0.965 : 1.0,
        child: Container(
          width: 196,
          height: 196,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withOpacity(0.1),
            border: Border.all(color: accent.withOpacity(running ? 0.55 : 0.3), width: 2),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(clockLabel(s.positionNowMs()), style: SeenlyText.serif(size: 44, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(status, textAlign: TextAlign.center, style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.inkMuted)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      PressScale(
        haptics: true,
        onTap: () => _send(running ? room.pause : room.play),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
          decoration: ClayBoxDecoration(
            color: running ? SeenlyPalette.paper : SeenlyPalette.accent,
            borderRadius: BorderRadius.circular(24),
            border: running ? Border.all(color: SeenlyPalette.accent.withOpacity(0.5)) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              running ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 22,
              color: running ? SeenlyPalette.accent : SeenlyPalette.accentOnAccent,
            ),
            const SizedBox(width: 8),
            Text(
              running ? at('перерыв', 'take a break') : (live ? at('продолжаем', 'carry on') : at('поехали!', 'let’s go!')),
              style: SeenlyText.serif(
                size: 17,
                weight: FontWeight.w600,
                color: running ? SeenlyPalette.accent : SeenlyPalette.accentOnAccent,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  // --- ready check ----------------------------------------------------------------

  Widget _ready(BuildContext context) {
    final s = room.state;
    if (s.isLive) return const SizedBox.shrink();
    final here = [for (final p in s.participants) if (p.present) p];
    final me = [for (final p in here) if (p.isYou) p].firstOrNull;
    final mineReady = me?.ready ?? false;
    return Column(children: [
      Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 10, children: [
        for (final p in here)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              UserAvatar(avatarUrl: p.avatarUrl, avatarPreset: p.avatarPreset, fallbackLetter: p.letter, size: 44),
              Positioned(
                right: -3,
                bottom: -3,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.ready ? SeenlyPalette.sage : SeenlyPalette.paper,
                    border: Border.all(color: p.ready ? SeenlyPalette.sage : SeenlyPalette.border, width: 2),
                  ),
                  child: p.ready ? Icon(Icons.check_rounded, size: 12, color: SeenlyPalette.accentOnAccent) : null,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(p.isYou ? at('вы', 'you') : p.name.toLowerCase(),
                style: SeenlyText.serif(size: 12, italic: true, color: SeenlyPalette.inkFaint)),
          ]),
      ]),
      const SizedBox(height: 12),
      PressScale(
        haptics: true,
        onTap: me == null ? null : () => _send(() => room.setReady(!mineReady)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          decoration: BoxDecoration(
            color: mineReady ? SeenlyPalette.sage.withOpacity(0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: mineReady ? SeenlyPalette.sage : SeenlyPalette.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(mineReady ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 18, color: mineReady ? SeenlyPalette.sage : SeenlyPalette.inkMuted),
            const SizedBox(width: 8),
            Text(mineReady ? at('я готов', 'I’m ready') : at('я готов?', 'ready?'),
                style: SeenlyText.serif(size: 14.5, weight: FontWeight.w600, color: mineReady ? SeenlyPalette.sage : SeenlyPalette.inkMuted)),
          ]),
        ),
      ),
      const SizedBox(height: 18),
    ]);
  }

  // --- rounds ---------------------------------------------------------------------

  Widget _rounds(BuildContext context) {
    final s = room.state;
    final live = s.isLive;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final k in RoomKeys.rounds) ...[
          Column(children: [
            Text(roundEmoji(k), style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: Duration(milliseconds: reduce ? 1 : 260),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Text(
                '${s.roundsOf(k)}',
                key: ValueKey('$k-${s.roundsOf(k)}'),
                style: SeenlyText.serif(size: 20, weight: FontWeight.w700),
              ),
            ),
          ]),
          const SizedBox(width: 22),
        ],
      ]),
      const SizedBox(height: 12),
      Opacity(
        opacity: live ? 1 : 0.45,
        child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final k in RoomKeys.rounds)
            PressScale(
              haptics: true,
              scaleTo: 0.93,
              onTap: live ? () => _send(() => room.round(k)) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: ClayBoxDecoration(
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SeenlyPalette.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(roundEmoji(k), style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Text(roundLabel(k), style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkMuted)),
                ]),
              ),
            ),
        ]),
      ),
      if (!live)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(at('раунды — когда начнёте', 'rounds — once you’ve started'),
              style: SeenlyText.serif(size: 12, italic: true, color: SeenlyPalette.inkFaint)),
        ),
    ]);
  }

  // --- dock -----------------------------------------------------------------------

  Widget _dock(BuildContext context) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        ListenableBuilder(
          listenable: voice,
          builder: (context, _) => RoomRoundButton(
            icon: !voice.isOn ? Icons.mic_none_rounded : (voice.muted ? Icons.mic_off_rounded : Icons.mic_rounded),
            active: voice.isOn && !voice.muted,
            color: SeenlyPalette.sage,
            size: 52,
            onTap: voice.isOn ? voice.toggleMute : onToggleVoice,
          ),
        ),
        const SizedBox(width: 16),
        RoomRoundButton(
          icon: Icons.chat_bubble_outline_rounded,
          size: 52,
          onTap: () => showRoomChatSheet(context, room),
        ),
        ListenableBuilder(
          listenable: voice,
          builder: (context, _) => voice.isOn
              ? Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: RoomRoundButton(icon: Icons.call_end_rounded, size: 52, onTap: onToggleVoice),
                )
              : const SizedBox.shrink(),
        ),
      ]),
      if (onFinish != null) ...[
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          SaveToSharedChip(room: room),
          ListenableBuilder(
            listenable: room,
            builder: (context, _) => room.state.isLive
                ? PressScale(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onFinish!();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: ClayBoxDecoration(
                        color: SeenlyPalette.paper,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: SeenlyPalette.accent.withOpacity(0.5)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.flag_rounded, size: 16, color: SeenlyPalette.accent),
                        const SizedBox(width: 6),
                        Text(at('доиграли', 'we’re done'),
                            style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600, color: SeenlyPalette.accent)),
                      ]),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ]),
      ],
    ]);
  }
}
