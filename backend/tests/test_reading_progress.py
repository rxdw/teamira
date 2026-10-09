"""PUT/GET /progress/reading — the bookmark behind the title screen's reading
tracker for books and manga (volume / chapter / page).

The rules worth pinning down: it is one row per (user, title) that is
replaced as a whole, zeros and nulls mean "not tracking that counter", a
bookmark with nothing left in it disappears instead of lingering as an empty
row, other people's bookmarks are invisible, and only books/manga are
accepted.
"""

BOOK = {"media_id": "gbooks-abc", "source": "google_books"}
MANGA = {"media_id": "shikimanga-2", "source": "shikimori_manga"}


def _put(client, user, **body):
    return client.put("/progress/reading", json=body, headers=user.headers)


def _get(client, user, ident):
    return client.get("/progress/reading", params=ident, headers=user.headers)


class TestReadingProgress:
    def test_untouched_title_is_empty_not_404(self, client, register_user):
        user = register_user()
        resp = _get(client, user, BOOK)
        assert resp.status_code == 200
        assert resp.json() == {"volume": None, "chapter": None, "page": None, "updated_at": None}

    def test_set_then_read_back(self, client, register_user):
        user = register_user()
        put = _put(client, user, **MANGA, volume=7, chapter=61)
        assert put.status_code == 200
        body = _get(client, user, MANGA).json()
        assert (body["volume"], body["chapter"], body["page"]) == (7, 61, None)
        assert body["updated_at"]

    def test_put_replaces_the_whole_bookmark(self, client, register_user):
        user = register_user()
        _put(client, user, **MANGA, volume=7, chapter=61)
        _put(client, user, **MANGA, volume=8)  # chapter left out -> no longer tracked
        body = _get(client, user, MANGA).json()
        assert (body["volume"], body["chapter"]) == (8, None)

    def test_zero_unsets_a_counter_and_all_empty_deletes_the_row(self, client, register_user, db_session):
        from app import models
        user = register_user()
        _put(client, user, **BOOK, page=120)
        assert db_session.query(models.ReadingProgress).count() == 1
        resp = _put(client, user, **BOOK, page=0)
        assert resp.json()["page"] is None
        db_session.expire_all()
        assert db_session.query(models.ReadingProgress).count() == 0
        # clearing something that was never set is fine too
        assert _put(client, user, **BOOK).status_code == 200

    def test_progress_is_per_user(self, client, register_user):
        a, b = register_user(), register_user()
        _put(client, a, **BOOK, page=50)
        assert _get(client, b, BOOK).json()["page"] is None
        assert _get(client, a, BOOK).json()["page"] == 50

    def test_only_books_and_manga(self, client, register_user):
        user = register_user()
        resp = _put(client, user, media_id="tmdb-603", source="tmdb", page=3)
        assert resp.status_code == 400

    def test_nonsense_counters_are_rejected(self, client, register_user):
        user = register_user()
        assert _put(client, user, **BOOK, page=-1).status_code == 422
        assert _put(client, user, **BOOK, page=10_000_000).status_code == 422

    def test_requires_login(self, client):
        assert client.get("/progress/reading", params=BOOK).status_code in (401, 403)
