"""Folding the refreshed, per-request sources (Steam store, AniList passport,
Open Library author) into a title's `extras`.

Kept apart from app/routers/media.py and free of any I/O so every rule here is
a plain function you can unit-test with a couple of dicts. The routers fetch
(with timeouts and the shared cache rules) and call these; nothing here
touches the forever title-detail cache, so what gets merged is never stored
in it — a price merged on Monday is gone on Tuesday's refresh, as it should be.
"""

from typing import Optional

from app.adapters.anilist import AniListInfo
from app.adapters.open_library import OlBookInfo, _name_tokens
from app.adapters.steam_store import SteamStore
from app.schemas import (
    MediaItem, ReadingLog, SystemRequirements, TitleCreator, TitleExtras, TitleLink, TitleTag,
)

# IGDB gives plenty of screenshots for a big game and none for a small one;
# below this many, Steam's own are worth swapping in.
_MIN_IGDB_SCREENSHOTS = 3


def _ensure_extras(item: MediaItem) -> TitleExtras:
    if item.extras is None:
        item.extras = TitleExtras()
    return item.extras


def merge_steam_store(item: MediaItem, store: SteamStore) -> None:
    """Price, Metacritic, achievements, controller/cloud features, PC
    platforms, system requirements, Steam Deck verdict, and — only where IGDB
    had little or nothing — languages and screenshots."""
    ex = _ensure_extras(item)
    ex.price = store.price
    ex.price_discount_pct = store.price_discount_pct
    ex.free_to_play = store.free_to_play
    ex.metacritic = store.metacritic
    ex.achievements = store.achievements
    ex.steam_features = list(store.features)
    ex.pc_platforms = list(store.platforms)
    ex.steam_deck = store.deck
    if store.requirements_min or store.requirements_rec:
        ex.requirements = SystemRequirements(
            minimum=list(store.requirements_min), recommended=list(store.requirements_rec),
        )
    if len(ex.screenshots) < _MIN_IGDB_SCREENSHOTS and store.screenshots:
        ex.screenshots = list(store.screenshots)
    if not ex.languages and store.languages:
        ex.languages = list(store.languages)
    if store.appid and not any(l.kind == "steam" for l in ex.links):
        ex.links.insert(0, TitleLink(
            kind="steam", label="Steam", url=f"https://store.steampowered.com/app/{store.appid}",
        ))


def merge_anilist_info(item: MediaItem, info: AniListInfo) -> None:
    """AniList's passport onto a manga or anime card: weighted tags,
    source material, popularity, legal places to read, and — for manga,
    which has no backdrop of its own — the banner image."""
    ex = _ensure_extras(item)
    if info.banner and not item.backdrop_url and item.media_type == "manga":
        item.backdrop_url = info.banner
    # Tags: AniList's carry a community weight; keep any Shikimori ones that
    # AniList doesn't already have (anime themes) after them.
    have = {t.name.casefold() for t in info.tags}
    ex.tags = list(info.tags) + [t for t in ex.tags if t.name.casefold() not in have]
    ex.source_material = info.source or ex.source_material
    ex.favourites = info.favourites or ex.favourites
    if ex.popularity is None:
        ex.popularity = info.popularity
    ex.original_language = ex.original_language or info.language
    if info.links:
        have_urls = {l.url for l in ex.links}
        ex.links = ex.links + [l for l in info.links if l.url not in have_urls]


def merge_book_info(item: MediaItem, info: OlBookInfo) -> None:
    """Open Library's author biography and reader counts onto a book."""
    ex = _ensure_extras(item)
    if info.first_sentence:
        ex.first_sentence = info.first_sentence
    if any(v is not None for v in (info.want, info.reading, info.read)):
        ex.reading_log = ReadingLog(want=info.want, reading=info.reading, read=info.read)

    born: Optional[str] = info.born
    if born and info.died:
        born = f"{born} – {info.died}"
    if not (info.bio or info.photo_url or born):
        return
    wanted = _name_tokens(info.author_name or "")
    for creator in ex.creators:
        if wanted and len(wanted & _name_tokens(creator.name)) >= min(2, len(wanted)):
            creator.bio, creator.photo_url, creator.born = info.bio, info.photo_url, born
            return
    if info.author_name:
        ex.creators.insert(0, TitleCreator(
            name=info.author_name, role="Author", bio=info.bio, photo_url=info.photo_url, born=born,
        ))
