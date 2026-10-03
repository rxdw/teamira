from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

from app.config import settings

# pool_size/max_overflow bumped well past SQLAlchemy's defaults (5 + 10 =
# 15 total). get_db() below hands out one connection per request for the
# *entire* request lifetime — including whatever slow, awaited I/O the
# route does in between its DB reads/writes. That's normally invisible,
# but onboarding's poster-deck loader (_PosterDeckLoader in the mobile
# app) used to fire ~26 GET /media/search requests concurrently the
# instant it opens, and that endpoint used to hold its `Depends(get_db)`
# session open across the whole TMDB/Shikimori/Google-Books fan-out in
# between. With only 15 connections available, the rest queued on the
# pool (default pool_timeout=30s) well past the mobile client's own 12s
# request timeout, so a chunk of the deck would silently time out.
#
# Two separate fixes went in for that, not just this pool bump: (1) this
# pool_size/max_overflow increase, a blunt "more headroom" mitigation,
# and (2) GET /media/search itself no longer takes a `Depends(get_db)`
# at all — see routers/media.py::search_media's own docstring — its
# cache reads/writes each open and close their own short-lived session
# instead, so the endpoint doesn't hold a pooled connection across the
# fan-out anymore regardless of how many fire at once. This bump stays
# as headroom for whatever the *next* fan-out-shaped endpoint turns out
# to be — see this file's own note on `get_db` below for the general
# shape of the problem and how to sidestep it the same way.
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=30,
    max_overflow=20,
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    """The usual way to get a session — `db: Session = Depends(get_db)`
    checks one out from the pool for the entire request, closed once the
    route returns. Fine for most routes (a handful of quick queries, no
    slow awaited I/O in between). For a route whose only DB use is
    through app/cache.py's get_static_title/set_static_title/
    cached_dynamic/etc AND that also does slow upstream I/O (an external
    API fan-out) in between — same shape as the old GET /media/search,
    see routers/media.py::search_media's own docstring — skip this
    dependency entirely and call those cache functions with `db=None`
    instead; each one opens and closes its own short-lived session right
    around the actual query, not the whole request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
