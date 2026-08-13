import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';

import '../models/active_journey.dart';
import '../models/profile_stats.dart';
import '../services/ai_service.dart';
import '../services/activity_service.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/co_view_vote_service.dart';
import '../services/co_view_poll_service.dart';
import '../services/diary_service.dart';
import '../services/feed_service.dart';
import '../services/friends_service.dart';
import '../services/integrations_service.dart';
import '../services/import_service.dart';
import '../services/lists_service.dart';
import '../services/media_service.dart';
import '../services/partner_service.dart';
import '../services/profile_service.dart';
import '../services/progress_service.dart';
import '../services/referral_link_service.dart';
import '../services/sources_service.dart';
import '../services/together_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// The one ChangeNotifier the app roots itself on: knows whether we have a
/// token, and hands out every service. Screens below the root shell reach
/// this via `context.watch<AppState>()` / `context.read<AppState>()`
/// instead of each constructing their own ApiClient.
class AppState extends ChangeNotifier {
  final ApiClient client = ApiClient.instance;

  late final AuthService auth = AuthService(client);
  late final MediaService media = MediaService(client);
  late final FeedService feed = FeedService(client);
  late final DiaryService diary = DiaryService(client);
  late final ProfileService profile = ProfileService(client);
  late final AiService ai = AiService(client);
  late final ProgressService progress = ProgressService(client);
  late final ListsService lists = ListsService(client);
  late final TogetherService together = TogetherService(client);
  late final IntegrationsService integrations = IntegrationsService(client);
  late final PartnerService partner = PartnerService(client);
  late final CoViewVoteService coViewVote = CoViewVoteService(client);
  late final CoViewPollService coViewPoll = CoViewPollService(client);
  late final FriendsService friends = FriendsService(client);
  late final ActivityService activity = ActivityService(client);
  late final ImportService import_ = ImportService(client);
  late final SourcesService sources = SourcesService(client);

  AuthStatus status = AuthStatus.unknown;
  SeenlyUser? currentUser;

  // Best-effort cached copy of GET /profile/level's `level` field, kept
  // fresh without a network round trip at every call site that cares
  // about someone's current level (e.g. the profile header's level
  // ring). Starts at 1 (the level everyone's unlocked from the very
  // first log), and gets refreshed opportunistically
  // — on bootstrap, right after saving a diary entry (the moment a level-up
  // would actually happen), and whenever the profile screen fetches its
  // own copy for the level ring.
  int cachedLevel = 1;

  Future<void> refreshLevel() async {
    try {
      final level = await profile.level();
      if (cachedLevel == level.level) return;
      cachedLevel = level.level;
      notifyListeners();
    } catch (_) {
      // Best-effort — keep showing the last known level rather than
      // letting a network hiccup blank out the mascot everywhere.
    }
  }

  // A one-shot request for Profile's own shelf tab (0 watched / 1 plan
  // to watch / 2 watching now), set by another RootShell tab right
  // before switching to Profile — e.g. Diary's "pick something from
  // your shelf" strip landing on "plan to watch" specifically instead
  // of whichever tab Profile happened to be left on. ProfileScreen
  // reads and clears this via [consumePendingProfileTab] on its very
  // next build, so it never re-fires on a later, unrelated tab switch.
  int? pendingProfileTab;

  void requestProfileTab(int tab) {
    pendingProfileTab = tab;
    notifyListeners();
  }

  int? consumePendingProfileTab() {
    final tab = pendingProfileTab;
    pendingProfileTab = null;
    return tab;
  }

  final AppLinks _appLinks = AppLinks();

  /// Wires up the referral-link listener — see
  /// services/referral_link_service.dart's module docstring for the
  /// full picture. Called once from bootstrap(); safe to call again
  /// (e.g. hot restart during dev) since it just re-subscribes.
  Future<void> initReferralLinks() async {
    try {
      // app_links renamed getInitialAppLink -> getInitialLink in 6.4 —
      // see the ^6.3.2 constraint in pubspec.yaml, which allows that
      // rename to be pulled in automatically.
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handleIncomingLink(initial);
    } catch (_) {
      // No initial link, or the platform channel isn't wired up yet on
      // this build — same as "nothing to do" for every other soft
      // failure in this flow.
    }
    _appLinks.uriLinkStream.listen((uri) {
      _handleIncomingLink(uri);
    }, onError: (_) {});

    // iOS's one-shot clipboard fallback (see ReferralLinkService) —
    // only worth checking once we're sure there wasn't already a real
    // link waiting, so a genuine seenly://invite open always wins over
    // a stale clipboard value from an older share.
    final clipboardCode = await ReferralLinkService.checkClipboardOnce();
    if (clipboardCode != null) await _handleReferralCode(clipboardCode);

    // Android's real deferred deep link — see
    // ReferralLinkService.checkPlayInstallReferrerOnce's own docstring
    // for why this one actually works (official Play Services API,
    // vs. the iOS clipboard workaround above). No-op on every other
    // platform.
    final playReferrerCode = await ReferralLinkService.checkPlayInstallReferrerOnce();
    if (playReferrerCode != null) await _handleReferralCode(playReferrerCode);
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    final code = ReferralLinkService.extractFromUri(uri);
    if (code != null) await _handleReferralCode(code);
  }

