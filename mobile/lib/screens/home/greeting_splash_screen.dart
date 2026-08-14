import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/diary_entry.dart';
import '../../services/log_theme_service.dart';
import '../../services/rabbit_mascot_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/log_theme_copy.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/rabbit_mascot.dart';
import '../../widgets/wow_motion.dart' show Entrance, FadeInNetworkImage, PressScale;

/// The very first thing a signed-in person sees on each cold launch —
/// a full-bleed "good evening, you're still on {last title}" front door,
/// before the tab shell itself. See app.dart's `_GreetingGate`, which
/// swaps this out for [RootShell] the moment `onEnter` fires (tapping
/// the main button or one of the quick jumps below), landing on
/// whichever tab was tapped.
///
/// Purely a mood-setting entrance, not a data screen of its own — the
/// last-logged title/poster it shows is already visible on Home and the
/// diary; this just gives the app one calm moment before the feed,
/// dressed in whatever [LogTheme] the person's already chosen (see
/// theme/log_theme_copy.dart) instead of reusing the ticket look
/// specifically.
class GreetingSplashScreen extends StatefulWidget {
  final void Function(int initialTab) onEnter;
  const GreetingSplashScreen({super.key, required this.onEnter});

  @override
  State<GreetingSplashScreen> createState() => _GreetingSplashScreenState();
}

class _GreetingSplashScreenState extends State<GreetingSplashScreen> {
  late final Future<DiaryEntry?> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadLast();
  }

  Future<DiaryEntry?> _loadLast() async {
    try {
      // Same list the Home tab and Diary tab already fetch, ordered
      // most-recent-first (see backend/app/routers/diary.py) — no new
      // endpoint needed, just the first row.
      final entries = await context.read<AppState>().diary.list();
      return entries.isNotEmpty ? entries.first : null;
    } catch (_) {
      // Best-effort — a failed fetch just means a generic greeting with
      // no title/poster behind it, never a blocked launch.
      return null;
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'still up?';
    if (hour < 12) return 'good morning';
    if (hour < 18) return 'good afternoon';
    return 'good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    final accent = switch (theme) {
      LogTheme.coach => SeenlyPalette.periwinkle,
      LogTheme.garden => SeenlyPalette.sage,
      LogTheme.ticket => SeenlyPalette.coral,
    };

    return Scaffold(
      backgroundColor: SeenlyPalette.ink,
      body: FutureBuilder<DiaryEntry?>(
        future: _future,
        builder: (context, snapshot) {
          final last = snapshot.data;
          final hasTitle = last != null;

          final posterHeight = MediaQuery.of(context).size.height * 0.82;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Layer 1 — last-watched poster, softly blurred and
              // darkened, filling most of the screen down to just
              // above the "into the diary" button (not the whole
              // screen, and not a tiny blurred patch either).
              // Quietly absent (falls back to plain ink) when
              // there's nothing logged yet or the image fails —
              // never a broken-image icon on someone's very first
              // screen.
              if (last?.posterUrl != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: posterHeight,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: FadeInNetworkImage(
                            url: last!.posterUrl!,
                            fit: BoxFit.cover,
                            duration: const Duration(milliseconds: 420),
                            placeholder: Container(color: SeenlyPalette.ink),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.0, 0.45, 0.85, 1.0],
                              colors: [
                                SeenlyPalette.ink.withOpacity(0.35),
                                SeenlyPalette.ink.withOpacity(0.45),
                                SeenlyPalette.ink.withOpacity(0.8),
                                SeenlyPalette.ink,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(26, 20, 26, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (context.watch<RabbitMascotPrefsService>().enabled)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Entrance(
                              riseBy: 16,
                              child: RabbitMascot(mood: RabbitMood.content, size: 52),
                            ),
                          ),
                        ),
                      Entrance(
                        delay: const Duration(milliseconds: 70),
                        child: Row(
                          children: [
                            Icon(LogThemeCopy.navIcon(theme, active: true),
                                size: 16, color: accent),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                hasTitle ? '${_greeting()}, you\'re still on' : _greeting(),
                                style: SeenlyText.serif(
                                    italic: true, size: 14, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Entrance(
                        delay: const Duration(milliseconds: 130),
                        riseBy: 20,
                        child: Text(
                          hasTitle ? last!.displayTitle : 'your diary is waiting',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(
                              size: 34, weight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                      const Spacer(),
                      Entrance(
                        delay: const Duration(milliseconds: 220),
                        riseBy: 16,
                        child: PressScale(
                          onTap: () => widget.onEnter(1), // Diary tab
                          haptics: true,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: SeenlyPalette.paper,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            alignment: Alignment.center,
                            child: Text('into the diary',
                                style: SeenlyText.mono(
                                    size: 12, color: SeenlyPalette.ink, weight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Entrance(
                        delay: const Duration(milliseconds: 270),
                        riseBy: 14,
                        child: Row(
                          children: [
                            Expanded(
                                child: _QuickJump(label: 'home', onTap: () => widget.onEnter(0))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _QuickJump(
                                    label: 'discover', onTap: () => widget.onEnter(2))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _QuickJump(
                                    label: 'profile', onTap: () => widget.onEnter(3))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The three "jump straight there" rows a map screen would've spent on
/// Mine/Trends/World — Home's own feed, Collections' browse shelves,
/// and Profile, all one tap away without landing on Home first.
class _QuickJump extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickJump({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: SeenlyText.mono(size: 11, color: Colors.white, weight: FontWeight.w600)),
      ),
    );
  }
}

