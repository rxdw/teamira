"""Tests for app/routers/co_view_vote.py. propose_vote and the
"personal" pool source (see _build_vote_pool) are both fully local —
only the "catalog" pool source hits a live adapter (the same
get_discover_pool feed.py's own GET /feed uses), so that one path isn't
covered here."""

from datetime import datetime, timezone

from app import models


def _link_two_users(client, register_user):
    a = register_user()
    b = register_user()
    code = client.post("/partner/pair", headers=a.headers).json()["pending_code"]
    client.post("/partner/join", json={"code": code}, headers=b.headers)
    return a, b


def _propose(client, headers, item):
    return client.post("/partner/co-viewing/vote/propose", json={"items": [item]}, headers=headers)


class TestProposeVote:
    def test_creates_an_active_session_with_the_proposed_item(
        self, client, register_user, sample_media_item
    ):
        alice, _bob = _link_two_users(client, register_user)
        item = sample_media_item()
        resp = _propose(client, alice.headers, item)
        assert resp.status_code == 201
        body = resp.json()
        assert body["status"] == "active"
        assert body["pool_source"] == "proposed"
        assert [d["id"] for d in body["deck"]] == [item["id"]]

    def test_proposing_again_while_one_is_active_returns_the_same_session(
        self, client, register_user, sample_media_item
    ):
        alice, _bob = _link_two_users(client, register_user)
        first = _propose(client, alice.headers, sample_media_item()).json()
        second = _propose(client, alice.headers, sample_media_item()).json()
        assert first["id"] == second["id"]

    def test_empty_items_is_422(self, client, register_user):
        alice, _bob = _link_two_users(client, register_user)
        resp = client.post("/partner/co-viewing/vote/propose", json={"items": []}, headers=alice.headers)
        assert resp.status_code == 422

    def test_requires_a_link(self, client, register_user, sample_media_item):
        alice = register_user()
        resp = _propose(client, alice.headers, sample_media_item())
        assert resp.status_code == 409

    def test_both_partners_see_the_same_round(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        proposed = _propose(client, alice.headers, sample_media_item()).json()
        bobs_view = client.get(f"/partner/co-viewing/vote/{proposed['id']}", headers=bob.headers)
        assert bobs_view.status_code == 200
        assert bobs_view.json()["id"] == proposed["id"]


class TestCastVote:
    def test_both_voting_yes_completes_the_round_and_adds_the_winner(
        self, client, register_user, sample_media_item, db_session
    ):
        alice, bob = _link_two_users(client, register_user)
        item = sample_media_item()
        session = _propose(client, alice.headers, item).json()

        alice_cast = client.post(
            f"/partner/co-viewing/vote/{session['id']}/cast",
            json={"media_id": item["id"], "source": item["source"], "decision": True},
            headers=alice.headers,
        )
        assert alice_cast.json()["status"] == "active"  # only one of two has voted yes so far

        bob_cast = client.post(
            f"/partner/co-viewing/vote/{session['id']}/cast",
            json={"media_id": item["id"], "source": item["source"], "decision": True},
            headers=bob.headers,
        )
        body = bob_cast.json()
        assert body["status"] == "done"
        assert body["winner"]["id"] == item["id"]

        # Landed on the shared co-viewing list for real, not just in the response.
        link = db_session.query(models.PartnerLink).filter(
            (models.PartnerLink.owner_id == alice.id) | (models.PartnerLink.partner_id == alice.id)
        ).first()
        coview_row = db_session.query(models.CoViewEntry).filter_by(
            link_id=link.id, media_id=item["id"], source=item["source"]
        ).first()
        assert coview_row is not None

    def test_match_schedules_a_push_to_both_members(
        self, client, register_user, sample_media_item
    ):
        """See routers/co_view_vote.py::cast_vote's own comment on why
        this fires from a BackgroundTasks call after db.commit(), not
        inline before it. TestClient runs background tasks synchronously
        as part of the request/response cycle, so patching the function
        and asserting on the call is enough — no need for a real
        Firebase credential or an async wait."""
        from unittest.mock import patch

        alice, bob = _link_two_users(client, register_user)
        item = sample_media_item()
        session = _propose(client, alice.headers, item).json()

        with patch("app.routers.co_view_vote.push.notify_match") as mock_notify:
            client.post(
                f"/partner/co-viewing/vote/{session['id']}/cast",
                json={"media_id": item["id"], "source": item["source"], "decision": True},
                headers=alice.headers,
            )
            assert not mock_notify.called  # only one of two has voted yes so far

            client.post(
                f"/partner/co-viewing/vote/{session['id']}/cast",
                json={"media_id": item["id"], "source": item["source"], "decision": True},
                headers=bob.headers,
            )

        assert mock_notify.called
        (member_ids, title_name, *_rest) = mock_notify.call_args[0]
        assert set(member_ids) == {alice.id, bob.id}
        assert title_name  # exact wording isn't the point here, just that it's non-empty

    def test_a_no_vote_never_schedules_a_push(self, client, register_user, sample_media_item):
        from unittest.mock import patch

        alice, bob = _link_two_users(client, register_user)
        item = sample_media_item()
        session = _propose(client, alice.headers, item).json()

        with patch("app.routers.co_view_vote.push.notify_match") as mock_notify:
            client.post(
                f"/partner/co-viewing/vote/{session['id']}/cast",
                json={"media_id": item["id"], "source": item["source"], "decision": False},
                headers=alice.headers,
            )
        assert not mock_notify.called

    def test_one_yes_one_no_does_not_complete_the_round(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        item = sample_media_item()
        session = _propose(client, alice.headers, item).json()

        client.post(
            f"/partner/co-viewing/vote/{session['id']}/cast",
            json={"media_id": item["id"], "source": item["source"], "decision": True},
            headers=alice.headers,
        )
        resp = client.post(
            f"/partner/co-viewing/vote/{session['id']}/cast",
            json={"media_id": item["id"], "source": item["source"], "decision": False},
            headers=bob.headers,
        )
        assert resp.json()["status"] == "active"
        assert resp.json()["winner"] is None

    def test_recasting_changes_the_decision_not_a_duplicate_vote(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link_two_users(client, register_user)
        item = sample_media_item()
        session = _propose(client, alice.headers, item).json()

        client.post(
            f"/partner/co-viewing/vote/{session['id']}/cast",
            json={"media_id": item["id"], "source": item["source"], "decision": False},
            headers=alice.headers,
        )
        # Changed her mind.
        client.post(
            f"/partner/co-viewing/vote/{session['id']}/cast",
            json={"media_id": item["id"], "source": item["source"], "decision": True},
            headers=alice.headers,
        )
        final = client.post(
            f"/partner/co-viewing/vote/{session['id']}/cast",
            json={"media_id": item["id"], "source": item["source"], "decision": True},
            headers=bob.headers,
        )
        assert final.json()["status"] == "done"  # both effectively said yes, once each

    def test_casting_on_a_finished_round_is_409(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        item = sample_media_item()
        session = _propose(client, alice.headers, item).json()
        for u in (alice, bob):
            client.post(
                f"/partner/co-viewing/vote/{session['id']}/cast",
                json={"media_id": item["id"], "source": item["source"], "decision": True},
                headers=u.headers,
            )

        again = client.post(
            f"/partner/co-viewing/vote/{session['id']}/cast",
            json={"media_id": item["id"], "source": item["source"], "decision": True},
            headers=alice.headers,
        )
        assert again.status_code == 409

    def test_cannot_cast_on_someone_elses_link(self, client, register_user, sample_media_item):
        alice, _bob = _link_two_users(client, register_user)
        stranger = register_user()
        item = sample_media_item()
        session = _propose(client, alice.headers, item).json()

        resp = client.post(
            f"/partner/co-viewing/vote/{session['id']}/cast",
            json={"media_id": item["id"], "source": item["source"], "decision": True},
            headers=stranger.headers,
        )
        assert resp.status_code == 409  # stranger has no active link at all


class TestEndVote:
    def test_either_side_can_end_it(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        session = _propose(client, alice.headers, sample_media_item()).json()

        resp = client.delete(f"/partner/co-viewing/vote/{session['id']}", headers=bob.headers)
        assert resp.status_code == 204

        gone = client.get(f"/partner/co-viewing/vote/{session['id']}", headers=alice.headers)
        assert gone.status_code == 404

    def test_ending_lets_a_new_round_start(self, client, register_user, sample_media_item):
        alice, _bob = _link_two_users(client, register_user)
        first = _propose(client, alice.headers, sample_media_item()).json()
        client.delete(f"/partner/co-viewing/vote/{first['id']}", headers=alice.headers)

        second = _propose(client, alice.headers, sample_media_item()).json()
        assert second["id"] != first["id"]


class TestPersonalPool:
    def _make_watch_later(self, db_session, user_id, **overrides):
        fields = dict(
            user_id=user_id, media_id=f"tmdb-{models.gen_uuid()[:8]}", media_type=models.MediaType.movie,
            source="tmdb", title_en="x", status=models.WatchStatus.watch_later, created_at=datetime.now(timezone.utc),
        )
        fields.update(overrides)
        entry = models.WatchlistEntry(**fields)
        db_session.add(entry)
        db_session.commit()
        return entry

    def test_deck_pulls_from_either_partners_watch_later_shelf(
        self, client, register_user, db_session
    ):
        alice, bob = _link_two_users(client, register_user)
        self._make_watch_later(db_session, alice.id)
        self._make_watch_later(db_session, bob.id)

        deck = client.get("/partner/co-viewing/vote/deck", params={"source": "personal"}, headers=alice.headers)
        assert deck.status_code == 200
        assert len(deck.json()) == 2

    def test_watched_or_watching_entries_are_not_in_the_personal_pool(self, client, register_user, db_session):
        alice, _bob = _link_two_users(client, register_user)
        self._make_watch_later(db_session, alice.id, status=models.WatchStatus.watched)

        deck = client.get("/partner/co-viewing/vote/deck", params={"source": "personal"}, headers=alice.headers)
        assert deck.json() == []

    def test_start_vote_with_an_empty_personal_pool_is_422(self, client, register_user):
        alice, _bob = _link_two_users(client, register_user)
        resp = client.post("/partner/co-viewing/vote", params={"source": "personal"}, headers=alice.headers)
        assert resp.status_code == 422

    def test_start_vote_builds_a_session_from_the_personal_pool(self, client, register_user, db_session):
        alice, _bob = _link_two_users(client, register_user)
        self._make_watch_later(db_session, alice.id)

        resp = client.post("/partner/co-viewing/vote", params={"source": "personal"}, headers=alice.headers)
        assert resp.status_code == 201
        assert resp.json()["pool_source"] == "personal"
        assert len(resp.json()["deck"]) == 1

    def test_deck_requires_a_link(self, client, register_user):
        alice = register_user()
        resp = client.get("/partner/co-viewing/vote/deck", headers=alice.headers)
        assert resp.status_code == 409
