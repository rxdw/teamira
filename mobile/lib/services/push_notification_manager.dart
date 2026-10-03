import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:provider/provider.dart';

import '../screens/friends/friends_screen.dart';
import '../screens/partner/album/album_home_screen.dart';
import '../screens/partner/co_view_hub_screen.dart';
import '../screens/premium/manage_subscription_screen.dart';
import '../screens/premium/premium_screen.dart';
import '../screens/title/title_detail_screen.dart';
import '../theme/palette.dart';
import 'premium_service.dart';
import 'push_service.dart';

/// Must be a top-level (or static) function — firebase_messaging calls
/// this in a separate isolate for a message that arrives while the app
/// is fully backgrounded/terminated. There's nothing to actually do
/// here for this app: every push this app sends already includes a
/// `notification` block (see app/push.py's own `messaging.Notification
/// (...)`), which both platforms display on their own, no app code
/// involved, whenever the app isn't in the foreground — see
/// PushNotificationManager._showForegroundNotification for the one case
/// (the app *is* open) where this app does have to draw the banner
/// itself. This empty handler exists only because firebase_messaging
/// requires *some* background handler to be registered before
/// FirebaseMessaging.instance is touched at all.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Owns everything push-notification-related on the client: asking for
/// permission, registering/refreshing the device's FCM token with the
/// backend (see [PushService]), drawing a local notification for a
/// message that arrives while the app is already open, and routing a
/// notification tap to the right screen.
///
/// Safe to construct and call every method on even when this build has
/// no Firebase project configured at all — no
/// android/app/google-services.json, no
/// ios/Runner/GoogleService-Info.plist (see
/// docs/push_notifications_setup.md, a manual, one-time step this
/// change can't do on its own since it needs a real Firebase project).
/// [init] catches Firebase.initializeApp()'s failure in that case, and
/// every other method below becomes a quiet no-op rather than a crash —
/// the same "just works with nothing configured, push itself just
/// doesn't happen" shape app/push.py already has on the backend side.
class PushNotificationManager {
  final PushService _pushService;
  final GlobalKey<NavigatorState> navigatorKey;

  PushNotificationManager(this._pushService, this.navigatorKey);

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _firebaseReady = false;
  bool _initStarted = false;
  RemoteMessage? _lastForegroundMessage;

  static const _androidChannel = AndroidNotificationChannel(
    'default_channel',
    'уведомления',
    description: 'совпадения, активность друзей и напоминания о серии',
    importance: Importance.high,
  );

