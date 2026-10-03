"""Seeds a handful of real, hand-picked "подборки Teamira" shelves —
one each for anime, series, games, books, and manga — exercising the
new multi-catalog admin_add_item path end to end so there's something
real on the Collections tab immediately, not just an empty admin API.

Talks to the DB directly rather than over HTTP: no running server and
no admin login required, since whoever can run this already has direct
access to this codebase/database (require_admin_user's User.is_admin
check exists to gate the *network* surface, not this). Each title is
resolved through the exact same adapters (TMDB/IGDB/Open Library) and
lands in the DB in the exact same shape admin_add_item itself would
produce — this is that endpoint's own logic, just called in a loop
instead of one title at a time over HTTP.

Requires the usual catalog API keys (TMDB_API_KEY, IGDB_*) already set
for the app to search normally — nothing extra needed for this script
specifically. A catalog that isn't configured just means that one
shelf's items get skipped (logged, not fatal) — the others still seed.

Safe to re-run: an existing shelf (matched by title) is reused rather
than duplicated, and a title already on a shelf is skipped rather than
added twice.

Usage:
    cd backend
    python -m app.seed_teamira_picks
"""
import asyncio
import logging

from sqlalchemy import text

from app import models
from app.adapters.igdb import IgdbAdapter
from app.adapters.open_library import OpenLibraryAdapter
from app.adapters.shikimori import ShikimoriMangaAdapter
from app.adapters.tmdb import TmdbAdapter
from app.database import Base, SessionLocal, engine

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("seed_teamira_picks")

_tmdb = TmdbAdapter()
_games = IgdbAdapter()
_books = OpenLibraryAdapter()
_manga = ShikimoriMangaAdapter()

