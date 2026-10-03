import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';

import '../analytics/analytics.dart';
import '../models/active_journey.dart';
import '../models/profile_stats.dart';
import '../navigation.dart' show rootNavigatorKey;
import '../services/ai_service.dart';
import '../services/activity_service.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../services/card_share_service.dart';
import '../services/co_view_vote_service.dart';
import '../services/co_view_poll_service.dart';
import '../services/diary_service.dart';
import '../services/feed_service.dart';
import '../services/friends_service.dart';
import '../services/integrations_service.dart';
import '../services/import_service.dart';
import '../services/lists_service.dart';
import '../services/media_service.dart';
import '../services/moderation_service.dart';
import '../services/partner_service.dart';
import '../services/profile_service.dart';
import '../services/progress_service.dart';
import '../services/push_notification_manager.dart';
import '../services/push_service.dart';
import '../services/recommendation_service.dart';
import '../services/referral_link_service.dart';
import '../services/referral_service.dart';
import '../services/sincerity_service.dart';
import '../services/sources_service.dart';
import '../services/title_link_service.dart';
import '../services/watchlist_service.dart';
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
  late final CalendarService calendar = CalendarService(client);
  late final DiaryService diary = DiaryService(client);
  late final ProfileService profile = ProfileService(client);
  late final CardShareService cardShares = CardShareService(client);
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
  late final WatchlistService watchlist = WatchlistService(client);
  late final ReferralService referrals = ReferralService(client);
  late final SincerityService sincerity = SincerityService(client);
  late final RecommendationService recommendations = RecommendationService(client);
  late final ModerationService moderation = ModerationService(client);
  late final PushService pushApi = PushService(client);
  late final PushNotificationManager push = PushNotificationManager(pushApi, rootNavigatorKey);

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

  // Set by refreshLevel() when a save just pushed the cached level
  // higher — consumed once by whichever screen's "keep the stub"-style
  // button is about to hand off to checkAndCelebrateNewAchievements, so
  // the person sees the level-up moment in the same breath as any badge
  // that came with it, without every refreshLevel() call site needing
  // to thread the result through by hand. Same one-shot
  // request/consume shape as [pendingProfileTab] below.
  ProfileLevel? pendingLevelUp;

  ProfileLevel? consumePendingLevelUp() {
    final level = pendingLevelUp;
    pendingLevelUp = null;
    return level;
  }

  // Whether refreshLevel() has ever resolved successfully this session —
  // guards the very first fetch below from being mistaken for a genuine
  // level-up. cachedLevel starts at a hardcoded 1 every fresh app
  // launch/login, purely as an in-memory placeholder; it says nothing
  // about the account's real level until that first fetch lands. Without
  // this guard, bootstrap()'s and login()'s own refreshLevel() calls
  // would see any returning user above level 1 as having just "leveled
  // up" from 1 — a false positive that then sits in pendingLevelUp,
  // unconsumed, until the next unrelated diary save hands off to
  // checkAndCelebrateNewAchievements and wrongly celebrates a level the
  // person has had for weeks. Once true, every later call goes through
  // the normal "did the cached number actually go up" check below.
  bool _levelKnown = false;

  Future<void> refreshLevel() async {
    try {
      final level = await profile.level();
      if (!_levelKnown) {
        // First successful fetch this session — establish the real
        // baseline silently, never as a celebration.
        _levelKnown = true;
        cachedLevel = level.level;
        notifyListeners();
        return;
      }
      if (cachedLevel == level.level) return;
      if (level.level > cachedLevel) {
        pendingLevelUp = level;
      }
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

  /// A password-reset token that arrived by deep link and hasn't been
  /// shown yet. The link opens the app at whatever screen it was on, so
  /// the token is parked here and the login screen picks it up on its
  /// next build (see LoginScreen.initState) — pushing a route from a
  /// stream callback would race whatever navigation is already in
  /// flight from a cold start.
  String? pendingPasswordResetToken;

  String? consumePendingPasswordResetToken() {
    final token = pendingPasswordResetToken;
    pendingPasswordResetToken = null;
    return token;
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    // Reset links come in two shapes: the app's own custom scheme
    // (`seenly://reset-password?token=...`), and the https landing page
    // once App/Universal Links are configured natively
    // (`https://<site>/reset-password?token=...`). Matching on the path
    // segment rather than the scheme covers both without the app needing
    // to know which one it was opened by.
    final token = uri.queryParameters['token'];
    if (token != null && token.isNotEmpty) {
      final where = '${uri.host}${uri.path}';
      if (where.contains('reset-password') || where.contains('reset')) {
        pendingPasswordResetToken = token;
        notifyListeners();
        return;
      }
      if (where.contains('verify-email') || where.contains('verify')) {
        // Verification needs no screen at all — it either works or the
        // link is stale, and either way the person is told once. Doing it
        // silently here means tapping the link in the mail app just
        // works, which is the whole point of sending one.
        try {
          await auth.verifyEmail(token);
          if (currentUser != null) await refreshCurrentUser();
        } catch (_) {
          // Stale or already-used link. The Account screen shows the
          // real state, and offers to send a fresh link.
        }
        return;
      }
    }

    final code = ReferralLinkService.extractFromUri(uri);
    if (code != null) {
      await _handleReferralCode(code);
      return;
    }
    // Same host, different query params — only ever one or the other,
    // so trying this second (rather than in parallel) is enough.
    final titleLink = TitleLinkService.extractFromUri(uri);
    if (titleLink != null) await _handleTitleLink(titleLink);
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

  // A one-shot request to open a specific title, set either the instant
  // a shared-title link arrives while already signed in, or right after
  // sign-in applies one that arrived earlier — see [_handleTitleLink]
  // and [_applyPendingTitleLink]. Same request/consume shape as
  // [pendingProfileTab] above, just consumed by RootShell (which pushes
  // TitleDetailScreen for it) instead of ProfileScreen.
  PendingTitleLink? pendingTitleLink;

  PendingTitleLink? consumePendingTitleLink() {
    final link = pendingTitleLink;
    pendingTitleLink = null;
    return link;
  }

  // One-shot: set true the moment onboarding finishes, consumed by
  // RootShell the same way pendingTitleLink is (see
  // consumePendingOnboardingPaywall below) — shows the paywall once,
  // softly, shortly after a brand-new account first lands on Home.
  // Never set again afterward, so it can only ever fire the one time
  // per account that finishOnboarding() itself only ever runs.
  bool pendingOnboardingPaywall = false;

  bool consumePendingOnboardingPaywall() {
    final pending = pendingOnboardingPaywall;
    pendingOnboardingPaywall = false;
    return pending;
  }

  // One-shot: set true the moment two accounts freshly link into a
  // co-viewing couple — see the three call sites that set it via
  // [notePartnerJustLinked] (home_screen.dart::_CoViewingCardState.
  // _submitJoin, widgets/plan_evening_sheet.dart::_submitJoin,
  // friend_profile_screen.dart::_acceptCoviewInvite), all of which just
  // got a fresh PartnerStatus back with exactly two members on it —
  // the couple's first moment, not a company growing further. Consumed
  // by RootShell the same one-shot way as [pendingTitleLink] (postFrame
  // check on mount *and* a live listener, since — unlike
  // [pendingOnboardingPaywall], which is always set before RootShell's
  // very first frame — linking can happen at any point while RootShell
  // is already sitting underneath other pushed screens).
  bool pendingPartnerLinkedPaywall = false;

  bool consumePendingPartnerLinkedPaywall() {
    final pending = pendingPartnerLinkedPaywall;
    pendingPartnerLinkedPaywall = false;
    return pending;
  }

  /// Call right after a join/accept succeeds and leaves the circle at
  /// exactly two people — see [pendingPartnerLinkedPaywall]'s own doc
  /// comment for why that count alone means "just became a couple"
  /// with no extra bookkeeping needed. No-ops for an account that's
  /// already premium — nothing to soft-offer there.
  void notePartnerJustLinked() {
    if (pendingPartnerLinkedPaywall) return;
    pendingPartnerLinkedPaywall = true;
    Analytics.instance.track('partner_linked_paywall_queued');
    notifyListeners();
  }

  Future<void> _handleTitleLink(PendingTitleLink link) async {
    if (status == AuthStatus.signedIn) {
      pendingTitleLink = link;
      notifyListeners();
    } else {
      await TitleLinkService.savePending(link);
    }
  }

  /// Applies whatever title link is waiting (tapped before sign-in) —
  /// called right alongside _applyPendingReferral() below, same timing.
  Future<void> _applyPendingTitleLink() async {
    final link = await TitleLinkService.takePending();
    if (link == null) return;
    pendingTitleLink = link;
    notifyListeners();
  }

  // Set for exactly one sign-in: the one right after register() creates a
  // brand-new account. Login and the bootstrap session-restore never set
  // this, so onboarding — which register() below advances into instead of
  // RootShell — only ever shows once per account, right after it's made.
  bool justRegistered = false;

  void finishOnboarding() {
    justRegistered = false;
    pendingOnboardingPaywall = true;
    Analytics.instance.track('onboarding_completed');
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

  /// Set when the server ends the session out from under us — a revoked
  /// token, a password changed on another device, a suspension, or an
  /// account deleted elsewhere. The login screen reads it once and shows
  /// it, so the person knows *why* they're being asked to sign in again
  /// instead of being dumped at a login form with no explanation.
  String? sessionEndedNotice;

  String? consumeSessionEndedNotice() {
    final notice = sessionEndedNotice;
    sessionEndedNotice = null;
    return notice;
  }

  /// Called by ApiClient when a refresh definitively fails. Everything
  /// below the shell is rebuilt by the `status` flip, so there's no
  /// navigation to do here — screens that were mid-request will surface
  /// a SessionExpiredException and simply be replaced.
  void _handleSessionExpired() {
    if (status == AuthStatus.signedOut) return;
    Analytics.instance.track('session_expired');
    currentUser = null;
    status = AuthStatus.signedOut;
    sessionEndedNotice = 'your session ended — please sign in again';
    _levelKnown = false;
    cachedLevel = 1;
    pendingLevelUp = null;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    // Wired before the first request goes out, so an expired token found
    // during bootstrap itself takes the same path as one that expires an
    // hour into a session.
    client.onSessionExpired = _handleSessionExpired;
    await client.loadTokens();
    // Sets up Firebase + the tap/foreground listeners regardless of
    // sign-in state, same reasoning as the deep-link listener right
    // below — registerDeviceToken() (which needs an actual account to
    // attach a token to) only happens once status reaches signedIn, a
    // few lines down and in login()/register() below.
    unawaited(push.init());
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
      unawaited(push.registerDeviceToken());
      await _applyPendingReferral();
      await _applyPendingTitleLink();
    } catch (_) {
      // Stored token is stale/invalid — treat as signed out rather than
      // getting stuck showing a spinner forever.
      await client.clearTokens();
      status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    await auth.login(username, password);
    currentUser = await auth.me();
    status = AuthStatus.signedIn;
    Analytics.instance.track('login');
    unawaited(refreshLevel());
    unawaited(push.registerDeviceToken());
    await _applyPendingReferral();
    await _applyPendingTitleLink();
    notifyListeners();
  }

  Future<void> register(String username, String password, {String? referralCode}) async {
    await auth.register(username, password, referralCode: referralCode);
    currentUser = await auth.me();
    status = AuthStatus.signedIn;
    justRegistered = true;
    Analytics.instance.track('signup', {
      // The code itself is never sent — only whether one was used.
      'has_referral_code': referralCode != null && referralCode.isNotEmpty,
    });
    unawaited(push.registerDeviceToken());
    // Covers the same-link-both-ways edge case: someone could type the
    // code by hand on this screen (referralCode above, handled entirely
    // server-side by /auth/register) *and* have gotten here via the
    // link's own pending code. claim_invite is a no-op once
    // referred_by_id is already set either way, so applying both is
    // always safe, never a double-credit.
    await _applyPendingReferral();
    await _applyPendingTitleLink();
    notifyListeners();
  }

  Future<void> logout() async {
    // Send what's queued while the access token still exists, so this
    // session's events stay attributed to the account it belonged to.
    Analytics.instance.track('logout');
    try {
      await Analytics.instance.flush(force: true).timeout(const Duration(seconds: 3));
    } catch (_) {}
    unawaited(push.unregisterDeviceToken());
    await auth.logout();
    currentUser = null;
    sessionEndedNotice = null;
    status = AuthStatus.signedOut;
    justRegistered = false;
    // Otherwise a second account signed into in the same app run would
    // inherit the previous account's cached level as its "starting
    // point" — logging in as someone on a different level would then
    // immediately misfire refreshLevel()'s level-up check the same way
    // a stale in-memory default would on a fresh launch.
    _levelKnown = false;
    cachedLevel = 1;
    pendingLevelUp = null;
    notifyListeners();
  }

  /// Called by the EULA gate once acceptance is recorded server-side.
  /// Re-fetching /auth/me would also work and would be one more round
  /// trip on a screen the person is waiting on — the server has already
  /// confirmed the write, so mirroring it locally is enough to let the
  /// gate fall through to Home.
  void markEulaAccepted() {
    final user = currentUser;
    if (user == null) return;
    currentUser = SeenlyUser(
      id: user.id,
      username: user.username,
      createdAt: user.createdAt,
      displayName: user.displayName,
      avatarPreset: user.avatarPreset,
      avatarUrl: user.avatarUrl,
      statusText: user.statusText,
      email: user.email,
      emailVerified: user.emailVerified,
      eulaCurrent: true,
      isAdmin: user.isAdmin,
    );
    Analytics.instance.track('eula_accepted');
    notifyListeners();
  }

  /// Deletes the account. The session is already cleared by the time
  /// this returns (AuthService does it), so all that's left is flipping
  /// the app back to signed-out — the confirmation of *when* the data is
  /// actually erased is shown by the screen that called this, since it's
  /// the one thing the person needs to read before the app changes under
  /// them.
  Future<AccountDeletion> deleteAccount(String password, {String? reason}) async {
    final result = await auth.deleteAccount(password, reason: reason);
    // The server erases this device's analytics history when the account is
    // purged; from here on the device is a stranger to it.
    await Analytics.instance.resetIdentity();
    currentUser = null;
    status = AuthStatus.signedOut;
    justRegistered = false;
    _levelKnown = false;
    cachedLevel = 1;
    pendingLevelUp = null;
    notifyListeners();
    return result;
  }

  /// Undoes a deletion inside the grace window. Authenticates with the
  /// password rather than a token — there is no token left, by design.
  Future<void> restoreAccount(String username, String password) async {
    await auth.restoreAccount(username, password);
    currentUser = await auth.me();
    status = AuthStatus.signedIn;
    Analytics.instance.track('account_restored');
    sessionEndedNotice = null;
    unawaited(refreshLevel());
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
