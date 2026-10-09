import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import '../../widgets/wow_motion.dart' show PressScale;
import 'package:provider/provider.dart';

import '../../services/coview_prefs_service.dart';
import '../../models/profile_stats.dart';
import '../../services/locale_service.dart';
import '../../services/log_theme_service.dart';
import '../../services/map_style_service.dart';
import '../../services/premium_service.dart';
import '../../services/ritual_prefs_service.dart';
import '../../services/sources_display_prefs_service.dart';
import '../../analytics/analytics.dart';
import '../../services/spoiler_prefs_service.dart';
import '../../services/app_skin_service.dart';
import '../../services/theme_prefs_service.dart';
import '../../theme/seenly_skin.dart';
import '../../services/today_pick_prefs_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../theme/notebook_paper.dart';
import 'account_screen.dart';
import 'integrations_screen.dart';
import 'notification_settings_screen.dart';
import '../legal/eula_screen.dart';
import '../premium/manage_subscription_screen.dart';
import '../premium/premium_screen.dart';
import '../premium/gift_premium_screen.dart';
import '../premium/keepsake_export_screen.dart';
import 'sincerity_screen.dart';
import '../import/import_screen.dart';
import '../../widgets/region_picker_sheet.dart';
import '../../services/app_translations.dart';
import '../../services/api_client.dart';
import '../../services/partner_service.dart';
import '../../services/shared_diary_service.dart';
import '../../models/shared_diary.dart';
import '../../widgets/settings_motion.dart';
import '../../widgets/home_widget_hint_sheet.dart';
import '../partner/album/album_strings.dart' show at;
import '../../widgets/decide_motion.dart' show BouncingDots;
import '../../widgets/soft_motion.dart';
import '../../theme/clay_kit.dart';

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
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('close this diary for now?'.tr,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 16)),
            const SizedBox(height: 6),
            Text(
              "everything you've logged stays right where it is — you'll pick up from here next time".tr,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 20),
            PressScale(
              onTap: () => Navigator.of(context).pop(true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Text('log out'.tr,
                    style: SeenlyText.serif(
                        italic: true, color: SeenlyPalette.accentOnAccent)),
              ),
            ),
            const SizedBox(height: 10),
            PressScale(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                child: Text('stay'.tr,
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
    final isPremium = context.read<PremiumService>().isPremium;
    final chosen = await showModalBottomSheet<LogTheme>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('how should logging feel?'.tr,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 16)),
            const SizedBox(height: 6),
            Text(
              'same diary either way — just a different little ritual'.tr,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 18),
            _ThemeChoiceRow(
              icon: Icons.local_activity_outlined,
              label: 'a ticket, torn open'.tr,
              selected: current == LogTheme.ticket,
              onTap: () => Navigator.of(context).pop(LogTheme.ticket),
            ),
            const SizedBox(height: 10),
            _ThemeChoiceRow(
              icon: Icons.train,
              label: 'an evening route, by train'.tr,
              selected: current == LogTheme.coach,
              onTap: () => Navigator.of(context).pop(LogTheme.coach),
            ),
            const SizedBox(height: 10),
            _ThemeChoiceRow(
              icon: Icons.local_florist_outlined,
              label: 'a window garden, in bloom'.tr,
              selected: current == LogTheme.garden,
              onTap: () => Navigator.of(context).pop(LogTheme.garden),
            ),
            const SizedBox(height: 10),
            _ThemeChoiceRow(
              icon: Icons.rocket_launch_outlined,
              label: 'a shuttle, cleared for launch'.tr,
              selected: current == LogTheme.shuttle,
              locked: !isPremium,
              onTap: () {
                if (!isPremium) {
                  Navigator.of(context).pop();
                  Navigator.of(this.context).push(
                    MaterialPageRoute(builder: (_) => const PremiumScreen()),
                  );
                  return;
                }
                Navigator.of(context).pop(LogTheme.shuttle);
              },
            ),
            const SizedBox(height: 6),
            PressScale(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('never mind'.tr,
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
                    icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Text('settings'.tr, style: SeenlyText.screenTitle),
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
                  children: staggerChildren([
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('account'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: ClayBoxDecoration(
                  boxShadow: SeenlyPalette.flatCardShadow,
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
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
              child: Text('premium'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final premium = context.watch<PremiumService>();
              // A free period unlocks features but isn't a purchase —
              // keep the way to buy visible instead of "premium is on".
              final onTrial = premium.trialActive && !premium.ownsPlan;
              // Someone with a plan of their own gets its management page;
              // a lapsed one with the comeback offer open gets told about
              // it here too, not only on Home.
              final manage = premium.hasSubscription;
              final winback = premium.winbackPercent;
              final String label;
              final String subtitle;
              if (manage) {
                label = premium.isPaused
                    ? 'premium is on a break'.tr
                    : premium.isCancelling
                        ? 'subscription ends soon'.tr
                        : 'premium is on'.tr;
                subtitle = 'pause, cancel or change the plan'.tr;
              } else if (winback != null) {
                label = '${'welcome back offer'.tr}: −$winback%';
                subtitle = 'a personal discount, for a few days only'.tr;
              } else if (onTrial) {
                label = 'free period is on'.tr;
                subtitle = 'tap to keep unlimited after it ends'.tr;
              } else {
                label = premium.isPremium ? 'premium is on'.tr : 'go premium'.tr;
                subtitle = 'unlimited ai asks, favorites, and the shuttle theme'.tr;
              }
              return _SettingsTile(
                icon: Icons.auto_awesome_outlined,
                label: label,
                subtitle: subtitle,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => manage
                      ? const ManageSubscriptionScreen()
                      : const PremiumScreen(),
                )),
              );
            }),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.card_giftcard_outlined,
              label: 'gift a subscription'.tr,
              subtitle: 'a little cheaper than the regular price'.tr,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GiftPremiumScreen())),
            ),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.auto_stories_outlined,
              label: 'keepsake export (pdf)'.tr,
              subtitle: 'your diary or your wrapped, as a pdf to save or print'.tr,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const KeepsakeExportScreen())),
            ),
            // The home-screen widget can only be placed from the phone's own
            // widget picker, so this tile just shows how. Android only, same
            // as the paywall's feature row (premium_screen.dart): the iOS
            // widget target isn't wired up yet.
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
              const SizedBox(height: 10),
              _SettingsTile(
                icon: Icons.widgets_outlined,
                label: at('виджет на главном экране', 'home-screen widget'),
                subtitle: at(
                  'как добавить его на экран телефона',
                  'how to add it to your phone’s home screen',
                ),
                onTap: () => showHomeWidgetHintSheet(context),
              ),
            ],
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('privacy'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: _PrivacySettingsCard(),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _SettingsTile(
                icon: Icons.wb_incandescent_outlined,
                label: 'sincerity points'.tr,
                subtitle: 'private by default — choose whether friends see this number'.tr,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SincerityScreen()),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.notifications_outlined,
              label: 'уведомления'.tr,
              subtitle: 'совпадения, друзья, серия и уровни'.tr,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('connections'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.sync_outlined,
              label: 'auto-tracking'.tr,
              subtitle: 'Plex, Jellyfin, Kodi, browser extension'.tr,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IntegrationsScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.move_to_inbox_outlined,
              label: 'import your history'.tr,
              subtitle: 'bring over a list from Letterboxd or elsewhere'.tr,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImportScreen()),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('your sources'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final sourcesPrefs = context.watch<SourcesDisplayPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.smart_display_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('mix your sources into the main list?'.tr,
                                style: SeenlyText.serif(size: 13)),
                          ),
                          CozySwitch(
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
                          'your YouTube and Twitch sources will show up alongside movies and shows in watched, watching, and plan to watch — heads up, they can look a little off there, since a source opens the video itself instead of a title page'.tr,
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
              child: Text('co-viewing'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final coViewPrefs = context.watch<CoViewPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.favorite_border, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('add matches to my own list too?'.tr,
                                style: SeenlyText.serif(size: 13)),
                          ),
                          CozySwitch(
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
                          'when a Watch Together match happens — one phone or over the network — it always shows up on your shared co-viewing screen if you have a partner linked. This only controls whether it also gets added to your own personal "watch together" list.'.tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            // "Наш дневник" sharing settings — only meaningful once
            // there's an active circle to share into, so this section
            // renders nothing at all otherwise rather than showing three
            // switches that would 409 the moment anyone touched them.
            const _SharedDiarySettingsSection(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('spoilers'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final spoilerPrefs = context.watch<SpoilerPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_movies_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('blur the synopsis'.tr, style: SeenlyText.serif(size: 13)),
                          ),
                          CozySwitch(
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
                          "off by default — a title's synopsis is usually written not to give anything away, so there's nothing to hide from unless you turn this on.".tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(height: 1, color: SeenlyPalette.border),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(Icons.rate_review_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('blur written reviews'.tr, style: SeenlyText.serif(size: 13)),
                          ),
                          CozySwitch(
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
                          "on by default — other people's reviews say what they want, so each one stays softly covered until you tap it. Turn this off if you'd rather just read them straight away.".tr,
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
              child: Text('privacy'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            // Product analytics opt-out (lib/analytics/analytics.dart). On by
            // default; turning it off stops collection immediately, empties
            // anything not yet sent and forgets this device's id.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: ClayBoxDecoration(
                  boxShadow: SeenlyPalette.flatCardShadow,
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ValueListenableBuilder<bool>(
                  valueListenable: Analytics.instance.enabledNotifier,
                  builder: (context, analyticsOn, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.insights_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('anonymous usage statistics'.tr, style: SeenlyText.serif(size: 13)),
                          ),
                          CozySwitch(
                            value: analyticsOn,
                            activeColor: SeenlyPalette.accent,
                            onChanged: (value) => Analytics.instance.setEnabled(value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'helps us see which screens get used and which ones confuse people. only what happened is sent — never titles, notes, what you search for, or anything you type. turning it off also forgets this device.'.tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text("today's pick".tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final todayPickPrefs = context.watch<TodayPickPrefsService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_movies_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('show today\'s pick on Home'.tr, style: SeenlyText.serif(size: 13)),
                          ),
                          CozySwitch(
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
                          "a franchise to marathon, picked fresh most days, with a little progress bar for however much of it you've already seen — there's a shuffle button on the card itself if it's not your thing that day. turn this off if you'd rather Home stayed without it.".tr,
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
              child: Text('language'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final locale = context.watch<LocaleService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text('🇷🇺'.tr, style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('russian interface'.tr, style: SeenlyText.serif(size: 13)),
                            const SizedBox(height: 2),
                            Text(
                              'translates the whole app — titles too, when TMDB has one, otherwise English'.tr,
                              style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                            ),
                          ],
                        ),
                      ),
                      CozySwitch(
                        value: locale.preferRussian,
                        activeColor: SeenlyPalette.accent,
                        onChanged: (value) async {
                          await context.read<LocaleService>().setPreferRussian(value);
                          // Pushes are worded on the server — tell it the new language.
                          if (context.mounted) {
                            unawaited(context.read<AppState>().push.refreshLanguage());
                          }
                        },
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
                child: PressScale(
                  onTap: () => showRegionPickerSheet(context),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: ClayBoxDecoration(
                      boxShadow: SeenlyPalette.flatCardShadow,
                      color: SeenlyPalette.paper,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.public, size: 18, color: SeenlyPalette.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('streaming region'.tr, style: SeenlyText.serif(size: 13)),
                              const SizedBox(height: 2),
                              Text(
                                'which country\'s services show under "where to watch" — Kinopoisk, ivi, Netflix, and the rest all vary by country'.tr,
                                style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                              ),
                            ],
                          ),
                        ),
                        Text(current.label.tr, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 15, color: SeenlyPalette.inkFaint),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('map style'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final mapStyle = context.watch<MapStyleService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.layers_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Text('how the route map looks'.tr, style: SeenlyText.serif(size: 13)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'same choice as the layers button on the route map itself'.tr,
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
              child: Text('this diary'.tr, style: SeenlyText.metaLabel),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final logTheme = context.watch<LogThemeService>().theme;
              final (icon, subtitle) = switch (logTheme) {
                LogTheme.coach => (Icons.train, 'an evening route, boarded and torn at the gate'.tr),
                LogTheme.ticket => (Icons.local_activity_outlined, 'a little cinema, ticket torn for each evening'.tr),
                LogTheme.garden => (Icons.local_florist_outlined, 'a window garden, a flower grown for each evening'.tr),
                LogTheme.shuttle => (Icons.rocket_launch_outlined, 'a shuttle, a capsule launched for each evening'.tr),
              };
              return _SettingsTile(
                icon: icon,
                label: 'logging ritual'.tr,
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
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_outlined, size: 17, color: SeenlyPalette.inkMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('skip the ritual'.tr, style: SeenlyText.serif(size: 13)),
                            const SizedBox(height: 2),
                            Text(
                              'no seats, no tickets, no animations — every log just happens instantly'.tr,
                              style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                            ),
                          ],
                        ),
                      ),
                      CozySwitch(
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
              final themePrefs = context.watch<ThemePrefsService>();
              final isPremium = context.watch<PremiumService>().isPremium;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.nights_stay_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Text('appearance'.tr, style: SeenlyText.serif(size: 13)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'dark mode is early — for now it just changes the co-viewing bunnies'.tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                      // A flavor mood is always light regardless of
                      // system/dark — see AppAppearance.themeMode's own
                      // doc comment for why. Said here up front, not
                      // just after picking one, since it's the one
                      // thing about these two that isn't obvious from
                      // the swatch alone.
                      Padding(
                        padding: const EdgeInsets.only(left: 27, top: 2),
                        child: Text(
                          "orange and strawberry are always light — that's the whole point, not a bug".tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in _themeOptions)
                            SizedBox(
                              width: 78,
                              child: _ThemeOptionButton(
                                icon: option.icon,
                                label: option.label,
                                swatchColor: option.swatchColor,
                                locked: option.value.isFlavor && !isPremium,
                                selected: option.value == themePrefs.appearance,
                                onTap: () {
                                  if (option.value.isFlavor && !isPremium) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const PremiumScreen()),
                                    );
                                    return;
                                  }
                                  context.read<ThemePrefsService>().setAppearance(option.value);
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final skinPrefs = context.watch<AppSkinService>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_outlined, size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Text('visual style'.tr, style: SeenlyText.serif(size: 13)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 27),
                        child: Text(
                          'a pastel paper skin on top of light or dark — same diary either way'.tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final option in _skinOptions)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _AppSkinSwatchButton(
                                  option: option,
                                  selected: option.skin == skinPrefs.skin,
                                  onTap: () => context.read<AppSkinService>().setSkin(option.skin),
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
            // Sits immediately above "log out" because it's the same
            // family of thing — the account rather than the diary — and
            // because App Store review expects account deletion to be
            // findable without hunting. See AccountScreen.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: ClayBoxDecoration(
                  boxShadow: SeenlyPalette.flatCardShadow,
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PressScale(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AccountScreen()),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.manage_accounts_outlined,
                              size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('account'.tr, style: SeenlyText.serif(size: 13)),
                                const SizedBox(height: 2),
                                Text(
                                  'email, password, blocked accounts, downloading or deleting everything'
                                      .tr,
                                  style: SeenlyText.mono(
                                      size: 9, color: SeenlyPalette.placeholder),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 18, color: SeenlyPalette.placeholder),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(height: 1, color: SeenlyPalette.border),
                    const SizedBox(height: 12),
                    PressScale(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EulaScreen()),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.gavel_outlined,
                              size: 17, color: SeenlyPalette.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('terms of use'.tr,
                                style: SeenlyText.serif(size: 13)),
                          ),
                          Icon(Icons.chevron_right,
                              size: 18, color: SeenlyPalette.placeholder),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: PressScale(
                onTap: _loggingOut ? null : _confirmLogout,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ClayBoxDecoration(
                    boxShadow: SeenlyPalette.flatCardShadow,
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SeenlyPalette.coral.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 17, color: SeenlyPalette.coral),
                      const SizedBox(width: 10),
                      Text('log out'.tr,
                          style: SeenlyText.serif(italic: true, color: SeenlyPalette.coral)),
                      const Spacer(),
                      if (_loggingOut)
                        BouncingDots(color: SeenlyPalette.coral, dotSize: 4),
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
                    Text('tanè · v0.1.0'.tr,
                        style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
                    const SizedBox(height: 3),
                    Text('formerly seenly — same diary, new name'.tr,
                        style: SeenlyText.serif(
                            italic: true, size: 10, color: SeenlyPalette.placeholder)),
                  ],
                ),
              ),
            ),
                  ]),
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
  final bool locked;
  final VoidCallback onTap;

  const _ThemeChoiceRow({
    required this.icon,
    required this.label,
    required this.selected,
    this.locked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.985,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent.withOpacity(0.12) : SeenlyPalette.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? SeenlyPalette.accent : SeenlyPalette.border, width: selected ? 1.4 : 1),
        ),
        child: Row(
          children: [
            FadeIcon(icon: icon, size: 17, color: selected ? SeenlyPalette.accent : SeenlyPalette.inkMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: SeenlyText.serif(
                      size: 13, color: selected ? SeenlyPalette.ink : SeenlyPalette.inkMuted)),
            ),
            // The trailing mark (a premium lock, or the tick of the chosen
            // one) swaps softly rather than blinking.
            SoftSwap(
              pop: true,
              alignment: Alignment.centerRight,
              duration: const Duration(milliseconds: 260),
              child: locked
              ? Container(
                key: const ValueKey<String>('lock'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: SeenlyPalette.mustard.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 11, color: SeenlyPalette.clay),
                    const SizedBox(width: 3),
                    Text('premium'.tr,
                        style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.clay)),
                  ],
                ),
              )
              : selected
                  ? Icon(Icons.check_circle, key: const ValueKey<String>('on'), size: 17, color: SeenlyPalette.accent)
                  : const SizedBox(key: ValueKey<String>('off'), width: 17, height: 17),
            ),
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
      child: PressScale(
        onTap: interactive ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: ClayBoxDecoration(
            boxShadow: SeenlyPalette.flatCardShadow,
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
                Icon(Icons.chevron_right, size: 17, color: SeenlyPalette.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

const _themeOptions = [
  _ThemeOption(AppAppearance.system, Icons.brightness_auto_outlined, 'system'),
  _ThemeOption(AppAppearance.light, Icons.light_mode_outlined, 'light'),
  _ThemeOption(AppAppearance.dark, Icons.dark_mode_outlined, 'dark'),
  _ThemeOption(AppAppearance.orange, Icons.local_activity_outlined, 'tangerine', swatchColor: Color(0xFFE8823A)),
  _ThemeOption(AppAppearance.strawberry, Icons.local_activity_outlined, 'strawberry', swatchColor: Color(0xFFE0344F)),
];

class _ThemeOption {
  final AppAppearance value;
  final IconData icon;
  final String label;
  // Set only for the two premium flavors — _ThemeOptionButton shows it
  // as a small preview dot instead of relying on the label alone,
  // since "tangerine"/"strawberry" is a color choice first.
  final Color? swatchColor;
  const _ThemeOption(this.value, this.icon, this.label, {this.swatchColor});
}

/// One tappable option for the "appearance" settings row — same
/// selected/unselected treatment as [_AppSkinSwatchButton], plus an
/// optional premium lock badge for the two flavor moods (mirrors the
/// lock treatment _ThemeChoiceRow already uses for the shuttle logging
/// theme, just adapted to this compact swatch shape).
class _ThemeOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? swatchColor;
  final bool locked;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOptionButton({
    required this.icon,
    required this.label,
    this.swatchColor,
    this.locked = false,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = swatchColor;
    return OptionSwatch(
      label: label.tr,
      selected: selected,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          swatch != null
              ? Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
                )
              : FadeIcon(
                  icon: icon,
                  size: 18,
                  color: selected ? SeenlyPalette.accent : SeenlyPalette.inkMuted,
                ),
          if (locked)
            Positioned(
              right: -6,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: SeenlyPalette.mustard.withOpacity(0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: SeenlyPalette.paper, width: 1.2),
                ),
                child: Icon(Icons.lock_outline, size: 8, color: SeenlyPalette.paper),
              ),
            ),
        ],
      ),
    );
  }
}

class _SkinOption {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final Color swatch;
  const _SkinOption(this.skin, this.icon, this.label, this.swatch);
}

const _skinOptions = [
  _SkinOption(AppSkin.classic, Icons.article_outlined, 'standard', Color(0xFF7D5A6B)),
  _SkinOption(AppSkin.cozy, Icons.favorite, 'cozy diary', Color(0xFF7A2E45)),
  _SkinOption(AppSkin.clay, Icons.blur_circular, 'clay', Color(0xFFEA6B9B)),
];

/// One tappable option for the "visual style" settings row — same
/// selected/unselected treatment as [_ThemeOptionButton] just above,
/// plus a small color dot previewing that skin's accent so "cozy diary"
/// doesn't have to be taken on faith.
class _AppSkinSwatchButton extends StatelessWidget {
  final _SkinOption option;
  final bool selected;
  final VoidCallback onTap;
  const _AppSkinSwatchButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OptionSwatch(
      label: option.label.tr,
      selected: selected,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: option.swatch, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          FadeIcon(
            icon: option.icon,
            size: 16,
            color: selected ? SeenlyPalette.accent : SeenlyPalette.inkMuted,
          ),
        ],
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
    return OptionSwatch(
      label: info.label.tr,
      selected: selected,
      onTap: onTap,
      fill: color,
      // The tick pops in on the chosen one and shrinks away on the rest.
      child: SoftSwap(
        pop: true,
        alignment: Alignment.center,
        duration: const Duration(milliseconds: 260),
        child: selected
            ? Icon(
                Icons.check_circle,
                key: const ValueKey<bool>(true),
                size: 16,
                color: info.style == MapStyle.night ? SeenlyPalette.paper : SeenlyPalette.accent,
              )
            : const SizedBox(key: ValueKey<bool>(false), width: 16, height: 16),
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
  bool _savingDiscoverable = false;

  Future<void> _toggleDiscoverable() async {
    final me = _me;
    if (me == null || _savingDiscoverable) return;
    setState(() => _savingDiscoverable = true);
    try {
      final updated = await context
          .read<AppState>()
          .profile
          .updateMe(discoverable: !me.discoverable);
      if (!mounted) return;
      setState(() {
        _me = updated;
        _savingDiscoverable = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingDiscoverable = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("that didn't save — try again".tr)));
    }
  }

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
          .showSnackBar(SnackBar(content: Text("that didn't save — try again".tr)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _loading || me == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: BouncingDots(color: SeenlyPalette.inkFaint, dotSize: 5),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'who can see what you\'ve watched, are watching now, plan to watch, or have marked as a favorite'.tr,
                  style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
                ),
                const SizedBox(height: 12),
                _PrivacyRow(
                  label: 'watched'.tr,
                  icon: Icons.check_circle_outline,
                  value: PrivacyLevelWire.fromWire(me.privacyWatched),
                  saving: _saving == PrivacyShelf.watched,
                  onChanged: (level) => _setLevel(PrivacyShelf.watched, level),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: SeenlyPalette.border),
                const SizedBox(height: 12),
                _PrivacyRow(
                  label: 'watching now'.tr,
                  icon: Icons.play_circle_outline,
                  value: PrivacyLevelWire.fromWire(me.privacyWatching),
                  saving: _saving == PrivacyShelf.watching,
                  onChanged: (level) => _setLevel(PrivacyShelf.watching, level),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: SeenlyPalette.border),
                const SizedBox(height: 12),
                _PrivacyRow(
                  label: 'plan to watch'.tr,
                  icon: Icons.bookmark_border,
                  value: PrivacyLevelWire.fromWire(me.privacyPlanned),
                  saving: _saving == PrivacyShelf.planned,
                  onChanged: (level) => _setLevel(PrivacyShelf.planned, level),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: SeenlyPalette.border),
                const SizedBox(height: 12),
                _PrivacyRow(
                  label: 'favorite films'.tr,
                  icon: Icons.favorite_border,
                  value: PrivacyLevelWire.fromWire(me.privacyFavorites),
                  saving: _saving == PrivacyShelf.favorites,
                  onChanged: (level) => _setLevel(PrivacyShelf.favorites, level),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: SeenlyPalette.border),
                const SizedBox(height: 12),
                // Not a shelf setting: the four above decide what a
                // viewer sees once they're already looking at this
                // profile, this decides whether a stranger can find it at
                // all. There was no way to be un-findable before —
                // username search matched any substring of every name in
                // the database.
                PressScale(
                  onTap: _savingDiscoverable ? null : _toggleDiscoverable,
                  child: Row(
                    children: [
                      Icon(Icons.search_outlined,
                          size: 16, color: SeenlyPalette.inkMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('people can find me by my username'.tr,
                                style: SeenlyText.serif(size: 13)),
                            const SizedBox(height: 2),
                            Text(
                              'turning this off keeps every friend you already have — only search stops finding you'
                                  .tr,
                              style: SeenlyText.mono(
                                  size: 9, color: SeenlyPalette.placeholder),
                            ),
                          ],
                        ),
                      ),
                      if (_savingDiscoverable)
                        BouncingDots(color: SeenlyPalette.accent, dotSize: 4)
                      else
                        Switch(
                          value: me.discoverable,
                          activeColor: SeenlyPalette.accent,
                          onChanged: (_) => _toggleDiscoverable(),
                        ),
                    ],
                  ),
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
            SoftSwap(
              alignment: Alignment.center,
              duration: const Duration(milliseconds: 200),
              child: saving
                  ? BouncingDots(key: const ValueKey<String>('saving'), color: SeenlyPalette.accent, dotSize: 4)
                  : const SizedBox(key: ValueKey<String>('idle'), width: 1, height: 1),
            ),
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
                SoftChoice(
                  label: level.label.tr,
                  selected: value == level,
                  onTap: saving ? null : () => onChanged(level),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Наш дневник" — sharing settings for a co-viewing circle, in the same
/// paper-card shape as every other section on this screen.
///
/// Self-contained (own fetch, own state) rather than plumbed through the
/// screen's provider tree: these three switches are the only place in
/// the app that reads or writes PartnerPrefs, so giving them a shared
/// service instance elsewhere would be plumbing for an audience of one.
///
/// Renders nothing at all for anyone without an active circle. Showing
/// three greyed-out switches with a "link up first" caption was
/// considered and rejected — it turns a settings screen that's otherwise
/// entirely about *this* account into a place that advertises a feature
/// the person hasn't set up, which the co-viewing card on Home already
/// does perfectly well.
class _SharedDiarySettingsSection extends StatefulWidget {
  const _SharedDiarySettingsSection();

  @override
  State<_SharedDiarySettingsSection> createState() =>
      _SharedDiarySettingsSectionState();
}

class _SharedDiarySettingsSectionState
    extends State<_SharedDiarySettingsSection> {
  late final PartnerService _partner = PartnerService(ApiClient.instance);
  late final SharedDiaryService _shared = SharedDiaryService(ApiClient.instance);

  bool _linked = false;
  PartnerPrefs? _prefs;
  bool _loading = true;
  // Per-switch, so flipping one doesn't disable the other two while its
  // own request is in flight.
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await _partner.status();
      if (!status.linked) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final prefs = await _shared.prefs();
      if (!mounted) return;
      setState(() {
        _linked = true;
        _prefs = prefs;
        _loading = false;
      });
    } catch (_) {
      // No circle, offline, whatever — see this widget's own docstring.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String key, bool value) async {
    final before = _prefs;
    if (before == null) return;
    setState(() {
      _saving.add(key);
      _prefs = switch (key) {
        'auto' => before.copyWith(autoShareLogs: value),
        'ratings' => before.copyWith(shareRatings: value),
        _ => before.copyWith(shareNotes: value),
      };
    });
    try {
      final updated = await _shared.updatePrefs(
        autoShareLogs: key == 'auto' ? value : null,
        shareRatings: key == 'ratings' ? value : null,
        shareNotes: key == 'notes' ? value : null,
      );
      if (mounted) setState(() => _prefs = updated);
    } catch (_) {
      // Roll back to what the server last confirmed — a switch that
      // silently disagrees with the server is worse than one that
      // visibly snaps back.
      if (mounted) setState(() => _prefs = before);
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (!_linked || _prefs == null) return const SizedBox.shrink();
    final prefs = _prefs!;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text('наш дневник'.tr, style: SeenlyText.metaLabel),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: ClayBoxDecoration(
                boxShadow: SeenlyPalette.flatCardShadow,
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SharedToggleRow(
                    icon: Icons.auto_stories_outlined,
                    label: 'записывать мои вечера в общий дневник'.tr,
                    value: prefs.autoShareLogs,
                    saving: _saving.contains('auto'),
                    onChanged: (v) => _set('auto', v),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 27, top: 2),
                    child: Text(
                      'вечер, который вы посмотрели вместе, всё равно попадёт в общий дневник — этот переключатель только про то, что вы смотрите в одиночку'.tr,
                      style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                  _SharedToggleRow(
                    icon: Icons.favorite_border_rounded,
                    label: 'показывать мою оценку'.tr,
                    value: prefs.shareRatings,
                    saving: _saving.contains('ratings'),
                    onChanged: (v) => _set('ratings', v),
                  ),
                  const SizedBox(height: 10),
                  _SharedToggleRow(
                    icon: Icons.edit_note_rounded,
                    label: 'показывать мои заметки'.tr,
                    value: prefs.shareNotes,
                    saving: _saving.contains('notes'),
                    onChanged: (v) => _set('notes', v),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 27, top: 2),
                    child: Text(
                      'заметки — самое личное, что есть в дневнике, поэтому по умолчанию они скрыты'.tr,
                      style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final bool saving;
  final ValueChanged<bool> onChanged;

  const _SharedToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: SeenlyPalette.inkMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: SeenlyText.serif(size: 13)),
        ),
        if (saving)
          BouncingDots(color: SeenlyPalette.inkFaint, dotSize: 4)
        else
          CozySwitch(
            value: value,
            activeColor: SeenlyPalette.accent,
            onChanged: onChanged,
          ),
      ],
    );
  }
}
