import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../models/co_view_room.dart';
import '../../../services/api_client.dart';
import '../../../services/co_view_room_service.dart';
import '../../../services/error_text.dart';
import '../../../services/premium_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/premium_upsell_sheet.dart';
import '../../../widgets/saved_celebration.dart';
import '../../../widgets/wow_motion.dart';
import 'circle_review_screen.dart';
import 'room_controller.dart';
import 'room_invite_sheet.dart';
import 'room_player.dart';
import 'room_strings.dart';
import 'play/play_room_view.dart';
import 'reading/reading_room_view.dart';
import 'room_widgets.dart';
import 'voice_controller.dart';
import 'zen_view.dart';

/// "Гостиная" — the room itself. Two ways of being in it, switched at the
/// top like the home screen's "вы | вы и …": **вместе** (picture, chat,
/// reactions, signals, voice) and **дзен** (the picture as a window, glowing
/// orbs for each of you, one-tap feelings). Same room, same clock, same
/// voice; only how much interface is around.
///
/// The screen draws [RoomController.state] and sends intents back; it never
/// owns playback. When the room ends — anyone pressing "досмотрели", or the
/// film reaching its end — every device plays the same ritual once: the
/// saved-evening celebration, then each person's own part of the joint review.
class RoomScreen extends StatefulWidget {
  final RoomState initial;
  const RoomScreen({super.key, required this.initial});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final CoViewRoomService _service = CoViewRoomService(ApiClient.instance);
  late final RoomController _room = RoomController(initial: widget.initial, service: _service);
  late final VoiceController _voice = VoiceController(roomId: widget.initial.id, service: _service);

