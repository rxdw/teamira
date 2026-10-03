import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_translations.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'tane_thinking.dart' show paintSparkle;
import 'together_motion.dart' show HeartsBurst;
import 'wow_motion.dart' show FadeInNetworkImage;

/// The moment after something is saved — a title logged in the diary, or
/// put on the plan — played over whatever screen is showing.
///
/// It is the same family as Ask tanè's hand-off: a soft halo, a ring that
/// spreads, four-point sparkles, hearts when it's a shared evening. The
/// poster is set down like a keepsake and then *stamped*: a logged title
/// gets a round stamp that punches in and draws its own tick; a planned
/// one gets a bookmark ribbon that drops from the top of the poster and,
/// when there is one, the evening's date underneath.
///
/// It never blocks anything: the whole thing ignores touches, lives in the
/// root overlay (so it carries on across the screen that just closed) and
/// removes itself. Starting another one replaces the one still playing.
enum SavedKind { logged, planned }

class _ActiveCelebration {
  final OverlayEntry entry;
  final Completer<void> done;
  bool removed = false;

  _ActiveCelebration(this.entry, this.done);

  void finish() {
    if (!removed) {
      removed = true;
      entry.remove();
    }
    if (!done.isCompleted) done.complete();
  }
}

_ActiveCelebration? _active;

