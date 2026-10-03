"""Tests for app/routers/imports.py. POST /import/preview resolves every
parsed line against a live TMDB search (see preview_import's own
_tmdb.catalog_search call) and isn't covered here. Everything parsing-
related (_parse_csv/_parse_plain_text/_parse_pasted_text/_best_match/
_parse_watched_at) is pure and tested directly; POST /import/commit
takes already-resolved MediaItem objects with no adapter call at all,
so that's covered through real HTTP."""

from app.routers.imports import (
    _best_match,
    _parse_csv,
    _parse_pasted_text,
    _parse_plain_text,
    _parse_watched_at,
)
from app.schemas import ExternalIds, LocalizedText, MediaItem


def _candidate(id_, year=None) -> MediaItem:
    return MediaItem(
        id=id_, media_type="movie", external_ids=ExternalIds(tmdb=id_),
        title=LocalizedText(en=id_), description=LocalizedText(), source="tmdb", year=year,
    )


class TestParseCsv:
    def test_letterboxd_style_columns(self):
        text = "Name,Year,Rating,Watched Date\nThe Matrix,1999,4.5,2024-01-02\n"
        lines = _parse_csv(text)
        assert len(lines) == 1
        assert lines[0].title == "The Matrix"
        assert lines[0].year == 1999
        assert lines[0].watched_at == "2024-01-02"

    def test_star_rating_scales_to_ten_hearts(self):
        # Letterboxd stars: 0.5-5 in half-star steps -> 1-10 hearts.
        lines = _parse_csv("Name,Rating\nx,4.5\n")
        assert lines[0].rating == 9
        lines = _parse_csv("Name,Rating\ny,0.5\n")
        assert lines[0].rating == 1

    def test_accepts_title_or_film_column_too(self):
        assert _parse_csv("Title\nInception\n")[0].title == "Inception"
        assert _parse_csv("Film\nInception\n")[0].title == "Inception"

    def test_row_with_no_title_column_match_is_skipped(self):
        assert _parse_csv("Foo,Bar\nx,y\n") == []

    def test_column_names_are_case_and_whitespace_insensitive(self):
        lines = _parse_csv(" Name , Year \n Dune , 2021 \n")
        assert lines[0].title == "Dune"
        assert lines[0].year == 2021

    def test_garbage_year_is_ignored_not_a_crash(self):
        lines = _parse_csv("Name,Year\nx,not-a-year\n")
        assert lines[0].year is None


class TestParsePlainText:
    def test_one_title_per_line(self):
        lines = _parse_plain_text("The Matrix\nInception\n")
        assert [l.title for l in lines] == ["The Matrix", "Inception"]

    def test_strips_bullet_prefixes(self):
        lines = _parse_plain_text("- The Matrix\n• Inception\n* Dune\n")
        assert [l.title for l in lines] == ["The Matrix", "Inception", "Dune"]

    def test_extracts_a_trailing_year_in_parens(self):
        lines = _parse_plain_text("The Matrix (1999)\n")
        assert lines[0].title == "The Matrix"
        assert lines[0].year == 1999

    def test_blank_lines_are_skipped(self):
        lines = _parse_plain_text("The Matrix\n\n\nInception\n")
        assert len(lines) == 2

    def test_raw_keeps_the_original_untrimmed_line(self):
        lines = _parse_plain_text("  - The Matrix (1999)  \n")
        assert lines[0].raw == "- The Matrix (1999)"
        assert lines[0].title == "The Matrix"


class TestParsePastedTextDetection:
    def test_detects_csv_by_header(self):
        _, detected = _parse_pasted_text("Name,Year\nThe Matrix,1999\n")
        assert detected == "csv"

    def test_plain_single_column_is_text_even_with_a_comma_free_first_line(self):
        _, detected = _parse_pasted_text("The Matrix\nInception\n")
        assert detected == "text"

    def test_a_line_with_a_comma_but_no_title_like_header_is_still_text(self):
        # Only >1 column AND a recognizable title-column header counts as CSV.
        _, detected = _parse_pasted_text("something, else\nmore, stuff\n")
        assert detected == "text"

    def test_empty_input(self):
        lines, detected = _parse_pasted_text("   ")
        assert lines == []
        assert detected == "text"


