import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/diary_entry.dart';
import '../../models/media_item.dart';
import '../../services/episode_continuation.dart';
import '../../services/log_theme_service.dart';
import '../../services/ritual_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import 'cinema_log_screen.dart';
import 'coach_log_screen.dart';
import 'episode_log_followup.dart';
import 'garden_log_screen.dart';
import 'journey_select_screen.dart';
import 'shuttle_log_screen.dart';
import '../../widgets/achievement_unlock_overlay.dart';
import '../../widgets/level_up_celebration.dart';
import '../../widgets/sincerity_toast.dart';
import '../../widgets/wow_motion.dart' show Entrance, FadeInNetworkImage, PressScale;
import '../../services/app_translations.dart';
import '../../widgets/saved_celebration.dart';

/// First step of logging a title — whether tonight's evening already
/// happened or is happening right now. Full-bleed split screen: the top
/// half is "already watched" (goes straight into the existing rating
/// ritual — see [CoachLogScreen] / [CinemaLogScreen] / [GardenLogScreen]
/// — for a movie/whole-title just like before; for a single episode,
/// marks it watched right away via [markEpisodeWatched] — guaranteed
/// regardless of what follows — then still runs that same seat/venue +
/// ticket-tear ritual for this episode's evening, and once that's done
/// asks whether to keep going — on yes, chains straight into the next
/// unwatched episode via this same choice screen, see
/// [nextUnwatchedEpisode] and [confirmWatchNextEpisode]), the bottom half is
/// "watching now" (opens the route/path picker, see
/// [JourneySelectScreen], and a live progress screen after it — same
/// split applies once the person is actually back). Each half is one
/// big tap target, the poster + title float on the seam between them.
class WatchingChoiceScreen extends StatelessWidget {
  final MediaItem item;
  // Set together only when this choice is for one specific episode of a
  // series — both null logs the title as a whole, same as before.
  final int? season;
  final int? episode;
  // Pre-checks the themed screens' own "watched with partner" toggle —
  // for a title that's demonstrably already a shared evening (opened
  // from the co-viewing planned grid's "смотрю" button, see
  // CoViewHubScreen._openPlannedLogging) rather than a solo log where
  // the person has to opt in themselves. Still just the toggle's
  // starting position: nothing stops the person flipping it back off on
  // the rating screen if this evening wasn't actually together.
  final bool initialWatchedWithPartner;
  const WatchingChoiceScreen({
    super.key,
    required this.item,
    this.season,
    this.episode,
    this.initialWatchedWithPartner = false,
  });

  Widget _ratingScreen(LogTheme theme) => switch (theme) {
        LogTheme.coach => CoachLogScreen(
            item: item, season: season, episode: episode, initialWatchedWithPartner: initialWatchedWithPartner),
        LogTheme.ticket => CinemaLogScreen(
            item: item, season: season, episode: episode, initialWatchedWithPartner: initialWatchedWithPartner),
        LogTheme.garden => GardenLogScreen(
            item: item, season: season, episode: episode, initialWatchedWithPartner: initialWatchedWithPartner),
        LogTheme.shuttle => ShuttleLogScreen(
            item: item, season: season, episode: episode, initialWatchedWithPartner: initialWatchedWithPartner),
      };

