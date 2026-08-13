import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// A small, shared vocabulary of "wow" micro-motion — kept minimalist and
/// elegant on purpose (soft easing, small distances, no bounce) so it
/// reads as *polish* rather than decoration, and so the same three moves
/// can be dropped in anywhere in the app and still feel like one voice.
///
/// - [Entrance] — a once-per-appearance cascade: content settles in from
///   just below with a breath of a fade, staggered by [delay] so a stack
///   of sections/cards arrives like a held breath being let out, not a
///   single flat cut.
/// - [PressScale] — the tactile reply every tappable surface deserves: a
///   hair of a scale-down the instant a finger lands, springing back on
///   release. Makes the whole app feel like it's responding to touch
///   rather than just reacting to it.
/// - [Breathe] — a very slow, very small looping pulse for the one or two
///   things per screen that should feel quietly alive (a glow behind an
///   icon, a streak flame) — never more than one per screen, or it stops
///   reading as "alive" and starts reading as "busy".

/// A once-per-appearance cascade: content settles in from just below
/// with a breath of a fade, staggered by [delay] so a stack of
/// sections/cards arrives like a held breath being let out, not a
/// single flat cut. Plays the moment this widget mounts — right for
/// content that's on screen from the very first frame (a header, a
/// dialog), but for anything further down a long page it means the
/// animation already finished by the time someone actually scrolls to
/// it. For that case, see [ScrollReveal] below.
///
/// Re-mounting (e.g. a fresh [key] after a pull to refresh) plays it
/// again, which is exactly the point — it turns a refresh into a small
/// resettle instead of a silent swap.
class Entrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double riseBy;
  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 560),
    this.riseBy = 26,
  });

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // A single post-frame timer per instance rather than Future.delayed
    // in initState — keeps every Entrance in a screen keyed to the same
    // frame clock, so staggered delays line up exactly instead of
    // drifting by however long each widget took to build.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        // A hair of scale-in stacked on top of the fade+rise — on its
        // own it's imperceptible, but it's the difference between a
        // flat slide-and-fade (what every other list entrance does)
        // and something that reads as *settling* into place. Kept
        // small on purpose: any more and it starts looking like a pop
        // instead of a settle.
        final scale = 0.97 + 0.03 * t;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.riseBy),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}

