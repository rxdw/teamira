"""The richer title card for games, books, manga and anime ("extras").

Everything here runs offline: the parsers are pure (a dict in, a model out),
the merge rules are plain functions, and the endpoint tests monkeypatch the
adapters the same way tests/test_media_detail.py seeds the cache. What is NOT
covered is the shape of the live APIs — the sample dicts below follow each
API's documentation, so a field renamed upstream shows up as a real-world
miss, not as a failure here (same caveat as tests/test_anilist.py).
"""

import pytest

from app import cache, extras_merge, game_store, manga_reviews
from app.adapters import google_books, igdb, open_library, shikimori
from app.adapters.anilist import AniListInfo, parse_info
from app.adapters.steam_store import SteamStore, parse_languages, parse_requirements, parse_store
from app.routers import media as media_router
from app.schemas import (
    ExternalIds, LocalizedText, MediaDetailOut, MediaItem, TitleCreator, TitleExtras,
)


def _item(media_type="game", id_="igdb-1", source="igdb", **kw) -> MediaItem:
    return MediaItem(
        id=id_, media_type=media_type, external_ids=ExternalIds(),
        title=LocalizedText(en="T"), description=LocalizedText(en="d"), source=source, **kw,
    )


# ---------------------------------------------------------------- Steam store

class TestSteamStore:
    def test_languages_split_audio_and_drop_footnote(self):
        raw = ("English<strong>*</strong>, Russian, French<strong>*</strong>"
               "<br><strong>*</strong>languages with full audio support")
        langs = parse_languages(raw)
        assert [(l.name, l.audio) for l in langs] == [
            ("English", True), ("Russian", False), ("French", True),
        ]
        assert all(l.interface for l in langs)

    def test_parse_store_full_entry(self):
        store = parse_store("620", {
            "is_free": False,
            "price_overview": {"final_formatted": "199 pуб.", "discount_percent": 50},
            "metacritic": {"score": 95, "url": "https://mc"},
            "achievements": {"total": 51},
            "categories": [{"id": 28}, {"id": 18}, {"id": 23}, {"id": 2}],
            "supported_languages": "English, Russian",
            "screenshots": [{"path_full": "https://s/1.jpg"}, {"path_thumbnail": "https://s/2.jpg"}],
        })
        assert store.price == "199 pуб." and store.price_discount_pct == 50
        assert store.metacritic == 95 and store.achievements == 51
        # "partial" is dropped when "full" controller support is there
        assert store.features == ["Full controller support", "Steam Cloud"]
        assert store.screenshots == ["https://s/1.jpg", "https://s/2.jpg"]

    def test_parse_store_free_game_has_no_price(self):
        store = parse_store("570", {"is_free": True})
        assert store.free_to_play is True and store.price is None

    def test_parse_store_survives_junk(self):
        assert parse_store("1", None).price is None
        assert parse_store("1", {"metacritic": "x", "achievements": []}).metacritic is None


class TestSteamRequirementsAndDeck:
    MIN = (
        '<strong>Minimum:</strong><br><ul class="bb_ul">'
        '<li><strong>OS *:</strong> Windows&nbsp;10 64-bit<br></li>'
        '<li><strong>Video Card:</strong> GTX 960<br></li>'
        '<li><strong>Hard Drive:</strong> 50 GB<br></li>'
        '<li><strong>Something odd:</strong> kept as written</li></ul>'
    )

    def test_list_form_labels_are_canonicalised_and_entities_decoded(self):
        rows = parse_requirements(self.MIN)
        assert [(r.label, r.value) for r in rows] == [
            ("OS", "Windows 10 64-bit"), ("Graphics", "GTX 960"),
            ("Storage", "50 GB"), ("Something odd", "kept as written"),
        ]

    def test_bare_lines_without_labels(self):
        rows = parse_requirements("<strong>Recommended:</strong><br>Windows 10<br>8 GB RAM")
        assert [(r.label, r.value) for r in rows] == [("", "Windows 10"), ("", "8 GB RAM")]

    def test_absent_requirements_are_empty_not_an_error(self):
        # Steam sends [] (a list!) instead of an object when there are none.
        assert parse_requirements(None) == [] and parse_requirements([]) == []
        assert parse_store("1", {"pc_requirements": []}).requirements_min == []

    def test_platforms_keep_only_the_true_ones_in_a_fixed_order(self):
        store = parse_store("1", {"platforms": {"windows": True, "mac": False, "linux": True}})
        assert store.platforms == ["windows", "linux"]

    def test_merge_attaches_requirements_platforms_and_deck(self):
        item = _item()
        store = parse_store("620", {
            "pc_requirements": {"minimum": self.MIN},
            "platforms": {"windows": True, "mac": True, "linux": False},
        })
        store.deck = "verified"
        extras_merge.merge_steam_store(item, store)
        ex = item.extras
        assert ex.steam_deck == "verified" and ex.pc_platforms == ["windows", "mac"]
        assert ex.requirements.minimum[0].label == "OS" and ex.requirements.recommended == []

    def test_no_requirements_leaves_the_field_unset(self):
        item = _item()
        extras_merge.merge_steam_store(item, SteamStore(appid="1"))
        assert item.extras.requirements is None and item.extras.steam_deck is None


