#!/usr/bin/env python3
"""New-episode/new-release push — the one push in this app driven by an
outside catalog's own clock (a season airing weekly, a game shipping on
its release date) rather than something a person did *in* the app, so
like send_scheduled_push.py's own two triggers, this runs on a plain
cron schedule rather than as a BackgroundTasks call:

    0 * * * *  cd /app && python scripts/send_new_episode_push.py

Every user with a "watching"-status series/anime entry
(models.WatchStatus.watching) gets checked against TMDB's own
next_episode_to_air/last_episode_to_air (via TmdbAdapter.next_episode) —
the same "TMDB owns every episode date in this app, Shikimori is never
consulted here" reasoning app/routers/calendar.py's own module docstring
explains (a watching-list title's media_id is always a real tmdb id).
Every user with a game tracked on watch_later/watching gets checked
against IGDB's first_release_date the same way
app/routers/calendar.py::_game_release_date does — and shares its cache,
via a direct import of that function rather than a second copy of the
same lookup.

Each *title* is only ever fetched from TMDB/IGDB once per run, however
many users are watching it — this script groups by media_id first, then
fans the resulting push out to everyone who qualifies for it. A push
fires the moment an episode/release first reads as "already out" and
models.NotifiedRelease has no row yet for that exact
(user, source, media_id, release_key) — see that model's own docstring
for why PushLog's own "already sent today" dedup isn't fine-grained
enough here (one show can air weekly; each episode needs exactly one
push, not zero or unlimited). A person who already logged the episode
themselves (DiaryEntry.season/episode already at or past it) is skipped
outright — no reason to "notify" someone of something they've already
told this app they watched.

Nothing here waits for an "evening window" the way
send_scheduled_push.py's streak/memory pushes deliberately do — a new
episode/release is closer to this app's other immediate pushes (a
match, a friend's log) than to an end-of-day nudge.

    --dry-run   list who would be notified and about what; sends nothing
"""

import argparse
import asyncio
import logging
import os
import sys
from datetime import date

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.bi import Bi
from app import models, push  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.routers.calendar import _game_release_date, _tmdb_next_episode_cached  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("send_new_episode_push")


def _already_notified(db, user_id: str, source: str, media_id: str, release_key: str) -> bool:
    return (
        db.query(models.NotifiedRelease)
        .filter(
            models.NotifiedRelease.user_id == user_id,
            models.NotifiedRelease.source == source,
            models.NotifiedRelease.media_id == media_id,
            models.NotifiedRelease.release_key == release_key,
        )
        .first()
        is not None
    )


def _mark_notified(db, user_id: str, source: str, media_id: str, release_key: str) -> None:
    db.add(models.NotifiedRelease(
        user_id=user_id, source=source, media_id=media_id, release_key=release_key,
    ))
    db.commit()


def _group_by_media_id(entries: list) -> dict:
    grouped: dict[str, list] = {}
    for e in entries:
        grouped.setdefault(e.media_id, []).append(e)
    return grouped