/// The scroll-triggered sibling of [Entrance]: instead of playing the
/// moment this widget mounts, it watches the nearest [Scrollable] and
/// plays its own fade + rise the moment its own top edge actually
/// crosses into the visible viewport (plus [revealMargin] of lead, so it
/// settles into place a hair before it's fully in view rather than
/// visibly popping in right at the edge) — so scrolling itself becomes
/// the thing that unveils each section, one after another, at whatever
/// pace someone actually scrolls at, rather than everything below the
/// fold having already finished animating before it's ever seen.
///
/// Content already on screen the moment this mounts (the very top of a
/// short list, or anything above the fold on first paint) still reveals
/// right away — there's no scroll gesture required to trigger the very
/// first check.
///
/// Unlike [Entrance], this replays every time the content re-enters
/// view rather than once per mount: once an item scrolls far enough out
/// of the viewport (past [revealMargin] on either edge) it quietly
/// resets to its hidden state — invisible, since it's off-screen by
/// then anyway — so the next time it's scrolled back into view, up or
/// down, it settles in again instead of just sitting there already
/// fully in place. A slow scroll back and forth near the reveal edge
/// won't thrash, since it takes a real scroll past the margin in each
/// direction to toggle it.
///
/// The reveal itself is two moves layered on one timeline rather than a
/// plain fade+rise:
/// - fade + rise finish just over halfway through the timeline — a
///   settle, same shape as [Entrance].
/// - the content itself sharpens from a soft blur into focus over the
///   back half of the same timeline, so it settles the way a camera
///   racks into focus rather than just becoming opaque.
/// The blur wrapper is dropped entirely once it finishes (not just set
/// to a no-op value), so a settled section costs nothing extra to keep
/// painting.
/// Broadcasts the nearest ancestor [ScrollReveal]'s reveal/hide events
/// down to descendants — specifically for [HorizontalReveal] tiles
/// living inside a horizontal list that's nested inside a
/// [ScrollReveal]-wrapped section (cast, trailers, provider chips,
/// ...). Two independent counters, since "start showing" and "go back
/// to hidden" need to reach descendants at different moments:
/// - [playGeneration] bumps once per forward-trigger, whether that
///   trigger came from scrolling into view, scrolling back into view a
///   second time, or a [TabActivation] replay.
/// - [resetGeneration] bumps the instant the section leaves view (or
///   is about to replay) and snaps back to hidden — *before* the next
///   reveal's delay/animation even begins, so anything listening can
///   snap back to hidden in the same instant rather than sitting at
///   its old fully-revealed state until the next play catches up to
///   it. Without this, a tile that's already settled from a previous
///   pass stays fully visible for the whole gap between the section
///   re-entering view and its delayed forward actually starting,
///   reading as "pops in immediately, *then* plays the slide-in" —
///   exactly backwards from the intended effect.
/// A one-shot entrance for a single hero banner (right now, just
/// Profile's cover photo) — slides in from just past its own edge
/// while fading in, the same soft `easeOutCubic` + no-bounce feel as
/// [Entrance], just with a longer travel distance and duration so a
/// wide banner reads as *arriving* on its own rather than blending
/// into the same small 26px settle every card/section already uses.
/// [from] picks the direction: negative slides in from above (a
/// banner dropping into place, the default), positive from below.
/// Plays once per mount — same "a fresh key re-plays it" behavior as
/// [Entrance], so a pull-to-refresh that remounts the header lets the
/// banner arrive again instead of just sitting there static.
class BannerReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double from;

  const BannerReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 640),
    this.from = -56,
  });

  @override
  State<BannerReveal> createState() => _BannerRevealState();
}

class _BannerRevealState extends State<BannerReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // Same reasoning as Entrance's own post-frame timer — keyed to the
    // shared frame clock rather than Future.delayed straight from
    // initState, so it lines up with whatever else on the header is
    // staggered against it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.from),
            child: child,
          ),
        );
      },
    );
  }
}

class RevealPulse extends InheritedWidget {
  final int playGeneration;
  final int resetGeneration;
  const RevealPulse({
    super.key,
    required this.playGeneration,
    required this.resetGeneration,
    required super.child,
  });

  static RevealPulse? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RevealPulse>();

  @override
  bool updateShouldNotify(RevealPulse oldWidget) =>
      playGeneration != oldWidget.playGeneration || resetGeneration != oldWidget.resetGeneration;
}

/// The horizontal sibling of [Entrance], for individual tiles inside a
/// horizontal list (cast, trailers, provider chips, a shelf of
/// posters, ...) that sits inside a [ScrollReveal]-wrapped section:
/// instead of settling up from below on its own, each tile settles in
/// from the right, staggered by [delay] across the row — reads as one
/// shelf sliding into place rather than a stack of things dropping in.
///
/// Its trigger is borrowed from the nearest ancestor [ScrollReveal]
/// (via the ambient [RevealPulse] it broadcasts) rather than computed
/// independently: a tile living inside a horizontal `ListView` nested
/// in a vertical page scroll has no reliable "in view" signal of its
/// own — it can scroll in and out sideways completely unrelated to
/// whether the page around it is even visible. Riding the section's
/// own trigger instead means the whole row moves as one piece with its
/// container — the section blurs into focus and rises, the shelf of
/// tiles cascades in from the right, together — including every time
/// the section is scrolled back into view again, since [ScrollReveal]
/// itself already replays on every pass, not just the first.
///
/// With no [RevealPulse] ancestor (used bare, outside any
/// [ScrollReveal]) it falls back to playing once on mount, same as
/// [Entrance].
class HorizontalReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  // Signed: a positive value settles in from the right (the usual case —
  // see the class doc), a negative value settles in from the left. Sign
  // is the only thing that matters here; [_curve]'s own t=0→1 sweep is
  // what actually drives the translation either way.
  final double slideBy;
  const HorizontalReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 640),
    this.slideBy = 34,
  });

  @override
  State<HorizontalReveal> createState() => _HorizontalRevealState();
}

