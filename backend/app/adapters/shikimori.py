"""
Shikimori (shikimori.one) — a Russian anime/manga cataloguing site whose
own database is written in Russian first, not translated from English —
so unlike TMDB (see app/adapters/tmdb.py), a Russian title/description here
isn't a *translation* of anything, it's the source text the Shikimori
community itself wrote for the title. That's the whole reason this
adapter exists as a second, anime-only translation source: TMDB rides
anime under its own "tv" segment and TMDB's ru-RU coverage there is
patchy (most anime on TMDB simply has no Russian translation at all,
because TMDB's translator community skews Western-film/TV), whereas
Shikimori's russian/description fields exist for almost every anime in
its catalog, including obscure ones. So for media_type == "anime",
title_ru/overview_ru/poster_url_ru are taken from here instead of from
TmdbAdapter.full_detail (see app/routers/media.py::
_merge_anime_ru_from_shikimori) — cast/director/trailers stay TMDB's,
Shikimori's own people/video data is far thinner and not worth a second
source for.

No API key: Shikimori's read-only `/api/animes` (search + show) endpoints
are unauthenticated — OAuth is only needed for write actions (rating,
list-editing, etc.) this app never does. The one thing their docs do ask
of every client is a descriptive User-Agent identifying the app (see
SHIKIMORI_USER_AGENT below) — Shikimori is a much smaller, community-run
service than TMDB and blocks anonymous/default-looking user agents outright.

Matching is the fundamentally different — and fundamentally lossier —
part of this adapter compared to TMDB's. TMDB is looked up by an exact
id the item already carries (result.item.external_ids.tmdb); nothing
here plays that role for Shikimori, so every lookup is a best-effort
title(+year) search against Shikimori's own catalog rather than an id
fetch. That means occasional wrong or missing matches are expected
(common titles, same-named remakes, sequels sharing a franchise name),
not a bug to chase — see anime_supplement()'s docstring for exactly how
candidates are scored and how bad matches are screened out.
"""

import re
from typing import List, Optional

import httpx

SHIKIMORI_BASE = "https://shikimori.one/api"

# Shikimori's own ToS asks every API client to identify itself in the
# User-Agent (they rate-limit/block generic ones) — this app's own name is
# enough, no registration/key required for these read-only endpoints.
SHIKIMORI_USER_AGENT = "Seenly (+https://github.com/seenly)"

SHIKIMORI_ATTRIBUTION = "Русские описания предоставлены Shikimori"

# How many search hits we look at before giving up on a title — Shikimori's
# own relevance ranking almost always puts the right title in the first
# handful of hits; anything past this is more likely a same-named
# franchise entry than the one we're actually after.
_SEARCH_CANDIDATES = 5

# BBCode-ish markup Shikimori descriptions carry (its editor's own dialect,
# not real BBCode) — stripped down to plain text since this app has no rich
# text renderer for it. `[character=1234]Name[/character]` links a mention
# to a character page; everything else (`[i]`, `[b]`, `[spoiler]`, etc.)
# is plain emphasis/formatting with no equivalent worth preserving here.
_CHARACTER_TAG_RE = re.compile(r"\[character=\d+\](.*?)\[/character\]", re.DOTALL)
_BBCODE_TAG_RE = re.compile(r"\[/?[a-zA-Z_]+(?:=[^\]]*)?\]")


def _clean_description(raw: Optional[str]) -> Optional[str]:
    """Strips Shikimori's editor markup out of a raw `description` field
    down to plain text. Returns None for an empty/whitespace-only result —
    some Shikimori entries carry a description that's nothing but markup
    (rare, but seen on very obscure titles), and an empty string should
    degrade exactly like "no description" everywhere else in this app,
    not render as a blank paragraph."""
    if not raw:
        return None
    text = _CHARACTER_TAG_RE.sub(r"\1", raw)
    text = _BBCODE_TAG_RE.sub("", text)
    text = text.replace("\r\n", "\n").strip()
    return text or None


