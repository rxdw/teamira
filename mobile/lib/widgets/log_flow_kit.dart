import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart';
import '../services/app_translations.dart';

/// Shared pieces for the "pick a seat → settle the details → confirm →
/// watch the pass appear" ritual that every log theme now runs. Kept
/// deliberately generic (no theme-specific copy or data baked in) so
/// the coach, cinema, and garden flows can each supply their own seat
/// glyph, ambience tint, and final keepsake while sharing the same
/// scaffolding, spacing, and feel.

/// A shared back-chevron + optional trailing action row, used at the
/// top of every step so the ritual always feels navigable rather than
/// a one-way dialog.
class LogFlowTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final String? trailingLabel;
  final VoidCallback? onTrailing;

  const LogFlowTopBar({super.key, required this.onBack, this.trailingLabel, this.onTrailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: SeenlyPalette.ink.withOpacity(0.28), shape: BoxShape.circle),
              child: const Icon(Icons.chevron_left, color: SeenlyPalette.paper, size: 22),
            ),
          ),
          if (trailingLabel != null)
            GestureDetector(
              onTap: onTrailing,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(trailingLabel!.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.6))),
              ),
            )
          else
            const SizedBox(width: 38),
        ],
      ),
    );
  }
}

/// A little dark pill announcing which seat's been claimed — sits at
/// the top of the details step as a quiet reminder of the choice just
/// made, the same way a real stub stays in your pocket the rest of
/// the night.
class SeatPill extends StatelessWidget {
  final String label;
  const SeatPill({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: SeenlyPalette.ink.withOpacity(0.3), borderRadius: BorderRadius.circular(14)),
      child: Text(label, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper, weight: FontWeight.w600)),
    );
  }
}

/// One label/value line on the confirm step's summary card.
class ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const ConfirmRow({super.key, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
        Text(value, style: SeenlyText.serif(size: 13, color: valueColor ?? SeenlyPalette.ink)),
      ],
    );
  }
}

// A tiny icon per preset vibe tag — same words the plain form always
// used, just given a face here so they read as something to *pick*.
// Covers both the "why did you love this" and "what fell short" preset
// lists (see mood_tag_picker.dart) — a handful of labels are shared
// between the two ('the ending', 'the pacing') and only need one entry.
const Map<String, IconData> logFlowTagIcons = {
  'the music': Icons.music_note,
  'the ending': Icons.flag_outlined,
  'the atmosphere': Icons.blur_on,
  'the performances': Icons.theater_comedy,
  'the visuals': Icons.image_outlined,
  'the story': Icons.auto_stories,
  'the humor': Icons.sentiment_very_satisfied,
  'the pacing': Icons.speed,
  'saw it coming': Icons.visibility,
  'flat characters': Icons.person_outline,
  'style over substance': Icons.style,
  'ran too long': Icons.hourglass_bottom,
  'the tone': Icons.tune,
  'forgettable': Icons.blur_off,
};

/// A colorful, bigger vibe/mood chip — the "same kind of choice" as
/// the seat grid, worn as a tag instead of a place to sit: an icon in
/// a soft tinted bubble plus the label, sized for a thumb rather than
/// a checkbox.
class VibeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const VibeChip({super.key, required this.label, required this.active, required this.onTap});

  Color _tint() {
    final tints = [SeenlyPalette.sage, SeenlyPalette.mustard, SeenlyPalette.periwinkle, SeenlyPalette.coral, SeenlyPalette.pink, SeenlyPalette.accent];
    return tints[label.hashCode.abs() % tints.length];
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint();
    final icon = logFlowTagIcons[label] ?? Icons.local_fire_department;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.only(left: 6, right: 14, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: active ? tint.withOpacity(0.18) : SeenlyPalette.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? tint.withOpacity(0.65) : SeenlyPalette.dashedBorder, width: active ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: tint.withOpacity(active ? 0.9 : 0.35), shape: BoxShape.circle),
              child: Icon(icon, size: 14, color: active ? SeenlyPalette.paper : SeenlyPalette.ink.withOpacity(0.55)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(size: 11.5, color: active ? SeenlyPalette.ink : SeenlyPalette.inkMuted, weight: active ? FontWeight.w600 : FontWeight.w400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays vibe chips out one to a row, each stretched to fill the full
/// available width — instead of a plain Wrap, where short labels
/// ("alone") and long ones ("rewatching for the 100th time") each
/// claim only as much room as their own text needs, or the old 2-up
/// grid, which still left short labels looking cramped next to long
/// ones. One per row keeps every chip (and its label) reading at the
/// same, full-width scale.
class VibeChipGrid extends StatelessWidget {
  final List<String> tags;
  final bool Function(String tag) isActive;
  final ValueChanged<String> onToggle;

  const VibeChipGrid({super.key, required this.tags, required this.isActive, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < tags.length; i++) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 9));
      rows.add(VibeChip(label: tags[i], active: isActive(tags[i]), onTap: () => onToggle(tags[i])));
    }
    return Column(children: rows);
  }
}

