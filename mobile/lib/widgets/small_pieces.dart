import 'package:flutter/material.dart';

import '../services/app_translations.dart';
import '../theme/clay_kit.dart';
import '../theme/notebook_paper.dart';
import '../theme/palette.dart';
import '../theme/seenly_skin.dart';
import '../theme/text_styles.dart';
import '../widgets/decide_motion.dart' show BouncingDots;
import '../widgets/soft_motion.dart';
import '../widgets/wow_motion.dart' show PressScale;

/// Shared timing for every underline-tab switch in the app (Profile,
/// friend profile, co-viewing, Collections, Sources, Search's media
/// filter) so they all feel like the same soft, unhurried motion
/// rather than each screen picking its own pace.
const kTabTransitionDuration = Duration(milliseconds: 380);
const kTabTextDuration = Duration(milliseconds: 260);
const kTabLeadCurve = Curves.easeOutCubic;
const kTabLagCurve = Curves.easeInCubic;

/// A dashed-border box — the app's consistent visual for "not yet": queued
/// items, an empty add-collection slot, a not-started game.
class DashedBox extends StatelessWidget {
  final Widget child;
  final double radius;
  Color get color => _color ?? SeenlyPalette.dashedBorder;
  final Color? _color;

  DashedBox({
    super.key,
    required this.child,
    this.radius = 10,
    Color? color,
  }) : _color = color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(radius: radius, color: color),
      child: Padding(padding: const EdgeInsets.all(1.5), child: child),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final double radius;
  final Color color;
  const _DashedRRectPainter({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const dashWidth = 5.0;
    const gapWidth = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// One media-type tile — an icon dot in that type's categorical color, a
/// count, and a label. Used for the Profile "your shelf" grid and the
/// Wrapped breakdown. When [soon] is true (anime/books/manga — tracked in
/// the data model already, just not hooked up to a source yet) it shows a
/// dashed outline and "soon" instead of a bare zero, so the empty state
/// reads as a promise rather than a bug.
class MediaCountTile extends StatelessWidget {
  final Color color;
  final int count;
  final String label;

  const MediaCountTile({
    super.key,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (SeenlySkin.isClay) {
      return ClaySurface(
        radius: 26,
        elevation: 0.6,
        color: Color.alphaBlend(color.withOpacity(0.24), SeenlyPalette.paper),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$count', style: SeenlyText.serif(size: 22, weight: FontWeight.w900, color: ClayTones.shadeOf(color, 0.12))),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(0.09), SeenlyPalette.paper),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.28), width: 1.2),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: SeenlyText.serif(size: 21, color: color)),
          const SizedBox(height: 5),
          Text(label,
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
        ],
      ),
    );
  }
}


class PillChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final bool dashed;
  final bool fullWidth;

  const PillChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
    this.dashed = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    if (SeenlySkin.isClay) {
      return ClayChip(label: label, active: active, onTap: onTap, fullWidth: fullWidth);
    }
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: fullWidth ? double.infinity : null,
      alignment: fullWidth ? Alignment.center : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? SeenlyPalette.accent : SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        border: active || dashed
            ? Border.all(
                color: active ? SeenlyPalette.accent : SeenlyPalette.dashedBorder,
              )
            : null,
      ),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 220),
        style: SeenlyText.mono(
          size: 11,
          color: active ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted,
        ),
        child: Text(
          label,
          textAlign: fullWidth ? TextAlign.center : null,
          overflow: fullWidth ? TextOverflow.ellipsis : null,
        ),
      ),
    );
    return PressScale(onTap: onTap, child: child);
  }
}

