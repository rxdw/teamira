"""Seeds a handful of real, hand-picked "подборки Teamira" shelves —
one each for anime, series, games, books, and manga — exercising the
new multi-catalog admin_add_item path end to end so there's something
real on the Collections tab immediately, not just an empty admin API.

Talks to the DB directly rather than over HTTP: no running server and
no TEAMIRA_ADMIN_KEY required, since whoever can run this already has
direct access to this codebase/database (require_teamira_admin's header
key exists to gate the *network* surface, not this). Each title is
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
from app.adapters.google_books import GoogleBooksAdapter
from app.adapters.shikimori import ShikimoriMangaAdapter
from app.adapters.tmdb import TmdbAdapter
from app.database import Base, SessionLocal, engine

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("seed_teamira_picks")

_tmdb = TmdbAdapter()
_games = IgdbAdapter()
_books = GoogleBooksAdapter()
_manga = ShikimoriMangaAdapter()

# (shelf title RU, shelf title EN, media_type, search queries — one item
# added per query, in this order, so the shelf reads top-to-bottom as a
# real list). A query is either a bare title, or a (title, year) pair
# when the title alone is ambiguous enough (a remake, a same-named
# indie) that picking the wrong TMDB hit is a real risk — see _find_hit.
#
# `title_en` is stored alongside `title` (see
# models.TeamiraCollection.title_en) so the shelf name itself follows the
# language toggle the same way franchise shelves already do (see
# app/curated_franchises.py) — the client's displayTitle just picks
# whichever of the two matches the current language, no client change
# needed since that field already existed and was simply always None for
# hand-picked shelves before this.
SHELVES: list[tuple[str, str, str, list]] = [
    ("аниме, с которых стоит начать", "Anime to start with", "anime", [
        "Fullmetal Alchemist: Brotherhood",
        "Attack on Titan",
        "Death Note",
        "Steins;Gate",
        "Cowboy Bebop",
        "Hunter x Hunter",
    ]),
    ("сериалы, которые затягивают с первой серии", "Shows that hook you from episode one", "series", [
        "Breaking Bad",
        "Chernobyl",
        "The Wire",
        "Fleabag",
        "Succession",
        "True Detective",
    ]),
    ("уютные игры на тихий вечер", "Cozy games for a quiet evening", "game", [
        "Stardew Valley",
        "Hades",
        "Disco Elysium",
        "Outer Wilds",
        "Journey",
        "Kentucky Route Zero",
    ]),
    ("книги, после которых иначе смотришь на мир", "Books that change how you see the world", "book", [
        "Nineteen Eighty-Four",
        "Brave New World",
        "Slaughterhouse-Five",
        "The Great Gatsby",
        "Norwegian Wood",
        "Crime and Punishment",
    ]),
    ("манга для старта", "Manga to start with", "manga", [
        "Berserk",
        "Vagabond",
        "One Piece",
        "Vinland Saga",
        "Monster",
        "20th Century Boys",
    ]),
    ("фильмы, которые стоит посмотреть хотя бы раз", "Movies worth watching at least once", "movie", [
        "Parasite",
        "The Godfather",
        "In the Mood for Love",
        "No Country for Old Men",
        "There Will Be Blood",
        "Whiplash",
    ]),
    ("аниме на тихие выходные", "Anime for a quiet weekend", "anime", [
        "Your Name",
        "Spirited Away",
        "Violet Evergarden",
        "Made in Abyss",
        "Mob Psycho 100",
        "A Silent Voice",
    ]),
    ("мини-сериалы на один присест", "Miniseries for one sitting", "series", [
        "Band of Brothers",
        "Sherlock",
        "Big Little Lies",
        "The Queen's Gambit",
        "Mare of Easttown",
        "Dark",
    ]),
    ("инди-игры с настоящей историей", "Indie games with a real story", "game", [
        "What Remains of Edith Finch",
        "Celeste",
        "Firewatch",
        "Return of the Obra Dinn",
        "Undertale",
        "Night in the Woods",
    ]),
    ("нон-фикшн, который читается как роман", "Nonfiction that reads like a novel", "book", [
        "Sapiens",
        "Educated",
        "Into the Wild",
        "The Immortal Life of Henrietta Lacks",
        "In Cold Blood",
        "Man's Search for Meaning",
    ]),
    ("манга для тех, кто уже втянулся", "Manga for the already hooked", "manga", [
        "Chainsaw Man",
        "Jujutsu Kaisen",
        "Tokyo Ghoul",
        "Fullmetal Alchemist",
        "Fruits Basket",
        "Bleach",
    ]),
    ("вечер пятницы", "Friday night", "movie", [
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
    ("погрустить", "For a good cry", "movie", [
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
    ("поплакать под аниме", "Anime to cry to", "anime", [
        "Grave of the Fireflies",
        "Clannad",
        "Your Lie in April",
        "I Want to Eat Your Pancreas",
        "Anohana: The Flower We Saw That Day",
        "Weathering with You",
    ]),
    ("уютный вечер под одеялом", "Cozy night under a blanket", "series", [
        "Gilmore Girls",
        "Schitt's Creek",
        "Parks and Recreation",
        "Ted Lasso",
        "Brooklyn Nine-Nine",
        "The Great British Bake Off",
    ]),
    ("страшно, но не оторваться", "Scary but you can't stop playing", "game", [
        "Resident Evil 4",
        "Silent Hill 2",
        "Amnesia: The Dark Descent",
        "Outlast",
        "Phasmophobia",
        "Little Nightmares",
    ]),
    ("книги для отпуска", "Books for vacation", "book", [
        "The Hitchhiker's Guide to the Galaxy",
        "Good Omens",
        "The Martian",
        "Ready Player One",
        "Project Hail Mary",
        "The Rosie Project",
    ]),
    ("взбодриться", "Something to cheer you up", "movie", [
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
    ("уютный вечер за фильмом", "A cozy movie night", "movie", [
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
    ("страшное на ночь", "Scary movies for the night", "movie", [
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
    ("свидание", "Date night", "movie", [
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
    ("мозговзрыв", "Mind-benders", "movie", [
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
    ("заряд адреналина", "Adrenaline rush", "movie", [
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
    ("детективы, которые держат в напряжении", "Detective thrillers", "movie", [
        ("Zodiac", 2007),
        ("Gone Girl", 2014),
        ("Prisoners", 2013),
        ("Se7en", 1995),
        ("Nightcrawler", 2014),
        ("The Girl with the Dragon Tattoo", 2011),
    ]),
    ("детективные сериалы", "Detective series", "series", [
        "Mindhunter",
        "Sharp Objects",
        "Broadchurch",
        "The Night Of",
        "Happy Valley",
        "Top of the Lake",
    ]),
    ("кооператив на двоих", "Couch co-op for two", "game", [
        "It Takes Two",
        "A Way Out",
        "Portal 2",
        "Overcooked",
        "Unravel Two",
        "Cuphead",
    ]),
    ("стратегии для вдумчивых вечеров", "Strategy games for thoughtful evenings", "game", [
        "Sid Meier's Civilization VI",
        "XCOM 2",
        "Into the Breach",
        "Slay the Spire",
        "Baldur's Gate 3",
        "Divinity: Original Sin 2",
    ]),
    ("классика мировой литературы", "World literature classics", "book", [
        "Anna Karenina",
        "War and Peace",
        "One Hundred Years of Solitude",
        "Don Quixote",
        "The Master and Margarita",
        "Moby-Dick",
    ]),
    ("научная фантастика, которая изменила жанр", "Sci-fi that changed the genre", "book", [
        "Dune",
        "Neuromancer",
        "The Left Hand of Darkness",
        "Foundation",
        "Snow Crash",
        "Hyperion",
    ]),
    ("антиутопии и киберпанк", "Dystopias and cyberpunk anime", "anime", [
        "Ghost in the Shell",
        "Psycho-Pass",
        "Akira",
        "Cyberpunk: Edgerunners",
        "Serial Experiments Lain",
        "Texhnolyze",
    ]),
    ("спортивная драма и мотивация", "Sports anime for motivation", "anime", [
        "Haikyuu!!",
        "Slam Dunk",
        "Ping Pong the Animation",
        "Kuroko's Basketball",
        "Yuri!!! on Ice",
        "Free!",
    ]),
    ("военные драмы", "War dramas", "movie", [
        "Saving Private Ryan",
        ("1917", 2019),
        "Dunkirk",
        "Full Metal Jacket",
        "Come and See",
        "Hacksaw Ridge",
    ]),
    ("семейный вечер", "Family movie night", "movie", [
        ("Paddington", 2014),
        "Coco",
        "Up",
        "Inside Out",
        "The Incredibles",
        "Zootopia",
    ]),
    ("классика сёнэна", "Classic shonen manga", "manga", [
        "Naruto",
        "Dragon Ball",
        "Hunter x Hunter",
        "My Hero Academia",
        "Demon Slayer",
        "Attack on Titan",
    ]),
    ("рабочие будни в необычном свете", "Workplace comedies (and one drama)", "series", [
        "The Office",
        "Superstore",
        "Abbott Elementary",
        "Severance",
        "WeCrashed",
        "Silicon Valley",
    ]),
    ("открытый мир, в котором хочется потеряться", "Open worlds to get lost in", "game", [
        "The Witcher 3: Wild Hunt",
        "Red Dead Redemption 2",
        "Elden Ring",
        "Horizon Zero Dawn",
        "Ghost of Tsushima",
        "The Legend of Zelda: Breath of the Wild",
    ]),
    ("детективы и триллеры (книги)", "Mystery & thriller books", "book", [
        "Gone Girl",
        "The Silent Patient",
        "And Then There Were None",
        "The Girl on the Train",
        "In the Woods",
        "The Da Vinci Code",
    ]),
    ("документалки, которые смотрятся как кино", "Documentaries that feel like movies", "movie", [
        "Free Solo",
        "Man on Wire",
        "The Act of Killing",
        "Won't You Be My Neighbor?",
        "Amy",
        "Icarus",
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


def _get_or_create_shelf(db, title: str, title_en: str) -> models.TeamiraCollection:
    row = db.query(models.TeamiraCollection).filter_by(title=title).first()
    if row is not None:
        # Re-running this script against a shelf that was created before
        # title_en existed (or whose English name changed here since)
        # should still pick that up, rather than only ever setting it at
        # creation time.
        if row.title_en != title_en:
            row.title_en = title_en
            db.commit()
            logger.info("updated shelf %r title_en -> %r", title, title_en)
        return row
    max_position = db.query(models.TeamiraCollection).count()
    row = models.TeamiraCollection(title=title, title_en=title_en, position=max_position)
    db.add(row)
    db.commit()
    db.refresh(row)
    logger.info("created shelf %r / %r", title, title_en)
    return row


async def _seed_shelf(db, title: str, title_en: str, media_type: str, queries: list) -> None:
    row = _get_or_create_shelf(db, title, title_en)
    existing = {(item.media_id, item.media_type) for item in row.items}
    next_position = len(row.items)

    # A fully-seeded shelf already carries at least one item per query —
    # skip it without a single catalog request. This is an approximation
    # (it can't tell "every query matched" from "some matched, some
    # legitimately don't exist on the catalog and never will"), but it's
    # the common case by far, and the cost of being wrong is just that a
    # shelf with a genuinely unmatched title keeps retrying that one
    # title's search on every startup forever — not a big deal, and far
    # cheaper than the alternative of re-resolving every title on every
    # shelf on every restart regardless of whether anything changed. See
    # _seed_teamira_shelves_background's docstring in app/main.py for the
    # rate-limit cost this is specifically here to avoid.
    if len(existing) >= len(queries):
        logger.info("  %-45s -> shelf already full (%d/%d), skipping catalog lookups", title, len(existing), len(queries))
        return

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


async def seed_all_shelves(db) -> None:
    """Runs the actual seeding of every shelf in SHELVES against an
    already-open session. This is the reusable half of what used to be
    only reachable via `python -m app.seed_teamira_picks` — app/main.py's
    own startup now calls this too (see on_startup), so the shelves show
    up automatically the first time the backend boots against a given
    database and nobody has to remember to run this script by hand.

    Assumes the `teamira_collection_items.source` and
    `teamira_collections.title_en` columns already exist — app/main.py's
    own _STARTUP_COLUMN_MIGRATIONS already guarantees that on every
    startup, so this doesn't repeat that DDL itself (see main() below,
    which still does for the standalone CLI path).
    """
    for title, title_en, media_type, queries in SHELVES:
        logger.info("\n%s / %s (%s)", title, title_en, media_type)
        await _seed_shelf(db, title, title_en, media_type, queries)
    _invalidate_teamira_cache(db)


async def main() -> None:
    # MVP-style: make sure the tables (and the newer `source` column —
    # see models.TeamiraCollectionItem) exist even against a completely
    # fresh database, the same way app/main.py's own startup does. Only
    # needed here for the standalone CLI path — app/main.py's own
    # startup already runs equivalent migrations before it calls
    # seed_all_shelves() directly.
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE teamira_collection_items ADD COLUMN IF NOT EXISTS source VARCHAR"))
        conn.execute(text("ALTER TABLE teamira_collections ADD COLUMN IF NOT EXISTS title_en VARCHAR"))

    db = SessionLocal()
    try:
        await seed_all_shelves(db)
    finally:
        db.close()

    logger.info("\ndone — open Collections -> Teamira picks to see them.")


if __name__ == "__main__":
    asyncio.run(main())