# ----------------------------------------------------------------------- IGDB

IGDB_GAME = {
    "id": 10, "name": "Portal 2",
    "storyline": " Wake up, test subject. ",
    "themes": [{"name": "Science fiction"}, {"name": "Comedy"}],
    "player_perspectives": [{"name": "First person"}],
    "alternative_names": [{"name": "Портал 2"}, {"name": "Portal 2"}],
    "aggregated_rating": 94.6, "aggregated_rating_count": 40,
    "screenshots": [{"url": "//images.igdb.com/igdb/image/upload/t_thumb/a.jpg"}],
    "videos": [{"video_id": "abc123", "name": "Launch trailer"}, {"video_id": "abc123"}],
    "language_supports": [
        {"language": {"name": "Russian"}, "language_support_type": {"name": "Interface"}},
        {"language": {"name": "Russian"}, "language_support_type": {"name": "Subtitles"}},
        {"language": {"name": "German"}, "language_support_type": {"name": "Audio"}},
        {"language": {"name": "English"}, "language_support_type": {"name": "Audio"}},
    ],
    "websites": [
        {"url": "https://store.steampowered.com/app/620", "category": 13},
        {"url": "https://www.gog.com/game/portal_2", "category": 17},
        {"url": "https://twitter.com/x", "category": 5},
        {"url": "https://www.thinkwithportals.com", "category": 1},
    ],
    "collections": [{"name": "Portal", "games": [
        {"id": 10, "name": "Portal 2"},
        {"id": 9, "name": "Portal", "first_release_date": 1191888000,
         "cover": {"url": "//images.igdb.com/igdb/image/upload/t_thumb/p.jpg"}},
    ]}],
    "dlcs": [{"id": 11, "name": "Peer Review"}],
    "parent_game": {"id": 8, "name": "Base"},
    "similar_games": [
        {"id": 20, "name": "Quantum Conundrum", "cover": {"url": "//x/t_thumb/q.jpg"}},
        {"id": 21, "name": "No cover game"},
    ],
}


class TestIgdbExtras:
    def test_build_extras(self):
        ex = igdb.build_extras(IGDB_GAME)
        assert ex.complete is True
        assert [t.name for t in ex.tags] == ["Science fiction", "Comedy"]
        assert ex.perspectives == ["First person"]
        assert ex.storyline == "Wake up, test subject."
        assert ex.alt_titles == ["Портал 2"]  # the title itself is not an alias
        assert ex.critic_score == 95 and ex.critic_votes == 40
        assert len(ex.screenshots) == 1 and "t_screenshot_big" in ex.screenshots[0]

    def test_languages_group_by_language_and_russian_first(self):
        langs = igdb.build_extras(IGDB_GAME).languages
        assert [l.name for l in langs] == ["Russian", "English", "German"]
        ru = langs[0]
        assert ru.interface and ru.subtitles and not ru.audio

    def test_links_only_stores_official_and_wiki_in_order(self):
        links = igdb.build_extras(IGDB_GAME).links
        assert [l.kind for l in links] == ["steam", "gog", "official"]  # twitter dropped

    def test_related_excludes_self_and_orders_base_first(self):
        rel = igdb.build_extras(IGDB_GAME).related
        assert [(r.relation, r.title) for r in rel] == [
            ("Base game", "Base"), ("Same series", "Portal"), ("DLC", "Peer Review"),
        ]
        assert rel[1].id == "igdb-9" and rel[1].source == "igdb" and rel[1].year == 2007

    def test_trailers_dedupe_and_thumbnail(self):
        tr = igdb.build_trailers(IGDB_GAME)
        assert len(tr) == 1 and tr[0].video_id == "abc123"
        assert tr[0].thumbnail_url.endswith("/abc123/hqdefault.jpg")

    def test_similar_skips_games_without_cover(self):
        sim = igdb.build_similar(IGDB_GAME)
        assert [m.id for m in sim] == ["igdb-20"]

    def test_time_to_beat_seconds_to_hours(self):
        ttb = igdb.parse_time_to_beat([{"hastily": 36000, "normally": 54000, "completely": None, "count": 7}])
        assert (ttb.hastily, ttb.normally, ttb.completely, ttb.votes) == (10.0, 15.0, None, 7)
        assert igdb.parse_time_to_beat([{"hastily": None}]) is None
        assert igdb.parse_time_to_beat([]) is None

    def test_empty_game_still_gets_an_empty_extras_object(self):
        ex = igdb.build_extras({"id": 1, "name": "x"})
        assert isinstance(ex, TitleExtras) and ex.complete is True and not ex.screenshots


