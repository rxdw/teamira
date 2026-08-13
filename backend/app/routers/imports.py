"""
Bulk "bring your history over" endpoint — what the Settings -> import
screen and the onboarding import step both call. Deliberately source-agnostic
rather than a Letterboxd-specific integration: Letterboxd (and Trakt,
Serializd, IMDb list exports, ...) all export the same shape at heart — a
list of titles, sometimes with a year/date/rating attached — so one parser
that understands "a CSV with a title column" covers all of them without a
dedicated adapter per service. A person can also just type/paste a plain
list by hand, one title per line.

Two-step flow, same reasoning as the diary form itself (search, then log):
1. POST /import/preview — parse whatever was pasted and try to resolve
   each line to a real title via the same TMDB search used everywhere
   else in the app. Returns a match (or none) per line for the client to
   show and let the person drop bad matches — nothing is written yet.
2. POST /import/commit — the rows the person actually confirmed, each
   tagged watched or watch_later, get written for real: watched rows go
   through the exact same log_watched() the diary form itself uses;
   watch_later rows upsert a WatchlistEntry exactly like feed/react does.
"""
import csv
import io
import logging
import re
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.schemas import MediaItem
from app.adapters.tmdb import TmdbAdapter
from app.routers.diary import log_watched

logger = logging.getLogger("teamira.routers.imports")

router = APIRouter(prefix="/import", tags=["import"])
_tmdb = TmdbAdapter()

_MAX_ROWS = 500
_YEAR_IN_PARENS = re.compile(r"\((\d{4})\)\s*$")
_TITLE_COLUMNS = {"name", "title", "film"}
_DATE_COLUMNS = ("watched date", "date")


class ImportLine(BaseModel):
    raw: str
    title: str
    year: Optional[int] = None
    watched_at: Optional[str] = None
    rating: Optional[int] = None  # 1-10 hearts, only if the source carried its own rating


def _parse_csv(text: str) -> List[ImportLine]:
    reader = csv.DictReader(io.StringIO(text))
    lines: List[ImportLine] = []
    for row in reader:
        clean = {(k or "").strip().lower(): (v or "").strip() for k, v in row.items()}
        title = next((clean[c] for c in _TITLE_COLUMNS if clean.get(c)), None)
        if not title:
            continue

        year = None
        if clean.get("year"):
            try:
                year = int(clean["year"])
            except ValueError:
                pass

        watched_at = next((clean[c] for c in _DATE_COLUMNS if clean.get(c)), None)

        rating = None
        if clean.get("rating"):
            try:
                # Letterboxd stars are 0.5-5 in half-star steps — scale to
                # this app's 1-10 hearts (see schemas.DiaryEntryCreate.rating).
                rating = max(1, min(10, round(float(clean["rating"]) * 2)))
            except ValueError:
                pass

        lines.append(ImportLine(raw=title, title=title, year=year, watched_at=watched_at, rating=rating))
    return lines


def _parse_plain_text(text: str) -> List[ImportLine]:
    lines: List[ImportLine] = []
    for raw_line in text.splitlines():
        line = raw_line.strip().lstrip("-•*").strip()
        if not line:
            continue
        year = None
        match = _YEAR_IN_PARENS.search(line)
        if match:
            year = int(match.group(1))
            line = line[: match.start()].strip()
        lines.append(ImportLine(raw=raw_line.strip(), title=line, year=year))
    return lines


def _parse_pasted_text(text: str) -> tuple[List[ImportLine], str]:
    """Auto-detects a CSV export (Letterboxd's own "Name" column, or the
    "Title"/"Film" a couple of similar services use) vs. a plain
    one-title-per-line paste. `"Title (Year)"` on a plain-text line is
    read as a year hint the same way a CSV's own Year column is."""
    stripped = text.strip()
    if not stripped:
        return [], "text"

    first_line = stripped.splitlines()[0]
    header_cols = [c.strip().strip('"').lower() for c in first_line.split(",")]
    looks_like_csv = len(header_cols) > 1 and any(c in _TITLE_COLUMNS for c in header_cols)

    if looks_like_csv:
        return _parse_csv(stripped), "csv"
    return _parse_plain_text(stripped), "text"


def _best_match(
    year: Optional[int], candidates: List[MediaItem]
) -> tuple[Optional[MediaItem], List[MediaItem]]:
    if not candidates:
        return None, []
    if year is not None:
        same_year = [c for c in candidates if c.year == year]
        if same_year:
            rest = same_year[1:] + [c for c in candidates if c not in same_year]
            return same_year[0], rest[:4]
    return candidates[0], candidates[1:5]