class _HorizontalRevealState extends State<HorizontalReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  // The last RevealPulse generations reacted to — null until the
  // first didChangeDependencies for each.
  int? _seenPlay;
  int? _seenReset;
  Timer? _delayTimer;

  void _play() {
    _delayTimer?.cancel();
    _delayTimer = Timer(widget.delay, () {
      if (mounted) _c.forward(from: 0);
    });
  }

  // Snaps straight back to hidden, no animation, no delay — mirrors
  // exactly what the ancestor ScrollReveal does to itself the instant
  // it leaves view. Cancels any pending [_play] too, so a tile that's
  // mid-stagger-delay when the section scrolls away doesn't still pop
  // in a moment later while already hidden.
  void _resetNow() {
    _delayTimer?.cancel();
    _c.value = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pulse = RevealPulse.of(context);
    if (pulse == null) {
      // No ScrollReveal ancestor at all — behave like Entrance: play
      // once, right away.
      if (_seenPlay == null) {
        _seenPlay = -1;
        _play();
      }
      return;
    }

    if (_seenPlay == null) {
      _seenPlay = pulse.playGeneration;
      _seenReset = pulse.resetGeneration;
      // The ancestor may already be mid-reveal (or long past it) by
      // the time this tile first mounts — e.g. this row lazily
      // building its items a frame after the section itself settled.
      // Only replay for that case; generation 0 means the section
      // hasn't revealed yet at all, and its own first pulse will
      // reach this the normal way, below.
      if (pulse.playGeneration > 0) _play();
      return;
    }

    // Checked before play, and unconditionally — a reset can arrive on
    // its own (the section merely scrolled out, nothing to play yet)
    // or on the same beat as a fresh play trigger; either way this
    // tile needs to actually be hidden before that play's own delay
    // starts counting down.
    if (pulse.resetGeneration != _seenReset) {
      _seenReset = pulse.resetGeneration;
      _resetNow();
    }
    if (pulse.playGeneration != _seenPlay) {
      _seenPlay = pulse.playGeneration;
      _play();
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((1 - t) * widget.slideBy, 0),
            child: child,
          ),
        );
      },
    );
  }
}

/// Broadcasts "this tab just became the active one" down to every
/// [ScrollReveal] beneath it, so cards/sections that are already
/// sitting in view replay their settle-in on a tab switch instead of
/// just sitting there already fully revealed.
///
/// This exists because [IndexedStack] (as used by RootShell for the
/// bottom-nav tabs) keeps every tab mounted, laid out, and positioned
/// at all times — that's the whole point of it, so each tab keeps its
/// own scroll position and in-flight data across switches. But it also
/// means nothing about a tab's cards actually changes geometrically
/// when you switch to it — no remount, no position change — so
/// [ScrollReveal]'s normal scroll-position check has nothing to
/// trigger off. RootShell wraps each tab's screen in one of these;
/// nothing else needs to change per screen or per section —
/// [ScrollReveal] picks it up ambiently via [TabActivation.of].
class TabActivation extends InheritedWidget {
  final bool active;
  // Bumped by RootShell once per activation (false→true) — compared
  // against the last generation each ScrollReveal has seen, since a
  // rebuild that leaves `active: true` unchanged (some other bit of
  // state changing on the visible tab) shouldn't replay anything.
  final int generation;

  const TabActivation({
    super.key,
    required this.active,
    required this.generation,
    required super.child,
  });

  static TabActivation? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabActivation>();

  @override
  bool updateShouldNotify(TabActivation oldWidget) =>
      active != oldWidget.active || generation != oldWidget.generation;
}

class ScrollReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double riseBy;
  final double revealMargin;
  const ScrollReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 680),
    this.riseBy = 18,
    this.revealMargin = 80,
  });

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal> with SingleTickerProviderStateMixin {
  // Driven linearly (no curve on the controller itself) — [_riseCurve]
  // and [_focusCurve] below each apply their own easing over their own
  // slice of the timeline, so two differently-timed motions can share
  // one controller/one AnimationBuilder instead of needing two tickers.
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);

  // The fade + rise pass: finishes just over halfway through the
  // timeline, so the shape and position are fully settled before the
  // focus pass (below) spends the rest of the time sharpening it.
  static const _riseCurve = Interval(0.0, 0.62, curve: Curves.easeOutCubic);
  // The blur-to-sharp pass: starts while the rise is still finishing (a
  // hair of overlap reads as one continuous move rather than two stages
  // visibly handing off) and is the last thing to complete, so the very
  // last thing anyone perceives is the content snapping into focus.
  static const _focusCurve = Interval(0.32, 1.0, curve: Curves.easeOut);

  static const _maxBlur = 3.0;

  ScrollPosition? _position;
  // Whether this item is currently considered "in view" — drives both
  // the forward play (false → true) and the reset back to hidden
  // (true → false), so the same check works for scrolling in either
  // direction, any number of times.
  bool _revealed = false;
  bool _checkScheduled = false;
  // A cancelable delayed-forward, so an item that scrolls back out of
  // view again before its stagger [delay] even elapses doesn't still
  // pop in a moment later while already off-screen.
  Timer? _delayTimer;
  // The last [TabActivation.generation] this item has reacted to. Null
  // until the first didChangeDependencies — that first sighting is
  // just recorded, not replayed, since the item's own normal mount
  // reveal (below) already handles first appearance.
  int? _seenGeneration;
  // Bumped every time this section actually starts (or re-starts) its
  // forward play — broadcast to descendants as [RevealPulse.playGeneration]
  // so a [HorizontalReveal] row nested inside can ride the same
  // trigger instead of computing its own (unreliable, for a
  // horizontally-scrolling child) in-view check.
  int _playGeneration = 0;
  // Bumped every time this section snaps back to hidden — broadcast as
  // [RevealPulse.resetGeneration] so descendants snap back to hidden in
  // the same instant too, rather than sitting at their old fully-
  // revealed state until the next play eventually reaches them.
  int _resetGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-resolved on every dependency change (not just once in
    // initState) since the nearest Scrollable can legitimately change
    // out from under a widget — e.g. this same subtree getting reused
    // inside a different ancestor after a hot navigation. Cheap no-op
    // in the common case where it hasn't.
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_check);
      _position = position;
      _position?.addListener(_check);
    }

    final activation = TabActivation.of(context);
    if (activation != null) {
      if (_seenGeneration == null) {
        _seenGeneration = activation.generation;
      } else if (activation.active && activation.generation != _seenGeneration) {
        _seenGeneration = activation.generation;
        _scheduleReplay();
      }
    }

    _scheduleCheck();
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _delayTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    // A post-frame callback rather than checking inline — this widget's
    // own RenderBox has no size/position yet during build, only once
    // layout for this frame has actually completed.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      _check();
    });
  }

  // Null while this item's own box, or the nearest Scrollable's own
  // viewport box, isn't laid out yet — callers retry a frame later
  // rather than treating that as "not in view".
  bool? _computeInView() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    // The nearest Scrollable's own viewport box gives an accurate
    // visible region in global coordinates — e.g. Home's feed sits
    // above a bottom nav bar, so the screen's own full height would
    // overshoot how far down is actually visible. Falls back to the
    // screen height on the rare frame where that box isn't resolvable
    // yet (still reasonable, just slightly generous).
    final scrollableBox =
        _position != null ? Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox? : null;
    final viewportTop = (scrollableBox != null && scrollableBox.hasSize)
        ? scrollableBox.localToGlobal(Offset.zero).dy
        : 0.0;
    final viewportBottom = (scrollableBox != null && scrollableBox.hasSize)
        ? viewportTop + scrollableBox.size.height
        : MediaQuery.of(context).size.height;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;

    // In view (with a margin of lead/trail on both edges) whenever this
    // item overlaps the expanded viewport band — true for a fresh
    // reveal scrolling in from below *or* from above.
    return top < viewportBottom + widget.revealMargin && bottom > viewportTop - widget.revealMargin;
  }

  void _check() {
    if (!mounted) return;
    final inView = _computeInView();
    if (inView == null) {
      _scheduleCheck();
      return;
    }

    if (inView && !_revealed) {
      _revealed = true;
      _delayTimer?.cancel();
      _delayTimer = Timer(widget.delay, () {
        if (mounted && _revealed) {
          setState(() => _playGeneration++);
          _c.forward();
        }
      });
    } else if (!inView && _revealed) {
      _revealed = false;
      _delayTimer?.cancel();
      // Instant, not animated — by definition this only fires once the
      // item is well past the margin on either side, so it's already
      // off-screen and the reset is never actually seen. Still
      // broadcast via setState though — descendants (a nested
      // HorizontalReveal row) aren't off-screen themselves in the same
      // geometric sense a horizontally-scrolling child has no
      // reliable "off-screen" signal of its own, which is the whole
      // reason they ride this broadcast instead — so without this
      // they'd keep sitting at their last fully-revealed state.
      _c.value = 0;
      setState(() => _resetGeneration++);
    }
  }

  // Forces the settle-in to play again for an item that's already
  // revealed and sitting in view — used when this tab has just become
  // active again (see [TabActivation]), where geometry hasn't changed
  // at all so [_check] alone would never notice anything to do.
  void _scheduleReplay() {
    SchedulerBinding.instance.addPostFrameCallback((_) => _replay());
  }

  void _replay() {
    if (!mounted) return;
    final inView = _computeInView();
    if (inView == null) {
      // Layout not settled yet this frame — try again next frame
      // rather than silently dropping the replay.
      _scheduleReplay();
      return;
    }
    if (!inView) return; // off-screen on this tab — nothing to replay
    _delayTimer?.cancel();
    _revealed = true;
    _c.value = 0;
    // Snaps descendants back to hidden in this same beat too — without
    // this, a nested HorizontalReveal row would still show its old
    // fully-settled state for the whole gap between this replay
    // starting and its own delayed forward below actually landing.
    setState(() => _resetGeneration++);
    _delayTimer = Timer(widget.delay, () {
      if (mounted && _revealed) {
        setState(() => _playGeneration++);
        _c.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Also checked on every build, not just on scroll — covers content
    // whose position shifts without a scroll event firing (e.g. a
    // skeleton above it collapsing once real data loads in).
    _scheduleCheck();
    return RevealPulse(
      playGeneration: _playGeneration,
      resetGeneration: _resetGeneration,
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final rise = _riseCurve.transform(_c.value).clamp(0.0, 1.0);
          final focus = _focusCurve.transform(_c.value).clamp(0.0, 1.0);

          // Blur-to-sharp: kept mounted for the widget's whole lifetime
          // (sigma just animates down to exactly 0) rather than being
          // removed from the tree once it finishes — swapping the filter
          // in/out at the tail end changes render-tree topology right at
          // the moment content settles, which showed up as a one-frame
          // twitch. Sigma 0 is visually a no-op and cheap enough to leave
          // mounted.
          final result = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: _maxBlur * (1 - focus),
              sigmaY: _maxBlur * (1 - focus),
              tileMode: TileMode.decal,
            ),
            child: child!,
          );

          return Opacity(
            opacity: rise,
            child: Transform.translate(
              offset: Offset(0, (1 - rise) * widget.riseBy),
              child: result,
            ),
          );
        },
      ),
    );
  }
}