  int _mode = 0;
  bool _embedFailed = false;
  bool _showSignals = false;
  bool _ending = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _room.addListener(_checkEnd);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _room.removeListener(_checkEnd);
    if (!_leaving) _room.leave();
    _voice.dispose();
    _room.dispose();
    super.dispose();
  }

  // --- ending ------------------------------------------------------------

  void _checkEnd() {
    if (_room.state.isEnded && !_room.endAlreadyHandled && mounted) _onEnded();
    // A guest whose invitation was taken back: leave the room politely.
    if (_room.lostAccess && !_leaving && mounted) {
      _leaving = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(at('вас больше нет в этой комнате', 'you’re no longer in this room'))),
      );
      Navigator.of(context).pop();
      return;
    }
    // The subscription lapsed while you were in zen: the room goes on, just
    // in the normal view (the server stops taking emotion taps too).
    if (_mode == 1 && !_room.state.zenAvailable && mounted) setState(() => _mode = 0);
  }

  Future<void> _onEnded() async {
    if (_room.endAlreadyHandled) return;
    _room.markEndHandled();
    setState(() => _ending = true);
    final s = _room.state;
    await _voice.leave();
    if (!mounted) return;

    if (s.savedEntryId != null) {
      final others = s.others.map((p) => p.name).join(', ');
      await showSavedCelebration(
        context,
        kind: SavedKind.logged,
        title: s.title,
        posterUrl: s.posterUrl,
        mediaType: s.mediaType,
        partnerName: others.isEmpty ? null : others,
        together: true,
      );
      if (!mounted) return;
      _leaving = true;
      if (s.meIsGuest) {
        // A guest has no part in the circle's joint review; the evening is in
        // their own diary, where they can rate it like any other.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(at('вечер записан в ваш дневник — оценить его можно там', 'the evening is in your diary — rate it there')),
        ));
        Navigator.of(context).pop();
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CircleReviewScreen(
          reviewId: s.reviewId,
          roomId: s.id,
          diaryEntryId: s.myDiaryEntryId,
          title: s.title,
          posterUrl: s.posterUrl,
          momentsDurationMs: s.durationMs,
        ),
      ));
      return;
    }

    // Closed, or finished with the save switch off: nothing was written.
    _leaving = true;
    if (s.startedAt != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.isReading
            ? at('прочитали — в список не записали', 'read — not saved to the list')
            : s.isGame
                ? at('поиграли — в список не записали', 'played — not saved to the list')
                : at('посмотрели — в список не записали', 'watched — not saved to the list')),
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _finish() async {
    final s = _room.state;
    if (s.isReading) return _finishReading();
    if (s.isGame) {
      // A game has no end to reach; a session of a minute or less is more
      // likely a mis-tap than an evening.
      if (s.positionNowMs() < 60000) {
        final ok = await _confirm(
          at('точно доиграли?', 'really done?'),
          at('вы почти не играли — меньше минуты', 'you’ve hardly played — under a minute'),
          at('да, закончили', 'yes, we’re done'),
        );
        if (ok != true) return;
      }
      try {
        await _room.finish();
      } catch (e) {
        _toast(describeError(e));
      }
      return;
    }
    if (s.progress < 0.5 && (s.durationMs ?? 0) > 0) {
      final ok = await _confirm(
        at('точно досмотрели?', 'really done?'),
        at('фильм ещё не дошёл до середины', 'the film hasn’t reached the halfway mark'),
        at('да, закончили', 'yes, we’re done'),
      );
      if (ok != true) return;
    }
    try {
      await _room.finish();
    } catch (e) {
      _toast(describeError(e));
    }
  }

  /// "Дочитали": the book has no clock, so how far you are is the furthest
  /// anybody got (what the server will record as where the evening ended).
  Future<void> _finishReading() async {
    final s = _room.state;
    final furthest = s.participants.fold<int>(0, (m, p) => p.progress > m ? p.progress : m);
    if (furthest < 500) {
      final ok = await _confirm(
        at('точно дочитали?', 'really done?'),
        at('вы ещё не дошли до середины', 'you haven’t reached the halfway mark yet'),
        at('да, закончили', 'yes, we’re done'),
      );
      if (ok != true) return;
    }
    try {
      await _room.finishReading();
    } catch (e) {
      _toast(describeError(e));
    }
  }

  Future<void> _onReachedEnd() async {
    // Ending the room is the circle's call; guests just watch it end.
    if (_room.state.isEnded || _room.state.meIsGuest) return;
    try {
      await _room.finish();
    } catch (_) {
      // The other side's push will bring the ending anyway.
    }
  }

  // --- leaving -----------------------------------------------------------

  Future<void> _confirmLeave() async {
    final s = _room.state;
    if (s.isEnded || !s.isLive) {
      await _leaveNow();
      return;
    }
    final ok = await _confirm(
      at('выйти из комнаты?', 'leave the room?'),
      s.presentCount > 1
          ? at('остальные продолжат, а вы сможете вернуться', 'the others will carry on, and you can come back')
          : s.isReading
              ? at('вы вернётесь на свою страницу', 'you’ll come back to your page')
              : s.isGame
                  ? at('таймер встанет на паузу — вернётесь и продолжите', 'the timer will pause — come back and carry on')
                  : at('фильм встанет на паузу — вернётесь и продолжите', 'the film will pause — come back and carry on'),
      at('выйти', 'leave'),
    );
    if (ok == true) await _leaveNow();
  }

  Future<void> _leaveNow() async {
    _leaving = true;
    await _voice.leave();
    await _room.leave();
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool?> _confirm(String title, String body, String yes) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SeenlyText.serif(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(body, style: SeenlyText.serif(size: 14, color: SeenlyPalette.inkMuted)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: PressScale(
                  onTap: () => Navigator.pop(ctx, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: ClayBoxDecoration(
                      color: SeenlyPalette.paper,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: SeenlyPalette.border),
                    ),
                    child: Text(at('остаться', 'stay'), style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PressScale(
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: ClayBoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(18)),
                    child: Text(yes,
                        style: SeenlyText.serif(size: 15, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // --- modes / voice ------------------------------------------------------

  Future<void> _setMode(int m) async {
    if (m == 1 && !_room.state.zenAvailable) {
      await showPremiumUpsellSheet(
        context,
        triggerSource: 'co_view_zen',
        initialKind: PremiumPlanKind.couple,
        icon: Icons.spa_rounded,
        title: at('дзен — для вас двоих', 'zen — for the two of you'),
        message: at(
          'тихий режим с живыми огоньками, тапами-эмоциями и таймлайном моментов фильма. '
              'одна подписка — на двоих, и вдвоём это дешевле',
          'a quiet mode with glowing orbs, one-tap feelings and a timeline of your film’s moments. '
              'one subscription covers both of you — and it costs less together',
        ),
      );
      return;
    }
    setState(() => _mode = m);
  }

  Future<void> _toggleVoice() async {
    if (_voice.isOn) {
      await _voice.leave();
      return;
    }
    await _voice.join();
    if (!mounted) return;
    switch (_voice.status) {
      case VoiceStatus.unavailable:
        _toast(at('голос на этом сервере пока не включён', 'voice isn’t set up on this server yet'));
      case VoiceStatus.denied:
        _toast(at('разрешите доступ к микрофону в настройках телефона', 'allow microphone access in your phone’s settings'));
      case VoiceStatus.off:
        _toast(at('не удалось включить голос', 'couldn’t turn voice on'));
      default:
        break;
    }
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.initial.isReading) return _readingScaffold();
    if (widget.initial.isGame) return _gameScaffold();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_ending) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: SeenlyPalette.background,
        body: Stack(children: [
          Positioned.fill(child: ZenBackdrop(posterUrl: widget.initial.posterUrl, visible: _mode == 1)),
          SafeArea(
          child: ListenableBuilder(
            listenable: _room,
            builder: (context, _) => Column(
              children: [
                _topBar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
                  child: RoomModeSwitch(
                    mode: _mode,
                    onChanged: _setMode,
                    zenLocked: !_room.state.zenAvailable,
                  ),
                ),
                // One picture for both modes: it stays mounted (so nothing
                // reloads or doubles up when you switch) and only its frame
                // softly narrows in "дзен".
                _stage(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: MediaQuery.of(context).disableAnimations ? 1 : 420),
                    switchInCurve: Curves.easeOutCubic,
                    child: _mode == 0 ? _together() : _zen(),
                  ),
                ),
              ],
            ),
          ),
          ),
        ]),
      ),
    );
  }

  /// A book or a manga: the same room, the same top bar, voice and ending —
  /// with the page where the picture would be, and no zen (its feelings are a
  /// film's; a reader's moments come from where they react and write).
  Widget _readingScaffold() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_ending) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: SeenlyPalette.background,
        body: SafeArea(
          child: Column(
            children: [
              ListenableBuilder(listenable: _room, builder: (context, _) => _topBar()),
              const SizedBox(height: 4),
              Expanded(
                child: ReadingRoomView(
                  room: _room,
                  voice: _voice,
                  onToggleVoice: _toggleVoice,
                  onFinish: _room.state.canSteer ? _finish : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A real game: the same room, top bar, voice and ending — with the session
  /// clock, the ready check and the tally where the picture would be.
  Widget _gameScaffold() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_ending) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: SeenlyPalette.background,
        body: SafeArea(
          child: Column(
            children: [
              ListenableBuilder(listenable: _room, builder: (context, _) => _topBar()),
              const SizedBox(height: 4),
              Expanded(
                child: PlayRoomView(
                  room: _room,
                  voice: _voice,
                  onToggleVoice: _toggleVoice,
                  onFinish: _room.state.canSteer ? _finish : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stage() {
    final zen = _mode == 1;
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedPadding(
      duration: Duration(milliseconds: reduce ? 1 : 420),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(horizontal: zen ? 52 : 18),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(zen ? 22 : 24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: SeenlyPalette.border),
                borderRadius: BorderRadius.circular(zen ? 22 : 24),
              ),
              child: _player(),
            ),
          ),
          Positioned.fill(child: FloatingReactions(room: _room)),
          Positioned(left: 14, right: 14, top: 12, child: Center(child: RoomToasts(room: _room))),
        ],
      ),
    );
  }

  Widget _topBar() {
    final s = _room.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
      child: Row(
        children: [
          PressScale(
            onTap: _confirmLeave,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(Icons.keyboard_arrow_down_rounded, size: 26, color: SeenlyPalette.ink),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: 17, weight: FontWeight.w600)),
                Text(
                  s.meIsGuest
                      ? at('вы в гостях · ${s.presentCount} в комнате', 'you’re a guest · ${s.presentCount} here')
                      : s.isLobby
                          ? at('гостиная · ждём всех', 'lounge · waiting for everyone')
                          : at('гостиная · ${s.presentCount} в комнате', 'lounge · ${s.presentCount} here'),
                  style: SeenlyText.serif(size: 12, italic: true, color: SeenlyPalette.inkFaint),
                ),
              ],
            ),
          ),
          if (s.canSteer)
            PressScale(
              haptics: true,
              onTap: () => showRoomInviteSheet(context, _room),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: SeenlyPalette.sage.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SeenlyPalette.sage.withOpacity(0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_add_alt_1_rounded, size: 15, color: SeenlyPalette.sage),
                  const SizedBox(width: 6),
                  Text(
                    s.guests.isEmpty ? at('позвать', 'invite') : at('гости ${s.guests.length}', 'guests ${s.guests.length}'),
                    style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.sage),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _player() => RoomPlayer(
        controller: _room,
        onReachedEnd: _onReachedEnd,
        forceParallel: _embedFailed,
        onEmbedFailed: () {
          if (!mounted || _embedFailed) return;
          setState(() => _embedFailed = true);
          _toast(at('встроенный плеер не запустился — оставляем общий таймер, включите видео у себя',
              'the built-in player wouldn’t start — keeping the shared clock, play it on your own'));
        },
      );

  Widget _transport({required bool big}) {
    final s = _room.state;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ListenableBuilder(
          listenable: _voice,
          builder: (context, _) => RoomRoundButton(
            icon: !_voice.isOn
                ? Icons.mic_none_rounded
                : (_voice.muted ? Icons.mic_off_rounded : Icons.mic_rounded),
            active: _voice.isOn && !_voice.muted,
            color: SeenlyPalette.sage,
            onTap: _voice.isOn ? _voice.toggleMute : _toggleVoice,
          ),
        ),
        const SizedBox(width: 18),
        RoomRoundButton(
          icon: s.meIsGuest
              ? (s.isPlaying ? Icons.pause_rounded : Icons.lock_outline_rounded)
              : (s.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          active: !s.meIsGuest,
          size: big ? 70 : 58,
          onTap: s.meIsGuest
              ? () => _toast(at('включает и ставит на паузу тот, кто позвал; попросите сигналом', 'the circle plays and pauses — ask with a signal'))
              : () async {
            try {
              await _room.togglePlay();
            } catch (e) {
              _toast(describeError(e));
            }
          },
        ),
        const SizedBox(width: 18),
        big
            ? RoomRoundButton(
                icon: Icons.chat_bubble_outline_rounded,
                onTap: () => showRoomChatSheet(context, _room),
              )
            : RoomRoundButton(
                icon: _voice.isOn ? Icons.call_end_rounded : Icons.headset_mic_outlined,
                onTap: _voice.isOn ? _toggleVoice : () => showRoomChatSheet(context, _room),
              ),
      ],
    );
  }

  Widget _together() {
    final s = _room.state;
    return ListView(
      key: const ValueKey('together'),
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      children: [
        const SizedBox(height: 10),
        RoomProgress(room: _room),
        const SizedBox(height: 12),
        _transport(big: true),
        const SizedBox(height: 14),
        PresenceStrip(room: _room, voice: _voice),
        const SizedBox(height: 14),
        ChatPeek(room: _room, onOpen: () => showRoomChatSheet(context, _room)),
        const SizedBox(height: 12),
        ReactionBar(onReact: (k) => _room.react(k).catchError((_) {})),
        const SizedBox(height: 10),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 260),
          crossFadeState: _showSignals ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: Center(
            child: PressScale(
              onTap: () => setState(() => _showSignals = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                child: Text(at('сигналы · пульс, рука, пауза?', 'signals · heartbeat, hand, pause?'),
                    style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkFaint)),
              ),
            ),
          ),
          secondChild: SignalRow(onSignal: (k) {
            _room.signal(k).catchError((_) {});
            HapticFeedback.selectionClick();
          }),
        ),
        const SizedBox(height: 16),
        if (s.meIsGuest)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                at('вы в гостях: смотрите, пишите и говорите — пульт у тех, кто позвал',
                    'you’re a guest: watch, chat and talk — the remote is with whoever invited you'),
                textAlign: TextAlign.center,
                style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkFaint),
              ),
            ),
          )
        else
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SaveToSharedChip(room: _room),
            if (s.isLive)
              PressScale(
                onTap: _finish,
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
                    Text(at('досмотрели', 'we’re done'),
                        style: SeenlyText.serif(size: 13.5, weight: FontWeight.w600, color: SeenlyPalette.accent)),
                  ]),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _zen() {
    return Column(
      key: const ValueKey('zen'),
      children: [
        Expanded(child: ZenView(room: _room, voice: _voice)),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _transport(big: false),
            if (_room.state.isLive && !_room.state.meIsGuest)
              PressScale(
                onTap: _finish,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(at('досмотрели', 'we’re done'),
                      style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkFaint)),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}
