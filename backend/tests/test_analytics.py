"""POST /analytics/events and the things around it: identity, forgiveness,
idempotency, privacy rules on props, erasure on account purge, retention,
and the reporting views.

The endpoint's contract is easy to get subtly wrong in ways that only show
up in production (a retried batch double-counting, an expired token turning
into a 401 that signs someone out of the app, note text leaking through a
prop), so most of these tests exist to pin exactly those.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import text

from app import account_deletion, models
from app.config import settings


def _id() -> str:
    return uuid.uuid4().hex[:20]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.isoformat().replace("+00:00", "Z")


def _event(name: str = "screen_view", *, ts: datetime | None = None, sid: str | None = None, **extra) -> dict:
    ev = {"id": _id(), "name": name, "ts": _iso(ts or _now()), "sid": sid or "session_aaaaaaaa"}
    ev.update(extra)
    return ev


def _batch(events: list[dict], anon_id: str | None = None, **extra) -> dict:
    body = {"anon_id": anon_id or f"anon_{_id()}", "platform": "android", "app_version": "dev", "build": "release", "locale": "ru", "events": events}
    body.update(extra)
    return body


def _rows(db_session, anon_id: str) -> list[models.AnalyticsEvent]:
    return (
        db_session.query(models.AnalyticsEvent)
        .filter(models.AnalyticsEvent.anon_id == anon_id)
        .order_by(models.AnalyticsEvent.ts, models.AnalyticsEvent.id)
        .all()
    )


class TestIngest:
    def test_anonymous_batch_is_stored(self, client, db_session):
        body = _batch([_event(screen="DiaryScreen", props={"nav": "tab"}), _event("app_open")])
        resp = client.post("/analytics/events", json=body)
        assert resp.status_code == 202, resp.text
        assert resp.json() == {"accepted": 2, "rejected": 0}

        rows = _rows(db_session, body["anon_id"])
        assert [r.name for r in rows] == ["screen_view", "app_open"] or {r.name for r in rows} == {"screen_view", "app_open"}
        screen_row = next(r for r in rows if r.name == "screen_view")
        assert screen_row.screen == "DiaryScreen"
        assert screen_row.props == {"nav": "tab"}
        assert screen_row.user_id is None
        assert (screen_row.platform, screen_row.build, screen_row.locale) == ("android", "release", "ru")

    def test_signed_in_batch_gets_user_id_from_token(self, client, db_session, register_user):
        user = register_user()
        body = _batch([_event()])
        resp = client.post("/analytics/events", json=body, headers=user.headers)
        assert resp.status_code == 202
        assert _rows(db_session, body["anon_id"])[0].user_id == user.id

    def test_garbage_token_is_anonymous_not_401(self, client, db_session):
        """An expired/revoked token must never turn a statistics call into
        a 401 — the mobile client would try to refresh, or sign the person
        out. It just means 'anonymous'."""
        body = _batch([_event()])
        resp = client.post("/analytics/events", json=body, headers={"Authorization": "Bearer not-a-real-token"})
        assert resp.status_code == 202
        assert _rows(db_session, body["anon_id"])[0].user_id is None

    def test_user_id_in_body_is_ignored(self, client, db_session, register_user):
        victim = register_user()
        body = _batch([_event()], user_id=victim.id)
        body["events"][0]["user_id"] = victim.id
        resp = client.post("/analytics/events", json=body)
        assert resp.status_code == 202
        assert _rows(db_session, body["anon_id"])[0].user_id is None

    def test_soft_deleted_account_is_anonymous(self, client, db_session, register_user):
        user = register_user()
        row = db_session.get(models.User, user.id)
        row.deleted_at = _now()
        db_session.flush()
        body = _batch([_event()])
        resp = client.post("/analytics/events", json=body, headers=user.headers)
        assert resp.status_code == 202
        assert _rows(db_session, body["anon_id"])[0].user_id is None

    def test_retried_batch_is_not_double_counted(self, client, db_session):
        body = _batch([_event(), _event("app_open")])
        first = client.post("/analytics/events", json=body)
        second = client.post("/analytics/events", json=body)
        assert first.json()["accepted"] == 2
        assert second.json()["accepted"] == 0
        assert len(_rows(db_session, body["anon_id"])) == 2

    def test_partial_retry_only_inserts_the_new_events(self, client, db_session):
        e1, e2, e3 = _event(), _event(), _event()
        anon = f"anon_{_id()}"
        client.post("/analytics/events", json=_batch([e1, e2], anon_id=anon))
        resp = client.post("/analytics/events", json=_batch([e2, e3], anon_id=anon))
        assert resp.json()["accepted"] == 1
        assert len(_rows(db_session, anon)) == 3

    def test_empty_batch_is_fine(self, client):
        resp = client.post("/analytics/events", json=_batch([]))
        assert resp.status_code == 202
        assert resp.json() == {"accepted": 0, "rejected": 0}


class TestForgiveness:
    def test_bad_events_are_dropped_and_counted_good_ones_kept(self, client, db_session):
        good = _event(screen="HomeScreen")
        bad = [
            {"id": _id(), "name": "Screen View", "ts": _iso(_now()), "sid": "session_aaaaaaaa"},   # bad name
            {"id": "x", "name": "screen_view", "ts": _iso(_now()), "sid": "session_aaaaaaaa"},      # bad id
            {"id": _id(), "name": "screen_view", "ts": "yesterday", "sid": "session_aaaaaaaa"},     # bad ts
            {"id": _id(), "name": "screen_view", "ts": _iso(_now())},                                # no sid
            "not even a dict",
        ]
        body = _batch([good, *bad])
        resp = client.post("/analytics/events", json=body)
        assert resp.status_code == 202
        assert resp.json() == {"accepted": 1, "rejected": 5}
        assert len(_rows(db_session, body["anon_id"])) == 1

    def test_bad_screen_name_is_nulled_not_rejected(self, client, db_session):
        body = _batch([_event(screen="drop table; --")])
        client.post("/analytics/events", json=body)
        rows = _rows(db_session, body["anon_id"])
        assert len(rows) == 1 and rows[0].screen is None

    def test_future_timestamp_is_clamped_to_now(self, client, db_session):
        body = _batch([_event(ts=_now() + timedelta(days=3))])
        client.post("/analytics/events", json=body)
        stored = _rows(db_session, body["anon_id"])[0].ts
        assert stored <= _now() + timedelta(seconds=5)

    def test_very_old_event_is_rejected(self, client):
        resp = client.post("/analytics/events", json=_batch([_event(ts=_now() - timedelta(days=30))]))
        assert resp.json() == {"accepted": 0, "rejected": 1}

    def test_offline_backlog_within_two_weeks_is_kept(self, client, db_session):
        body = _batch([_event(ts=_now() - timedelta(days=5))])
        client.post("/analytics/events", json=body)
        assert len(_rows(db_session, body["anon_id"])) == 1


class TestEnvelope:
    def test_bad_anon_id_is_422(self, client):
        assert client.post("/analytics/events", json=_batch([_event()], anon_id="short")).status_code == 422
        assert client.post("/analytics/events", json=_batch([_event()], anon_id="has spaces in it!")).status_code == 422

    def test_too_many_events_is_422(self, client):
        events = [_event() for _ in range(101)]
        assert client.post("/analytics/events", json=_batch(events)).status_code == 422

    def test_exactly_the_maximum_is_fine(self, client):
        events = [_event() for _ in range(100)]
        resp = client.post("/analytics/events", json=_batch(events))
        assert resp.status_code == 202 and resp.json()["accepted"] == 100

    def test_unknown_build_value_is_422(self, client):
        assert client.post("/analytics/events", json=_batch([_event()], build="nightly")).status_code == 422


class TestPropsPrivacy:
    def _stored_props(self, client, db_session, props):
        body = _batch([_event("search_performed", props=props)])
        assert client.post("/analytics/events", json=body).status_code == 202
        return _rows(db_session, body["anon_id"])[0].props

    def test_scalars_survive(self, client, db_session):
        props = {"media_type": "movie", "results": 12, "has_note": True, "ratio": 0.5, "nothing": None}
        assert self._stored_props(client, db_session, props) == props

    def test_nested_values_are_dropped(self, client, db_session):
        stored = self._stored_props(client, db_session, {"ok": "yes", "list": [1, 2], "obj": {"a": 1}})
        assert stored == {"ok": "yes"}

    def test_email_like_strings_are_dropped(self, client, db_session):
        stored = self._stored_props(client, db_session, {"ok": "yes", "leak": "someone@example.com"})
        assert stored == {"ok": "yes"}

    def test_long_strings_are_truncated(self, client, db_session):
        stored = self._stored_props(client, db_session, {"note": "x" * 5000})
        assert len(stored["note"]) == 120

    def test_bad_keys_are_dropped(self, client, db_session):
        stored = self._stored_props(client, db_session, {"Good": 1, "has space": 1, "fine_key": 1})
        assert stored == {"fine_key": 1}

    def test_prop_count_is_capped(self, client, db_session):
        stored = self._stored_props(client, db_session, {f"k{i}": i for i in range(50)})
        assert len(stored) == 20

    def test_all_props_invalid_stores_null(self, client, db_session):
        assert self._stored_props(client, db_session, {"Bad": 1}) is None


class TestSwitchesAndLimits:
    def test_disabled_server_side_accepts_but_stores_nothing(self, client, db_session, monkeypatch):
        monkeypatch.setattr(settings, "analytics_enabled", False)
        body = _batch([_event()])
        resp = client.post("/analytics/events", json=body)
        assert resp.status_code == 202
        assert resp.json() == {"accepted": 0, "rejected": 0}
        assert _rows(db_session, body["anon_id"]) == []

    def test_per_device_rate_limit(self, client):
        anon = f"anon_{_id()}"
        codes = [client.post("/analytics/events", json=_batch([_event()], anon_id=anon)).status_code for _ in range(22)]
        assert codes[:20] == [202] * 20
        assert codes[20:] == [429, 429]


class TestErasureAndRetention:
    def test_purge_user_erases_their_events_and_their_devices(self, client, db_session, register_user):
        user = register_user()
        other = register_user()
        my_device, their_device, stranger_device = f"anon_{_id()}", f"anon_{_id()}", f"anon_{_id()}"

        # Before login the device only has an anon_id; after login the same
        # device's events carry the user_id too.
        client.post("/analytics/events", json=_batch([_event("app_open")], anon_id=my_device))
        client.post("/analytics/events", json=_batch([_event()], anon_id=my_device), headers=user.headers)
        client.post("/analytics/events", json=_batch([_event()], anon_id=their_device), headers=other.headers)
        client.post("/analytics/events", json=_batch([_event()], anon_id=stranger_device))

        account_deletion.purge_user(db_session, db_session.get(models.User, user.id))

        assert _rows(db_session, my_device) == []          # both rows, incl. the pre-login one
        assert len(_rows(db_session, their_device)) == 1   # someone else, untouched
        assert len(_rows(db_session, stranger_device)) == 1

    def test_retention_sweep_deletes_only_old_rows(self, client, db_session, monkeypatch):
        monkeypatch.setattr(settings, "analytics_retention_days", 30)
        anon = f"anon_{_id()}"
        old = models.AnalyticsEvent(event_id=_id(), ts=_now() - timedelta(days=45), anon_id=anon, session_id="s_old_aaaa", name="app_open")
        fresh = models.AnalyticsEvent(event_id=_id(), ts=_now() - timedelta(days=2), anon_id=anon, session_id="s_new_aaaa", name="app_open")
        db_session.add_all([old, fresh])
        db_session.flush()

        account_deletion.sweep_expired_artifacts(db_session)

        remaining = _rows(db_session, anon)
        assert [r.event_id for r in remaining] == [fresh.event_id]

    def test_retention_zero_keeps_everything(self, db_session, monkeypatch):
        monkeypatch.setattr(settings, "analytics_retention_days", 0)
        anon = f"anon_{_id()}"
        db_session.add(models.AnalyticsEvent(event_id=_id(), ts=_now() - timedelta(days=900), anon_id=anon, session_id="s_old_aaaa", name="app_open"))
        db_session.flush()
        account_deletion.sweep_expired_artifacts(db_session)
        assert len(_rows(db_session, anon)) == 1


class TestViews:
    def test_screen_view_duration_is_time_until_next_event_and_capped(self, db_session):
        anon, sid = f"anon_{_id()}", f"sess_{_id()}"
        t0 = _now() - timedelta(minutes=30)

        def add(name, offset_s, screen=None, props=None):
            db_session.add(models.AnalyticsEvent(
                event_id=_id(), ts=t0 + timedelta(seconds=offset_s), anon_id=anon, session_id=sid,
                name=name, screen=screen, props=props, build="release",
            ))

        add("screen_view", 0, "HomeScreen", {"nav": "tab"})
        add("screen_view", 40, "DiaryScreen", {"nav": "push"})
        add("tap_something", 41)                     # not a screen change: must not end DiaryScreen's stay
        add("screen_view", 40 + 3000, "TitleDetailScreen")  # 50 min later: DiaryScreen capped at 600 s
        add("app_background", 40 + 3000 + 12)
        db_session.flush()

        rows = db_session.execute(
            text("SELECT screen, nav, seconds_on_screen FROM v_analytics_screen_views WHERE anon_id = :a ORDER BY ts"),
            {"a": anon},
        ).all()
        assert [(r.screen, r.nav, r.seconds_on_screen) for r in rows] == [
            ("HomeScreen", "tab", 40),
            ("DiaryScreen", "push", 600),
            ("TitleDetailScreen", "push", 12),
        ]

    def test_daily_views_aggregate(self, db_session):
        anon = f"anon_{_id()}"
        for name in ("app_open", "diary_entry_logged", "diary_entry_logged"):
            db_session.add(models.AnalyticsEvent(event_id=_id(), ts=_now(), anon_id=anon, session_id="s_aaaaaaaa", name=name, build="release"))
        db_session.flush()
        counts = dict(db_session.execute(text(
            "SELECT name, events FROM v_analytics_events_daily WHERE day = (now() AT TIME ZONE 'UTC')::date AND build = 'release'"
        )).all())
        assert counts["diary_entry_logged"] >= 2
        active = db_session.execute(text(
            "SELECT active_devices FROM v_analytics_daily_active WHERE day = (now() AT TIME ZONE 'UTC')::date AND build = 'release'"
        )).scalar()
        assert active >= 1


class TestReport:
    """scripts/analytics_report.py against synthetic traffic. These assert
    on the numbers and on the 'never opened' call-out, since that last one
    is the reason the report exists."""

    @staticmethod
    def _seed(db_session, monkeypatch):
        from scripts import analytics_report

        monkeypatch.setattr(analytics_report, "_load_registry", lambda: ["HomeScreen", "DiaryScreen", "PremiumScreen", "GiftPremiumScreen"])
        now = _now()
        counter = {"n": 0}

        def ev(anon, sid, name, offset_s, screen=None, props=None, build="release", user_id=None):
            counter["n"] += 1
            db_session.add(models.AnalyticsEvent(
                event_id=f"seed_{uuid.uuid4().hex[:16]}_{counter['n']}", ts=now - timedelta(seconds=offset_s), anon_id=anon,
                session_id=sid, name=name, screen=screen, props=props, build=build, user_id=user_id,
                platform="android", app_version="1.0", locale="ru",
            ))

        # Device A: home -> diary -> premium, logs an evening, finishes onboarding.
        a, sa = f"anon_A{_id()}", f"sess_A{_id()}"
        ev(a, sa, "app_open", 600)
        ev(a, sa, "screen_view", 590, "OnboardingScreen", {"nav": "gate", "kind": "screen"})
        for step in range(1, 10):
            ev(a, sa, "onboarding_step", 590 - step * 10, props={"step": step})
        ev(a, sa, "onboarding_completed", 480)
        ev(a, sa, "screen_view", 470, "HomeScreen", {"nav": "tab", "kind": "screen"}, user_id="u1")
        ev(a, sa, "screen_view", 400, "DiaryScreen", {"nav": "tab", "kind": "screen"}, user_id="u1")
        ev(a, sa, "search_performed", 390, props={"results": 0})
        ev(a, sa, "search_performed", 380, props={"results": 5})
        ev(a, sa, "diary_entry_logged", 300, props={"media_type": "movie"})
        ev(a, sa, "screen_view", 200, "PremiumScreen", {"nav": "push", "kind": "screen"}, user_id="u1")
        ev(a, sa, "screen_view", 100, "DiaryScreen", {"nav": "back", "kind": "screen"}, user_id="u1")
        ev(a, sa, "app_background", 50)
        # Device B: only home.
        b, sb = f"anon_B{_id()}", f"sess_B{_id()}"
        ev(b, sb, "app_open", 300)
        ev(b, sb, "screen_view", 290, "HomeScreen", {"nav": "tab", "kind": "screen"})
        ev(b, sb, "screen_view", 250, "PlanEveningSheet", {"nav": "push", "kind": "sheet"})
        ev(b, sb, "app_background", 200)
        # A debug-build device that must vanish under --build release.
        c, sc = f"anon_C{_id()}", f"sess_C{_id()}"
        ev(c, sc, "screen_view", 100, "GiftPremiumScreen", {"nav": "push", "kind": "screen"}, build="debug")
        db_session.flush()
        return analytics_report

    def test_report_ranks_screens_and_calls_out_never_opened(self, db_session, monkeypatch):
        report = self._seed(db_session, monkeypatch)
        out = report.build_report(db_session, days=7, build="release")

        home = next(line for line in out.splitlines() if "HomeScreen" in line and "открытий" not in line)
        assert home.split()[2:4] == ["2", "2"]                      # 2 views, 2 devices
        diary = next(line for line in out.splitlines() if line.strip().split()[1:2] == ["DiaryScreen"])
        assert diary.split()[2] == "1"                              # the 'back' return is not an extra open
        assert "PlanEveningSheet" in out

        never = out.split("не открыли НИ РАЗУ")[1].split("\n\n")[0]
        assert "GiftPremiumScreen" in never                         # only opened on a debug build -> filtered out
        assert "HomeScreen" not in never and "PremiumScreen\n" not in never.replace("GiftPremiumScreen", "")

    def test_build_filter_changes_the_answer(self, db_session, monkeypatch):
        report = self._seed(db_session, monkeypatch)
        everything = report.build_report(db_session, days=7, build="all")
        never_all = everything.split("не открыли НИ РАЗУ")[1].split("\n\n")[0]
        assert "GiftPremiumScreen" not in never_all                 # the debug device did open it

    def test_activity_funnels_and_search(self, db_session, monkeypatch):
        report = self._seed(db_session, monkeypatch)
        out = report.build_report(db_session, days=7, build="release")
        assert "Поиск: 2 запросов, из них без результатов — 1 (50%)" in out
        assert "записали вечер в дневник" in out
        assert "завершили" in out
        assert "PremiumScreen" in out

    def test_empty_database_says_what_to_check(self, db_session, monkeypatch):
        from scripts import analytics_report

        monkeypatch.setattr(analytics_report, "_load_registry", lambda: [])
        out = analytics_report.build_report(db_session, days=1, build="release", now=_now() - timedelta(days=3650))
        assert "Событий нет" in out


class TestDashboardViews:
    """The four views the Grafana dashboard reads beyond the raw event table
    (migration d4a7e1c05b92). They must (a) count correctly and (b) be safe
    to grant to a read-only role — i.e. expose only dates, categories and
    counts, never the rows of `users`."""

    def test_registrations_and_diary_and_premium_counts(self, db_session, register_user):
        u1, u2 = register_user(), register_user()
        for uid, mtype in ((u1.id, models.MediaType.movie), (u1.id, models.MediaType.movie), (u2.id, models.MediaType.game)):
            db_session.add(models.DiaryEntry(user_id=uid, media_id=_id(), media_type=mtype, source="tmdb"))
        state = db_session.get(models.UserPremiumState, u1.id) or models.UserPremiumState(user_id=u1.id)
        state.is_premium = True
        state.plan_kind = models.PremiumPlanKind(list(models.PremiumPlanKind)[0])
        state.plan_duration = models.PremiumDuration(list(models.PremiumDuration)[0])
        state.purchased_at = _now()
        db_session.add(state)
        db_session.flush()

        today = "(now() AT TIME ZONE 'UTC')::date"
        regs = db_session.execute(text(f"SELECT registrations FROM v_analytics_registrations_daily WHERE day = {today}")).scalar()
        assert regs >= 2
        diary = dict(db_session.execute(text(
            f"SELECT media_type, entries FROM v_analytics_diary_daily WHERE day = {today}"
        )).all())
        assert diary["movie"] >= 2 and diary["game"] >= 1
        purchases = db_session.execute(text(f"SELECT SUM(purchases) FROM v_analytics_premium_daily WHERE day = {today}")).scalar()
        assert purchases >= 1

    def test_views_expose_no_identifying_columns(self, db_session):
        cols = {
            row.table_name: {r.column_name for r in db_session.execute(text(
                "SELECT column_name FROM information_schema.columns WHERE table_name = :t"), {"t": row.table_name})}
            for row in db_session.execute(text(
                "SELECT table_name FROM information_schema.views WHERE table_name IN "
                "('v_analytics_registrations_daily','v_analytics_diary_daily','v_analytics_premium_daily','v_analytics_retention')"
            ))
        }
        assert set(cols) == {"v_analytics_registrations_daily", "v_analytics_diary_daily", "v_analytics_premium_daily", "v_analytics_retention"}
        forbidden = {"id", "user_id", "email", "username", "password_hash", "anon_id", "session_id", "media_id", "title_ru", "title_en"}
        for view, columns in cols.items():
            assert not (columns & forbidden), f"{view} exposes {columns & forbidden}"

    def test_retention_counts_returns_on_day_1_and_7_and_ignores_too_young_cohorts(self, db_session):
        old_day = _now() - timedelta(days=10)
        young = _now() - timedelta(hours=2)
        anon_back, anon_gone, anon_young = (f"anon_{_id()}" for _ in range(3))

        def ev(anon, when):
            db_session.add(models.AnalyticsEvent(
                event_id=_id(), ts=when, anon_id=anon, session_id=f"s_{_id()}", name="app_open", build="retention_t"[:8],
            ))

        # back: first seen 10 days ago, returned on day 1 and on day 7
        for offset in (0, 1, 7):
            ev(anon_back, old_day + timedelta(days=offset))
        # gone: first seen 10 days ago, never returned
        ev(anon_gone, old_day)
        # young: first seen 2 hours ago -> not yet eligible for D1 or D7
        ev(anon_young, young)
        db_session.flush()

        day_old = old_day.astimezone(timezone.utc).date()
        row = db_session.execute(text(
            "SELECT cohort_size, eligible_d1, returned_d1, eligible_d7, returned_d7 FROM v_analytics_retention "
            "WHERE day = :d AND build = 'retentio'"), {"d": day_old}).one()
        assert (row.cohort_size, row.eligible_d1, row.returned_d1, row.eligible_d7, row.returned_d7) == (2, 2, 1, 2, 1)

        today_row = db_session.execute(text(
            "SELECT cohort_size, eligible_d1, eligible_d7 FROM v_analytics_retention "
            "WHERE day = (now() AT TIME ZONE 'UTC')::date AND build = 'retentio'")).one()
        assert (today_row.cohort_size, today_row.eligible_d1, today_row.eligible_d7) == (1, 0, 0)