  Future<void> _handleReferralCode(String code) async {
    if (status == AuthStatus.signedIn) {
      try {
        await friends.claimInvite(code);
      } catch (_) {
        // Stale/unknown code, or a network hiccup — see
        // routers/friends.py::claim_invite's own "quiet no-op" design;
        // nothing here should ever surface as a visible error over a
        // link tap.
      }
    } else {
      await ReferralLinkService.savePending(code);
    }
  }

  /// Applies whatever referral code is waiting (from a link tapped
  /// before the person had signed in) — called right after login/
  /// register succeed, below.
  Future<void> _applyPendingReferral() async {
    final code = await ReferralLinkService.takePending();
    if (code == null) return;
    try {
      await friends.claimInvite(code);
    } catch (_) {
      // Same "never block sign-in over this" reasoning as above.
    }
  }

  // Set for exactly one sign-in: the one right after register() creates a
  // brand-new account. Login and the bootstrap session-restore never set
  // this, so onboarding — which register() below advances into instead of
  // RootShell — only ever shows once per account, right after it's made.
  bool justRegistered = false;

  void finishOnboarding() {
    justRegistered = false;
    notifyListeners();
  }

  // Every "watching now" journey still running behind whatever screen is
  // on top, keyed by the title's own media id — see ActiveJourney's doc
  // comment. More than one title can be "in progress" at once (that's
  // the whole point of the "watching now" screen: someone can start a
  // film, wander off partway through, and start a different show later
  // without losing the first one), so this is a map rather than the
  // single nullable field it used to be. Empty means nothing's in
  // progress right now.
  final Map<String, ActiveJourney> activeJourneys = {};

  // Newest-first, so anything that only wants to show "the" current
  // journey (the badge, when more than one is running) has an obvious
  // pick without needing its own sort.
  List<ActiveJourney> get activeJourneysList =>
      activeJourneys.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  ActiveJourney? journeyFor(String itemId) => activeJourneys[itemId];

  void startJourney(ActiveJourney journey) {
    activeJourneys[journey.item.id] = journey;
    notifyListeners();
  }

  void clearJourney(String itemId) {
    if (activeJourneys.remove(itemId) == null) return;
    notifyListeners();
  }

  // Guarded the same way clearJourney() is against a missing/already-in-
  // that-state journey — pause/resume can be triggered from more than
  // one place now (the map's own button, the badge, or the "watching
  // now" screen), so this can't assume it's the only caller.
  void pauseJourney(String itemId) {
    final journey = activeJourneys[itemId];
    if (journey == null || journey.isPaused) return;
    activeJourneys[itemId] = journey.copyWith(pausedAt: DateTime.now());
    notifyListeners();
  }

  void resumeJourney(String itemId) {
    final journey = activeJourneys[itemId];
    if (journey == null || !journey.isPaused) return;
    activeJourneys[itemId] = journey.copyWith(
      clearPausedAt: true,
      pausedDuration: journey.pausedDuration + DateTime.now().difference(journey.pausedAt!),
    );
    notifyListeners();
  }

  Future<void> bootstrap() async {
    await client.loadToken();
    // Deep-link listener starts regardless of sign-in state — a code
    // tapped while signed out just gets stashed (see
    // ReferralLinkService.savePending) until login/register below apply
    // it, rather than only working for people who happen to already be
    // signed in.
    unawaited(initReferralLinks());
    if (!client.isAuthenticated) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    try {
      currentUser = await auth.me();
      status = AuthStatus.signedIn;
      unawaited(refreshLevel());
      await _applyPendingReferral();
    } catch (_) {
      // Stored token is stale/invalid — treat as signed out rather than
      // getting stuck showing a spinner forever.
      await client.setToken(null);
      status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    await auth.login(username, password);
    currentUser = await auth.me();
    status = AuthStatus.signedIn;
    unawaited(refreshLevel());
    await _applyPendingReferral();
    notifyListeners();
  }

  Future<void> register(String username, String password, {String? referralCode}) async {
    await auth.register(username, password, referralCode: referralCode);
    currentUser = await auth.me();
    status = AuthStatus.signedIn;
    justRegistered = true;
    // Covers the same-link-both-ways edge case: someone could type the
    // code by hand on this screen (referralCode above, handled entirely
    // server-side by /auth/register) *and* have gotten here via the
    // link's own pending code. claim_invite is a no-op once
    // referred_by_id is already set either way, so applying both is
    // always safe, never a double-credit.
    await _applyPendingReferral();
    notifyListeners();
  }

  Future<void> logout() async {
    await auth.logout();
    currentUser = null;
    status = AuthStatus.signedOut;
    justRegistered = false;
    notifyListeners();
  }

  /// Re-fetches /auth/me — used after editing name/avatar/status
  /// (EditProfileScreen) so the header reflects the change immediately
  /// without a full app restart.
  Future<void> refreshCurrentUser() async {
    currentUser = await auth.me();
    notifyListeners();
  }
}