/// Wraps [child] with a soft press-down/spring-back scale and forwards
/// [onTap] — a drop-in replacement for a bare `GestureDetector(onTap: ...)`
/// wherever a tap should feel acknowledged rather than just registered.
/// Scale is deliberately subtle (down to [scaleTo], default 0.96) so it
/// reads as tactile feedback, not a "bouncy button" effect.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleTo;
  // Opt-in, not on by default: PressScale wraps nearly every tappable
  // surface in the app, including dense grids/rows where a click on
  // every single tap would turn into buzzing noise rather than a nice
  // touch. Reserved for the handful of deliberate, one-at-a-time taps
  // (a header action, a toggle) where a tick actually reads as premium.
  final bool haptics;
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleTo = 0.96,
    this.haptics = false,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: widget.scaleTo)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut, reverseCurve: Curves.easeOutBack));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null
          ? null
          : (_) {
              if (widget.haptics) HapticFeedback.selectionClick();
              _c.forward();
            },
      onTapUp: widget.onTap == null ? null : (_) => _c.reverse(),
      onTapCancel: widget.onTap == null ? null : () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        child: widget.child,
        builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
      ),
    );
  }
}

/// Counts up from 0 to [value] once, the first time it's built — for a
/// rating or stat number that should feel like it's tallying up rather
/// than just appearing. Renders with the same [style] and [decimals] the
/// static text would have used; a drop-in replacement for a plain `Text`
/// wherever a number is the whole point of the moment.
class CountUpNumber extends StatefulWidget {
  final double value;
  final int decimals;
  final TextStyle? style;
  final Duration duration;
  final String suffix;
  const CountUpNumber({
    super.key,
    required this.value,
    this.decimals = 1,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.suffix = '',
  });

