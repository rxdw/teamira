"""Tests for app/routers/referrals.py. The three real-human verification
conditions (entries, streak, days-since-signup) all key off actual
timestamps a real signup flow can't produce on demand within a test run
(nobody has a 5-day activity streak the moment they register) — so most
of this constructs the underlying Referral/ActivityEvent rows directly
via `db_session`, the same approach test_challenges.py uses for diary
rows, and calls _recompute_pending directly rather than only through
GET /status."""

from datetime import datetime, timedelta, timezone

from app import models
from app.routers import referrals


def _make_referral(db_session, referrer_id: str, referred_id: str, *, created_at, **overrides) -> models.Referral:
    fields = dict(
        referrer_id=referrer_id,
        referred_id=referred_id,
        status=models.ReferralStatus.pending,
        created_at=created_at,
    )
    fields.update(overrides)
    referral = models.Referral(**fields)
    db_session.add(referral)
    db_session.commit()
    return referral


def _make_activity_event(db_session, user_id: str, created_at) -> models.ActivityEvent:
    event = models.ActivityEvent(
        user_id=user_id, verb="marked_watched", media_title="x", media_type=models.MediaType.movie,
        created_at=created_at,
    )
    db_session.add(event)
    db_session.commit()
    return event


def _make_diary_entry(db_session, user_id: str) -> models.DiaryEntry:
    entry = models.DiaryEntry(
        user_id=user_id, media_id=f"tmdb-{models.gen_uuid()[:8]}", media_type=models.MediaType.movie,
        source="tmdb", title_en="x",
    )
    db_session.add(entry)
    db_session.commit()
    return entry


def _give_real_streak_and_entries(db_session, user_id: str, *, days: int, entries: int):
    """Enough ActivityEvent rows on `days` consecutive real calendar days
    (ending today) and enough DiaryEntry rows to satisfy both of
    _recompute_pending's non-time-since-signup conditions."""
    today = datetime.now(timezone.utc)
    for i in range(days):
        _make_activity_event(db_session, user_id, today - timedelta(days=i))
    for _ in range(entries):
        _make_diary_entry(db_session, user_id)


class TestNextMilestone:
    """_next_milestone replaces the old get_influencer_discount_percent/
    get_next_influencer_tier pair — same "pure function, easy to test
    at the boundaries" shape, just returning (threshold, days) off the
    MILESTONES ladder instead of a discount percent. Expressed off the
    live constants rather than hardcoded numbers, so a future tuning
    pass (the ladder's shape has already changed twice) doesn't leave
    these quietly wrong.
    """

    def test_before_the_first_tier(self):
        first = min(referrals.MILESTONES)
        assert referrals._next_milestone(0) == (first, referrals.MILESTONES[first])

    def test_between_named_tiers(self):
        tiers = sorted(referrals.MILESTONES)
        assert referrals._next_milestone(tiers[0]) == (tiers[1], referrals.MILESTONES[tiers[1]])

    def test_right_at_the_highest_named_tier(self):
        # The highest MILESTONES key is itself already paid out by now —
        # the next one due is the first recurring crossing past it.
        highest = max(referrals.MILESTONES)
        first_recurring = highest + referrals.RECURRING_MILESTONE_STEP
        assert referrals._next_milestone(highest) == (first_recurring, referrals.RECURRING_MILESTONE_DAYS)

    def test_recurring_tier_stops_at_the_ceiling(self):
        # Unlike the very first version of this ladder (which repeated
        # forever), a positive grant repeated without limit still adds
        # up to an unbounded total given enough confirmed referrals —
        # so RECURRING_MILESTONE_LAST_AT is a real ceiling: nothing
        # pays out past it, same (None, None) shape the old influencer
        # discount had at its own cap.
        last = referrals.RECURRING_MILESTONE_LAST_AT
        assert referrals._next_milestone(last) == (None, None)
        assert referrals._next_milestone(last + 1000) == (None, None)

    def test_recurring_tier_pays_out_right_up_to_the_ceiling(self):
        last = referrals.RECURRING_MILESTONE_LAST_AT
        step = referrals.RECURRING_MILESTONE_STEP
        assert referrals._next_milestone(last - step) == (last, referrals.RECURRING_MILESTONE_DAYS)

    def test_recurring_days_never_exceeds_the_ten_tier(self):
        # The explicit ask this replaced an earlier, bigger number for:
        # nothing past the named ladder should ever hand out more days
        # in one grant than the ladder's own biggest named tier already
        # does.
        assert referrals.RECURRING_MILESTONE_DAYS <= max(referrals.MILESTONES.values())

    def test_lifetime_maximum_is_bounded(self):
        # The number this whole file's comments quote (363 days) —
        # pinned here so it can't silently drift the next time either
        # constant gets tuned again without someone noticing the total
        # moved too.
        named_total = sum(referrals.MILESTONES.values())
        highest_named = max(referrals.MILESTONES)
        crossings = (referrals.RECURRING_MILESTONE_LAST_AT - highest_named) // referrals.RECURRING_MILESTONE_STEP
        lifetime_max = named_total + crossings * referrals.RECURRING_MILESTONE_DAYS
        assert lifetime_max == 363