class TestBestMatch:
    def test_no_candidates(self):
        assert _best_match(1999, []) == (None, [])

    def test_no_year_hint_picks_the_first_candidate(self):
        candidates = [_candidate("a"), _candidate("b")]
        matched, alternates = _best_match(None, candidates)
        assert matched.id == "a"
        assert [c.id for c in alternates] == ["b"]

    def test_prefers_a_same_year_candidate_over_the_first_result(self):
        candidates = [_candidate("wrong_year", 2010), _candidate("right_year", 1999)]
        matched, _ = _best_match(1999, candidates)
        assert matched.id == "right_year"

    def test_falls_back_to_the_first_result_if_no_year_matches(self):
        candidates = [_candidate("a", 2010), _candidate("b", 2011)]
        matched, _ = _best_match(1999, candidates)
        assert matched.id == "a"

    def test_alternates_are_capped_at_four(self):
        candidates = [_candidate(str(i)) for i in range(10)]
        _, alternates = _best_match(None, candidates)
        assert len(alternates) == 4


class TestParseWatchedAt:
    def test_date_only_format(self):
        assert _parse_watched_at("2024-01-02").year == 2024

    def test_datetime_format(self):
        parsed = _parse_watched_at("2024-01-02T10:30:00")
        assert parsed.hour == 10

    def test_none_falls_back_to_now(self):
        from datetime import datetime, timezone
        before = datetime.now(timezone.utc)
        parsed = _parse_watched_at(None)
        assert parsed >= before

    def test_unparseable_string_falls_back_to_now_not_a_crash(self):
        from datetime import datetime, timezone
        before = datetime.now(timezone.utc)
        parsed = _parse_watched_at("not a date at all")
        assert parsed >= before


class TestCommitImport:
    def test_requires_auth(self, client, sample_media_item):
        resp = client.post("/import/commit", json={"rows": [{"item": sample_media_item(), "status": "watched"}]})
        assert resp.status_code == 401

    def test_empty_rows_is_400(self, client, register_user):
        alice = register_user()
        resp = client.post("/import/commit", json={"rows": []}, headers=alice.headers)
        assert resp.status_code == 400

    def test_watched_row_logs_a_diary_entry_with_its_rating(self, client, register_user, sample_media_item):
        alice = register_user()
        resp = client.post(
            "/import/commit",
            json={"rows": [{"item": sample_media_item(), "status": "watched", "rating": 8}]},
            headers=alice.headers,
        )
        assert resp.status_code == 200
        assert resp.json() == {"watched_count": 1, "watch_later_count": 0}

        diary = client.get("/diary", headers=alice.headers).json()
        assert len(diary) == 1
        assert diary[0]["rating"] == 8

    def test_watch_later_row_creates_a_watchlist_entry(self, client, register_user, sample_media_item):
        alice = register_user()
        item = sample_media_item()
        resp = client.post(
            "/import/commit", json={"rows": [{"item": item, "status": "watch_later"}]}, headers=alice.headers
        )
        assert resp.json() == {"watched_count": 0, "watch_later_count": 1}

        collections = client.get("/profile/collections", headers=alice.headers).json()
        assert item["id"] in [e["media_id"] for e in collections["watch_later"]]

    def test_watching_row_lands_on_the_watching_shelf(self, client, register_user, sample_media_item):
        alice = register_user()
        item = sample_media_item()
        client.post("/import/commit", json={"rows": [{"item": item, "status": "watching"}]}, headers=alice.headers)

        collections = client.get("/profile/collections", headers=alice.headers).json()
        assert item["id"] in [e["media_id"] for e in collections["watching"]]

    def test_a_second_import_of_the_same_title_updates_rather_than_duplicates(
        self, client, register_user, sample_media_item
    ):
        alice = register_user()
        item = sample_media_item()
        client.post("/import/commit", json={"rows": [{"item": item, "status": "watch_later"}]}, headers=alice.headers)
        client.post("/import/commit", json={"rows": [{"item": item, "status": "watching"}]}, headers=alice.headers)

        collections = client.get("/profile/collections", headers=alice.headers).json()
        assert len(collections["watch_later"]) + len(collections["watching"]) == 1
        assert item["id"] in [e["media_id"] for e in collections["watching"]]

    def test_mixed_batch_counts_each_bucket_correctly(self, client, register_user, sample_media_item):
        alice = register_user()
        resp = client.post(
            "/import/commit",
            json={
                "rows": [
                    {"item": sample_media_item(), "status": "watched"},
                    {"item": sample_media_item(), "status": "watch_later"},
                    {"item": sample_media_item(), "status": "watch_later"},
                ]
            },
            headers=alice.headers,
        )
        assert resp.json() == {"watched_count": 1, "watch_later_count": 2}

    def test_invalid_rating_is_rejected_by_validation(self, client, register_user, sample_media_item):
        alice = register_user()
        resp = client.post(
            "/import/commit",
            json={"rows": [{"item": sample_media_item(), "status": "watched", "rating": 99}]},
            headers=alice.headers,
        )
        assert resp.status_code == 422
