from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

from app.config import settings

# pool_size/max_overflow bumped well past SQLAlchemy's defaults (5 + 10 =
# 15 total). get_db() below hands out one connection per request for the
# *entire* request lifetime — including whatever slow, awaited I/O the
# route does in between its DB reads/writes (e.g. GET /media/search
# holding its session open across the TMDB round trip in
# cache.cached_dynamic). That's normally invisible, but onboarding's
# poster-deck loader (_PosterDeckLoader in the mobile app) fires ~26
# /media/search requests concurrently the instant it opens. With only 15
# connections available, the rest queued on the pool (default
# pool_timeout=30s) well past the mobile client's own 12s request
# timeout, so a chunk of the deck would silently time out — every other
# screen in the app never bursts anywhere near this many concurrent
# requests, which is why the symptom only ever showed up here.
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=30,
    max_overflow=20,
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