/// The seat glyph every theme's seat-picker draws — a backrest resting
/// on a slightly wider base, in the app's flat paper-cut shape language
/// rather than a system icon. Used at modal size in the old pickers;
/// here it's simply asked to draw itself bigger, never redrawn.
class SeatGlyph extends StatelessWidget {
  final Color color;
  final double size;
  const SeatGlyph({super.key, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: size * 0.62, height: size * 0.42, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.18))),
          const SizedBox(height: 2),
          Container(width: size, height: size * 0.32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.11))),
        ],
      ),
    );
  }
}

/// A single big, tappable seat — the modal pickers' seat button, given
/// real room to breathe on a full screen instead of being one of a
/// dozen crammed into a dialog.
class BigSeatButton extends StatelessWidget {
  final bool taken;
  final bool selected;
  final VoidCallback onTap;
  final double size;
  // Optional: marks a seat as one of the room's best few — a small
  // glow the cinema flow uses for the classic center-back "sweet
  // spot"; defaults off so every other theme's grid is unaffected.
  final bool prime;
  const BigSeatButton({super.key, required this.taken, required this.selected, required this.onTap, this.size = 34, this.prime = false});

  @override
  Widget build(BuildContext context) {
    final color = taken
        ? SeenlyPalette.paper.withOpacity(0.16)
        : selected
            ? SeenlyPalette.accent
            : prime
                ? SeenlyPalette.mustard.withOpacity(0.85)
                : SeenlyPalette.paper.withOpacity(0.55);
    return GestureDetector(
      onTap: taken ? null : onTap,
      child: AnimatedScale(
        scale: selected ? 1.16 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [BoxShadow(color: SeenlyPalette.accent.withOpacity(0.55), blurRadius: 16, spreadRadius: 1)],
                )
              : prime && !taken
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [BoxShadow(color: SeenlyPalette.mustard.withOpacity(0.28), blurRadius: 10, spreadRadius: 0.5)],
                    )
                  : const BoxDecoration(),
          padding: const EdgeInsets.all(4),
          child: SeatGlyph(color: color, size: size),
        ),
      ),
    );
  }
}

/// Deterministic "which seats are already taken tonight" — same title
/// always seeds the same handful, so the room doesn't reshuffle itself
/// if the screen rebuilds.
Set<int> seededTakenSeats(String seed, int total, {int salt = 0, int minTaken = 8, int extraRange = 14}) {
  final r = math.Random(seed.hashCode ^ salt);
  final count = minTaken + r.nextInt(extraRange);
  final taken = <int>{};
  while (taken.length < count && taken.length < total - 1) {
    taken.add(r.nextInt(total));
  }
  return taken;
}

/// The warm, gently animated backdrop shared by every step of a log
/// ritual — a dusk gradient tinted toward the theme's own color, with
/// a handful of soft, drifting motes, so the whole thing reads as one
/// continuous evening rather than four separate screens.
class LogFlowBackdrop extends StatelessWidget {
  final Animation<double> dust;
  final List<LightMote> motes;
  final Color tint;

  const LogFlowBackdrop({super.key, required this.dust, required this.motes, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SeenlyPalette.ink, Color.lerp(SeenlyPalette.ink, tint, 0.14)!],
        ),
      ),
      child: AnimatedBuilder(
        animation: dust,
        builder: (_, __) => CustomPaint(
          painter: DustPainter(t: dust.value, motes: motes),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// A small glowing plaque of text — used for the coach route line, the
/// cinema's screen number, the garden's plot name — one shared shape
/// for "here's tonight's small, specific detail" across every theme.
class GlowPlaque extends StatelessWidget {
  final String text;
  final double breathe;
  final Color glow;

  const GlowPlaque({super.key, required this.text, required this.breathe, this.glow = SeenlyPalette.mustard});

  @override
  Widget build(BuildContext context) {
    final intensity = 0.35 + 0.65 * ((math.sin(breathe * 2 * math.pi) + 1) / 2);
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: SeenlyPalette.ink.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: glow.withOpacity(0.22 * intensity), blurRadius: 16, spreadRadius: 1)],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.paper, weight: FontWeight.w600),
      ),
    );
  }
}

