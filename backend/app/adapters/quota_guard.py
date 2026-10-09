"""Daily request budget + temporary pause for a quota-limited, sometimes
unreachable third-party API (ПоискКино, Hardcover).

In process memory on purpose, not a DB table: the worst case of losing it
(a restart, or several workers each counting separately) is a few extra
requests, and each adapter's own handling of the API's 429/401/5xx answers
is the real backstop. Counts attempts, not successes — a failed call still
used quota. With N workers each counts on its own, so set the budget to
roughly limit/N.
"""

import time
from datetime import datetime, timezone
from typing import Callable


class QuotaGuard:
    def __init__(self, budget: Callable[[], int]) -> None:
        # A callable, not a number, so a settings change (or a test
        # monkeypatching settings) is picked up without rebuilding this.
        self._budget = budget
        self._day = None
        self._used = 0
        self._paused_until = 0.0

    def allow(self) -> bool:
        if time.monotonic() < self._paused_until:
            return False
        today = datetime.now(timezone.utc).date()
        if today != self._day:
            self._day = today
            self._used = 0
        return self._used < self._budget()

    def spend(self) -> None:
        self._used += 1

    def pause(self, seconds: float) -> None:
        self._paused_until = max(self._paused_until, time.monotonic() + seconds)

    def reset(self) -> None:  # tests
        self._day, self._used, self._paused_until = None, 0, 0.0
