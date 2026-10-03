"""Abuse-prevention rate limiting for a handful of user-facing endpoints
(register/login in routers/auth.py, the AI ask endpoint in
routers/ai.py, and the TMDB/IGDB/Google Books/Trakt-backed catalog
endpoints in routers/media.py, routers/reviews.py, routers/watch.py,
routers/image_proxy.py) — backed by Postgres (models.RateLimitHit)
instead of an in-process dict, so the limit means the same thing
regardless of how many uvicorn workers or how many replicas this
backend is running as.

The previous version kept a sliding window of raw hit timestamps per
key entirely in memory. That's gone for two reasons, not just one:
  - Per-process only. A multi-worker/multi-instance deployment got one
    independent limit *per process*, not one shared limit — someone
    could get roughly (limit x worker count) through before every
    worker had seen them. Harmless on a single-instance MVP deployment,
    a real leak the moment this runs behind a load balancer with
    several workers.
  - Resets on restart/deploy, and isn't visible to any other process —
    same "state that only the one process in memory knows about"
    problem as the old in-process asyncio.Lock in cache.py (see that
    module's `_advisory_lock` for the matching fix there).

Design trade-off worth being explicit about: this uses a *fixed*
window (bucketed by `int(now // window_seconds)`), not the previous
sliding one. A fixed window can let a caller through up to ~2x
`max_calls` if they cluster requests right around a window boundary
(a burst at the tail of one window, another burst at the head of the
next). That's an accepted trade for what a fixed window buys instead:
the whole check is one atomic `INSERT ... ON CONFLICT DO UPDATE ...
RETURNING count` — a single round trip, no read-modify-write race
between two processes incrementing the same key at the same instant,
and no sliding list of timestamps to prune. For abuse prevention
(not, say, billing-accurate metering) that's the right trade.

Deliberately NOT applied to the outbound-API throttles in
app/adapters/ (steam.py, igdb.py, open_library.py, shikimori.py) —
those exist to keep this backend under some third party's own rate
limit, not to cap what a caller can do to this backend. A modest,
harmless amount of per-process duplication there (this process and
its sibling worker each independently pacing their own outbound calls)
doesn't add up to a real problem the way it does for the endpoints
above, so those stay simple and in-memory."""

from __future__ import annotations

import ipaddress
import time
from contextlib import contextmanager
from functools import lru_cache
from typing import Optional

from fastapi import HTTPException, Request, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import settings


@contextmanager
def _session(db: Optional[Session]):
    """Same short-lived-session trick as app/cache.py's own `_session`
    (kept as its own copy rather than imported, so this module doesn't
    need to depend on cache.py for something this small): yields `db`
    unmanaged if given, or opens/closes a fresh session just for the one
    INSERT/DELETE below when the caller passes `db=None`. That matters
    for the handful of high-fanout read endpoints (search, reviews, ...)
    that deliberately don't take `Depends(get_db)` at all — see
    routers/media.py::search_media's own docstring for the pool-
    exhaustion incident that caused that — so rate-limiting them can't
    just assume a session is already sitting there."""
    if db is not None:
        yield db
        return
    from app.database import SessionLocal
    own_db = SessionLocal()
    try:
        yield own_db
    finally:
        own_db.close()


def _parse_trusted_networks(raw: str) -> tuple:
    networks = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            networks.append(ipaddress.ip_network(part, strict=False))
        except ValueError:
            continue
    return tuple(networks)


@lru_cache(maxsize=8)
def _trusted_networks(raw: str) -> tuple:
    """Cached by the raw setting *string* rather than reading
    `settings.trusted_proxy_ips` directly inside a no-arg cached
    function — this way a test (or a config reload) that changes the
    setting to a value this process hasn't seen before still gets a
    correct parse for it, rather than whatever was cached on the very
    first call regardless of what the setting says now."""
    return _parse_trusted_networks(raw)


def _is_trusted_proxy(ip_str: str) -> bool:
    networks = _trusted_networks(settings.trusted_proxy_ips)
    if not networks:
        return False
    try:
        addr = ipaddress.ip_address(ip_str)
    except ValueError:
        return False
    return any(addr in net for net in networks)