  @override
  State<CountUpNumber> createState() => _CountUpNumberState();
}

class _CountUpNumberState extends State<CountUpNumber> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _tween =
      Tween(begin: 0.0, end: widget.value).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _c.forward());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tween,
      builder: (context, _) =>
          Text('${_tween.value.toStringAsFixed(widget.decimals)}${widget.suffix}', style: widget.style),
    );
  }
}

/// A very slow, very small looping pulse — opacity and scale both
/// breathing between [minScale]..1.0 over [period]. Meant for a glow or
/// an icon that should feel quietly alive rather than static.
///
/// Defaults are calm on purpose: small amplitude, slow period. This is
/// meant to sit at the edge of noticing, not something someone's eye
/// tracks — a visible "pulse" on an icon, especially near the top of the
/// screen where it sits in peripheral vision the whole time someone's
/// reading, reads as distracting rather than alive, and can be
/// uncomfortable for motion-sensitive people. When pairing with
/// [BreathingGlow] on the same element, prefer leaning on the glow for
/// the "alive" read and keeping this one (if used at all) barely there.
class Breathe extends StatefulWidget {
  final Widget child;
  final Duration period;
  final double minScale;
  final double minOpacity;
  const Breathe({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 5200),
    this.minScale = 0.97,
    this.minOpacity = 0.88,
  });

  @override
  State<Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<Breathe> with SingleTickerProviderStateMixin {
  // repeat() (not repeat(reverse: true)) driving a hand-rolled sine wave
  // below, rather than an eased 0→1 tween bounced back and forth. A
  // bounced tween's velocity hits exactly zero at both ends every cycle —
  // technically smooth, but it reads as a held pause-and-snap at each
  // extreme rather than one continuous motion. A genuine sine keeps
  // moving through the whole loop the way an actual breath does, with no
  // seam where the two curves are stitched back to back.
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // 0 → 1 → 0 continuously, easing in/out of both the trough and
        // the peak the way an actual inhale/exhale does.
        final v = (1 - math.cos(_c.value * 2 * math.pi)) / 2;
        return Opacity(
          opacity: widget.minOpacity + (1 - widget.minOpacity) * v,
          child: Transform.scale(scale: widget.minScale + (1 - widget.minScale) * v, child: child),
        );
      },
    );
  }
}