/// The one primary call-to-action style used everywhere: a full-width
/// (or inline) pill in the accent color with italic serif label. Eases
/// down a couple percent in scale on press and springs back on release
/// — a small, soft bit of tactile feedback so tapping the app's one
/// recurring action never feels inert.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool expand;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
    this.expand = true,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (SeenlySkin.isClay) {
      return ClayButton(
        label: widget.label,
        onTap: widget.onTap,
        loading: widget.loading,
        expand: widget.expand,
      );
    }
    final button = Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 24),
      decoration: BoxDecoration(
        color: SeenlyPalette.accent,
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      // Waiting isn't a spinner: three dots hop along while the label
      // steps aside for them (and comes back when it's done).
      child: SoftSwap(
        alignment: Alignment.center,
        duration: const Duration(milliseconds: 220),
        child: widget.loading
            ? SizedBox(
                key: const ValueKey<String>('loading'),
                height: 18,
                child: Center(child: BouncingDots(color: SeenlyPalette.accentOnAccent)),
              )
            : Text(
                widget.label,
                key: ValueKey<String>('label:${widget.label}'),
                style: SeenlyText.serif(
                    italic: true, size: 14, color: SeenlyPalette.accentOnAccent),
              ),
      ),
    );

    final tappable = GestureDetector(
      onTap: widget.loading ? null : widget.onTap,
      onTapDown: widget.loading || widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.loading || widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.loading || widget.onTap == null ? null : () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: button,
      ),
    );
    return widget.expand ? SizedBox(width: double.infinity, child: tappable) : tappable;
  }
}

/// Shared body for an evenly-split row of underline tabs. Used by both
/// [UnderlineTabRow] and (whenever its labels all fit unscrolled)
/// [ScrollableUnderlineTabs] — the caller owns the surrounding
/// baseline border, this just lays out the tabs and the indicator.
///
/// The accent underline doesn't just glide at a constant width —
/// its leading edge (the direction it's heading) eases out quickly
/// while its trailing edge eases in and lags behind, so the bar
/// stretches like a soft rubber band mid-transition and then settles
/// back to a normal tab-width underline once it arrives. Label color
/// crossfades on the same clock instead of switching instantly.
class _EqualWidthUnderlineTabs extends StatefulWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final TextStyle Function(bool active)? labelStyleBuilder;
  const _EqualWidthUnderlineTabs({
    required this.labels,
    required this.activeIndex,
    required this.onChanged,
    this.labelStyleBuilder,
  });

  @override
  State<_EqualWidthUnderlineTabs> createState() => _EqualWidthUnderlineTabsState();
}

