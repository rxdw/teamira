"""Tests for the pure helpers of Ask Teamira's game pipeline in
app/routers/ai.py. /ai/ask itself stays untested for the reason in
tests/README.md (it needs live catalog + embedding calls); everything
that decides *what a game ask means and how candidates are ordered* is a
plain function and is covered here."""

import pytest

from app.adapters.igdb import GameHit
from app.routers import ai
from app.schemas import ExternalIds, LocalizedText, MediaItem


def _game(title, rating=8.0, modes=("Co-operative",)) -> MediaItem:
    return MediaItem(
        id=f"igdb-{abs(hash(title)) % 10**6}", media_type="game",
        external_ids=ExternalIds(), title=LocalizedText(en=title),
        description=LocalizedText(en="d"), source="igdb", rating=rating,
        game_modes=list(modes),
    )


class TestMediaKinds:
    def test_a_watch_verb_rules_out_games(self):
        assert ai._media_kinds("что посмотреть вечером") == {"movie", "tv"}

    def test_a_play_verb_means_games(self):
        assert ai._media_kinds("something to play tonight") == {"game"}
        assert ai._media_kinds("во что поиграть") == {"game"}

    def test_both_verbs_or_neither_keeps_the_default(self):
        default = {"movie", "tv", "game"}
        assert ai._media_kinds("watch or play something") == default
        assert ai._media_kinds("sci-fi") == default

    def test_play_inside_another_word_does_not_count(self):
        assert ai._media_kinds("display case") == {"movie", "tv", "game"}

    def test_an_explicit_kind_wins(self):
        assert ai._media_kinds("movie for two") == {"movie"}


class TestGameTitleQuery:
    def test_a_short_remainder_can_be_a_title(self):
        assert ai._game_title_query("hollow knight") == "hollow knight"

    def test_nothing_left_means_no_title_lookup(self):
        assert ai._game_title_query("") is None

    def test_a_long_description_is_not_a_title(self):
        assert ai._game_title_query("game where you do many different things every single day of week") is None


class TestTitleHitRelevant:
    def test_needs_half_the_words_in_the_title(self):
        item = _game("Hollow Knight")
        assert ai._title_hit_relevant(["hollow", "knight"], item)
        assert ai._title_hit_relevant(["hollow", "bird"], item)
        assert not ai._title_hit_relevant(["cozy", "farming"], item)

    def test_no_tokens_is_never_relevant(self):
        assert not ai._title_hit_relevant([], _game("Anything"))


class TestRelaxationLadder:
    def test_strictest_first_then_era_then_topic_but_never_the_mode(self):
        steps = ai._relaxation_ladder((3,), (9,), (), 2030, 2039)
        assert steps[0]["year_from"] == 2030 and steps[0]["genre_ids"] == (9,)
        assert steps[1]["year_from"] is None and steps[1]["genre_ids"] == (9,)
        assert steps[2]["genre_ids"] == () and steps[2]["mode_ids"] == (3,)
        assert all(step["mode_ids"] == (3,) for step in steps)

    def test_a_bare_mode_ask_has_nothing_to_relax(self):
        assert len(ai._relaxation_ladder((3,), (), (), None, None)) == 1


class TestQualityBonus:
    def test_bounded(self):
        best = ai._game_quality_bonus(_game("x", rating=9.5), GameHit(item=_game("x"), rating_count=50000))
        assert 11.9 <= best <= 12.0
        assert ai._game_quality_bonus(_game("x", rating=None), None) == 0.0

    def test_more_ratings_and_a_higher_score_both_help(self):
        low = ai._game_quality_bonus(_game("a", 6.5), GameHit(item=_game("a"), rating_count=20))
        high = ai._game_quality_bonus(_game("a", 8.8), GameHit(item=_game("a"), rating_count=2000))
        assert high > low


class TestFranchiseCap:
    @pytest.mark.parametrize("a,b", [
        ("Borderlands 3", "Borderlands: The Pre-Sequel"),
        ("Left 4 Dead 2", "Left 4 Dead"),
        ("Portal 2", "Portal"),
        ("Diablo III", "Diablo"),
    ])
    def test_sequels_share_a_key(self, a, b):
        assert ai._franchise_key(a) == ai._franchise_key(b)

    def test_a_title_that_merely_ends_in_numeral_letters_is_kept_whole(self):
        assert ai._franchise_key("Civ") == "civ"

    def test_a_series_takes_at_most_two_places_and_others_still_fit(self):
        rows = [(0, 0, 0, _game(t), None) for t in
                ["Borderlands 2", "Borderlands 3", "Borderlands: The Pre-Sequel", "Portal 2"]]
        picked = [r[3].title.en for r in ai._pick_top(rows, limit=10)]
        assert picked == ["Borderlands 2", "Borderlands 3", "Portal 2"]

    def test_only_games_are_capped(self):
        movie = MediaItem(id="tmdb-1", media_type="movie", external_ids=ExternalIds(),
                          title=LocalizedText(en="Saw"), description=LocalizedText(en="d"), source="tmdb")
        rows = [(0, 0, 0, movie, None)] * 5
        assert len(ai._pick_top(rows, limit=10)) == 5

    def test_limit_is_respected(self):
        rows = [(0, 0, 0, _game(f"Game {chr(65 + i)}{i}"), None) for i in range(10)]
        assert len(ai._pick_top(rows, limit=4)) == 4
