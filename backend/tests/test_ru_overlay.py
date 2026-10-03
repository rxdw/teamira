"""app/ru_overlay.py — Russian poster/title on list items.

No database and no network: the bulk cache read, the TMDB lookup and the cache
write are all replaced. What's checked is the behaviour the feed relies on —
cached titles are filled at once, cold ones are looked up (and cached), a
failure or a slow lookup never breaks or blocks the response, and nothing but
TMDB items is touched.
"""
from __future__ import annotations

import asyncio

import pytest

from app import ru_overlay
from app.schemas import ExternalIds, LocalizedText, MediaItem


def _item(n: int, source: str = "tmdb") -> MediaItem:
    return MediaItem(
        id=f"tmdb-{n}" if source == "tmdb" else f"igdb-{n}",
        media_type="movie" if source == "tmdb" else "game",
        external_ids=ExternalIds(tmdb=str(n)) if source == "tmdb" else ExternalIds(),
        title=LocalizedText(en=f"Title {n}"),
        description=LocalizedText(en=f"About {n}"),
        poster_url="/en.jpg",
        source=source,
    )


RU = {"title_ru": "Название", "overview_ru": "Про это", "poster_ru": "https://x/ru.jpg"}


@pytest.fixture
def stubs(monkeypatch):
    state = {"cached": {}, "looked_up": [], "written": {}, "fail": set(), "delay": 0.0}

    monkeypatch.setattr(ru_overlay, "_bulk_cached", lambda ids: {i: state["cached"][i] for i in ids if i in state["cached"]})

    async def fake_lookup(tmdb_id, segment):
        state["looked_up"].append(tmdb_id)
        if state["delay"]:
            await asyncio.sleep(state["delay"])
        if tmdb_id in state["fail"]:
            raise RuntimeError("429")
        return dict(RU)

    monkeypatch.setattr(ru_overlay._tmdb, "shelf_ru_supplement", fake_lookup)
    monkeypatch.setattr(
        ru_overlay.cache, "set_static_title",
        lambda db, media_id, source, payload: state["written"].__setitem__(media_id, (source, payload)),
    )
    monkeypatch.setattr(ru_overlay, "_semaphore", None)
    ru_overlay._in_flight.clear()
    return state


def test_cached_titles_are_filled_without_any_tmdb_call(stubs):
    items = [_item(1), _item(2)]
    stubs["cached"] = {"tmdb-1": RU, "tmdb-2": RU}
    asyncio.run(ru_overlay.overlay_ru(items))
    assert [i.poster_url_ru for i in items] == [RU["poster_ru"]] * 2
    assert items[0].title.ru == "Название" and items[0].description.ru == "Про это"
    assert stubs["looked_up"] == []


def test_cold_titles_are_looked_up_and_cached_forever(stubs):
    items = [_item(1)]
    asyncio.run(ru_overlay.overlay_ru(items))
    assert items[0].poster_url_ru == RU["poster_ru"]
    assert stubs["written"]["tmdb-1"][0] == ru_overlay.RU_SUPPLEMENT_CACHE_SOURCE


def test_only_tmdb_items_are_touched(stubs):
    game = _item(5, source="igdb")
    asyncio.run(ru_overlay.overlay_ru([game]))
    assert game.poster_url_ru is None and stubs["looked_up"] == []


def test_a_failed_lookup_keeps_the_english_poster_and_is_not_cached(stubs):
    stubs["fail"] = {"1"}
    items = [_item(1), _item(2)]
    asyncio.run(ru_overlay.overlay_ru(items))
    assert items[0].poster_url_ru is None and items[0].poster_url == "/en.jpg"
    assert "tmdb-1" not in stubs["written"]          # retried next time
    assert items[1].poster_url_ru == RU["poster_ru"]  # the others still work


def test_a_genuine_miss_never_clears_what_the_item_already_has(stubs):
    item = _item(1)
    item.poster_url_ru = "https://x/already.jpg"
    stubs["cached"] = {"tmdb-1": {"title_ru": None, "overview_ru": None, "poster_ru": None}}
    asyncio.run(ru_overlay.overlay_ru([item]))
    assert item.poster_url_ru == "https://x/already.jpg"


def test_a_slow_lookup_does_not_block_the_response_and_still_lands_in_the_cache(stubs, monkeypatch):
    monkeypatch.setattr(ru_overlay, "INLINE_BUDGET_SECONDS", 0.05)
    stubs["delay"] = 0.3
    items = [_item(1)]

    async def scenario():
        started = asyncio.get_running_loop().time()
        await ru_overlay.overlay_ru(items)
        took = asyncio.get_running_loop().time() - started
        assert took < 0.25                       # answered before the lookup finished
        assert items[0].poster_url_ru is None    # this response stays English
        await asyncio.sleep(0.4)                 # ...the lookup carries on meanwhile
        assert "tmdb-1" in stubs["written"]      # so the next load has it

    asyncio.run(scenario())


def test_titles_beyond_the_inline_limit_are_filled_in_the_background(stubs, monkeypatch):
    monkeypatch.setattr(ru_overlay, "INLINE_LOOKUP_LIMIT", 2)
    items = [_item(n) for n in range(1, 6)]

    async def scenario():
        await ru_overlay.overlay_ru(items)
        assert [i.poster_url_ru is not None for i in items] == [True, True, False, False, False]
        await asyncio.sleep(0.1)
        assert set(stubs["written"]) == {f"tmdb-{n}" for n in range(1, 6)}

    asyncio.run(scenario())


def test_wants_ru():
    assert ru_overlay.wants_ru("ru") and ru_overlay.wants_ru("RU-ru")
    assert not ru_overlay.wants_ru(None) and not ru_overlay.wants_ru("en") and not ru_overlay.wants_ru("")