# (shelf title, media_type, search queries — one item added per query,
# in this order, so the shelf reads top-to-bottom as a real list).
# A query is either a bare title, or a (title, year) pair when the
# title alone is ambiguous enough (a remake, a same-named indie) that
# picking the wrong TMDB hit is a real risk — see _find_hit.
SHELVES: list[tuple[str, str, list]] = [
    ("аниме, с которых стоит начать", "anime", [
        "Fullmetal Alchemist: Brotherhood",
        "Attack on Titan",
        "Death Note",
        "Steins;Gate",
        "Cowboy Bebop",
        "Hunter x Hunter",
    ]),
    ("сериалы, которые затягивают с первой серии", "series", [
        "Breaking Bad",
        "Chernobyl",
        "The Wire",
        "Fleabag",
        "Succession",
        "True Detective",
    ]),
    ("уютные игры на тихий вечер", "game", [
        "Stardew Valley",
        "Hades",
        "Disco Elysium",
        "Outer Wilds",
        "Journey",
        "Kentucky Route Zero",
    ]),
    ("книги, после которых иначе смотришь на мир", "book", [
        "Nineteen Eighty-Four",
        "Brave New World",
        "Slaughterhouse-Five",
        "The Great Gatsby",
        "Norwegian Wood",
        "Crime and Punishment",
    ]),
    ("манга для старта", "manga", [
        "Berserk",
        "Vagabond",
        "One Piece",
        "Vinland Saga",
        "Monster",
        "20th Century Boys",
    ]),
    ("фильмы, которые стоит посмотреть хотя бы раз", "movie", [
        "Parasite",
        "The Godfather",
        "In the Mood for Love",
        "No Country for Old Men",
        "There Will Be Blood",
        "Whiplash",
    ]),
    ("аниме на тихие выходные", "anime", [
        "Your Name",
        "Spirited Away",
        "Violet Evergarden",
        "Made in Abyss",
        "Mob Psycho 100",
        "A Silent Voice",
    ]),
    ("мини-сериалы на один присест", "series", [
        "Band of Brothers",
        "Sherlock",
        "Big Little Lies",
        "The Queen's Gambit",
        "Mare of Easttown",
        "Dark",
    ]),
    ("инди-игры с настоящей историей", "game", [
        "What Remains of Edith Finch",
        "Celeste",
        "Firewatch",
        "Return of the Obra Dinn",
        "Undertale",
        "Night in the Woods",
    ]),
    ("нон-фикшн, который читается как роман", "book", [
        "Sapiens",
        "Educated",
        "Into the Wild",
        "The Immortal Life of Henrietta Lacks",
        "In Cold Blood",
        "Man's Search for Meaning",
    ]),
    ("манга для тех, кто уже втянулся", "manga", [
        "Chainsaw Man",
        "Jujutsu Kaisen",
        "Tokyo Ghoul",
        "Fullmetal Alchemist",
        "Fruits Basket",
        "Bleach",
    ]),
    ("вечер пятницы", "movie", [
        "Game Night",
        "The Nice Guys",
        "Palm Springs",
        "Booksmart",
        "Superbad",
        "Knives Out",
        ("The Grand Budapest Hotel", 2014),
        ("21 Jump Street", 2012),
        ("Kingsman: The Secret Service", 2014),
        ("Free Guy", 2021),
        ("Scott Pilgrim vs. the World", 2010),
        ("Deadpool", 2016),
    ]),
    ("погрустить", "movie", [
        "Manchester by the Sea",
        "Blue Valentine",
        "Marriage Story",
        "Call Me by Your Name",
        "Her",
        "Eternal Sunshine of the Spotless Mind",
        ("Room", 2015),
        ("The Green Mile", 1999),
        ("Requiem for a Dream", 2000),
        ("The Fault in Our Stars", 2014),
        ("Never Let Me Go", 2010),
        ("My Sister's Keeper", 2009),
        ("Revolutionary Road", 2008),
    ]),
    ("поплакать под аниме", "anime", [
        "Grave of the Fireflies",
        "Clannad",
        "Your Lie in April",
        "I Want to Eat Your Pancreas",
        "Anohana: The Flower We Saw That Day",
        "Weathering with You",
    ]),
    ("уютный вечер под одеялом", "series", [
        "Gilmore Girls",
        "Schitt's Creek",
        "Parks and Recreation",
        "Ted Lasso",
        "Brooklyn Nine-Nine",
        "The Great British Bake Off",
    ]),
    ("страшно, но не оторваться", "game", [
        "Resident Evil 4",
        "Silent Hill 2",
        "Amnesia: The Dark Descent",
        "Outlast",
        "Phasmophobia",
        "Little Nightmares",
    ]),
    ("книги для отпуска", "book", [
        "The Hitchhiker's Guide to the Galaxy",
        "Good Omens",
        "The Martian",
        "Ready Player One",
        "Project Hail Mary",
        "The Rosie Project",
    ]),
    ("взбодриться", "movie", [
        ("La La Land", 2016),
        ("Sing Street", 2016),
        ("The Intouchables", 2011),
        ("Amélie", 2001),
        ("School of Rock", 2003),
        ("Little Miss Sunshine", 2006),
        ("Paddington 2", 2017),
        ("Chef", 2014),
        ("Pitch Perfect", 2012),
        ("Ratatouille", 2007),
    ]),
    ("уютный вечер за фильмом", "movie", [
        ("It's a Wonderful Life", 1946),
        ("The Holiday", 2006),
        ("Chocolat", 2000),
        ("Notting Hill", 1999),
        ("About Time", 2013),
        ("The Secret Life of Walter Mitty", 2013),
        ("Midnight in Paris", 2011),
        ("Little Women", 2019),
        ("Julie & Julia", 2009),
        ("You've Got Mail", 1998),
    ]),
    ("страшное на ночь", "movie", [
        ("Hereditary", 2018),
        ("The Conjuring", 2013),
        ("Get Out", 2017),
        ("A Quiet Place", 2018),
        ("It Follows", 2014),
        ("The Babadook", 2014),
        ("Sinister", 2012),
        ("Insidious", 2010),
        ("The Witch", 2015),
        ("Talk to Me", 2022),
    ]),
    ("свидание", "movie", [
        ("Before Sunrise", 1995),
        ("Pride & Prejudice", 2005),
        ("500 Days of Summer", 2009),
        ("Crazy Rich Asians", 2018),
        ("The Shape of Water", 2017),
        ("To All the Boys I've Loved Before", 2018),
        ("Silver Linings Playbook", 2012),
        ("A Star Is Born", 2018),
        ("Portrait of a Lady on Fire", 2019),
    ]),
    ("мозговзрыв", "movie", [
        ("Inception", 2010),
        ("The Prestige", 2006),
        ("Memento", 2000),
        ("Shutter Island", 2010),
        ("Arrival", 2016),
        ("Donnie Darko", 2001),
        ("The Matrix", 1999),
        ("Coherence", 2013),
        ("Predestination", 2014),
        ("Tenet", 2020),
    ]),
    ("заряд адреналина", "movie", [
        ("Mad Max: Fury Road", 2015),
        ("John Wick", 2014),
        ("Mission: Impossible - Fallout", 2018),
        ("The Raid", 2011),
        ("Baby Driver", 2017),
        ("Die Hard", 1988),
        ("Speed", 1994),
        ("Edge of Tomorrow", 2014),
        ("Extraction", 2020),
        ("Top Gun: Maverick", 2022),
    ]),
]


