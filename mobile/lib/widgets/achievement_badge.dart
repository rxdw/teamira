import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/achievement.dart';
import '../services/app_translations.dart';
import '../services/log_theme_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';

/// Maps an `Achievement.iconKey` (a small fixed vocabulary from the
/// backend — see AchievementOut in schemas.py) to the icon shown on its
/// badge. [title] is used to pick a more specific icon within a
/// category that covers several different achievements — `icon_key`
/// alone only has 8 values (see backend/app/routers/profile.py's
/// `_MOVIE_MILESTONES` / `_GENRE_MASTERY` / `_STREAK_MILESTONES`), but
/// there are ~45 achievements total, so several genuinely different
/// achievements (five movie-count tiers, four genres, four streak
/// tiers) would otherwise render as the exact same icon with nothing
/// but the label to tell them apart. Kept in one place so the profile
/// teaser row and the full achievements screen never drift apart.
IconData achievementIcon(String iconKey, String title) {
  final t = title.toLowerCase();
  switch (iconKey) {
    case 'level':
      // Level milestones (5, 10, 15, ...) — see _LEVEL_MILESTONES in
      // backend/app/routers/profile.py and the "level path" section of
      // screens/profile/level_detail_screen.dart, which shows the same
      // badge inline as each milestone is reached. A small climbing set
      // so the badge itself hints at how far along the path it sits,
      // rather than repeating one glyph for every tier.
      final n = int.tryParse(RegExp(r'\d+').firstMatch(t)?.group(0) ?? '') ?? 0;
      if (n >= 30) return Icons.auto_awesome;
      if (n >= 25) return Icons.public_outlined;
      if (n >= 20) return Icons.landscape_outlined;
      if (n >= 15) return Icons.terrain_outlined;
      if (n >= 10) return Icons.route_outlined;
      return Icons.eco_outlined;
    case 'milestone':
      // The five _MOVIE_MILESTONES titles, in ascending order — a small
      // sense of rank climbing alongside the count itself.
      if (t.contains('first watch')) return Icons.play_circle_outline;
      if (t.contains('warming up')) return Icons.local_activity_outlined;
      if (t.contains('movie buff')) return Icons.military_tech_outlined;
      if (t.contains('100 films')) return Icons.emoji_events_outlined;
      if (t.contains('film scholar')) return Icons.workspace_premium_outlined;
      return Icons.emoji_events_outlined;
    case 'review':
      return Icons.edit_outlined;
    case 'rewatch':
      return Icons.replay;
    case 'explorer':
      return Icons.explore_outlined;
    case 'genre':
      // The four fixed _GENRE_MASTERY entries — each gets something
      // that actually reads as that genre rather than a shared
      // category glyph.
      if (t.contains('comedy')) return Icons.theater_comedy_outlined;
      if (t.contains('brave')) return Icons.dark_mode_outlined; // horror
      if (t.contains('kid at heart')) return Icons.toys_outlined; // animation
      if (t.contains('curious mind')) return Icons.travel_explore_outlined; // documentary
      return Icons.category_outlined;
    case 'saga':
      // Franchise achievements are unbounded (one per completed
      // collection — see the `franchise_collections` loop) and named
      // after whatever the franchise actually is, so there's no fixed
      // vocabulary to branch on the way genre/milestone/streak have —
      // the title itself (now that the teaser row's overflow is fixed
      // and the full label actually shows) is what tells them apart.
      return Icons.local_movies_outlined;
    case 'streak':
      // The four fixed _STREAK_MILESTONES titles, in ascending order.
      if (t.contains('good week')) return Icons.local_fire_department_outlined;
      if (t.contains('whole month')) return Icons.whatshot;
      if (t.contains('triple digits')) return Icons.bolt;
      if (t.contains('unbroken year')) return Icons.auto_awesome;
      return Icons.local_fire_department_outlined;
    case 'loyalty':
      return Icons.cake_outlined;
    default:
      return Icons.star_outline;
  }
}