# ------------------------------------------------------------------ Shikimori

ROLES = [
    {"roles": ["Story & Art"], "person": {"id": 1, "name": "Kentarou Miura", "russian": "Кэнтаро Миура",
                                          "image": {"preview": "/system/people/preview/1.jpg"}}},
    {"roles": ["Main"], "character": {"id": 7, "name": "Guts", "russian": "Гатс",
                                      "image": {"preview": "/system/characters/preview/7.jpg"}}},
    {"roles": ["Supporting"], "character": {"id": 8, "name": "Casca", "russian": None, "image": {}}},
    {"roles": ["Main"], "character": {"id": 9, "name": "Griffith", "russian": "Гриффит", "image": {}}},
    {"roles": ["Main"], "character": {"id": 7, "name": "Guts", "russian": "Гатс", "image": {}}},  # dupe
]


class TestShikimoriExtras:
    def test_manga_roles(self):
        creators, chars = shikimori.parse_roles(ROLES, anime=False)
        assert creators[0].name_ru == "Кэнтаро Миура"
        assert creators[0].photo_url == "https://shikimori.io/system/people/preview/1.jpg"
        assert [c.name for c in chars] == ["Guts", "Griffith", "Casca"]  # Main first, deduped
        assert chars[0].role == "Main" and chars[2].role == "Supporting"

    def test_anime_staff_is_filtered_to_key_roles(self):
        rows = [
            {"roles": ["Key Animation"], "person": {"id": 1, "name": "A"}},
            {"roles": ["Director"], "person": {"id": 2, "name": "B"}},
            {"roles": ["Music"], "person": {"id": 3, "name": "C"}},
        ]
        creators, _ = shikimori.parse_roles(rows, anime=True)
        assert [c.name for c in creators] == ["B", "C"]  # Director before Music

    def test_related_manga_is_openable_anime_is_not(self):
        rel = shikimori.parse_related([
            {"relation": "Sequel", "manga": {"id": 5, "name": "Berserk 2", "russian": "Берсерк 2",
                                             "aired_on": "2011-01-01", "image": {"preview": "/m.jpg"}}},
            {"relation": "Adaptation", "anime": {"id": 33, "name": "Berserk", "aired_on": "1997-10-08",
                                                 "image": {"preview": "/a.jpg"}}},
            {"relation": "Other", "manga": None, "anime": None},
        ])
        assert [r.relation for r in rel] == ["Adaptation", "Sequel"]  # adaptation leads
        adaptation, sequel = rel
        assert adaptation.media_type == "anime" and adaptation.id is None and adaptation.year == 1997
        assert sequel.id == "shikimanga-5" and sequel.source == "shikimori_manga"

    def test_manga_extras_kind_sets_language_and_popularity_sums(self):
        ex = shikimori.manga_extras(
            {"kind": "manhwa", "name": "Solo", "english": ["Solo Leveling"], "japanese": ["x"],
             "rates_statuses_stats": [{"name": "Planned", "value": 10}, {"name": "Completed", "value": 5}],
             "aired_on": "2018-03-04"},
            [], [], [], complete=False,
        )
        assert ex.original_language == "ko" and ex.popularity == 15 and ex.complete is False
        assert ex.alt_titles == ["Solo Leveling", "x"] and ex.start_date == "2018-03-04"

    def test_anime_extras(self):
        ex = shikimori.anime_extras(
            {"studios": [{"name": "MAPPA"}], "episodes": 12, "episodes_aired": 3, "duration": 24,
             "next_episode_at": "2026-10-10T15:00:00.000+03:00",
             "genres": [{"name": "Isekai", "kind": "theme"}, {"name": "Action", "kind": "genre"}]},
            [], [], [],
        )
        assert ex.studios == ["MAPPA"] and (ex.episodes, ex.episodes_aired, ex.episode_minutes) == (12, 3, 24)
        assert [t.name for t in ex.tags] == ["Isekai"]  # plain genres stay on the card


