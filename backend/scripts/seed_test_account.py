#!/usr/bin/env python3
"""
Seed a test Seenly account with a realistic diary history — enough spread
across this month/this year to make Wrapped and /profile/stats look full,
plus a handful of entries pinned to *exactly* 1, 2, 3, 6 months and 1, 2
years ago (today's date) so the Home screen's "on this day" cards have
something to show the moment you open the app.

Talks to the real running API (no direct DB access), so it exercises the
exact same endpoints the app itself uses — POST /auth/register,
POST /diary, POST /profile/favorites/pick.

Usage:
    pip install requests
    python3 seed_test_account.py
    python3 seed_test_account.py --base-url http://localhost:8000 --username demo1 --password demo1234
    python3 seed_test_account.py --username demo1 --password demo1234 --reset

--reset drops nothing server-side (there's no delete-account endpoint) —
it just logs into an existing account instead of trying to register a new
one, so you can re-run the script against the same test user to top it
up with a fresh batch of entries.
"""
from __future__ import annotations

import argparse
import calendar
import random
import sys
from datetime import date, datetime, time, timedelta

try:
    import requests
except ImportError:
    print("This script needs the 'requests' package: pip install requests")
    sys.exit(1)


# ---------------------------------------------------------------------------
# A small made-up catalog. Titles are real, well-known films/shows/games/
# books so the demo actually looks like something — but the ids and images
# are fake (picsum.photos, seeded per title so they're stable across runs),
# so this never touches TMDB/IGDB/Open Library or needs any API key.
# ---------------------------------------------------------------------------

def _poster(seed: str) -> str:
    return f"https://picsum.photos/seed/{seed}-poster/500/750"


def _backdrop(seed: str) -> str:
    return f"https://picsum.photos/seed/{seed}-backdrop/1280/720"


CATALOG = [
    # (title, media_type, source, genres, runtime_minutes)
    ("Interstellar", "movie", "tmdb", ["Sci-Fi", "Drama", "Adventure"], 169),
    ("Parasite", "movie", "tmdb", ["Thriller", "Drama"], 132),
    ("The Grand Budapest Hotel", "movie", "tmdb", ["Comedy", "Drama"], 99),
    ("Everything Everywhere All at Once", "movie", "tmdb", ["Sci-Fi", "Comedy", "Action"], 140),
    ("Dune", "movie", "tmdb", ["Sci-Fi", "Adventure"], 155),
    ("Amélie", "movie", "tmdb", ["Romance", "Comedy"], 122),
    ("Whiplash", "movie", "tmdb", ["Drama", "Music"], 106),
    ("The Grand Voyage", "movie", "tmdb", ["Adventure", "Drama"], 128),
    ("Coraline", "movie", "tmdb", ["Fantasy", "Family"], 100),
    ("Blade Runner 2049", "movie", "tmdb", ["Sci-Fi", "Thriller"], 164),
    ("La La Land", "movie", "tmdb", ["Romance", "Music"], 128),
    ("Knives Out", "movie", "tmdb", ["Mystery", "Comedy"], 130),
    ("The Bear", "series", "tmdb", ["Drama", "Comedy"], 30),
    ("Breaking Bad", "series", "tmdb", ["Drama", "Crime"], 47),
    ("Fleabag", "series", "tmdb", ["Comedy", "Drama"], 26),
    ("Severance", "series", "tmdb", ["Sci-Fi", "Thriller"], 55),
    ("Spirited Away", "anime", "tmdb", ["Fantasy", "Adventure", "Anime"], 125),
    ("Your Name", "anime", "tmdb", ["Romance", "Fantasy", "Anime"], 106),
    ("Attack on Titan", "anime", "tmdb", ["Action", "Anime", "Drama"], 24),
    ("Hades", "game", "igdb", ["Roguelike", "Action"], None),
    ("Elden Ring", "game", "igdb", ["RPG", "Action"], None),
    ("Stardew Valley", "game", "igdb", ["Simulation", "Indie"], None),
    ("Project Hail Mary", "book", "open_library", ["Sci-Fi"], None),
    ("Piranesi", "book", "open_library", ["Fantasy"], None),
]

MOOD_TAGS = [
    "cozy night in", "background noise", "full attention", "watched with snacks",
    "couldn't stop crying", "laughed way too hard", "rainy day pick", "late night watch",
]