class ImportPreviewRequest(BaseModel):
    text: str


class ImportRowOut(BaseModel):
    raw: str
    matched: Optional[MediaItem] = None
    alternates: List[MediaItem] = Field(default_factory=list)
    year: Optional[int] = None
    watched_at: Optional[str] = None
    rating: Optional[int] = None


class ImportPreviewOut(BaseModel):
    rows: List[ImportRowOut]
    source_detected: str  # "csv" | "text"


@router.post("/preview", response_model=ImportPreviewOut)
async def preview_import(
    payload: ImportPreviewRequest,
    current_user: models.User = Depends(get_current_user),
):
    lines, detected = _parse_pasted_text(payload.text)
    if not lines:
        raise HTTPException(
            status_code=400,
            detail="Nothing to import — paste one title per line, or a CSV export",
        )
    if len(lines) > _MAX_ROWS:
        raise HTTPException(
            status_code=400,
            detail=f"That's a lot at once — try {_MAX_ROWS} titles or fewer per import",
        )

    rows: List[ImportRowOut] = []
    for line in lines:
        candidates, _ = await _tmdb.catalog_search(line.title)
        matched, alternates = _best_match(line.year, candidates)
        rows.append(ImportRowOut(
            raw=line.raw,
            matched=matched,
            alternates=alternates,
            year=line.year,
            watched_at=line.watched_at,
            rating=line.rating,
        ))
    return ImportPreviewOut(rows=rows, source_detected=detected)


class ImportCommitRow(BaseModel):
    item: MediaItem
    status: str  # "watched" | "watch_later" | "watching"
    watched_at: Optional[str] = None
    rating: Optional[int] = Field(default=None, ge=1, le=10)


class ImportCommitRequest(BaseModel):
    rows: List[ImportCommitRow]


class ImportCommitOut(BaseModel):
    watched_count: int
    watch_later_count: int


def _parse_watched_at(raw: Optional[str]) -> datetime:
    if not raw:
        return datetime.utcnow()
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(raw, fmt)
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(raw)
    except ValueError:
        return datetime.utcnow()


@router.post("/commit", response_model=ImportCommitOut)
def commit_import(
    payload: ImportCommitRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not payload.rows:
        raise HTTPException(status_code=400, detail="Nothing to import")
    if len(payload.rows) > _MAX_ROWS:
        raise HTTPException(
            status_code=400,
            detail=f"That's a lot at once — try {_MAX_ROWS} titles or fewer per import",
        )

    watched_count = 0
    watch_later_count = 0

    for row in payload.rows:
        if row.status == "watched":
            log_watched(
                db,
                current_user.id,
                row.item,
                watched_at=_parse_watched_at(row.watched_at),
                rating=row.rating,
            )
            watched_count += 1
        else:
            # "watch_later" or "watching" — same upsert, different resting
            # status. "watching" only ever arrives from "your sources"
            # (routers/sources.py) — a playlist/channel someone's partway
            # through, marked so by hand on the review screen rather than
            # derived from episode progress the way a series' "watching"
            # normally is (there's no episode catalog for a YouTube/Twitch
            # source to log progress against).
            target_status = (
                models.WatchStatus.watching
                if row.status == "watching"
                else models.WatchStatus.watch_later
            )
            entry = (
                db.query(models.WatchlistEntry)
                .filter(
                    models.WatchlistEntry.user_id == current_user.id,
                    models.WatchlistEntry.media_id == row.item.id,
                    models.WatchlistEntry.source == row.item.source,
                )
                .first()
            )
            if entry is None:
                db.add(models.WatchlistEntry(
                    user_id=current_user.id,
                    media_id=row.item.id,
                    media_type=row.item.media_type,
                    source=row.item.source,
                    title_ru=row.item.title.ru,
                    title_en=row.item.title.en,
                    poster_url=row.item.poster_url,
                    backdrop_url=row.item.backdrop_url,
                    year=row.item.year,
                    genres=row.item.genres,
                    rating=row.item.rating,
                    runtime_minutes=row.item.runtime_minutes,
                    status=target_status,
                ))
            else:
                entry.status = target_status
            watch_later_count += 1

    db.commit()
    return ImportCommitOut(watched_count=watched_count, watch_later_count=watch_later_count)
