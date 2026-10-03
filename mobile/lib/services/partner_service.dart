import '../models/co_view_entry.dart';
import '../models/media_item.dart';
import '../models/partner_status.dart';
import '../models/suggestion.dart';
import 'api_client.dart';
import '../analytics/analytics.dart';

/// Talks to /partner — a standing pairing (link once with a code, stays
/// linked) plus the one-tap "suggest this for tonight" suggestions sent
/// over it. See backend/app/routers/partner.py for the reasoning.
class PartnerService {
  final ApiClient _client;
  PartnerService(this._client);

  Future<PartnerStatus> status() async {
    final json = await _client.get('/partner') as Map<String, dynamic>;
    return PartnerStatus.fromJson(json);
  }

  /// Generates (or re-fetches) a code to send to a partner.
  Future<PartnerStatus> pair() async {
    final json = await _client.post('/partner/pair') as Map<String, dynamic>;
    Analytics.instance.track('coview_pair_code_created');
    return PartnerStatus.fromJson(json);
  }

  /// Joins a partner's code (case-insensitive).
  Future<PartnerStatus> join(String code) async {
    final json = await _client.post('/partner/join', body: {
      'code': code.trim().toUpperCase(),
    }) as Map<String, dynamic>;
    Analytics.instance.track('coview_joined_by_code');
    return PartnerStatus.fromJson(json);
  }

  Future<void> unlink() => _client.delete('/partner');

  /// Invites one specific person straight into this account's
  /// co-viewing circle — no code to share. The one way to grow a
  /// couple into a company, and how the "invite to co-viewing" button
  /// on a friend's own profile works (see friend_profile_screen.dart).
  /// Starts a brand new circle on the spot if this account isn't linked
  /// to anyone yet.
  Future<PartnerInvite> sendInvite(String userId) async {
    final json = await _client.post('/partner/invite', body: {
      'user_id': userId,
    }) as Map<String, dynamic>;
    Analytics.instance.track('coview_invite_sent');
    return PartnerInvite.fromJson(json);
  }

  /// Every pending invite touching this account, split by direction —
  /// polled from the profile screen and anywhere else that shows
  /// invite state.
  Future<PartnerInvites> invites() async {
    final json = await _client.get('/partner/invites') as Map<String, dynamic>;
    return PartnerInvites.fromJson(json);
  }

