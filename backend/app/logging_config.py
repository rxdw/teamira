"""Structured (JSON) logging, opt-in via settings.log_format="json" (see
config.py for why "text" — everything left exactly as uvicorn's own
defaults render it — stays the default).

Why this lives here and gets called from app/main.py rather than uvicorn's
own --log-config flag: this app is started as `uvicorn app.main:app` (see
Dockerfile), and uvicorn builds its Config — which is what runs its own
logging.config.dictConfig(LOGGING_CONFIG) — *before* it imports app.main
(Config.__init__ configures logging; Config.load(), which does the actual
`import_from_string("app.main:app")`, only happens later, when the server
starts serving). That ordering means whatever this module does at import
time inside app/main.py runs strictly after uvicorn's own logging setup,
and safely overrides it — no --log-config file to keep in sync with this
one, no risk of uvicorn's own dictConfig call clobbering this one instead
(it would, if the order were reversed).
"""

from __future__ import annotations

import datetime
import json
import logging
import traceback

from app.config import settings


class _JsonFormatter(logging.Formatter):
    """One JSON object per line. Deliberately not using python-json-logger
    or similar — the shape needed here (timestamp, level, logger, message,
    exception) is small enough that a dependency for it would be a worse
    trade than the ~20 lines below."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.datetime.fromtimestamp(
                record.created, tz=datetime.timezone.utc
            ).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # uvicorn's AccessFormatter stashes these on the record for its own
        # "%(client_addr)s ..." format string; carried through here too so
        # an access log line in JSON mode still has the request it's about,
        # not just a bare templated message.
        for attr in ("client_addr", "request_line", "status_code"):
            value = getattr(record, attr, None)
            if value is not None:
                payload[attr] = value
        if record.exc_info:
            payload["exception"] = "".join(traceback.format_exception(*record.exc_info))
        return json.dumps(payload, ensure_ascii=False)


def configure_logging() -> None:
    if settings.log_format != "json":
        return  # uvicorn's own defaults are left completely alone

    handler = logging.StreamHandler()
    handler.setFormatter(_JsonFormatter())

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)

    # uvicorn's own "uvicorn"/"uvicorn.access" loggers (unlike
    # "uvicorn.error", which has no handler of its own and already
    # propagates to "uvicorn" — see config.py's LOGGING_CONFIG) carry their
    # own handlers with propagate=False, specifically so this app's own
    # loggers and uvicorn's don't double up in the *default* text setup.
    # In JSON mode there's only one handler in the whole process (the one
    # just built above), so reusing it here — rather than leaving uvicorn's
    # own text-formatted handlers in place alongside it — is what makes
    # "json mode" actually mean every line, not just this app's own.
    for name in ("uvicorn", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers = [handler]
        logger.propagate = False
