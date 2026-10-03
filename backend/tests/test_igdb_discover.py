"""Tests for the pure query-building half of IgdbAdapter.discover — Ask
Teamira's quality-gated game discovery. The exact APICalypse text matters
(a wrong clause is a silent empty shortlist), and building it needs no
network, so it's checked directly."""

from app.adapters.igdb import build_discover_query


class TestBuildDiscoverQuery:
    def test_always_requires_a_cover_and_an_audience(self):
        q = build_discover_query(min_rating_count=25)
        assert "cover != null" in q and "total_rating_count >= 25" in q

    def test_rating_floor_only_when_asked_for(self):
        assert "total_rating >=" not in build_discover_query(min_rating_count=4, min_rating=0)
        assert "total_rating >= 68" in build_discover_query(min_rating_count=25, min_rating=68)

    def test_play_mode_filter(self):
        assert "game_modes = (3)" in build_discover_query(mode_ids=[3])
        assert "game_modes = (2,3,4)" in build_discover_query(mode_ids=[4, 3, 2, 3])

    def test_genres_and_themes_are_or_matched(self):
        q = build_discover_query(genre_ids=[5, 25], theme_ids=[19, 21])
        assert "(genres = (5,25) | themes = (19,21))" in q

    def test_a_single_topical_group_needs_no_parentheses_around_the_or(self):
        assert "themes = (18)" in build_discover_query(theme_ids=[18])
        assert "|" not in build_discover_query(theme_ids=[18])

    def test_structural_clauses_can_be_switched_off(self):
        assert "parent_game = null" in build_discover_query()
        assert "version_parent = null" in build_discover_query()
        q = build_discover_query(structural=False)
        assert "parent_game" not in q and "version_parent" not in q

    def test_year_window(self):
        q = build_discover_query(year_from=2010, year_to=2019)
        assert "first_release_date >= 1262304000" in q
        assert "first_release_date <= 1577750400" in q

    def test_sort_and_limit(self):
        q = build_discover_query(sort="total_rating_count", limit=50)
        assert "sort total_rating_count desc;" in q and q.rstrip().endswith("limit 50;")

    def test_text_search_keeps_relevance_order_and_escapes_quotes(self):
        q = build_discover_query(text='say "hi"', sort="total_rating", min_rating_count=5)
        assert q.startswith('search "say \\"hi\\"";')
        assert "sort" not in q  # an explicit sort would discard search relevance

    def test_fetches_what_ask_needs_beyond_the_shared_fields(self):
        q = build_discover_query()
        assert "total_rating_count" in q.split("where")[0] and "themes.name" in q.split("where")[0]
        assert "game_modes.name" in q
