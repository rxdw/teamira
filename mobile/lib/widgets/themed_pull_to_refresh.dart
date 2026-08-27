import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/log_theme_service.dart';
import '../theme/palette.dart';
import 'themed_loading_indicator.dart';

/// Home's own pull-to-refresh, standing in for the plain Material
/// [RefreshIndicator] — same job (wrap a scrollable, hand it
/// [onRefresh]), but painted with whichever of the app's own three
/// logging motifs is active (see [LogThemeService]) instead of a
/// circular spinner: a sprout opening its leaves, a ticket sliding out
/// of a slot, or a coach window whose scenery starts crawling — the
/// same drawings [ThemedLoadingIndicator] uses everywhere else, just
/// driven by the drag itself rather than a timer while you're still
/// pulling, then handed off to the same gentle loop once you've pulled
/// far enough to arm a refresh.
///
/// [RefreshIndicator] has no hook for swapping its visuals (its
/// painting is hardcoded to [RefreshProgressIndicator]), so this
/// listens to the same [ScrollNotification] family Flutter's own
/// implementation does and drives the motif directly.
class ThemedPullToRefresh extends StatefulWidget {
  final Widget child;
  final RefreshCallback onRefresh;

  /// Roughly how far below the top edge the motif sits once armed —
  /// same idea as [RefreshIndicator.displacement].
  final double displacement;

  const ThemedPullToRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 56,
  });

  @override
  State<ThemedPullToRefresh> createState() => _ThemedPullToRefreshState();
}