enum AchievementBadgeSize { small, large }

/// The four badge rarities (see `Achievement.rarity` / backend
/// `_rarity_for_target`) — cozy, diary-appropriate names rather than
/// game-y ones, each with its own fill treatment. Kept in one place so
/// the badge widget, the showcase legend, and the unlock-moment sheet
/// all agree on the same four colors and labels.
enum BadgeRarity { habit, devoted, obsession, legend }

BadgeRarity badgeRarityFromKey(String key) {
  switch (key) {
    case 'legend':
      return BadgeRarity.legend;
    case 'obsession':
      return BadgeRarity.obsession;
    case 'devoted':
      return BadgeRarity.devoted;
    default:
      return BadgeRarity.habit;
  }
}

/// Rarity for a level-milestone badge (level 5, 10, 15, ...) — kept in
/// sync with backend/app/routers/profile.py's `_rarity_for_level`, its
/// own curve rather than the general `_rarity_for_target` one (which is
/// tuned for movie-count-sized targets, not a level number). Used both
/// here (the badges screen reads a rarity key straight from the
/// backend) and by the "level path" milestone cards, which show the
/// same badge before the backend achievement list technically exists
/// for that level yet.
String levelBadgeRarityKey(int level) {
  if (level >= 30) return 'legend';
  if (level >= 20) return 'obsession';
  if (level >= 10) return 'devoted';
  return 'habit';
}

extension BadgeRarityStyle on BadgeRarity {
  /// Shown on the showcase legend and the unlock sheet — lowercase,
  /// same tone as the rest of the app's copy ("achievements",
  /// "milestones"), not game-y words like "common"/"epic".
  String get label {
    switch (this) {
      case BadgeRarity.habit:
        return 'habit'.tr;
      case BadgeRarity.devoted:
        return 'devoted'.tr;
      case BadgeRarity.obsession:
        return 'obsession'.tr;
      case BadgeRarity.legend:
        return 'legend'.tr;
    }
  }

  /// The badge's base color — used for the glow, the pin ribbon, and the
  /// legend dot. Each rarity's gradient (see [gradient]) lightens toward
  /// this same hue rather than introducing a second color, so the glow
  /// and the fill always read as one material.
  Color get color {
    switch (this) {
      case BadgeRarity.habit:
        return SeenlyPalette.sage;
      case BadgeRarity.devoted:
        return SeenlyPalette.periwinkle;
      case BadgeRarity.obsession:
        return SeenlyPalette.mustard;
      case BadgeRarity.legend:
        return SeenlyPalette.coral;
    }
  }

  /// The fill gradient for an unlocked badge of this rarity. The first
  /// three are a simple two-stop lighten-toward-white — the same "soft
  /// inner light" treatment the badge always used for mustard, just
  /// reused per-color. Legend is the one exception: a three-stop diagonal
  /// sweep through the app's accent, mustard, and coral — a small "foil"
  /// effect built entirely from colors already in the palette, not a new
  /// one introduced just for this.
  LinearGradient get gradient {
    if (this == BadgeRarity.legend) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          SeenlyPalette.accent,
          SeenlyPalette.mustard,
          SeenlyPalette.coral,
        ],
      );
    }
    final base = color;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(base, Colors.white, 0.22)!,
        base,
      ],
    );
  }
}