async def _find_hit(query, media_type: str):
    """One best-guess hit for `query` off whichever catalog `media_type`
    belongs to. `query` is either a bare title (first result of the
    right media_type wins — same "trust the catalog's own ranking"
    approach admin_search_catalogs leaves to whoever's picking a result
    by hand) or a (title, year) pair, for a common title that TMDB's
    search could easily return the wrong film for (a remake, a same-
    named indie) — picks the candidate whose year matches, falling back
    to the first hit of the right media_type if none do."""
    title, year = query if isinstance(query, tuple) else (query, None)
    try:
        if media_type in ("movie", "series", "anime"):
            items, _original_titles = await _tmdb.catalog_search(title)
            candidates = [item for item in items if item.media_type == media_type]
            if year is not None:
                for item in candidates:
                    if item.year == year:
                        return item
            return candidates[0] if candidates else None
        if media_type == "game":
            items = await _games.search(title)
            return items[0] if items else None
        if media_type == "book":
            items = await _books.search(title)
            return items[0] if items else None
        if media_type == "manga":
            items = await _manga.search(title)
            return items[0] if items else None
    except Exception:
        logger.exception("catalog search failed for %r (%s)", title, media_type)
    return None


def _get_or_create_shelf(db, title: str) -> models.TeamiraCollection:
    row = db.query(models.TeamiraCollection).filter_by(title=title).first()
    if row is not None:
        return row
    max_position = db.query(models.TeamiraCollection).count()
    row = models.TeamiraCollection(title=title, position=max_position)
    db.add(row)
    db.commit()
    db.refresh(row)
    logger.info("created shelf %r", title)
    return row


async def _seed_shelf(db, title: str, media_type: str, queries: list) -> None:
    row = _get_or_create_shelf(db, title)
    existing = {(item.media_id, item.media_type) for item in row.items}
    next_position = len(row.items)

    for query in queries:
        label = f"{query[0]} ({query[1]})" if isinstance(query, tuple) else query
        hit = await _find_hit(query, media_type)
        if hit is None:
            logger.warning("  %-45s -> no match on catalog, skipped", label)
            continue
        key = (hit.id, hit.media_type)
        if key in existing:
            logger.info("  %-45s -> already on the shelf", label)
            continue

        item = models.TeamiraCollectionItem(
            collection_id=row.id,
            media_id=hit.id,
            media_type=hit.media_type,
            source=hit.source,
            position=next_position,
        )
        db.add(item)
        try:
            db.commit()
        except Exception:
            db.rollback()
            logger.warning("  %-45s -> failed to save, skipped", label)
            continue
        existing.add(key)
        next_position += 1
        display_title = hit.title.en or hit.title.ru or label
        logger.info("  %-45s -> added: %s", label, display_title)


def _invalidate_teamira_cache(db) -> None:
    row = db.get(models.CachedFeedSnapshot, "feed:teamira:v7")
    if row is not None:
        db.delete(row)
        db.commit()


async def main() -> None:
    # MVP-style: make sure the tables (and the newer `source` column —
    # see models.TeamiraCollectionItem) exist even against a completely
    # fresh database, the same way app/main.py's own startup does.
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE teamira_collection_items ADD COLUMN IF NOT EXISTS source VARCHAR"))

    db = SessionLocal()
    try:
        for title, media_type, queries in SHELVES:
            logger.info("\n%s (%s)", title, media_type)
            await _seed_shelf(db, title, media_type, queries)
        _invalidate_teamira_cache(db)
    finally:
        db.close()

    logger.info("\ndone — open Collections -> Teamira picks to see them.")


if __name__ == "__main__":
    asyncio.run(main())