class _ThemedPullToRefreshState extends State<ThemedPullToRefresh>
    with TickerProviderStateMixin {
  // How far you need to drag (px) before letting go triggers a refresh.
  static const double _armDistance = 78;
  // Hard visual clamp so the motif never over-stretches past its frame.
  static const double _maxPull = 130;

  // The live pull distance. Set directly (not animated) while a finger
  // is actually dragging — the touch itself is already the animation —
  // and only ever eased with `animateTo` once the finger lifts, either
  // settling back to 0 (released early) or holding at the armed
  // position through the refresh.
  late final AnimationController _pull = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: _maxPull,
    duration: const Duration(milliseconds: 260),
  );

  // The same 2200ms breath [ThemedLoadingIndicator] loops on — reused
  // here once armed/refreshing so the motif doesn't change rhythm when
  // it hands off from "pulled" to "looping".
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  bool _armed = false;
  bool _refreshing = false;

  // Safety net: if the pull ever gets left above zero without a
  // release actually firing — e.g. bouncing (iOS-style) physics
  // reports drag-past-the-top purely through ScrollUpdateNotification
  // deltas rather than OverscrollNotification, or a ScrollEnd simply
  // doesn't arrive for whatever reason — this makes sure the motif
  // can never just sit there stranded mid-drag forever. Restarted on
  // every notification that still looks like an active drag; if it
  // ever fires, that means nothing has touched `_pull` in a while, so
  // it's safe to assume the gesture is over and ease back down.
  Timer? _staleGuard;

  @override
  void dispose() {
    _staleGuard?.cancel();
    _pull.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _armStaleGuard() {
    _staleGuard?.cancel();
    _staleGuard = Timer(const Duration(milliseconds: 400), () {
      if (mounted && !_refreshing && _pull.value > 0) {
        unawaited(_release());
      }
    });
  }

  bool _handleNotification(ScrollNotification notification) {
    // Ignore nested scrollables (a horizontal shelf inside the feed,
    // say) — only the outermost one drives the indicator.
    if (notification.depth != 0 || _refreshing) return false;

    // Two different sources for the same gesture, because Flutter's
    // two scroll physics report an overscroll differently:
    //  - ClampingScrollPhysics (Android's default) refuses to move
    //    the scroll position past the edge and reports the refused
    //    amount as an OverscrollNotification.
    //  - BouncingScrollPhysics (iOS/macOS's default) has no boundary
    //    at all — it just lets the position go negative and reports
    //    that as an ordinary ScrollUpdateNotification. Listening for
    //    OverscrollNotification alone (the previous version of this
    //    method) meant the motif never moved a pixel on iOS.
    // RefreshIndicator itself handles both for the same reason; this
    // mirrors that.
    double? overscrollDelta;
    if (notification is OverscrollNotification && notification.overscroll < 0) {
      overscrollDelta = -notification.overscroll;
    } else if (notification is ScrollUpdateNotification &&
        notification.metrics.extentBefore == 0.0 &&
        (notification.scrollDelta ?? 0) < 0) {
      overscrollDelta = -notification.scrollDelta!;
    }

    if (overscrollDelta != null) {
      final next = (_pull.value + overscrollDelta).clamp(0.0, _maxPull);
      _pull.value = next;
      final armed = next >= _armDistance;
      if (armed != _armed) {
        setState(() => _armed = armed);
        if (armed) HapticFeedback.selectionClick();
      }
      _armStaleGuard();
    }

    // The expected way this resolves: the finger lifts, physics
    // settles, Flutter reports it's done.
    if (notification is ScrollEndNotification && _pull.value > 0) {
      _staleGuard?.cancel();
      unawaited(_release());
    }

    return false;
  }

  Future<void> _release() async {
    _staleGuard?.cancel();
    if (_armed) {
      setState(() {
        _refreshing = true;
        _armed = false;
      });
      _loop.repeat();
      unawaited(_pull.animateTo(_armDistance, curve: Curves.easeOut));
      try {
        await widget.onRefresh();
      } catch (error, stack) {
        // Same non-fatal handling RefreshIndicator itself gives a
        // failed onRefresh — surfaced to the framework's error
        // reporting rather than crashing the pull gesture.
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'seenly',
          context: ErrorDescription('while refreshing via ThemedPullToRefresh'),
        ));
      } finally {
        if (mounted) {
          _loop.stop();
          await _pull.animateTo(0,
              duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
          if (mounted) setState(() => _refreshing = false);
        }
      }
    } else {
      await _pull.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _handleNotification,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge([_pull, _loop]),
              builder: (context, _) {
                final pull = _pull.value;
                if (pull <= 0.5 && !_refreshing) return const SizedBox.shrink();
                final dragProgress = (pull / _armDistance).clamp(0.0, 1.0);
                final travel = math.min(pull, widget.displacement + 20);
                final visibleProgress = _refreshing ? 1.0 : dragProgress;
                return Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: math.max(0, travel - 44)),
                    child: Opacity(
                      opacity: visibleProgress,
                      child: Transform.scale(
                        scale: 0.6 + 0.4 * visibleProgress,
                        child: _PullMotif(
                          theme: theme,
                          dragT: dragProgress,
                          loopT: _loop.value,
                          refreshing: _refreshing,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The motif itself: a small paper disc (echoing the ticket/boarding
/// pass card stock elsewhere in the app) holding whichever painter is
/// active, fed either the drag-driven `t` while pulling or the looping
/// controller's `t` once armed/refreshing.
class _PullMotif extends StatelessWidget {
  final LogTheme theme;
  final double dragT; // 0..1, how far through the arm distance
  final double loopT; // 0..1, current loop phase
  final bool refreshing;

  const _PullMotif({
    required this.theme,
    required this.dragT,
    required this.loopT,
    required this.refreshing,
  });

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    final t = refreshing ? loopT : _dragCommitment(theme, dragT);
    final painter = switch (theme) {
      LogTheme.garden => SproutMotionPainter(t: t),
      LogTheme.coach => CoachWindowMotionPainter(t: t),
      LogTheme.ticket => TicketPrintMotionPainter(t: t),
      LogTheme.shuttle => ShuttlePulseMotionPainter(t: t),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: SeenlyPalette.ink.withOpacity(0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CustomPaint(size: const Size(size, size), painter: painter),
    );
  }

  /// Maps 0..1 of "how far through the arm distance" onto the leading,
  /// non-cyclic portion of each painter's own `t` curve — the part
  /// where it's still opening rather than holding or retracting — so
  /// pulling further visibly commits the motif further, topping out
  /// fully open right as the drag arms.
  double _dragCommitment(LogTheme theme, double dragT) {
    return switch (theme) {
      LogTheme.garden => dragT * 0.5, // 0..0.5 is the sprout's full growth
      LogTheme.ticket => dragT * 0.6, // 0..0.6 is the ticket's slide-out
      LogTheme.coach => 0, // the window only starts moving once refreshing
      LogTheme.shuttle => dragT * 0.5, // 0..0.5 is the flame's full pulse
    };
  }
}
