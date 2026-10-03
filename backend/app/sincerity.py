"""Sincerity points — the app's one progression currency. Buys a
handful of small, real perks (see the second section of this
docstring), and its lifetime total drives the level ring in the merged
Sincerity screen. See mobile's sincerity_screen.dart for how the
balance, level and history are shown, and settings_screen.dart for the
one privacy toggle that governs whether a friend can see the balance at
all.

This module went through a second product reversal worth recording,
bigger than the first one below: it used to be deliberately narrow —
"only for closing an honest loop, never for raw activity" — while a
*separate*, live-recomputed XP/level system (formerly
routers/profile.py::compute_level_for_user) covered ordinary activity:
watching things, writing reviews, rewatching, streaks, inviting
friends, sharing cards, claiming challenges. Two numbers, two
philosophies, both shown on Profile.

In practice that meant explaining to every new arrival which of two
near-identical-looking counters a given action fed, and — the concrete
trigger — that the honest-acts-only currency had gotten broad enough
(recommendation stakes, nudges, revealing a hidden rating) that "closes
a loop honestly" was already stretching to cover things that are really
just social/paired activity, not honesty specifically. Splitting hairs
between the two systems was costing more than the purity of keeping
raw activity out of sincerity was worth. So: one currency. Sincerity
points are now everything — the honest-act reasons below (closed_gestalt
through second_chance) keep their original, larger, "this was a genuinely
notable honest act" weight, and a new "everyday activity" section pays
out the same small, flat, one-time award the old XP wells used to
compute live, just as real ledger rows instead — see
earn_watched_logged and friends, below the original honest-act
functions.

The old XP system could never be "spent" for exactly the reason this
merge had to solve: it was recomputed fresh from raw activity on every
read, so a balance that could go down would just silently refill itself
right back up from the same underlying rows. Every one of the wells
below is instead a one-time ledger write, fired from the exact place
the underlying fact first becomes true (a title first reaches `watched`,
a diary entry is created with a note, a streak grows past its old
high-water mark, ...) — the same "record once, never recompute" shape
every earn_* function in the honest-acts section already used. That's
what makes the merged balance genuinely spendable without a later read
un-spending it. Level, in turn, is computed from
User.lifetime_sincerity_earned (a separate, monotonically-increasing
running total — see record_transaction), not from sincerity_balance
itself, so that spending never knocks anyone back down a level.

The size mismatch between the two systems (honest acts: 1-4 points;
old XP: 10-500) is resolved by pulling the everyday-activity numbers
*down* to the honest-acts scale, not the other way — see this module's
existing "small, deliberately unglamorous integers" principle below,
which now applies to literally everything in the ledger. The level
curve was rescaled the same direction (see LEVEL_BASE_POINTS/
LEVEL_STEP_POINTS).

This module went through one product reversal worth recording. It
originally shipped as "purely reflective — a mirror, not a paywall",
deliberately never gating anything. In practice that meant three of
the reasons below (recommendation_stake/accurate_recommendation/
stake_forfeited, spoiler_unlock, debt_settled) were fully worked out in
the ledger math and in the Sincerity screen's own "как это работает"
copy, but had no feature anywhere in the app that actually triggered
them — a currency you could earn but never meaningfully spend. The
fix wasn't more earning; it was giving the existing spends somewhere
real to go:

- recommendation_stake now backs a real feature (see
  app/routers/recommendations.py) — stake points on a friend liking
  something you recommend, and get them back with a bonus if you called
  it right.
- spoiler_unlock now buys an early, specific thing: seeing a
  circle-mate's already-shared rating on a shared-diary title before
  you've rated it yourself (see app/routers/shared_diary.py's
  rating_hidden logic and reveal_rating). The honest default is your
  own opinion forms first — formed_own_opinion is the earn side of that
  same trade, for the times you didn't pay to peek.
- debt_settled now buys something concrete too: permanently exempting
  one stale watch_later item from further stale_debt decay (see
  WatchlistEntry.debt_exempt), for a flat fee, once.
- pin_slot_purchased is the newest of the four, and the only one with
  no earn-side counterpart — a flat, permanent purchase of one more
  badge-showcase slot (see User.bonus_pin_slots and
  routers/profile.py::pin_achievements/buy_pin_slot), for someone who'd
  rather show off more of an already-earned track record than spend the
  points on anything above.

Two more were added in the same spirit, after "still only four things
to spend on, still only five ways to earn" was itself the next round of
product feedback:

- second_chance is honest_drop's mirror on the earn side: going back to
  something you dropped with a real reason and actually finishing it
  later, rather than quietly re-adding it and pretending the drop never
  happened (see earn_second_chance and SECOND_CHANCE_MIN_AGE for the
  "long enough to be a real change of heart" guard).
- nudge_sent is the cheapest spend in the economy on purpose: one push
  notification, not a feature unlock, prodding a circle-mate about a
  shared plan that's gone stale (see spend_nudge,
  routers/shared_diary.py::nudge, and NUDGE_STALE_THRESHOLD/
  NUDGE_COOLDOWN for what "stale enough, not spammy" means here).

Design principles this module still enforces:

- Earn for *closing an honest loop*, never for raw activity. There is no
  reward anywhere in this file for logging more, rating more, or
  writing longer notes — only for closing a planned item honestly,
  revising a past opinion instead of defending it, dropping something
  with a real reason, forming your own opinion before peeking at a
  circle-mate's, or a recommendation stake paying off.
- Spend only on actions that create *more* exposure, *more* honesty, or
  showcase a track record that's already genuinely earned — never on
  anything that fakes the signal itself (no buying a public rating, no
  buying a "trustworthy" badge with no track record behind it, no way
  to un-form an opinion after the fact). pin_slot_purchased fits this
  because it only ever surfaces *unlocked* achievements — the badges
  themselves are still earned the normal way; the purchase is just
  permission to show off more of them at once.
- Every earn/spend call writes exactly one SincerityTransaction in the
  same commit as the balance change (see record_transaction) — the
  ledger and the denormalized balance can never disagree.
- All thresholds/amounts below are small, deliberately unglamorous
  integers. This is not meant to feel like a game economy with tunable
  power curves; the numbers exist only so the history reads clearly
  ("+2", "-3"), not to be optimized.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app import models

# ---------------------------------------------------------------------------
# Tunables — kept in one place and named, not sprinkled as bare numbers
# through the functions below, so a future rebalance is a one-line change
# with an obvious blast radius.
# ---------------------------------------------------------------------------

# How long a watch_later item has to sit untouched before *finally*
# closing it (watched, or honestly marked "not for me") counts as
# closing a real gestalt rather than routine housekeeping.
STALE_PLANNED_THRESHOLD = timedelta(days=90)
# Above the threshold, the award scales with how long it hung — capped
# so a five-year-old forgotten item doesn't dwarf everything else in the
# history. +1 per additional threshold-period waited, up to this many
# points on top of the base award.
CLOSED_GESTALT_BASE = 1
CLOSED_GESTALT_MAX_BONUS = 4

REVISED_RATING_AWARD = 2
# A rating can't be "revised" twice in a row for points inside this
# window — otherwise nudging a rating up and down repeatedly would farm
# this reason. Only the *first* change after this cool-down earns.
REVISED_RATING_COOLDOWN = timedelta(days=14)

HONEST_DROP_AWARD = 1

# A person who dropped something and comes back to it later, honestly,
# is doing the opposite of defending a first impression — see
# earn_second_chance. Needs SECOND_CHANCE_MIN_AGE to have actually
# passed since the drop, so "dropped, then immediately un-dropped and
# finished it five minutes later" (routine list housekeeping, not a
# real change of heart) doesn't farm this.
SECOND_CHANCE_AWARD = 1
SECOND_CHANCE_MIN_AGE = timedelta(days=3)

# Recommendation stakes: the recommender chooses how much to risk
# (bounded below), and a correct call pays back the stake plus a
# fraction — never a multiple large enough to make staking a way to
# *grow* a balance faster than closing real gestalts does.
MIN_RECOMMENDATION_STAKE = 1
MAX_RECOMMENDATION_STAKE = 5
ACCURATE_RECOMMENDATION_BONUS_RATE = 0.5  # +50% of the staked amount back on a hit
# A prediction is "accurate" when the friend's actual rating lands
# within this many points (on the same 1-10 scale) of what was staked.
RECOMMENDATION_TOLERANCE = 2

SPOILER_UNLOCK_COST = 2

# Past this long with no rating logged, a staked recommendation is
# nobody's fault anymore — the stake is returned in full (see
# expire_recommendation_stake) rather than sitting pending forever or
# quietly burning the staker for a friend who was just never going to
# get to it.
RECOMMENDATION_EXPIRY = timedelta(days=120)

# A watch_later item past this age starts quietly costing upkeep — the
# "debt" side of the economy. Charged at most once per item per period
# (see apply_stale_planned_decay), not compounding daily.
STALE_DEBT_THRESHOLD = timedelta(days=180)
STALE_DEBT_PERIOD = timedelta(days=30)
STALE_DEBT_AMOUNT = 1
# A one-time, flat-fee way off the stale_debt treadmill for one item —
# see spend_debt_settlement and WatchlistEntry.debt_exempt. Priced above
# a single STALE_DEBT_AMOUNT charge (settling only pays for itself once
# the item would otherwise have bled for a few periods) so it's a real
# choice, not a strictly-dominant one over just letting it decay.
DEBT_SETTLEMENT_COST = 3

# One more permanent badge-showcase slot, on top of the free 3 (see
# User.bonus_pin_slots and routers/profile.py::pin_achievements). Capped
# at MAX_BONUS_PIN_SLOTS so the showcase — deliberately a *curated*
# highlight reel, not a second achievements list — can't be bought its
# way into pointlessness.
PIN_SLOT_COST = 4
MAX_BONUS_PIN_SLOTS = 3

# A push notification, not a feature unlock — the cheapest spend in the
# whole economy on purpose, since all it buys is one nudge, once, not
# an ongoing capability. NUDGE_STALE_THRESHOLD gates it to the same
# "actually stuck", not "added yesterday", bar the rest of the debt
# side of the economy uses; NUDGE_COOLDOWN stops the same title from
# being nudged into a notification-spam vector.
NUDGE_COST = 1
NUDGE_STALE_THRESHOLD = timedelta(days=21)
NUDGE_COOLDOWN = timedelta(days=14)

# The honest-default reward for forming your own opinion on a shared
# title instead of spending SPOILER_UNLOCK_COST to see a circle-mate's
# rating first — see earn_formed_own_opinion. Small and roughly
# balanced against that cost: peeking and not peeking are both
# reasonable choices, neither strictly wins.
OWN_OPINION_AWARD = 1

# ---------------------------------------------------------------------------
# Everyday activity — the wells merged in from the old, live-recomputed
# XP system (see this module's own docstring for the full story). Every
# one of these is a flat, one-time award; none of them scale with how
# much someone does beyond the single event they represent, on purpose —
# same "small, unglamorous integer" stance as the honest-acts section
# above, just applied to a broader set of triggers now.
# ---------------------------------------------------------------------------

WATCHED_LOGGED_AWARD = 1        # a title reaches `watched` for the first time ever
REVIEW_WRITTEN_AWARD = 1        # a diary entry logged with an actual note attached
REWATCH_LOGGED_AWARD = 1        # logging a title again after it was already watched
TOGETHER_BONUS_AWARD = 1        # on top of watched/rewatch, for an evening logged as watched together
GENRE_EXPLORED_AWARD = 1        # one genre, the first time it's ever logged on this account
# One point per day added to this account's longest-ever streak, paid
# out as the streak actually grows rather than in a lump sum at some
# milestone — see earn_streak_progress and User.streak_sincerity_award_days
# for how a broken-then-restarted streak doesn't re-earn days it already
# has credit for.
STREAK_DAY_AWARD = 1
FRIEND_INVITED_AWARD = 3        # a real person registered using this account's invite code
CARD_SHARE_AWARD = 1            # a share card left the app (see routers/card_shares.py's own caps)

# Each level costs more than the last — level 1->2 takes 8 points, and
# every level after that costs 3 more than the one before it. Same
# simple rising-staircase shape the old XP system's level curve used
# (100 base / +40 per level), pulled down to match the new, much
# smaller per-action awards above (see this module's docstring).
LEVEL_BASE_POINTS = 8
LEVEL_STEP_POINTS = 3


def compute_level(lifetime_points: int) -> tuple[int, int, int]:
    """Returns (level, points_into_current_level, points_for_next_level).
    Mirrors the old routers/profile.py::_compute_level exactly, just
    against the new curve and against User.lifetime_sincerity_earned
    instead of a live-recomputed XP total — see this module's docstring
    for why lifetime-earned, not the spendable balance, is what level is
    computed from.
    """
    level = 1
    remaining = max(lifetime_points, 0)
    needed = LEVEL_BASE_POINTS
    while remaining >= needed:
        remaining -= needed
        level += 1
        needed += LEVEL_STEP_POINTS
    return level, remaining, needed


def title_key(source: str, media_id: str) -> str:
    """The stable per-title identifier earn_revised_rating's cool-down
    is keyed on — see that function's docstring for why a title needs
    one shared key across its WatchlistEntry and (possibly several)
    DiaryEntry rows. Both call sites should build this the same way
    rather than hand-rolling the format, so a future third caller can't
    quietly drift to a different string shape and defeat the cool-down.
    """
    return f"{source}:{media_id}"


def record_transaction(
    db: Session,
    user: models.User,
    *,
    delta: int,
    reason: models.SincerityReason,
    note: Optional[str] = None,
    related_entry_id: Optional[str] = None,
    related_user_id: Optional[str] = None,
) -> models.SincerityTransaction:
    """The one place that ever changes User.sincerity_balance — every
    earn_*/spend_* function below (and any future one) must go through
    this rather than touching the column directly, so the balance and
    the ledger can never drift apart. Does not commit; same convention
    as routers/diary.py::log_watched — the caller commits once, after
    whatever else it's writing in the same request.
    """
    user.sincerity_balance += delta
    if delta > 0:
        # Never decremented, even by a spend — see User.lifetime_sincerity_
        # earned's own docstring for why level is computed from this
        # instead of the spendable balance above.
        user.lifetime_sincerity_earned += delta
    txn = models.SincerityTransaction(
        user_id=user.id,
        delta=delta,
        reason=reason,
        note=note,
        related_entry_id=related_entry_id,
        related_user_id=related_user_id,
    )
    db.add(txn)
    return txn


# ---------------------------------------------------------------------------
# Earning
# ---------------------------------------------------------------------------


def earn_closed_gestalt(
    db: Session,
    user: models.User,
    *,
    entry_id: str,
    title: str,
    planned_since: datetime,
    closed_honestly_as: str,  # "watched" | "not for me" — for the history note only
) -> Optional[models.SincerityTransaction]:
    """Call when a WatchlistEntry leaves `watch_later` for real — either
    logged as watched (routers/diary.py::log_watched) or explicitly
    marked "not for me" (a new, lightweight status distinct from
    `dropped`, which already means "started, then gave up" — see
    honest_drop below for that case instead). Returns None (awards
    nothing) if it hadn't been sitting long enough to count as a real
    gestalt rather than routine list upkeep.
    """
    age = datetime.now(timezone.utc) - planned_since
    if age < STALE_PLANNED_THRESHOLD:
        return None
    extra_periods = int((age - STALE_PLANNED_THRESHOLD) / STALE_PLANNED_THRESHOLD)
    award = CLOSED_GESTALT_BASE + min(extra_periods, CLOSED_GESTALT_MAX_BONUS)
    return record_transaction(
        db, user,
        delta=award,
        reason=models.SincerityReason.closed_gestalt,
        note=f"{title} — {closed_honestly_as}, after {age.days} days on your list",
        related_entry_id=entry_id,
    )


def earn_revised_rating(
    db: Session,
    user: models.User,
    *,
    title_key: str,
    title: str,
    old_rating: int,
    new_rating: int,
) -> Optional[models.SincerityTransaction]:
    """Call when a person changes a rating they'd already given a title
    (not the first rating ever — that's just logging, not revising).
    Skips the award if the numbers are actually identical, or if this
    same title already earned a revised_rating award inside the
    cool-down window.

    `title_key` should be a stable `f"{source}:{media_id}"` string, the
    same for every row that represents "this title" — NOT a
    WatchlistEntry or DiaryEntry primary key. This matters because a
    rating can be revised through two different doors that don't share
    a row id: re-logging through log_watched (which only has the
    WatchlistEntry row) and editing a past evening through diary.py's
    PATCH endpoint (which only has that one DiaryEntry row, and a movie
    can have several of those across rewatches — see DiaryEntry's class
    docstring). Keying on the title itself, rather than whichever row
    happened to be touched, is what makes the cool-down below actually
    stop "revise via one door, wait a second, revise again via the
    other door" from paying out twice for what is really one change of
    mind.

    The cool-down itself is checked against this module's own ledger
    (the most recent revised_rating SincerityTransaction for this
    title_key) rather than a "when was this last changed" column on the
    caller's model — neither DiaryEntry nor WatchlistEntry actually
    tracks "when the rating itself last changed" specifically (their
    timestamps also move on unrelated edits) — so the ledger is the
    only reliable clock, and every caller gets the same protection for
    free with nothing to remember to pass in.
    """
    if old_rating == new_rating:
        return None
    recent = (
        db.query(models.SincerityTransaction)
        .filter(
            models.SincerityTransaction.related_entry_id == title_key,
            models.SincerityTransaction.reason == models.SincerityReason.revised_rating,
        )
        .order_by(models.SincerityTransaction.created_at.desc())
        .first()
    )
    if recent is not None and datetime.now(timezone.utc) - recent.created_at < REVISED_RATING_COOLDOWN:
        return None
    direction = "up" if new_rating > old_rating else "down"
    return record_transaction(
        db, user,
        delta=REVISED_RATING_AWARD,
        reason=models.SincerityReason.revised_rating,
        note=f"{title} — changed {old_rating} to {new_rating} ({direction})",
        related_entry_id=title_key,
    )


def earn_honest_drop(
    db: Session,
    user: models.User,
    *,
    entry_id: str,
    title: str,
    reason_text: str,
) -> Optional[models.SincerityTransaction]:
    """Call when a WatchlistEntry is marked `dropped` *with* a non-empty
    reason attached (see the drop-flow's own reason field on the
    client). A drop with no reason earns nothing — the point is the
    honesty of saying why, not the act of giving up itself.
    """
    if not reason_text or not reason_text.strip():
        return None
    return record_transaction(
        db, user,
        delta=HONEST_DROP_AWARD,
        reason=models.SincerityReason.honest_drop,
        note=f"{title} — dropped: {reason_text.strip()}",
        related_entry_id=entry_id,
    )


def earn_second_chance(
    db: Session,
    user: models.User,
    *,
    entry_id: str,
    title: str,
    dropped_since: datetime,
    dropped_reason: Optional[str],
) -> Optional[models.SincerityTransaction]:
    """Call from routers/diary.py::log_watched when a WatchlistEntry that
    was `dropped` gets logged as `watched` for real — the honest mirror
    of earn_honest_drop above: dropping something with a real reason is
    one honest act, and coming back to actually finish it later, instead
    of quietly re-adding it and pretending the drop never happened, is
    another. Returns None if it hasn't been long enough since the drop
    to be a real change of heart rather than routine list housekeeping
    (see SECOND_CHANCE_MIN_AGE).
    """
    if datetime.now(timezone.utc) - dropped_since < SECOND_CHANCE_MIN_AGE:
        return None
    note = f"{title} — gave it another shot" + (f" (dropped it over \"{dropped_reason}\")" if dropped_reason else "")
    return record_transaction(
        db, user,
        delta=SECOND_CHANCE_AWARD,
        reason=models.SincerityReason.second_chance,
        note=note,
        related_entry_id=entry_id,
    )


def has_unlocked_reveal(db: Session, user_id: str, entry_id: str) -> bool:
    """Whether `user_id` has already paid spoiler_unlock to see
    `entry_id`'s rating early. Two callers, one question:
    app/routers/shared_diary.py's rating_hidden logic uses it to avoid
    charging the same reveal twice, and earn_formed_own_opinion_if_eligible
    below uses it to withhold that award from someone who peeked instead
    of forming their own opinion first. The ledger is the only place this
    is recorded — see spend_spoiler_unlock's related_entry_id — so this
    is a plain lookup, not a second source of truth to keep in sync.
    """
    return (
        db.query(models.SincerityTransaction)
        .filter(
            models.SincerityTransaction.user_id == user_id,
            models.SincerityTransaction.reason == models.SincerityReason.spoiler_unlock,
            models.SincerityTransaction.related_entry_id == entry_id,
        )
        .first()
        is not None
    )


def earn_formed_own_opinion(
    db: Session, user: models.User, *, entry_id: str, title: str
) -> models.SincerityTransaction:
    """Records the award once eligibility (see
    earn_formed_own_opinion_if_eligible) has already been decided.
    `entry_id` is the *circle-mate's* DiaryEntry id, not the caller's
    own — deliberately, so has_unlocked_reveal above can check "did this
    person pay to see that exact rating" using the same id on both
    sides of the trade.
    """
    return record_transaction(
        db, user,
        delta=OWN_OPINION_AWARD,
        reason=models.SincerityReason.formed_own_opinion,
        note=f"{title} — rated it your way, before peeking",
        related_entry_id=entry_id,
    )


def earn_formed_own_opinion_if_eligible(
    db: Session,
    user: models.User,
    *,
    link_id: str,
    source: str,
    media_id: str,
    title: str,
) -> Optional[models.SincerityTransaction]:
    """Call from routers/diary.py::log_watched on someone's *first-ever*
    rating of a title (prior_count == 0 — a rewatch or a plain rating
    revision is earn_revised_rating's territory, not this one), only
    when this exact log is going into a shared circle (`link_id` is
    that log's resolved_shared_link_id, never a link the person merely
    belongs to but chose not to share into this time — see this
    function's own call site for why that's the deliberate scope).

    Looks for the earliest already-shared, already-rated DiaryEntry for
    the same (source, media_id) from anyone else on that link. None
    found -> nobody to have peeked at, no award (this isn't a "first
    to watch it" bonus, just the honesty of not looking first when you
    could have). Found, but this person already paid to reveal that
    exact entry (has_unlocked_reveal) -> no award either, since the
    entire point is not having looked. Otherwise, they rated it
    independently — see earn_formed_own_opinion.
    """
    partner_entry = (
        db.query(models.DiaryEntry)
        .filter(
            models.DiaryEntry.shared_link_id == link_id,
            models.DiaryEntry.user_id != user.id,
            models.DiaryEntry.source == source,
            models.DiaryEntry.media_id == media_id,
            models.DiaryEntry.rating.isnot(None),
        )
        .order_by(models.DiaryEntry.created_at.asc())
        .first()
    )
    if partner_entry is None:
        return None
    if has_unlocked_reveal(db, user.id, partner_entry.id):
        return None
    return earn_formed_own_opinion(db, user, entry_id=partner_entry.id, title=title)


# ---------------------------------------------------------------------------
# Everyday activity — see this module's docstring and the tunables
# above. Each function fires exactly once for the event it represents;
# every call site is responsible for only calling it when that event
# has genuinely just happened (e.g. a title *just* reached `watched`,
# not merely "is watched") — none of these re-check history themselves
# the way e.g. earn_revised_rating's cool-down does, because the
# triggering fact itself (a status transition, a brand-new row) is
# already a one-time thing at the call site.
# ---------------------------------------------------------------------------


def earn_watched_logged(db: Session, user: models.User, *, entry_id: str, title: str) -> models.SincerityTransaction:
    """Call from routers/diary.py::log_watched the moment a title's
    WatchlistEntry first transitions to `watched` — never again for
    that same title (a rewatch is earn_rewatch_logged's territory, not
    this one)."""
    return record_transaction(
        db, user,
        delta=WATCHED_LOGGED_AWARD,
        reason=models.SincerityReason.watched_logged,
        note=f"{title} — watched",
        related_entry_id=entry_id,
    )


def earn_review_written(db: Session, user: models.User, *, entry_id: str, title: str) -> models.SincerityTransaction:
    """Call when a brand-new DiaryEntry is created with a non-empty note
    already attached. Deliberately only at creation, not on a later
    edit that merely adds a note to an existing row — see
    routers/diary.py::log_watched's own call site for why that's the
    one moment this can't be farmed by repeatedly editing one entry's
    note back and forth."""
    return record_transaction(
        db, user,
        delta=REVIEW_WRITTEN_AWARD,
        reason=models.SincerityReason.review_written,
        note=f"{title} — wrote a note",
        related_entry_id=entry_id,
    )


def earn_rewatch_logged(db: Session, user: models.User, *, entry_id: str, title: str) -> models.SincerityTransaction:
    """Call when a title already marked `watched` gets logged again —
    for a movie/whole-title, every fresh rewatch row; for a series (one
    persistent DiaryEntry row), only the moment is_rewatch first flips
    from false to true, never again after that on the same row."""
    return record_transaction(
        db, user,
        delta=REWATCH_LOGGED_AWARD,
        reason=models.SincerityReason.rewatch_logged,
        note=f"{title} — watched again",
        related_entry_id=entry_id,
    )


def earn_watched_together(db: Session, user: models.User, *, entry_id: str, title: str) -> models.SincerityTransaction:
    """Call alongside earn_watched_logged/earn_rewatch_logged (a bonus on
    top, never instead of) when this same log is also marked as watched
    together with a partner — for a series' single persistent row, only
    the moment that flag first flips true, same one-time rule as
    earn_rewatch_logged above."""
    return record_transaction(
        db, user,
        delta=TOGETHER_BONUS_AWARD,
        reason=models.SincerityReason.watched_together_bonus,
        note=f"{title} — watched together",
        related_entry_id=entry_id,
    )


def earn_genres_explored(db: Session, user: models.User, *, genres: list[str]) -> list[models.SincerityTransaction]:
    """Call with every genre on whatever was just logged. Awards each
    genre this account has never logged before — deduplicated against
    the ledger itself (every past genre_explored award's related_entry_id
    is `f"genre:{key}"`), not against a second stored set, same "ledger
    is the only reliable memory" shape has_unlocked_reveal uses for
    reveals. Harmless to call with genres already explored; those are
    silently skipped, so callers don't need to pre-filter."""
    keys = {g.strip().lower() for g in genres if g and g.strip()}
    if not keys:
        return []
    related_ids = {f"genre:{k}" for k in keys}
    already = {
        row.related_entry_id
        for row in db.query(models.SincerityTransaction.related_entry_id)
        .filter(
            models.SincerityTransaction.user_id == user.id,
            models.SincerityTransaction.reason == models.SincerityReason.genre_explored,
            models.SincerityTransaction.related_entry_id.in_(related_ids),
        )
        .all()
    }
    awarded = []
    for key in sorted(keys):
        related_id = f"genre:{key}"
        if related_id in already:
            continue
        awarded.append(record_transaction(
            db, user,
            delta=GENRE_EXPLORED_AWARD,
            reason=models.SincerityReason.genre_explored,
            note=f"first time logging {key}",
            related_entry_id=related_id,
        ))
    return awarded


def earn_streak_progress(db: Session, user: models.User, db_current_streak: int) -> Optional[models.SincerityTransaction]:
    """Call with this account's current streak length (see
    app/streaks.py::current_streak) right after logging something —
    awards the difference between that and
    User.streak_sincerity_award_days (this account's previous
    high-water mark), then raises the mark to match. A streak that
    breaks and restarts from day 1 simply earns nothing further until it
    passes the old mark again — it never claws points back for days
    already paid out."""
    new_days = max(db_current_streak, 0)
    if new_days <= user.streak_sincerity_award_days:
        return None
    delta_days = new_days - user.streak_sincerity_award_days
    user.streak_sincerity_award_days = new_days
    return record_transaction(
        db, user,
        delta=delta_days * STREAK_DAY_AWARD,
        reason=models.SincerityReason.streak_milestone,
        note=f"streak reached {new_days} day{'s' if new_days != 1 else ''}",
    )


def earn_friend_invited(db: Session, referrer: models.User, *, friend_name: str) -> models.SincerityTransaction:
    """Call once, right after a new account's referred_by_id is set to
    `referrer.id` — from either routers/auth.py::register (code entered
    at signup) or routers/friends.py::claim_invite (link tapped after
    the fact). Both call sites already guard against a double-set of
    referred_by_id itself, so there's nothing further to dedupe here."""
    return record_transaction(
        db, referrer,
        delta=FRIEND_INVITED_AWARD,
        reason=models.SincerityReason.friend_invited,
        note=f"{friend_name} joined using your invite",
    )


def earn_card_share(db: Session, user: models.User, *, card_key: str) -> models.SincerityTransaction:
    """Call from routers/card_shares.py once a share is confirmed
    countable — that router already enforces the once-per-card and
    per-day caps before ever calling this, so this function just records
    the ledger side, same division of labor as the honest-acts spend_*
    functions above."""
    return record_transaction(
        db, user,
        delta=CARD_SHARE_AWARD,
        reason=models.SincerityReason.card_shared,
        note="shared a card",
        related_entry_id=card_key,
    )


def earn_challenge_claimed(db: Session, user: models.User, *, challenge_id: str, title: str, points: int) -> models.SincerityTransaction:
    """Call from routers/challenges.py::claim_challenge once, right when
    a finished challenge's reward is collected — that router already
    checks the challenge is actually completed and not already claimed
    before calling this."""
    return record_transaction(
        db, user,
        delta=points,
        reason=models.SincerityReason.challenge_claimed,
        note=f"{title} — collected",
        related_entry_id=challenge_id,
    )


# ---------------------------------------------------------------------------
# Recommendation stakes (spend now, resolve later)
# ---------------------------------------------------------------------------


def spend_recommendation_stake(
    db: Session,
    staker: models.User,
    *,
    friend_id: str,
    friend_name: str,
    title: str,
    amount: int,
) -> models.SincerityTransaction:
    """Call when a person recommends a specific title to a specific
    friend with an explicit predicted rating attached, and chooses to
    stake `amount` points on it. Caller is responsible for clamping
    `amount` to [MIN_RECOMMENDATION_STAKE, MAX_RECOMMENDATION_STAKE] and
    for checking staker.sincerity_balance >= amount beforehand — going
    negative here is a caller bug, not a case this function guards
    against, same as other "caller validated already" helpers elsewhere
    in this codebase.
    """
    return record_transaction(
        db, staker,
        delta=-amount,
        reason=models.SincerityReason.recommendation_stake,
        note=f"staked on {friend_name} liking {title}",
        related_user_id=friend_id,
    )


def resolve_recommendation_stake(
    db: Session,
    staker: models.User,
    *,
    friend_id: str,
    friend_name: str,
    title: str,
    staked_amount: int,
    predicted_rating: int,
    actual_rating: int,
) -> models.SincerityTransaction:
    """Call once the friend actually logs their own rating for the
    staked title. A hit pays the stake back plus interest; a miss
    writes a zero-delta note-only row (see SincerityTransaction's own
    docstring for why that's the one allowed exception to "delta is
    never a no-op") so the history can say what happened, since the
    cost was already taken at stake time.
    """
    hit = abs(predicted_rating - actual_rating) <= RECOMMENDATION_TOLERANCE
    if hit:
        payout = staked_amount + round(staked_amount * ACCURATE_RECOMMENDATION_BONUS_RATE)
        return record_transaction(
            db, staker,
            delta=payout,
            reason=models.SincerityReason.accurate_recommendation,
            note=f"{friend_name} rated {title} {actual_rating} — you called {predicted_rating}",
            related_user_id=friend_id,
        )
    return record_transaction(
        db, staker,
        delta=0,
        reason=models.SincerityReason.stake_forfeited,
        note=f"{friend_name} rated {title} {actual_rating} — you called {predicted_rating}, stake lost",
        related_user_id=friend_id,
    )


def expire_recommendation_stake(
    db: Session, staker: models.User, *, friend_name: str, title: str, staked_amount: int
) -> models.SincerityTransaction:
    """Call once RECOMMENDATION_EXPIRY has passed on a still-pending
    Recommendation with no rating from the friend — see
    app/routers/recommendations.py's lazy expiry sweep, the same
    "recompute on read, no scheduler" shape apply_stale_planned_decay
    uses for its own passive charge. Unlike a miss, this isn't the
    staker's call turning out wrong — nobody's rated anything yet — so
    the full stake comes back rather than being forfeited.
    """
    return record_transaction(
        db, staker,
        delta=staked_amount,
        reason=models.SincerityReason.stake_expired,
        note=f"{friend_name} never got to {title} — stake returned",
        related_user_id=None,
    )


# ---------------------------------------------------------------------------
# Spending
# ---------------------------------------------------------------------------


def spend_spoiler_unlock(db: Session, user: models.User, *, title: str, entry_id: str) -> models.SincerityTransaction:
    """Caller (app/routers/shared_diary.py::reveal_rating) is responsible
    for checking user.sincerity_balance >= SPOILER_UNLOCK_COST and that
    this exact entry_id hasn't already been unlocked (has_unlocked_reveal)
    first. `entry_id` is the circle-mate's DiaryEntry id whose rating is
    being revealed — recorded as related_entry_id so has_unlocked_reveal
    can recognize this exact reveal later (both to avoid a double charge
    and to withhold earn_formed_own_opinion for this same entry).
    """
    return record_transaction(
        db, user,
        delta=-SPOILER_UNLOCK_COST,
        reason=models.SincerityReason.spoiler_unlock,
        note=f"revealed {title} early",
        related_entry_id=entry_id,
    )


def spend_debt_settlement(db: Session, user: models.User, *, entry_id: str, title: str) -> models.SincerityTransaction:
    """Pay the flat DEBT_SETTLEMENT_COST to permanently exempt one
    watch_later item from further stale_debt decay. Caller
    (app/routers/watchlist.py::settle_debt) is responsible for checking
    the entry has actually crossed STALE_DEBT_THRESHOLD (nothing to
    settle before then), that it isn't already debt_exempt, that the
    balance covers the cost, and for setting
    WatchlistEntry.debt_exempt = True in the same commit — this
    function only records the ledger side.
    """
    return record_transaction(
        db, user,
        delta=-DEBT_SETTLEMENT_COST,
        reason=models.SincerityReason.debt_settled,
        note=f"{title} — settled, no more debt on this one",
        related_entry_id=entry_id,
    )


def spend_pin_slot(db: Session, user: models.User) -> models.SincerityTransaction:
    """Pay PIN_SLOT_COST for one more permanent badge-showcase slot.
    Caller (routers/profile.py::buy_pin_slot) is responsible for
    checking user.bonus_pin_slots < MAX_BONUS_PIN_SLOTS and the balance
    covers it, and for incrementing bonus_pin_slots in the same commit —
    this function only records the ledger side, same division of labor
    as spend_debt_settlement above.
    """
    return record_transaction(
        db, user,
        delta=-PIN_SLOT_COST,
        reason=models.SincerityReason.pin_slot_purchased,
        note="bought one more badge-showcase slot",
    )


def has_nudged_recently(db: Session, user_id: str, related_entry_id: str) -> bool:
    """Whether `user_id` already spent a nudge on this exact
    CoViewEntry within NUDGE_COOLDOWN — same ledger-as-source-of-truth
    shape as has_unlocked_reveal above, just windowed by time instead of
    being a one-time flag, since a nudge (unlike a reveal) is fine to
    repeat once enough time has actually passed.
    """
    since = datetime.now(timezone.utc) - NUDGE_COOLDOWN
    return (
        db.query(models.SincerityTransaction)
        .filter(
            models.SincerityTransaction.user_id == user_id,
            models.SincerityTransaction.reason == models.SincerityReason.nudge_sent,
            models.SincerityTransaction.related_entry_id == related_entry_id,
            models.SincerityTransaction.created_at >= since,
        )
        .first()
        is not None
    )


def spend_nudge(db: Session, user: models.User, *, title: str, entry_id: str) -> models.SincerityTransaction:
    """Pay NUDGE_COST to send a circle-mate one push notification about a
    shared co-viewing plan that's gone stale (see
    routers/shared_diary.py::nudge and NUDGE_STALE_THRESHOLD). Caller is
    responsible for checking the entry is actually stale enough, that
    has_nudged_recently is False, and that the balance covers it — this
    function only records the ledger side and leaves the actual push
    (push.py::notify_nudge) to the caller, since sending it is a
    background_tasks concern this module has no access to.
    """
    return record_transaction(
        db, user,
        delta=-NUDGE_COST,
        reason=models.SincerityReason.nudge_sent,
        note=f"nudged about {title}",
        related_entry_id=entry_id,
    )


# ---------------------------------------------------------------------------
# Passive decay — meant to run from a periodic job, not a request path
# ---------------------------------------------------------------------------


def apply_stale_planned_decay(db: Session, user: models.User, *, entry_id: str, title: str, planned_since: datetime) -> Optional[models.SincerityTransaction]:
    """Charges at most one STALE_DEBT_AMOUNT per STALE_DEBT_PERIOD for a
    still-`watch_later` entry older than STALE_DEBT_THRESHOLD.

    No scheduler/cron infra exists anywhere in this backend (see
    routers/referrals.py's own module docstring) — periodic-feeling
    logic here recomputes lazily on read instead, the same shape as
    streaks and the AI-ask monthly reset. So rather than a job that
    ticks once per period, this is designed to be called on *every*
    read of this entry's owner's sincerity balance (see
    apply_stale_planned_decay_for_user, called from
    routers/sincerity.py::get_my_sincerity) and self-limits via its own
    ledger: it looks up the most recent stale_debt SincerityTransaction
    for this entry_id and only charges again once STALE_DEBT_PERIOD has
    passed since that charge (or since planned_since, if this entry has
    never been charged before) — the same "ledger as the only reliable
    clock" approach earn_revised_rating uses for its cool-down, for the
    same reason: nothing else tracks "last time this specific thing
    happened" on its own.
    """
    age = datetime.now(timezone.utc) - planned_since
    if age < STALE_DEBT_THRESHOLD:
        return None
    last_charge = (
        db.query(models.SincerityTransaction)
        .filter(
            models.SincerityTransaction.related_entry_id == entry_id,
            models.SincerityTransaction.reason == models.SincerityReason.stale_debt,
        )
        .order_by(models.SincerityTransaction.created_at.desc())
        .first()
    )
    since = last_charge.created_at if last_charge is not None else planned_since
    if datetime.now(timezone.utc) - since < STALE_DEBT_PERIOD:
        return None
    return record_transaction(
        db, user,
        delta=-STALE_DEBT_AMOUNT,
        reason=models.SincerityReason.stale_debt,
        note=f"{title} — still just sitting there ({age.days} days)",
        related_entry_id=entry_id,
    )


def apply_stale_planned_decay_for_user(db: Session, user: models.User) -> list[models.SincerityTransaction]:
    """Runs apply_stale_planned_decay over every one of this user's
    still-`watch_later` items — see that function's docstring for why
    this is meant to be called on read (from GET /sincerity/me) rather
    than from a job that doesn't exist in this backend. Cheap: this
    user's watch_later shelf is normally a few dozen rows at most, and
    each check is a single indexed lookup against the ledger.
    """
    planned = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == user.id,
            models.WatchlistEntry.status == models.WatchStatus.watch_later,
            # Paid off once via spend_debt_settlement — see
            # WatchlistEntry.debt_exempt's own docstring for why this
            # never flips back to False on its own.
            models.WatchlistEntry.debt_exempt.is_(False),
        )
        .all()
    )
    charged = []
    for entry in planned:
        txn = apply_stale_planned_decay(
            db, user,
            entry_id=entry.id,
            title=entry.title_en or entry.title_ru or "—",
            planned_since=entry.created_at,
        )
        if txn is not None:
            charged.append(txn)
    return charged