async def send_new_episodes(db, dry_run: bool) -> int:
    entries = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.status == models.WatchStatus.watching,
            models.WatchlistEntry.media_type.in_([models.MediaType.series, models.MediaType.anime]),
            models.WatchlistEntry.source == "tmdb",
        )
        .all()
    )
    if not entries:
        return 0

    sent = 0
    today = date.today()
    for media_id, watchers in _group_by_media_id(entries).items():
        try:
            info = await _tmdb_next_episode_cached(db, media_id)
        except Exception as exc:  # noqa: BLE001 — one bad title shouldn't stop the whole run
            logger.warning("next_episode fetch failed for %s: %s", media_id, exc)
            continue
        if not info:
            continue
        last = info.get("last") or {}
        air_date = last.get("air_date")
        season, episode = last.get("season_number"), last.get("episode_number")
        if not air_date or season is None or episode is None:
            continue
        try:
            if date.fromisoformat(air_date) > today:
                continue  # not aired yet — nothing to push for this title this run
        except ValueError:
            continue
        release_key = f"s{season}e{episode}"

        for entry in watchers:
            diary = (
                db.query(models.DiaryEntry)
                .filter(
                    models.DiaryEntry.user_id == entry.user_id,
                    models.DiaryEntry.source == "tmdb",
                    models.DiaryEntry.media_id == media_id,
                )
                .first()
            )
            if diary and diary.season is not None and diary.episode is not None:
                if (diary.season, diary.episode) >= (season, episode):
                    continue  # already watched this far — not "news" to them
            if _already_notified(db, entry.user_id, "tmdb", media_id, release_key):
                continue
            title_name = entry.title_ru or entry.title_en or "что-то"
            title_name_en = entry.title_en or entry.title_ru or "something"
            if dry_run:
                logger.info("[dry-run] new episode -> user=%s %s %s", entry.user_id, title_name, release_key)
                sent += 1
                continue
            user = db.query(models.User).filter(models.User.id == entry.user_id).first()
            if user is None or user.deleted_at is not None:
                continue
            media_type_str = entry.media_type.value if hasattr(entry.media_type, "value") else entry.media_type
            n = push.push_service.send_to_user(
                db, user, push.PushCategory.NEW_EPISODES,
                title=Bi("Новая серия! 🎬", "A new episode! 🎬"),
                body=Bi(f"«{title_name}» — вышла {season} сезон {episode} серия",
                        f"“{title_name_en}” — season {season}, episode {episode} is out"),
                data={
                    "type": "new_episode", "media_id": media_id, "source": "tmdb",
                    "media_type": media_type_str, "title": title_name,
                    "season": season, "episode": episode,
                },
            )
            _mark_notified(db, entry.user_id, "tmdb", media_id, release_key)
            if n:
                sent += 1
    return sent


async def send_game_releases(db, dry_run: bool) -> int:
    entries = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.status.in_([models.WatchStatus.watch_later, models.WatchStatus.watching]),
            models.WatchlistEntry.media_type == models.MediaType.game,
            models.WatchlistEntry.source == "igdb",
        )
        .all()
    )
    if not entries:
        return 0

    sent = 0
    today = date.today()
    for media_id, watchers in _group_by_media_id(entries).items():
        try:
            release_date_str = await _game_release_date(db, media_id)
        except Exception as exc:  # noqa: BLE001
            logger.warning("release date fetch failed for %s: %s", media_id, exc)
            continue
        if not release_date_str:
            continue
        try:
            release_date = date.fromisoformat(release_date_str)
        except ValueError:
            continue
        if release_date > today:
            continue  # not out yet
        release_key = "release"

        for entry in watchers:
            if _already_notified(db, entry.user_id, "igdb", media_id, release_key):
                continue
            title_name = entry.title_ru or entry.title_en or "что-то"
            title_name_en = entry.title_en or entry.title_ru or "something"
            if dry_run:
                logger.info("[dry-run] game release -> user=%s %s", entry.user_id, title_name)
                sent += 1
                continue
            user = db.query(models.User).filter(models.User.id == entry.user_id).first()
            if user is None or user.deleted_at is not None:
                continue
            n = push.push_service.send_to_user(
                db, user, push.PushCategory.NEW_EPISODES,
                title=Bi("Игра вышла! 🎮", "The game is out! 🎮"),
                body=Bi(f"«{title_name}» уже можно поиграть",
                        f"“{title_name_en}” is out — time to play"),
                data={
                    "type": "new_episode", "media_id": media_id, "source": "igdb",
                    "media_type": "game", "title": title_name,
                },
            )
            _mark_notified(db, entry.user_id, "igdb", media_id, release_key)
            if n:
                sent += 1
    return sent


async def main_async(dry_run: bool) -> int:
    db = SessionLocal()
    try:
        episodes_sent = await send_new_episodes(db, dry_run)
        games_sent = await send_game_releases(db, dry_run)
        logger.info(
            "%snew episodes: %d, game releases: %d",
            "[dry-run] " if dry_run else "", episodes_sent, games_sent,
        )
        return 0
    finally:
        db.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    return asyncio.run(main_async(args.dry_run))


if __name__ == "__main__":
    raise SystemExit(main())