/// A soft blurred halo breathing behind [child] — much more legible as
/// "alive" at a glance than [Breathe]'s own scale/opacity pulse on the
/// icon alone, since a glow reads clearly even at a size where a few
/// percent of icon scale barely registers. Same continuous sine timing
/// as [Breathe] (and can share its [period] to stay in lockstep with a
/// [Breathe] wrapping the same icon). [child] itself is not resized —
/// only the glow around it breathes — so it pairs cleanly with a
/// [Breathe] on the icon without the two motions fighting each other.
///
/// Defaults are deliberately calm: a slow period and a small size/opacity
/// swing. This is meant to sit at the very edge of noticing — something
/// that would look static in a screenshot but reads as quietly alive in
/// motion — not a pulse someone tracks with their eye. If in doubt, go
/// slower and smaller rather than faster and bigger; a glow that's too
/// present in peripheral vision reads as distracting (or, for motion-
/// sensitive people, uncomfortable) rather than premium.
class BreathingGlow extends StatefulWidget {
  final Widget child;
  final Color color;
  final double size;
  final Duration period;
  final double minSize;
  final double maxOpacity;
  const BreathingGlow({
    super.key,
    required this.child,
    required this.color,
    this.size = 46,
    this.period = const Duration(milliseconds: 5200),
    this.minSize = 0.88,
    this.maxOpacity = 0.22,
  });

  @override
  State<BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<BreathingGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = (1 - math.cos(_c.value * 2 * math.pi)) / 2;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            IgnorePointer(
              child: Opacity(
                opacity: widget.maxOpacity * (0.4 + 0.6 * v),
                child: Container(
                  width: widget.size * (widget.minSize + (1 - widget.minSize) * v),
                  height: widget.size * (widget.minSize + (1 - widget.minSize) * v),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [widget.color.withOpacity(0.9), widget.color.withOpacity(0.0)],
                    ),
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    );
  }
}

/// A soft, warm-toned shimmer placeholder for skeleton loading states —
/// a rounded block with a diagonal highlight sweeping across it on a
/// slow, continuous loop. Deliberately tuned to Seenly's own paper
/// palette rather than the stark grey most apps default to, so a
/// loading screen already looks like *this* app mid-thought instead of
/// a generic placeholder borrowed from somewhere else.
class ShimmerBlock extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final Color baseColor;
  final Color highlightColor;
  const ShimmerBlock({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.baseColor = const Color(0xFFE9DBBF), // SeenlyPalette.cork
    this.highlightColor = const Color(0xFFFFFDF8), // SeenlyPalette.paper
  });

  @override
  State<ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<ShimmerBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Sweeps the highlight from well past the left edge to well
          // past the right, so it always enters and exits soft instead
          // of popping in/out at the block's own boundary.
          final t = Curves.easeInOut.transform(_c.value);
          final dx = -1.6 + 3.2 * t;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              gradient: LinearGradient(
                begin: Alignment(dx - 0.7, -0.3),
                end: Alignment(dx + 0.7, 0.3),
                colors: [widget.baseColor, widget.highlightColor, widget.baseColor],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A drop-in `Image.network` replacement that fades the decoded image in
/// over [placeholder] once its first frame is ready, instead of the
/// default hard pop the instant bytes finish downloading. On a feed made
/// almost entirely of posters/thumbnails, this one change is worth more
/// to the overall feel of "smooth" than most of the motion elsewhere in
/// this file — a wall of images popping in one by one, out of sync with
/// each other, reads as janky no matter how nice the surrounding motion
/// is. [placeholder] should be sized to exactly match the eventual
/// image (a solid fallback fill works well) so there's no layout jump.
class FadeInNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Widget placeholder;
  final Duration duration;
  final Alignment alignment;
  const FadeInNetworkImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.duration = const Duration(milliseconds: 280),
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, __, ___) => placeholder,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        // Already in the cache (common on a re-scroll or a revisit) —
        // show it immediately rather than replaying a fade for an image
        // that was never actually missing.
        if (wasSynchronouslyLoaded) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (frame == null) placeholder,
            AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: duration,
              curve: Curves.easeOut,
              child: child,
            ),
          ],
        );
      },
    );
  }
}
