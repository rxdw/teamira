import 'dart:async';

import 'package:flutter/material.dart';

import 'analytics.dart';
import 'screen_names.dart';

/// Reports a `screen_view` for every route the app pushes — screens, bottom
/// sheets — without any screen having to opt in.
///
/// How it names them: Navigator routes in this app are anonymous
/// (`MaterialPageRoute(builder: ...)`, ~400 call sites), so instead of
/// editing every one, the observer waits one frame for the route's content
/// to be built, then walks a few levels down its widget tree for the first
/// widget whose class name ends in `Screen` (or `Sheet` — see
/// screen_names.dart). `RouteSettings(name: ...)` wins when a route has one.
///
/// What it deliberately doesn't cover, because they aren't routes: the four
/// tabs, the login/onboarding/EULA steps and the greeting splash. Those are
/// announced explicitly (RootShell, ScreenViewTracker in app.dart).
///
/// A route it can't name is reported as `(unnamed)` rather than dropped, so
/// the report shows how much is unlabelled instead of quietly undercounting;
/// plain dialogs are the exception — a confirm box isn't a screen.
class AnalyticsRouteObserver extends NavigatorObserver {
  /// How many widget levels below the route's content to look for a name.
  /// The screen is normally 2–4 levels down (Semantics/Builder wrappers);
  /// the cap stops a route whose content has no *Screen widget from being
  /// mis-named after something buried deep inside it.
  static const int _maxDepth = 12;

  // Remembers what each route turned out to be, so popping back to it can
  // be reported without walking the tree again. Garbage-collected with the
  // route.
  final Expando<AnalyticsScreenName> _names = Expando<AnalyticsScreenName>('analyticsScreenName');

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // No previous route = the app's first route, whose content (the auth
    // gate and tab shell) announces itself.
    if (previousRoute == null) return;
    _track(route, 'push');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) return;
    _track(newRoute, 'replace');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    try {
      final known = _names[previousRoute];
      if (known != null) {
        Analytics.instance.screen(known.name, kind: known.kind, nav: 'back');
      } else if (previousRoute.isFirst) {
        Analytics.instance.returnToRoot();
      }
    } catch (_) {}
  }

  void _track(Route<dynamic> route, String nav) {
    try {
      if (route is! ModalRoute) return; // not something with visible content
      final startedAt = DateTime.now();

      final explicit = route.settings.name;
      if (explicit != null && explicit.isNotEmpty && explicit != '/') {
        final resolved = AnalyticsScreenName(explicit, route is PageRoute ? 'screen' : 'sheet');
        _names[route] = resolved;
        Analytics.instance.screen(resolved.name, kind: resolved.kind, nav: nav, at: startedAt);
        return;
      }

      // The route's content doesn't exist until the frame after the push.
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolve(route, nav, startedAt, 0));
    } catch (_) {}
  }

  void _resolve(ModalRoute<dynamic> route, String nav, DateTime startedAt, int attempt) {
    try {
      final context = route.subtreeContext;
      if (context == null) {
        if (attempt < 2) {
          // Not built yet (a slow first frame). Try again shortly; if the
          // route is gone by then, it was popped before it ever showed.
          Timer(const Duration(milliseconds: 250), () => _resolve(route, nav, startedAt, attempt + 1));
        }
        return;
      }

      AnalyticsScreenName? resolved;
      final typeName = _findScreenTypeName(context);
      if (typeName != null) resolved = screenNameFromTypeName(typeName);

      if (resolved == null) {
        // Nothing with a recognisable name. A page is still a screen worth
        // counting; a bottom sheet likewise; anything else (dialogs,
        // popups) is not.
        if (route is PageRoute) {
          resolved = const AnalyticsScreenName('(unnamed)', 'screen');
        } else if (route is ModalBottomSheetRoute) {
          resolved = const AnalyticsScreenName('(unnamed)', 'sheet');
        } else {
          return;
        }
      }

      _names[route] = resolved;
      Analytics.instance.screen(resolved.name, kind: resolved.kind, nav: nav, at: startedAt);
    } catch (_) {}
  }

  String? _findScreenTypeName(BuildContext context) {
    if (context is! Element) return null;
    String? found;

    void visit(Element element, int depth) {
      if (found != null || depth > _maxDepth) return;
      final typeName = element.widget.runtimeType.toString();
      if (screenNameFromTypeName(typeName) != null) {
        found = typeName;
        return;
      }
      element.visitChildren((child) => visit(child, depth + 1));
    }

    context.visitChildren((child) => visit(child, 0));
    return found;
  }
}

/// Announces a screen that is swapped in place instead of pushed as a route
/// (see [Analytics.setRootScreen]). Wrap the screen where it's built:
///
///     const ScreenViewTracker(name: 'LoginScreen', child: LoginScreen())
///
/// The event fires once, when the wrapper is first mounted — i.e. when that
/// screen actually appears — and not on rebuilds.
class ScreenViewTracker extends StatefulWidget {
  final String name;
  final Widget child;

  const ScreenViewTracker({super.key, required this.name, required this.child});

  @override
  State<ScreenViewTracker> createState() => _ScreenViewTrackerState();
}

class _ScreenViewTrackerState extends State<ScreenViewTracker> {
  @override
  void initState() {
    super.initState();
    // Only queues an in-memory event: safe to call while the tree builds.
    Analytics.instance.setRootScreen(widget.name);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
