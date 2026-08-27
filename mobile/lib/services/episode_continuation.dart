import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../models/series_route_state.dart';
import '../screens/add_entry/journey_progress_screen.dart';
import '../screens/add_entry/journey_select_screen.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'journey_transfer_service.dart';
import 'log_theme_service.dart';
import 'series_route_prefs_service.dart';
import '../widgets/themed_loading_indicator.dart';
import 'app_translations.dart';

/// Above this gap since the last episode finished, the confirmation
/// reads as "pick this back up?" (naming where it left off) rather than
/// "keep going?" (see spec points 5 vs 6) — the same continue-or-fresh
/// decision either way, just worded for how long it's actually been.
const Duration _immediateContinuationWindow = Duration(minutes: 45);

/// Starts watching one specific episode — the actual entry point for
/// "watch next episode" buttons (see series_episodes_sheet.dart), and
/// also what [WatchingChoiceScreen]'s "watching now" half defers to for
/// an episode-level log (season/episode both set) instead of always
/// showing the full picker — see that screen's own `_watchingNow`.
///
/// - First episode of a season, or nothing saved for this series yet →
///   the full picker, same as starting any title fresh (spec point 7).
/// - Picking up again soon after the last one → a quick "watch the next
///   episode?" nudge (spec point 5).
/// - Picking up after a real gap → "continue from {place}?" naming
///   where it left off (spec point 6).
/// - Either confirmation's "yes" skips the picker entirely and boards
///   the transfer leg [buildTransfer] already worked out.
///
/// Returns the same three-way result the rating flow itself returns
/// (see [JourneyProgressScreen._imBack]'s own doc comment) — `true` once
/// an entry's actually saved, `false` if the person tore up the journey
/// outright, `null` if nothing happened (picker/sheet dismissed, or the
/// "not now" branch) — so callers that need to know whether to close
/// themselves or refresh (like [WatchingChoiceScreen]) can just forward
/// it on rather than guessing from a void return.
Future<bool?> startEpisodeJourney(
  BuildContext context, {
  required MediaItem item,
  required LogTheme theme,
  required int season,
  required int episode,
}) async {
  final prefs = SeriesRoutePrefsService();
  final saved = await prefs.load(item.source, item.id);

  if (saved == null || saved.theme != theme) {
    // No stop to transfer from (or the person's since switched the
    // app's whole theme, which makes an old stop meaningless) — same
    // full picker as watching episode one.
    if (!context.mounted) return null;
    return _openFullPicker(context, item: item, theme: theme, season: season, episode: episode);
  }

  final gap = DateTime.now().difference(saved.finishedAt);
  final immediate = gap <= _immediateContinuationWindow;

  if (!context.mounted) return null;
  final choice = await _showContinuationSheet(context, theme: theme, saved: saved, immediate: immediate);

  if (choice == _ContinuationChoice.continueTransfer) {
    if (!context.mounted) return null;
    // buildTransfer's coach/train case makes a real network call to
    // find the next real station (capped at 6s now — see
    // journey_transfer_service.dart's own comment — but still not
    // instant), and until this overlay was added there was *nothing*
    // on screen between tapping "yes, continue" and the next route
    // appearing, which read as the button doing nothing at all.
    _showRouteLoadingOverlay(context);
    final transfer = await buildTransfer(state: saved, item: item);
    if (!context.mounted) return null;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss the overlay
    if (transfer == null) {
      // The saved stop no longer resolves (a cinema/garden that's
      // since dropped out of the curated list) — fall back exactly as
      // if nothing had been saved, rather than leaving the person stuck.
      if (!context.mounted) return null;
      return _openFullPicker(context, item: item, theme: theme, season: season, episode: episode);
    }
    if (!context.mounted) return null;
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => JourneyProgressScreen(
          item: item,
          theme: theme,
          routeLabel: transfer.routeLabel,
          routeDetail: transfer.routeDetail,
          routeMinutes: transfer.routeMinutes,
          originLat: transfer.originLat,
          originLng: transfer.originLng,
          destLat: transfer.destLat,
          destLng: transfer.destLng,
          season: season,
          episode: episode,
          destMatchKey: transfer.destMatchKey,
        ),
      ),
    );
  }

  if (choice == _ContinuationChoice.startNew) {
    // A deliberate fresh start makes the old stop stale — the episode
    // after this one shouldn't still offer to resume a route this
    // person just said they didn't want.
    await prefs.clear(item.source, item.id);
    if (!context.mounted) return null;
    return _openFullPicker(context, item: item, theme: theme, season: season, episode: episode);
  }

  // `notNow` (only offered in the immediate case) or the sheet got
  // dismissed with no choice made: genuinely nothing happened.
  return null;
}

Future<bool?> _openFullPicker(
  BuildContext context, {
  required MediaItem item,
  required LogTheme theme,
  required int season,
  required int episode,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => JourneySelectScreen(item: item, theme: theme, season: season, episode: episode),
    ),
  );
}

enum _ContinuationChoice { continueTransfer, startNew, notNow }

/// Shown the instant "yes, continue" is tapped, dismissed the instant
/// [buildTransfer] resolves — see the call site's comment above for why
/// this exists: without it, the (capped, but real) network lookup for
/// the next real station left the screen looking like the tap did
/// nothing at all. Not dismissible by tapping outside — this is a "wait
/// a beat" state, not a dialog with a decision to back out of.
void _showRouteLoadingOverlay(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.3),
    builder: (_) => Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
            ),
            const SizedBox(height: 10),
            Text('finding the way…'.tr,
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted)),
          ],
        ),
      ),
    ),
  );
}

String _themeNoun(LogTheme theme) => switch (theme) {
      LogTheme.coach => 'route'.tr,
      LogTheme.ticket => 'trip'.tr,
      LogTheme.garden => 'walk'.tr,
      LogTheme.shuttle => 'launch'.tr,
    };

Future<_ContinuationChoice?> _showContinuationSheet(
  BuildContext context, {
  required LogTheme theme,
  required SeriesRouteState saved,
  required bool immediate,
}) {
  final accent = switch (theme) {
    LogTheme.coach => SeenlyPalette.periwinkle,
    LogTheme.garden => SeenlyPalette.sage,
    LogTheme.ticket => SeenlyPalette.coral,
    LogTheme.shuttle => SeenlyPalette.periwinkle,
  };
  final title = immediate ? 'watch the next episode?'.tr : '${'continue from'.tr} ${saved.stopLabel}?';
  final subtitle = immediate
      ? '${'pick up the same'.tr} ${_themeNoun(theme)} ${'right where it left off'.tr}'
      : '${'last left off at'.tr} ${saved.stopLabel} — ${'pick it back up, or start a fresh'.tr} ${_themeNoun(theme)}';
  final yesLabel = immediate ? 'yes'.tr : 'yes, continue'.tr;
  final noLabel = immediate ? 'not now'.tr : 'start new'.tr;
  final noChoice = immediate ? _ContinuationChoice.notNow : _ContinuationChoice.startNew;

  return showModalBottomSheet<_ContinuationChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text(title, style: SeenlyText.serif(italic: true, size: 18)),
            const SizedBox(height: 6),
            Text(subtitle, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => Navigator.of(sheetContext).pop(_ContinuationChoice.continueTransfer),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(yesLabel,
                    style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.paper)),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(noChoice),
                child: Text(noLabel, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