class _EqualWidthUnderlineTabsState extends State<_EqualWidthUnderlineTabs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _fromIndex;
  late int _toIndex;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.activeIndex;
    _toIndex = widget.activeIndex;
    _controller = AnimationController(vsync: this, duration: kTabTransitionDuration, value: 1);
  }

  @override
  void didUpdateWidget(covariant _EqualWidthUnderlineTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndex != _toIndex) {
      _fromIndex = _toIndex;
      _toIndex = widget.activeIndex;
      _controller
        ..stop()
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder wraps the whole Stack (rather than just the
    // indicator) so the indicator ends up a direct child of Stack —
    // nesting it one level deeper (e.g. inside Positioned.fill +
    // LayoutBuilder) means Flutter can't attach its StackParentData
    // at all, and it silently renders as a full-bleed box instead of a
    // positioned line.
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = constraints.maxWidth / widget.labels.length;
        final fromLeft = tabWidth * _fromIndex;
        final toLeft = tabWidth * _toIndex;
        final movingForward = toLeft >= fromLeft;
        return Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < widget.labels.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onChanged(i),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: kTabTextDuration,
                            curve: Curves.easeOutCubic,
                            style: widget.labelStyleBuilder != null
                                ? widget.labelStyleBuilder!(widget.activeIndex == i)
                                : SeenlyText.serif(
                                    italic: true,
                                    size: 14,
                                    color: widget.activeIndex == i
                                        ? SeenlyPalette.ink
                                        : SeenlyPalette.placeholder,
                                  ),
                            child: Text(widget.labels[i]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final lead = kTabLeadCurve.transform(_controller.value);
                final lag = kTabLagCurve.transform(_controller.value);
                // Whichever edge is heading toward the new tab eases
                // out fast (lead); the edge it's pulling away from
                // eases in slowly and catches up last (lag) — that gap
                // between the two curves is what reads as "stretch".
                final left = movingForward
                    ? fromLeft + (toLeft - fromLeft) * lag
                    : fromLeft + (toLeft - fromLeft) * lead;
                final right = movingForward
                    ? (fromLeft + tabWidth) + (toLeft - fromLeft) * lead
                    : (fromLeft + tabWidth) + (toLeft - fromLeft) * lag;
                return Positioned(
                  left: left,
                  bottom: SeenlySkin.isCozy ? -3 : 0,
                  width: right - left,
                  height: SeenlySkin.isCozy ? 8 : 2,
                  child: HandDrawnLine(color: SeenlyPalette.accent, thickness: 2.2),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Full-width underline tab bar — same visual as Profile's "watched / plan
/// to watch" switch: labels share the width evenly, a thin baseline runs
/// under the whole row, and the active tab gets a 2px accent underline.
/// Use this instead of [PillChip] for a top-level view toggle that should
/// read as a primary navigation choice rather than a filter.
/// Same visual language as [UnderlineTabRow] — italic serif label, 2px
/// accent underline on the active one, faded placeholder color
/// otherwise, thin baseline under the whole row — but scrollable and
/// sized to content instead of split evenly across a fixed width. Use
/// this for a filter row with more labels than a top-level 2-3 way
/// toggle (Collections' media-type filter, for one), while still
/// reading as "the same kind of tab", not a chip/pill filter.
class ScrollableUnderlineTabs extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final TextStyle Function(bool active)? labelStyleBuilder;
  const ScrollableUnderlineTabs({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onChanged,
    this.labelStyleBuilder,
  });

  static const _itemGap = 20.0;
  static const _edgePadding = 22.0;

  @override
  Widget build(BuildContext context) {
    if (SeenlySkin.isClay) {
      return ClayTabBar(
        labels: labels,
        activeIndex: activeIndex,
        onChanged: onChanged,
        allowScroll: true,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: SeenlyPalette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A short list (e.g. just "all" + one picked category) used to
          // sit packed on the left with the rest of the bar empty. Measure
          // whether the labels actually need scrolling first; only fall
          // back to the scrollable, left-packed layout when they don't fit.
          final style = labelStyleBuilder != null
              ? labelStyleBuilder!(false)
              : SeenlyText.serif(italic: true, size: 14);
          final widths = <double>[
            for (final label in labels)
              (TextPainter(
                text: TextSpan(text: label, style: style),
                textDirection: TextDirection.ltr,
              )..layout())
                  .width,
          ];
          var contentWidth = _edgePadding * 2;
          for (var i = 0; i < widths.length; i++) {
            contentWidth += widths[i];
            if (i != widths.length - 1) contentWidth += _itemGap;
          }

          if (contentWidth <= constraints.maxWidth) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: _edgePadding),
              child: _EqualWidthUnderlineTabs(
                labels: labels,
                activeIndex: activeIndex,
                onChanged: onChanged,
                labelStyleBuilder: labelStyleBuilder,
              ),
            );
          }

          // Content-sized and scrollable, so a sliding indicator has no
          // fixed geometry to glide across — instead each tab's own
          // underline grows out from the center as it becomes active
          // (and shrinks back to nothing as it stops being active),
          // fading in step, rather than snapping to a fixed-width bar
          // or sliding at a constant size.
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _edgePadding),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  GestureDetector(
                    onTap: () => onChanged(i),
                    child: Container(
                      margin: EdgeInsets.only(right: i == labels.length - 1 ? 0 : _itemGap),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: AnimatedDefaultTextStyle(
                              duration: kTabTextDuration,
                              curve: Curves.easeOutCubic,
                              style: labelStyleBuilder != null
                                  ? labelStyleBuilder!(activeIndex == i)
                                  : SeenlyText.serif(
                                      italic: true,
                                      size: 14,
                                      color: activeIndex == i
                                          ? SeenlyPalette.ink
                                          : SeenlyPalette.placeholder,
                                    ),
                              child: Text(labels[i]),
                            ),
                          ),
                          AnimatedContainer(
                            duration: kTabTransitionDuration,
                            curve: kTabLeadCurve,
                            width: activeIndex == i ? widths[i] : 0,
                            height: SeenlySkin.isCozy ? 8 : 2,
                            child: HandDrawnLine(color: SeenlyPalette.accent, thickness: 2.2),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class UnderlineTabRow extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final TextStyle Function(bool active)? labelStyleBuilder;
  const UnderlineTabRow({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onChanged,
    this.labelStyleBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (SeenlySkin.isClay) {
      return ClayTabBar(
        labels: labels,
        activeIndex: activeIndex,
        onChanged: onChanged,
        margin: const EdgeInsets.symmetric(vertical: 4),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: SeenlyPalette.border)),
      ),
      child: _EqualWidthUnderlineTabs(
        labels: labels,
        activeIndex: activeIndex,
        onChanged: onChanged,
        labelStyleBuilder: labelStyleBuilder,
      ),
    );
  }
}

/// One row of a movie-card meta column (year, runtime, certification,
/// rating) — a small icon plus a plain-language label. Shared between
/// [TitleDetailScreen]'s header and anywhere else that wants the same
/// "movie card" meta look (e.g. the decide/random reveal screen).
class MetaLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  const MetaLine({super.key, required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor ?? SeenlyPalette.inkFaint),
          const SizedBox(width: 8),
          Text(
            label,
            style: SeenlyText.serif(size: 15, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A genre label styled like the rest of the app's quiet, editorial
/// vocabulary — a thin outline and letter-spaced small text — instead
/// of a filled Material-style oval, which read as generic UI chrome
/// against the warm paper background rather than part of the diary.
class GenreTag extends StatelessWidget {
  final String label;
  const GenreTag({super.key, required this.label});

  static TextStyle get textStyle => SeenlyText.mono(
        size: 11,
        color: SeenlyPalette.inkMuted,
        weight: FontWeight.w600,
      ).copyWith(letterSpacing: 0.6);

  /// Natural width the pill needs to show [label] without clipping —
  /// text width plus the horizontal padding and the 1px border on
  /// each side. Used by [GenreTagsFlow] to pack tags into rows.
  static double naturalWidth(String label) {
    final painter = TextPainter(
      text: TextSpan(text: label.tr.toUpperCase(), style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width + 12 * 2 + 1 * 2;
  }

  @override
  Widget build(BuildContext context) {
    if (SeenlySkin.isClay) {
      return ClaySurface(
        radius: 18,
        elevation: 0.3,
        color: Color.alphaBlend(SeenlyPalette.periwinkle.withOpacity(0.16), SeenlyPalette.paper),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Center(
          child: Text(
            label.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted, weight: FontWeight.w800),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: SeenlyPalette.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.tr.toUpperCase(),
        textAlign: TextAlign.center,
        style: textStyle,
      ),
    );
  }
}

/// Lays genre tags out edge-to-edge across the full width: as many as
/// fit on a line are stretched to fill it (wider labels claim
/// proportionally more space, so none are ever squeezed below what
/// they need), and whatever doesn't fit drops to a new, equally
/// full-width line below.
class GenreTagsFlow extends StatelessWidget {
  final List<String> genres;
  const GenreTagsFlow({super.key, required this.genres});

  static const double _spacing = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final widths = [for (final g in genres) GenreTag.naturalWidth(g)];

        final lines = <List<int>>[];
        var current = <int>[];
        var currentWidth = 0.0;
        for (var i = 0; i < genres.length; i++) {
          final w = widths[i];
          final projected =
              current.isEmpty ? w : currentWidth + _spacing + w;
          if (current.isNotEmpty && projected > maxWidth) {
            lines.add(current);
            current = [i];
            currentWidth = w;
          } else {
            current.add(i);
            currentWidth = projected;
          }
        }
        if (current.isNotEmpty) lines.add(current);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int li = 0; li < lines.length; li++) ...[
              if (li > 0) const SizedBox(height: _spacing),
              Row(
                children: [
                  for (int j = 0; j < lines[li].length; j++) ...[
                    if (j > 0) const SizedBox(width: _spacing),
                    Expanded(
                      // Flex proportional to the tag's natural width, so
                      // extra line width is shared out in proportion —
                      // a long label never ends up narrower than it needs.
                      flex: widths[lines[li][j]].round(),
                      child: GenreTag(label: genres[lines[li][j]]),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
