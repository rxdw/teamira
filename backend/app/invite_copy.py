"""Single source of truth for the wording of invite/referral copy that
otherwise has to be kept in sync by hand across two different surfaces:

- routers/friends.py's GET /friends/invite, which returns `share_text`
  for the person to paste into whatever messaging app they want (no
  HTML, always has the code/link baked in).
- routers/linking.py's GET /i/{code} landing page, whose intro line
  greets whoever *receives* that link/code and lands on the web page
  (HTML context, referrer name instead of a link/code).

These aren't literally the same string — different audience, different
context (plain text vs. HTML), different language register — but they're
both "how tanè talks about being invited", and used to each be
hand-written separately in their own router. Wording tanè's invite
copy from here means a change only has to happen once.
"""


def build_share_text(*, link: str | None, invite_code: str) -> str:
    """The text the *inviting* person shares — friends.py's InviteOut.share_text."""
    if link:
        return f"join me on tanè — track what you watch, read, and play: {link}"
    return f"join me on tanè — track what you watch, read, and play: code {invite_code}"


def build_landing_intro(*, referrer_name: str | None) -> str:
    """The greeting shown on linking.py's GET /i/{code} landing page to
    whoever *receives* the link."""
    if referrer_name:
        return f"{referrer_name} зовёт вас на tanè"
    return "Вас пригласили на tanè"


# Shown wherever the referral program's rules are surfaced to users —
# the referral screen itself (e.g. below the promo code / milestone
# list), a help/FAQ entry, and/or the app's terms of service. Kept here
# alongside the other invite copy rather than hardcoded in a template,
# for the same reason as build_share_text/build_landing_intro above:
# one place to edit, not several screens to keep in sync by hand.
#
# The actual anti-abuse mechanics (IP dedup, streak/entries gate, daily
# cap — see routers/referrals.py) do the real work silently. This line
# exists purely so there's something to point to if a bonus ever needs
# clawing back by hand — it doesn't need to explain how detection works.
REFERRAL_RULES_TEXT = (
    "Бонусы за приглашения начисляются только за реальных, активных "
    "пользователей. Мы оставляем за собой право не засчитывать "
    "приглашение или отменить уже начисленный бонус, если увидим "
    "признаки злоупотребления реферальной программой."
)
