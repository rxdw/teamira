import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;

import '../models/planned_evening.dart';
import 'evening_plan_service.dart';
import 'locale_service.dart';
import 'premium_service.dart';
import '../state/app_state.dart';

/// Feeds the premium home-screen widget (Settings > premium > "home-screen
/// widget" explains how to add it) — one glanceable slot on the phone's own home screen, filled
/// with whichever of these three is most worth showing right now:
///
///  1. a countdown to the soonest upcoming co-viewing evening
///     ([EveningPlanService.planMatching], `coViewing: true` only — a
///     solo plan doesn't belong on a widget pitched as "your evening
///     together")
///  2. today's pick ([AppState.feed.todayPick]) — the same franchise
///     shelf + progress Home's own card shows
///  3. the current streak ([AppState.profile.yearStats])
///
/// in that order — see [_gather]. Below premium, or before anyone's
/// linked in, it still refreshes to a "не премиум"/empty state rather
/// than leaving whatever the widget last happened to show, since a
/// widget that's just wrong (a streak from three subscription-tiers
/// ago) is worse than one that's honestly empty.
///
/// This is a plain, non-listenable service — nothing in the Flutter UI
/// reads its state back, it only ever writes outward — so it's a bare
/// class handed out via `Provider.value`, not a [ChangeNotifier]. It
/// self-attaches as a [WidgetsBindingObserver] in [init] purely so it
/// can catch the one moment that matters most for a home-screen widget:
/// the app being backgrounded, which is exactly when someone's about to
/// go looking at their home screen.
///
/// [HomeWidget]'s own API is the verified 0.6.0 surface (checked
/// against the package source directly, not assumed): [saveWidgetData]
/// takes a plain `id`/`data` pair with no app-group parameter — on iOS
/// it's written whatever [setAppGroupId] was last called with, which
/// [init] does once, up front. [renderFlutterWidget] is used only for
/// the pick's poster thumbnail — rendering it in Flutter (where a
/// network image is trivial) rather than teaching either native side to
/// fetch and decode one.
class HomeWidgetService with WidgetsBindingObserver {
  // Same string every platform side must agree on — see
  // ios/HomeWidgetSetup.md and android/app/src/main/AndroidManifest.xml.
  static const _appGroupId = 'group.com.example.seenly.widget';

  static const _androidProviderName = 'SeenlyWidgetProvider';
  static const _iosWidgetName = 'SeenlyWidget';

