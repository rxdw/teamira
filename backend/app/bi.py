"""A text that exists in both languages — for things the SERVER words and the
phone only displays (push notifications, today).

`Bi` is a `str` whose value is the Russian text, with the English one riding
along as `.en`. Everything that already treats a push title/body as a plain
string — the PushLog row, equality checks in tests, `_sent_today_with_title`
— keeps working unchanged on the Russian text, because that is the str; only
the one place that knows which language a device wants (app/push.py::
PushService.send_to_user) asks for the other.

Russian is the default on purpose: it is what every push was before devices
reported a language, so a token that never said (an old install) keeps
getting exactly what it always got.
"""

from typing import Optional


class Bi(str):
    en: str

    def __new__(cls, ru: str, en: str) -> "Bi":
        obj = super().__new__(cls, ru)
        obj.en = en
        return obj


def pick(text: str, lang: Optional[str]) -> str:
    """The English text of a Bi when `lang` is English, else the plain str
    (a Bi's Russian text, or a str that was never bilingual)."""
    if lang == "en" and isinstance(text, Bi):
        return text.en
    return str(text)


def normalize_lang(raw: Optional[str]) -> str:
    """"en", "en-US", "EN_gb" -> "en"; anything else, or nothing -> "ru"."""
    return "en" if (raw or "").strip().lower().startswith("en") else "ru"


def years_en(n: int) -> str:
    return f"{n} year" if n == 1 else f"{n} years"