class ShikimoriAdapter:
    source_name = "shikimori"

    async def _search(self, client: httpx.AsyncClient, query: str) -> List[dict]:
        resp = await client.get(
            f"{SHIKIMORI_BASE}/animes",
            params={"search": query, "limit": _SEARCH_CANDIDATES},
        )
        resp.raise_for_status()
        return resp.json() or []

    @staticmethod
    def _year_of(entry: dict) -> Optional[int]:
        date_str = entry.get("aired_on") or entry.get("released_on")
        return int(date_str[:4]) if date_str and len(date_str) >= 4 and date_str[:4].isdigit() else None

    @classmethod
    def _pick_best_match(cls, candidates: List[dict], title: str, year: Optional[int]) -> Optional[dict]:
        """Scores Shikimori's search hits against the title we're actually
        trying to translate and returns the best one, or None when nothing
        looks like a real match — a wrong Shikimori entry attached to the
        wrong anime (e.g. matching a same-named spin-off or remake) would
        be worse than just falling back to TMDB/English, so this errs
        toward returning nothing over guessing.

        Scored on two independent signals:
        - name match: Shikimori's own `name` (romaji/English) or `russian`
          equals our title case-insensitively -> strong signal, since a
          title match is usually enough on its own for anime (far less
          ambiguous than movies/TV, where "search" is a common word).
        - year match: our `year` (when we have one) equals the year parsed
          out of Shikimori's `aired_on`/`released_on` -> tie-breaker between
          same-named entries (a franchise reusing its own title across
          seasons/remakes is the main case this guards against).

        A candidate needs the name match at minimum; year is only used to
        choose between multiple name-matching candidates, never to accept
        a title match on its own (Shikimori doesn't reliably have a year
        for every entry, and a bare year match with no title agreement is
        too weak to trust)."""
        norm_title = title.strip().casefold()
        name_matches = [
            c for c in candidates
            if norm_title in {
                (c.get("name") or "").strip().casefold(),
                (c.get("russian") or "").strip().casefold(),
            }
        ]
        if not name_matches:
            return None
        if year:
            for c in name_matches:
                if cls._year_of(c) == year:
                    return c
        return name_matches[0]

    async def anime_supplement(self, title: str, year: Optional[int] = None) -> Optional[dict]:
        """Looks up `title` (the item's own English/original anime title —
        callers pass result.item.title.en, not anything Shikimori-specific)
        on Shikimori and returns its Russian title/description/poster, or
        None when nothing on Shikimori looks like a confident match for
        it. `year` narrows down same-named franchise entries when we have
        one (see _pick_best_match above); passing None just means ties are
        broken by whichever candidate Shikimori's own search ranked first.

        Two requests: the search hit only carries a truncated/no
        description, so a second GET /animes/{id} fetches the full one.
        `poster.originalUrl` (Shikimori's largest size) is used over
        `poster.mainUrl`/`main2xUrl` — this app's poster tiles want the
        same "biggest available, let the client downscale" treatment as
        TMDB's w500 poster_url elsewhere.

        Returns None outright on any request failure or an empty search —
        this is a best-effort overlay, and a Shikimori hiccup should
        degrade to "just keep TMDB's/English text" exactly like every
        other optional TMDB call in this app degrades on its own failures."""
        if not title.strip():
            return None
        async with httpx.AsyncClient(
            timeout=8.0, headers={"User-Agent": SHIKIMORI_USER_AGENT}
        ) as client:
            try:
                candidates = await self._search(client, title)
            except httpx.HTTPError:
                return None
            match = self._pick_best_match(candidates, title, year)
            if not match or not match.get("id"):
                return None
            try:
                resp = await client.get(f"{SHIKIMORI_BASE}/animes/{match['id']}")
                if resp.status_code == 404:
                    return None
                resp.raise_for_status()
            except httpx.HTTPError:
                return None
        detail = resp.json()

        title_ru = (detail.get("russian") or "").strip() or None
        overview_ru = _clean_description(detail.get("description"))
        poster = detail.get("image") or {}
        poster_url = poster.get("original") or poster.get("preview") or None
        if poster_url and poster_url.startswith("/"):
            poster_url = f"https://shikimori.one{poster_url}"

        if not title_ru and not overview_ru and not poster_url:
            return None

        return {
            "title_ru": title_ru,
            "overview_ru": overview_ru,
            "poster_ru": poster_url,
        }
