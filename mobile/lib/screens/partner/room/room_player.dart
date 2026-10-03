import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../models/co_view_room.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/wow_motion.dart';
import 'room_controller.dart';
import 'room_strings.dart';

/// How far the local picture may wander from the room's clock before it is
/// pulled back with a seek. Smaller would make every network hiccup audible.
const int kRoomDriftLimitMs = 1600;

/// The picture of a room. Three implementations behind one widget:
/// YouTube in an embedded player, a direct https file/stream through
/// `video_player`, and "parallel" — no picture at all, just the shared
/// clock on a cozy stage while each person plays the title in their own
/// streaming app. Twitch recordings run as parallel too: the embed needs the
/// same app-attestation YouTube's does (see pubspec), so the honest version
/// is "open it in Twitch, we keep the clock".
///
/// The widget never decides anything: it follows [RoomController.state]
/// (play/pause/seek arrive as a bumped `controlSeq`) and reports up only
/// what the picture knows and the room doesn't — the video's length, and
/// that it reached the end.
class RoomPlayer extends StatefulWidget {
  final RoomController controller;
  final VoidCallback onReachedEnd;

  /// The embed said no (YouTube refused to play inside the app). The screen
  /// swaps to the parallel stage for this device.
  final VoidCallback? onEmbedFailed;
  final bool forceParallel;

  const RoomPlayer({
    super.key,
    required this.controller,
    required this.onReachedEnd,
    this.onEmbedFailed,
    this.forceParallel = false,
  });

  @override
  State<RoomPlayer> createState() => _RoomPlayerState();
}

class _RoomPlayerState extends State<RoomPlayer> {
  @override
  Widget build(BuildContext context) {
    final s = widget.controller.state;
    final kind = widget.forceParallel ? PlayerKind.parallel : s.playerKind;
    switch (kind) {
      case PlayerKind.youtube:
        if (s.playerRef == null) break;
        return _YoutubeStage(
          controller: widget.controller,
          videoId: s.playerRef!,
          onReachedEnd: widget.onReachedEnd,
          onFailed: widget.onEmbedFailed,
        );
      case PlayerKind.direct:
        if (s.playerRef == null) break;
        return _DirectStage(
          controller: widget.controller,
          url: s.playerRef!,
          onReachedEnd: widget.onReachedEnd,
          onFailed: widget.onEmbedFailed,
        );
      case PlayerKind.twitch:
      case PlayerKind.parallel:
        break;
    }
    return ParallelStage(controller: widget.controller, onReachedEnd: widget.onReachedEnd);
  }
}

// --- shared following logic ---------------------------------------------------

/// Turns "the room says X" into "do X to the local player", once per
/// command and with a drift check in between.
class _Follower {
  _Follower(this.controller);
  final RoomController controller;
  int _appliedSeq = -1;

  /// Returns what to do now, or null for nothing.
  ({bool play, int? seekTo})? next({required int localMs, required bool localPlaying}) {
    final s = controller.state;
    final target = s.positionNowMs();
    final isNews = s.controlSeq != _appliedSeq;
    final drift = (localMs - target).abs();
    if (!isNews && drift <= kRoomDriftLimitMs && localPlaying == s.isPlaying) return null;
    if (!isNews && !s.isPlaying) {
      return drift > kRoomDriftLimitMs ? (play: false, seekTo: s.positionMs) : null;
    }
    _appliedSeq = s.controlSeq;
    final needSeek = isNews ? drift > 500 || !s.isPlaying : drift > kRoomDriftLimitMs;
    return (play: s.isPlaying, seekTo: needSeek ? (s.isPlaying ? target : s.positionMs) : null);
  }
}

bool _atTheEnd(int positionMs, int? durationMs) =>
    durationMs != null && durationMs > 0 && positionMs >= durationMs * 0.97;

// --- YouTube ---------------------------------------------------------------------

class _YoutubeStage extends StatefulWidget {
  final RoomController controller;
  final String videoId;
  final VoidCallback onReachedEnd;
  final VoidCallback? onFailed;
  const _YoutubeStage({
    required this.controller,
    required this.videoId,
    required this.onReachedEnd,
    this.onFailed,
  });

