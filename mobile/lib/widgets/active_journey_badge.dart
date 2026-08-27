import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/active_journey.dart';
import '../screens/add_entry/journey_progress_screen.dart';
import '../services/app_translations.dart';
import '../services/log_theme_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

String _fmtElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

(IconData, Color, String) _visuals(LogTheme theme) => switch (theme) {
      LogTheme.coach => (Icons.train, SeenlyPalette.periwinkle, 'still on the road'),
      LogTheme.garden => (Icons.directions_walk, SeenlyPalette.sage, 'still out in the garden'),
      LogTheme.ticket => (Icons.flight, SeenlyPalette.coral, 'still in the air'),
      LogTheme.shuttle => (Icons.rocket_launch, SeenlyPalette.periwinkle, 'still in orbit'),
    };

/// Reopens a journey's full "in progress" screen — the same push both
/// this badge and the "watching now" list use, so tapping a card there
/// lands on the exact same map/route screen as tapping the badge does.
void openActiveJourney(BuildContext context, ActiveJourney journey) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => JourneyProgressScreen(
        item: journey.item,
        theme: journey.theme,
        routeLabel: journey.routeLabel,
        routeDetail: journey.routeDetail,
        routeMinutes: journey.routeMinutes,
        originLat: journey.originLat,
        originLng: journey.originLng,
        destLat: journey.destLat,
        destLng: journey.destLng,
      ),
    ),
  );
}

/// A small persistent pill that surfaces whenever a "watching now"
/// journey is running behind whatever's currently on screen — the
/// honest fix for backing out of [JourneyProgressScreen] by accident.
/// The timer never actually stopped (see [ActiveJourney]'s doc
/// comment); this is how the person finds their way back to it
/// instead of it quietly vanishing. Mount once near the app's root
/// (see RootShell) so it's visible no matter which tab is open.
class ActiveJourneyBadge extends StatefulWidget {
  const ActiveJourneyBadge({super.key});

  @override
  State<ActiveJourneyBadge> createState() => _ActiveJourneyBadgeState();
}

class _ActiveJourneyBadgeState extends State<ActiveJourneyBadge> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Just for the elapsed-time readout to keep counting up while the
    // badge sits there — each journey's actual progress lives entirely
    // in its own AppState.activeJourneys entry, not in this timer.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<AppState>().activeJourneysList;
    if (journeys.isEmpty) return const SizedBox.shrink();
    final journey = journeys.first; // newest-first — see activeJourneysList
    final extraCount = journeys.length - 1;
    final (themeIcon, color, label) = _visuals(journey.theme);
    final icon = journey.isPaused ? Icons.pause_circle_outline : themeIcon;
    final elapsed = journey.elapsedAt(DateTime.now());

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Material(
            color: SeenlyPalette.ink,
            borderRadius: BorderRadius.circular(999),
            elevation: 3,
            shadowColor: Colors.black.withOpacity(0.3),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => openActiveJourney(context, journey),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(
                        '${journey.isPaused ? 'paused'.tr : label.tr} · ${journey.item.title.display}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_fmtElapsed(elapsed),
                        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper.withOpacity(0.6))),
                    if (extraCount > 0) ...[
                      const SizedBox(width: 6),
                      Text('+$extraCount',
                          style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper.withOpacity(0.6))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
