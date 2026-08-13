"""Wikipedia — the source for the "how this franchise was made" copy on
the Teamira picks "about this franchise" sheet (see
app/routers/teamira.py). TMDB's own /collection overview (see
app/adapters/tmdb.py::collection) is a short plot-flavoured blurb; it
doesn't cover production history, so this adapter fills that in from the
franchise's own Wikipedia article instead of anyone writing it by hand.

No API key needed — both endpoints used below are Wikipedia's free public
API. Content is CC BY-SA: whatever the client shows from `extract` must
carry an attribution + link back to the article (see
FranchiseInfoSheet on the client, which renders `history_url` for this).
"""

from typing import Optional
from urllib.parse import quote

import httpx

WIKI_OPENSEARCH = "https://{lang}.wikipedia.org/w/api.php"
WIKI_SUMMARY = "https://{lang}.wikipedia.org/api/rest_v1/page/summary/{title}"


class WikipediaAdapter:
    source_name = "wikipedia"

    async def _summary_for(self, lang: str, title: str) -> Optional[dict]:
        """Resolves `title` to the best-matching article in `lang`
        Wikipedia (via opensearch, since a franchise's display title in
        curated_franchises.py doesn't always exactly match the article
        title — e.g. disambiguation suffixes), then fetches its summary.
        Returns None if there's no match, the match is a disambiguation
        page, or the article has no extract text."""
        # follow_redirects=True is required here: Wikipedia's REST summary
        # endpoint replies with an HTTP 301/302 (not 200) whenever the
        # requested title isn't already in the article's exact normalized
        # form, or is itself a redirect page to the "real" title — both of
        # which are the common case, not the exception. httpx (unlike
        # requests) defaults to NOT following redirects, so without this
        # every single lookup here silently came back None regardless of
        # whether the article actually existed.
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
            search_resp = await client.get(
                WIKI_OPENSEARCH.format(lang=lang),
                params={
                    "action": "opensearch",
                    "search": title,
                    "limit": 1,
                    "namespace": 0,
                    "format": "json",
                },
            )
            if search_resp.status_code != 200:
                return None
            payload = search_resp.json()
            titles = payload[1] if len(payload) > 1 else []
            if not titles:
                return None
            matched_title = titles[0]

            summary_resp = await client.get(
                WIKI_SUMMARY.format(lang=lang, title=quote(matched_title, safe=""))
            )
            if summary_resp.status_code != 200:
                return None
            data = summary_resp.json()

        if data.get("type") == "disambiguation":
            return None
        extract = (data.get("extract") or "").strip()
        if not extract:
            return None
        page_url = (data.get("content_urls") or {}).get("desktop", {}).get("page")
        if not page_url:
            return None
        return {"extract": extract, "url": page_url}

    async def franchise_history(self, title: str, en_title: Optional[str] = None) -> Optional[dict]:
        """{"extract": str, "url": str} for the franchise's own Wikipedia
        article. Tries Russian first (curated_franchises.py titles are
        already Russian, e.g. "Звёздные войны"), then falls back to the
        English Wikipedia — but only if the caller passed `en_title`.

        Bug fixed: this used to retry the *same* Russian `title` string
        against English Wikipedia when the Russian lookup failed. A
        Cyrillic query almost never matches an English article title, so
        that fallback silently never found anything — for any franchise
        whose Russian Wikipedia article didn't exist under a title close
        enough for opensearch to resolve (e.g. "Тёмный рыцарь (трилогия
        Нолана)", which only has a disambiguation page on ru.wikipedia,
        while the real article lives at en.wikipedia's "The Dark Knight
        trilogy"). Callers now pass an explicit English title (see
        curated_franchises.py) when the Russian article doesn't cover it;
        without one, the English attempt is skipped rather than wasted on
        a query that can't succeed.

        Returns None if nothing usable was found — callers just omit the
        "how it was made" section for that shelf, same as any other
        optional field.
        """
        try:
            result = await self._summary_for("ru", title)
        except Exception:
            result = None
        if result:
            return result

        if en_title:
            try:
                result = await self._summary_for("en", en_title)
            except Exception:
                result = None
            if result:
                return result

        return None