/// One achievement badge — shape follows the active [LogTheme] (a punched
/// ticket stub for ticket/coach, a seed packet for garden), same visual
/// language as the streak card and favorite-film tiles elsewhere on
/// Profile. Used both in the profile teaser row ([AchievementBadgeSize.small])
/// and the full achievements screen ([AchievementBadgeSize.large]).
class AchievementBadge extends StatelessWidget {
  final LogTheme theme;
  final String iconKey;
  final String label;
  final bool unlocked;
  final AchievementBadgeSize size;
  /// "habit" | "devoted" | "obsession" | "legend" — see [BadgeRarity].
  /// Ignored while locked (locked badges stay a neutral silhouette
  /// regardless of rarity, same as before — no point flaunting how rare
  /// something you haven't earned is).
  final String rarity;
  /// Shown under the label only when locked and there's real progress to
  /// show (e.g. "6 / 11") — omitted entirely otherwise rather than
  /// printing "0 / 1" for something not even started yet.
  final String? progressLabel;
  /// True if this badge is one of the (at most 3) pinned to the profile
  /// showcase — draws a small ribbon in the corner instead of the plain
  /// checkmark. Only meaningful while [unlocked].
  final bool pinned;
  /// Tapping an unlocked badge toggles it in/out of the showcase pin —
  /// null (the default) leaves the badge non-interactive, e.g. in the
  /// profile teaser row where tapping opens the full screen instead.
  final VoidCallback? onTap;

