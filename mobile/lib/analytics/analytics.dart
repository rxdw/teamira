import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/locale_service.dart';

/// First-party product analytics. The whole app talks to this one class:
///
///     Analytics.instance.track('diary_entry_logged', {'media_type': 'movie'});
///
/// Screen views are recorded automatically (see AnalyticsRouteObserver and
/// ScreenViewTracker) — nothing in a screen needs to call [screen].
///
/// Where the events go and how to read them: docs/analytics.md. What is
/// and is not collected: docs/privacy_data_inventory.md. The short version
/// of the second: event names, screen names and small closed-vocabulary
/// facts (a media type, a count, a yes/no). Never titles, notes, search
/// text, e-mail addresses or anything a person typed.
///
/// Design notes:
///  - **Never throws, never blocks.** Every public method swallows its own
///    errors. A statistics call that can crash the diary is worse than no
///    statistics.
///  - **Batched.** Events queue in memory and go out together — after 15 s,
///    at 25 queued, or when the app is backgrounded — as one POST. The queue
///    is saved to disk on background so a kill between sessions loses
///    nothing, and capped so a phone that is offline for a month can't fill
///    its storage.
///  - **Retry-safe.** Every event carries a random id; the server ignores ids
///    it has already stored, so re-sending after a timeout is harmless.
///  - **Identity.** `anon_id` is random per install, forgotten on opt-out.
///    Who the person *is* is decided by the server from the access token on
///    the request — the client never claims a user id.
///  - **Opt-out is honoured at the source.** When off, nothing is queued and
///    nothing is sent; turning it off also empties the queue and discards
///    the anon_id.
class Analytics with WidgetsBindingObserver {
  Analytics._();
  static final Analytics instance = Analytics._();

  /// Pass `--dart-define=SEENLY_APP_VERSION=1.2.3` on release builds (next
  /// to SEENLY_API_BASE_URL) to have versions show up in the report;
  /// otherwise everything is reported as `dev`.
  static const String appVersion = String.fromEnvironment('SEENLY_APP_VERSION', defaultValue: 'dev');

  static const String _kAnonId = 'seenly_analytics_anon_id';
  static const String _kEnabled = 'seenly_analytics_enabled';
  static const String _kQueue = 'seenly_analytics_queue';

  static const int _maxQueue = 1000;
  static const int _maxPersisted = 300;
  static const int _batchSize = 50; // server accepts up to 100
  static const int _flushThreshold = 25;
  static const Duration _flushDelay = Duration(seconds: 15);
  static const Duration _sessionTimeout = Duration(minutes: 30);
  static const int _maxPropString = 120;

  /// Drives the switch in Settings.
  final ValueNotifier<bool> enabledNotifier = ValueNotifier<bool>(true);

  SharedPreferences? _prefs;
  bool _initialized = false;
  bool _enabled = true;
  String _anonId = '';
  String _sessionId = '';
  DateTime? _lastActivityAt;
  DateTime? _backgroundedAt;

  final List<Map<String, dynamic>> _queue = <Map<String, dynamic>>[];
  Timer? _flushTimer;
  bool _flushing = false;
  int _failures = 0;
  DateTime? _retryNotBefore;

  // Screen bookkeeping: the last thing on screen (to re-announce it when a
  // new session starts under it), the tab shell's current screen (to
  // announce it again when a pushed route is popped back to it), and a
  // guard against the same view being reported twice in a blink.
  String? _currentScreen;
  String _currentKind = 'screen';
  String? _rootScreen;
  String? _lastScreenKey;
  DateTime? _lastScreenAt;

  bool get enabled => _enabled;

  // ------------------------------------------------------------------ setup