class TestRecurringMilestoneGrant:
    """Integration-level: the actual ReferralReward rows a real
    verification produces once a referrer's confirmed count passes the
    named ladder. Referred users past the last one or two are seeded
    directly as already-rewarded rows rather than run through the full
    verify flow — see TestRecomputePending.test_daily_verification_cap's
    own comment for why (speed, not correctness: only the *last*
    confirmation in each block needs to go through the real path, since
    that's the one _grant_milestone_if_crossed actually has to act on)."""

    @staticmethod
    def _seed_confirmed(db_session, referrer_id: str, n: int, *, tag: str):
        for i in range(n):
            user = models.User(username=f"{tag}_{i}_{models.gen_uuid()[:6]}", password_hash="x")
            db_session.add(user)
            db_session.commit()
            _make_referral(
                db_session, referrer_id, user.id,
                created_at=datetime.now(timezone.utc), status=models.ReferralStatus.rewarded,
            )

    @staticmethod
    def _verify_one_more(db_session, register_user, referrer_id: str):
        person = register_user()
        _give_real_streak_and_entries(db_session, person.id, days=5, entries=3)
        _make_referral(
            db_session, referrer_id, person.id,
            created_at=datetime.now(timezone.utc) - timedelta(days=referrals.DAYS_SINCE_SIGNUP_REQUIRED + 1),
        )
        referrals._recompute_pending(db_session, referrer_id)

    def test_pays_out_at_the_first_recurring_crossing(self, db_session, register_user):
        first_crossing = max(referrals.MILESTONES) + referrals.RECURRING_MILESTONE_STEP
        alice = register_user()
        self._seed_confirmed(db_session, alice.id, first_crossing - 1, tag="rec1")
        self._verify_one_more(db_session, register_user, alice.id)  # crosses it

        reward = db_session.query(models.ReferralReward).filter_by(
            user_id=alice.id, reason=models.ReferralRewardReason.milestone_recurring,
        ).first()
        assert reward is not None
        assert reward.granted_days == referrals.RECURRING_MILESTONE_DAYS

    def test_fires_again_at_the_next_crossing(self, db_session, register_user):
        # The shared-reason "already granted?" check is scoped to this
        # specific referral's own source_referral_id (see
        # _grant_milestone_if_crossed's own docstring) — this is the
        # test that would fail if that check were reason-only instead,
        # the way the named-tier one is.
        step = referrals.RECURRING_MILESTONE_STEP
        first_crossing = max(referrals.MILESTONES) + step
        alice = register_user()
        self._seed_confirmed(db_session, alice.id, first_crossing - 1, tag="rec2a")
        self._verify_one_more(db_session, register_user, alice.id)  # first crossing
        self._seed_confirmed(db_session, alice.id, step - 1, tag="rec2b")
        self._verify_one_more(db_session, register_user, alice.id)  # second crossing

        rewards = db_session.query(models.ReferralReward).filter_by(
            user_id=alice.id, reason=models.ReferralRewardReason.milestone_recurring,
        ).all()
        assert len(rewards) == 2

    def test_nothing_pays_out_past_the_ceiling(self, db_session, register_user):
        # The case _next_milestone's own ceiling test checks the pure
        # function for — this is the same thing verified at the level
        # that actually matters: a real confirmed referral past
        # RECURRING_MILESTONE_LAST_AT must not create a ReferralReward
        # row at all, not just report (None, None) if asked.
        #
        # _seed_confirmed bypasses _grant_milestone_if_crossed entirely
        # (see its own docstring) — it creates the Referral rows but no
        # ReferralReward rows for any of them, milestone crossings on
        # the way to the ceiling included. So the only reward this test
        # could possibly produce is from the one referral that actually
        # goes through the real verify flow below, and that one is past
        # the ceiling — hence exactly zero, not a count of crossings.
        last = referrals.RECURRING_MILESTONE_LAST_AT
        alice = register_user()
        self._seed_confirmed(db_session, alice.id, last, tag="rec3")  # already at the ceiling
        self._verify_one_more(db_session, register_user, alice.id)  # one past it

        rewards = db_session.query(models.ReferralReward).filter_by(
            user_id=alice.id, reason=models.ReferralRewardReason.milestone_recurring,
        ).all()
        assert rewards == []