  /// The whole ritual, skipped — no seat/venue pick, no journey, no
  /// ticket tear. Just marks the evening (or episode) logged right now,
  /// with no rating/note attached. Used both by the inline banner's
  /// "log it now" tap and automatically whenever [RitualPrefsService.
  /// skipRitual] is on — see this screen's own `build`.
  Future<void> _quickLog(BuildContext context) async {
    DiaryEntry? loggedEntry;
    if (season != null && episode != null) {
      await markEpisodeWatched(context: context, item: item, season: season!, episode: episode!);
      if (!context.mounted) return;
      try {
        // markEpisodeWatched only ticks progress and (via
        // maybeLogCompletedSeason) logs a diary row once the whole
        // season is done — same as the rating ritual, this specific
        // episode's own evening still needs its own row so it shows up
        // in "watched now" right away, not just once the season wraps.
        loggedEntry = await context.read<AppState>().diary.logEntry(
              item: item,
              watchedAt: DateTime.now(),
              season: season,
              episode: episode,
              watchedWithPartner: initialWatchedWithPartner,
            );
      } catch (_) {
        // Best-effort — same as below.
      }
    } else {
      try {
        loggedEntry = await context.read<AppState>().diary.logEntry(
              item: item,
              watchedAt: DateTime.now(),
              watchedWithPartner: initialWatchedWithPartner,
            );
      } catch (_) {
        // Best-effort — the person asked for speed over ceremony, not a
        // hard failure dialog; the diary just stays a beat behind.
      }
    }
    if (!context.mounted) return;
    if (loggedEntry != null) showSincerityToasts(context, loggedEntry.sincerityAwarded);
    // "Speed over ceremony" was never meant to mean "no celebration
    // ever" — every themed rating ritual (CoachLogScreen,
    // CinemaLogScreen, ...) checks for a fresh level-up/achievement
    // right after its own save; this quick path used to skip that
    // entirely, so anyone who taps "log it now" or has Settings' "skip
    // the ritual" on — i.e. most saves, for exactly the kind of
    // frequent logger who'd actually notice a missing celebration —
    // never saw one, even on a genuine level-up. refreshLevel() is
    // awaited here (unlike the ritual screens' fire-and-forget call)
    // because there's no several-second ritual animation left for the
    // network round trip to hide inside before we'd otherwise pop and
    // lose the moment.
    await context.read<AppState>().refreshLevel();
    if (!context.mounted) return;
    final leveledUp = context.read<AppState>().consumePendingLevelUp();
    if (leveledUp != null && context.mounted) {
      await showLevelUpCelebration(context, leveledUp);
    }
    if (context.mounted) {
      await checkAndCelebrateNewAchievements(context);
    }
    if (context.mounted) {
      // The quick path has no ritual of its own — this is its moment.
      showSavedCelebration(
        context,
        kind: SavedKind.logged,
        title: item.title.display,
        posterUrl: item.posterUrl,
        mediaType: item.mediaType,
        together: initialWatchedWithPartner,
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _alreadyWatched(BuildContext context, LogTheme theme) async {
    if (context.read<RitualPrefsService>().skipRitual) return _quickLog(context);
    if (season != null && episode != null) {
      // Mark it watched right away — "already watched" means watched no
      // matter what happens in the ritual/next-episode prompt below (a
      // person backing out of the ticket tear, or dismissing the "watch
      // next?" offer, still watched this episode).
      await markEpisodeWatched(context: context, item: item, season: season!, episode: episode!);
      if (!context.mounted) return;

      // Same seat-pick → details → confirm → ticket-tear ritual as a
      // whole-title log, just for this one episode's evening.
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ratingScreen(theme)),
      );
      if (!context.mounted) return;

      // Offer to keep going straight into the next episode — same
      // already-watched/watching-now choice as this screen itself, but
      // only if the person actually wants to keep the evening going.
      final next = await nextUnwatchedEpisode(context: context, item: item);
      if (context.mounted && next != null) {
        final wantsNext = await confirmWatchNextEpisode(context, theme);
        if (context.mounted && wantsNext) {
          final chained = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => WatchingChoiceScreen(
                item: item,
                season: next.$1,
                episode: next.$2,
                initialWatchedWithPartner: initialWatchedWithPartner,
              ),
            ),
          );
          if (context.mounted) Navigator.of(context).pop(chained ?? true);
          return;
        }
      }
      if (context.mounted) Navigator.of(context).pop(true);
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ratingScreen(theme)),
    );
    if (context.mounted) Navigator.of(context).pop(saved);
  }

  Future<void> _watchingNow(BuildContext context, LogTheme theme) async {
    if (context.read<RitualPrefsService>().skipRitual) return _quickLog(context);
    bool? saved;
    if (season != null && episode != null) {
      // An episode of a series — check whether there's a route/place to
      // resume from (see startEpisodeJourney) instead of always forcing
      // the full picker: the same continue-or-fresh-start decision
      // "watch next episode" already gets from the episodes sheet, so
      // picking "watching now" for a series behaves the same way no
      // matter which button got you here.
      saved = await startEpisodeJourney(context, item: item, theme: theme, season: season!, episode: episode!);
    } else {
      saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => JourneySelectScreen(
            item: item,
            theme: theme,
            season: season,
            episode: episode,
            initialWatchedWithPartner: initialWatchedWithPartner,
          ),
        ),
      );
    }
    if (context.mounted) Navigator.of(context).pop(saved);
  }

  String _watchingNowSubtitle(LogTheme theme) => switch (theme) {
        LogTheme.coach => 'a route, chosen and boarded now'.tr,
        LogTheme.ticket => 'a cinema, flown to and playing now'.tr,
        LogTheme.garden => 'a garden, walked right now'.tr,
        LogTheme.shuttle => 'a launch site, cleared and lifting off now'.tr,
      };

  IconData _watchingNowIcon(LogTheme theme) => switch (theme) {
        LogTheme.coach => Icons.train,
        LogTheme.ticket => Icons.flight,
        LogTheme.garden => Icons.directions_walk,
        LogTheme.shuttle => Icons.rocket_launch,
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    final ritualPrefs = context.watch<RitualPrefsService>();
    final showBanner = !ritualPrefs.skipRitual && !ritualPrefs.bannerDismissed;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _ChoiceHalf(
                  icon: Icons.check,
                  iconColor: SeenlyPalette.sage,
                  title: 'already watched'.tr,
                  subtitle: 'rate it and log the evening now'.tr,
                  background: SeenlyPalette.paper,
                  contentAlignment: const Alignment(0, 0.35),
                  entranceDelay: const Duration(milliseconds: 40),
                  onTap: () => _alreadyWatched(context, theme),
                ),
              ),
              Expanded(
                child: _ChoiceHalf(
                  icon: _watchingNowIcon(theme),
                  iconColor: SeenlyPalette.periwinkle,
                  title: 'watching now'.tr,
                  subtitle: _watchingNowSubtitle(theme).tr,
                  background: SeenlyPalette.periwinkle.withOpacity(0.08),
                  contentAlignment: const Alignment(0, -0.35),
                  entranceDelay: const Duration(milliseconds: 90),
                  onTap: () => _watchingNow(context, theme),
                ),
              ),
            ],
          ),
          // The poster + title, floating right on the seam between the
          // two halves — the one piece of context both choices share.
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Entrance(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('how far in are we?'.tr, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                      const SizedBox(height: 10),
                      _PosterSeamCard(item: item),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: Entrance(
              riseBy: 10,
              child: _RoundBackButton(onTap: () => Navigator.of(context).pop()),
            ),
          ),
          if (showBanner)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 14,
              child: Entrance(
                delay: const Duration(milliseconds: 160),
                riseBy: 18,
                child: _QuickLogBanner(
                  onLogNow: () => _quickLog(context),
                  onDismiss: () async {
                    await context.read<RitualPrefsService>().dismissBanner();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("won't ask again — turn on \"skip the ritual\" in settings any time".tr),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One full-bleed half of the split screen — a single large tap target
/// rather than a small card, so either choice is easy to hit anywhere
/// in its half. [contentAlignment] nudges the icon/title toward the
/// outer edge of each half (away from the seam) so neither half's
/// content crowds the floating poster card in the middle.
class _ChoiceHalf extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color background;
  final Alignment contentAlignment;
  final Duration entranceDelay;
  final VoidCallback onTap;
  const _ChoiceHalf({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.contentAlignment,
    this.entranceDelay = Duration.zero,
    required this.onTap,
  });

  @override
  State<_ChoiceHalf> createState() => _ChoiceHalfState();
}

class _ChoiceHalfState extends State<_ChoiceHalf> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        color: Color.alphaBlend(
          widget.iconColor.withOpacity(_pressed ? 0.06 : 0),
          widget.background,
        ),
        child: Align(
          alignment: widget.contentAlignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Entrance(
              delay: widget.entranceDelay,
              riseBy: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: widget.iconColor.withOpacity(0.14), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Icon(widget.icon, size: 24, color: widget.iconColor),
                  ),
                  const SizedBox(height: 14),
                  Text(widget.title, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(widget.subtitle,
                      textAlign: TextAlign.center,
                      style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Poster + title, floating on the seam between the two halves —
/// `width: double.infinity` inside a horizontally-padded, centered
/// parent so the title text has an actual bound to wrap/ellipsis
/// against instead of trying to size to its own unconstrained content.
class _PosterSeamCard extends StatelessWidget {
  final MediaItem item;
  const _PosterSeamCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.16), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40,
              height: 56,
              child: item.posterUrl != null
                  ? FadeInNetworkImage(
                      url: item.posterUrl!,
                      fit: BoxFit.cover,
                      placeholder: Container(color: SeenlyPalette.mediaColor(item.mediaType)),
                    )
                  : Container(color: SeenlyPalette.mediaColor(item.mediaType)),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('logging'.tr, style: SeenlyText.metaLabel),
                const SizedBox(height: 2),
                Text(item.title.display,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(italic: true, size: 14.5, weight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RoundBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: SeenlyPalette.paper.withOpacity(0.92),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
      ),
    );
  }
}

/// Floating card offering a way out of the seat/venue/ticket ritual
/// entirely — one tap logs the evening right now, no animations. The X
/// hides this banner for good (see [RitualPrefsService.dismissBanner]);
/// the standing way to get the same instant behavior back afterward is
/// the "skip the ritual" toggle in settings, which this banner's own
/// snackbar (see WatchingChoiceScreen.build) points to.
class _QuickLogBanner extends StatelessWidget {
  final VoidCallback onLogNow;
  final VoidCallback onDismiss;
  const _QuickLogBanner({required this.onLogNow, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.16), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "don't want the seats, the tickets, any of it?".tr,
                  style: SeenlyText.serif(size: 12.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  'skip the ritual — just log it now'.tr,
                  style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
                ),
                const SizedBox(height: 8),
                PressScale(
                  onTap: onLogNow,
                  child: Text(
                    'log it now →'.tr,
                    style: SeenlyText.serif(size: 12.5, weight: FontWeight.w600, color: SeenlyPalette.accent),
                  ),
                ),
              ],
            ),
          ),
          PressScale(
            onTap: onDismiss,
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 16, color: SeenlyPalette.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}