/// Plays the celebration and returns when it has finished (callers rarely
/// need to wait — it's fine to fire and forget, including right before
/// popping the current screen).
///
///  * [partnerName] set → a *shared* evening (hearts, "together", and the
///    person's name); [together] alone does the same without a name — for
///    a circle of several;
///  * [whenLabel] → for [SavedKind.planned], the date/time chip, e.g.
///    "sat · 19:00";
///  * [rating] → for [SavedKind.logged], the hearts given (1–10);
///  * [compact] → a shorter run, for places that already had a ceremony
///    of their own just before;
///  * [haptics] → one firm tap at the moment of the stamp.
Future<void> showSavedCelebration(
  BuildContext context, {
  required SavedKind kind,
  required String title,
  String? posterUrl,
  String mediaType = 'movie',
  String? partnerName,
  bool? together,
  String? whenLabel,
  int? rating,
  bool compact = false,
  bool haptics = true,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future<void>.value();

  _active?.finish();
  final done = Completer<void>();
  late final _ActiveCelebration active;
  final entry = OverlayEntry(
    builder: (_) => _SavedCelebration(
      kind: kind,
      title: title,
      posterUrl: posterUrl,
      mediaType: mediaType,
      partnerName: partnerName,
      together: together ?? partnerName != null,
      whenLabel: whenLabel,
      rating: rating,
      compact: compact,
      haptics: haptics,
      onDone: () {
        active.finish();
        if (identical(_active, active)) _active = null;
      },
    ),
  );
  active = _ActiveCelebration(entry, done);
  _active = active;
  overlay.insert(entry);
  return done.future;
}

class _SavedCelebration extends StatefulWidget {
  final SavedKind kind;
  final String title;
  final String? posterUrl;
  final String mediaType;
  final String? partnerName;
  final bool together;
  final String? whenLabel;
  final int? rating;
  final bool compact;
  final bool haptics;
  final VoidCallback onDone;

  const _SavedCelebration({
    required this.kind,
    required this.title,
    required this.posterUrl,
    required this.mediaType,
    required this.partnerName,
    required this.together,
    required this.whenLabel,
    required this.rating,
    required this.compact,
    required this.haptics,
    required this.onDone,
  });

  @override
  State<_SavedCelebration> createState() => _SavedCelebrationState();
}

class _SavedCelebrationState extends State<_SavedCelebration> with SingleTickerProviderStateMixin {
  static const _posterW = 156.0;
  static const _posterH = 234.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.compact ? 2300 : 3000),
  );
  Timer? _hapticTimer;

  bool get _together => widget.together;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
    if (widget.haptics) {
      // On the stamp: 30 % of the way in.
      _hapticTimer = Timer(
        Duration(milliseconds: (_c.duration!.inMilliseconds * 0.30).round()),
        HapticFeedback.mediumImpact,
      );
    }
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  IconData _typeIcon(String mediaType) {
    switch (mediaType) {
      case 'series':
        return Icons.live_tv_outlined;
      case 'anime':
        return Icons.auto_awesome_outlined;
      case 'manga':
        return Icons.import_contacts_outlined;
      case 'book':
        return Icons.menu_book_outlined;
      case 'game':
        return Icons.sports_esports_outlined;
      default:
        return Icons.local_movies_outlined;
    }
  }

  String get _headline {
    if (widget.kind == SavedKind.logged) {
      return _together ? 'logged together'.tr : 'in your diary'.tr;
    }
    return _together ? 'planned together'.tr : 'on your list'.tr;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            double seg(double a, double b, [Curve curve = Curves.linear]) =>
                curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0).toDouble());

            final scrim = seg(0, 0.10) * (1 - seg(0.88, 1.0));
            final exit = seg(0.86, 1.0, Curves.easeIn);
            final enterOpacity = seg(0.04, 0.16);
            final enter = seg(0.04, 0.30, Curves.easeOutBack);
            final stamp = seg(0.30, 0.46);
            final caption = seg(0.44, 0.64, Curves.easeOutCubic);
            // A very slow drift while it holds, so it never sits dead still.
            final float = reduceMotion ? 0.0 : math.sin(t * math.pi * 3) * 3;

            final poster = _poster(enter, enterOpacity, reduceMotion);
            final group = SizedBox(
              width: _posterW,
              height: _posterH,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // The halo behind the poster.
                  Positioned(
                    left: -80,
                    right: -80,
                    top: -80,
                    bottom: -80,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            SeenlyPalette.accent.withOpacity(0.36 * enterOpacity * (1 - exit)),
                            SeenlyPalette.accent.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  poster,
                  if (!reduceMotion)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BurstPainter(
                          t: seg(0.30, 0.92),
                          planned: widget.kind == SavedKind.planned,
                          posterSize: const Size(_posterW, _posterH),
                        ),
                      ),
                    ),
                  if (widget.kind == SavedKind.logged)
                    Positioned(
                      right: -14,
                      bottom: -14,
                      child: _stamp(stamp, seg(0.36, 0.52), reduceMotion),
                    )
                  else
                    Positioned(
                      right: 16,
                      top: -8,
                      child: _ribbon(stamp, reduceMotion),
                    ),
                ],
              ),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: SeenlyPalette.ink.withOpacity(0.42 * scrim)),
                if (!reduceMotion)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RaysPainter(
                        t: t,
                        strength: seg(0.28, 0.5) * (1 - exit),
                        color: SeenlyPalette.mustard,
                      ),
                    ),
                  ),
                Center(
                  child: Transform.translate(
                    offset: Offset(0, -28 - 14 * exit + float),
                    child: Opacity(
                      opacity: (1 - exit).clamp(0.0, 1.0).toDouble(),
                      child: Transform.scale(
                        scale: 1 - 0.04 * exit,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // A shared evening opens with a small shower of
                            // hearts around the poster.
                            if (_together && !reduceMotion)
                              HeartsBurst(
                                delay: Duration(milliseconds: (_c.duration!.inMilliseconds * 0.3).round()),
                                reach: 0.9,
                                child: group,
                              )
                            else
                              group,
                            const SizedBox(height: 30),
                            _captionBlock(caption),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _poster(double enter, double opacity, bool reduceMotion) {
    final color = SeenlyPalette.mediaColor(widget.mediaType);
    final placeholder = Container(
      color: color,
      alignment: Alignment.center,
      child: Icon(_typeIcon(widget.mediaType), size: 52, color: SeenlyPalette.paper.withOpacity(0.7)),
    );
    final card = Container(
      width: _posterW,
      height: _posterH,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.paper, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.34), blurRadius: 34, offset: const Offset(0, 16)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.posterUrl != null && widget.posterUrl!.isNotEmpty
          ? FadeInNetworkImage(url: widget.posterUrl!, placeholder: placeholder)
          : placeholder,
    );
    if (reduceMotion) return Opacity(opacity: opacity, child: card);
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: (1 - enter) * -0.07,
        child: Transform.scale(scale: 0.78 + 0.22 * enter, child: card),
      ),
    );
  }

  /// The round "logged" stamp: punches down from large with a small
  /// overshoot, and draws its own tick.
  Widget _stamp(double p, double tickProgress, bool reduceMotion) {
    if (p <= 0) return const SizedBox.shrink();
    final scale = reduceMotion
        ? 1.0
        : (p < 0.55
            ? 2.2 - 1.28 * Curves.easeIn.transform(p / 0.55)
            : 0.92 + 0.08 * Curves.easeOutBack.transform((p - 0.55) / 0.45));
    return Opacity(
      opacity: math.min(1.0, p * 4),
      child: Transform.rotate(
        angle: -0.2 + 0.1 * p,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: SeenlyPalette.accent,
              shape: BoxShape.circle,
              border: Border.all(color: SeenlyPalette.paper, width: 3),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: CustomPaint(
              painter: _TickPainter(progress: reduceMotion ? 1 : tickProgress, color: SeenlyPalette.accentOnAccent),
            ),
          ),
        ),
      ),
    );
  }

  /// The bookmark ribbon for a planned title: drops from above the poster's
  /// top edge and settles with a little bounce.
  Widget _ribbon(double p, bool reduceMotion) {
    if (p <= 0) return const SizedBox.shrink();
    final drop = reduceMotion ? 1.0 : Curves.easeOutBack.transform(p);
    return Opacity(
      opacity: math.min(1.0, p * 5),
      child: Transform.translate(
        offset: Offset(0, -64 * (1 - drop)),
        child: SizedBox(
          width: 38,
          height: 62,
          child: CustomPaint(
            painter: _RibbonPainter(color: SeenlyPalette.accent),
            child: Align(
              alignment: const Alignment(0, -0.35),
              child: Icon(Icons.bookmark_added_rounded, size: 19, color: SeenlyPalette.accentOnAccent),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SeenlyPalette.paper.withOpacity(0.32)),
        ),
        child: child,
      );

  Widget _dateChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: SeenlyPalette.mustard.withOpacity(0.24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SeenlyPalette.mustard.withOpacity(0.6), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_rounded, size: 15, color: SeenlyPalette.mustard),
            const SizedBox(width: 7),
            Text(
              label,
              style: SeenlyText.serif(italic: true, size: 14.5, weight: FontWeight.w600, color: SeenlyPalette.paper),
            ),
          ],
        ),
      );

  Widget _captionBlock(double p) {
    final pills = <Widget>[
      if (widget.kind == SavedKind.logged && widget.rating != null)
        _pill(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, size: 12, color: SeenlyPalette.pink),
            const SizedBox(width: 5),
            Text('${widget.rating}',
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper, weight: FontWeight.w600)),
          ],
        )),
      if (widget.partnerName != null)
        _pill(Text(
          '${'with'.tr} ${widget.partnerName}',
          style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper, weight: FontWeight.w600),
        )),
    ];
    final plannedDate = widget.kind == SavedKind.planned && widget.whenLabel != null
        ? widget.whenLabel!
        : null;
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - p)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _headline,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 24, weight: FontWeight.w600, color: SeenlyPalette.paper),
              ),
              const SizedBox(height: 8),
              // The actual answer to "what did I just save" — bumped up
              // from a small dim mono caption to the same serif-italic
              // family the poster titles use everywhere else in the app
              // (see _FeedTile), so it reads at a glance instead of
              // disappearing under the headline.
              Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 17, weight: FontWeight.w600, color: SeenlyPalette.paper),
              ),
              if (plannedDate != null) ...[
                const SizedBox(height: 12),
                _dateChip(plannedDate),
              ],
              if (pills.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: pills,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tick that draws itself: [progress] is how much of the stroke is laid
/// down so far.
class _TickPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _TickPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.27, size.height * 0.53)
      ..lineTo(size.width * 0.43, size.height * 0.69)
      ..lineTo(size.width * 0.74, size.height * 0.34);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = size.width * 0.085
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TickPainter old) => old.progress != progress || old.color != color;
}