class TestCreateReferralForSignup:
    def test_creates_a_pending_row(self, db_session, register_user):
        alice = register_user()
        bob = register_user()
        referrals.create_referral_for_signup(db_session, alice.id, bob.id, ip="1.2.3.4")
        row = db_session.query(models.Referral).filter_by(referred_id=bob.id).first()
        assert row is not None
        assert row.status == models.ReferralStatus.pending
        assert row.referrer_id == alice.id

    def test_self_referral_is_ignored(self, db_session, register_user):
        alice = register_user()
        referrals.create_referral_for_signup(db_session, alice.id, alice.id, ip="1.2.3.4")
        assert db_session.query(models.Referral).filter_by(referred_id=alice.id).first() is None

    def test_is_idempotent_for_the_same_referred_id(self, db_session, register_user):
        alice = register_user()
        bob = register_user()
        referrals.create_referral_for_signup(db_session, alice.id, bob.id, ip="1.2.3.4")
        referrals.create_referral_for_signup(db_session, alice.id, bob.id, ip="1.2.3.4")
        rows = db_session.query(models.Referral).filter_by(referred_id=bob.id).all()
        assert len(rows) == 1

    def test_same_referrer_same_ip_twice_auto_rejects_the_second(self, db_session, register_user):
        alice = register_user()
        bob = register_user()
        carol = register_user()
        referrals.create_referral_for_signup(db_session, alice.id, bob.id, ip="9.9.9.9")
        referrals.create_referral_for_signup(db_session, alice.id, carol.id, ip="9.9.9.9")

        bobs_row = db_session.query(models.Referral).filter_by(referred_id=bob.id).first()
        carols_row = db_session.query(models.Referral).filter_by(referred_id=carol.id).first()
        assert bobs_row.status == models.ReferralStatus.pending
        assert carols_row.status == models.ReferralStatus.rejected

    def test_different_ips_are_both_accepted(self, db_session, register_user):
        alice = register_user()
        bob = register_user()
        carol = register_user()
        referrals.create_referral_for_signup(db_session, alice.id, bob.id, ip="1.1.1.1")
        referrals.create_referral_for_signup(db_session, alice.id, carol.id, ip="2.2.2.2")

        assert db_session.query(models.Referral).filter_by(referred_id=bob.id).first().status == models.ReferralStatus.pending
        assert db_session.query(models.Referral).filter_by(referred_id=carol.id).first().status == models.ReferralStatus.pending


class TestGrantPremiumDays:
    def test_creates_state_for_an_account_with_none(self, db_session, register_user):
        alice = register_user()
        referrals.grant_premium_days(db_session, alice.id, 10)
        state = db_session.get(models.UserPremiumState, alice.id)
        assert state is not None
        assert state.premium_expires_at > datetime.now(timezone.utc) + timedelta(days=9)

    def test_extends_a_still_active_expiry(self, db_session, register_user):
        alice = register_user()
        referrals.grant_premium_days(db_session, alice.id, 10)
        first_expiry = db_session.get(models.UserPremiumState, alice.id).premium_expires_at

        referrals.grant_premium_days(db_session, alice.id, 5)
        second_expiry = db_session.get(models.UserPremiumState, alice.id).premium_expires_at
        assert (second_expiry - first_expiry).days == 5

    def test_resets_from_now_if_already_expired(self, db_session, register_user):
        alice = register_user()
        state = models.UserPremiumState(
            user_id=alice.id, is_premium=False,
            premium_expires_at=datetime.now(timezone.utc) - timedelta(days=100),
        )
        db_session.add(state)
        db_session.commit()

        referrals.grant_premium_days(db_session, alice.id, 10)
        expiry = db_session.get(models.UserPremiumState, alice.id).premium_expires_at
        assert expiry > datetime.now(timezone.utc) + timedelta(days=9)