  const AchievementBadge({
    super.key,
    required this.theme,
    required this.iconKey,
    required this.label,
    required this.unlocked,
    this.size = AchievementBadgeSize.small,
    this.rarity = 'habit',
    this.progressLabel,
    this.pinned = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final large = size == AchievementBadgeSize.large;
    final w = large ? 64.0 : 46.0;
    final h = large ? 78.0 : 56.0;
    final icon = achievementIcon(iconKey, label);
    final rarityStyle = badgeRarityFromKey(rarity);
    final isLegend = unlocked && rarityStyle == BadgeRarity.legend;

    // Unlocked achievements get a warm fill keyed to their rarity (see
    // BadgeRarityStyle.gradient) — the icon is sized to dominate the
    // shape (not tucked into a corner or padded to the bottom) so the
    // whole card reads as the badge, and a soft glow in the same hue
    // lifts it off the page a little, like the streak card's shadow
    // does.
    final iconColor = unlocked ? SeenlyPalette.paper : SeenlyPalette.placeholder;
    final iconSize = large ? (unlocked ? 36.0 : 23.0) : (unlocked ? 25.0 : 16.0);
    final unlockedFill = rarityStyle.gradient;

    Widget badge;
    if (theme == LogTheme.garden) {
      badge = ClipPath(
        clipper: _SeedPacketClipper(),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(gradient: unlocked ? unlockedFill : null),
          // A touch below dead-center so the icon sits clear of the
          // packet's pointed flap rather than crowding it, while still
          // filling almost the entire body of the packet.
          alignment: const Alignment(0, 0.22),
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
      );
      if (!unlocked) {
        badge = DashedBox(radius: large ? 6 : 4, color: SeenlyPalette.dashedBorder, child: badge);
      }
    } else {
      final notch = Container(
        width: large ? 10 : 8,
        height: large ? 10 : 8,
        decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
      );
      badge = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              gradient: unlocked ? unlockedFill : null,
              borderRadius: BorderRadius.circular(large ? 8 : 5),
              border: unlocked ? null : Border.all(color: SeenlyPalette.dashedBorder, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
          Positioned(top: large ? -5 : -4, child: notch),
          Positioned(bottom: large ? -5 : -4, child: notch),
        ],
      );
    }

    if (isLegend) {
      // A single tiny spark tucked near the top edge — the one place an
      // animation-adjacent flourish is allowed to live permanently in
      // the grid (everything more than this is reserved for the unlock
      // moment itself), so a legend badge is recognizable at a glance
      // even before you read the label.
      badge = Stack(
        clipBehavior: Clip.none,
        children: [
          badge,
          Positioned(
            top: large ? 6 : 4,
            left: large ? 10 : 7,
            child: Icon(Icons.auto_awesome, size: large ? 10 : 7, color: SeenlyPalette.paper.withOpacity(0.85)),
          ),
        ],
      );
    }

    if (unlocked) {
      // The glow, plus either a pin ribbon (if this badge is in the
      // showcase) or a plain stamped checkmark in the corner — the
      // detail that sells "collected" at a glance, on both shapes.
      final markSize = large ? 17.0 : 13.0;
      badge = Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(boxShadow: [
              BoxShadow(
                color: rarityStyle.color.withOpacity(isLegend ? 0.5 : 0.45),
                blurRadius: large ? (isLegend ? 18 : 14) : 9,
                offset: const Offset(0, 4),
              ),
            ]),
            child: badge,
          ),
          Positioned(
            top: large ? -5 : -4,
            right: large ? -5 : -4,
            child: Container(
              width: markSize,
              height: markSize,
              decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: pinned
                  ? Icon(Icons.push_pin, size: large ? 11 : 9, color: SeenlyPalette.accent)
                  : Container(
                      width: markSize - 3,
                      height: markSize - 3,
                      decoration: BoxDecoration(
                        color: rarityStyle.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: SeenlyPalette.paper, width: large ? 1.4 : 1),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.check, size: large ? 9 : 7, color: SeenlyPalette.paper),
                    ),
            ),
          ),
        ],
      );
    }

    final content = SizedBox(
      width: large ? 76 : 46,
      child: Column(
        children: [
          badge,
          SizedBox(height: large ? 8 : 5),
          Text(label.tr,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: SeenlyText.mono(
                size: large ? 9.5 : 7.5,
                color: unlocked ? SeenlyPalette.inkFaint : SeenlyPalette.placeholder,
              )),
          if (progressLabel != null) ...[
            const SizedBox(height: 2),
            Text(progressLabel!, style: SeenlyText.mono(size: large ? 8.5 : 7, color: SeenlyPalette.placeholder)),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}

class _SeedPacketClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    return Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.18)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..lineTo(0, h * 0.18)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// A small round badge medallion — the same circular, pastel-filled
/// treatment [AchievementsScreen]'s own showcase grid uses, just sized
/// down for a teaser row. Unlike [AchievementBadge] (which follows the
/// active [LogTheme]'s shape — ticket stub, boarding pass, seed packet),
/// this one is always a plain circle: for a small "here's what I'm
/// proud of" row sitting right under the profile header, the same
/// rounded language [FavoritesShowcaseRow] uses for its poster corners
/// reads calmer than a theatrical shape repeated three times in a row.
/// Handles both states — filled gradient + corner mark when [unlocked],
/// a neutral dashed outline otherwise — so it doubles as both the
/// pinned-badges showcase (always unlocked) and the general achievements
/// teaser row (a mix of both).
class RoundBadgeMedallion extends StatelessWidget {
  final String iconKey;
  final String title;
  final String rarity;
  final bool unlocked;
  /// Only meaningful while [unlocked] — draws a pin mark in the corner
  /// instead of the plain checkmark.
  final bool pinned;
  /// Shown under the label only when locked and there's real progress
  /// (e.g. "6 / 11") — omitted otherwise, same rule as [AchievementBadge].
  final String? progressLabel;
  final double diameter;
  final bool showLabel;
  final VoidCallback? onTap;

  const RoundBadgeMedallion({
    super.key,
    required this.iconKey,
    required this.title,
    required this.rarity,
    this.unlocked = true,
    this.pinned = false,
    this.progressLabel,
    this.diameter = 52,
    this.showLabel = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rarityStyle = badgeRarityFromKey(rarity);
    final icon = achievementIcon(iconKey, title);
    final isLegend = unlocked && rarityStyle == BadgeRarity.legend;

    Widget medallion = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: unlocked ? rarityStyle.gradient : null,
        color: unlocked ? null : SeenlyPalette.paper,
        border: unlocked ? null : Border.all(color: SeenlyPalette.dashedBorder, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: diameter * (unlocked ? 0.4 : 0.32),
        // Unlocked badges fill with the rarity's own color (see
        // [BadgeRarity.gradient]), so an icon painted in that same base
        // hue barely reads against it — legend already sidestepped this
        // by using paper; every rarity now does, for real contrast
        // instead of a same-color icon nearly disappearing into its fill.
        color: unlocked ? SeenlyPalette.paper : SeenlyPalette.placeholder,
      ),
    );
    if (unlocked) {
      medallion = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: rarityStyle.color.withOpacity(isLegend ? 0.45 : 0.32),
              blurRadius: diameter * 0.24,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: medallion,
      );
    }
    if (isLegend) {
      medallion = Stack(
        clipBehavior: Clip.none,
        children: [
          medallion,
          Positioned(
            top: diameter * 0.1,
            left: diameter * 0.16,
            child: Icon(Icons.auto_awesome,
                size: diameter * 0.16, color: SeenlyPalette.paper.withOpacity(0.85)),
          ),
        ],
      );
    }
    if (unlocked) {
      // A small stamped mark in the corner — a pin for anything already
      // showcased on the profile, a plain checkmark otherwise. Same
      // "collected" tell the full achievements grid uses, just scaled
      // down to fit a teaser-sized circle.
      final markSize = diameter * 0.3;
      medallion = Stack(
        clipBehavior: Clip.none,
        children: [
          medallion,
          Positioned(
            top: -markSize * 0.15,
            right: -markSize * 0.15,
            child: Container(
              width: markSize,
              height: markSize,
              decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: pinned
                  ? Icon(Icons.push_pin, size: markSize * 0.62, color: SeenlyPalette.accent)
                  : Container(
                      width: markSize * 0.78,
                      height: markSize * 0.78,
                      decoration: BoxDecoration(
                        color: rarityStyle.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: SeenlyPalette.paper, width: 1.2),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.check, size: markSize * 0.42, color: SeenlyPalette.paper),
                    ),
            ),
          ),
        ],
      );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        medallion,
        if (showLabel) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: diameter + 14,
            child: Text(
              title.tr,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.mono(
                size: 8.5,
                color: unlocked ? SeenlyPalette.inkFaint : SeenlyPalette.placeholder,
              ),
            ),
          ),
          if (progressLabel != null) ...[
            const SizedBox(height: 2),
            Text(progressLabel!, style: SeenlyText.mono(size: 7.5, color: SeenlyPalette.placeholder)),
          ],
        ],
      ],
    );

    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: content);
  }
}