# --------------------------------------------------------------------- AniList

class TestAniListInfo:
    MEDIA = {
        "siteUrl": "https://anilist.co/manga/1", "bannerImage": "https://b/1.jpg",
        "countryOfOrigin": "KR", "source": "WEB_NOVEL", "popularity": 1000, "favourites": 50,
        "tags": [
            {"name": "Isekai", "rank": 90}, {"name": "Weak", "rank": 10},
            {"name": "Twist", "rank": 95, "isMediaSpoiler": True}, {"name": "Magic", "rank": 60},
        ],
        "externalLinks": [
            {"site": "Webtoon", "url": "https://webtoon", "type": "STREAMING"},
            {"site": "Official Site", "url": "https://off", "type": "INFO"},
            {"site": "Twitter", "url": "https://tw", "type": "SOCIAL"},
            {"site": "Old", "url": "https://old", "type": "STREAMING", "isDisabled": True},
        ],
    }

    def test_manga_passport(self):
        info = parse_info(self.MEDIA, with_links=True)
        assert [(t.name, t.rank) for t in info.tags] == [("Isekai", 90), ("Magic", 60)]
        assert (info.language, info.source, info.banner) == ("ko", "Web novel", "https://b/1.jpg")
        assert [(l.kind, l.label) for l in info.links] == [("read", "Webtoon"), ("official", "Official site")]

    def test_anime_passport_has_no_links(self):
        assert parse_info(self.MEDIA, with_links=False).links == []

    def test_missing(self):
        assert parse_info(None, with_links=True).missing is True


# ------------------------------------------------------------------ Google Books

VOLUME = {
    "id": "vol1",
    "volumeInfo": {
        "title": "Dune", "subtitle": "Book One", "authors": ["Frank Herbert"],
        "publisher": "Ace", "publishedDate": "1990-09-01", "pageCount": 592, "language": "en",
        "industryIdentifiers": [{"type": "ISBN_10", "identifier": "0441172717"},
                                {"type": "ISBN_13", "identifier": "978-0441172719"}],
        "previewLink": "https://books.google.com/preview", "infoLink": "https://books.google.com/info",
        "imageLinks": {"thumbnail": "http://books.google.com/x.jpg"},
    },
    "accessInfo": {"viewability": "PARTIAL"},
    "saleInfo": {"saleability": "FOR_SALE", "buyLink": "https://play.google.com/buy"},
}


class TestGoogleBooksDetail:
    def test_normalize_detail_fills_the_facts_that_were_always_empty(self):
        item = google_books.normalize_detail(VOLUME)
        assert item.publisher == "Ace" and item.isbn == "9780441172719"
        ex = item.extras
        assert (ex.pages, ex.published_date, ex.subtitle, ex.book_language) == (592, "1990-09-01", "Book One", "en")
        assert ex.creators[0].name == "Frank Herbert" and ex.creators[0].role == "Author"
        assert [l.kind for l in ex.links] == ["preview", "buy"]

    def test_no_preview_when_nothing_is_viewable(self):
        vol = {**VOLUME, "accessInfo": {"viewability": "NO_PAGES"}, "saleInfo": {}}
        assert [l.kind for l in google_books.normalize_detail(vol).extras.links] == ["other"]

    def test_more_by_author_skips_self_editions_other_languages_and_coverless(self):
        def row(id_, title, lang="en", cover=True, votes=1):
            info = {"title": title, "language": lang, "ratingsCount": votes, "authors": ["A"]}
            if cover:
                info["imageLinks"] = {"thumbnail": "http://x/c.jpg"}
            return {"id": id_, "volumeInfo": info}
        picked = google_books.pick_more_by_author(
            [row("vol1", "Dune"), row("v2", "Dune"), row("v3", "Messiah", votes=5),
             row("v4", "Children", votes=50), row("v5", "Дюна", lang="ru"), row("v6", "Nocover", cover=False)],
            "vol1", "Dune", "en",
        )
        assert [m.id.split("-")[-1] for m in picked] == ["v4", "v3"]  # most-rated first


