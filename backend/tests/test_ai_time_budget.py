"""Unit tests for the time-budget slice of app/routers/ai.py — the
"есть часа полтора, что посмотреть" feature. All four functions here are
pure (no DB, no network, no embeddings), so these go straight at them
rather than through /ai/ask, which also needs a live adapter/embeddings
call this test environment can't make. See tests/README.md for why
/ai/ask itself stays untested."""

from app.routers.ai import _budget_shape, _parse_spoken_budget, _time_fit_bonus, _time_reasoning
from app.schemas import ExternalIds, LocalizedText, MediaItem


def _item(runtime_minutes) -> MediaItem:
    return MediaItem(
        id="tmdb-1",
        media_type="movie",
        external_ids=ExternalIds(tmdb="1"),
        title=LocalizedText(en="x"),
        description=LocalizedText(en="x"),
        source="tmdb",
        runtime_minutes=runtime_minutes,
    )


class TestParseSpokenBudgetRussian:
    def test_poltora_chasa_is_ninety(self):
        assert _parse_spoken_budget("есть часа полтора, что посмотреть") == 90

    def test_pol_chasa_is_thirty(self):
        assert _parse_spoken_budget("есть только полчаса") == 30

    def test_digit_hours(self):
        assert _parse_spoken_budget("у меня есть 2 часа") == 120

    def test_digit_hours_with_decimal_point(self):
        assert _parse_spoken_budget("2.5 часа свободно") == 150

    def test_digit_hours_with_comma_decimal(self):
        assert _parse_spoken_budget("1,5 ч есть") == 90

    def test_digit_minutes(self):
        assert _parse_spoken_budget("40 минут в запасе") == 40
        assert _parse_spoken_budget("40 мин") == 40

    def test_inverted_word_order_hours(self):
        assert _parse_spoken_budget("часа два, не больше") == 120

    def test_inverted_word_order_minutes_with_digit(self):
        assert _parse_spoken_budget("минут 45 есть") == 45

    def test_spelled_out_minutes(self):
        assert _parse_spoken_budget("есть минут сорок") == 40

    def test_spelled_out_hours(self):
        assert _parse_spoken_budget("часа полтора точно наберётся") == 90

    def test_spelled_out_hours_reverse_order(self):
        assert _parse_spoken_budget("два часа в запасе") == 120


class TestParseSpokenBudgetEnglish:
    def test_half_an_hour(self):
        assert _parse_spoken_budget("I have half an hour") == 30

    def test_digit_hours(self):
        assert _parse_spoken_budget("got about 2 hours tonight") == 120

    def test_digit_minutes(self):
        assert _parse_spoken_budget("only 40 minutes free") == 40


class TestParseSpokenBudgetEdgeCases:
    def test_no_time_language_returns_none(self):
        assert _parse_spoken_budget("три мушкетёра") is None

    def test_a_bare_number_with_no_unit_is_not_a_budget(self):
        assert _parse_spoken_budget("покажи 40") is None

    def test_absurdly_large_value_is_rejected(self):
        # 2000 minutes (~33 hours) is far more likely a typo than a real
        # evening — outside AiAskRequest.minutes_available's own sanity
        # window (10-720), so this should fall through to None rather
        # than returning something absurd.
        assert _parse_spoken_budget("2000 минут") is None

    def test_below_the_floor_is_rejected(self):
        assert _parse_spoken_budget("5 минут всего") is None

    def test_empty_string(self):
        assert _parse_spoken_budget("") is None


class TestBudgetShape:
    def test_short_is_episode(self):
        assert _budget_shape(40) == "episode"
        assert _budget_shape(70) == "episode"

    def test_long_is_movie(self):
        assert _budget_shape(100) == "movie"
        assert _budget_shape(180) == "movie"

    def test_in_between_is_either(self):
        assert _budget_shape(85) == "either"


class TestTimeFitBonus:
    def test_no_runtime_on_file_is_neutral(self):
        assert _time_fit_bonus(_item(None), 90) == 0.0

    def test_zero_runtime_is_neutral(self):
        assert _time_fit_bonus(_item(0), 90) == 0.0

    def test_much_shorter_than_budget_gets_the_smaller_bonus(self):
        # 40 / 90 = 0.44, under the 0.55 cutoff
        assert _time_fit_bonus(_item(40), 90) == 6.0

    def test_fits_comfortably_gets_the_full_bonus(self):
        # 80 / 90 = 0.89
        assert _time_fit_bonus(_item(80), 90) == 14.0

    def test_fits_exactly_still_gets_the_full_bonus(self):
        assert _time_fit_bonus(_item(90), 90) == 14.0

    def test_running_over_is_a_penalty(self):
        # 135 / 90 = 1.5 -> overrun 0.5 of the way to the 2.0 cap
        assert _time_fit_bonus(_item(135), 90) == -11.0

    def test_penalty_is_capped_past_double_the_budget(self):
        way_over = _time_fit_bonus(_item(400), 90)
        at_the_cap = _time_fit_bonus(_item(180), 90)  # exactly 2x
        assert way_over == at_the_cap == -22.0

    def test_penalty_scales_between_fitting_and_the_cap(self):
        small_overrun = _time_fit_bonus(_item(100), 90)  # ratio 1.11
        big_overrun = _time_fit_bonus(_item(150), 90)    # ratio 1.67
        # More overrun -> a bigger (more negative) penalty.
        assert -22.0 < big_overrun < small_overrun < 0.0


class TestTimeReasoning:
    def test_no_runtime_is_none(self):
        assert _time_reasoning(_item(None), 90, lang_ru=True) is None

    def test_fits_with_time_to_spare_russian(self):
        text = _time_reasoning(_item(60), 90, lang_ru=True)
        assert text == "60 мин — останется ещё 30"

    def test_fits_with_time_to_spare_english(self):
        text = _time_reasoning(_item(60), 90, lang_ru=False)
        assert text == "60 min — 30 to spare"

    def test_fits_almost_exactly_uses_the_just_fits_phrasing(self):
        # 90 - 80 = 10 minutes left, under the 20-minute cutoff for
        # "останется ещё N".
        text = _time_reasoning(_item(80), 90, lang_ru=True)
        assert text == "80 мин — как раз"

    def test_runs_over_russian(self):
        text = _time_reasoning(_item(120), 90, lang_ru=True)
        assert text == "120 мин — на 30 дольше, чем есть"

    def test_runs_over_english(self):
        text = _time_reasoning(_item(120), 90, lang_ru=False)
        assert text == "120 min — 30 over"