def client_key(request: Request) -> str:
    """Best-effort caller identity for IP-based rate limiting.

    With no trusted_proxy_ips configured (the default — see config.py),
    this is just the TCP peer address, and X-Forwarded-For is ignored
    entirely: an untrusted client could set that header to anything, so
    trusting it without knowing it actually came from a proxy in front
    of this app would let anyone bypass rate limiting just by sending a
    fresh value on every request.

    With trusted_proxy_ips configured, and the peer address is one of
    them, this instead walks X-Forwarded-For from the right: each hop
    prepends itself as it forwards a request on, so the rightmost
    entries are the ones a *trusted* proxy actually added, and the first
    entry (from the right) that isn't itself a trusted proxy is the real
    client — everything to its right is proxy noise, everything to its
    left (if the client sent its own X-Forwarded-For hoping to spoof
    this) is exactly as untrustworthy as the client itself and is
    correctly never reached."""
    peer = request.client.host if request.client else None
    if peer is None:
        return "unknown"
    if not _is_trusted_proxy(peer):
        return peer

    forwarded = request.headers.get("x-forwarded-for", "")
    hops = [h.strip() for h in forwarded.split(",") if h.strip()]
    for hop in reversed(hops):
        if not _is_trusted_proxy(hop):
            return hop
    # Every hop came from a trusted proxy (or there were none at all) —
    # fall back to the peer address rather than guessing at a client IP
    # this app has no actual evidence for.
    return peer


class RateLimiter:
    def __init__(self, name: str, max_calls: int, window_seconds: int):
        self.name = name
        self.max_calls = max_calls
        self.window_seconds = window_seconds

    def check(self, db: Optional[Session], key: str) -> None:
        """Raises 429 if `key` has already hit the limit within the
        current fixed window; otherwise records this call and lets it
        through. Call once per request, as early as possible. `db` is a
        real session when the caller already has one open for other
        reasons; pass `db=None` to have this open (and promptly close)
        a short-lived session of its own instead — see `_session` above."""
        with _session(db) as session:
            window_start = int(time.time() // self.window_seconds) * self.window_seconds
            # One atomic statement: Postgres serializes concurrent INSERT
            # ... ON CONFLICT DO UPDATE on the same primary key under a
            # row-level lock, so two workers hitting the same key in the
            # same window can't both read count=N and both write back N+1
            # the way a separate SELECT-then-UPDATE from Python could.
            # RETURNING hands back the post-increment count from that same
            # statement — no second query needed to find out where it landed.
            row = session.execute(
                text(
                    """
                    INSERT INTO rate_limit_hits (limiter, key, window_start, count)
                    VALUES (:limiter, :key, :window_start, 1)
                    ON CONFLICT (limiter, key, window_start)
                    DO UPDATE SET count = rate_limit_hits.count + 1
                    RETURNING count
                    """
                ),
                {"limiter": self.name, "key": key, "window_start": window_start},
            ).first()
            session.commit()
            count = row[0] if row is not None else 1

            # Opportunistic cleanup, not scheduled — same spirit as the old
            # in-memory version's _prune, just now a cheap DELETE against an
            # indexed primary key instead of a dict walk. Runs on roughly
            # 1 in 200 checks per limiter rather than every call, since this
            # is a DELETE against Postgres now, not a free in-memory scan.
            if count % 200 == 0:
                stale_before = window_start - self.window_seconds * 10
                session.execute(
                    text(
                        "DELETE FROM rate_limit_hits "
                        "WHERE limiter = :limiter AND window_start < :stale_before"
                    ),
                    {"limiter": self.name, "stale_before": stale_before},
                )
                session.commit()

        if count > self.max_calls:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests — try again in a bit",
            )


# One shared instance per protected route, not per-request — a fresh
# RateLimiter() on every call would have no memory of anything (and,
# now, would just point at the same shared `rate_limit_hits` rows
# regardless — but still only one instance is needed).
login_limiter = RateLimiter("login", max_calls=10, window_seconds=60)
register_limiter = RateLimiter("register", max_calls=5, window_seconds=60)

# --- User-enumeration and account-recovery limits --------------------------
#
# GET /friends/search was the single worst hole in this API: a
# `LIKE '%q%'` over every username, with `min_length=1` and no limit of
# any kind. Twenty-six requests — one per letter — returned essentially
# the whole user table, complete with ids, display names and avatars.
# The query shape is fixed in routers/friends.py (prefix match, minimum
# length, an opt-out), but the shape alone isn't enough: enumeration is a
# *volume* attack, so it also needs a ceiling. Keyed on user id rather
# than IP, since search is authenticated — an attacker would need a fresh
# account per bucket, and account creation has its own limiter above.
#
# 30/minute is far above what a person typing a name reaches (the client
# debounces) and far below what walking a namespace needs.
friend_search_limiter = RateLimiter("friend_search", max_calls=30, window_seconds=60)