NOTES = [
    "exactly what I needed tonight", "better on a rewatch", "gorgeous soundtrack",
    "no notes, just perfect", "took a while to get into it but worth it",
    None, None, None,  # bias toward "no note" — most real logs don't have one
]


def months_ago(d: date, n: int) -> date:
    """Same calendar day n months back, clamped to the target month's last
    day if it doesn't have one (e.g. the 31st, one month before a 30-day
    month) — mirrors exactly what the app's own "on this day" matching
    does, so an offset that lands on a short month just quietly won't
    produce a match, same as it wouldn't in real, organically-logged data.
    """
    month = d.month - n
    year = d.year
    while month <= 0:
        month += 12
        year -= 1
    day = min(d.day, calendar.monthrange(year, month)[1])
    return date(year, month, day)


def rand_time() -> time:
    hour = random.choice([13, 15, 18, 19, 20, 21, 22, 23])
    return time(hour, random.choice([0, 10, 15, 20, 30, 45]))


def as_watched_at(d: date) -> str:
    return datetime.combine(d, rand_time()).isoformat()


class SeenlyClient:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.token: str | None = None

    def _headers(self) -> dict:
        return {"Authorization": f"Bearer {self.token}"} if self.token else {}

    def register(self, username: str, password: str) -> bool:
        r = self.session.post(
            f"{self.base_url}/auth/register",
            json={"username": username, "password": password},
        )
        if r.status_code == 201:
            self.token = r.json()["access_token"]
            return True
        return False

    def login(self, username: str, password: str) -> None:
        r = self.session.post(
            f"{self.base_url}/auth/login",
            json={"username": username, "password": password},
        )
        r.raise_for_status()
        self.token = r.json()["access_token"]

    def log_entry(self, item: dict, watched_at: str, rating: int | None,
                  note: str | None, mood_tags: list[str], is_favorite: bool) -> dict:
        r = self.session.post(
            f"{self.base_url}/diary",
            headers=self._headers(),
            json={
                "item": item,
                "rating": rating,
                "note": note,
                "mood_tags": mood_tags or None,
                "watched_at": watched_at,
                "is_favorite": is_favorite,
            },
        )
        r.raise_for_status()
        return r.json()

    def set_top_favorites(self, picks: list[dict]) -> None:
        r = self.session.post(
            f"{self.base_url}/profile/favorites/pick",
            headers=self._headers(),
            json={"picks": picks},
        )
        r.raise_for_status()

    def get_stats(self) -> dict:
        r = self.session.get(f"{self.base_url}/profile/stats", headers=self._headers())
        r.raise_for_status()
        return r.json()

    def get_wrapped(self, period: str) -> dict:
        r = self.session.get(
            f"{self.base_url}/profile/wrapped", headers=self._headers(), params={"period": period}
        )
        r.raise_for_status()
        return r.json()


def make_item(idx: int, title: str, media_type: str, source: str, genres: list[str],
              runtime_minutes: int | None) -> dict:
    seed = f"seenly-seed-{idx}-{title.lower().replace(' ', '-')}"
    return {
        "id": seed,
        "media_type": media_type,
        "external_ids": {"tmdb": seed if source == "tmdb" else None},
        "title": {"en": title, "ru": None},
        "description": {"en": f"Seed data for {title}.", "ru": None},
        "poster_url": _poster(seed),
        "backdrop_url": _backdrop(seed),
        "year": random.randint(2015, 2024),
        "genres": genres,
        "rating": round(random.uniform(6.5, 9.2), 1),
        "source": source,
        "runtime_minutes": runtime_minutes,
    }