/// A quiet dark pool at the top and bottom of the screen — the ceiling
/// and floor of whatever room the evening is happening in (theatre,
/// coach, window box) always eat a little more of the light than the
/// middle does. Opt-in only (drop it in a `Positioned.fill` above the
/// backdrop, below the step content) so it never changes a screen that
/// hasn't asked for it.
class EveningVignette extends StatelessWidget {
  const EveningVignette({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.16, 0.84, 1.0],
          colors: [
            SeenlyPalette.ink.withOpacity(0.55),
            SeenlyPalette.ink.withOpacity(0.0),
            SeenlyPalette.ink.withOpacity(0.0),
            SeenlyPalette.ink.withOpacity(0.6),
          ],
        ),
      ),
    );
  }
}

/// A little announcement that flickers up once, holds a beat, and
/// dims itself back out — the "please silence your phone" cinema
/// slide, the coach's "please take your seat" chime, the garden's own
/// quiet-hour notice. One curve shared by every theme so the three
/// only differ in the actual words. Pass a controller that runs once
/// from 0 to 1 (no repeat) — this just maps that into an opacity.
double eveningAnnouncementOpacity(double t) {
  if (t < 0.15) return Curves.easeOut.transform(t / 0.15);
  if (t < 0.7) return 1.0;
  return 1.0 - Curves.easeIn.transform(((t - 0.7) / 0.3).clamp(0.0, 1.0));
}

/// The "please silence your phone" / "please fasten your seatbelt"
/// style announcement, sitting in the ordinary top-of-column flow
/// instead of floating in a Stack layer over the title and glow-plaque
/// beneath it. The old floating version sat at a fixed offset from the
/// top of the screen and the title/subtitle/plaque did too — on longer
/// titles (or longer translated strings) the two landed on the same
/// patch of screen and the text visibly ran together. Living in the
/// flow means it simply pushes everything below it down while it's
/// visible, then folds its own height away once it's done, so nothing
/// downstream ever has to share its space.
class CollapsingAnnouncement extends StatelessWidget {
  final Animation<double> preshow; // runs 0→1 once, doesn't repeat
  final Animation<double> breathe; // the shared pulse, for the glow
  final String text;
  final Color glow;

  const CollapsingAnnouncement({
    super.key,
    required this.preshow,
    required this.breathe,
    required this.text,
    this.glow = SeenlyPalette.mustard,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: preshow,
      builder: (_, __) {
        final opacity = eveningAnnouncementOpacity(preshow.value);
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: opacity <= 0.02
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Opacity(
                    opacity: opacity,
                    child: AnimatedBuilder(
                      animation: breathe,
                      builder: (_, __) => GlowPlaque(text: text, breathe: breathe.value, glow: glow),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// One quiet, in-character line sitting in a soft outlined pill below
/// the route/screen/bed strip — the small aside a friend would mutter
/// under their breath while you're both waiting for the bus, the
/// lights, or the kettle. Fills what used to be dead air between the
/// strip and the confirm button with a bit more of the same ritual,
/// rather than a generic empty gap. Purely decorative — no state, no
/// interaction — and breathes on the same shared pulse as everything
/// else on the confirm step so it never feels bolted on.
class AmbientNote extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String text;
  final double breathe;

  const AmbientNote({
    super.key,
    required this.icon,
    required this.tint,
    required this.text,
    required this.breathe,
  });

  @override
  Widget build(BuildContext context) {
    final t = 0.35 + 0.65 * ((math.sin(breathe * 2 * math.pi) + 1) / 2);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withOpacity(0.20 + 0.12 * t)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.paper.withOpacity(0.78)),
      ),
    );
  }
}

/// Picks one line from [lines] deterministically per [seed] — same
/// title always gets the same aside, the way the route/hall/spot
/// assignment already works, rather than reshuffling every rebuild.
String pickAmbientLine(String seed, List<String> lines, {int salt = 0}) {
  final r = math.Random(seed.hashCode ^ salt ^ 0x616D6269); // 'ambi'
  return lines[r.nextInt(lines.length)];
}

/// Shown when someone tries to back out of the seat/spot step — by the
/// top bar's chevron or the system back gesture — instead of letting
/// that pop happen straight away. Three plain options, one tap each:
/// stay put, step back to the still-running progress screen, or end
/// the route outright.
Future<void> showLeaveRouteDialog(
  BuildContext context, {
  required String routeNoun,
  required VoidCallback onReturnToRoute,
  required VoidCallback onEndRoute,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: SeenlyPalette.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('leave without finishing?'.tr,
          style: SeenlyText.serif(italic: true, size: 17, color: SeenlyPalette.paper)),
      content: Text(
        "nothing's logged yet.".tr,
        style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.65)),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('stay'.tr, style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.paper.withOpacity(0.65))),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onReturnToRoute();
          },
          child: Text('${'back to'.tr} $routeNoun',
              style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.paper, weight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onEndRoute();
          },
          child: Text('${'cancel'.tr} $routeNoun',
              style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.coral, weight: FontWeight.w600)),
        ),
      ],
    ),
  );
}