/// Localizes an achievement's caption for display. Almost every caption
/// is one of a small fixed set of strings baked into
/// backend/app/routers/profile.py (movie/genre/streak/level milestones,
/// craft achievements) — those translate with a plain `.tr` lookup, same
/// as everything else in this file. Saga captions are the one exception:
/// they're assembled server-side as "watched all {N} in the saga" with a
/// franchise-specific N, so no single literal string can be in the
/// translation table. For those we rebuild the sentence client-side from
/// [Achievement.progressTarget] (the same number the caption embeds) and
/// translated fragments instead, so franchise completions read in
/// Russian too rather than silently falling back to English.
String _localizedCaption(Achievement a) {
  if (a.category == 'saga') {
    return '${'watched all'.tr} ${a.progressTarget} ${'in the saga'.tr}';
  }
  return a.caption.tr;
}

/// Turns the backend's terse `Achievement.caption` ("watched all 9 in
/// the saga", "a 7-day streak") into a full sentence for
/// [showBadgeDetailCard] below. Kept under its own tense-neutral label
/// there rather than grammatically stitched onto anything — captions mix
/// past-tense phrases ("wrote a note...") and plain noun phrases ("10
/// films logged") depending on the badge, so gluing a verb in front
/// would read fine for some and broken for others.
String _sentenceCase(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  final capitalized = t[0].toUpperCase() + t.substring(1);
  return capitalized.endsWith('.') ? capitalized : '$capitalized.';
}