  /// Called once, early in app startup (see app.dart) — sets up
  /// Firebase and the local-notification/tap listeners. Deliberately
  /// does *not* request notification permission or register a token —
  /// see [registerDeviceToken], called separately once someone's
  /// actually signed in. There's no account for a token to belong to
  /// before that, and asking for permission before someone has even
  /// created an account is the kind of prompt that gets reflexively
  /// denied, souring the *next* permission dialog too.
  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e, st) {
      developer.log(
        'Firebase.initializeApp() failed — push notifications are disabled for '
        'this run. See docs/push_notifications_setup.md.',
        name: 'PushNotificationManager',
        error: e,
        stackTrace: st,
      );
      return;
    }

    await _setupLocalNotifications();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_registerToken(token));
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // The app was launched *by* tapping a notification (it was fully
      // terminated beforehand) — defer one frame so the root shell has
      // actually mounted before anything tries to push a route onto it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleTap(initialMessage));
    }
  }

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        // The local notification below only carries `type` as its
        // payload string (see _showForegroundNotification) — full
        // routing re-derives from the RemoteMessage that triggered it
        // rather than trying to serialize the whole data map into a
        // plain-string payload.
        if (_lastForegroundMessage != null) {
          _handleTap(_lastForegroundMessage!);
        }
      },
    );
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    _lastForegroundMessage = message;
    final notification = message.notification;
    if (notification == null) return;
    unawaited(_localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['type'] as String?,
    ));
  }

  void _handleTap(RemoteMessage message) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    final data = message.data;
    switch (data['type'] as String?) {
      case 'match':
      case 'friend_activity':
      case 'memory':
      case 'new_episode':
        final mediaId = data['media_id'] as String?;
        final source = data['source'] as String?;
        final mediaType = data['media_type'] as String?;
        if (mediaId != null && source != null && mediaType != null) {
          navigator.push(MaterialPageRoute(
            builder: (_) => TitleDetailScreen(
              mediaId: mediaId,
              source: source,
              mediaType: mediaType,
              seedTitle: (data['title'] as String?) ?? message.notification?.title ?? '',
            ),
          ));
        }
        break;
      case 'friend_request':
        // Lands directly on the friends screen's incoming-requests list
        // rather than just the root shell — see
        // push.py::notify_friend_request on the backend and
        // FriendsScreen's own incoming-count pill (NotificationCountPill)
        // for the in-app half of this same signal.
        navigator.popUntil((route) => route.isFirst);
        navigator.push(MaterialPageRoute(builder: (_) => const FriendsScreen()));
        break;
      case 'trial_ending':
      case 'trial_ended':
        // The free-period reminder series (backend app/trial.py). Marks
        // the matching in-app nudge as already handled first, so the
        // shell doesn't stack a second paywall on top of this one when
        // the app comes to the foreground.
        final ctx = navigatorKey.currentContext;
        if (ctx != null) unawaited(ctx.read<PremiumService>().takeTrialNudge());
        navigator.popUntil((route) => route.isFirst);
        navigator.push(MaterialPageRoute(
          builder: (_) => PremiumScreen(
            triggerSource: data['type'] == 'trial_ended' ? 'trial_ended_push' : 'trial_ending_push',
          ),
          fullscreenDialog: true,
        ));
        break;
      case 'winback':
        // The comeback offer after a cancelled plan ran out (backend
        // app/subscription.py). Same idea as the trial pair above: mark
        // the in-app nudge handled first so the shell doesn't stack a
        // second paywall on this one.
        final wctx = navigatorKey.currentContext;
        if (wctx != null) unawaited(wctx.read<PremiumService>().takeWinbackNudge());
        navigator.popUntil((route) => route.isFirst);
        navigator.push(MaterialPageRoute(
          builder: (_) => const PremiumScreen(triggerSource: 'winback_push'),
          fullscreenDialog: true,
        ));
        break;
      case 'pause_ending':
        // "Your pause ends soon" — the useful place to land is the page
        // where it can be extended into a cancel or ended early.
        navigator.popUntil((route) => route.isFirst);
        navigator.push(MaterialPageRoute(
          builder: (_) => const ManageSubscriptionScreen(),
        ));
        break;
      case 'pair_album_note':
      case 'pair_album_reveal':
      case 'pair_album_capsule':
      case 'pair_album_anniversary':
        // A sealed note, an unsealed one, a capsule, an anniversary: all
        // land on the album's front page, which shows what's new (the
        // unread badge, the capsule that's ready). Fetches its own status,
        // and says so plainly if the link has since been ended.
        navigator.popUntil((route) => route.isFirst);
        navigator.push(MaterialPageRoute(builder: (_) => const AlbumHomeLoader()));
        break;
      case 'partner_invite':
        // CoViewHubScreen (see push.py::notify_partner_invite) renders
        // its own back arrow when given onBack, but has no Scaffold of
        // its own — it's normally embedded in the root shell's tab, not
        // pushed standalone, so one is added here.
        navigator.popUntil((route) => route.isFirst);
        navigator.push(MaterialPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: SeenlyPalette.background,
            body: SafeArea(
              child: CoViewHubScreen(onBack: () => Navigator.of(context).pop()),
            ),
          ),
        ));
        break;
      default:
        // partner_linked, level_up, streak_reminder — no title to deep-
        // link to, and no dedicated screen for "here's your new level"/
        // "here's your partner link" to land on either (see this file's
        // own module docstring: a deliberate scope cut, not an
        // oversight). Landing back on whatever the root shell already
        // shows is a reasonable default rather than doing nothing at
        // all with the tap.
        navigator.popUntil((route) => route.isFirst);
    }
  }

  /// Requests notification permission and registers the resulting FCM
  /// token with the backend. Call once someone is actually signed in
  /// (see state/app_state.dart's bootstrap/login/register) — never
  /// before, for the reason [init]'s own docstring gives.
  Future<void> registerDeviceToken() async {
    if (!_firebaseReady) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (e, st) {
      developer.log('registerDeviceToken failed', name: 'PushNotificationManager', error: e, stackTrace: st);
    }
  }

  Future<void> _registerToken(String token) async {
    String? timezone;
    try {
      timezone = await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      // Best-effort — see models.PushToken.timezone's own docstring on
      // the backend for what happens with no timezone at all (the
      // streak reminder simply never fires for this device, rather than
      // guessing and getting it wrong).
    }
    try {
      await _pushService.registerToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
        timezone: timezone,
      );
    } catch (e, st) {
      developer.log('registerToken failed', name: 'PushNotificationManager', error: e, stackTrace: st);
    }
  }

  /// Called on sign-out (see state/app_state.dart::logout) so a shared
  /// or reset device stops getting the account that just signed out's
  /// pushes. Best-effort: if this fails (offline logout, say), the
  /// token is simply left registered until the *next* account to sign
  /// in on this device overwrites it — see routers/push.py::
  /// register_token's own docstring on why that overwrite is safe.
  Future<void> unregisterDeviceToken() async {
    if (!_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _pushService.unregisterToken(token);
    } catch (e, st) {
      developer.log('unregisterDeviceToken failed', name: 'PushNotificationManager', error: e, stackTrace: st);
    }
  }
}