def build_plan(today: date) -> list[tuple[dict, date, bool]]:
    """Returns (item, watched_date, force_favorite) tuples: the exact
    on-this-day anchors first, then a wider spread across this month/
    this year/the last couple of years for Wrapped and the diary itself
    to have real depth."""
    items = [make_item(i, *row) for i, row in enumerate(CATALOG)]
    plan: list[tuple[dict, date, bool]] = []

    # --- "on this day" anchors — exact months-ago offsets from today ---
    on_this_day_offsets = [1, 2, 3, 4, 6, 9, 12, 18, 24]
    anchor_items = random.sample(items, k=min(len(on_this_day_offsets), len(items)))
    for item, offset in zip(anchor_items, on_this_day_offsets):
        d = months_ago(today, offset)
        if d.day != today.day:
            continue  # short month clamped it away — same as the app's own rule
        plan.append((item, d, offset in (1, 12)))  # favorite the 1-month and 1-year ones

    # --- this month, several entries, so the "month" Wrapped has body ---
    for _ in range(7):
        d = today.replace(day=random.randint(1, today.day))
        plan.append((random.choice(items), d, False))

    # --- earlier this year, one to a few per month, for the "year" Wrapped ---
    for month in range(1, today.month):
        for _ in range(random.randint(2, 4)):
            last_day = calendar.monthrange(today.year, month)[1]
            d = date(today.year, month, random.randint(1, last_day))
            plan.append((random.choice(items), d, False))

    # --- last year and the year before, scattered, for general diary depth ---
    for year_offset in (1, 2):
        for _ in range(10):
            month = random.randint(1, 12)
            last_day = calendar.monthrange(today.year - year_offset, month)[1]
            d = date(today.year - year_offset, month, random.randint(1, last_day))
            plan.append((random.choice(items), d, False))

    return plan


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", default="http://localhost:8000")
    parser.add_argument("--username", default=f"demo{random.randint(1000, 9999)}")
    parser.add_argument("--password", default="demopass123")
    parser.add_argument("--reset", action="store_true", help="log into an existing account instead of registering")
    args = parser.parse_args()

    client = SeenlyClient(args.base_url)

    if args.reset:
        client.login(args.username, args.password)
        print(f"Logged into existing account '{args.username}'.")
    else:
        if not client.register(args.username, args.password):
            print(f"Couldn't register '{args.username}' (already taken?) — trying to log in instead.")
            client.login(args.username, args.password)
        print(f"Account ready: '{args.username}' / '{args.password}'")

    today = date.today()
    plan = build_plan(today)
    random.shuffle(plan[9:])  # keep the on-this-day anchors first for the log below, shuffle the rest

    logged = 0
    failed = 0
    favorited_movies: list[dict] = []
    on_this_day_log: list[str] = []

    for i, (item, watched_date, force_favorite) in enumerate(plan):
        rating = random.randint(6, 10) if random.random() < 0.85 else None
        note = random.choice(NOTES)
        tags = random.sample(MOOD_TAGS, k=random.choice([0, 0, 1, 2]))
        is_favorite = force_favorite or (item["media_type"] == "movie" and random.random() < 0.12)

        try:
            client.log_entry(
                item=item,
                watched_at=as_watched_at(watched_date),
                rating=rating,
                note=note,
                mood_tags=tags,
                is_favorite=is_favorite,
            )
            logged += 1
            if is_favorite and item["media_type"] == "movie" and len(favorited_movies) < 5:
                favorited_movies.append(item)
            if i < 9:
                months = (today.year - watched_date.year) * 12 + (today.month - watched_date.month)
                label = f"{months} months ago" if months % 12 else (
                    "a year ago" if months == 12 else f"{months // 12} years ago"
                )
                on_this_day_log.append(f"  - {item['title']['en']} — logged {watched_date.isoformat()} ({label})")
        except requests.HTTPError as e:
            failed += 1
            print(f"  ! failed to log '{item['title']['en']}' on {watched_date}: {e}")

    if favorited_movies:
        try:
            client.set_top_favorites([
                {"media_id": m["id"], "source": m["source"]} for m in favorited_movies
            ])
        except requests.HTTPError as e:
            print(f"  ! couldn't set the profile stories banner: {e}")

    print()
    print(f"Logged {logged} evenings ({failed} failed) for '{args.username}'.")
    if on_this_day_log:
        print()
        print("These should show up under Home → \"on this day\" right now:")
        print("\n".join(on_this_day_log))
    print()
    try:
        stats = client.get_stats()
        year_wrapped = client.get_wrapped("year")
        print(f"/profile/stats: {stats}")
        print(f"/profile/wrapped?period=year: movies={year_wrapped['breakdown']['movies']}, "
              f"series={year_wrapped['breakdown']['series']}, anime={year_wrapped['breakdown']['anime']}, "
              f"games={year_wrapped['breakdown']['games']}, books={year_wrapped['breakdown']['books']}")
    except Exception as e:  # best-effort sanity check only
        print(f"(couldn't fetch a sanity-check summary: {e})")

    print()
    print(f"Log in with: username='{args.username}'  password='{args.password}'")


if __name__ == "__main__":
    main()