/// A bookmark: a rounded strip with a V cut into its lower edge.
class _RibbonPainter extends CustomPainter {
  final Color color;

  const _RibbonPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w / 2, h - 13)
      ..lineTo(0, h)
      ..close();
    canvas.drawShadow(path, Colors.black.withOpacity(0.5), 5, false);
    canvas.drawPath(path, Paint()..color = color);
    // A thin lighter edge down the left, like a fold catching the light.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w * 0.12, h - 6),
      Paint()..color = Colors.white.withOpacity(0.14),
    );
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter old) => old.color != color;
}

/// Soft rays fanning out behind the poster, turning very slowly.
class _RaysPainter extends CustomPainter {
  final double t;
  final double strength; // 0..1
  final Color color;

  const _RaysPainter({required this.t, required this.strength, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    final centre = Offset(size.width / 2, size.height / 2 - 28);
    final reach = size.longestSide * 0.7;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.30 * strength), color.withOpacity(0)],
      ).createShader(Rect.fromCircle(center: centre, radius: reach));
    const rays = 12;
    final spin = t * 0.6;
    for (int i = 0; i < rays; i++) {
      final a = i / rays * 2 * math.pi + spin;
      const half = 0.075;
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy)
          ..lineTo(centre.dx + math.cos(a - half) * reach, centre.dy + math.sin(a - half) * reach)
          ..lineTo(centre.dx + math.cos(a + half) * reach, centre.dy + math.sin(a + half) * reach)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.t != t || old.strength != strength;
}