  @override
  State<_YoutubeStage> createState() => _YoutubeStageState();
}

class _YoutubeStageState extends State<_YoutubeStage> {
  late final YoutubePlayerController _yt;
  late final _Follower _follower = _Follower(widget.controller);
  StreamSubscription<YoutubePlayerValue>? _sub;
  Timer? _poll;
  bool _ready = false;
  bool _failed = false;
  bool _endedFired = false;
  bool _localPlaying = false;

  @override
  void initState() {
    super.initState();
    _yt = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        enableCaption: false,
        playsInline: true,
        strictRelatedVideos: true,
        enableKeyboard: false,
      ),
    );
    _yt.loadVideoById(videoId: widget.videoId);
    _yt.pauseVideo();
    _sub = _yt.listen(_onValue);
    widget.controller.addListener(_follow);
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _follow());
    // If the embed hasn't produced a playable video shortly, it's refused.
    Timer(const Duration(seconds: 14), () {
      if (mounted && !_ready && !_failed) _fail();
    });
  }

  void _onValue(YoutubePlayerValue v) {
    if (v.hasError) {
      _fail();
      return;
    }
    if (v.playerState != PlayerState.unknown && v.playerState != PlayerState.unStarted) {
      if (!_ready) {
        _ready = true;
        _yt.duration.then((d) {
          if (d > 0) widget.controller.learnDuration((d * 1000).round());
        });
        _follow();
      }
    }
    _localPlaying = v.playerState == PlayerState.playing || v.playerState == PlayerState.buffering;
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    widget.onFailed?.call();
  }

  Future<void> _follow() async {
    if (!_ready || !mounted || _failed) return;
    final secs = await _yt.currentTime;
    final localMs = (secs * 1000).round();
    final act = _follower.next(localMs: localMs, localPlaying: _localPlaying);
    if (act != null) {
      if (act.seekTo != null) await _yt.seekTo(seconds: act.seekTo! / 1000, allowSeekAhead: true);
      if (act.play) {
        await _yt.playVideo();
      } else {
        await _yt.pauseVideo();
      }
    }
    if (!_endedFired && widget.controller.state.isPlaying) {
      final d = widget.controller.state.durationMs;
      if (_atTheEnd(localMs, d)) {
        _endedFired = true;
        widget.onReachedEnd();
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_follow);
    _poll?.cancel();
    _sub?.cancel();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        // Every control goes through the room, so nobody can seek on their own.
        child: YoutubePlayer(controller: _yt, aspectRatio: 16 / 9),
      );
}

// --- direct file / stream -------------------------------------------------------

class _DirectStage extends StatefulWidget {
  final RoomController controller;
  final String url;
  final VoidCallback onReachedEnd;
  final VoidCallback? onFailed;
  const _DirectStage({
    required this.controller,
    required this.url,
    required this.onReachedEnd,
    this.onFailed,
  });

  @override
  State<_DirectStage> createState() => _DirectStageState();
}

class _DirectStageState extends State<_DirectStage> {
  late final VideoPlayerController _vp;
  late final _Follower _follower = _Follower(widget.controller);
  Timer? _poll;
  bool _ready = false;
  bool _endedFired = false;

  @override
  void initState() {
    super.initState();
    _vp = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _vp.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      final d = _vp.value.duration.inMilliseconds;
      if (d > 0) widget.controller.learnDuration(d);
      _follow();
    }).catchError((_) {
      widget.onFailed?.call();
    });
    widget.controller.addListener(_follow);
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _follow());
  }

  Future<void> _follow() async {
    if (!_ready || !mounted) return;
    final v = _vp.value;
    final act = _follower.next(localMs: v.position.inMilliseconds, localPlaying: v.isPlaying);
    if (act != null) {
      if (act.seekTo != null) await _vp.seekTo(Duration(milliseconds: act.seekTo!));
      if (act.play) {
        await _vp.play();
      } else {
        await _vp.pause();
      }
    }
    if (!_endedFired && widget.controller.state.isPlaying) {
      final d = v.duration.inMilliseconds;
      if (d > 0 && v.position.inMilliseconds >= d - 600) {
        _endedFired = true;
        widget.onReachedEnd();
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_follow);
    _poll?.cancel();
    _vp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: SeenlyPalette.paperOnDark.withOpacity(0.7)),
          ),
        ),
      );
    }
    return AspectRatio(aspectRatio: _vp.value.aspectRatio, child: VideoPlayer(_vp));
  }
}

