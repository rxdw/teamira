"""Unit tests for app/game_intent.py — how an Ask says a game should be
*played* ("co-op game for two"). Pure string work: no DB, no network, no
embeddings, so these go straight at the parser.

The regression these exist for: "co-op game for two" used to have no
signal the ranker understood, fell through to an IGDB *title* search, and
came back with a fan mod, a brain-training cartridge and a joke simulator.
"""

import pytest

from app import game_intent as gi


def _parse(q, explicit=True):
    return gi.parse(q, games_explicit=explicit)


class TestStrongVocabularyIsEnoughOnItsOwn:
    @pytest.mark.parametrize("q", [
        "co-op for two", "coop", "co op games", "cooperative", "co-operative",
        "кооператив", "кооперативная игра", "split screen", "сплит-скрин",
        "multiplayer", "мультиплеер",
    ])
    def test_counts_even_without_the_word_game(self, q):
        intent = _parse(q, explicit=False)
        assert intent.active and intent.strong

    def test_coop_requires_the_coop_mode(self):
        assert _parse("co-op game for two").required_modes == {gi.MODE_COOP}

    def test_split_screen_requires_split_screen(self):
        assert _parse("split screen racing game").required_modes == {gi.MODE_SPLIT}


class TestSoftPhrasesNeedAGameAsk:
    @pytest.mark.parametrize("q", [
        "movie for two", "фильм для двоих", "что посмотреть вдвоём",
        "something to watch with a friend", "фильм на диване",
    ])
    def test_ignored_when_the_ask_is_not_about_games(self, q):
        assert not _parse(q, explicit=False).active

    @pytest.mark.parametrize("q,players", [
        ("game for two", 2), ("2 player game", 2), ("two-player game", 2),
        ("игра для двоих", 2), ("во что поиграть вдвоём", 2),
        ("game to play with a friend", 2), ("игра с девушкой", 2),
        ("game for three", 3), ("игра втроём", 3),
        ("game for 4 players", 4), ("игра вчетвером", 4),
    ])
    def test_head_counts(self, q, players):
        intent = _parse(q)
        assert intent.active and intent.players == players and not intent.strong

    def test_for_two_accepts_coop_versus_and_couch(self):
        intent = _parse("game for two")
        assert intent.required_modes == {gi.MODE_COOP, gi.MODE_MULTI, gi.MODE_SPLIT}
        assert intent.preferred_modes == {gi.MODE_COOP, gi.MODE_SPLIT}


class TestThingsThatLookLikeIntentButAreNot:
    @pytest.mark.parametrize("q", [
        "a game for 2 hours tonight", "game for 3 days", "game for 4 year olds",
        "party-based rpg", "single player story game", "cozy farming game",
    ])
    def test_no_false_positives(self, q):
        assert not _parse(q).active


class TestEvaluate:
    def test_coop_ask_drops_games_without_coop(self):
        intent = _parse("co-op game for two")
        assert intent.evaluate(["Single player"]) is None
        assert intent.evaluate([]) is None

    def test_coop_ask_keeps_coop_and_labels_it(self):
        fit = _parse("co-op game for two").evaluate(["Single player", "Co-operative"])
        assert fit.bonus == gi.MODE_MATCH_BONUS and fit.labels == ("co-op",)

    def test_small_group_asks_reject_mmos_and_battle_royales(self):
        intent = _parse("co-op game for two")
        assert intent.evaluate(["Massively Multiplayer Online (MMO)", "Co-operative"]) is None
        assert intent.evaluate(["Battle Royale", "Co-operative"]) is None

    def test_an_mmo_with_split_screen_is_allowed(self):
        assert _parse("co-op game").evaluate(["Massively Multiplayer Online (MMO)", "Co-operative", "Split screen"]) is not None

    def test_preferred_mode_earns_the_extra_bonus(self):
        intent = _parse("game for two")
        assert intent.evaluate(["Co-operative"]).bonus == gi.MODE_MATCH_BONUS + gi.MODE_PREFERRED_BONUS
        assert intent.evaluate(["Multiplayer"]).bonus == gi.MODE_MATCH_BONUS

    def test_no_intent_is_neutral_for_every_game(self):
        fit = _parse("cozy game").evaluate(["Single player"])
        assert fit.bonus == 0.0 and fit.labels == ()


class TestStrip:
    def test_removes_play_mode_words_and_keeps_the_topic(self):
        assert gi.strip("horror co-op game for two") == "horror game"

    def test_multiplayer_no_longer_looks_like_animation(self):
        # "мультиплеер" starts with "мульт", an animation keyword.
        assert "мульт" not in gi.strip("мультиплеер игра")
