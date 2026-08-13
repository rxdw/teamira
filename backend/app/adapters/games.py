from typing import List

from app.schemas import MediaItem, ExternalIds, LocalizedText
from app.adapters.base import MediaAdapter

# A real deployment would add an IGDB or RAWG
# adapter here behind the same MediaAdapter interface.

_MOCK_GAMES = [
    {"id": "g-1", "title": "The Witcher 3: Wild Hunt",
     "desc": "A vast dark-fantasy open world where a monster hunter searches for his adopted daughter amid war and myth.",
     "year": 2015, "genres": ["RPG", "fantasy"], "rating": 9.3},
    {"id": "g-2", "title": "Elden Ring",
     "desc": "An open world from FromSoftware, built with George R. R. Martin — brutal, beautiful, unforgiving.",
     "year": 2022, "genres": ["RPG", "souls-like"], "rating": 9.5},
    {"id": "g-3", "title": "Disco Elysium",
     "desc": "A detective story without a single fight: a murder investigation and a fractured identity told through dialogue.",
     "year": 2019, "genres": ["RPG", "detective"], "rating": 9.2},
]


def _normalize(raw: dict) -> MediaItem:
    return MediaItem(
        id=raw["id"],
        media_type="game",
        external_ids=ExternalIds(tmdb=None, imdb=None),
        title=LocalizedText(ru=None, en=raw["title"]),
        description=LocalizedText(ru=None, en=raw["desc"]),
        poster_url=None,
        year=raw["year"],
        genres=raw["genres"],
        rating=raw["rating"],
        source="mock_games",
    )


class GamesAdapter(MediaAdapter):
    source_name = "mock_games"

    async def search(self, query: str) -> List[MediaItem]:
        q = query.strip().lower()
        items = [_normalize(r) for r in _MOCK_GAMES]
        if not q:
            return items
        return [it for it in items if q in (it.title.en or "").lower()]