class TestRecomputePending:
    def test_stays_pending_without_enough_entries(self, db_session, register_user):
        alice = register_user()
        bob = register_user()
        _give_real_streak_and_entries(db_session, bob.id, days=5, entries=1)
        _make_referral(
            db_session, alice.id, bob.id,
            created_at=datetime.now(timezone.utc) - timedelta(days=referrals.DAYS_SINCE_SIGNUP_REQUIRED + 1),
        )
        referrals._recompute_pending(db_session, alice.id)
        row = db_session.query(models.Referral).filter_by(referred_id=bob.id).first()
        assert row.status == models.ReferralStatus.pending

    def test_stays_pending_without_enough_streak(self, db_session, register_user):
        alice = register_user()
        bob = register_user()
        _give_real_streak_and_entries(db_session, bob.id, days=2, entries=5)
        _make_referral(
            db_session, alice.id, bob.id,
            created_at=datetime.now(timezone.utc) - timedelta(days=referrals.DAYS_SINCE_SIGNUP_REQUIRED + 1),
        )
        referrals._recompute_pending(db_session, alice.id)
        row = db_session.query(models.Referral).filter_by(referred_id=bob.id).first()
        assert row.status == models.ReferralStatus.pending

    def test_stays_pending_before_the_signup_age_requirement(self, db_session, register_user):
        alice = register_user()
        bob = register_user()
        _give_real_streak_and_entries(db_session, bob.id, days=5, entries=5)
        _make_referral(db_session, alice.id, bob.id, created_at=datetime.now(timezone.utc) - timedelta(days=1))
        referrals._recompute_pending(db_session, alice.id)
        row = db_session.query(models.Referral).filter_by(referred_id=bob.id).first()
        assert row.status == models.ReferralStatus.pending

    def test_all_three_conditions_verifies_and_rewards_both_sides(self, db_session, register_user):
        alice = register_user()
        bob = register_user()
        _give_real_streak_and_entries(db_session, bob.id, days=5, entries=3)
        _make_referral(
            db_session, alice.id, bob.id,
            created_at=datetime.now(timezone.utc) - timedelta(days=referrals.DAYS_SINCE_SIGNUP_REQUIRED + 1),
        )
        referrals._recompute_pending(db_session, alice.id)

        row = db_session.query(models.Referral).filter_by(referred_id=bob.id).first()
        assert row.status == models.ReferralStatus.rewarded  # 1st verified -> crosses MILESTONES[1]
        assert row.verified_at is not None

        # The referred person's own welcome reward.
        bobs_reward = db_session.query(models.ReferralReward).filter_by(
            user_id=bob.id, reason=models.ReferralRewardReason.referred_welcome
        ).first()
        assert bobs_reward is not None
        assert bobs_reward.granted_days == referrals.REFERRED_WELCOME_DAYS

        # The referrer's milestone reward for reaching 1 verified invite.
        alices_reward = db_session.query(models.ReferralReward).filter_by(
            user_id=alice.id, reason=models.ReferralRewardReason.milestone_1
        ).first()
        assert alices_reward is not None
        assert alices_reward.granted_days == referrals.MILESTONES[1]

    def test_a_second_referral_that_does_not_cross_a_milestone_is_verified_not_rewarded(
        self, db_session, register_user
    ):
        alice = register_user()
        first = register_user()
        second = register_user()
        old = datetime.now(timezone.utc) - timedelta(days=referrals.DAYS_SINCE_SIGNUP_REQUIRED + 1)
        for referred in (first, second):
            _give_real_streak_and_entries(db_session, referred.id, days=5, entries=3)
            _make_referral(db_session, alice.id, referred.id, created_at=old)
        referrals._recompute_pending(db_session, alice.id)

        first_row = db_session.query(models.Referral).filter_by(referred_id=first.id).first()
        second_row = db_session.query(models.Referral).filter_by(referred_id=second.id).first()
        assert first_row.status == models.ReferralStatus.rewarded   # crossed milestone 1
        assert second_row.status == models.ReferralStatus.verified  # 2 verified isn't a milestone

    def test_daily_verification_cap(self, db_session, register_user):
        alice = register_user()
        old = datetime.now(timezone.utc) - timedelta(days=referrals.DAYS_SINCE_SIGNUP_REQUIRED + 1)
        # Created directly rather than via register_user() — that goes
        # through the real /auth/register endpoint, which is itself
        # rate-limited to 5/minute (see test_auth.py); DAILY_VERIFY_CAP+1
        # accounts in one test would trip that unrelated limiter before
        # ever reaching the behavior this test is actually about.
        referred_ids = []
        for i in range(referrals.DAILY_VERIFY_CAP + 1):
            user = models.User(username=f"daily_cap_{i}_{models.gen_uuid()[:6]}", password_hash="x")
            db_session.add(user)
            db_session.commit()
            referred_ids.append(user.id)
            _give_real_streak_and_entries(db_session, user.id, days=5, entries=3)
            _make_referral(db_session, alice.id, user.id, created_at=old)

        referrals._recompute_pending(db_session, alice.id)

        rows = db_session.query(models.Referral).filter_by(referrer_id=alice.id).all()
        verified_or_rewarded = [
            r for r in rows if r.status in (models.ReferralStatus.verified, models.ReferralStatus.rewarded)
        ]
        still_pending = [r for r in rows if r.status == models.ReferralStatus.pending]
        assert len(verified_or_rewarded) == referrals.DAILY_VERIFY_CAP
        assert len(still_pending) == 1