# ------------------------------------------------------------------ Open Library

class TestOpenLibraryBookInfo:
    DOCS = [{
        "title": "Dune", "author_name": ["Frank Herbert"], "author_key": ["OL1A"],
        "first_sentence": ["In the week before their departure to Arrakis..."],
        "want_to_read_count": 1200, "currently_reading_count": 80, "already_read_count": 900,
    }]
    AUTHOR = {"bio": {"type": "/type/text", "value": "American author. [Wiki](http://x) Wrote Dune."},
              "birth_date": "8 October 1920", "death_date": "11 February 1986", "photos": [123]}

    def test_matches_and_collects_everything(self):
        info = open_library.parse_book_info(self.DOCS, "Dune", "Frank Herbert", self.AUTHOR)
        assert info.bio.startswith("American author. Wiki Wrote Dune")
        assert (info.want, info.reading, info.read) == (1200, 80, 900)
        assert info.photo_url == "https://covers.openlibrary.org/a/olid/OL1A-M.jpg?default=false"
        assert info.first_sentence.startswith("In the week")

    def test_wrong_author_is_no_match_never_someone_elses_bio(self):
        assert open_library.parse_book_info(self.DOCS, "Dune", "Brian Herbert", self.AUTHOR).missing
        assert open_library.parse_book_info(self.DOCS, "Other title", "Frank Herbert", self.AUTHOR).missing

    def test_long_bio_is_cut_at_a_sentence(self):
        bio = "Sentence one is here. " * 80
        info = open_library.parse_book_info(self.DOCS, "Dune", "Frank Herbert", {"bio": bio})
        assert len(info.bio) <= open_library.MAX_BIO_CHARS and info.bio.endswith(".")


# ------------------------------------------------------------------------ merge

class TestMerge:
    def test_steam_store_swaps_in_screens_only_when_igdb_has_few(self):
        item = _item(extras=TitleExtras(screenshots=["igdb1"]))
        store = SteamStore(appid="620", price="1 $", screenshots=["s1", "s2"], metacritic=90)
        extras_merge.merge_steam_store(item, store)
        assert item.extras.screenshots == ["s1", "s2"] and item.extras.metacritic == 90
        assert item.extras.links[0].url.endswith("/app/620")

        rich = _item(extras=TitleExtras(screenshots=["a", "b", "c"]))
        extras_merge.merge_steam_store(rich, store)
        assert rich.extras.screenshots == ["a", "b", "c"]

    def test_steam_link_not_duplicated(self):
        item = _item(extras=igdb.build_extras(IGDB_GAME))
        extras_merge.merge_steam_store(item, SteamStore(appid="620"))
        assert sum(1 for l in item.extras.links if l.kind == "steam") == 1

    def test_anilist_banner_only_for_manga_without_backdrop(self):
        info = AniListInfo(banner="https://b", tags=[], source="Manga")
        manga = _item("manga", "shikimanga-1", "shikimori_manga")
        extras_merge.merge_anilist_info(manga, info)
        assert manga.backdrop_url == "https://b" and manga.extras.source_material == "Manga"
        anime = _item("anime", "tmdb-1", "tmdb")
        extras_merge.merge_anilist_info(anime, info)
        assert anime.backdrop_url is None

    def test_anilist_tags_outrank_shikimori_themes_without_duplicates(self):
        from app.schemas import TitleTag
        item = _item("anime", "tmdb-1", "tmdb", extras=TitleExtras(tags=[TitleTag(name="Isekai"), TitleTag(name="School")]))
        extras_merge.merge_anilist_info(item, AniListInfo(tags=[TitleTag(name="isekai", rank=90)]))
        assert [(t.name, t.rank) for t in item.extras.tags] == [("isekai", 90), ("School", None)]

    def test_book_info_enriches_matching_author_and_adds_reading_log(self):
        item = _item("book", "gbooks-1", "google_books",
                     extras=TitleExtras(creators=[TitleCreator(name="Frank Herbert", role="Author")]))
        info = open_library.parse_book_info(TestOpenLibraryBookInfo.DOCS, "Dune", "Frank Herbert",
                                            TestOpenLibraryBookInfo.AUTHOR)
        extras_merge.merge_book_info(item, info)
        author = item.extras.creators[0]
        assert author.bio and author.born == "8 October 1920 – 11 February 1986" and author.photo_url
        assert item.extras.reading_log.want == 1200 and len(item.extras.creators) == 1


