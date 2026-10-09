"""One rule for every optional third-party source that has a quota and can
be unreachable (Kinopoisk, Hardcover):

    fresh cached copy            -> use it
    else fetch                   -> cache it (a real answer, including
                                    "not found", is cached)
    fetch says "unavailable"     -> NOT cached; serve the last known copy
                                    if there is one, otherwise None
    anything else goes wrong     -> None (a cache/DB hiccup must never
                                    break the screen asking for this)

`cache.cached_dynamic` stores whatever fetch returns and stores nothing
when fetch raises, which is exactly what keeps a bad minute from being
remembered for weeks. Expired rows are not deleted, only ignored by
cached_dynamic, so `cache.get_dynamic_stale` can still hand back the old
copy when a refresh isn't possible.
"""

import logging
from datetime import timedelta
from typing import Awaitable, Callable, Optional, Type, TypeVar

from pydantic import BaseModel

from app import cache

M = TypeVar("M", bound=BaseModel)


async def load(
    key: str,
    fetch: Callable[[], Awaitable[BaseModel]],
    ttl: timedelta,
    model: Type[M],
    unavailable: Type[Exception],
    logger: logging.Logger,
    label: str,
) -> Optional[M]:
    try:
        raw = await cache.cached_dynamic(None, key, fetch, ttl=ttl)
    except unavailable as exc:
        raw = cache.get_dynamic_stale(None, key)
        if raw is None:
            logger.info("%s skipped [%s]: %s", label, key, exc)
            return None
        logger.info("%s refresh failed [%s]: %s — serving the previous copy", label, key, exc)
    except Exception:  # noqa: BLE001
        logger.warning("%s lookup failed [%s]", label, key, exc_info=True)
        return None
    return model.model_validate_json(raw)
