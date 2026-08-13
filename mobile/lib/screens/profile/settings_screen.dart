import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/coview_prefs_service.dart';
import '../../models/profile_stats.dart';
import '../../services/locale_service.dart';
import '../../services/log_theme_service.dart';
import '../../services/map_style_service.dart';
import '../../services/rabbit_mascot_prefs_service.dart';
import '../../services/ritual_prefs_service.dart';
import '../../services/sources_display_prefs_service.dart';
import '../../services/spoiler_prefs_service.dart';
import '../../services/theme_prefs_service.dart';
import '../../services/today_pick_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import 'integrations_screen.dart';
import '../import/import_screen.dart';
import '../../widgets/rabbit_mascot.dart';
import '../../widgets/region_picker_sheet.dart';
import '../../widgets/themed_loading_indicator.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loggingOut = false;

  Future<void> _confirmLogout() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('close this diary for now?',
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 16)),
            const SizedBox(height: 6),
            Text(
              "everything you've logged stays right where it is — you'll pick up from here next time",
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Text('log out',
                    style: SeenlyText.serif(
                        italic: true, color: SeenlyPalette.accentOnAccent)),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                child: Text('stay',
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _loggingOut = true);
    await context.read<AppState>().logout();
    // No further navigation needed — AppState.logout() flips `status` to
    // signedOut, and the root _AuthGate (see app.dart) swaps straight to
    // LoginScreen on its own.
  }

  Future<void> _chooseLogTheme(BuildContext context, LogTheme current) async {
    final service = context.read<LogThemeService>();
    final chosen = await showModalBottomSheet<LogTheme>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('how should logging feel?',
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 16)),
            const SizedBox(height: 6),
            Text(
              'same diary either way — just a different little ritual',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 18),
            _ThemeChoiceRow(
              icon: Icons.local_activity_outlined,
              label: 'a ticket, torn open',
              selected: current == LogTheme.ticket,
              onTap: () => Navigator.of(context).pop(LogTheme.ticket),
            ),
            const SizedBox(height: 10),
            _ThemeChoiceRow(
              icon: Icons.train,
              label: 'an evening route, by train',
              selected: current == LogTheme.coach,
              onTap: () => Navigator.of(context).pop(LogTheme.coach),
            ),
            const SizedBox(height: 10),
            _ThemeChoiceRow(
              icon: Icons.local_florist_outlined,
              label: 'a window garden, in bloom',
              selected: current == LogTheme.garden,
              onTap: () => Navigator.of(context).pop(LogTheme.garden),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('never mind',
                    textAlign: TextAlign.center,
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) await service.setTheme(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Text('settings', style: SeenlyText.screenTitle),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Everything below the header scrolls — this used to be a
            // plain Column with a Spacer pushing the "teamira · v0.1.0"
            // footer to the bottom, which only worked while the content
            // above happened to be short enough to fit one screen. Adding
            // the map style section pushed it past that, and a Spacer
            // inside an unbounded/overflowing Column doesn't scroll, it
            // just clips — hence "bottom overflowed" with no way to pull
            // the rest into view. Expanded+SingleChildScrollView here
            // (with the footer's spacing now a fixed SizedBox instead of
            // a Spacer, since Spacer needs a bounded height a scroll view
            // doesn't give it) fixes that regardless of how tall the
            // content ends up being on a given device.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('account', style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: SeenlyPalette.accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        (user?.username.isNotEmpty ?? false)
                            ? user!.username.substring(0, 1).toUpperCase()
                            : '?',
                        style: SeenlyText.serif(
                            size: 15, color: SeenlyPalette.accentOnAccent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(user?.username ?? '', style: SeenlyText.cardTitle),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('privacy', style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: _PrivacySettingsCard(),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('connections', style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.sync_outlined,
              label: 'auto-tracking',
              subtitle: 'Plex, Jellyfin, Kodi, browser extension',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IntegrationsScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.move_to_inbox_outlined,
              label: 'import your history',
              subtitle: 'bring over a list from Letterboxd or elsewhere',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImportScreen()),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('your sources', style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final sourcesPrefs = context.watch<SourcesDisplayPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.smart_display_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('mix your sources into the main list?',
                                style: SeenlyText.serif(size: 13)),
                          ),
                          Switch(
                            value: sourcesPrefs.mergeIntoMainList,
                            activeColor: SeenlyPalette.accent,
                            onChanged: (value) =>
                                context.read<SourcesDisplayPrefsService>().setMergeIntoMainList(value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'your YouTube and Twitch sources will show up alongside movies and '
                          'shows in watched, watching, and plan to watch — heads up, they can '
                          'look a little off there, since a source opens the video itself '
                          'instead of a title page',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('co-viewing', style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final coViewPrefs = context.watch<CoViewPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.favorite_border, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('add matches to my own list too?',
                                style: SeenlyText.serif(size: 13)),
                          ),
                          Switch(
                            value: coViewPrefs.addMatchesToOwnList,
                            activeColor: SeenlyPalette.accent,
                            onChanged: (value) =>
                                context.read<CoViewPrefsService>().setAddMatchesToOwnList(value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'when a Watch Together match happens — one phone or over the '
                          'network — it always shows up on your shared co-viewing screen '
                          'if you have a partner linked. This only controls whether it '
                          'also gets added to your own personal "watch together" list.',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('spoilers', style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final spoilerPrefs = context.watch<SpoilerPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_movies_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('blur the synopsis', style: SeenlyText.serif(size: 13)),
                          ),
                          Switch(
                            value: spoilerPrefs.blurDescriptions,
                            activeColor: SeenlyPalette.accent,
                            onChanged: (value) =>
                                context.read<SpoilerPrefsService>().setBlurDescriptions(value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'off by default — a title\'s synopsis is usually written not to '
                          'give anything away, so there\'s nothing to hide from unless you '
                          'turn this on.',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(height: 1, color: SeenlyPalette.border),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.rate_review_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('blur written reviews', style: SeenlyText.serif(size: 13)),
                          ),
                          Switch(
                            value: spoilerPrefs.blurReviews,
                            activeColor: SeenlyPalette.accent,
                            onChanged: (value) =>
                                context.read<SpoilerPrefsService>().setBlurReviews(value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'on by default — other people\'s reviews say what they want, so '
                          'each one stays softly covered until you tap it. Turn this off if '
                          'you\'d rather just read them straight away.',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text("today's pick", style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final todayPickPrefs = context.watch<TodayPickPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_movies_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('show today\'s pick on Home', style: SeenlyText.serif(size: 13)),
                          ),
                          Switch(
                            value: todayPickPrefs.enabled,
                            activeColor: SeenlyPalette.accent,
                            onChanged: (value) =>
                                context.read<TodayPickPrefsService>().setEnabled(value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'a franchise to marathon, picked fresh most days, with a little '
                          'progress bar for however much of it you\'ve already seen — there\'s '
                          'a shuffle button on the card itself if it\'s not your thing that day. '
                          'turn this off if you\'d rather Home stayed without it.',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('language', style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final locale = context.watch<LocaleService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Text('🇷🇺', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('show titles in Russian', style: SeenlyText.serif(size: 13)),
                            const SizedBox(height: 2),
                            Text(
                              'when TMDB has a translation for it — otherwise English',
                              style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: locale.preferRussian,
                        activeColor: SeenlyPalette.accent,
                        onChanged: (value) =>
                            context.read<LocaleService>().setPreferRussian(value),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final locale = context.watch<LocaleService>();
              final current = kRegionOptions.firstWhere(
                (o) => o.code == locale.region,
                orElse: () => kRegionOptions.first,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: GestureDetector(
                  onTap: () => showRegionPickerSheet(context),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SeenlyPalette.paper,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.public, size: 18, color: SeenlyPalette.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('streaming region', style: SeenlyText.serif(size: 13)),
                              const SizedBox(height: 2),
                              Text(
                                'which country\'s services show under "where to watch" '
                                '— Kinopoisk, ivi, Netflix, and the rest all vary by country',
                                style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                              ),
                            ],
                          ),
                        ),
                        Text(current.label, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 15, color: SeenlyPalette.inkFaint),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('map style', style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final mapStyle = context.watch<MapStyleService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.layers_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Text('how the route map looks', style: SeenlyText.serif(size: 13)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'same choice as the layers button on the route map itself',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final info in MapStyleCatalog.all)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _MapStyleSwatchButton(
                                  info: info,
                                  selected: info.style == mapStyle.style,
                                  onTap: () => context.read<MapStyleService>().setStyle(info.style),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('this diary', style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final logTheme = context.watch<LogThemeService>().theme;
              final (icon, subtitle) = switch (logTheme) {
                LogTheme.coach => (Icons.train, 'an evening route, boarded and torn at the gate'),
                LogTheme.ticket => (Icons.local_activity_outlined, 'a little cinema, ticket torn for each evening'),
                LogTheme.garden => (Icons.local_florist_outlined, 'a window garden, a flower grown for each evening'),
              };
              return _SettingsTile(
                icon: icon,
                label: 'logging ritual',
                subtitle: subtitle,
                onTap: () => _chooseLogTheme(context, logTheme),
              );
            }),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final ritualPrefs = context.watch<RitualPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_outlined, size: 17, color: SeenlyPalette.inkMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('skip the ritual', style: SeenlyText.serif(size: 13)),
                            const SizedBox(height: 2),
                            Text(
                              'no seats, no tickets, no animations — every log just happens instantly',
                              style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: ritualPrefs.skipRitual,
                        activeColor: SeenlyPalette.accent,
                        onChanged: (value) => context.read<RitualPrefsService>().setSkipRitual(value),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final mascotPrefs = context.watch<RabbitMascotPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 64,
                          height: 44,
                          child: OverflowBox(
                            // RabbitMascot's own intrinsic height —
                            // 742x1153 canvas (see widgets/rabbit_mascot.dart) —
                            // taller and narrower than the old fixed
                            // mascot art this preview was tuned for.
                            minHeight: 64 / (742 / 1153),
                            maxHeight: 64 / (742 / 1153),
                            child: const RabbitMascot(size: 64),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('rabbit companion', style: SeenlyText.serif(size: 13)),
                            const SizedBox(height: 2),
                            Text(
                              'a little guide on empty screens, loading, and milestones',
                              style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: mascotPrefs.enabled,
                        activeColor: SeenlyPalette.accent,
                        onChanged: (value) => context.read<RabbitMascotPrefsService>().setEnabled(value),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final themePrefs = context.watch<ThemePrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.nights_stay_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Text('appearance', style: SeenlyText.serif(size: 13)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'dark mode is early — for now it just changes the rabbit',
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final option in _themeOptions)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _ThemeOptionButton(
                                  icon: option.icon,
                                  label: option.label,
                                  selected: option.mode == themePrefs.mode,
                                  onTap: () => context.read<ThemePrefsService>().setMode(option.mode),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: GestureDetector(
                onTap: _loggingOut ? null : _confirmLogout,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SeenlyPalette.coral.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 17, color: SeenlyPalette.coral),
                      const SizedBox(width: 10),
                      Text('log out',
                          style: SeenlyText.serif(italic: true, color: SeenlyPalette.coral)),
                      const Spacer(),
                      if (_loggingOut)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: ThemedLoadingIndicator(
                              strokeWidth: 2, color: SeenlyPalette.coral),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Center(
                child: Column(
                  children: [
                    Text('teamira · v0.1.0',
                        style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
                    const SizedBox(height: 3),
                    Text('formerly seenly — same diary, new name',
                        style: SeenlyText.serif(
                            italic: true, size: 10, color: SeenlyPalette.placeholder)),
                  ],
                ),
              ),
            ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeChoiceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChoiceRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent.withOpacity(0.12) : SeenlyPalette.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? SeenlyPalette.accent : SeenlyPalette.border, width: selected ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: selected ? SeenlyPalette.accent : SeenlyPalette.inkMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: SeenlyText.serif(
                      size: 13, color: selected ? SeenlyPalette.ink : SeenlyPalette.inkMuted)),
            ),
            if (selected) Icon(Icons.check_circle, size: 17, color: SeenlyPalette.accent),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool interactive;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.interactive = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: GestureDetector(
        onTap: interactive ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: SeenlyPalette.inkMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: SeenlyText.serif(size: 13)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                    ],
                  ],
                ),
              ),
              if (interactive)
                const Icon(Icons.chevron_right, size: 17, color: SeenlyPalette.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOption {
  final ThemeMode mode;
  final IconData icon;
  final String label;
  const _ThemeOption(this.mode, this.icon, this.label);
}

const _themeOptions = [
  _ThemeOption(ThemeMode.system, Icons.brightness_auto_outlined, 'system'),
  _ThemeOption(ThemeMode.light, Icons.light_mode_outlined, 'light'),
  _ThemeOption(ThemeMode.dark, Icons.dark_mode_outlined, 'dark'),
];

/// One tappable option for the "appearance" settings row — same
/// selected/unselected treatment as [_MapStyleSwatchButton] just below,
/// minus the color swatch (there's no dark palette yet to preview).
class _ThemeOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOptionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: SeenlyPalette.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? SeenlyPalette.accent : SeenlyPalette.border,
                  width: selected ? 2 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon,
                  size: 18, color: selected ? SeenlyPalette.accent : SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: SeenlyText.mono(
                    size: 9,
                    color: selected ? SeenlyPalette.ink : SeenlyPalette.inkMuted,
                    weight: selected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// One tappable swatch + label for the "map style" settings row — same
/// four options and the same color key as _MapStyleSheet on the route
/// map itself (see screens/add_entry/journey_progress_screen.dart),
/// just stacked vertically to fit four across a settings-width row.
class _MapStyleSwatchButton extends StatelessWidget {
  final MapStyleInfo info;
  final bool selected;
  final VoidCallback onTap;
  const _MapStyleSwatchButton({required this.info, required this.selected, required this.onTap});

  static const _swatchColors = {
    MapStyle.classic: Color(0xFFAAD3DF),
    MapStyle.paper: Color(0xFFE8E0D0),
    MapStyle.night: Color(0xFF1B1F2A),
    MapStyle.terrain: Color(0xFFC9DCA8),
  };

  @override
  Widget build(BuildContext context) {
    final color = _swatchColors[info.style]!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? SeenlyPalette.accent : SeenlyPalette.border,
                  width: selected ? 2 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Icon(Icons.check_circle,
                      size: 16,
                      color: info.style == MapStyle.night ? SeenlyPalette.paper : SeenlyPalette.accent)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(info.label,
                style: SeenlyText.mono(
                    size: 9,
                    color: selected ? SeenlyPalette.ink : SeenlyPalette.inkMuted,
                    weight: selected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// Per-shelf visibility — who can see this account's watched / watching
/// now / plan to watch (see models.User.privacy_watched/watching/
/// planned on the backend). Its own dedicated block, separate from
/// every other toggle on this screen, since it's the one section that
/// controls what *other people* can see rather than how the app itself
/// behaves. Ships open ("everyone" on all three) — someone has to
/// deliberately dial it back.
class _PrivacySettingsCard extends StatefulWidget {
  const _PrivacySettingsCard();

  @override
  State<_PrivacySettingsCard> createState() => _PrivacySettingsCardState();
}

class _PrivacySettingsCardState extends State<_PrivacySettingsCard> {
  ProfileMe? _me;
  bool _loading = true;
  PrivacyShelf? _saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await context.read<AppState>().profile.me();
      if (!mounted) return;
      setState(() {
        _me = me;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setLevel(PrivacyShelf shelf, PrivacyLevel level) async {
    final me = _me;
    if (me == null || _saving != null) return;
    setState(() => _saving = shelf);
    try {
      final updated = await context.read<AppState>().profile.updateMe(
            privacyWatched: shelf == PrivacyShelf.watched ? level.wireValue : null,
            privacyWatching: shelf == PrivacyShelf.watching ? level.wireValue : null,
            privacyPlanned: shelf == PrivacyShelf.planned ? level.wireValue : null,
            privacyFavorites: shelf == PrivacyShelf.favorites ? level.wireValue : null,
          );
      if (!mounted) return;
      setState(() {
        _me = updated;
        _saving = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("that didn't save — try again")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _loading || me == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(height: 16, width: 16, child: ThemedLoadingIndicator(strokeWidth: 2)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'who can see what you\'ve watched, are watching now, plan to watch, or have marked as a favorite',
                  style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
                ),
                const SizedBox(height: 12),
                _PrivacyRow(
                  label: 'watched',
                  icon: Icons.check_circle_outline,
                  value: PrivacyLevelWire.fromWire(me.privacyWatched),
                  saving: _saving == PrivacyShelf.watched,
                  onChanged: (level) => _setLevel(PrivacyShelf.watched, level),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: SeenlyPalette.border),
                const SizedBox(height: 12),
                _PrivacyRow(
                  label: 'watching now',
                  icon: Icons.play_circle_outline,
                  value: PrivacyLevelWire.fromWire(me.privacyWatching),
                  saving: _saving == PrivacyShelf.watching,
                  onChanged: (level) => _setLevel(PrivacyShelf.watching, level),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: SeenlyPalette.border),
                const SizedBox(height: 12),
                _PrivacyRow(
                  label: 'plan to watch',
                  icon: Icons.bookmark_border,
                  value: PrivacyLevelWire.fromWire(me.privacyPlanned),
                  saving: _saving == PrivacyShelf.planned,
                  onChanged: (level) => _setLevel(PrivacyShelf.planned, level),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: SeenlyPalette.border),
                const SizedBox(height: 12),
                _PrivacyRow(
                  label: 'favorite films',
                  icon: Icons.favorite_border,
                  value: PrivacyLevelWire.fromWire(me.privacyFavorites),
                  saving: _saving == PrivacyShelf.favorites,
                  onChanged: (level) => _setLevel(PrivacyShelf.favorites, level),
                ),
              ],
            ),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final PrivacyLevel value;
  final bool saving;
  final ValueChanged<PrivacyLevel> onChanged;
  const _PrivacyRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.saving,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: SeenlyPalette.inkMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: SeenlyText.serif(size: 13))),
            if (saving)
              const SizedBox(
                  width: 13, height: 13, child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent)),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final level in PrivacyLevel.values)
                GestureDetector(
                  onTap: saving ? null : () => onChanged(level),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: value == level ? SeenlyPalette.accent : SeenlyPalette.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      level.label,
                      style: SeenlyText.mono(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: value == level ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