/// The centered, blurred-backdrop card a badge tap opens into — what
/// explains, softly, what a badge is actually for. Shared between
/// [AchievementsScreen]'s own grid and Profile's pinned-badges teaser
/// row so the two never drift into two different explanations of the
/// same badge. Same fade + slight scale-in over a blurred, tap-to-
/// dismiss backdrop as [showHowItWorksSheet] elsewhere in the app,
/// rather than a bottom sheet — this is one small standalone fact about
/// a single badge, not a flow anchored to the bottom of the screen.
///
/// [onTogglePin] is only offered a pin/unpin action when non-null — the
/// full achievements grid passes its own pin handler, while Profile's
/// teaser row (which has no local pin-state bookkeeping of its own)
/// leaves it null and the card renders read-only.
Future<void> showBadgeDetailCard(
  BuildContext context, {
  required Achievement achievement,
  bool pinned = false,
  VoidCallback? onTogglePin,
}) {
  return showGeneralDialog(
    context: context,
    barrierLabel: achievement.title.tr,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) => _BadgeDetailCard(
      achievement: achievement,
      pinned: pinned,
      onTogglePin: onTogglePin == null
          ? null
          : () {
              Navigator.of(dialogContext).pop();
              onTogglePin();
            },
    ),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _BadgeDetailCard extends StatelessWidget {
  final Achievement achievement;
  final bool pinned;
  final VoidCallback? onTogglePin;
  const _BadgeDetailCard({required this.achievement, required this.pinned, this.onTogglePin});

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final rarity = badgeRarityFromKey(a.rarity);
    final icon = achievementIcon(a.iconKey, a.title);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(color: SeenlyPalette.ink.withOpacity(0.28)),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: GestureDetector(
                onTap: () {}, // swallow — a tap on the card itself shouldn't dismiss it
                child: Container(
                  width: 300,
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: SeenlyPalette.ink.withOpacity(0.18),
                          blurRadius: 30,
                          offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                                color: SeenlyPalette.background, shape: BoxShape.circle),
                            child: Icon(Icons.close, size: 12, color: SeenlyPalette.inkMuted),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -6),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: a.unlocked ? rarity.gradient : null,
                            color: a.unlocked ? null : SeenlyPalette.background,
                            border: a.unlocked
                                ? null
                                : Border.all(color: SeenlyPalette.dashedBorder, width: 1.4),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            icon,
                            size: 26,
                            color: a.unlocked
                                ? SeenlyPalette.paper
                                : SeenlyPalette.placeholder,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(a.title.tr,
                          textAlign: TextAlign.center,
                          style: SeenlyText.serif(size: 17, weight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        a.unlocked ? rarity.label : 'not earned yet'.tr,
                        style: SeenlyText.mono(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: a.unlocked ? rarity.color : SeenlyPalette.placeholder,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        a.unlocked ? 'why you have it'.tr : 'how to earn it'.tr,
                        style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _sentenceCase(_localizedCaption(a)),
                        textAlign: TextAlign.center,
                        style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
                      ),
                      if (!a.unlocked && a.progressCurrent > 0) ...[
                        const SizedBox(height: 10),
                        Text('${a.progressCurrent} / ${a.progressTarget} ${'so far'.tr}',
                            style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                      ],
                      if (onTogglePin != null) ...[
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: onTogglePin,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: pinned ? SeenlyPalette.background : SeenlyPalette.accent,
                              borderRadius: BorderRadius.circular(24),
                              border: pinned ? Border.all(color: SeenlyPalette.border) : null,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.push_pin,
                                    size: 14,
                                    color: pinned
                                        ? SeenlyPalette.inkMuted
                                        : SeenlyPalette.accentOnAccent),
                                const SizedBox(width: 7),
                                Text(
                                  pinned ? 'unpin from profile'.tr : 'pin to profile'.tr,
                                  style: SeenlyText.serif(
                                    italic: true,
                                    color: pinned
                                        ? SeenlyPalette.inkMuted
                                        : SeenlyPalette.accentOnAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