// --- parallel ------------------------------------------------------------------

/// The stage for a title each person plays in their own app: a soft poster,
/// a big quiet clock, and a "3, 2, 1" the moment somebody presses play.
class ParallelStage extends StatefulWidget {
  final RoomController controller;
  final VoidCallback onReachedEnd;
  const ParallelStage({super.key, required this.controller, required this.onReachedEnd});

  @override
  State<ParallelStage> createState() => _ParallelStageState();
}

class _ParallelStageState extends State<ParallelStage> {
  int _lastSeq = -1;
  int _countdown = 0;
  Timer? _countTimer;
  bool _endedFired = false;

  @override
  void initState() {
    super.initState();
    _lastSeq = widget.controller.state.controlSeq;
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    final s = widget.controller.state;
    if (s.controlSeq != _lastSeq) {
      final wasNews = _lastSeq >= 0;
      _lastSeq = s.controlSeq;
      if (wasNews && s.isPlaying && s.positionMs < 2000) _startCountdown();
    }
    if (!_endedFired && s.isPlaying && _atTheEnd(s.positionNowMs(), s.durationMs)) {
      _endedFired = true;
      widget.onReachedEnd();
    }
  }

  void _startCountdown() {
    _countTimer?.cancel();
    setState(() => _countdown = 3);
    _countTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _countdown -= 1);
      if (_countdown <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _openElsewhere() async {
    final s = widget.controller.state;
    Uri? uri;
    if (s.source == 'twitch' && s.playerRef != null) {
      uri = Uri.parse('https://www.twitch.tv/videos/${s.playerRef}');
    } else if (s.source == 'youtube' && s.playerRef != null) {
      uri = Uri.parse('https://www.youtube.com/watch?v=${s.playerRef}');
    } else if (s.playerKind == PlayerKind.direct && s.playerRef != null) {
      uri = Uri.tryParse(s.playerRef!);
    }
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final s = widget.controller.state;
        final reduce = MediaQuery.of(context).disableAnimations;
        final canOpen = s.source == 'youtube' || s.source == 'twitch' || s.playerKind == PlayerKind.direct;
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (s.posterUrl != null)
                Opacity(
                  opacity: 0.32,
                  child: FadeInNetworkImage(url: s.posterUrl!, fit: BoxFit.cover, placeholder: const SizedBox.shrink()),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.15), Colors.black.withOpacity(0.55)],
                  ),
                ),
              ),
              Center(
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: reduce ? 1 : 320),
                  child: _countdown > 0
                      ? Text(
                          '$_countdown',
                          key: ValueKey(_countdown),
                          style: SeenlyText.serif(size: 64, weight: FontWeight.w600, color: SeenlyPalette.paperOnDark),
                        )
                      : Column(
                          key: const ValueKey('clock'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              clockLabel(s.positionNowMs()),
                              style: SeenlyText.serif(size: 38, weight: FontWeight.w600, color: SeenlyPalette.paperOnDark),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              s.isPlaying
                                  ? at('играем вместе', 'playing together')
                                  : (s.isLobby ? at('ждём всех и начинаем', 'waiting for everyone') : at('на паузе', 'paused')),
                              style: SeenlyText.serif(
                                  size: 13.5, italic: true, color: SeenlyPalette.paperOnDark.withOpacity(0.82)),
                            ),
                          ],
                        ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 10,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        at('включите фильм у себя — мы синхронизируем старт, паузы и голос',
                            'start the film on your own — we keep start, pauses and voice in sync'),
                        style: SeenlyText.serif(size: 12, color: SeenlyPalette.paperOnDark.withOpacity(0.72)),
                        maxLines: 2,
                      ),
                    ),
                    if (canOpen)
                      PressScale(
                        onTap: _openElsewhere,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.open_in_new_rounded, size: 18, color: SeenlyPalette.paperOnDark),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