  AppState? _app;
  EveningPlanService? _plans;
  PremiumService? _premium;
  bool _initialized = false;
  bool _refreshing = false;
  // Coalesces a refresh requested while one is already in flight into a
  // single follow-up run, rather than queuing one per caller — several
  // call sites (RootShell's initial frame, a lifecycle pause, an
  // evening plan being confirmed right after) can all fire within the
  // same moment.
  bool _refreshPending = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      // Best-effort, same as every other call in this class (see the
      // class doc comment) — but this one matters more than most: it
      // runs inside main.dart's startup Future.wait, before runApp, so
      // an uncaught throw here would blank-screen the whole app rather
      // than just leave the widget stale. home_widget has no
      // implementation at all on web (and none on desktop either), so
      // this always throws MissingPluginException there.
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (_) {}
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Called once from [RootShellState] once the three services below
  /// are actually available (they aren't yet at [init] time — see
  /// main.dart's eager-load list vs. AppState's own later bootstrap).
  /// Safe to call again if the same instances come back around; a
  /// different [AppState] (a fresh sign-in) always triggers a refresh.
  void attach(AppState app, EveningPlanService plans, PremiumService premium) {
    final accountChanged = _app != app;
    _app = app;
    _plans = plans;
    _premium = premium;
    if (accountChanged) refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) refresh();
  }

  /// Gathers fresh data and pushes it to both native widgets. Safe to
  /// call often — network failures here are the same "best effort,
  /// leave the widget showing whatever it last had" story Home's own
  /// `_load()` tells for its non-critical sections, not a user-facing
  /// error.
  Future<void> refresh() async {
    if (_refreshing) {
      _refreshPending = true;
      return;
    }
    _refreshing = true;
    try {
      final app = _app;
      final premium = _premium;
      if (app == null || premium == null || app.currentUser == null) return;

      if (!premium.isPremium) {
        await _push(_WidgetPayload.locked());
        return;
      }

      await _push(await _gather(app, _plans));
    } catch (_) {
      // Leave the widget showing its last good state.
    } finally {
      _refreshing = false;
      if (_refreshPending) {
        _refreshPending = false;
        unawaited(refresh());
      }
    }
  }

  Future<_WidgetPayload> _gather(AppState app, EveningPlanService? plans) async {
    // 1. Countdown — the soonest upcoming *co-viewing* plan, within a
    // window worth counting down to. Past that, "in 11 days" reads more
    // like clutter than a countdown, so it falls through to the pick/
    // streak instead — the plan itself doesn't go anywhere, it'll pick
    // back up here as the date gets close.
    final plan = plans?.planMatching((p) => p.coViewing && !p.isPast);
    if (plan != null && plan.daysUntil <= 13) {
      return _WidgetPayload.countdown(plan);
    }

    // 2. Today's pick — best-effort, exactly like Home's own card.
    try {
      final pick = await app.feed.todayPick();
      if (!pick.isEmpty) {
        String? posterPath;
        final posterUrl = pick.collection.items.first.posterUrl;
        if (posterUrl != null) {
          posterPath = await _renderPoster(posterUrl);
        }
        return _WidgetPayload.pick(pick.collection.displayTitle, pick.watchedCount, pick.totalCount, posterPath);
      }
    } catch (_) {
      // Fall through to streak.
    }

    // 3. Streak — the reliable fallback; 0 renders as its own gentle
    // nudge rather than a bare "0".
    try {
      final stats = await app.profile.yearStats();
      return _WidgetPayload.streak(stats.streakDays);
    } catch (_) {
      return _WidgetPayload.empty();
    }
  }

  /// Downloads [posterUrl] and hands it to [HomeWidget.renderFlutterWidget]
  /// — the widget storage area is filled with a rendered PNG and its
  /// path saved under `widget_poster` (see that method's own doc
  /// comment), which is what SeenlyWidgetProvider.kt / SeenlyWidget.swift
  /// read back. `null` on any failure — a text-only card is a fine
  /// fallback, a crashed refresh is not.
  Future<String?> _renderPoster(String posterUrl) async {
    try {
      final response = await http.get(Uri.parse(posterUrl)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      final result = await HomeWidget.renderFlutterWidget(
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(response.bodyBytes, width: 160, height: 160, fit: BoxFit.cover),
        ),
        key: 'widget_poster',
        logicalSize: const Size(160, 160),
      );
      return result is String ? result : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _push(_WidgetPayload payload) async {
    await HomeWidget.saveWidgetData<String>('state', payload.state);
    await HomeWidget.saveWidgetData<String>('title', payload.title);
    await HomeWidget.saveWidgetData<String>('subtitle', payload.subtitle);
    await HomeWidget.saveWidgetData<String>('number', payload.number);
    if (payload.state != 'pick') {
      // Only the pick state has a poster — clear any stale one from a
      // previous refresh rather than leaving yesterday's poster behind
      // a streak card.
      await HomeWidget.saveWidgetData<String>('poster_path', '');
    }
    await HomeWidget.updateWidget(androidName: _androidProviderName, iOSName: _iosWidgetName);
  }
}

/// What actually gets written to the widget's shared storage — see
/// [HomeWidgetService._push]. Every field is already the exact display
/// string (localized here, in Dart, where [LocaleService] lives —
/// simpler than teaching two native platforms the same plural rules).
class _WidgetPayload {
  final String state; // "countdown" | "pick" | "streak" | "empty" | "locked"
  final String title;
  final String subtitle;
  final String number;

  const _WidgetPayload._(this.state, this.title, this.subtitle, this.number);

  // Not const: both read LocaleService.appIsRussian, which reflects the
  // user's current locale choice at runtime and so can't be folded into
  // a compile-time constant.
  _WidgetPayload.locked()
      : this._('locked', '', LocaleService.appIsRussian ? 'открой премиум для этого виджета' : 'unlock premium for this widget', '');

  _WidgetPayload.empty()
      : this._('empty', '', LocaleService.appIsRussian ? 'запиши сегодняшний вечер' : 'log tonight\'s evening', '');

  factory _WidgetPayload.countdown(PlannedEvening plan) {
    final days = plan.daysUntil;
    final who = plan.partnerUsername;
    final String number;
    if (LocaleService.appIsRussian) {
      number = days == 0 ? 'сегодня' : (days == 1 ? 'завтра' : '$days ${_ruDaysWord(days)}');
    } else {
      number = days == 0 ? 'today' : (days == 1 ? 'tomorrow' : '$days days');
    }
    final subtitle = who != null && who.isNotEmpty
        ? (LocaleService.appIsRussian ? 'вечер с $who' : 'evening with $who')
        : (LocaleService.appIsRussian ? 'совместный вечер' : 'evening together');
    return _WidgetPayload._('countdown', plan.title, subtitle, number);
  }

  factory _WidgetPayload.pick(String collectionTitle, int watched, int total, String? posterPath) {
    final subtitle = LocaleService.appIsRussian ? '$watched из $total просмотрено' : '$watched of $total watched';
    final payload = _WidgetPayload._('pick', collectionTitle, subtitle, '');
    if (posterPath != null) {
      // Fire-and-forget the poster path write alongside the rest —
      // _push always clears it for non-pick states, so there's no
      // ordering hazard between this and that.
      HomeWidget.saveWidgetData<String>('poster_path', posterPath);
    }
    return payload;
  }

  factory _WidgetPayload.streak(int streakDays) {
    if (streakDays <= 0) return _WidgetPayload.empty();
    final subtitle = LocaleService.appIsRussian ? _ruDaysWord(streakDays) : (streakDays == 1 ? 'day in a row' : 'days in a row');
    return _WidgetPayload._('streak', LocaleService.appIsRussian ? 'твой стрик' : 'your streak', subtitle, '$streakDays');
  }

  static String _ruDaysWord(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'дней подряд';
    switch (n % 10) {
      case 1:
        return 'день подряд';
      case 2:
      case 3:
      case 4:
        return 'дня подряд';
      default:
        return 'дней подряд';
    }
  }
}