/// The impact at the stamp (or the ribbon's landing): a ring spreading out
/// and a shower of sparkles. [planned] makes it calmer — fewer, smaller,
/// no white — because a plan is a promise rather than a finish.
class _BurstPainter extends CustomPainter {
  final double t; // 0..1
  final bool planned;
  final Size posterSize;

  const _BurstPainter({required this.t, required this.planned, required this.posterSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    // The impact happens at the stamp (bottom right) or the ribbon (top
    // right).
    final origin = planned
        ? Offset(posterSize.width - 16 - 19, 20)
        : Offset(posterSize.width - 8, posterSize.height - 8);

    final ringP = Curves.easeOutCubic.transform((t / 0.7).clamp(0.0, 1.0).toDouble());
    if (t < 0.7) {
      canvas.drawCircle(
        origin,
        30 + 120 * ringP,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 * (1 - ringP) + 0.5
          ..color = SeenlyPalette.accent.withOpacity(0.55 * (1 - ringP)),
      );
    }

    final count = planned ? 9 : 16;
    for (int i = 0; i < count; i++) {
      final delay = ((i * 7) % 5) * 0.035;
      final local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0).toDouble();
      if (local <= 0) continue;
      final angle = i / count * 2 * math.pi + (planned ? 0.5 : 0.2);
      final speed = 0.65 + 0.35 * (((i * 5) % 4) / 3);
      final travel = Curves.easeOutCubic.transform(local) * (planned ? 78 : 118) * speed;
      final life = math.sin(math.pi * local);
      final pos = origin + Offset(math.cos(angle) * travel, math.sin(angle) * travel * 0.9 - 14 * local);
      final color = switch (i % 3) {
        0 => SeenlyPalette.accent,
        1 => SeenlyPalette.mustard,
        _ => planned ? SeenlyPalette.mustard : SeenlyPalette.paper,
      };
      paintSparkle(
        canvas,
        pos,
        (planned ? 3.4 : 4.2 + (i % 3) * 1.8) * (0.4 + 0.6 * life),
        Paint()..color = color.withOpacity(0.95 * life),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}