  /// Call once from main(), after WidgetsFlutterBinding.ensureInitialized().
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _enabled = prefs.getBool(_kEnabled) ?? true;
      enabledNotifier.value = _enabled;
      _anonId = prefs.getString(_kAnonId) ?? '';
      if (_anonId.isEmpty) {
        _anonId = _newAnonId();
        await prefs.setString(_kAnonId, _anonId);
      }
      _restoreQueue(prefs.getString(_kQueue));
    } catch (_) {
      // Preferences unavailable: run in memory for this launch.
      if (_anonId.isEmpty) _anonId = _newAnonId();
    }
    _sessionId = _newId('s');
    _lastActivityAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    track('app_open', {'cold': true});
    if (_queue.isNotEmpty) _scheduleFlush();
  }

  // ----------------------------------------------------------------- public

  /// Records one event. `props` must be flat scalars (String, num, bool,
  /// enum); anything else is dropped. Keep them small and closed-vocabulary.
  void track(String name, [Map<String, Object?>? props]) {
    if (!_enabled || !_initialized) return;
    try {
      _record(name, props: props);
    } catch (_) {}
  }

  /// Records that a screen (or sheet) came into view. Called by the route
  /// observer and by [ScreenViewTracker]; screens don't call this.
  void screen(String name, {String kind = 'screen', String nav = 'push', DateTime? at}) {
    if (!_enabled || !_initialized) return;
    try {
      final now = DateTime.now();
      final key = '$kind|$name|$nav';
      final lastAt = _lastScreenAt;
      if (_lastScreenKey == key && lastAt != null && now.difference(lastAt) < const Duration(milliseconds: 400)) {
        return; // the same view reported twice in a blink (replace + pop, rebuild…)
      }
      _lastScreenKey = key;
      _lastScreenAt = now;
      if (kind == 'screen') {
        _currentScreen = name;
        _currentKind = kind;
      }
      _record('screen_view', props: {'kind': kind, 'nav': nav}, screen: name, at: at);
    } catch (_) {}
  }

  /// A screen that lives directly under the app's first route — the login,
  /// onboarding and EULA steps, the greeting splash, and each tab of the
  /// main shell. They are swapped in place rather than pushed, so the route
  /// observer never sees them; whoever shows them announces them here. The
  /// last one announced is what a popped route returns to.
  void setRootScreen(String name, {String nav = 'gate'}) {
    _rootScreen = name;
    screen(name, nav: nav);
  }

  /// A pushed route was popped and the app's first route is visible again.
  void returnToRoot() {
    final root = _rootScreen;
    if (root != null) screen(root, nav: 'back');
  }

  /// Sends what's queued now (used on background and before sign-out).
  /// Ignores the retry back-off: the caller is asking for a best effort.
  Future<void> flush({bool force = false}) async {
    if (!_enabled || !_initialized || _flushing || _queue.isEmpty) return;
    if (!force) {
      final notBefore = _retryNotBefore;
      if (notBefore != null && DateTime.now().isBefore(notBefore)) {
        _scheduleFlush(after: notBefore.difference(DateTime.now()));
        return;
      }
    }
    _flushing = true;
    try {
      while (_queue.isNotEmpty && _enabled) {
        final batch = _queue.take(_batchSize).toList();
        final delivered = await _send(batch);
        if (!delivered) {
          _failures++;
          final seconds = min(600, 15 * pow(2, min(_failures, 6)).toInt());
          _retryNotBefore = DateTime.now().add(Duration(seconds: seconds));
          break;
        }
        _failures = 0;
        _retryNotBefore = null;
        // By identity, not by position: events may have been appended (and
        // the oldest trimmed) while the request was in flight.
        final sent = Set<Map<String, dynamic>>.identity()..addAll(batch);
        _queue.removeWhere(sent.contains);
      }
    } catch (_) {
      // never surface
    } finally {
      _flushing = false;
    }
    if (_queue.isNotEmpty && _enabled) {
      final notBefore = _retryNotBefore;
      _scheduleFlush(after: notBefore != null ? notBefore.difference(DateTime.now()) : _flushDelay);
    }
  }

  /// The Settings switch. Turning it off empties the queue and forgets the
  /// device id, so nothing already collected can be sent later and a later
  /// opt-in starts from a clean identity.
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    enabledNotifier.value = value;
    try {
      await _prefs?.setBool(_kEnabled, value);
      if (!value) {
        _flushTimer?.cancel();
        _queue.clear();
        _anonId = _newAnonId();
        await _prefs?.setString(_kAnonId, _anonId);
        await _prefs?.remove(_kQueue);
      } else {
        _sessionId = _newId('s');
        _lastActivityAt = DateTime.now();
      }
    } catch (_) {}
  }

  /// Forgets this device: new anon_id, new session, nothing queued. Used
  /// when the account is deleted — the server erases everything this device
  /// reported while signed in, and this makes sure nothing sent afterwards
  /// can be tied back to the same id.
  Future<void> resetIdentity() async {
    try {
      _flushTimer?.cancel();
      _queue.clear();
      _anonId = _newAnonId();
      _sessionId = _newId('s');
      _lastActivityAt = DateTime.now();
      await _prefs?.setString(_kAnonId, _anonId);
      await _prefs?.remove(_kQueue);
    } catch (_) {}
  }

  // -------------------------------------------------------------- lifecycle

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized) return;
    try {
      if (state == AppLifecycleState.paused) {
        _backgroundedAt = DateTime.now();
        track('app_background');
        _persistQueue();
        unawaited(flush(force: true));
      } else if (state == AppLifecycleState.resumed) {
        final away = _backgroundedAt;
        _backgroundedAt = null;
        if (away != null && DateTime.now().difference(away) > _sessionTimeout) {
          _sessionId = _newId('s');
          _lastActivityAt = DateTime.now();
          track('app_open', {'cold': false});
          final current = _currentScreen;
          if (current != null) {
            _lastScreenKey = null; // don't let the de-dupe swallow it
            screen(current, kind: _currentKind, nav: 'resume');
          }
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- private

  void _record(String name, {Map<String, Object?>? props, String? screen, DateTime? at}) {
    final now = DateTime.now();
    final last = _lastActivityAt;
    if (last != null && now.difference(last) > _sessionTimeout) {
      _sessionId = _newId('s'); // idle in the foreground for 30 min: a new session
    }
    _lastActivityAt = now;

    final event = <String, dynamic>{
      'id': _newId('e'),
      'name': name,
      'ts': (at ?? now).toUtc().toIso8601String(),
      'sid': _sessionId,
    };
    if (screen != null) event['screen'] = screen;
    final clean = _sanitize(props);
    if (clean.isNotEmpty) event['props'] = clean;

    if (kDebugMode) {
      debugPrint('[analytics] $name${screen != null ? ' $screen' : ''}${clean.isNotEmpty ? ' $clean' : ''}');
    }

    _queue.add(event);
    if (_queue.length > _maxQueue) {
      _queue.removeRange(0, _queue.length - _maxQueue);
    }
    if (_queue.length >= _flushThreshold) {
      unawaited(flush());
    } else {
      _scheduleFlush();
    }
  }

  Map<String, Object?> _sanitize(Map<String, Object?>? props) {
    if (props == null || props.isEmpty) return const <String, Object?>{};
    final out = <String, Object?>{};
    props.forEach((key, value) {
      if (value == null || value is bool) {
        out[key] = value;
      } else if (value is num) {
        // jsonEncode throws on NaN/Infinity.
        if (!value.isNaN && !value.isInfinite) out[key] = value;
      } else if (value is String) {
        out[key] = value.length > _maxPropString ? value.substring(0, _maxPropString) : value;
      } else if (value is Enum) {
        out[key] = value.name;
      }
      // anything else (lists, maps, objects): dropped, like the server does.
    });
    return out;
  }

  void _scheduleFlush({Duration after = _flushDelay}) {
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = Timer(after.isNegative ? _flushDelay : after, () {
      unawaited(flush());
    });
  }

  /// true  = delivered, or rejected in a way retrying can't fix (drop it);
  /// false = try again later (offline, timeout, 429, 5xx).
  Future<bool> _send(List<Map<String, dynamic>> batch) async {
    try {
      await ApiClient.instance.post(
        '/analytics/events',
        body: <String, dynamic>{
          'anon_id': _anonId,
          'platform': defaultTargetPlatform.name,
          'app_version': appVersion,
          'build': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
          'locale': LocaleService.appIsRussian ? 'ru' : 'en',
          'events': batch,
        },
        timeout: const Duration(seconds: 10),
      );
      return true;
    } on ApiException catch (e) {
      return !(e.statusCode == 429 || e.statusCode >= 500);
    } catch (_) {
      return false;
    }
  }

  void _persistQueue() {
    try {
      final prefs = _prefs;
      if (prefs == null) return;
      final start = _queue.length > _maxPersisted ? _queue.length - _maxPersisted : 0;
      unawaited(prefs.setString(_kQueue, jsonEncode(_queue.sublist(start))));
    } catch (_) {}
  }

  void _restoreQueue(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is Map) _queue.add(Map<String, dynamic>.from(item));
      }
    } catch (_) {}
  }

  static final Random _random = _makeRandom();

  static Random _makeRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static String _hex(int chars) {
    const digits = '0123456789abcdef';
    final b = StringBuffer();
    for (var i = 0; i < chars; i++) {
      b.write(digits[_random.nextInt(16)]);
    }
    return b.toString();
  }

  static String _newId(String prefix) => '$prefix${_hex(16)}';
  static String _newAnonId() => 'a${_hex(20)}';
}