# Password reset is the other enumeration surface: it takes an address
# and tells you something about whether it exists. The response is
# deliberately identical either way (see routers/auth.py), which closes
# the direct leak — this closes the timing-and-volume one, and stops the
# endpoint being used to mail-bomb someone else's inbox. Keyed on IP,
# since nobody is signed in when they use it.
password_reset_limiter = RateLimiter("password_reset", max_calls=5, window_seconds=3600)
email_verify_limiter = RateLimiter("email_verify", max_calls=5, window_seconds=3600)

# Refresh is called on a normal cadence by every signed-in device, so
# this is a runaway-client and stolen-token-grinding guard, not a usage
# limit. Keyed on IP: a legitimate phone refreshes roughly twice an hour.
refresh_limiter = RateLimiter("token_refresh", max_calls=60, window_seconds=3600)

# Reports are free to file and land in a queue a human reads, so the
# limit exists to stop the queue being flooded — the unique constraint on
# models.Report already stops the same person reporting the same thing
# twice, this stops them reporting fifty different things a minute.
report_limiter = RateLimiter("report_create", max_calls=20, window_seconds=3600)
# Generous — this exists to stop unauthenticated-style abuse of a
# now-authenticated endpoint (see routers/ai.py), not to enforce the
# app's actual "3 free asks a month" premium limit, which now lives on
# the server too (see routers/premium.py) rather than client-side only.
ai_ask_limiter = RateLimiter("ai_ask", max_calls=30, window_seconds=3600)

# --- Per-IP throttles for the TMDB/IGDB/Google Books/Trakt-backed catalog
# endpoints (routers/media.py, routers/reviews.py, routers/watch.py,
# routers/image_proxy.py) — see each router's own call site for why. These
# endpoints now also require a logged-in caller (app/deps.py's
# get_current_user_id / get_current_user), so this is a second, belt-and-
# suspenders layer: it caps how hard any single IP can hammer this app's
# own third-party quota, independent of how many accounts that IP is
# doing it through. Limits are generous on purpose — these back ordinary
# search-as-you-type and a title screen that can legitimately fire
# several of these in a row (detail + episodes + reviews + watch
# providers, each pulling in a handful of images) — this exists to stop a
# scraper/bot, not to get in a real user's way.
media_read_limiter = RateLimiter("media_read", max_calls=120, window_seconds=60)
reviews_limiter = RateLimiter("reviews", max_calls=60, window_seconds=60)
watch_providers_limiter = RateLimiter("watch_providers", max_calls=60, window_seconds=60)
# watch-out stays unauthenticated on purpose (see routers/watch.py's own
# docstring — it's opened in the device's bare browser, no token to carry
# there), so this is its only abuse guard.
watch_out_limiter = RateLimiter("watch_out", max_calls=30, window_seconds=60)
# Every poster/backdrop/photo on a screen is its own request here, so this
# ceiling is per-image, not per-screen — kept high accordingly. Signature
# + TTL verification (routers/image_proxy.py) is the primary gate; this is
# just a backstop against one IP hammering the endpoint (valid signature
# or not) hard enough to matter.
image_proxy_limiter = RateLimiter("image_proxy", max_calls=600, window_seconds=60)

# --- Product analytics ingestion (routers/analytics.py) ---------------------
#
# Unauthenticated on purpose — the onboarding and login screens have to be
# measurable too, and those are exactly the ones with no token yet — so
# this is the only abuse guard the endpoint has. Two keys, because neither
# alone is right:
#   - per install (`anon_id`): a well-behaved app flushes a batch every
#     15 s at most, so 20/minute is ~5x that; it stops one runaway client.
#   - per IP: generous (300/minute), because a mobile carrier's NAT can put
#     hundreds of real people behind one address. Its job is to stop
#     someone minting a fresh anon_id per request to get around the first.
analytics_anon_limiter = RateLimiter("analytics_anon", max_calls=20, window_seconds=60)
analytics_ip_limiter = RateLimiter("analytics_ip", max_calls=300, window_seconds=60)