  /// This account's taste match against each other member of its
  /// co-viewing circle — one row for a couple, one per other seat for a
  /// company. Powers the "мы" tab's compatibility section. Empty for an
  /// account not currently linked to anyone.
  Future<List<CircleCompatibility>> compatibility() async {
    final json = await _client.get('/partner/compatibility') as List;
    return json.map((e) => CircleCompatibility.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Accepting a direct invite joins the inviter's circle — a couple's
  /// worth if it's a fresh one, or the whole company if it's already
  /// grown past two.
  Future<PartnerStatus> acceptInvite(String inviteId) async {
    final json = await _client.post('/partner/invites/$inviteId/accept') as Map<String, dynamic>;
    Analytics.instance.track('coview_invite_accepted');
    return PartnerStatus.fromJson(json);
  }

  /// Also how the *sender* cancels their own still-pending invite — same
  /// "make this invite stop existing" action either way.
  Future<void> declineInvite(String inviteId) =>
      _client.post('/partner/invites/$inviteId/decline');

  /// The one-tap "I'm suggesting this for tonight" from a title screen.
  Future<void> suggest(MediaItem item) => _client.post('/partner/suggest', body: {
        'item': item.toJson(),
      });

  /// Polled from Home — every suggestion sent to this account that hasn't
  /// been dismissed yet, newest first.
  Future<List<Suggestion>> suggestions() async {
    final json = await _client.get('/partner/suggestions') as List;
    return json
        .map((e) => Suggestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> dismiss(String suggestionId) =>
      _client.delete('/partner/suggestions/$suggestionId');

  /// Agreeing to watch it — this is what actually moves the title onto
  /// the shared co-viewing list as "planned together". [date]/[hour]/
  /// [minute] carry whatever the plan-an-evening ritual picked (see
  /// plan_evening_sheet.dart's approvingSuggestion mode) — approving a
  /// suggestion *is* planning that evening, so it gets the same "when"
  /// as anything else planned, not a bare, dateless add.
  Future<CoViewEntry> acceptSuggestion(
    String suggestionId, {
    DateTime? date,
    int? hour,
    int? minute,
  }) async {
    final json = await _client.post('/partner/suggestions/$suggestionId/accept', body: {
      if (date != null) 'scheduled_date': date.toIso8601String(),
      'scheduled_hour': hour,
      'scheduled_minute': minute,
    }) as Map<String, dynamic>;
    return CoViewEntry.fromJson(json);
  }

  /// The shared co-viewing screen's whole state: both usernames plus the
  /// planned/watched split. Only ever called while linked.
  Future<CoViewList> coViewing() async {
    final json = await _client.get('/partner/co-viewing') as Map<String, dynamic>;
    return CoViewList.fromJson(json);
  }

  /// Mirrors a "plan an evening" ticket planned as co-viewing onto the
  /// shared co-viewing list, so a linked partner sees the same scheduled
  /// evening too (see PlannedEvening.coViewing and
  /// backend/app/routers/partner.py::plan_co_viewing). Only ever called
  /// while linked — the caller checks [PartnerStatus.linked] first.
  Future<CoViewEntry> planCoViewing(
    MediaItem item, {
    required DateTime date,
    int? hour,
    int? minute,
  }) async {
    final json = await _client.post('/partner/co-viewing/plan', body: {
      'item': item.toJson(),
      'scheduled_date': date.toIso8601String(),
      'scheduled_hour': hour,
      'scheduled_minute': minute,
    }) as Map<String, dynamic>;
    return CoViewEntry.fromJson(json);
  }

  /// Best-effort sync for the local pass-the-phone Watch Together mode —
  /// mirrors a round's matches onto the shared co-viewing list. Silently a
  /// no-op server-side when nobody's linked, so it's safe to always call
  /// after a local swipe round, linked or not.
  Future<void> syncLocalMatches(List<MediaItem> items) {
    if (items.isEmpty) return Future.value();
    return _client.post('/partner/co-viewing/bulk', body: {
      'items': items.map((e) => e.toJson()).toList(),
    });
  }

  /// Marks a co-viewing title watched — logs the same evening into *both*
  /// linked accounts' personal diaries server-side.
  /// Marks a shared title watched right now — same "client supplies its
  /// own local wall-clock instant" convention every other watched_at
  /// write already follows (see DiaryService.logEntry). Without this,
  /// the co-viewing screen was the one place that let the backend stamp
  /// a bare UTC instant instead, which the client always reads back as
  /// if it were local (see DiaryEntry.fromJson) — near a midnight
  /// boundary that could log the evening under the wrong calendar day.
  ///
  /// [alreadyLogged] is for the planned card's "смотрю" button (see
  /// CoViewHubScreen._openPlannedLogging): the caller has already been
  /// through the normal per-title logging ritual and written their own
  /// rated diary row themselves, so this call should only flip the
  /// CoViewEntry off "запланировано" — not write a second, bare row on
  /// top of it (or an unrated one for the other member(s), who didn't
  /// ask for that). Leave it false for a plain instant "mark watched"
  /// with no ritual involved, which still wants the old dual write.
  Future<CoViewEntry> markCoViewWatched(String entryId, {bool alreadyLogged = false}) async {
    final json = await _client.post('/partner/co-viewing/$entryId/watched', body: {
      'watched_at': DateTime.now().toIso8601String(),
      'already_logged': alreadyLogged,
    }) as Map<String, dynamic>;
    return CoViewEntry.fromJson(json);
  }

  /// Drops a title straight onto the shared "planned, whenever" list, no
  /// schedule attached — used to confirm a "pick for us" random draw.
  /// Same endpoint [planCoViewing] uses, just without a date.
  Future<CoViewEntry> addToPlanned(MediaItem item) async {
    final json = await _client.post('/partner/co-viewing/plan', body: {
      'item': item.toJson(),
    }) as Map<String, dynamic>;
    return CoViewEntry.fromJson(json);
  }

  Future<void> removeCoViewEntry(String entryId) =>
      _client.delete('/partner/co-viewing/$entryId');
}
