import 'package:flutter/material.dart';

/// A stable reference to the app's Navigator, alive for the whole
/// process — not rebuilt when MaterialApp's own `key:` (see app.dart)
/// forces a fresh widget tree on a theme/skin/locale change. Lives in
/// its own file rather than in app.dart itself so both app.dart (which
/// hands it to MaterialApp's `navigatorKey:`) and
/// state/app_state.dart (which hands it to PushNotificationManager) can
/// import it without a circular import between those two.
///
/// Exists for exactly one caller: PushNotificationManager, which routes
/// a notification tap from outside any screen's own BuildContext (a
/// callback firebase_messaging invokes on its own, not from inside a
/// widget build) — see services/push_notification_manager.dart.
final rootNavigatorKey = GlobalKey<NavigatorState>();