class TestPromoCode:
    def test_creates_one_lazily(self, db_session, register_user):
        alice = register_user()
        promo = referrals.get_or_create_promo_code(db_session, alice.id)
        assert promo.discount_percent == referrals.PROMO_DISCOUNT_PERCENT
        assert len(promo.code) == referrals._PROMO_CODE_LENGTH

    def test_is_idempotent(self, db_session, register_user):
        alice = register_user()
        first = referrals.get_or_create_promo_code(db_session, alice.id)
        second = referrals.get_or_create_promo_code(db_session, alice.id)
        assert first.code == second.code


class TestStatusHttp:
    def test_requires_auth(self, client):
        assert client.get("/referrals/status").status_code == 401

    def test_shape_for_a_fresh_account(self, client, register_user):
        alice = register_user()
        resp = client.get("/referrals/status", headers=alice.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["verified_count"] == 0
        assert body["referred"] == []
        assert body["promo_code"]
        assert body["next_milestone_at"] == 1
        assert body["next_milestone_days"] == referrals.MILESTONES[1]


class TestAdminEndpoints:
    def test_non_admin_gets_403(self, client, register_user):
        alice = register_user()
        assert client.get("/referrals/admin/suspicious", headers=alice.headers).status_code == 403

    def test_unauthenticated_gets_401(self, client):
        assert client.get("/referrals/admin/suspicious").status_code == 401

    def test_admin_can_list_and_reject(self, client, register_user, db_session):
        admin = register_user()
        user = db_session.get(models.User, admin.id)
        user.is_admin = True
        db_session.commit()

        alice = register_user()
        bob = register_user()
        rejected = _make_referral(
            db_session, alice.id, bob.id, created_at=datetime.now(timezone.utc), status=models.ReferralStatus.rejected
        )

        listed = client.get("/referrals/admin/suspicious", headers=admin.headers)
        assert listed.status_code == 200
        assert any(r["id"] == rejected.id for r in listed.json())

        carol = register_user()
        pending_row = _make_referral(db_session, alice.id, carol.id, created_at=datetime.now(timezone.utc))
        reject_resp = client.post(f"/referrals/admin/{pending_row.id}/reject", headers=admin.headers)
        assert reject_resp.status_code == 204
        assert db_session.get(models.Referral, pending_row.id).status == models.ReferralStatus.rejected

    def test_reject_unknown_id_is_404(self, client, register_user, db_session):
        admin = register_user()
        user = db_session.get(models.User, admin.id)
        user.is_admin = True
        db_session.commit()
        resp = client.post(
            "/referrals/admin/00000000-0000-0000-0000-000000000000/reject", headers=admin.headers
        )
        assert resp.status_code == 404
