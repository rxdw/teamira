import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/diary_entry.dart';
import '../services/log_theme_service.dart';
import 'boarding_drop_overlay.dart';
import 'coach_seat_overlay.dart';
import 'coach_submit_button.dart';
import 'evening_road.dart';
import 'garden_bed.dart';
import 'garden_drop_overlay.dart';
import 'garden_seed_overlay.dart';
import 'garden_submit_button.dart';
import 'seat_picker_overlay.dart';
import 'ticket_drop_overlay.dart';
import 'ticket_jar.dart';
import 'ticket_submit_button.dart';

/// The one place that knows all three themes exist. Every screen that
/// used to call the ticket widgets directly calls these instead, so
/// picking a theme in Settings changes the seat/coach-seat/planting
/// ritual, the tear/stamp/bloom moment, the jar/board/garden, and the
/// submit button everywhere at once — nothing left half-dressed in an
/// old theme.

/// Pre-log ritual: the cinema's seat, or the coach's seat, depending
/// on the current [LogTheme]. [runtimeMinutes] only matters for the
/// coach theme, where it decides the route.
Future<void> showPreLogRitual(
  BuildContext context, {
  required String title,
  required String mediaType,
  int? runtimeMinutes,
}) {
  final theme = context.read<LogThemeService>().theme;
  return switch (theme) {
    LogTheme.coach =>
      showCoachSeat(context, title: title, mediaType: mediaType, runtimeMinutes: runtimeMinutes),
    LogTheme.ticket => showSeatPicker(context, title: title, mediaType: mediaType),
    LogTheme.garden => showGardenPlant(context, title: title, mediaType: mediaType),
  };
}

/// Post-log ritual: tearing the ticket, or tearing the boarding pass
/// at the gate.
Future<void> showLogDrop(
  BuildContext context, {
  required String title,
  required String mediaType,
  required int? rating,
  required DateTime watchedAt,
  int? runtimeMinutes,
}) {
  final theme = context.read<LogThemeService>().theme;
  return switch (theme) {
    LogTheme.coach => showBoardingDrop(context,
        title: title, mediaType: mediaType, rating: rating, watchedAt: watchedAt, runtimeMinutes: runtimeMinutes),
    LogTheme.ticket =>
      showTicketDrop(context, title: title, mediaType: mediaType, rating: rating, watchedAt: watchedAt),
    LogTheme.garden => showBloomDrop(context,
        title: title, mediaType: mediaType, rating: rating, watchedAt: watchedAt, runtimeMinutes: runtimeMinutes),
  };
}

/// The Diary tab's centerpiece: the ticket jar, or the route board.
class DiaryCenterpiece extends StatelessWidget {
  final List<DiaryEntry> entries;
  const DiaryCenterpiece({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    return switch (theme) {
      LogTheme.coach => RouteBoard(entries: entries),
      LogTheme.ticket => TicketJar(entries: entries),
      LogTheme.garden => GardenBox(entries: entries),
    };
  }
}

/// The "save this evening" / "log another evening" button: a ticket,
/// or a little coach.
class LogSubmitButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const LogSubmitButton({super.key, required this.label, this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    return switch (theme) {
      LogTheme.coach => CoachSubmitButton(label: label, onTap: onTap, loading: loading),
      LogTheme.ticket => TicketSubmitButton(label: label, onTap: onTap, loading: loading),
      LogTheme.garden => GardenSubmitButton(label: label, onTap: onTap, loading: loading),
    };
  }
}