# ------------------------------------------------------------------ endpoint

def _detail_params(media_id, source, media_type="game"):
    return {"media_id": media_id, "media_type": media_type, "source": source}


class TestMediaDetailEndpoint:
    def test_cold_game_builds_bundle_then_caches_without_the_store_overlay(
        self, client, register_user, db_session, monkeypatch,
    ):
        user = register_user()
        item = _item(extras=igdb.build_extras(IGDB_GAME))
        calls = {"bundle": 0}

        async def fake_bundle(raw_id):
            calls["bundle"] += 1
            return item, igdb.build_trailers(IGDB_GAME), igdb.build_similar(IGDB_GAME)

        async def fake_store(raw_id, lang):
            return SteamStore(appid="620", price="199 pуб.", metacritic=95)

        async def no_steam(result, lang):
            return None

        monkeypatch.setattr(media_router._games, "full_detail_bundle", fake_bundle)
        monkeypatch.setattr(game_store, "get_store", fake_store)
        monkeypatch.setattr(media_router, "_apply_steam", no_steam)

        resp = client.get("/media/detail", params=_detail_params("igdb-1", "igdb"), headers=user.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["item"]["extras"]["price"] == "199 pуб."          # overlay applied
        assert body["trailers"][0]["video_id"] == "abc123"
        assert [m["id"] for m in body["similar"]] == ["igdb-20"]

        # the price is NOT in the forever cache ...
        stored = MediaDetailOut.model_validate_json(cache.get_static_title(db_session, "igdb-1", "igdb"))
        assert stored.item.extras.price is None and stored.item.extras.languages
        # ... and a second open is a cache hit
        client.get("/media/detail", params=_detail_params("igdb-1", "igdb"), headers=user.headers)
        assert calls["bundle"] == 1

    def test_card_cached_before_extras_existed_is_rebuilt_once(
        self, client, register_user, db_session, monkeypatch,
    ):
        user = register_user()
        cache.set_static_title(db_session, "igdb-2", "igdb", MediaDetailOut(item=_item(id_="igdb-2")))
        new_item = _item(id_="igdb-2", extras=TitleExtras())

        async def fake_bundle(raw_id):
            return new_item, [], []

        async def none(*a, **k):
            return None

        monkeypatch.setattr(media_router._games, "full_detail_bundle", fake_bundle)
        monkeypatch.setattr(game_store, "get_store", none)
        monkeypatch.setattr(media_router, "_apply_steam", none)

        resp = client.get("/media/detail", params=_detail_params("igdb-2", "igdb"), headers=user.headers)
        assert resp.status_code == 200
        stored = MediaDetailOut.model_validate_json(cache.get_static_title(db_session, "igdb-2", "igdb"))
        assert stored.item.extras is not None  # upgraded in place

    def test_incomplete_manga_is_returned_but_not_remembered(
        self, client, register_user, db_session, monkeypatch,
    ):
        user = register_user()
        item = _item("manga", "shikimanga-3", "shikimori_manga", extras=TitleExtras(complete=False))

        async def fake_bundle(raw_id):
            return item, []

        async def none(*a, **k):
            return None

        monkeypatch.setattr(media_router._manga, "full_detail_bundle", fake_bundle)
        monkeypatch.setattr(manga_reviews, "get_manga", none)
        monkeypatch.setattr(manga_reviews, "get_info", none)

        resp = client.get("/media/detail", params=_detail_params("shikimanga-3", "shikimori_manga", "manga"),
                          headers=user.headers)
        assert resp.status_code == 200
        assert cache.get_static_title(db_session, "shikimanga-3", "shikimori_manga") is None
